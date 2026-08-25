# M2's second concrete engine: a real-time-steppable multi-machine classical
# (network swing) model, built on NetworkDynamics (docs/plans/m2-plan.md §3).
#
# THE TIER. Each machine is a constant-magnitude voltage `E′` **at its bus** whose
# angle is the rotor angle, so its state is `(δ, ω)` and branch coupling is the
# closed form `K_ij = E′ᵢE′ⱼ/X_ij` (the D8 correction; see the tier note at the
# head of `model/network_model.jl`). No bus voltage is an unknown, so the whole
# system stays a pure ODE and `Tsit5` still applies. Per machine, on `S_base`:
#
#     dδᵢ/dt = ω₀·ωᵢ
#     dωᵢ/dt = (Pmᵢ − Σⱼ K_ij·sin(δᵢ−δⱼ) − Dᵢ·ωᵢ) / (2Hᵢ)
#
# `ωᵢ` is a **per-unit speed deviation of one machine** and is NOT M1's aggregate
# `Δω`. The system-wide quantity is the inertia-weighted mean
# `ω_coi = Σ Hᵢωᵢ / Σ Hᵢ`, reported separately and under its own name — conflating
# the two is the silent error `m2-plan.md` warns about.
#
# THE SIGN CONVENTION, spelled out, because a flipped sign still oscillates, still
# settles, and still has a nadir (validation V2 is what catches it). The edge
# output is `K·sin(δ_src − δ_dst)` wrapped in `AntiSymmetric`, so the *destination*
# vertex sees `+K·sin(δ_src−δ_dst)` and the *source* vertex sees the negative of
# it. Summed at vertex i that gives `esumᵢ = −Σⱼ K_ij·sin(δᵢ−δⱼ)`, i.e. minus the
# electrical power flowing **out** of bus i — which is why the vertex RHS *adds*
# `esum` to `Pm`. At equilibrium `Pmᵢ = Σⱼ K_ij·sin(δᵢ−δⱼ)`: generation equals
# export, which is exactly what V2 asserts.
#
# THE EDGE-ORDERING HAZARD, and why it needs its own test. `Graphs.SimpleGraph`
# iterates its edges in sorted `(src, dst)` order, **not** in the order branches
# were added, and NetworkDynamics indexes edge parameters by position in
# `Graphs.edges(g)`. For `three_machine_ring` the branches [L12, L23, L31] map to
# graph edges [1, 3, 2] — so "branch k ↦ edge k" would give two of the three lines
# the wrong coupling. The defence is structural: the edge parameters are filled in
# a **single pass over the graph's own edge list**, looking each branch up by its
# bus pair, so there is no index that could be permuted. `branch_to_edge` is kept
# only as the reverse map `TripLine` will need (step 5) and is asserted to be a
# permutation. This matters because **V2 cannot catch a mis-mapping**:
# `find_fixpoint` happily converges on whatever self-consistent (wrong) network it
# is handed, and the electrical power recomputed from the same wrong couplings
# still equals `Pm`. Only a direct assertion on the mapping bites.
#
# NO EQUILIBRIUM AFTER A **GENERATOR** TRIP — do not "fix" the drift.
# `NetworkModel` enforces `Σ P0 = 0` at construction, but losing a machine
# deliberately breaks it: the classical tier has no governors, so the remaining
# machines cannot make up the loss. The system therefore has **no fixpoint at all**
# afterwards. Speed falls until damping balances the shortfall
# (`ω_coi → ΣPm_remaining / ΣD`) and, because that limit is non-zero, every `δ` then
# grows without bound at a common rate. That is the physics of this tier, not a bug
# and not an integration failure: angle *differences* still settle. Consequences:
# never call `find_fixpoint` on a post-generator-trip state (it cannot converge),
# and never assert on an absolute angle.
#
# A **LINE** TRIP IS THE OTHER CASE, and the sharper test. It changes no `Pm`, so
# `Σ Pm = 0` still holds and the surviving network *does* have an equilibrium: every
# machine returns to `ω = 0` and the angle differences move to a new steady state in
# which the remaining branches carry what the lost one used to. On a radial pair
# that steady state is a closed form (`asin` of the flow over the coupling), which
# is what step 5's validation asserts. The exception is a trip that **splits** the
# network: each island then holds its own frequency and the single `ω_coi` read-out
# is a weighted average of two unrelated numbers — physically real, deliberately not
# refused here, and the reason `NetworkModel` refuses to be *constructed*
# disconnected.

const _SWING_DT0 = 0.02   # default real-time step (s), matching M1's

# WHY A SEPARATE EVENT LOG AND NOT AN EXTRA RECORDER CHANNEL (step 7's first
# decision, docs/plans/m2-tasks.md). The trajectory carries `δ_*`, `ω_*` and the
# aggregates, and from those a *generator* trip is partly reconstructible (a
# machine's speed goes flat, its inertia leaves the aggregate) while a *line* trip
# leaves no trace at all: play a run back and nothing says which line opened, or
# when. Two reasons the fix is a log rather than a channel:
#
#   1. A trip is a single-sample spike, and decimation is precisely the operation
#      that deletes those. The recorder halves its buffer by keeping every other
#      retained sample, so a marker that is non-zero in one sample has a 50 %
#      chance of vanishing at each halving — the one datum whose *exact instant*
#      matters would be the first thing thrown away.
#   2. A channel is a `Float64`. "Which line?" is a pair of bus names, and encoding
#      symbols as numbers to fit the buffer is a code nothing would decode.
#
# So events are logged where they are *applied* — inside `inject!`, timestamped
# from the integrator's own clock. Deliberately not in the UI's click handler: a
# scripted run (`smoke_render`, the tests, any headless driver) never clicks, and a
# log that only exists when a human is watching is not a record of the run.
#
# Bounded, like everything else here: events are user clicks, so the cap is far
# above any real session, but a scripted driver pushing events in a loop must not
# turn this into the one vector in the engine that grows forever. At the cap the
# log stops appending and counts the drops (`n_events_dropped`) — keeping the
# *earliest* events, the same "the start is what matters" choice the recorder makes
# when it decimates rather than rolling.
const _EVENT_LOG_CAP = 256

"""
    EngineEvent(t, kind, a, b)

One perturbation, as applied — the record a played-back trajectory cannot supply.

  - `t`    — simulation time at which the engine applied it (the integrator's own
             clock, read inside `inject!`; never a wall clock).
  - `kind` — `:trip_generator` or `:trip_line`.
  - `a`, `b` — what it hit: the machine id and `Symbol("")` for a generator trip,
             the two bus names for a line trip.

Only events that actually *changed* something are logged: re-tripping an already
offline machine is a no-op in `inject!` and produces no entry, so the log is a
record of the run rather than of the clicks.
"""
struct EngineEvent
    t::Float64
    kind::Symbol
    a::Symbol
    b::Symbol
end

"""
    describe_event(ev::EngineEvent) -> String

One-line label for an event — what a plot marker or a status line shows. Lives
here rather than in `ui/` so both a window and a headless report name an event the
same way.
"""
describe_event(ev::EngineEvent) =
    ev.kind === :trip_generator ? string("trip ", ev.a) :
    ev.kind === :trip_line      ? string("trip line ", ev.a, "–", ev.b) :
                                  string(ev.kind, " ", ev.a, " ", ev.b)

"""
    swing_vertex!(dv, v, esum, p, t)

One machine's RHS. State `v = (δ, ω)` — rotor angle (rad) and per-unit speed
deviation. Parameters `p = (Pm, H, D, ω₀)`, all on the system base.

`ω₀` rides in the parameter vector rather than being captured in a closure so that
every model compiles to the *same* `Network` type: a closure over `ω₀` would make
each system its own anonymous function type and force a recompile per model.
"""
function swing_vertex!(dv, v, esum, p, t)
    δ, ω = v[1], v[2]
    Pm, H, D, ω₀ = p[1], p[2], p[3], p[4]
    dv[1] = ω₀ * ω
    # `esum` is MINUS the electrical power exported from this bus — see the sign
    # convention note in the file header — hence `+ esum[1]`, not `-`.
    dv[2] = (Pm + esum[1] - D * ω) / (2 * H)
    return nothing
end

"""
    swing_edge!(e, v_src, v_dst, p, t)

One branch's transferred power `P = K·sin(δ_src − δ_dst)`, wrapped by the caller in
`AntiSymmetric` so the two ends see equal and opposite injections (lossless line).
"""
swing_edge!(e, v_src, v_dst, p, t) = (e[1] = p[1] * sin(v_src[1] - v_dst[1]); nothing)

"""
    SwingEngine{NW,I,R} <: SimulationEngine

Real-time multi-machine classical engine. The three type parameters are the
concrete NetworkDynamics `Network`, the concrete integrator, and the concrete
`TrajectoryRecorder` — pinned so every field is concretely typed (SPEC §4) even
though the recorder's channel count depends on the number of machines. Built
through `init!`/the constructor below, never by filling fields by hand.

Fields worth naming: the canonical `model`; the compiled `nw`; the live `online`
machine set and the live `lines_online` branch set (indices into
`model.branches`, tracked explicitly rather than inferred from "is this coupling
zero?" — a generator trip also zeroes its incident couplings, and a line that is
still in service beside a dead machine is not a tripped line); the **shared**
parameter vector (`eng.params === eng.integrator.p`,
the M1 pattern that lets an event change the system without disturbing the
continuous state — inherited here from NetworkDynamics rather than assumed, and
asserted in `test/`); flat index vectors into the state and parameter arrays
(`δ_idx`/`ω_idx`/`Pm_pidx`/`K_pidx`), resolved once through NetworkDynamics'
symbolic interface so nothing here assumes a memory layout; `branch_to_edge` and
`incident`, the graph bookkeeping the header describes; `branch_of_buses`, the
bus-pair index behind `is_online`; the pre-trip inertias `H` (kept for step 6's
`coi_model`, never mutated) beside the live COI weights `w` (a machine's inertia
while it is online, zero once tripped) and their sum; the bounded `traj`; the
bounded `log` of applied events with its `n_dropped` counter; and the running
`nadir` of the COI frequency.
"""
mutable struct SwingEngine{NW,I,R} <: SimulationEngine
    model::NetworkModel
    nw::NW
    online::Set{Symbol}
    lines_online::Set{Int}
    params::Vector{Float64}
    dt::Float64
    integrator::I
    f0::Float64
    ω₀::Float64
    ids::Vector{Symbol}
    δ_idx::Vector{Int}
    ω_idx::Vector{Int}
    Pm_pidx::Vector{Int}
    K_pidx::Vector{Int}
    branch_to_edge::Vector{Int}
    incident::Vector{Vector{Int}}
    branch_of_buses::Dict{Tuple{Symbol,Symbol},Int}
    H::Vector{Float64}
    w::Vector{Float64}
    Σw::Float64
    traj::R
    sample::Vector{Float64}
    log::Vector{EngineEvent}
    n_dropped::Int
    nadir::Float64
end

"""
    SwingEngine(net::NetworkModel; t0=0.0, dt=0.02, solver=Tsit5(), capacity=200_000)

Compile `net` into a NetworkDynamics `Network`, place it on its steady state, and
return a ready-to-step engine.

The steady state comes from `find_fixpoint` — no hand-rolled power flow (D6,
SPEC §8). Flat start is an *acceptance criterion*, not a nicety: M1's state was
deviations and so began at the origin by construction, but M2 carries absolute
angles, and a model placed off-equilibrium rings from `t = 0` with a plausible
oscillation that is pure initialization artifact. Validation V1 asserts it.

Note that `find_fixpoint` picks an arbitrary **gauge**: shifting every `δ` by the
same constant is still an equilibrium, so the absolute angles it returns are
meaningless and only their differences are not. Tests must assert differences.
"""
function SwingEngine(net::NetworkModel; t0::Real = 0.0,
                     dt::Real = _SWING_DT0,
                     solver = OrdinaryDiffEq.Tsit5(),
                     capacity::Integer = _TRAJ_CAPACITY)
    ma = machine_arrays(net)
    ba = branch_arrays(net)
    nb = length(net.buses)

    # The same graph the model validated itself against (one edge per bus pair,
    # connected — both already enforced by the `NetworkModel` constructor).
    g = Graphs.SimpleGraph(nb)
    for e in eachindex(ba.src)
        Graphs.add_edge!(g, ba.src[e], ba.dst[e])
    end
    ne = Graphs.ne(g)

    vertex = NetworkDynamics.VertexModel(f = swing_vertex!,
                                         g = NetworkDynamics.StateMask(1:1),
                                         sym = [:δ, :ω], psym = [:Pm, :H, :D, :ω₀],
                                         name = :machine)
    edge = NetworkDynamics.EdgeModel(g = NetworkDynamics.AntiSymmetric(swing_edge!),
                                     outsym = [:P], psym = [:K], name = :branch)
    nw = NetworkDynamics.Network(g, [vertex for _ in 1:nb], [edge for _ in 1:ne])

    # --- parameters, and the edge mapping that cannot be permuted ---------------
    # Both dictionaries are keyed by the *unordered* vertex pair, and the fill loop
    # walks the graph's own edge list, so an edge takes the coupling of whichever
    # branch connects those two buses. There is no positional correspondence to get
    # wrong. (Orientation is harmless either way: K is symmetric and K·sin is
    # antisymmetric, so flipping an edge's ends flips the sign of a quantity that
    # `AntiSymmetric` was going to flip anyway.)
    K_of_pair = Dict{Tuple{Int,Int},Float64}()
    branch_of_pair = Dict{Tuple{Int,Int},Int}()
    for e in eachindex(ba.K)
        key = minmax(ba.src[e], ba.dst[e])
        K_of_pair[key] = ba.K[e]
        branch_of_pair[key] = e
    end

    s = NetworkDynamics.NWState(nw)
    ω₀ = 2π * net.f0
    for i in 1:nb
        s.v[i, :δ] = 0.0                 # only the fixpoint solver's starting guess
        s.v[i, :ω] = 0.0
        s.p.v[i, :Pm] = ma.Pm[i]
        s.p.v[i, :H]  = ma.H[i]
        s.p.v[i, :D]  = ma.D[i]
        s.p.v[i, :ω₀] = ω₀
    end

    branch_to_edge = Vector{Int}(undef, length(ba.K))
    incident = [Int[] for _ in 1:nb]
    for (ei, ed) in enumerate(Graphs.edges(g))
        i, j = Graphs.src(ed), Graphs.dst(ed)
        key = minmax(i, j)
        s.p.e[ei, :K] = K_of_pair[key]
        branch_to_edge[branch_of_pair[key]] = ei
        push!(incident[i], ei)
        push!(incident[j], ei)
    end

    # --- steady state, then the integrator -------------------------------------
    fp = NetworkDynamics.find_fixpoint(nw, s)
    u0 = collect(NetworkDynamics.uflat(fp))
    p0 = collect(NetworkDynamics.pflat(fp))
    t0f = Float64(t0)
    # Same integrator discipline as M1 (docs/SPEC.md §6): a large *finite* tspan
    # because we drive it with `step!(integ, dt, true)` and never reach the end,
    # an explicit seed `dt`, and the integrator's own saved solution switched off —
    # we keep our own bounded history, and its would grow without bound on a long
    # live run. There is deliberately **no `isoutofdomain` guard**: M1 has one to
    # absorb headroom overshoot, but nothing here is bounded — post-trip the angles
    # drift forever by design (see the header), so a copied state guard would fire
    # spuriously and collapse the step size.
    prob = OrdinaryDiffEq.ODEProblem(nw, u0, (t0f, t0f + 1.0e6), p0)
    integrator = OrdinaryDiffEq.init(prob, solver; dt = Float64(dt),
                                     save_everystep = false, dense = false)

    # Flat indices into the state and parameter vectors, resolved once through
    # NetworkDynamics' symbolic interface. Nothing in this engine assumes a stride
    # or an ordering; `test/` asserts these round-trip against a symbolic read, so
    # if the upstream layout ever moves, that test says so instead of the physics
    # going quietly wrong.
    SII = NetworkDynamics.SII
    δ_idx   = [SII.variable_index(nw, NetworkDynamics.VIndex(i, :δ)) for i in 1:nb]
    ω_idx   = [SII.variable_index(nw, NetworkDynamics.VIndex(i, :ω)) for i in 1:nb]
    Pm_pidx = [SII.parameter_index(nw, NetworkDynamics.VPIndex(i, :Pm)) for i in 1:nb]
    K_pidx  = [SII.parameter_index(nw, NetworkDynamics.EPIndex(e, :K)) for e in 1:ne]

    ids = Symbol[m.id for m in net.machines]     # bus order, by construction
    # `H` is the pre-trip baseline, kept unmutated; `w` is the live COI weight
    # (a machine's inertia while online, zero once tripped). Nothing in M2a reads
    # `H` yet — step 6's `coi_model` needs the original inertias to compile the
    # aggregate model, and recovering them from `w` after a trip is impossible.
    H = copy(ma.H)
    w = copy(ma.H)

    # Bus pair ⇒ branch index, so "which line is this?" is a hash lookup rather
    # than a scan over `model.branches`. It exists because a UI asks it once per
    # line per frame (`is_online`), which puts it in the redraw path; the key is
    # the *unordered* pair, matching `TripLine`'s "either order" contract.
    branch_of_buses = Dict{Tuple{Symbol,Symbol},Int}(
        _bus_pair(br.from, br.to) => b for (b, br) in pairs(net.branches))

    # One channel per machine angle, one per machine speed, then the two
    # aggregates. `:t` is prepended by the recorder itself (engines/recorder.jl).
    #
    # `δ_coi` is here because the channel set of a running engine cannot be
    # changed later (step 7's decision) and because the *individual* angles are
    # gauge-arbitrary: only differences mean anything, and the difference a reader
    # wants is against the aggregate. It could in principle be recomputed from the
    # per-machine angles afterwards — but only by a consumer that also reproduces
    # the live COI weights, which change at every generator trip. One channel is
    # cheaper than making every consumer re-derive that bookkeeping correctly.
    channels = vcat([Symbol("δ_", id) for id in ids],
                    [Symbol("ω_", id) for id in ids], [:δ_coi, :f_coi])
    traj = TrajectoryRecorder(channels...; capacity = capacity)

    eng = SwingEngine(net, nw, Set(ids), Set(eachindex(net.branches)),
                      integrator.p, Float64(dt), integrator,
                      net.f0, ω₀, ids, δ_idx, ω_idx, Pm_pidx, K_pidx,
                      branch_to_edge, incident, branch_of_buses, H, w, sum(w), traj,
                      Vector{Float64}(undef, length(channels)),
                      EngineEvent[], 0, net.f0)
    _record!(eng)                                 # seed the pre-disturbance point
    return eng
end

"""
    init!(SwingEngine, net::NetworkModel; t0=0.0, dt=0.02, solver=Tsit5(), capacity=200_000)

Interface entry point. Dispatches on the engine **type** and returns a freshly
built, fully-typed engine — the same construction-order resolution M1 uses: the
struct is parametric on types that only exist once the network and integrator do,
so there is no half-built engine to mutate in place. See `interface.jl`.
"""
init!(::Type{SwingEngine}, net::NetworkModel; kwargs...) = SwingEngine(net; kwargs...)

# Inertia-weighted mean of one per-machine quantity over the machines still
# online. `w` is zero for a tripped machine, so its state keeps integrating
# harmlessly without polluting the aggregate read-out. With everything tripped
# there is no weighted mean to report and the result is `NaN` — the honest answer,
# and one that plotting skips rather than drawing a fake zero.
#
# ONE helper for both aggregates, because they are the same weighted mean over the
# same live weights: a second copy is how `ω_coi` and `δ_coi` would come to
# disagree about which machines count.
@inline function _coi(eng::SwingEngine, u, idx::Vector{Int})
    eng.Σw > 0 || return NaN
    acc = 0.0
    @inbounds for i in eachindex(eng.w)
        acc += eng.w[i] * u[idx[i]]
    end
    return acc / eng.Σw
end

@inline _ω_coi(eng::SwingEngine, u) = _coi(eng, u, eng.ω_idx)

# The aggregate ANGLE — a plain linear mean, deliberately not a circular one.
# `δ` here is the *unwrapped* rotor angle NetworkDynamics integrates, which after a
# generator trip grows without bound by design (see the header); wrapping it into
# `(-π, π]` to take a circular mean would put an artificial sawtooth into the one
# reference the traces are drawn against.
@inline _δ_coi(eng::SwingEngine, u) = _coi(eng, u, eng.δ_idx)

"""
    current_state(eng::SwingEngine) -> (; t, δ, ω, δ_coi, ω_coi, f_coi)

Named state at "now". Pure read of the integrator — no stepping.

  - `δ`     — per-machine rotor angles (rad), in bus order. **Gauge-dependent**:
              only differences are meaningful (see the constructor's note).
  - `ω`     — per-machine per-unit speed deviations, in bus order. One machine's
              deviation; *not* M1's aggregate `Δω`.
  - `δ_coi` — the inertia-weighted mean of `δ` over online machines (rad). Carries
              the same arbitrary gauge as `δ` itself, which is exactly the point:
              `δ[i] - δ_coi` is gauge-free and is the angle worth plotting.
  - `ω_coi` — the inertia-weighted mean of `ω` over online machines (pu).
  - `f_coi` — that same aggregate in engineering units, `f0·(1 + ω_coi)` (Hz).
              The system frequency, and the quantity comparable to M1's `f`.

`δ` and `ω` are freshly allocated copies, so a caller may keep them; the three
scalars are the cheap read for a live indicator.
"""
function current_state(eng::SwingEngine)
    u = eng.integrator.u
    ω_coi = _ω_coi(eng, u)
    return (t = eng.integrator.t, δ = u[eng.δ_idx], ω = u[eng.ω_idx],
            δ_coi = _δ_coi(eng, u), ω_coi = ω_coi, f_coi = eng.f0 * (1 + ω_coi))
end

# Append the current state to the bounded trajectory and update the running nadir.
#
# Reads the flat state directly through the index vectors and fills a reusable
# scratch buffer, so the per-step path creates no temporaries — `current_state`
# builds fresh vectors and is the read-out API, deliberately not used by this loop.
# (The recorder's own `push!` still reallocates when a channel outgrows its
# capacity, amortised; "no temporaries" is the claim, not "no allocation ever".)
#
# As in M1, the nadir is tracked HERE, incrementally, and never read back out of
# the trajectory: the recorder decimates once full, so the lowest retained sample
# is not the lowest that occurred (see engines/recorder.jl).
function _record!(eng::SwingEngine)
    u = eng.integrator.u
    n = length(eng.ids)
    @inbounds for i in 1:n
        eng.sample[i]     = u[eng.δ_idx[i]]
        eng.sample[n + i] = u[eng.ω_idx[i]]
    end
    f_coi = eng.f0 * (1 + _ω_coi(eng, u))
    eng.sample[2n + 1] = _δ_coi(eng, u)
    eng.sample[2n + 2] = f_coi
    record!(eng.traj, eng.integrator.t, eng.sample)
    f_coi < eng.nadir && (eng.nadir = f_coi)
    return nothing
end

"""
    step!(eng::SwingEngine, dt=eng.dt) -> (; t, δ, ω, ω_coi, f_coi)

Advance by exactly `dt`, record the trajectory point, and return the new state.
Extends `CommonSolve.step!`, sharing one generic with the integrator's own
`step!(integrator, dt, true)`.
"""
function step!(eng::SwingEngine, dt::Real = eng.dt)
    step!(eng.integrator, Float64(dt), true)
    # Fail loud, not silent: a failed integration leaves `step!` a no-op that would
    # otherwise flatline the trajectory with no indication anything went wrong.
    if !SciMLBase.successful_retcode(eng.integrator.sol.retcode)
        error("SwingEngine integration failed: retcode = ",
              eng.integrator.sol.retcode, " at t = ", eng.integrator.t)
    end
    _record!(eng)
    return current_state(eng)
end

"""
    state_series(eng::SwingEngine) -> NamedTuple

The recorded trajectory as `(; t, δ_<id>..., ω_<id>..., δ_coi, f_coi)` — one
channel per machine angle, one per machine speed, then the aggregate angle (rad,
same gauge as the per-machine angles) and the aggregate frequency in Hz.

**It records no events.** Nothing in these channels says a line opened, and a
single-sample marker is exactly what decimation deletes — `event_log(eng)` is
where applied perturbations live, with their exact instants (see the note at the
head of this file).

**Bounded, not complete**, exactly as for M1: once the recorder fills it decimates,
so late in a long run the samples are evenly spaced but coarser than `dt`. Use the
returned `t` rather than an assumed step, and do not derive exact extrema from
these vectors (`eng.nadir` is the running one).

Note that this shape differs from `FrequencyResponseEngine`'s fixed
`(; t, f, RoCoF, ΔPm, tripped_mw)`. Both satisfy "a `NamedTuple` of equal-length
series keyed by name", which is the contract `interface.jl` actually states, and a
consumer that reads channels by name works against either; a consumer that assumes
a *particular* set of channels does not. See the conformance finding in
`docs/plans/m2-context.md`.
"""
state_series(eng::SwingEngine) = series(eng.traj)

"""
    timestep(eng::SwingEngine) -> Float64

The engine's own real-time step (s), so the orchestration loop never hard-codes a
cadence (see `engines/interface.jl`).
"""
timestep(eng::SwingEngine) = eng.dt

"""
    machine_ids(eng::SwingEngine) -> Vector{Symbol}

Machine ids in bus order — the order of `current_state`'s `δ`/`ω` vectors and the
order the `state_series` channels are named in. An accessor rather than a field
read so `ui/` never reaches into engine internals (SPEC §3.1); the same reason
`system_inertia`/`is_online` exist for M1.
"""
machine_ids(eng::SwingEngine) = copy(eng.ids)

"""
    event_log(eng::SwingEngine) -> Vector{EngineEvent}

Every perturbation the engine has actually applied, in order, each with the
simulation time it landed at. A copy, so a caller may keep it.

This is the record the trajectory cannot hold (see the head of this file): a line
trip changes no channel that survives decimation, so without this a played-back
run cannot say which line opened or when.

Bounded at $(_EVENT_LOG_CAP) entries — far above any interactive session, and a
scripted driver that exceeds it keeps the earliest events while
`n_events_dropped` counts the rest.
"""
event_log(eng::SwingEngine) = copy(eng.log)

"""
    n_events(eng::SwingEngine) -> Int

How many events the log currently holds. `event_log` copies, and a UI has to ask
"has anything happened since the last frame?" on every frame — so the cheap
question gets its own answer rather than being asked by copying the vector and
measuring it, the same reason the bus-pair lookup is indexed.
"""
n_events(eng::SwingEngine) = length(eng.log)

"""
    n_events_dropped(eng::SwingEngine) -> Int

How many applied events the bounded log had to discard (`0` in any real session).
Reported rather than silent: a truncated log that does not say it is truncated
reads as "nothing else happened".
"""
n_events_dropped(eng::SwingEngine) = eng.n_dropped

# Append one applied event. Called from `inject!` *after* its no-op guards, so the
# log records what changed the system rather than what was asked for, and reads
# the integrator's own clock rather than being handed a time by the caller.
function _log_event!(eng::SwingEngine, kind::Symbol, a::Symbol, b::Symbol)
    if length(eng.log) < _EVENT_LOG_CAP
        push!(eng.log, EngineEvent(eng.integrator.t, kind, a, b))
    else
        eng.n_dropped += 1
    end
    return nothing
end

"""
    system_inertia(eng::SwingEngine) -> Float64

Total inertia of the machines still online (s, on `model.S_base`) — the same
physical quantity M1's `system_inertia` reports, and the same live indicator, so
the UI reads it through one name for both engines. Drops the moment a machine
trips.
"""
system_inertia(eng::SwingEngine) = eng.Σw

"""
    is_online(eng::SwingEngine, id::Symbol) -> Bool

Whether machine `id` is still online. Unknown ids are simply `false` (a *button*
for a machine that does not exist is not the caller bug `inject!` throws on).
"""
is_online(eng::SwingEngine, id::Symbol) = id in eng.online

# Vertex index of a machine by id. Throws if absent — tripping a machine that does
# not exist is a caller bug, the same contract as M1's `_find_unit`.
function _machine_vertex(eng::SwingEngine, id::Symbol)
    for (v, mid) in pairs(eng.ids)
        mid === id && return v
    end
    throw(KeyError(id))
end

"""
    inject!(eng::SwingEngine, ev::TripGenerator) -> eng

Take a machine offline live: zero its mechanical power and the coupling of every
branch incident to it, and drop it from the COI read-out. **The state vector is
never resized** — the machine's `(δ, ω)` keeps integrating, now decoupled and
undriven, so it simply damps out; resizing mid-integration would force an
integrator re-init and throw away the continuous-state-carries-through property
that makes live injection clean.

Two integrator-boundary calls make this a discrete *event* rather than a silent
parameter poke, and both are needed:

  - `derivative_discontinuity!` so the FSAL solver drops its cached (now stale)
    derivative instead of integrating the first post-trip step from the pre-trip
    one — an error small enough that no assertion catches it unless one is written.
  - `auto_dt_reset!` so the step-size controller re-estimates from the new
    dynamics rather than carrying a step chosen for the pre-trip system.

A machine's branches stay *in service* (`lines_online` is untouched): they are
still there, they simply have nothing left to carry, and reporting them as tripped
would confuse a dead generator with a dead line.

**The post-trip system has no equilibrium** — see the header. Frequency falls until
damping balances the lost generation, and the angles then drift together forever.
That is this tier's physics (no governors), so do not call `find_fixpoint` on the
result and do not assert on an absolute angle.

Tripping an already-offline machine is a no-op; tripping one that does not exist
throws `KeyError`, and the lookup happens first so that error is reachable.
"""
function inject!(eng::SwingEngine, ev::TripGenerator)
    v = _machine_vertex(eng, ev.id)          # throws KeyError on unknown id
    ev.id in eng.online || return eng        # exists but already offline ⇒ no-op
    delete!(eng.online, ev.id)
    p = eng.params                           # === eng.integrator.p (shared object)
    p[eng.Pm_pidx[v]] = 0.0
    for e in eng.incident[v]
        p[eng.K_pidx[e]] = 0.0
    end
    eng.w[v] = 0.0                           # out of the aggregate read-out...
    eng.Σw = sum(eng.w)                      # ...and out of the inertia indicator
    _log_event!(eng, :trip_generator, ev.id, Symbol(""))
    SciMLBase.derivative_discontinuity!(eng.integrator, true)
    SciMLBase.auto_dt_reset!(eng.integrator)
    return eng
end

# The unordered bus pair, as a canonically ordered tuple — the key both the index
# and every lookup go through, so "B1–B2" and "B2–B1" cannot become two keys.
@inline _bus_pair(a::Symbol, b::Symbol) = a < b ? (a, b) : (b, a)

# Branch index (position in `model.branches`) of the line joining two buses, in
# either order, or `nothing`. ONE lookup, shared by the read-out and by the event,
# so "which line is this?" cannot mean two different things in the two places that
# ask — the same reason the recorder has a single `_accept!`. That sharing is also
# why the index went *here* rather than into `is_online` alone: a fast path for the
# read-out and a scan for the event would be the second meaning this comment
# exists to prevent.
#
# It is a hash lookup because a UI calls `is_online` once per line per frame, which
# puts it squarely in the redraw path. At three branches the scan cost nothing; the
# point is that it no longer scales with the network.
_find_branch(eng::SwingEngine, from::Symbol, to::Symbol) =
    get(eng.branch_of_buses, _bus_pair(from, to), nothing)

# The same lookup, but a missing branch is a caller bug rather than a `false` —
# the contract `_machine_vertex` already sets for machines.
function _branch_index(eng::SwingEngine, from::Symbol, to::Symbol)
    b = _find_branch(eng, from, to)
    b === nothing && throw(KeyError((from, to)))
    return b
end

"""
    is_online(eng::SwingEngine, from::Symbol, to::Symbol) -> Bool

Whether the branch between buses `from` and `to` is still in service. Tracked
explicitly rather than read back as `K != 0`, because those are different
questions: a generator trip zeroes the coupling of every branch incident to its
bus, and those lines are still in service — they simply have nothing left to
carry. An unknown bus pair is `false`, matching the machine method (a *button* for
a line that does not exist is not the caller bug `inject!` throws on).
"""
function is_online(eng::SwingEngine, from::Symbol, to::Symbol)
    b = _find_branch(eng, from, to)
    return b !== nothing && b in eng.lines_online
end

"""
    inject!(eng::SwingEngine, ev::TripLine) -> eng

Take a branch out of service live: zero its coupling `K`, so it transfers no power
from this instant on. **The state vector is never resized** and no machine's `Pm`
changes — the discipline and the reasoning are `TripGenerator`'s.

The two integrator-boundary calls are the same pair and are needed for the same
reasons: `derivative_discontinuity!` so the FSAL solver drops its now-stale cached
derivative instead of integrating the first post-trip step from the pre-trip one,
and `auto_dt_reset!` so the step-size controller re-estimates from the new dynamics
rather than carrying a step chosen for the intact network.

Unlike a generator trip this **has an equilibrium** (`Σ Pm` is untouched): the
machines swing and settle back to `ω = 0`, with the surviving branches carrying
what the tripped one used to. See the header for the split-network exception.

Tripping an already-tripped line is a no-op; naming a bus pair no branch joins
throws `KeyError`, and the lookup happens first so that error is reachable.
"""
function inject!(eng::SwingEngine, ev::TripLine)
    b = _branch_index(eng, ev.from, ev.to)   # throws KeyError on an unjoined pair
    b in eng.lines_online || return eng      # exists but already tripped ⇒ no-op
    delete!(eng.lines_online, b)
    # `branch_to_edge` is the reverse of the graph's own edge ordering, which is
    # NOT branch order (see the header). This is the one place that map is read,
    # and `test/` asserts it is a permutation *and* that the right line goes dead.
    eng.params[eng.K_pidx[eng.branch_to_edge[b]]] = 0.0
    # Logged by the branch's own bus names, not the caller's argument order, so two
    # runs that trip the same line agree on what the log says happened.
    br = eng.model.branches[b]
    _log_event!(eng, :trip_line, br.from, br.to)
    SciMLBase.derivative_discontinuity!(eng.integrator, true)
    SciMLBase.auto_dt_reset!(eng.integrator)
    return eng
end
