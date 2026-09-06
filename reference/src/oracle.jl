# The `NetworkModel → PowerDynamics` builder and the run that comes out of it.
#
# The whole file is one claim: a PowerDynamics case for one of our models is
# DERIVED, and the derivation is short enough to read. Everything long in here is
# a precondition or a comment about why a mapping is what it is.

"""
    OracleCase

A built PowerDynamics case, plus the few things needed to read it back in our own
terms. Concrete-typed fields (SPEC §4).

  - `net`     — the canonical model it was compiled from.
  - `tier`    — `:swing` or `:classical` (see the module header).
  - `nw`      — the PowerDynamics `Network`.
  - `s0`      — its initial state, seeded from **our** fixpoint (below).
  - `ids`     — machine ids in bus order, so a channel can be named `ω_G1`.
  - `angsym`  — the tier's rotor-angle symbol (`:mach₊θ` / `:mach₊δ`).
  - `H`       — **our** inertia weights on the system base. The centre-of-inertia
                read-out is computed with these and never with a weighting of
                PowerDynamics' own, or the comparison would be one aggregation
                against a different aggregation rather than one implementation
                against another.
  - `trips`   — scheduled generator trips as `time => vertex`, so the read-out can
                drop a tripped machine from the aggregate at the same instant our
                engine does.
"""
struct OracleCase
    net::NetworkModel
    tier::Symbol
    nw::NetworkDynamics.Network
    s0::NetworkDynamics.NWState
    ids::Vector{Symbol}
    angsym::Symbol
    H::Vector{Float64}
    trips::Vector{Pair{Float64,Int}}
end

"""
    reduced_line_reactance(net::NetworkModel, e::Integer) -> Float64

The branch reactance a `ClassicalMachine` pair needs, on the system base:

    X_line = X_ij − X′d,ᵢ − X′d,ⱼ

**This is the number that decides whether the `:classical` comparison means
anything.** Our tier puts `E′` at the bus and folds nothing in, so its coupling
denominator is `X_ij` outright. PowerDynamics' machine sits *behind* `X′d` on an
algebraic terminal bus, so its internal-node-to-internal-node reactance is
`X′d,ᵢ + X_line + X′d,ⱼ`. Handing it `X_ij` unreduced makes that sum
`X_ij + X′d,ᵢ + X′d,ⱼ` — on `two_machine_system()` a 0.425 pu coupling path where
ours is 0.25, i.e. a synchronising coupling 41 % too weak — and the resulting gap
is pure modelling error wearing a fidelity finding's clothes.

The two formulations coincide **only on a radial pair**. A machine of branch
degree 2 has one internal reactance to spend across two lines, and subtracting it
from each double-counts it; that is the same argument point 2 of the tier note in
`src/model/network_model.jl` makes against folding `X′d` INTO the coupling, seen
from the other side. `build_oracle(:classical)` enforces the degree and the
positivity rather than documenting them — see `_assert_radial`.
"""
function reduced_line_reactance(net::NetworkModel, e::Integer)
    ma = machine_arrays(net)
    ba = branch_arrays(net)
    return ba.X[e] - ma.Xd′[ba.src[e]] - ma.Xd′[ba.dst[e]]
end

# The tier boundary of the `:classical` mapping, enforced instead of documented.
# A comment saying the ring is not a valid oracle case is exactly the thing that
# gets stepped over later; a thrown error is not.
function _assert_radial(net::NetworkModel)
    ma = machine_arrays(net)
    ba = branch_arrays(net)
    degree = zeros(Int, length(net.buses))
    for e in eachindex(ba.src)
        degree[ba.src[e]] += 1
        degree[ba.dst[e]] += 1
    end
    for (v, d) in pairs(degree)
        d == 1 || throw(ArgumentError(
            "build_oracle(tier = :classical): machine $(net.machines[v].id) has branch " *
            "degree $d. `E′ behind X′d` and `E′ at the bus` coincide only on a radial " *
            "pair — a machine on two lines has one internal reactance to spend across " *
            "both, and the line reduction would count it twice. Use tier = :swing, " *
            "which needs no reduction and is valid on any topology."))
    end
    for e in eachindex(ba.src)
        Xr = reduced_line_reactance(net, e)
        Xr > 0 || throw(ArgumentError(
            "build_oracle(tier = :classical): branch $(net.branches[e].id) reduces to " *
            "X_line = $Xr pu ≤ 0 (X = $(ba.X[e]), X′d = $(ma.Xd′[ba.src[e]]) and " *
            "$(ma.Xd′[ba.dst[e]]) on the system base). The machines' internal reactances " *
            "exceed the tie, so there is no line left to put between them and the " *
            "reduction does not exist for this model."))
    end
    return nothing
end

# `Swing` and `ClassicalMachine` both carry (δ, ω) and nothing else. M3's governor
# state `ΔPm` has no counterpart in either, so a governed model is not expressible
# here — and a silently-ungoverned oracle would look like a physics disagreement.
# Rejected loudly, on the model, where the data lives.
function _assert_governor_free(net::NetworkModel)
    ma = machine_arrays(net)
    for (v, m) in pairs(net.machines)
        ma.invR[v] == 0 || throw(ArgumentError(
            "build_oracle: machine $(m.id) has droop R = $(m.R). PowerDynamics' Swing " *
            "and ClassicalMachine carry (δ, ω) only — there is no `ΔPm` state to map " *
            "M3's governor onto, and an ungoverned oracle would read as a physics " *
            "disagreement. Use a governor-free model (R = Inf), or attach a " *
            "PowerDynamics governor deliberately and re-derive the band."))
        ma.headroom[v] == 0 || throw(ArgumentError(
            "build_oracle: machine $(m.id) has headroom $(ma.headroom[v]) pu " *
            "(Pmax = $(m.Pmax) MW, P0 = $(m.P0) MW). Reserve is only meaningful with " *
            "a governor to command it, which this tier has not got."))
    end
    return nothing
end

# The scheduled-event schedule, validated in the same shape `solve!` takes it.
# Only SCHEDULED events exist here: state-triggered protection (M3's shed ladders
# and out-of-step relays) is an engine construction argument, not a property of
# the model, so it cannot reach this builder — and it must not, because a relay
# fires at an instant nobody can know in advance and there is nothing to schedule.
function _schedule(net::NetworkModel, perturbations)
    out = Tuple{Float64,PerturbationEvent}[]
    for p in perturbations
        p isa Pair || throw(ArgumentError(
            "build_oracle: perturbations must be `time => event` pairs, got $(typeof(p))"))
        t, ev = p
        ev isa PerturbationEvent || throw(ArgumentError(
            "build_oracle: perturbations must be `time => event` pairs, but the value " *
            "of one is a $(typeof(ev))"))
        isfinite(t) || throw(ArgumentError("build_oracle: event time must be finite, got $t"))
        ev isa Union{TripLine,TripGenerator} || throw(ArgumentError(
            "build_oracle: $(typeof(ev)) has no PowerDynamics mapping. The oracle " *
            "maps TripLine (the pi-line's `active` parameter) and TripGenerator " *
            "(mechanical power to zero plus every incident line deactivated, which " *
            "is what `inject!(::SwingEngine, ::TripGenerator)` does)."))
        push!(out, (Float64(t), ev))
    end
    return out
end

"""
    build_oracle(net::NetworkModel; tier = :swing, perturbations = ()) -> OracleCase

Compile `net` into a PowerDynamics case. See the module header for what the two
tiers are for; `reduced_line_reactance` for the one number `:classical` turns on.

**The initial state is OUR fixpoint, not PowerDynamics' power flow**, and that is
a deliberate choice with two consequences worth having in front of you.

  - It removes initialisation as a source of difference, so the agreement band
    can be derived from solver tolerance alone rather than carrying an
    initialisation offset nobody has measured.
  - It turns the no-disturbance run into an **independent check of
    `find_fixpoint`**: PowerDynamics reaches equilibrium through complex bus
    voltages, a pi-line admittance and a current balance, where ours is a
    closed-form `K·sin(δᵢ−δⱼ)`. If our steady state is not a steady state of that
    formulation, a flat run says so immediately.

    What that does *not* check is the per-unit conversion — this builder hands
    PowerDynamics the already-converted `machine_arrays` numbers, so both sides
    fork downstream of it. See the module header.

`perturbations` takes the same `time => event` pairs `solve!` does, and the two
supported events map to parameter changes on the PowerDynamics side exactly as
`inject!` makes them on ours: `TripLine` deactivates the pi-line; `TripGenerator`
zeroes the machine's mechanical power **and** deactivates every incident line,
because that is what zeroing `Pm` and every incident `K` amounts to.
"""
function build_oracle(net::NetworkModel; tier::Symbol = :swing, perturbations = ())
    tier in (:swing, :classical) || throw(ArgumentError(
        "build_oracle: tier must be :swing or :classical, got :$tier."))
    _assert_governor_free(net)
    tier === :classical && _assert_radial(net)
    schedule = _schedule(net, perturbations)

    ma = machine_arrays(net)
    ba = branch_arrays(net)
    nb = length(net.buses)
    ids = Symbol[m.id for m in net.machines]

    # PowerDynamics' bases are process-global and are read at CONSTRUCTION time
    # (see the module header). Set from the model in hand, on every call, right
    # before anything is built.
    set_Sbase!(net.S_base)
    set_fbase!(net.f0)

    # --- which scheduled events touch which component ------------------------
    # Resolved before the components are built, because a callback has to be
    # attached to the model object at `compile_*` time.
    trips = Pair{Float64,Int}[]                        # time => vertex (generator)
    gen_trip_times = [Float64[] for _ in 1:nb]
    line_off_times = [Float64[] for _ in eachindex(net.branches)]
    for (t, ev) in schedule
        if ev isa TripLine
            e = _branch_between(net, ev.from, ev.to)
            push!(line_off_times[e], t)
        else                                            # TripGenerator
            v = _machine_vertex(net, ev.id)
            push!(gen_trip_times[v], t)
            push!(trips, t => v)
            for e in eachindex(ba.src)                  # …and every incident line
                (ba.src[e] == v || ba.dst[e] == v) && push!(line_off_times[e], t)
            end
        end
    end
    sort!(trips; by = first)

    # --- vertices ------------------------------------------------------------
    angsym = tier === :swing ? :mach₊θ : :mach₊δ
    buses = NetworkDynamics.VertexModel[]
    for v in 1:nb
        inj = if tier === :swing
            # `M = 2H`, `D·(ω − ωset)` with `ωset = 1` and `ω` per-unit, and
            # `dθ/dt = ωbase·(ω − ωframe)` with `ωframe = 1`. Substituting
            # `ω_PD − 1 = ω_ours` gives `swing_vertex!` line for line, INCLUDING
            # the constant voltage magnitude at the bus — which is the one thing
            # our tier note says our model does and `E′ behind X′d` does not.
            Library.Swing(; name = :mach, V = ma.E[v], M = 2 * ma.H[v],
                            D = ma.D[v], Pm = ma.Pm[v])
        else
            # `vf_set` IS the internal EMF magnitude: with `R_s = 0` the machine's
            # own algebraic pair collapses to `V_q + X′_d·I_d = vf_set` on the q
            # axis, so it takes our `E′` directly rather than through a terminal
            # voltage setpoint. `R_s = 0` is not a default we are trusting — the
            # classical tier is lossless by construction and a stator resistance
            # would put losses into a network whose `Σ P0 = 0` balance forbids
            # them.
            Library.ClassicalMachine(; name = :mach, τ_m_input = false, R_s = 0.0,
                                       X′_d = ma.Xd′[v], H = ma.H[v], D = ma.D[v],
                                       vf_set = ma.E[v], τ_m_set = ma.Pm[v])
        end
        b = compile_bus(MTKBus(inj); vidx = v, name = net.buses[v].id)
        if !isempty(gen_trip_times[v])
            psym = tier === :swing ? :mach₊Pm : :mach₊τ_m_set
            aff = ComponentAffect([], [psym]) do u, p, ctx
                p[psym] = 0.0
            end
            set_callback!(b, PresetTimeComponentCallback(gen_trip_times[v], aff))
        end
        push!(buses, b)
    end

    # --- edges ---------------------------------------------------------------
    # `R` and all four shunt terms are passed explicitly as zero rather than left
    # to PowerDynamics' defaults (which are zero today). The classical tier's
    # network is lossless — that is what makes `Σ P0 = 0` exact and the model
    # constructor's balance check meaningful — and a shunt susceptance would move
    # the equilibrium our fixpoint was solved for. A default is not a guarantee.
    lines = NetworkDynamics.EdgeModel[]
    for e in eachindex(ba.src)
        X = tier === :swing ? ba.X[e] : reduced_line_reactance(net, e)
        pl = Library.PiLine(; name = :pibranch, R = 0.0, X = X,
                              G_src = 0.0, B_src = 0.0, G_dst = 0.0, B_dst = 0.0)
        l = compile_line(MTKLine(pl); src = ba.src[e], dst = ba.dst[e],
                         name = net.branches[e].id)
        if !isempty(line_off_times[e])
            aff = ComponentAffect([], [:pibranch₊active]) do u, p, ctx
                p[:pibranch₊active] = 0.0
            end
            set_callback!(l, PresetTimeComponentCallback(sort(line_off_times[e]), aff))
        end
        push!(lines, l)
    end

    nw = Network(buses, lines; warn_order = false)

    # --- the initial state: ours ---------------------------------------------
    eng = SwingEngine(net)
    δ0 = collect(current_state(eng).δ)
    s0 = NWState(nw)
    for v in 1:nb
        s0.v[v, angsym] = δ0[v]
        s0.v[v, :mach₊ω] = 1.0                  # PowerDynamics' ω is absolute pu…
    end                                          # …ours is the deviation from it.

    return OracleCase(net, tier, nw, s0, ids, angsym, copy(ma.H), trips)
end

# Branch index for an unordered bus pair, with the same message shape
# `inject!(::SwingEngine, ::TripLine)` uses.
function _branch_between(net::NetworkModel, from::Symbol, to::Symbol)
    for (e, br) in pairs(net.branches)
        (br.from === from && br.to === to) && return e
        (br.from === to && br.to === from) && return e
    end
    throw(ArgumentError("build_oracle: no branch between :$from and :$to."))
end

function _machine_vertex(net::NetworkModel, id::Symbol)
    v = findfirst(m -> m.id === id, net.machines)
    v === nothing && throw(ArgumentError("build_oracle: no machine :$id."))
    return v
end

"""
    oracle_band(a_coarse, a_fine, b_coarse, b_fine;
                channel = system_frequency, factor = 3) -> Float64

The agreement band for a **cross-implementation** comparison. One line, because
**the derivation moved into core as `convergence_band` in M5 step 2** — read it
there. Nothing about it was specific to PowerDynamics, and the detailed tier's
internal comparison against `SwingEngine` is the same explicit-against-stiff
shape, so a second copy here would have been the drift hazard this package's own
header warns about.

What stays here is what the derivation cannot carry: **the measurements this pair
produced.** On `three_machine_ring()` with `TripLine(:B3, :B1)` the cross gap comes
out at **0.30–0.33 of this band** at `reltol` = 1e-3, 1e-5 and 1e-7 alike. That it
sits below even `factor = 1` is itself informative: the two errors partly cancel,
so the sum overestimates their difference. And one asymmetry the same numbers
expose, which belongs in the record rather than in a footnote: at matched tolerance
**PowerDynamics is the less accurate of the two** — `err_theirs / err_ours` is 3.5
at 1e-3 and 18 at 1e-7. The oracle is a floor, not a ceiling (D7), and here that is
a measurement rather than a slogan.
"""
oracle_band(a_coarse::NamedTuple, a_fine::NamedTuple,
            b_coarse::NamedTuple, b_fine::NamedTuple;
            channel = system_frequency, factor::Real = 3) =
    GridSim.convergence_band(a_coarse, a_fine, b_coarse, b_fine;
                             channel = channel, factor = factor)

"""
    oracle_solve(case::OracleCase, tspan; saveat, reltol = 1e-9, abstol = 1e-9)

Run the case and return the trajectory **in the shape `state_series(::SwingEngine)`
returns** — `(; t, δ_<id>…, ω_<id>…, δ_coi, f_coi)` — so `divergence` (M4 step 2)
applies across the two sides with no adapter and no resampling.

`saveat` must be the **same explicit grid** the GridSim side was solved on. That
is not a convenience: step 2 established that there is no interpolant left after a
solve to resample with (D10), and straight-lining between decimated samples was
measured at 33.7× the band. `divergence` refuses two grids for that reason; this
function is what makes handing it one possible.

Unit conventions, converted here and nowhere else:

  - PowerDynamics' `ω` is an **absolute** per-unit speed sitting at 1 in steady
    state; ours is the **deviation**. `ω_ours = ω_PD − 1`.
  - `f_coi` is the inertia-weighted mean of those deviations using **our** `H`
    weights (`case.H`), then `f0·(1 + ω_coi)`. Using PowerDynamics' own weighting
    would compare two aggregations rather than two implementations.
  - A machine tripped by a scheduled `TripGenerator` leaves the aggregate at the
    instant it trips, exactly as `inject!` drops its weight — and the sample **at**
    the event instant is the pre-event one, which is the ordering the playback
    driver already asserts from outside itself.
"""
function oracle_solve(case::OracleCase, tspan; saveat,
                      reltol::Real = 1e-9, abstol::Real = 1e-9)
    grid = collect(saveat)
    isempty(grid) && throw(ArgumentError("oracle_solve: saveat grid is empty."))
    tstops = Float64[t for (t, _) in case.trips]
    prob = ODEProblem(case.nw, case.s0, (Float64(tspan[1]), Float64(tspan[2])))
    # `tstops` are the EVENT instants only, never the output grid. Landing the
    # solver on every output point would truncate its own step-size control once
    # per sample and quietly make this a different numerical path from the one
    # the comparison claims to be checking — the same argument `playback.jl`
    # makes for not driving `step!(integ, dt, true)` in playback.
    sol = solve(prob, Rodas5P(); reltol = reltol, abstol = abstol,
                saveat = grid, tstops = tstops)

    nb = length(case.ids)
    δ = [[sol(t; idxs = VIndex(v, case.angsym)) for t in grid] for v in 1:nb]
    ω = [[sol(t; idxs = VIndex(v, :mach₊ω)) - 1.0 for t in grid] for v in 1:nb]

    # The live COI weights, sample by sample. `<` and not `≤`: the sample AT an
    # event instant is the pre-event one on our side too.
    f0 = case.net.f0
    δ_coi = Vector{Float64}(undef, length(grid))
    f_coi = Vector{Float64}(undef, length(grid))
    w = copy(case.H)
    for (k, t) in pairs(grid)
        for (t_ev, v) in case.trips
            t_ev < t && (w[v] = 0.0)
        end
        Σw = sum(w)
        if Σw > 0
            δ_coi[k] = sum(w[v] * δ[v][k] for v in 1:nb) / Σw
            f_coi[k] = f0 * (1 + sum(w[v] * ω[v][k] for v in 1:nb) / Σw)
        else
            δ_coi[k] = NaN
            f_coi[k] = NaN
        end
    end

    names = Symbol[:t]
    vals  = Any[grid]
    for v in 1:nb; push!(names, Symbol(:δ_, case.ids[v])); push!(vals, δ[v]); end
    for v in 1:nb; push!(names, Symbol(:ω_, case.ids[v])); push!(vals, ω[v]); end
    push!(names, :δ_coi); push!(vals, δ_coi)
    push!(names, :f_coi); push!(vals, f_coi)
    return NamedTuple{Tuple(names)}(Tuple(vals))
end

"""
    set_mechanical_power!(case::OracleCase, id::Symbol, Pm_pu::Real) -> OracleCase

Write one machine's mechanical power (pu on the system base) into the case's
initial parameter vector, **before** it is solved.

This is the oracle's counterpart to writing `eng.params[eng.Pm_pidx[v]]` on the
GridSim side, and it exists so the two writes cannot come to disagree about which
symbol carries mechanical power in which tier (`:mach₊Pm` for `Swing`, a
mechanical *torque* setpoint `:mach₊τ_m_set` for `ClassicalMachine` — and that
difference is not cosmetic, it is the whole of D14).

**Why a parameter and not a state.** A mechanical-power step is the one
disturbance that is bus-local, works on any topology, and needs no new event
type: both sides start from the *unmodified* fixpoint and differ only in a
parameter. Seeding a non-equilibrium state instead would mean a second way to
place an engine's initial condition — the shape D4 and D8 already forbid — and
would leave the recorder's first sample describing the state before the seed.
Parameters are the sanctioned perturbation channel (SPEC §6).

At `t = 0` and `ω = 1` a per-unit torque and a per-unit power are the same
number, so the same value goes to both tiers; they part company only once `ω`
moves, which is exactly the effect being measured.
"""
function set_mechanical_power!(case::OracleCase, id::Symbol, Pm_pu::Real)
    v = _machine_vertex(case.net, id)
    psym = case.tier === :swing ? :mach₊Pm : :mach₊τ_m_set
    case.s0.p.v[v, psym] = Float64(Pm_pu)
    return case
end
