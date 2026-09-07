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
  - `tier`    — `:swing`, `:classical`, `:sauer_pai` or `:sauer_pai_avr` (see the
                module header).
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
  - `bus_ids` — bus ids in vertex order, so the `:sauer_pai` read-out can name a
                voltage channel `V_B1` exactly as `state_series(::DetailedEngine)`
                does. Empty channel names are not interchangeable: `divergence`
                compares two NamedTuples by key.
  - `mach_bus`— the vertex each machine sits on. `machine_arrays` became
                machine-indexed with a `bus` column in M5 step 1, so "machine `k`
                is at bus `k`" is no longer a fact about the data — it is a fact
                about the fixtures, and this field is what stops the builder from
                relying on it.
  - `X_ls`    — the stator leakage reactance handed to `SauerPaiMachine`, per
                machine. **Not a parameter of our model** (`m5-prestudy.md` §2a):
                it survives nowhere in the degeneration, so it is a constant this
                builder must supply to their component and nothing more. Kept on
                the case because varying it is the tier's free positive control.
  - `mpfx`    — the namespace every machine symbol sits under. `:mach₊` wherever the
                injector IS the machine; `:gen₊mach₊` at `:sauer_pai_avr`, where the
                injector is a `CompositeInjector` holding the machine and its
                exciter and therefore namespaces both. A field rather than a branch
                at each of fourteen call sites.
  - `regulated` — per machine, whether it got an `AVRTypeI` (a live regulator) or an
                `AVRFixed` (a held field voltage). Only the first has a field-voltage
                STATE for the read-out to read.
  - `avr_Ta`  — the amplifier time constant handed to `AVRTypeI`. Our exciter is its
                `Ta → 0` limit (`m5-prestudy.md` §2a), and a limit is not a setting:
                this number is the whole of the difference between the two models,
                so it lives where a test can read it and halve it.
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
    bus_ids::Vector{Symbol}
    mach_bus::Vector{Int}
    X_ls::Vector{Float64}
    mpfx::Symbol
    regulated::Vector{Bool}
    avr_Ta::Float64
end

# Machine symbols under a case's namespace. One place, so a tier that moves the
# namespace moves every reference with it.
_ms(pfx::Symbol, name) = Symbol(pfx, name)
_ms(case::OracleCase, name) = Symbol(case.mpfx, name)

# `AVRTypeI`'s regulator-output limits, set wide and ASSERTED never to bind. They
# are not our `Efd` limits and cannot be made into them (`m5-prestudy.md` §2a):
# they sit on `vr`, one block earlier. Passing ±Inf would put an `Inf` inside their
# anti-windup `ifelse`; a wide finite number the run is checked against says the
# same thing without one.
const _AVR_VR_LIM = 1.0e3
# `Kf = 0` switches the stabiliser off; `Tf` still divides its own derivative, so
# it needs a finite value. Seeded at `v_fb = 0` the state satisfies `Tf·ẋ = -x`
# from rest and never leaves it.
const _AVR_TF = 1.0
# The saturation ceiling, switched off by `Se1 = Se2 = 0`: `EXP_SE` returns `SE1`
# when the two agree, so `vfceil ≡ 0` exactly. `E1`/`E2` are then multiplied by
# nothing and are passed only because they are required parameters.
const _AVR_E1, _AVR_E2 = 1.0, 2.0

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

# The detailed tier's own boundary. The restrictions are NOT the classical tier's
# — a `SauerPaiMachine` needs a terminal bus with a voltage on it, which is what
# `DetailedEngine` gives it — but three of ours are unbuilt work rather than
# physics, and each names the step that lifts it.
#
# `X_ls` is validated here rather than clamped: `γ_d1 = (X″_d − X_ls)/(X′_d − X_ls)`
# divides by `X′_d − X_ls`, so `X_ls = X′_d` is a division by zero inside somebody
# else's component, which surfaces as a NaN trajectory rather than as an error.
function _assert_sauer_pai_tier(net::NetworkModel, X_ls::Vector{Float64})
    # THE TWO REJECTIONS THAT USED TO BE HERE ARE GONE, AND M5 STEP 6 IS WHY. A
    # load is now a `ZIPLoad` injector on its bus and a machine-free bus is now
    # `MTKBus()` with the load as its only injector (or with none at all, for a
    # bare junction) — both expressible all along, and both unbuilt until the step
    # that needed them. Nothing replaces them: the one restriction the mapping does
    # carry is on OUR side (they give `P` and `Q` separate share triples and we give
    # them one), so there is nothing about the model in hand to refuse. It is stated
    # in `_zip_injector` instead.
    for (v, ks) in pairs(net.machines_at_bus)
        length(ks) == 1 || isempty(ks) || throw(ArgumentError(
            "build_oracle(tier = :sauer_pai): bus $(net.buses[v].id) carries " *
            "$(length(ks)) machines. `DetailedEngine` refuses this too " *
            "(`_assert_detailed_tier`), for the same reason and with the same status: " *
            "unbuilt work, not a tier boundary."))
    end
    ma = machine_arrays(net)
    for k in eachindex(X_ls)
        lim = min(ma.Xd′[k], ma.Xq′[k])
        0.0 < X_ls[k] < lim || throw(ArgumentError(
            "build_oracle(tier = :sauer_pai): machine $(net.machines[k].id) would get " *
            "X_ls = $(X_ls[k]) pu against min(X′d, X′q) = $lim. `SauerPaiMachine` " *
            "divides by `X′ − X_ls` in both axes, so this is a division by zero inside " *
            "their component and it would arrive as a NaN trajectory, not as an error. " *
            "X_ls is a constant this builder supplies and not a parameter of our model " *
            "(m5-prestudy.md §2a); pick `X_ls_frac` in (0, 1)."))
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

# The AVR tier's own boundary, on top of `_assert_sauer_pai_tier`.
#
# THE LIMITED EXCITER IS REFUSED, AND THE PLAN SAID SO BEFORE THE CODE DID
# (`m5-plan.md` step 5, `m5-prestudy.md` §2a). `AVRTypeI`'s hard limits sit on the
# REGULATOR OUTPUT `vr`, one block upstream of the field voltage, so our
# `Efd ∈ [Efd_min, Efd_max]` has no counterpart on their side at all. Comparing a
# limited run against it would not be a fidelity measurement, it would be two
# different models — and the gap would be read as a finding. The limit gets its
# check from the closed form in `test/m5_detailed.jl`, which is four orders sharper
# than anything external could be; this tier takes the unlimited exciter only.
function _assert_avr_tier(net::NetworkModel)
    any(m -> m.K_A > 0 && isfinite(m.T_E), net.machines) || throw(ArgumentError(
        "build_oracle(tier = :sauer_pai_avr): no machine carries a live regulator " *
        "(K_A > 0 with a finite T_E). Every machine would compile to an AVRFixed, " *
        "which is what tier = :sauer_pai already is — use that, rather than a case " *
        "whose extra component does nothing."))
    for m in net.machines
        (m.Efd_min == -Inf && m.Efd_max == Inf) || throw(ArgumentError(
            "build_oracle(tier = :sauer_pai_avr): machine $(m.id) carries field-" *
            "voltage limits (Efd_min, Efd_max) = ($(m.Efd_min), $(m.Efd_max)). " *
            "AVRTypeI's limits sit on the REGULATOR OUTPUT vr, not on Efd, so there " *
            "is nothing on their side to match them against — a comparison here " *
            "would be two different models and its gap would be read as a fidelity " *
            "finding. The limited exciter's oracle is the closed form in the core " *
            "suite. This tier takes the unlimited one only."))
        (m.K_A == 0 || isfinite(m.T_E)) || throw(ArgumentError(
            "build_oracle(tier = :sauer_pai_avr): machine $(m.id) has K_A = " *
            "$(m.K_A) with T_E = Inf, which is a field voltage held at its dispatch " *
            "and compiles to AVRFixed. Legal, but say it with K_A = 0 so the model " *
            "and the built case agree about which machines are regulated."))
    end
    return nothing
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
function build_oracle(net::NetworkModel; tier::Symbol = :swing, perturbations = (),
                      X_ls_frac::Real = 0.5, avr_Ta::Real = 0.002)
    tier in (:swing, :classical, :sauer_pai, :sauer_pai_avr) || throw(ArgumentError(
        "build_oracle: tier must be :swing, :classical, :sauer_pai or " *
        ":sauer_pai_avr, got :$tier."))
    _assert_governor_free(net)

    # The two detailed tiers share every mapping but the injector: `:sauer_pai` puts
    # the machine on the bus with its field voltage HELD, `:sauer_pai_avr` wraps it
    # and an exciter in a `CompositeInjector`. Named once, so the difference stays
    # visible only where it is real.
    detailed = tier in (:sauer_pai, :sauer_pai_avr)
    mpfx = tier === :sauer_pai_avr ? :gen₊mach₊ : :mach₊

    ma = machine_arrays(net)
    nm = length(net.machines)
    regulated = Bool[m.K_A > 0 && isfinite(m.T_E) for m in net.machines]
    avr_Ta > 0 || throw(ArgumentError(
        "build_oracle: avr_Ta ($avr_Ta) must be > 0 s — it is AVRTypeI's amplifier " *
        "time constant, written in the MULTIPLIED form Ta·ẋ ~ rhs, so zero is a " *
        "structural change to their model rather than a setting. Our exciter is its " *
        "Ta → 0 LIMIT, and that is the whole reason the two sides differ at all."))
    # `X_ls` is a builder constant, computed before the precondition that checks it.
    X_ls = detailed ?
        Float64[Float64(X_ls_frac) * min(ma.Xd′[k], ma.Xq′[k]) for k in 1:nm] :
        Float64[]

    if detailed
        _assert_sauer_pai_tier(net, X_ls)
        # `:sauer_pai` holds the field voltage at its dispatch, so a machine carrying
        # a regulator there would run with its exciter silently dropped. Core's own
        # guard, called rather than copied.
        tier === :sauer_pai ?
            GridSim._assert_no_regulator(net, "build_oracle(tier = :sauer_pai)") :
            _assert_avr_tier(net)
    else
        # The hole M5 step 2 opened and named: `SwingEngine` and `coi_model` refuse
        # a machine carrying detailed data, and this builder — a THIRD consumer of
        # the same frozen-flux assumption — did not. Core's own guard is called
        # rather than copied, so the three cannot drift apart.
        GridSim._assert_frozen_flux(net, "build_oracle(tier = :$tier)")
        # A LOAD HAS NO HOME AT THE CLASSICAL TIER on either side, and saying so
        # here rather than letting it surface is the M5 step 6 addition. `SwingEngine`
        # refuses a model carrying `Load` outright (a constant-magnitude `E` behind a
        # reactance holds voltage up by construction, so a voltage-dependent draw is
        # not representable), and this builder would otherwise construct a
        # PowerDynamics network with the load quietly absent and only fail several
        # hundred lines later, inside the seed.
        isempty(net.loads) || throw(ArgumentError(
            "build_oracle(tier = :$tier): the model carries $(length(net.loads)) " *
            "load(s) ($(join([l.id for l in net.loads], ", "))). A voltage-dependent " *
            "load is a DETAILED-tier object — `SwingEngine` refuses it too, and for " *
            "the same reason. Use tier = :sauer_pai, where M5 step 6 maps it onto " *
            "`ZIPLoad`. This is a tier boundary, not unbuilt work."))
        # Called explicitly, not left to the `SwingEngine` at the bottom of this
        # function: everything between here and there indexes `machine_arrays` BY
        # VERTEX, which is only legal once one-machine-per-bus holds. Since M5
        # step 1 made `machine_arrays` machine-indexed, that is a fact about the
        # fixtures rather than about the data, and it is now checked before it is
        # used instead of several hundred lines later.
        GridSim._assert_one_machine_per_bus(net, "build_oracle(tier = :$tier)")
        tier === :classical && _assert_radial(net)
    end
    schedule = _schedule(net, perturbations)

    ba = detailed ? branch_topology(net) : branch_arrays(net)
    nb = length(net.buses)
    ids = Symbol[m.id for m in net.machines]
    bus_ids = Symbol[b.id for b in net.buses]
    mach_bus = detailed ? copy(ma.bus) : collect(1:nb)

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
            detailed && throw(ArgumentError(
                "build_oracle(tier = :$tier): TripGenerator has no counterpart to " *
                "compare against — `inject!(::DetailedEngine, ::TripGenerator)` refuses " *
                "by name (a tripped machine turns its bus into a passive algebraic node, " *
                "which is unbuilt at this tier). An oracle case our own engine cannot " *
                "run is worse than no case: it would be read as a fidelity finding."))
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
    angsym = tier === :swing ? _ms(mpfx, "θ") : _ms(mpfx, "δ")
    buses = NetworkDynamics.VertexModel[]
    mach_of_bus = zeros(Int, nb)
    for k in eachindex(mach_bus); mach_of_bus[mach_bus[k]] = k; end
    # Loads by VERTEX (M5 step 6). `load_arrays` is the one place a load converts,
    # on our side and therefore on this one — the module header's rule about the
    # model applied to a unit conversion.
    la = load_arrays(net)
    load_of_bus = zeros(Int, nb)
    for j in eachindex(la.bus); load_of_bus[la.bus[j]] = j; end
    for v in 1:nb
        k = mach_of_bus[v]
        inj = k == 0 ? nothing : if detailed
            # `SauerPaiMachine` is SIXTH order; ours is fourth. The mapping is its
            # `X″ = X′` degeneration, where `γ_1 = 1` and `γ_2 = 0` EXACTLY, and
            # every remaining line collapses onto `m5-prestudy.md` §2 with nothing
            # approximated. Its two sub-transient states survive the degeneration
            # as integrators that drive nothing, which is why they are seeded (so
            # the flat run stays flat) and skipped in a per-state comparison.
            #
            # `T′_d0` and `T′_q0` are passed STRAIGHT THROUGH from our model, `Inf`
            # included. The pre-study flagged that as a risk — they write the
            # MULTIPLIED form `T′·Dt(E′q) ~ rhs`, so `Inf` is `Inf·ẋ ~ finite` —
            # and spike S1 measured it: `mtkcompile` accepts it and freezes `E′q`
            # bit-identically over a horizon on which a finite `T′` moves it by
            # exactly `1/T′`. So the frozen limit is EXACT on both sides and the
            # planned large-but-finite fallback is not needed (m5-context.md D10).
            #
            # `vf_input`/`τ_m_input` default to TRUE and would leave unconnected
            # inputs; `stator_dynamics` already defaults to false. All three are
            # passed explicitly for this file's standing reason: a default is not a
            # guarantee. `vf_input` is the ONE thing `:sauer_pai_avr` changes about
            # the machine — the field voltage becomes an input, and the exciter
            # wired to it is the whole of that tier.
            #
            # `Sn`/`Vn` are deliberately NOT passed. They carry `initf_weak` defaults
            # of `Sbase`/`Vbase`, which is the ratio-of-one this builder wants, and
            # passing them makes them live parameters scaling the terminal equations.
            mach = Library.SauerPaiMachine(; name = :mach,
                vf_input = tier === :sauer_pai_avr,
                τ_m_input = false, stator_dynamics = false,
                R_s = ma.Ra[k], X_d = ma.Xd[k], X_q = ma.Xq[k],
                X′_d = ma.Xd′[k], X′_q = ma.Xq′[k],
                X″_d = ma.Xd′[k], X″_q = ma.Xq′[k], X_ls = X_ls[k],
                T′_d0 = ma.Td0′[k], T′_q0 = ma.Tq0′[k],
                T″_d0 = _SP_TPP, T″_q0 = _SP_TPP,
                H = ma.H[k], D = ma.D[k],
                vf_set = 1.0, τ_m_set = ma.Pm[k])
            tier === :sauer_pai ? mach :
                _with_exciter(mach, ma, k, regulated[k], Float64(avr_Ta))
        elseif tier === :swing
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
        # A BUS IS ITS INJECTORS, and after step 6 there may be nought, one or two
        # of them. `MTKBus(mach, load)` is the shape their own docstring draws, and
        # `MTKBus()` — a bare Kirchhoff node — is what a junction with neither is.
        # Our side has exactly the same three cases: a machine vertex, a machine
        # vertex whose `G`/`B` are non-zero, and a passive vertex.
        j = load_of_bus[v]
        mtk = if inj === nothing
            j == 0 ? MTKBus() : MTKBus(_zip_injector(la, j))
        else
            j == 0 ? MTKBus(inj) : MTKBus(inj, _zip_injector(la, j))
        end
        b = compile_bus(mtk; vidx = v, name = net.buses[v].id)
        if !isempty(gen_trip_times[v])
            psym = tier === :swing ? _ms(mpfx, "Pm") : _ms(mpfx, "τ_m_set")
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
        # The detailed tier needs NO reduction: `SauerPaiMachine` sits behind its
        # reactance on an algebraic terminal bus and so does ours, so both sides
        # are handed the same line — which is also why the meshed ring, invalid
        # for `:classical`, is a valid case here (`m5-prestudy.md` §2a).
        X = tier === :classical ? reduced_line_reactance(net, e) : ba.X[e]
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
    s0 = NWState(nw)
    if detailed
        _seed_sauer_pai!(s0, net, ma, mach_bus, X_ls, mpfx, regulated)
    else
        eng = SwingEngine(net)
        δ0 = collect(current_state(eng).δ)
        for v in 1:nb
            s0.v[v, angsym] = δ0[v]
            s0.v[v, :mach₊ω] = 1.0              # PowerDynamics' ω is absolute pu…
        end                                     # …ours is the deviation from it.
    end

    return OracleCase(net, tier, nw, s0, ids, angsym, copy(ma.H), trips,
                      bus_ids, mach_bus, X_ls, mpfx, regulated, Float64(avr_Ta))
end

"""
    _zip_injector(la, j) -> ZIPLoad

Our `Load` as PowerDynamics' `ZIPLoad` (M5 step 6). **Four convention questions
were settled by reading their source before any band was written down**, which is
the rule M4 step 4 paid for — that step's plan named the wrong component and the
source said so.

**1. The sign is an INJECTION, so a drawing load is NEGATIVE.** Their equations are
`terminal.i_r ~ real(S/u)`, `i_i ~ -imag(S/u)`, i.e. `i = conj(S)/conj(u)` — the
current the component pushes INTO the bus. Their own `Pset` carries `guess = -1`
and their `ConstantYLoad` writes `iload = -Y·u`, so both say the same thing. Ours
is the opposite: `Load.P0` is positive when consuming, and the engine SUBTRACTS
`_load_current` in the Kirchhoff sum. So `Pset = -P`, `Qset = -Q`, and the two
sides then hold the same equation rather than the same numbers.

**2. Their shares normalise where ours do.** `Vrel = |V|/Vset` with `Vset = 1`
gives `P = Pset(KpZ|V|² + KpI|V| + KpC)`, which is our polynomial exactly. Had they
normalised anywhere else, `P₀` and `Pset` would denominate different quantities and
the comparison would be measuring the normalisation rather than the load model.

**3. It carries no state.** Every equation is algebraic, so this injector adds
nothing to seed — which is why `_seed_sauer_pai!` is untouched by this step and
why the band below is not one lag richer the way `AVRTypeI`'s is.

**4. THEIR MODEL IS STRICTLY MORE GENERAL THAN OURS, and the restriction is on our
side.** They carry SEPARATE share triples for `P` and `Q` (`KpZ/KpI/KpC` against
`KqZ/KqI/KqC`); `Load` carries one triple and applies it to both. So the mapping
sends our single triple to both of theirs, and a `ZIPLoad` whose two triples differ
is a model we cannot express — a real restriction, recorded here rather than
discovered as a disagreement later.

`KpC` and `KqC` have DEFAULT EXPRESSIONS on their side (`1 - KpZ - KpI`) that would
compute the right thing. All six are passed anyway, for this file's standing
reason: a default is not a guarantee.
"""
_zip_injector(la, j::Int) = Library.ZIPLoad(;
    name = :load, Vset = 1.0,
    Pset = -la.P[j], Qset = -la.Q[j],
    KpZ = la.a_z[j], KpI = la.a_i[j], KpC = la.a_p[j],
    KqZ = la.a_z[j], KqI = la.a_i[j], KqC = la.a_p[j])

"""
    _with_exciter(mach, ma, k, regulated, Ta) -> CompositeInjector

Wrap `SauerPaiMachine` and its exciter into one injector, the shape PowerDynamics'
own IEEE-9 example uses. `autoconnections` wires them by name: the machine's
`vf_in` finds the exciter's `vf` output, and `AVRTypeI`'s `v_mag` input finds the
machine's `v_mag_out`. Nothing here connects anything by hand.

**`AVRTypeI` degenerates to our exciter, and every setting that makes it do so is
passed explicitly** (`m5-prestudy.md` §2a). With `Kf = 0` (no stabiliser),
`Se1 = Se2 = 0` (no ceiling), `Ke = 1`, `tmeas_lag = false` and `Ta → 0`, their

    Ta·ẋvr    = Ka(vref − vm − v_fb) − vr
    Te·ẋvfout = vr − vfceil − Ke·vfout

collapses to `Te·ẋvfout = Ka(vref − |V|) − vfout`, which is ours line for line with
`T_E = Te` and `K_A = Ka`.

**`Ta → 0` IS THE GAP, and it is a limit rather than a setting.** Their `Ta`
multiplies a derivative, so zero would make that equation algebraic and change the
model's structure rather than its parameters. This comparison is therefore one lag
richer than ours by construction, the difference is first order in `Ta`, and the
check that matters is not the size of the gap but that HALVING `Ta` halves it.

A machine with no regulator (`K_A = 0`, `T_E = Inf`) gets `AVRFixed` instead —
their own held-field component — so every machine at this tier lives under the same
namespace and the read-out needs no per-machine branch to find `δ`.
"""
function _with_exciter(mach, ma, k::Int, regulated::Bool, Ta::Float64)
    avr = regulated ?
        Library.AVRTypeI(; name = :avr, tmeas_lag = false, anti_windup = true,
                         Ka = ma.K_A[k], Ta = Ta, Kf = 0.0, Tf = _AVR_TF,
                         Ke = 1.0, Te = ma.T_E[k],
                         vr_min = -_AVR_VR_LIM, vr_max = _AVR_VR_LIM,
                         E1 = _AVR_E1, E2 = _AVR_E2, Se1 = 0.0, Se2 = 0.0,
                         vref = 1.0) :          # overwritten from our fixpoint
        Library.AVRFixed(; name = :avr, vf_fixed = 1.0)
    return CompositeInjector([mach, avr]; name = :gen)
end

"""
    _seed_sauer_pai!(s0, net, ma, mach_bus, X_ls)

Seed PowerDynamics' six machine states, its two field/torque parameters and the
two bus-voltage states from **our** fixpoint, through a `DetailedEngine` built on
the same model.

This is `build_oracle`'s standing argument applied one tier up: initialisation is
removed as a source of difference, so the band is solver tolerance alone, and the
no-disturbance run becomes an independent check of OUR power flow rather than a
check of theirs.

The two sub-transient states have closed forms at the degeneration
(`m5-prestudy.md` §2a):

    ψ″_d = E′_q − (X′_d − X_ls)·I_d,    ψ″_q = −E′_d − (X′_q − X_ls)·I_q

`I_d`/`I_q` come from `GridSim._stator` — the very function the engine's own
right-hand side calls, reached through its module rather than re-derived here.
That is deliberate, and it is the module header's rule about the model applied to
an equation: the rotor-frame rotation and the stator inversion exist ONCE. A
second copy in this file would be a parallel hand-maintained derivation of the
one piece of algebra a convention error hides in most easily.
"""
function _seed_sauer_pai!(s0, net::NetworkModel, ma, mach_bus::Vector{Int},
                          X_ls::Vector{Float64}, mpfx::Symbol, regulated::Vector{Bool})
    apfx = Symbol(replace(String(mpfx), "mach₊" => "avr₊"))
    eng = init!(DetailedEngine, net)
    st = current_state(eng)
    u = eng.integrator.u
    for k in eachindex(mach_bus)
        v = mach_bus[k]
        Vre = u[eng.Vre_idx[v]]
        Vim = u[eng.Vim_idx[v]]
        δ, E′q, E′d = st.δ[k], st.E′q[k], st.E′d[k]
        Id, Iq, _, _, _ = GridSim._stator(Vre, Vim, δ, E′q, E′d,
                                          ma.Ra[k], ma.Xd′[k], ma.Xq′[k], 1.0)
        s0.v[v, _ms(mpfx, "δ")]    = δ
        s0.v[v, _ms(mpfx, "ω")]    = 1.0 + st.ω[k]  # theirs is absolute pu, ours the deviation
        s0.v[v, _ms(mpfx, "E′_q")] = E′q
        s0.v[v, _ms(mpfx, "E′_d")] = E′d
        s0.v[v, _ms(mpfx, "ψ″_d")] =  E′q - (ma.Xd′[k] - X_ls[k]) * Id
        s0.v[v, _ms(mpfx, "ψ″_q")] = -E′d - (ma.Xq′[k] - X_ls[k]) * Iq
        # Their field voltage and mechanical input are PARAMETERS at this tier,
        # exactly as ours are until plan step 5 gives the excitation a regulator.
        # Both are read off our engine rather than recomputed, so the two sides
        # cannot come to disagree about what "held at its pre-disturbance value"
        # means — and `Pm` in particular is the POWER FLOW's dispatch, which is not
        # `Machine.P0` on any model carrying a load.
        Efd = eng.integrator.u[eng.Efd_idx[k]]
        s0.p.v[v, _ms(mpfx, "τ_m_set")] = eng.params[eng.Pm_pidx[k]]
        if mpfx === :mach₊
            s0.p.v[v, _ms(mpfx, "vf_set")] = Efd
        elseif regulated[k]
            # THE EXCITER, SEEDED AT REST FROM OUR OWN EQUILIBRIUM. Their `vfout`
            # is the field voltage and their `vr` the regulator output; with
            # `Ke = 1` and no ceiling their field equation is
            # `Te·ẋvfout = vr − vfout`, so both sit at our `Efd`. `v_fb` is the
            # stabiliser feedback and is zero because `Kf = 0` makes it a state
            # that decays to zero and stays there once started at it.
            #
            # `vref` is OUR derived setpoint, not one of theirs: the whole reason
            # `Vref` is derived rather than supplied on our side is that a
            # setpoint which does not match the dispatch makes the flat run a
            # startup transient, and handing them a different one would put that
            # transient on one side only.
            s0.p.v[v, _ms(apfx, "vref")] = eng.params[eng.Vref_pidx[k]]
            s0.v[v, _ms(apfx, "vfout")]  = Efd
            s0.v[v, _ms(apfx, "vr")]     = Efd
            s0.v[v, _ms(apfx, "v_fb")]   = 0.0
        else
            s0.p.v[v, _ms(apfx, "vf_fixed")] = Efd
        end
    end
    # The bus voltages are STATES on their side too (`busbar₊u_r`/`u_i`, with a
    # zero mass matrix), not observables — measured, not assumed. So they are
    # seeded here, and in the read-out they come from stored samples rather than
    # from a reconstructed observable.
    for v in eachindex(net.buses)
        s0.v[v, :busbar₊u_r] = u[eng.Vre_idx[v]]
        s0.v[v, :busbar₊u_i] = u[eng.Vim_idx[v]]
    end
    return s0
end

# Their two sub-transient time constants. They sit on a pair of states the
# degeneration DECOUPLES — `1 − γ_1 = 0` removes them from the flux linkages and
# `γ_2 = 0` from the `E′` equations — so this number reaches no comparison channel.
# The test that says so does not argue it: it seeds those two states deliberately
# wrong and requires every channel not to move.
const _SP_TPP = 0.03

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

# Which stored row of the solution belongs to each requested output time.
#
# THIS IS NOT A FORMALITY, AND WRITING IT IS WHAT FOUND THE AMBIGUITY IT RESOLVES.
# The solver is handed the output grid as its own `saveat`, so every requested
# time is a stored sample and nothing is ever reconstructed from an interpolant
# (M4 step 3: a callback retroactively bends the interpolant of the step it
# ended). But a `PresetTimeComponentCallback` firing AT a grid point makes the
# solver store that instant TWICE — once before the affect and once after — so
# `sol.t` came back with 252 rows against a 251-point grid, and a read that just
# asks for "the value at t" silently gets one of the two without saying which.
#
# The FIRST row at a repeated instant is the pre-event one, and that is the one
# taken here, because it is the convention the GridSim side already keeps: its
# playback driver records the sample at an event instant as the pre-event state.
# Comparing a pre-event sample against a post-event one puts the entire size of
# the disturbance into a single point of the gap.
#
# Anything else — a missing grid point, a stored time nobody asked for — is
# refused rather than resampled: `divergence` refuses two grids for the same
# reason, and there is no interpolant left to resample with.
function _sample_rows(ts::AbstractVector, grid::AbstractVector)
    rows = Vector{Int}(undef, length(grid))
    j = 1
    for (i, g) in pairs(grid)
        j <= length(ts) || throw(ErrorException(
            "oracle_solve: the solution ends at t = $(ts[end]) but the output grid " *
            "asks for t = $g. The solver was handed this grid as its own `saveat`, " *
            "so a missing sample is a solve that stopped early, not a grid to " *
            "interpolate onto."))
        ts[j] == g || throw(ErrorException(
            "oracle_solve: expected the next stored sample to be t = $g but it is " *
            "t = $(ts[j]). The read-out indexes stored samples deliberately; a " *
            "stored time nobody asked for means the solve saved somewhere else " *
            "(a `tstop` that also saves, or `save_everystep`), and resampling onto " *
            "the requested grid is exactly what `divergence` refuses to do."))
        rows[i] = j                              # the FIRST row: pre-event, see above
        while j <= length(ts) && ts[j] == g
            j += 1
        end
    end
    j > length(ts) || throw(ErrorException(
        "oracle_solve: $(length(ts) - j + 1) stored samples lie beyond the end of " *
        "the output grid. Every stored sample should correspond to a requested time."))
    return rows
end

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
                      reltol::Real = 1e-9, abstol::Real = 1e-9,
                      adaptive::Bool = true, dt::Real = 0.0)
    grid = collect(saveat)
    isempty(grid) && throw(ArgumentError("oracle_solve: saveat grid is empty."))
    tstops = Float64[t for (t, _) in case.trips]
    prob = ODEProblem(case.nw, case.s0, (Float64(tspan[1]), Float64(tspan[2])))
    # `tstops` are the EVENT instants only, never the output grid. Landing the
    # solver on every output point would truncate its own step-size control once
    # per sample and quietly make this a different numerical path from the one
    # the comparison claims to be checking — the same argument `playback.jl`
    # makes for not driving `step!(integ, dt, true)` in playback.
    # `adaptive = false` with an explicit `dt` exists for ONE reason and the suite
    # does not use it: it is how M5 step 3's F4 was measured. The two "reaches
    # nothing" controls are bands rather than `===`, and the question was whether
    # bit-identity comes back once the adaptive error norm is taken out of it.
    # It does not — the deltas tighten from ~1e-10 to ~1e-15 and stop there,
    # because a decoupled differential state still sits in the implicit solver's
    # Newton system. Kept so the measurement can be re-run, documented so nobody
    # reaches for it without knowing what it answered.
    sol = adaptive ?
        solve(prob, Rodas5P(); reltol = reltol, abstol = abstol,
              saveat = grid, tstops = tstops) :
        solve(prob, Rodas5P(); adaptive = false, dt = Float64(dt),
              saveat = grid, tstops = tstops)

    # EVERY CHANNEL BELOW IS READ FROM A STORED SAMPLE, never from `sol(t)`. M4
    # step 3's finding is that a callback retroactively bends the interpolant of
    # the step it ended, and every case this function builds may carry one.
    rows = _sample_rows(sol.t, grid)
    take(v) = [v[r] for r in rows]

    nm = length(case.ids)
    mb = case.mach_bus
    δ = [take(sol[VIndex(mb[k], case.angsym)]) for k in 1:nm]
    ω = [take(sol[VIndex(mb[k], _ms(case, "ω"))]) .- 1.0 for k in 1:nm]

    # The live COI weights, sample by sample. `<` and not `≤`: the sample AT an
    # event instant is the pre-event one on our side too.
    f0 = case.net.f0
    δ_coi = Vector{Float64}(undef, length(grid))
    f_coi = Vector{Float64}(undef, length(grid))
    w = copy(case.H)
    mach_of_bus = Dict(mb[k] => k for k in 1:nm)
    for (i, t) in pairs(grid)
        for (t_ev, v) in case.trips
            t_ev < t && (w[mach_of_bus[v]] = 0.0)
        end
        Σw = sum(w)
        if Σw > 0
            δ_coi[i] = sum(w[k] * δ[k][i] for k in 1:nm) / Σw
            f_coi[i] = f0 * (1 + sum(w[k] * ω[k][i] for k in 1:nm) / Σw)
        else
            δ_coi[i] = NaN
            f_coi[i] = NaN
        end
    end

    # The channel set is `state_series`' for the tier being compared against — the
    # SAME NAMES IN THE SAME ORDER, because `divergence` matches two NamedTuples by
    # key and a channel that exists on one side only is a silent omission, not an
    # error. `:swing`/`:classical` mirror `state_series(::SwingEngine)`;
    # `:sauer_pai` mirrors `state_series(::DetailedEngine)`, which additionally
    # carries the two transient flux states per machine and a voltage magnitude per
    # bus. The flux states are frozen at step 3 and the voltage is the channel the
    # stator-ω residual actually lands in.
    names = Symbol[:t]
    vals  = Any[grid]
    for k in 1:nm; push!(names, Symbol(:δ_, case.ids[k])); push!(vals, δ[k]); end
    for k in 1:nm; push!(names, Symbol(:ω_, case.ids[k])); push!(vals, ω[k]); end
    if case.tier in (:sauer_pai, :sauer_pai_avr)
        for k in 1:nm
            push!(names, Symbol("E′q_", case.ids[k]))
            push!(vals, take(sol[VIndex(mb[k], _ms(case, "E′_q"))]))
        end
        for k in 1:nm
            push!(names, Symbol("E′d_", case.ids[k]))
            push!(vals, take(sol[VIndex(mb[k], _ms(case, "E′_d"))]))
        end
        # THE FIELD VOLTAGE. At `:sauer_pai` it is a held PARAMETER on their side
        # and a state with a zero derivative on ours, so this channel is constant on
        # both and carries no information at that tier at all — it exists so the two
        # key sets match, which `divergence` and the suite's `keys(o) == keys(t)`
        # both require, and so that `:sauer_pai_avr` has somewhere to put the one
        # comparison it is for. Said out loud rather than left to be discovered.
        apfx = Symbol(replace(String(case.mpfx), "mach₊" => "avr₊"))
        for k in 1:nm
            push!(names, Symbol("Efd_", case.ids[k]))
            push!(vals, case.tier === :sauer_pai ?
                fill(case.s0.p.v[mb[k], _ms(case, "vf_set")], length(grid)) :
                (case.regulated[k] ?
                 take(sol[VIndex(mb[k], Symbol(apfx, "vfout"))]) :
                 fill(case.s0.p.v[mb[k], Symbol(apfx, "vf_fixed")], length(grid))))
        end
        for v in eachindex(case.bus_ids)
            ur = take(sol[VIndex(v, :busbar₊u_r)])
            ui = take(sol[VIndex(v, :busbar₊u_i)])
            push!(names, Symbol(:V_, case.bus_ids[v]))
            push!(vals, [hypot(ur[i], ui[i]) for i in eachindex(grid)])
        end
    end
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
    k = _machine_vertex(case.net, id)
    psym = case.tier === :swing ? _ms(case, "Pm") : _ms(case, "τ_m_set")
    case.s0.p.v[case.mach_bus[k], psym] = Float64(Pm_pu)
    return case
end
