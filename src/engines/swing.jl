# M2's second concrete engine: a real-time-steppable multi-machine classical
# (network swing) model, built on NetworkDynamics (docs/plans/m2-plan.md §3).
#
# THE TIER. Each machine is a constant-magnitude voltage `E′` **at its bus** whose
# angle is the rotor angle, and branch coupling is the closed form
# `K_ij = E′ᵢE′ⱼ/X_ij` (the D8 correction; see the tier note at the head of
# `model/network_model.jl`). No bus voltage is an unknown, so the whole system stays
# a pure ODE and `Tsit5` still applies. Per machine, on `S_base`:
#
#     dδᵢ/dt   = ω₀·ωᵢ
#     dωᵢ/dt   = (Pm_effᵢ + ΔPmᵢ − Σⱼ K_ij·sin(δᵢ−δⱼ) − Dᵢ·ωᵢ) / (2Hᵢ)
#     dΔPmᵢ/dt = (−ωᵢ·(1/Rᵢ) − ΔPmᵢ) / Tgᵢ      saturated at headroomᵢ (M3 step 1)
#     Pm_effᵢ  = Pmᵢ + rateᵢ·clamp(t − t_startᵢ, 0, durationᵢ)          (M3 step 5)
#
# THE SCHEDULED RAMP (M3 step 5, D7) is the only `t`-dependence in the whole RHS,
# and it earns two notes here because it changes what the file can assume:
#
#   - **The steady-state solve now has to be told a time.** `find_fixpoint` defaults
#     to `t = NaN`, which was harmless while nothing read `t` and is fatal the moment
#     something does (`0.0 * clamp(NaN, …)` is `NaN`). The constructor pins it to the
#     run's own `t0`, and `t_start ≥ t0` is enforced — so the ramp contributes exactly
#     zero at the solve and M2's flat-start criterion survives unchanged.
#   - **A ramp leaves with its machine.** `Pm_eff` is `Pm` plus the ramp, so
#     `inject!(::TripGenerator)` zeroes the rate as well as `Pm`, or a dead rotor
#     would go on being injected into.
#
# `ωᵢ` is a **per-unit speed deviation of one machine** and is NOT M1's aggregate
# `Δω`. The system-wide quantity is the inertia-weighted mean
# `ω_coi = Σ Hᵢωᵢ / Σ Hᵢ`, reported separately and under its own name — conflating
# the two is the silent error `m2-plan.md` warns about. `ΔPmᵢ` inherits that
# discipline and goes one step further: there is deliberately **no aggregate `ΔPm`
# read-out at all**, because a pooled reserve figure is exactly what invites
# "the system has 900 MW of headroom" on a pair of areas that is about to separate.
#
# THE GOVERNOR STATE (M3 step 1) is a *control* state on the same electrical tier,
# not a new tier: nothing about the network representation changes. Three things
# about it are worth having in front of you before reading the RHS:
#
#   - **Governor-free is `R = Inf`, `Pmax = P0`, and it is the default.** The gain
#     `1/R` is then `0` and `ΔPm` starts at `0`, so `dΔPm/dt = −ΔPm/Tg` holds the
#     third state identically at zero. Every M2 model is still exactly the system
#     it was.
#   - **Headroom saturates in the DERIVATIVE, never by clamping the state** — the
#     correctness landmine carried since M1 (see `engines/frequency_response.jl`).
#     Zeroing the derivative also gives release for free: once frequency recovers,
#     the governor term turns negative and `ΔPm` comes off the ceiling unaided.
#   - **There is no down-regulation floor**, deliberately, as in M1. Only the
#     up-headroom saturates; a machine held above nominal commands unboundedly
#     negative `ΔPm`. A known limit of the tier, recorded rather than papered over.
#
# AND DROOP STILL DOES NOT GIVE A POST-TRIP EQUILIBRIUM. At settle
# `Δω = −ΔP/(1/R_eq + D)`, non-zero because load damping carries part of the
# deficit, so the angles keep drifting exactly as the note below describes.
# Governors make the drift slower, not absent. The two standing rules are unchanged.
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
# deliberately breaks it, and the remaining machines cannot make the loss up —
# not even with governors. The system therefore has **no fixpoint at all**
# afterwards. Speed falls until the primary response *plus* damping balances the
# shortfall and, because that limit is non-zero, every `δ` then grows without bound
# at a common rate. That is the physics of this tier, not a bug and not an
# integration failure: angle *differences* still settle. Consequences: never call
# `find_fixpoint` on a post-generator-trip state (it cannot converge), and never
# assert on an absolute angle.
#
# The settling speed is where the two cases differ, and only in magnitude:
#
#     no governors (M2):  ω_coi → ΣPm_remaining / ΣD
#     with droop (M3):    ω_coi → ΣPm_remaining / (Σ 1/Rᵢ + ΣD),  or the headroom
#                         ceiling if the droop command runs out of reserve first
#
# The second is smaller, never zero. Believing droop makes it zero is the premise
# `m3-plan.md` was written against.
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

One machine's RHS. State `v = (δ, ω, ΔPm)` — rotor angle (rad), per-unit speed
deviation, and the governor's extra mechanical power (pu on the system base).
Parameters `p = (Pm, H, D, ω₀, invR, headroom, Tg, rate, t_start, duration)`, all on
the system base.

`ΔPm` is a **deviation**: it starts at zero and rides on top of the scheduled `Pm`,
so a machine's total mechanical power is `Pm + ΔPm`. It is per machine, and there
is no aggregate counterpart by design (see the head of this file).

`(rate, t_start, duration)` are the scheduled **generation ramp** (M3 step 5, D7):
the scheduled power itself becomes `Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)`.
A machine with no ramp carries `rate = 0`, which is arithmetically the machine it
always was — asserted in `test/`, to the bit.

`ω₀` rides in the parameter vector rather than being captured in a closure so that
every model compiles to the *same* `Network` type: a closure over `ω₀` would make
each system its own anonymous function type and force a recompile per model. The
governor parameters ride there for a second reason as well — `inject!` has to be
able to take a machine's droop and reserve out of the live system at an event
boundary without touching the continuous state.
"""
function swing_vertex!(dv, v, esum, p, t)
    δ, ω, ΔPm = v[1], v[2], v[3]
    Pm, H, D, ω₀ = p[1], p[2], p[3], p[4]
    invR, headroom, Tg = p[5], p[6], p[7]
    rate, t_start, duration = p[8], p[9], p[10]
    dv[1] = ω₀ * ω
    # The scheduled generation ramp (M3 step 5, D7). Continuous in `t`: it holds at
    # `Pm` until `t_start`, travels linearly for `duration`, then holds. The two ends
    # are corners in the SLOPE, never jumps — and that is the whole reason this is a
    # ramp inside the RHS rather than the obvious alternative, **a staircase of N
    # discrete trips**. A staircase's edges are jump discontinuities in exactly the
    # signal step 3's shed ladder and step 4's out-of-step relay root-find on, so the
    # instants they report would be artefacts of the slice count N — a number that
    # moves when you change N and still looks like a result. That is the class of
    # error step 6's sweep exists to rule out, so it must not be built into the input
    # the sweep varies. Cost, stated: the vertex RHS now carries a scenario input.
    #
    # `rate == 0` is the un-ramped machine and is arithmetically identical to the
    # pre-M3-step-5 line (`Pm + 0.0` is `Pm`, bit for bit), which is what lets every
    # existing model keep its recorded run to the digit.
    Pm_eff = Pm + rate * clamp(t - t_start, 0.0, duration)
    # `esum` is MINUS the electrical power exported from this bus — see the sign
    # convention note in the file header — hence `+ esum[1]`, not `-`.
    dv[2] = (Pm_eff + ΔPm + esum[1] - D * ω) / (2 * H)
    # Governor/turbine first-order lag toward the droop-commanded power. `invR` is
    # the GAIN `1/R` already converted to the system base (`machine_arrays`), so a
    # governor-free machine is `invR = 0` — no droop command, and no `Inf` in the
    # hot path to produce a `NaN`.
    dΔPm = (-ω * invR - ΔPm) / Tg
    # Saturation in the DERIVATIVE at this machine's own up-reserve — never a
    # post-hoc clamp of the state, which would corrupt the integration (the M1
    # landmine; see `engines/frequency_response.jl`). Zeroing the derivative also
    # releases for free: when frequency recovers the governor term turns negative,
    # the condition stops firing, and `ΔPm` comes off the ceiling unaided.
    #
    # `zero(dΔPm)` and not `0.0`: the fixpoint solve differentiates this RHS, where
    # `dΔPm` is a dual number, and rebinding it to a `Float64` would make the local
    # type-unstable on exactly the path that has to be fast.
    if ΔPm >= headroom && dΔPm > 0
        dΔPm = zero(dΔPm)
    end
    dv[3] = dΔPm
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
(`δ_idx`/`ω_idx`/`ΔPm_idx`/`Pm_pidx`/`K_pidx`/`invR_pidx`/`hr_pidx`/`rate_pidx`), resolved once through
NetworkDynamics' symbolic interface so nothing here assumes a memory layout; `branch_to_edge` and
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
    ΔPm_idx::Vector{Int}
    Pm_pidx::Vector{Int}
    K_pidx::Vector{Int}
    invR_pidx::Vector{Int}
    hr_pidx::Vector{Int}
    rate_pidx::Vector{Int}
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
    ladders::Vector{ShedLadder}
    relays::Vector{OutOfStepRelay}
    ramps::Vector{Pair{Symbol,GenerationRamp}}
end

# `isoutofdomain` predicate, built per engine because it has to close over the
# resolved flat indices (there is no other way to reach `ΔPm` and `headroom` from
# the `(u, p, t)` the solver hands it).
#
# It touches **only** the `ΔPm` entries. `δ` and `ω` are deliberately unbounded in
# this engine — post-trip the angles drift forever by design — so a predicate that
# looked at them would reject every step of a perfectly correct run and collapse
# `dt` to an abort. That is not a hypothetical: it is why M2 shipped with no guard
# at all. Asserted directly in `test/` against a state with a large drifted angle,
# because a predicate that quietly grew a `δ` term would show up as "the solver got
# slow", not as a failure.
#
# The `1e-10` slack is roundoff tolerance so a step landing exactly *on* a ceiling
# is not rejected. A machine with zero headroom (every governor-free one) has
# `ΔPm ≡ 0` against a ceiling of `0`, which never trips it.
# --- how a shedding ladder reaches THIS engine's state (M3 step 3, D5) -----------
#
# `protection/load_shedding.jl` knows no state layout: a ladder binds to a named
# machine and the engine supplies two functions saying where that machine's speed
# and power live. Here they close over the flat indices resolved below, which is the
# whole point of the refactor — the condition reads **one machine's own** `ω`, never
# the COI average, and the affect steps **that machine's own** `Pm`, never a
# system-wide imbalance.
#
# `Pm` on this tier is a NET injection at the bus (generation minus load; see the
# file header), so disconnecting load raises it by exactly the block that was shed.
# That is the same sign as M1's `ΔP_dist += ΔP_pu` and for the same reason.
_swing_speed(ω_index::Int) = u -> @inbounds u[ω_index]
_swing_shed!(Pm_index::Int) =
    (integrator, ΔP_pu) -> (@inbounds integrator.p[Pm_index] += ΔP_pu; nothing)

# The ladders a `SwingEngine` is built with, validated and bound. Kept out of the
# constructor body because it is three guards and their messages, and the M2/M3
# discipline is that each guard is asserted by its own message — an invalid `shed`
# argument usually breaks more than one rule at once, and "it threw" would not show
# which one fired.
#
# `shed` is a **vector of pairs**, not a `Dict`: the callback set is built in the
# caller's order, and a `Dict`'s iteration order is not the caller's. Two runs of
# the same script must arm the same callbacks in the same order.
function _bind_shed(shed, ids::Vector{Symbol}, ω_idx::Vector{Int},
                    Pm_pidx::Vector{Int})
    ladders = ShedLadder[]
    bound = Any[]
    for (machine, stages) in shed
        machine === AGGREGATE_MACHINE && throw(ArgumentError(
            "shed: `:$(AGGREGATE_MACHINE)` is the aggregate engine's sentinel, not " *
            "a machine; on a network every ladder must name one of $(ids)"))
        v = findfirst(==(machine), ids)
        v === nothing && throw(ArgumentError(
            "shed: no machine named `:$machine` in this network; have $(ids)"))
        any(l -> l.machine === machine, ladders) && throw(ArgumentError(
            "shed: two ladders bound to machine `:$machine`; give it one ladder " *
            "with all its stages, or its blocks shed twice"))
        ladder = ShedLadder(machine, collect(LoadShedStage, stages))
        push!(ladders, ladder)
        push!(bound, (ladder, _swing_speed(ω_idx[v]), _swing_shed!(Pm_pidx[v])))
    end
    return ladders, bound
end

# --- how an out-of-step relay reaches THIS engine's state (M3 step 4, D6) --------
#
# `protection/out_of_step.jl` knows neither the state layout nor how to open a
# branch; both arrive as functions, the same seam the shedding ladder uses.
#
# `δdiff` reads the angle across the branch **in the branch's own orientation**
# (`from` minus `to`, straight out of `branch_arrays`), NOT the graph edge's. The
# two differ: `Graphs` iterates edges in sorted `(src, dst)` order and may hold the
# ends the other way round, which would silently negate the quantity. It does not
# matter to the threshold, which is on `|·|` — but it matters to `δ_tripped` in the
# log, and it would matter to anything that later reads the sign as a direction of
# flow. The unsigned test would have hidden the signed bug, so the orientation is
# taken from the place that defines it.
#
# `trip!` runs the engine's own `inject!(::TripLine)` — the real one, not a copy of
# its body. That is the strongest reading of the plan's "fires through the existing
# `inject!(::TripLine)` path": the no-op guard, `lines_online`, the event log and
# both integrator-boundary calls are then the shipped ones by construction rather
# than by a helper two call sites have to keep agreeing about.
#
# THE PRICE, STATED. `inject!` needs the engine, and the engine cannot exist yet:
# the callbacks are arguments to `init`, whose integrator is one of the engine's own
# type parameters. So the affect closes over a `Base.RefValue{Any}` that the
# constructor fills with the finished engine on its last line. That box is a local
# captured by one closure — it is **not** a field of any struct, so SPEC §4's
# concrete-field rule is untouched — and it costs one dynamic dispatch on an event
# that happens at most once per relay per run. The alternative (factoring `inject!`
# into a helper over the pieces that do exist early) was rejected because the only
# genuinely engine-bound piece is the event log's `n_dropped` counter: it would move
# the log into its own object to buy back type stability on a once-per-run call, and
# leave two ways to open a branch where the milestone's whole point is that there is
# one.
_swing_δdiff(i::Int, j::Int) = u -> @inbounds(u[i] - u[j])
function _swing_trip_branch!(box::Base.RefValue{Any}, from::Symbol, to::Symbol)
    ev = TripLine(from, to)                 # built once, not per fire
    return integrator -> (inject!(box[]::SwingEngine, ev); nothing)
end

# The relays a `SwingEngine` is built with, validated and bound. Kept out of the
# constructor body for `_bind_shed`'s reason: it is four guards and their messages,
# and the M2/M3 discipline is that each is asserted by its own wording.
#
# `out_of_step` is a **vector of pairs** `[(:B1, :B3) => OutOfStepTrip(2π/3)]`, not a
# `Dict`, so the callback set is built in the caller's order (`shed`'s reason). A
# bare number is accepted for the threshold, because a relay with no label to give
# should not have to name a type to say "trip at 120°".
#
# It takes the engine's own `branch_of_buses` rather than building a second bus-pair
# lookup: "which line is this?" must not have two implementations, which is the
# reason `_find_branch` exists at all (see its comment).
function _bind_out_of_step(out_of_step, net::NetworkModel, ba, δ_idx::Vector{Int},
                           branch_of::Dict{Tuple{Symbol,Symbol},Int},
                           box::Base.RefValue{Any})
    relays = OutOfStepRelay[]
    bound = Any[]
    pairs_seen = Set{Tuple{Symbol,Symbol}}()
    for (buspair, setting) in out_of_step
        from, to = buspair
        key = _bus_pair(from, to)
        b = get(branch_of, key, nothing)
        b === nothing && throw(ArgumentError(
            "out_of_step: no branch joins buses `:$from`–`:$to`; have " *
            "$([(br.from, br.to) for br in net.branches])"))
        key in pairs_seen && throw(ArgumentError(
            "out_of_step: two relays on the branch `:$from`–`:$to`; give it one " *
            "relay, or the second is armed on a tie the first has already opened"))
        push!(pairs_seen, key)
        s = setting isa OutOfStepTrip ? setting : OutOfStepTrip(setting)
        br = net.branches[b]
        # The branch's own bus names and orientation, not the caller's argument
        # order — the rule `inject!(::TripLine)` already applies to the event log.
        r = OutOfStepRelay(br.from, br.to, s)
        push!(relays, r)
        push!(bound, (r, _swing_δdiff(δ_idx[ba.src[b]], δ_idx[ba.dst[b]]),
                      _swing_trip_branch!(box, br.from, br.to)))
    end
    return relays, bound
end

# The fourth guard, which can only be checked once the steady state exists: a relay
# whose threshold is already exceeded at `t = 0` is armed on a system that is *by its
# own definition* out of step before the run begins. Checked against the fixpoint, so
# it catches a threshold set below a perfectly ordinary pre-fault transfer angle.
#
# WHAT SUCH A RELAY ACTUALLY DOES — and this is NOT what the guard was first written
# against, which is why the wording is now what was measured rather than what was
# reasoned. The obvious argument is "it can never fire: the condition starts negative
# and a downward crossing needs a positive side to fall from." That argument is
# wrong, and the measurement is in `test/`. The condition is `threshold − |δ|`, and
# `|δ|` is not monotone: the export swing carries the angle DOWN THROUGH ZERO before
# it runs away (the report's flow reversal, and this tier's version of it). So on the
# step-4 fixture a relay set at 0.3 rad against a 0.3789 rad steady state starts at
# `g = −0.079`, is carried *inside* its own threshold at t ≈ 0.41 s, and then fires
# on the way back out at **t ≈ 1.25 s** — 1.7 s before the genuine slip at 2.93 s,
# on an angle excursion that is an ordinary consequence of the disturbance and not a
# loss of synchronism at all.
#
# So the guard is not preventing an inert relay; it is preventing one that trips a
# healthy tie early and looks like it worked. Refused at construction, because both
# readings of a below-operating-point threshold ("trip immediately" and "trip on the
# swing") are things the caller did not ask for.
function _guard_out_of_step_start(bound::AbstractVector, u0::Vector{Float64})
    for (r, δdiff, _) in bound
        d = δdiff(u0)
        abs(d) < r.threshold_rad || throw(ArgumentError(
            "out_of_step: relay on `:$(r.from)`–`:$(r.to)` has threshold_rad " *
            "$(r.threshold_rad) rad, but the steady-state angle across that " *
            "branch is already $(abs(d)) rad. Such a relay protects nothing: it is " *
            "inert until the swing carries the angle back inside its threshold, and " *
            "then fires on the way out — at an instant set by the disturbance's " *
            "angle excursion rather than by any loss of synchronism."))
    end
    return nothing
end

# --- how a scheduled generation ramp reaches THIS engine's parameters (step 5, D7)
#
# Unlike a ladder or a relay, a ramp holds **no live state**: it is three numbers
# that sit in the vertex parameter vector and are read by the RHS. So there is
# nothing to bind by closure and nothing an engine could accidentally share with
# another — this only validates and normalises what the caller asked for.
#
# `ramp` is a **vector of pairs**, not a `Dict`, for `shed`'s and `out_of_step`'s
# reason: two runs of the same script must produce the same engine, and a `Dict`'s
# iteration order is not the caller's. Here it decides nothing about callbacks, but
# it does decide the order `generation_ramp`'s owner reports them in, and one rule
# for all three arming arguments is cheaper than a rule with an exception.
#
# THE `t_start ≥ t0` GUARD IS THE ONE THAT MATTERS, and it lives here rather than on
# `GenerationRamp` because only the engine knows `t0`. A ramp already under way at
# the start of the run would be folded into the steady state `find_fixpoint` places
# the engine on, and the run would then begin **off** the equilibrium of its own
# system: it would ring from `t = 0` with a plausible oscillation that is pure
# initialisation artefact. That is precisely M2's flat-start acceptance criterion
# (V1), and a mis-signed `t_start` is exactly how it would be lost quietly. Refused
# at construction instead.
function _bind_ramps(ramp, ids::Vector{Symbol}, t0::Float64)
    out = Pair{Symbol,GenerationRamp}[]
    for (machine, setting) in ramp
        findfirst(==(machine), ids) === nothing && throw(ArgumentError(
            "ramp: no machine named `:$machine` in this network; have $(ids)"))
        any(pr -> first(pr) === machine, out) && throw(ArgumentError(
            "ramp: two ramps on machine `:$machine`; give it one ramp, or only the " *
            "last would be armed and the other would silently do nothing"))
        r = setting::GenerationRamp
        r.t_start >= t0 || throw(ArgumentError(
            "ramp: the ramp on `:$machine` starts at t_start = $(r.t_start) s, before " *
            "the run's own t0 = $t0 s. A ramp already under way when the run starts " *
            "is folded into the steady state the engine is placed on, and the run " *
            "then rings from t0 with an oscillation that is initialisation artefact " *
            "rather than physics. Set t_start >= t0."))
        push!(out, machine => r)
    end
    return out
end

function _swing_outofdomain(ΔPm_idx::Vector{Int}, hr_pidx::Vector{Int})
    return function (u, p, t)
        @inbounds for k in eachindex(ΔPm_idx)
            u[ΔPm_idx[k]] > p[hr_pidx[k]] + 1e-10 && return true
        end
        return false
    end
end

"""
    SwingEngine(net::NetworkModel; t0=0.0, dt=0.02, solver=Tsit5(), shed=[],
                out_of_step=[], ramp=[], capacity=200_000)

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

`shed` arms low-frequency load shedding **per machine**, as a vector of pairs
`[:ES => stages, :PT => stages]` (`LoadShedStage`). Each pair becomes one
`ShedLadder` bound to that machine: its stages root-find crossings of **that
machine's own** frequency and step **that machine's own** `Pm`. Binding to a name
rather than to `f_coi` is decision D5, and it is the difference between Iberia's
defence plan firing on Iberian frequency and firing on an inertia-weighted average
of Iberia and Continental Europe — which is a number this file's header calls
meaningless the moment the two are separating. Default: no ladders.

The engine builds the ladders and owns them (`eng.ladders`, `shed_ladder`), because
a ladder holds a live latch and log that two engines must not share.

`out_of_step` arms out-of-step (pole-slip) protection **per branch**, as a vector of
pairs `[(:B1, :B3) => OutOfStepTrip(2π/3)]`; a bare number is taken as the threshold
in radians. Each pair becomes one `OutOfStepRelay` that root-finds the instant
`|δ_from − δ_to|` crosses its threshold and then opens that branch through this
engine's own `inject!(::TripLine)`. Latching, and disarmed rather than fired if the
branch is opened by anything else or a generator at either end trips (decision D6;
see `protection/out_of_step.jl` for why the threshold lives on the relay and not on
`Branch`). Owned by the engine for the ladders' reason. Default: no relays.

`ramp` schedules a **generation ramp** per machine, as a vector of pairs
`[:G1 => GenerationRamp(rate_pu_per_s, t_start, duration)]` (M3 step 5, D7). The
machine's scheduled power becomes `Pm + rate·clamp(t − t_start, 0, duration)` — a
continuous linear change rather than the instant `TripGenerator` applies, which is
what the report's 2.46 s cascade actually was and what step 6's sweep varies.
Unlike a ladder or a relay it carries no live state: it is three vertex parameters,
armed here and read by the RHS. `t_start` must be at or after `t0` (see
`_bind_ramps` for what a mis-signed one would do to the flat start). Default: no
ramps, which is `rate = 0` and is the machine every earlier model described, to the
bit.
"""
function SwingEngine(net::NetworkModel; t0::Real = 0.0,
                     dt::Real = _SWING_DT0,
                     solver = OrdinaryDiffEq.Tsit5(),
                     shed = Pair{Symbol,Vector{LoadShedStage}}[],
                     out_of_step = Pair{Tuple{Symbol,Symbol},OutOfStepTrip}[],
                     ramp = Pair{Symbol,GenerationRamp}[],
                     capacity::Integer = _TRAJ_CAPACITY)
    ma = machine_arrays(net)
    ba = branch_arrays(net)
    nb = length(net.buses)
    # Machine ids in bus order, by construction. Resolved at the top because the
    # shed ladders below are bound by id and their guard messages list them.
    ids0 = Symbol[m.id for m in net.machines]

    # The same graph the model validated itself against (one edge per bus pair,
    # connected — both already enforced by the `NetworkModel` constructor).
    g = Graphs.SimpleGraph(nb)
    for e in eachindex(ba.src)
        Graphs.add_edge!(g, ba.src[e], ba.dst[e])
    end
    ne = Graphs.ne(g)

    # `StateMask(1:1)` still means "this vertex's output to the network is state 1,
    # the angle" — the third state is invisible to the edges, which is the whole
    # claim that M3 adds a control state and does not move the electrical tier.
    vertex = NetworkDynamics.VertexModel(f = swing_vertex!,
                                         g = NetworkDynamics.StateMask(1:1),
                                         sym = [:δ, :ω, :ΔPm],
                                         psym = [:Pm, :H, :D, :ω₀, :invR, :headroom, :Tg,
                                                 :rate, :t_start, :duration],
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
        # `ΔPm` is a deviation, so the pre-disturbance value is zero — and it is a
        # genuine fixpoint of its own equation there (`dΔPm/dt = (−0·invR − 0)/Tg`),
        # so seeding it does not bias the solve. The saturation branch is not taken
        # at the seed either: `dΔPm` is `0`, not `> 0`.
        s.v[i, :ΔPm] = 0.0
        s.p.v[i, :Pm] = ma.Pm[i]
        s.p.v[i, :H]  = ma.H[i]
        s.p.v[i, :D]  = ma.D[i]
        s.p.v[i, :ω₀] = ω₀
        s.p.v[i, :invR]     = ma.invR[i]
        s.p.v[i, :headroom] = ma.headroom[i]
        s.p.v[i, :Tg]       = ma.Tg[i]
        # No ramp is the default, and it is `rate = 0` — arithmetically the machine
        # this engine described before M3 step 5. `t_start`/`duration` are then
        # unread; they are seeded to a self-consistent zero rather than to `Inf` so
        # nothing in the RHS can multiply a zero by an infinity.
        s.p.v[i, :rate]     = 0.0
        s.p.v[i, :t_start]  = 0.0
        s.p.v[i, :duration] = 0.0
    end
    # The armed ramps overwrite those defaults. Done through the symbolic interface
    # for the same reason every other parameter is (`test/` asserts the flat indices
    # round-trip against a symbolic read), and BEFORE the fixpoint solve, so the
    # steady state the engine is placed on is the steady state of the system the
    # ramp is armed on — not of a different one that gets the ramp bolted on after.
    ramps = _bind_ramps(ramp, ids0, Float64(t0))
    for (machine, r) in ramps
        i = findfirst(==(machine), ids0)::Int
        s.p.v[i, :rate]     = r.rate
        s.p.v[i, :t_start]  = r.t_start
        s.p.v[i, :duration] = r.duration
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

    # Flat indices into the state and parameter vectors, resolved once through
    # NetworkDynamics' symbolic interface. Nothing in this engine assumes a stride
    # or an ordering; `test/` asserts these round-trip against a symbolic read, so
    # if the upstream layout ever moves, that test says so instead of the physics
    # going quietly wrong.
    #
    # Resolved BEFORE the integrator (M3 step 1) because the `isoutofdomain`
    # predicate below is built from them and has to be handed to `init`. They come
    # off `nw` alone, so nothing about the ordering here depends on the integrator.
    SII = NetworkDynamics.SII
    δ_idx     = [SII.variable_index(nw, NetworkDynamics.VIndex(i, :δ)) for i in 1:nb]
    ω_idx     = [SII.variable_index(nw, NetworkDynamics.VIndex(i, :ω)) for i in 1:nb]
    ΔPm_idx   = [SII.variable_index(nw, NetworkDynamics.VIndex(i, :ΔPm)) for i in 1:nb]
    Pm_pidx   = [SII.parameter_index(nw, NetworkDynamics.VPIndex(i, :Pm)) for i in 1:nb]
    K_pidx    = [SII.parameter_index(nw, NetworkDynamics.EPIndex(e, :K)) for e in 1:ne]
    invR_pidx = [SII.parameter_index(nw, NetworkDynamics.VPIndex(i, :invR)) for i in 1:nb]
    hr_pidx   = [SII.parameter_index(nw, NetworkDynamics.VPIndex(i, :headroom)) for i in 1:nb]
    # Only the ramp's RATE gets a flat index: it is the one ramp parameter anything
    # writes at an event boundary (`inject!(::TripGenerator)` zeroes it — see there).
    # `t_start` and `duration` are set once at construction and never move, so an
    # index into them would be a handle to something nothing may write.
    rate_pidx = [SII.parameter_index(nw, NetworkDynamics.VPIndex(i, :rate)) for i in 1:nb]

    # Built BEFORE the integrator and shared with it, the same construction order
    # M1 uses: the callbacks close over these exact ladders and the engine keeps the
    # same objects as a field. They need the flat indices above, which is why they
    # are built here and not with the rest of the engine's own bookkeeping.
    ladders, bound_shed = _bind_shed(shed, ids0, ω_idx, Pm_pidx)

    # The out-of-step relays, and the box their affect reaches the finished engine
    # through — see the note above `_swing_trip_branch!` for why it has to be a box
    # and what that costs.
    eng_box = Base.RefValue{Any}(nothing)
    # Bus pair ⇒ branch index. Built HERE rather than with the rest of the engine's
    # bookkeeping because the relay binding below resolves branches through it, and
    # one lookup is the point (see `_find_branch`). The key is the *unordered* pair,
    # matching `TripLine`'s "either order" contract. It exists in the first place
    # because a UI asks `is_online` once per line per frame, which puts it in the
    # redraw path.
    branch_of_buses = Dict{Tuple{Symbol,Symbol},Int}(
        _bus_pair(br.from, br.to) => b for (b, br) in pairs(net.branches))
    relays, bound_oos =
        _bind_out_of_step(out_of_step, net, ba, δ_idx, branch_of_buses, eng_box)

    # --- steady state, then the integrator -------------------------------------
    t0f = Float64(t0)
    # `t = t0f`, EXPLICITLY, and this is not decoration. `find_fixpoint` defaults its
    # evaluation time to **`NaN`** (NetworkDynamics passes `t = NaN` straight into the
    # RHS through `NetworkFixedT`), which every model up to M3 step 4 got away with
    # only because no vertex RHS read `t` at all. Step 5's ramp does read it — and
    # `clamp(NaN − t_start, 0, d)` is `NaN`, `0.0 * NaN` is `NaN`, so an un-ramped
    # machine would have been enough to NaN out the steady-state solve of every model
    # in the repo. Evaluating at the run's own start time is also simply the right
    # question to ask: "what is this system's equilibrium at the instant the run
    # begins?"
    #
    # This is what makes THE RAMP INERT AT THE FIXPOINT SOLVE. `_bind_ramps` refuses
    # `t_start < t0`, so `clamp(t0 − t_start, 0, duration)` is exactly `0` here for
    # every armed ramp: the fixpoint is the equilibrium of the un-ramped system, the
    # engine starts flat on it, and the ramp begins from that flat start.
    fp = NetworkDynamics.find_fixpoint(nw, s; t = t0f)
    u0 = collect(NetworkDynamics.uflat(fp))
    p0 = collect(NetworkDynamics.pflat(fp))
    # The one relay guard that needs the steady state, so it runs here rather than
    # with the other three.
    _guard_out_of_step_start(bound_oos, u0)
    # Same integrator discipline as M1 (docs/SPEC.md §6): a large *finite* tspan
    # because we drive it with `step!(integ, dt, true)` and never reach the end,
    # an explicit seed `dt`, and the integrator's own saved solution switched off —
    # we keep our own bounded history, and its would grow without bound on a long
    # live run.
    #
    # THE `isoutofdomain` GUARD, AND THE HEADER NOTE IT REPLACES (M3 step 1). Until
    # M3 this file said there is deliberately **no** such guard, on the grounds that
    # nothing in the engine is bounded — post-trip the angles drift forever by
    # design, so a copied M1-style state guard would fire spuriously and collapse
    # the step size. That reasoning is still exactly right for `δ` and `ω`, and it
    # is now incomplete: `ΔPm` *is* bounded, by each machine's own headroom.
    #
    # So the predicate exists and tests **only the `ΔPm` indices**. It rejects and
    # retries an offending step, never writing the state, so it is not the forbidden
    # post-hoc clamp — the derivative saturation in `swing_vertex!` does the physical
    # work and this only absorbs adaptive-step overshoot on top of it. During
    # continuous integration it cannot stall, because the derivative is already zero
    # at the ceiling, which puts the solution *at* `headroom`, not above it.
    prob = OrdinaryDiffEq.ODEProblem(nw, u0, (t0f, t0f + 1.0e6), p0)
    integrator = OrdinaryDiffEq.init(prob, solver; dt = Float64(dt),
                                     isoutofdomain = _swing_outofdomain(ΔPm_idx, hr_pidx),
                                     callback = SciMLBase.CallbackSet(
                                         shed_callbacks(bound_shed, net.f0),
                                         out_of_step_callbacks(bound_oos)),
                                     save_everystep = false, dense = false)

    ids = ids0
    # `H` is the pre-trip baseline, kept unmutated; `w` is the live COI weight
    # (a machine's inertia while online, zero once tripped). Nothing in M2a reads
    # `H` yet — step 6's `coi_model` needs the original inertias to compile the
    # aggregate model, and recovering them from `w` after a trip is impossible.
    H = copy(ma.H)
    w = copy(ma.H)

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
                      net.f0, ω₀, ids, δ_idx, ω_idx, ΔPm_idx, Pm_pidx, K_pidx,
                      invR_pidx, hr_pidx, rate_pidx,
                      branch_to_edge, incident, branch_of_buses, H, w, sum(w), traj,
                      Vector{Float64}(undef, length(channels)),
                      EngineEvent[], 0, net.f0, ladders, relays, ramps)
    _record!(eng)                                 # seed the pre-disturbance point
    # The last line, and it has to be: an out-of-step relay's affect calls this
    # engine's own `inject!(::TripLine)`, and until now there was no engine to call
    # it on. Nothing can have fired before this point — `init` does not step.
    eng_box[] = eng
    return eng
end

"""
    init!(SwingEngine, net::NetworkModel; t0=0.0, dt=0.02, solver=Tsit5(), shed=[],
          out_of_step=[], capacity=200_000)

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
    current_state(eng::SwingEngine) -> (; t, δ, ω, ΔPm, δ_coi, ω_coi, f_coi)

Named state at "now". Pure read of the integrator — no stepping.

  - `δ`     — per-machine rotor angles (rad), in bus order. **Gauge-dependent**:
              only differences are meaningful (see the constructor's note).
  - `ω`     — per-machine per-unit speed deviations, in bus order. One machine's
              deviation; *not* M1's aggregate `Δω`.
  - `ΔPm`   — per-machine governor output (pu on `S_base`), in bus order: the extra
              mechanical power on top of the scheduled `Pm`, saturated at that
              machine's own headroom. **Deliberately not aggregated** — see the head
              of this file. It is read here rather than recorded as a trajectory
              channel: the channel set of a running engine is fixed at construction,
              and a per-machine reserve trace is not what a live indicator wants.
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
            ΔPm = u[eng.ΔPm_idx],
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
    step!(eng::SwingEngine, dt=eng.dt) -> (; t, δ, ω, ΔPm, δ_coi, ω_coi, f_coi)

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
    shed_ladder(eng::SwingEngine, machine::Symbol) -> ShedLadder

The load-shedding ladder bound to `machine`, for `shed_log` / `shed_total` and for
step 7's annotated panel. Throws `KeyError` if that machine has no ladder — asking
for one that was never armed is a caller bug, the same contract `_machine_vertex`
sets for machine ids.

Deliberately per machine and not pooled: see `shed_log`.
"""
function shed_ladder(eng::SwingEngine, machine::Symbol)
    for l in eng.ladders
        l.machine === machine && return l
    end
    throw(KeyError(machine))
end

"""
    out_of_step_relay(eng::SwingEngine, from::Symbol, to::Symbol) -> OutOfStepRelay

The out-of-step relay armed on the branch between buses `from` and `to`, in either
order, for `out_of_step_log` and for step 7's annotated panel. Throws `KeyError` if
that branch has no relay — asking about one that was never armed is a caller bug,
the same contract `shed_ladder` sets for machines.
"""
function out_of_step_relay(eng::SwingEngine, from::Symbol, to::Symbol)
    key = _bus_pair(from, to)
    for r in eng.relays
        _bus_pair(r.from, r.to) === key && return r
    end
    throw(KeyError((from, to)))
end

"""
    generation_ramp(eng::SwingEngine, machine::Symbol) -> GenerationRamp

The generation ramp armed on `machine` — what was scheduled, for annotation and for
step 6's sweep to read back what it set. Throws `KeyError` if that machine has no
ramp, the contract `shed_ladder` and `out_of_step_relay` already set.

**What was armed, not what is left.** A ramp is inert data; the live quantity is the
`rate` parameter in the running system, which `inject!(::TripGenerator)` zeroes when
the machine goes offline. This accessor does not track that, deliberately: two
different questions ("what did this scenario schedule?" and "what is the system
doing now?") must not share one answer.
"""
function generation_ramp(eng::SwingEngine, machine::Symbol)
    for (m, r) in eng.ramps
        m === machine && return r
    end
    throw(KeyError(machine))
end

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

**Its shedding ladder is disarmed too** (M3 step 3), without firing and without
touching what it already logged. A ladder bound to this machine would otherwise
keep root-finding on a rotor that is now islanded, undriven and decaying to
whatever `ω` damping leaves it at — a speed that is no longer the frequency of
anything — and its affect would step the `Pm` this trip has just zeroed, so a dead
machine would start injecting power. Disarming kills that by construction instead
of by argument.

This is a **generator** trip only. `inject!(::TripLine)` deliberately does *not*
disarm anything: a line trip can island a live machine, which is exactly the
situation its ladder exists for, and step 4's out-of-step protection fires through
that same path.

**Any scheduled generation ramp leaves with it too** (M3 step 5): the ramp adds to
`Pm`, so zeroing `Pm` without zeroing the ramp's rate would leave an offline,
decoupled machine still injecting the ramp — see the body.

**The machine's governor leaves with it, and its `ΔPm` is re-seated to zero at the
boundary** (M3 step 1). Zeroing the droop gain and the headroom is the physics — a
dead machine commands no primary response and holds no reserve — but doing only
that would strand a `ΔPm` that was riding the old ceiling *above* the new one of
zero, and the `isoutofdomain` guard would then reject every proposed step until
`dt` collapsed to an abort. This is the same hazard M1 documents and the same
answer: a **discrete jump at an event boundary**, which is not the forbidden
mid-integration post-hoc clamp. It re-seats to zero rather than to the new ceiling
because a tripped machine produces nothing at all, not merely nothing extra — its
scheduled `Pm` goes to zero in the very same breath.

Three integrator-boundary calls make this a discrete *event* rather than a silent
parameter poke, and all three are needed:

  - the `ΔPm` re-seat above, before the two calls below, so the derivative the
    solver recomputes is the one for the state it will actually integrate from;
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
    # The governor leaves with the machine: no droop command, no reserve.
    p[eng.invR_pidx[v]] = 0.0
    p[eng.hr_pidx[v]]   = 0.0
    # …and so does any scheduled generation ramp (M3 step 5). This is NOT tidiness.
    # `Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)`, so zeroing `Pm` alone
    # leaves the ramp term standing on its own: a machine that is offline, decoupled
    # from every branch and undriven would go on injecting `rate·(elapsed)` into a
    # rotor that is no longer connected to anything. `m3-context.md` predicted this
    # exact re-opening — it is the "a dead machine would shed and inject" case, which
    # step 3 found unreachable through the shed ladder and which explicit
    # `t`-dependence in the vertex RHS puts back on the table. Closed by construction
    # rather than by argument, and `test/` observes it from OUTSIDE the parameter
    # vector (the survivors' settling frequency), because reading the parameter back
    # would pass even if the RHS ignored it.
    p[eng.rate_pidx[v]] = 0.0
    # …and the state it had accumulated is re-seated at the boundary, or it would be
    # stranded above the ceiling that just went to zero and the `isoutofdomain`
    # guard would reject every step from here on (see the docstring).
    eng.integrator.u[eng.ΔPm_idx[v]] = 0.0
    # The area's defence plan goes with its machine (see the docstring): latched,
    # not fired, so the log stays a record of what actually shed.
    for l in eng.ladders
        l.machine === ev.id && disarm!(l)
    end
    # …and so does every out-of-step relay watching a branch that ends at this bus
    # (M3 step 4). Same asymmetry as the ladder, in the same direction: a *line*
    # trip is what a relay exists for, a *generator* trip is what makes its signal
    # meaningless. This machine's rotor is now islanded and undriven, so its `δ`
    # freezes while the survivors' common mode drifts on forever at `ω₀·ω_ss`
    # (measured in step 2's V3) — so `|δ_from − δ_to|` across an incident branch
    # grows at the FULL drift rate and crosses any threshold whatever, and the relay
    # would open a line that has carried nothing since the instant this trip zeroed
    # its coupling. Latched, not fired, so `out_of_step_log` still says it never
    # operated.
    bus = eng.model.machines[v].bus
    for r in eng.relays
        (r.from === bus || r.to === bus) && disarm!(r)
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
    # Any out-of-step relay on this branch is latched, whoever opened it — the user
    # here, another relay, or this relay itself firing (M3 step 4). One rule covers
    # all three, which is what makes "a relay logs a trip only if it opened
    # something" structural: reaching the affect at all requires being armed, and
    # an open branch disarms. Placed AFTER the no-op guard above, for `_log_event!`'s
    # reason — this records what changed the system, not what was asked for.
    # At most one relay can match: `NetworkModel` rejects parallel circuits, so a
    # bus pair names one branch, and `_bind_out_of_step` rejects two relays on it.
    # The loop is a scan over a handful of relays, not a case that can hit twice.
    br0 = eng.model.branches[b]
    for r in eng.relays
        r.from === br0.from && r.to === br0.to && disarm!(r)
    end
    # Logged by the branch's own bus names, not the caller's argument order, so two
    # runs that trip the same line agree on what the log says happened.
    br = eng.model.branches[b]
    _log_event!(eng, :trip_line, br.from, br.to)
    SciMLBase.derivative_discontinuity!(eng.integrator, true)
    SciMLBase.auto_dt_reset!(eng.integrator)
    return eng
end
