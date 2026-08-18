using GridSim
using Test
import CommonSolve
import OrdinaryDiffEq
import SciMLBase
import Observables          # the core→UI seam; also the positive control for the no-Makie test
import Pkg                  # to inspect the dependency closure (no-Makie invariant)

# The Iberian scenario script is a DELIVERABLE, so its claims are asserted below.
# Included as a module so the scenario data stays single-sourced (no second copy of
# the event times living in the test file) without leaking the script's constants
# into the suite's namespace. The script guards `main()` behind PROGRAM_FILE, so
# including it defines everything and runs nothing.
module Iberia
include(joinpath(@__DIR__, "..", "scripts", "iberia_2025_04_28.jl"))
end

# Scaffold-level tests: they exercise the durable contracts (data model, events,
# engine interface) that ship at initialization. The physics validation for M1
# (closed-form initial RoCoF and settling deviation, docs/SPEC.md §7.6) is added
# alongside FrequencyResponseEngine in the M1 code batch.

@testset "GridSim scaffold" begin

    @testset "domain model" begin
        sys = example_system()
        @test sys isa SystemModel
        @test sys.S_base == 550.0
        @test sys.f0 == 50.0
        @test length(sys.units) == 4
        @test all(u -> u isa GeneratingUnit, sys.units)
        # headroom is non-negative for every unit (Pmax ≥ P0)
        @test all(u -> u.Pmax ≥ u.P0, sys.units)
        # ids are unique
        @test length(unique(u.id for u in sys.units)) == length(sys.units)
    end

    @testset "events" begin
        @test TripGenerator(:G1) isa PerturbationEvent
        @test TripGenerator(:G1).id === :G1
        @test StepLoad(-0.1) isa PerturbationEvent
        @test StepLoad(-0.1).ΔP_pu == -0.1
    end

    @testset "engine interface exists" begin
        @test SimulationEngine isa Type
        # the interface verbs are defined as generic functions (no methods yet)
        for f in (init!, step!, solve!, current_state, state_series, inject!)
            @test f isa Function
        end
    end

    @testset "step!/solve! share CommonSolve's generic (no collision)" begin
        # The whole point of the fix: GridSim's exported `step!`/`solve!` ARE
        # CommonSolve's, so once a DiffEq package (which re-exports CommonSolve's
        # verbs) is `using`-ed in an engine module, there is one generic, not two
        # in conflict. Two `===` exported bindings cannot raise an export-
        # ambiguity warning.
        @test GridSim.step! === CommonSolve.step!
        @test GridSim.solve! === CommonSolve.solve!
        # `init!` stays uniquely ours — CommonSolve exports `init`, not `init!`.
        @test parentmodule(GridSim.init!) === GridSim
    end

    @testset "DiffEq dep loaded: shares one generic, no collision" begin
        # The empirical proof the scaffold's `import CommonSolve` fix actually
        # holds once a real SciML solver package is loaded (m1-tasks.md). Before
        # this, the `===` checks above only proved GridSim agrees with the
        # interface package; they could not prove OrdinaryDiffEq agrees too. Both
        # verbs matter: `step!` is the real-time path, `solve!` the playback path.
        @test OrdinaryDiffEq.step! === CommonSolve.step!
        @test OrdinaryDiffEq.solve! === CommonSolve.solve!
        # The transitive payoff — GridSim's exported verbs ARE the same generics
        # OrdinaryDiffEq drives its integrator with. Two `using`-imported bindings
        # that are `===` cannot raise an export-ambiguity warning, so an engine
        # doing `using GridSim, OrdinaryDiffEq` sees one `step!`/`solve!`, not two.
        @test GridSim.step! === OrdinaryDiffEq.step!
        @test GridSim.solve! === OrdinaryDiffEq.solve!
    end

    @testset "aggregates (COI, on system base) vs hand arithmetic" begin
        sys = example_system()   # S_base=550, D=1.5, Tg=8.0; all R=0.05
        all_ids = Set(u.id for u in sys.units)

        # All four online. H_sys = Σ Hᵢ·Sᵢ / S_base:
        #   (4.0·200 + 3.5·150 + 3.0·100 + 2.5·100)/550 = 1875/550.
        # 1/R_eq = Σ (1/Rᵢ)·(Sᵢ/S_base) = 20·(200+150+100+100)/550 = 20·1 = 20
        #   (ΣSᵢ == S_base here, so R_eq collapses to the common 0.05 droop).
        a = GridSim.aggregates(sys, all_ids)
        @test a.H_sys ≈ 1875 / 550
        @test a.R_eq ≈ 0.05
        @test a.D == 1.5            # system-wide pass-through
        @test a.Tg == 8.0
        # headroom = Σ(Pmaxᵢ−P0ᵢ)/S_base = (50+40+30+40)/550 = 160/550.
        @test a.headroom ≈ 160 / 550

        # Trip G1 (200 MVA, H=4): only G2,G3,G4 online.
        #   H_sys = (525+300+250)/550 = 1075/550.
        #   1/R_eq = 20·(150+100+100)/550 = 7000/550 → R_eq = 550/7000.
        b = GridSim.aggregates(sys, Set([:G2, :G3, :G4]))
        @test b.H_sys ≈ 1075 / 550
        @test b.R_eq ≈ 550 / 7000
        # Tripping G1 also takes G1's own 50 MW headroom out of the pool:
        #   headroom = (40+30+40)/550 = 110/550.
        @test b.headroom ≈ 110 / 550
        # Losing inertia lowers H_sys; losing a unit lowers droop gain ⇒ raises R_eq;
        # and removes that unit's reserve ⇒ lowers headroom.
        @test b.H_sys < a.H_sys
        @test b.R_eq > a.R_eq
        @test b.headroom < a.headroom

        # No units online ⇒ zero inertia, zero droop gain (R_eq = Inf, not NaN),
        # zero reserve.
        z = GridSim.aggregates(sys, Set{Symbol}())
        @test z.H_sys == 0.0
        @test z.R_eq == Inf
        @test z.headroom == 0.0
    end

    @testset "fr_rhs!: swing/governor RHS + headroom saturation in the derivative" begin
        # Hand-built params (not from a system) so each scenario is isolated.
        # H_sys=2, R_eq=0.05, D=1.5, Tg=8, a generation-loss imbalance, ceiling 0.2.
        mk(; ΔP_dist = -0.27, headroom = 0.2) =
            GridSim.FRParams(2.0, 0.05, 1.5, 8.0, ΔP_dist, headroom)
        du = zeros(2)

        # Initial RoCoF: at the trip instant the state is the origin, so the swing
        # equation collapses to dΔω/dt = ΔP_dist/(2·H_sys) (closed form, SPEC §7.6).
        p = mk()
        GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)
        @test du[1] ≈ p.ΔP_dist / (2 * p.H_sys)
        @test du[2] == 0.0                      # −0/R_eq − 0 = 0
        # RHS is type-stable and non-allocating in the hot path.
        @test (@inferred GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)) === nothing

        # Governor term below the ceiling, under-frequency (Δω<0) ⇒ ramp UP.
        #   dΔPm = (−(−0.02)/0.05 − 0.1)/8 = (0.4 − 0.1)/8 = 0.0375 > 0.
        GridSim.fr_rhs!(du, [-0.02, 0.1], mk(), 0.0)
        @test du[2] ≈ 0.0375
        @test du[2] > 0                         # not at the ceiling ⇒ free to rise

        # SATURATION BINDS: ΔPm already at headroom and the governor wants more.
        #   raw dΔPm = (0.4 − 0.2)/8 = 0.025 > 0 ⇒ zeroed.
        GridSim.fr_rhs!(du, [-0.02, 0.2], mk(), 0.0)
        @test du[2] == 0.0

        # RELEASE (the test a naive state-clamp fails): at the ceiling but Δω has
        # recovered (Δω>0), so the governor term is negative — ΔPm must be allowed
        # to come back DOWN. raw dΔPm = (−0.2 − 0.2)/8 = −0.05 < 0 ⇒ NOT zeroed.
        GridSim.fr_rhs!(du, [0.01, 0.2], mk(), 0.0)
        @test du[2] ≈ -0.05
        @test du[2] < 0

        # R_eq = Inf (no droop / no online droop) ⇒ −Δω/R_eq = 0, no NaN.
        q = GridSim.FRParams(2.0, Inf, 1.5, 8.0, -0.1, 0.2)
        GridSim.fr_rhs!(du, [-0.01, 0.0], q, 0.0)
        @test all(isfinite, du)
        @test du[2] == 0.0                      # (−0 − 0)/Tg = 0
    end

    @testset "FrequencyResponseEngine: build, step, trip, closed-form checks" begin
        sys = example_system()                  # S_base=550, f0=50, D=1.5, Tg=8

        # --- construction via the interface verb (Type dispatch ⇒ fresh engine) ---
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        @test eng isa FrequencyResponseEngine
        # LOAD-BEARING: the integrator must hold the SAME params object the engine
        # mutates, or `inject!` would silently no-op the running integration.
        @test eng.integrator.p === eng.params
        @test eng.online == Set([:G1, :G2, :G3, :G4])

        # Pre-disturbance: sitting at the origin ⇒ f=f0, RoCoF=0, ΔPm=0.
        s0 = current_state(eng)
        @test s0.f ≈ sys.f0
        @test s0.Δω == 0.0
        @test s0.RoCoF == 0.0
        @test s0.ΔPm == 0.0
        # The parametric design pays off: `current_state` is type-stable.
        @inferred current_state(eng)

        # Stepping with no disturbance keeps us at the origin (ΔP_dist still 0).
        step!(eng, 0.02)
        @test current_state(eng).f ≈ sys.f0

        # --- trip G1 (P0=150) live: only G2,G3,G4 remain online ----------------
        inject!(eng, TripGenerator(:G1))
        @test eng.online == Set([:G2, :G3, :G4])
        a1 = GridSim.aggregates(sys, eng.online)
        @test eng.params.ΔP_dist ≈ -150 / 550          # lost generation, pu
        @test eng.params.H_sys ≈ a1.H_sys              # aggregates refreshed
        @test eng.params.headroom ≈ 110 / 550

        # Closed-form INITIAL RoCoF at the trip instant (state still the origin):
        #   RoCoF0 = f0·ΔP_dist/(2·H_sys) = 50·(−150/550)/(2·1075/550) = −7500/2150.
        s_trip = current_state(eng)
        @test s_trip.RoCoF ≈ 50 * (-150 / 550) / (2 * a1.H_sys)
        @test s_trip.RoCoF ≈ -7500 / 2150
        @test s_trip.RoCoF < 0                          # losing gen ⇒ frequency falls

        # Run it out and check the saturation invariant: G1's trip leaves only
        # 0.2 pu of headroom, which the droop demand exceeds — so ΔPm must pin at
        # the ceiling and NEVER cross it (the post-hoc-clamp landmine).
        for _ in 1:5000                                 # 100 s at dt=0.02
            step!(eng, 0.02)
        end
        @test maximum(eng.pms) ≤ eng.params.headroom + 1e-6
        @test eng.nadir < sys.f0                         # frequency dipped
        @test current_state(eng).f < sys.f0              # and settles below nominal
        # Trajectory recorded one point per step (+ the seeded origin).
        @test length(eng.ts) == length(eng.fs) == length(eng.pms)
        @test issorted(eng.ts)

        # Tripping an already-offline unit is a no-op.
        d_before = eng.params.ΔP_dist
        inject!(eng, TripGenerator(:G1))
        @test eng.params.ΔP_dist == d_before

        # --- separate engine: a SMALL trip whose droop stays below headroom, so
        # the unsaturated settling closed form applies: Δω_ss = ΔP_dist/(D+1/R_eq).
        eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng2, TripGenerator(:G4))               # P0=60, small
        a2 = GridSim.aggregates(sys, eng2.online)
        for _ in 1:4000                                  # 80 s — well past settling
            step!(eng2, 0.02)
        end
        Δω_ss = (-60 / 550) / (a2.D + 1 / a2.R_eq)
        f_ss = sys.f0 * (1 + Δω_ss)
        @test isapprox(current_state(eng2).f, f_ss; atol = 0.02)
        @test current_state(eng2).ΔPm < a2.headroom      # never bound ⇒ clean settle
    end

    @testset "GeneratingUnit rejects negative headroom (Pmax < P0)" begin
        # A unit whose ceiling is below its output is negative reserve — it must
        # fail loud at construction, not silently poison the aggregate headroom.
        @test_throws ArgumentError GeneratingUnit(:bad, 100.0, 3.0, 80.0, 0.05, 50.0)
        # Pmax == P0 (zero headroom) is allowed.
        @test GeneratingUnit(:ok, 100.0, 3.0, 80.0, 0.05, 80.0) isa GeneratingUnit
    end

    @testset "inject!: tripping a non-existent unit throws (caller bug)" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys)
        # The lookup runs BEFORE the online check, so an unknown id is reachable
        # and loud rather than a silent no-op.
        @test_throws KeyError inject!(eng, TripGenerator(:NOPE))
    end

    @testset "StepLoad sign: positive load lowers frequency" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        # StepLoad is named for LOAD: +0.1 pu adds load ⇒ negative imbalance ⇒ dip.
        inject!(eng, StepLoad(0.1))
        @test eng.params.ΔP_dist ≈ -0.1
        for _ in 1:3000                                  # 60 s — well past settling
            step!(eng, 0.02)
        end
        @test current_state(eng).f < sys.f0              # added load ⇒ frequency falls
        # And shedding load raises it (mirror check on a fresh engine).
        eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng2, StepLoad(-0.1))
        for _ in 1:3000
            step!(eng2, 0.02)
        end
        @test current_state(eng2).f > sys.f0
    end

    @testset "inject! invalidates the FSAL cache (no stale-derivative first step)" begin
        # Bug: Tsit5 is FSAL — it reuses the cached RHS at the current state as the
        # next step's first stage. If inject! mutates params without u_modified!, the
        # first post-trip step integrates from the stale (pre-trip, ==0) derivative.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.001)
        step!(eng, 0.001)                                # seed a live (zero) FSAL cache
        @test current_state(eng).Δω == 0.0
        inject!(eng, TripGenerator(:G1))                 # true dΔω/dt jumps off zero
        a = GridSim.aggregates(sys, eng.online)
        dΔω0 = (-150 / 550) / (2 * a.H_sys)              # closed-form derivative at trip
        Δω0 = current_state(eng).Δω                      # still exactly 0 (state untouched)
        step!(eng, 0.001)
        # Realized average rate over the first post-trip step must match the true
        # derivative to O(dt); a stale-zero cache biases it low by ~10%, which this
        # tight rtol catches (the old atol=0.02 settling check absorbed it).
        rate = (current_state(eng).Δω - Δω0) / 0.001
        @test isapprox(rate, dΔω0; rtol = 2e-3)
    end

    @testset "second trip after saturation does not freeze the integrator" begin
        # Bug: inject! shrank headroom while leaving ΔPm pinned to the OLD ceiling,
        # so the isoutofdomain guard rejected every step until dt collapsed to an
        # abort — and step! then silently flatlined. The event-boundary re-init
        # (cap ΔPm to the new ceiling) plus the loud retcode check fix both halves.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng, TripGenerator(:G1))                 # big trip ⇒ ΔPm rides the ceiling
        for _ in 1:3000                                  # 60 s ⇒ ΔPm pins at headroom
            step!(eng, 0.02)
        end
        @test isapprox(current_state(eng).ΔPm, eng.params.headroom; atol = 1e-3)

        # Second trip: new headroom (110/550 → 80/550) is BELOW the pinned ΔPm.
        inject!(eng, TripGenerator(:G3))
        @test eng.params.headroom ≈ 80 / 550
        # Re-init'd down to the new ceiling at the event boundary (not left stranded).
        @test current_state(eng).ΔPm ≤ eng.params.headroom + 1e-9
        n = length(eng.pms)
        t0 = eng.integrator.t
        for _ in 1:2000                                  # must keep advancing, not abort
            step!(eng, 0.02)
        end
        @test eng.integrator.t > t0 + 39.0               # ~40 s of real progress, no freeze
        @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
        # Post-trip trajectory never crosses the new (shrunken) ceiling.
        @test all(≤(eng.params.headroom + 1e-6), @view eng.pms[n+1:end])
    end

    # --- M1 validation: closed forms + the low-inertia lesson (SPEC §7.6, §7.8)
    #
    # The engine-level testsets above prove the *mechanics* on one instance each.
    # These sweep the same closed forms across every unit, and add the acceptance
    # criterion the earlier tests do not touch at all: less online inertia ⇒
    # steeper RoCoF and deeper nadir (SPEC §7.8 AC #6).
    #
    # Two shared helpers, defined once for the block below.

    # Rebuild a system with every unit's inertia scaled by `k` and *nothing else*
    # touched. S_rated/P0/R/Pmax are carried through verbatim, so S_base, the
    # disturbance size, R_eq, D and the aggregate headroom are all identical
    # across scalings — which is what makes the comparison inertia-only rather
    # than a confounded "different system" comparison.
    scale_inertia(sys::SystemModel, k::Real) =
        SystemModel(sys.S_base, sys.f0, sys.D, sys.Tg,
                    [GeneratingUnit(u.id, u.S_rated, u.H * k, u.P0, u.R, u.Pmax)
                     for u in sys.units])

    # Trip one unit from a cold engine and run it out. Returns the readings the
    # closed forms and the ordering checks are stated in.
    function trip_and_run(sys::SystemModel, id::Symbol; dt = 0.02, T = 150.0)
        eng = init!(FrequencyResponseEngine, sys; dt = dt)
        inject!(eng, TripGenerator(id))
        RoCoF0 = current_state(eng).RoCoF        # read at the trip instant, un-stepped
        for _ in 1:round(Int, T / dt)
            step!(eng, dt)
        end
        s = current_state(eng)
        a = GridSim.aggregates(sys, eng.online)  # post-trip aggregates
        return (; RoCoF0, nadir = eng.nadir, Δω_end = s.Δω, f_end = s.f,
                ΔPm_end = s.ΔPm, ΔPm_max = maximum(eng.pms), aggr = a)
    end

    P0_of(sys, id) = first(u.P0 for u in sys.units if u.id === id)

    @testset "closed form: initial RoCoF, swept over every single-unit trip" begin
        # SPEC §7.6 / §7.8 AC #4. RoCoF0 = −f0·(P_k/S_base)/(2·H_sys), where H_sys
        # is the POST-trip aggregate — the tripped unit's inertia is gone the
        # instant it goes offline, which is the whole reason the number is
        # interesting. The state is still exactly the origin (Δω=0, ΔPm=0), so the
        # swing equation collapses to this with no transient contribution; read it
        # with no intervening step! or the state has already moved off the origin.
        sys = example_system()
        for u in sys.units
            eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
            inject!(eng, TripGenerator(u.id))
            a = GridSim.aggregates(sys, eng.online)
            @test a.H_sys > 0                     # never the all-offline edge (RoCoF → ∓Inf)
            expected = -sys.f0 * (u.P0 / sys.S_base) / (2 * a.H_sys)
            s = current_state(eng)
            @test s.RoCoF ≈ expected              # exact closed form, default rtol
            @test s.RoCoF < 0                     # losing generation ⇒ frequency falls
            @test s.Δω == 0.0                     # still at the origin: no state jump
            @test s.ΔPm == 0.0                    # governors have not moved yet
        end
    end

    @testset "closed form: settling deviation, swept over every trip" begin
        # SPEC §7.6 / §7.8 AC #5. Δω_ss = ΔP_dist/(D + 1/R_eq) — but ONLY while the
        # governors are unsaturated; the formula assumes ΔPm can reach the droop
        # demand *at the fixed point*. G2/G3/G4 do, so they get a tolerance that
        # bites: rtol = 1e-6, ~4 orders tighter than the ±0.02 Hz used in the
        # engine testset above. (That looseness is what once absorbed the stale-
        # derivative bug — a closed-form check with a tolerance looser than the
        # physics deserves is where the next bug hides.)
        sys = example_system()
        for id in (:G2, :G3, :G4)
            r = trip_and_run(sys, id)
            Δω_ss = (-P0_of(sys, id) / sys.S_base) / (r.aggr.D + 1 / r.aggr.R_eq)
            # Precondition, asserted not assumed — and stated on the *equilibrium*,
            # which is what the closed form is about: at the fixed point the droop
            # demand ΔPm_ss = −Δω_ss/R_eq must sit strictly under the ceiling, so
            # the saturation branch is inactive there. G2's overshoot does briefly
            # touch the ceiling on the way (measured, not assumed: its ΔPm_max sits
            # exactly at headroom), which clips the transient but cannot move the
            # equilibrium — the saturation is switched off again by the time the
            # trajectory settles. Hence the transient peak is checked against the
            # ceiling, not against the precondition.
            @test r.ΔPm_end < r.aggr.headroom - 1e-3
            @test r.ΔPm_max ≤ r.aggr.headroom + 1e-9
            @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-6)
            @test isapprox(r.f_end, sys.f0 * (1 + Δω_ss); rtol = 1e-6)
        end

        # G1 is the counter-case that proves the precondition is load-bearing, not
        # decoration: its droop demand exceeds the surviving reserve, ΔPm pins at
        # the ceiling, and the system settles *below* the unsaturated formula. A
        # test suite that only ever checked the formula would call this a failure;
        # it is the physics (reserve exhaustion), and the ceiling still holds.
        r1 = trip_and_run(sys, :G1)
        Δω_ss_unsat = (-P0_of(sys, :G1) / sys.S_base) / (r1.aggr.D + 1 / r1.aggr.R_eq)
        @test isapprox(r1.ΔPm_end, r1.aggr.headroom; atol = 1e-6)   # pinned
        @test r1.Δω_end < Δω_ss_unsat                               # deeper than the formula
        @test r1.ΔPm_max ≤ r1.aggr.headroom + 1e-9                  # ceiling never crossed
    end

    @testset "less inertia ⇒ steeper RoCoF and deeper nadir (inertia-only)" begin
        # SPEC §7.8 AC #6 — the low-inertia/renewables lesson, isolated. Only the
        # inertia moves; the disturbance, droop gain, damping and reserve are
        # identical across all four systems, so any difference in the response is
        # attributable to inertia and nothing else.
        base = example_system()
        ks = (2.0, 1.0, 0.5, 0.25)                   # decreasing inertia
        rs = [trip_and_run(scale_inertia(base, k), :G4) for k in ks]

        # Settling is inertia-FREE: Δω_ss = ΔP_dist/(D + 1/R_eq) has no H in it.
        # So every config must land on the SAME frequency and differ only in how
        # far it dipped on the way. Asserting the equality alongside the ordering
        # is a much sharper statement of the lesson than the ordering alone.
        # Mixing sources here is deliberate and safe: the disturbance comes from
        # `base` while D/R_eq come from the k=2.0 config's aggregates — legal
        # *because* droop, damping and reserve are invariant under inertia
        # scaling, which is the very premise this testset rests on. If
        # `scale_inertia` ever grows to touch a second field, that invariance is
        # gone and this line silently compares against the wrong baseline instead
        # of failing, so the two must move together.
        a = rs[1].aggr
        Δω_ss = (-P0_of(base, :G4) / base.S_base) / (a.D + 1 / a.R_eq)
        f_ss = base.f0 * (1 + Δω_ss)
        for r in rs
            @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-4)
            # No confound: if the ceiling bound in the low-inertia configs but not
            # the high-inertia ones, the "deeper nadir" would be partly reserve
            # exhaustion rather than inertia. Fail loudly instead of quietly.
            @test r.ΔPm_max < r.aggr.headroom - 1e-3
            # Not a vacuous ordering: each config must genuinely undershoot its
            # settling value. If a future parameter edit overdamped the system the
            # nadir would collapse onto f_ss in every config and the ordering below
            # would start passing on floating-point noise with nothing behind it.
            @test r.nadir < f_ss - 0.1
        end

        # Initial RoCoF: strictly steeper as inertia falls, and exactly inversely
        # proportional to it (halving H doubles RoCoF0 — same ΔP over half the
        # inertia). The exact ratio is a stronger check than the ordering.
        @test issorted([r.RoCoF0 for r in rs]; rev = true)   # increasingly negative
        for i in 2:length(ks)
            @test isapprox(rs[i].RoCoF0 / rs[1].RoCoF0, ks[1] / ks[i]; rtol = 1e-9)
        end

        # Nadir: strictly deeper as inertia falls. Physically — with a slow
        # governor (Tg = 8 s) the early fall is governed by inertia alone, so a
        # lighter system plunges further toward the damping-only asymptote before
        # the governors arrive to arrest it.
        @test issorted([r.nadir for r in rs]; rev = true)     # monotonically lower
        @test rs[end].nadir < rs[1].nadir - 0.5               # a visible gap, not noise
    end

    @testset "fewer units online ⇒ steeper RoCoF and deeper dip (SPEC AC #6)" begin
        # The literal wording of AC #6 ("fewer/less-inertia units online"). This is
        # the DEMONSTRATION, not the isolation: taking a unit offline moves inertia
        # and droop gain and reserve together, so unlike the inertia-only testset
        # above the two configs do NOT settle to the same frequency. Both effects
        # push the same way, which is exactly the operational point.
        sys = example_system()

        # Same disturbance (trip G4) in a full system vs one already missing G3.
        # Measure the dip relative to the pre-trip frequency, since the depleted
        # system is already below nominal when the second trip lands.
        function dip_after(pretrips, id; dt = 0.02, T = 150.0)
            eng = init!(FrequencyResponseEngine, sys; dt = dt)
            for p in pretrips
                inject!(eng, TripGenerator(p))
                for _ in 1:round(Int, T / dt)      # let the pre-trip fully settle
                    step!(eng, dt)
                end
            end
            f_before = current_state(eng).f
            mark = length(eng.fs)
            inject!(eng, TripGenerator(id))
            RoCoF0 = current_state(eng).RoCoF
            for _ in 1:round(Int, T / dt)
                step!(eng, dt)
            end
            tail = mark:length(eng.fs)
            return (; RoCoF0, dip = f_before - minimum(@view eng.fs[tail]),
                    ΔPm_max = maximum(@view eng.pms[tail]),
                    headroom = GridSim.aggregates(sys, eng.online).headroom)
        end

        full = dip_after(Symbol[], :G4)
        thin = dip_after([:G3], :G4)

        @test thin.RoCoF0 < full.RoCoF0            # steeper (both negative)
        @test thin.dip > full.dip                  # deeper dip below the pre-trip point
        # And the second mechanism the depleted system exposes: its surviving
        # reserve is smaller, so the same trip now exhausts it. Ceiling still holds.
        @test full.ΔPm_max < full.headroom - 1e-3        # full system: reserve to spare
        @test isapprox(thin.ΔPm_max, thin.headroom; atol = 1e-6)   # depleted: pinned
        @test thin.ΔPm_max ≤ thin.headroom + 1e-9
    end

    # --- orchestration: event queue + real-time loop (docs/SPEC.md §7.5) ------
    #
    # Every loop test below terminates on its own: either a finite `duration` with
    # `rtf = Inf` (no sleeping, so it cannot outlive the assertion it supports), or
    # an explicit stopper wired to a state callback plus a wall-clock watchdog. A
    # `while running[]` loop with wall-clock pacing is the classic way to hang a
    # suite, and a hung suite is worse than a failing one.

    @testset "load shedding: latching, downward-only, root-found" begin
        # The ladder is an ARMED PROTECTION SCHEME, not a user-injected event: it
        # fires on the system's own state, at a root-found instant, once per stage.
        sys = example_system()
        stage = LoadShedStage(49.5, 0.02; label = :s1)
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01, shed = [stage])
        @test isempty(shed_log(eng.ladder).t)            # nothing fires at build
        @test eng.ladder.armed == [true]
        inject!(eng, TripGenerator(:G4))                 # -60/550 pu => dips past 49.5
        for _ in 1:1500; step!(eng); end                 # 15 s
        lg = shed_log(eng.ladder)
        @test length(lg.t) == 1                          # fired exactly once
        @test lg.label == [:s1]
        @test eng.ladder.armed == [false]                # latched
        @test shed_total(eng.ladder) ≈ 0.02
        # Root-found, not step-quantised: the crossing instant is (almost surely)
        # NOT on the dt grid, and f at that instant is the threshold to solver tol.
        t_fire = lg.t[1]
        @test 0 < t_fire < 15
        @test !isapprox(t_fire / 0.01, round(t_fire / 0.01); atol = 1e-6)
        i = argmin(abs.(eng.ts .- t_fire))
        @test isapprox(eng.fs[i], 49.5; atol = 0.02)     # within one dt of the grid
        # And it actually helped: same scenario without the ladder settles lower.
        bare = init!(FrequencyResponseEngine, sys; dt = 0.01)
        inject!(bare, TripGenerator(:G4))
        for _ in 1:1500; step!(bare); end
        @test current_state(eng).f > current_state(bare).f
    end

    @testset "load shedding: downward crossings only (affect_neg! slot)" begin
        # Positional-argument hazard: `ContinuousCallback(cond, affect!, affect_neg!)`
        # — `affect!` is the UPcrossing, `affect_neg!` the DOWNcrossing. Wire the shed
        # into the wrong slot and it fires as frequency RISES through the threshold:
        # physically backwards, and silent. Assert both polarities, don't trust the
        # signature.
        #
        # `example_system` is underdamped (ζ ≈ 0.28), so a load shed sends frequency
        # up through a threshold and the swing brings it back down through the same
        # one ~6 s later. That gives both crossings in ONE run, in a known order.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(50.5, 0.02; label = :both_ways)])
        inject!(eng, StepLoad(-0.3))                     # shed load => f climbs
        for _ in 1:200; step!(eng); end                  # t = 2 s: f ≈ 52.8, well past 50.5
        @test current_state(eng).f > 50.5                # the UPcrossing really happened
        @test isempty(shed_log(eng.ladder).t)            # ...and it did NOT fire
        @test eng.ladder.armed == [true]
        for _ in 1:600; step!(eng); end                  # t = 8 s: the swing brings it back
        @test current_state(eng).f < 50.5                # now a DOWNcrossing
        @test length(shed_log(eng.ladder).t) == 1        # ...and it fired
        @test 2.0 < shed_log(eng.ladder).t[1] < 8.0      # on the way down, not the way up
    end

    @testset "load shedding: a fired stage never re-arms" begin
        # The latch sign is the subtle part: a disarmed stage's condition must keep
        # the sign it had just AFTER firing (negative). Return +1.0 instead and the
        # rootfinder sees a manufactured sign change at the disarm instant => double
        # shed. This drives frequency back up through the threshold and down again.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(49.5, 0.001; label = :once)])
        inject!(eng, TripGenerator(:G1))                 # deep dip => fires
        for _ in 1:500; step!(eng); end
        @test length(shed_log(eng.ladder).t) == 1
        inject!(eng, StepLoad(-0.6))                     # haul it back above 49.5
        for _ in 1:2000; step!(eng); end
        @test current_state(eng).f > 49.5
        inject!(eng, StepLoad(0.6))                      # and back down through it
        for _ in 1:2000; step!(eng); end
        @test current_state(eng).f < 49.5
        @test length(shed_log(eng.ladder).t) == 1        # still exactly one shed
        @test shed_total(eng.ladder) ≈ 0.001
    end

    @testset "shed sign == StepLoad(-dP): shedding load raises frequency" begin
        # Pins the convention against a future sign flip: `ΔP_dist += ΔP_pu` for a
        # shed must be the exact mirror of `StepLoad`'s `ΔP_dist -= ΔP_pu`.
        sys = example_system()
        shed_amt = 0.02
        # Fire the ladder at a threshold the trip is guaranteed to cross.
        a = init!(FrequencyResponseEngine, sys; dt = 0.005,
                  shed = [LoadShedStage(49.9, shed_amt; label = :x)])
        inject!(a, TripGenerator(:G4))
        for _ in 1:16000; step!(a); end                  # 80 s — well past settling
        @test length(shed_log(a.ladder).t) == 1
        # Equivalent hand-injected version: same trip, same shed as a StepLoad at the
        # root-found instant. Compare the SETTLING point, which is instant-independent.
        b = init!(FrequencyResponseEngine, sys; dt = 0.005)
        inject!(b, TripGenerator(:G4))
        inject!(b, StepLoad(-shed_amt))
        for _ in 1:16000; step!(b); end
        @test isapprox(a.params.ΔP_dist, b.params.ΔP_dist; rtol = 1e-12)
        # 80 s is ~3.5 damped periods past settling, so the two runs' different shed
        # INSTANTS have decayed out and only the shared fixed point is left. A flipped
        # sign would move that fixed point by ~0.11 Hz — 10⁴x this tolerance.
        @test isapprox(current_state(a).f, current_state(b).f; atol = 1e-5)
    end

    @testset "shed event is integrated, not just recorded (dt refinement)" begin
        # The shed affect! mutates `p` while leaving `u` alone — the stale-FSAL hazard
        # `inject!` arms against by hand. On the callback path DiffEqBase already sets
        # `derivative_discontinuity` before invoking the affect, so no explicit call is
        # needed there; this test is what keeps that true. It matters because the error
        # would be INVISIBLE to any readout assertion: `current_state` recomputes RoCoF
        # algebraically from `_dΔω`, so it would report the right post-shed value while
        # the integration drifted. Only refining dt and demanding convergence
        # discriminates.
        sys = example_system()
        stage = LoadShedStage(49.8, 0.05; label = :fsal)
        function run_to(dt, tend)
            eng = init!(FrequencyResponseEngine, sys; dt = dt, shed = [stage])
            inject!(eng, TripGenerator(:G1))
            for _ in 1:round(Int, tend / dt); step!(eng); end
            return eng
        end
        coarse = run_to(0.01, 3.0)
        fine   = run_to(0.001, 3.0)
        @test length(shed_log(coarse.ladder).t) == 1
        @test length(shed_log(fine.ladder).t) == 1
        # Root-found instant is a property of the trajectory, not of the sampling.
        @test isapprox(shed_log(coarse.ladder).t[1], shed_log(fine.ladder).t[1];
                       atol = 1e-4)
        # 10x refinement must not move the state: a stale-derivative step biases the
        # coarse run by ~dt*ΔP_shed/(2*H_sys), which this rtol rejects.
        @test isapprox(current_state(coarse).Δω, current_state(fine).Δω; rtol = 2e-3)
    end

    @testset "cumulative tripped MW counts generation only" begin
        # The second axis of report Figs 1-3 / 3-7 / 3-9 is tripped GENERATION.
        # Shed load is not generation and must not leak into it.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(49.5, 0.02; label = :s)])
        @test eng.tripped_mw == 0.0
        step!(eng)
        @test state_series(eng).tripped_mw[end] == 0.0
        inject!(eng, TripGenerator(:G1))                 # 150 MW
        step!(eng)
        @test eng.tripped_mw ≈ 150.0
        @test state_series(eng).tripped_mw[end] ≈ 150.0
        inject!(eng, TripGenerator(:G1))                 # already offline => no double count
        @test eng.tripped_mw ≈ 150.0
        inject!(eng, StepLoad(0.05))                     # load, not generation
        @test eng.tripped_mw ≈ 150.0
        inject!(eng, TripGenerator(:G3))                 # +70 MW
        for _ in 1:1500; step!(eng); end
        @test eng.tripped_mw ≈ 220.0
        @test !isempty(shed_log(eng.ladder).t)           # the ladder did fire...
        @test eng.tripped_mw ≈ 220.0                     # ...and did not touch the tally
        # The recorded series is aligned with the trajectory and non-decreasing.
        s = state_series(eng)
        @test length(s.tripped_mw) == length(s.t)
        @test issorted(s.tripped_mw)
        @test s.tripped_mw[end] ≈ 220.0
    end

    @testset "windowed_rocof: 500 ms sliding window, actual elapsed divisor" begin
        # Every RoCoF number in the ENTSO-E report is a 500 ms window (p.116); the
        # engine's `current_state` RoCoF is instantaneous. Different quantities.
        t = collect(0.0:0.01:2.0)
        f = 50.0 .- 2.0 .* t                             # exact -2 Hz/s ramp
        w = windowed_rocof(t, f)
        @test length(w) == length(t)
        @test all(isnan, w[t .< 0.5 - 1e-9])             # window not full yet => NaN
        @test all(x -> isapprox(x, -2.0; atol = 1e-9), filter(!isnan, w))
        @test count(!isnan, w) == count(>=(0.5 - 1e-9), t)
        # Non-uniform samples: the divisor is the ACTUAL elapsed time, not the
        # nominal window. Here the lookback lands 0.7 s back, not 0.5 s.
        tn = [0.0, 0.3, 1.0]
        fn = [50.0, 50.0, 49.0]
        wn = windowed_rocof(tn, fn)
        @test isnan(wn[1]) && isnan(wn[2])
        @test isapprox(wn[3], -1.0 / 0.7; atol = 1e-12)  # -1.4286, not -2.0
        # Window length is a knob.
        @test count(!isnan, windowed_rocof(t, f; window = 1.0)) < count(!isnan, w)
        @test_throws ArgumentError windowed_rocof(t, f[1:end-1])
        @test_throws ArgumentError windowed_rocof(t, f; window = 0.0)
        # NamedTuple method over a real trajectory: the windowed peak is strictly
        # shallower than the instantaneous one during a fast transient.
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.01)
        inject!(eng, TripGenerator(:G1))
        for _ in 1:1000; step!(eng); end
        s = state_series(eng)
        ww = windowed_rocof(s)
        @test ww.t === s.t
        @test length(ww.RoCoF) == length(s.t)
        @test minimum(filter(!isnan, ww.RoCoF)) > minimum(s.RoCoF)
    end

    @testset "inverter-based resources (H=0, R=Inf) give finite aggregates" begin
        # The Iberian scenario models the tripping blocks as IBR: zero inertia, no
        # droop, no headroom. This must stay expressible with no data-model change,
        # and must not produce NaN/Inf where a finite number belongs.
        pv = GeneratingUnit(:PV, 900.0, 0.0, 900.0, Inf, 900.0)
        sync = GeneratingUnit(:SYNC, 1000.0, 4.0, 600.0, 0.05, 800.0)
        sys = SystemModel(2000.0, 50.0, 1.5, 8.0, [sync, pv])
        a = GridSim.aggregates(sys, Set([:SYNC, :PV]))
        @test isfinite(a.H_sys) && a.H_sys ≈ 4.0 * 1000 / 2000     # PV adds no inertia
        @test isfinite(a.R_eq) && a.R_eq > 0                        # 1/Inf = 0, no NaN
        @test a.R_eq ≈ 1 / ((1 / 0.05) * 1000 / 2000)
        @test isfinite(a.headroom) && a.headroom ≈ (800 - 600) / 2000  # PV: zero reserve
        # An all-IBR set is the degenerate corner: no inertia, no droop, no NaN.
        b = GridSim.aggregates(sys, Set([:PV]))
        @test b.H_sys == 0.0 && b.R_eq == Inf && b.headroom == 0.0
        @test !isnan(b.H_sys) && !isnan(b.headroom)
        # And the engine runs with one in the mix: trip the PV, get a finite dip.
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01)
        inject!(eng, TripGenerator(:PV))
        for _ in 1:1000; step!(eng); end
        st = current_state(eng)
        @test isfinite(st.f) && st.f < sys.f0
        @test all(isfinite, state_series(eng).f)
        @test eng.tripped_mw ≈ 900.0
    end

    @testset "Iberia scenario: the two-window structure, asserted not banded" begin
        # The headless script is a deliverable, so its claims are pinned here. It is
        # included as a MODULE so the scenario stays single-sourced (no second copy of
        # the event times in the test) without leaking its constants into the suite;
        # `main()` is guarded by PROGRAM_FILE, so including it runs nothing.
        #
        # THE TOLERANCES ENCODE A STRUCTURE, NOT A BAND. The model errs in opposite
        # directions on either side of ~12:33:17, and one symmetric "close enough"
        # band would hide both halves. So each window is asserted with its own SIGN.
        eng = Iberia.replay()
        s = state_series(eng)
        at(tq) = s.f[argmin(abs.(s.t .- tq))]

        # Window 1 — before loss of synchronism the model runs TOO DEEP, because
        # Iberia was still synchronously inside Continental Europe behind a finite
        # tie and was therefore stiffer than the isolated system modelled here.
        for (tq, fref) in ((55.0, 49.98), (60.0, 49.94), (76.9, 49.90), (77.9, 49.80))
            fm = at(tq)
            @test fm < fref                              # the SIGN is the claim
            @test fref - fm < 0.15                       # …and it stays small
        end

        # Window 2 — 12:33:20 is DELIBERATELY NOT BANDED. The centre-of-inertia model
        # cannot reproduce the last 5 s (plan doc §2): ~5,000 MW of the imbalance was
        # export swing from loss of synchronism, which a two-state swing + governor
        # model has no state for. With the real defence plan armed the model recovers
        # while reality collapsed, so this row is asserted as a KNOWN STRUCTURAL
        # FAILURE. It is not a target: closing it requires the two-area model, and
        # doing so must come with a conscious edit to this assertion — never with a
        # parameter tuned until the number matches.
        @test at(80.0) > 48.50 + 0.5
        @test eng.nadir > 49.0                           # the ladder arrests the fall

        # The defence plan fired the stages the report annotates, in threshold order.
        lg = shed_log(eng.ladder)
        @test length(lg.t) == 4
        @test lg.threshold_hz == [49.8, 49.7, 49.6, 49.5]
        @test issorted(lg.t)                             # in time order too
        @test isapprox(shed_total(eng.ladder) * eng.model.S_base, 3907.0; atol = 1.0)
        # Root-found, so the crossing instants are not on the dt grid.
        @test all(t -> !isapprox(t / 0.01, round(t / 0.01); atol = 1e-6), lg.t)
        # Reality did not reach 49.5 Hz until 12:33:20.133 (report p.174), i.e. AFTER
        # the fidelity boundary; the model gets there ~1.7 s early, the same too-deep
        # error as the waypoints above. Two-sided on purpose: a one-sided "more than
        # 1 s early" would also be satisfied by a run firing at 60 s for unrelated
        # reasons, which is not the claim being made.
        @test 78.0 < lg.t[end] < 79.0

        # Disarming the ladder must make it worse — the mechanism has to be load-bearing.
        # The armed nadir is pinned at the 49.5 Hz threshold (that stage arrests the
        # fall), the disarmed one lands at ~48.73, so the gap is ~0.77 Hz; 0.5 is a
        # deliberate margin under it, not a number that happened to pass. If the
        # ladder's contents change, this is the assertion that moves.
        bare = Iberia.replay(; shed = false)
        @test bare.nadir < eng.nadir - 0.5
        @test isempty(shed_log(bare.ladder).t)

        # Cumulative tripped generation: the scripted sequence, and a lower bound by
        # construction (the report calls the last cluster a floor).
        @test issorted(s.tripped_mw)
        @test s.tripped_mw[end] ≈ 355 + 725 + 930 + 2600

        # The one RoCoF claim that lies INSIDE the faithful window: the report states
        # |RoCoF| stayed within 1 Hz/s until 12:33:20.560 (p.116), measured over a
        # 500 ms sliding window. Instantaneous RoCoF is a different quantity and is
        # steeper by construction — asserted, so the two cannot be conflated later.
        w = windowed_rocof(s)
        inwin = findall(t -> t <= Iberia.T_BOUNDARY, s.t)
        wv = filter(!isnan, w.RoCoF[inwin])
        @test !isempty(wv)
        @test maximum(abs, wv) < 1.0                     # the report's claim
        @test maximum(abs, wv) > 0.2                     # non-vacuous
        @test maximum(abs, wv) < maximum(abs, s.RoCoF[inwin])
    end

    @testset "Iberia scenario: keying the base off KE makes RoCoF0 H-independent" begin
        # The report's 2.21–2.71 s inertia band is uncertainty about how to SPLIT the
        # measured kinetic energy between machines and motor load. `S_base = KE/H_tot`
        # makes f0·ΔP/(2·H_sys) collapse to f0·ΔP_MW/(2·KE), so that split cancels out
        # of the initial RoCoF exactly. The script prints this; here it is pinned, so
        # nobody later reads the identical column as an empirical insensitivity result.
        r_lo  = Iberia.rocof0(Iberia.H_LO, :E6)
        r_mid = Iberia.rocof0(Iberia.H_MID, :E6)
        r_hi  = Iberia.rocof0(Iberia.H_HI, :E6)
        @test isapprox(r_lo, r_mid; rtol = 1e-12)
        @test isapprox(r_hi, r_mid; rtol = 1e-12)
        @test isapprox(r_mid, -50.0 * 2600.0 / (2 * Iberia.KE); rtol = 1e-12)
        @test r_mid < 0                                  # a trip lowers frequency
    end

    @testset "EventQueue" begin
        q = EventQueue()
        @test isempty(q) && length(q) == 0
        @test isempty(drain!(q))                        # draining an empty queue is fine

        push!(q, TripGenerator(:G1))
        push!(q, StepLoad(0.05))
        @test length(q) == 2 && !isempty(q)

        evs = drain!(q)                                 # submission order preserved
        @test evs == [TripGenerator(:G1), StepLoad(0.05)]
        @test isempty(q)                                # …and the queue is now empty
        @test isempty(drain!(q))                        # a second drain yields nothing

        # The swap must hand out a *fresh* vector each time, not alias the one the
        # caller is still holding — otherwise a later push! would mutate it.
        push!(q, TripGenerator(:G2))
        @test length(evs) == 2                          # the earlier batch is untouched
        empty!(q)
        @test isempty(q)
    end

    @testset "timestep is the engine's own dt" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.05)
        @test timestep(eng) == 0.05                     # what run_realtime! defaults to
    end

    @testset "UI accessors: system_inertia falls on a trip, is_online tracks it" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys)
        # The indicator must agree with the aggregate, not merely be non-zero.
        @test system_inertia(eng) ≈ GridSim.aggregates(sys, Set(u.id for u in sys.units)).H_sys
        @test all(is_online(eng, u.id) for u in sys.units)
        @test !is_online(eng, :nope)                    # a button for a ghost unit, not a bug

        H_before = system_inertia(eng)
        inject!(eng, TripGenerator(:G1))
        @test !is_online(eng, :G1)
        @test is_online(eng, :G2)
        # Losing a unit removes its kinetic energy from the pool: strictly less inertia.
        @test system_inertia(eng) < H_before
        @test system_inertia(eng) ≈
            GridSim.aggregates(sys, Set([:G2, :G3, :G4])).H_sys
    end

    @testset "run_realtime! headless (rtf = Inf) with a queued trip" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        q = EventQueue()
        push!(q, TripGenerator(:G1))                    # applied at the first step boundary

        out = run_realtime!(eng, obs; rtf = Inf, queue = q, duration = 2.0)

        @test out.engine === eng                        # returns the handles it used
        @test out.queue === q
        @test out.control isa RealtimeControl
        @test isempty(q)                                # the loop drained it
        @test !(:G1 in eng.online)                      # …and injected it

        @test isapprox(current_state(eng).t, 2.0; atol = 0.021)   # ran the sim duration
        @test obs[] == current_state(eng)                # published the latest state
        s = state_series(eng)
        # Seed point + ~100 steps of 0.02. Deliberately a *range*: whether the loop
        # takes 100 or 101 steps turns on where 100 accumulated additions of 0.02
        # land relative to 2.0 in Float64 — not a property worth asserting, and an
        # exact count would fail mysteriously on an integrator bookkeeping change.
        @test 101 ≤ length(s.t) ≤ 102
        @test length(s.f) == length(s.t) == length(s.RoCoF) == length(s.ΔPm)
        @test minimum(s.f) < sys.f0 - 0.05               # losing 150 MW dips frequency
        @test eng.nadir == minimum(s.f)
    end

    @testset "run_realtime! stops when control.running[] is cleared" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        ctl = RealtimeControl(; rtf = Inf)
        # Stop from a state callback: deterministic (counts published states, so it
        # also proves one publish per step) and independent of wall-clock timing.
        published = Ref(0)
        Observables.on(obs) do _
            published[] += 1
            published[] == 10 && stop!(ctl)
        end
        # `duration = Inf` on purpose — the callback is what must end this loop.
        run_realtime!(eng, obs; control = ctl, duration = Inf)
        @test published[] == 10
        @test !ctl.running[]
        @test isapprox(current_state(eng).t, 0.2; atol = 1e-9)   # exactly 10 × dt
    end

    @testset "run_realtime! honours pause and resumes without catch-up sprint" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        ctl = RealtimeControl(; rtf = Inf, paused = true)
        task = @async run_realtime!(eng, nothing; control = ctl, duration = 1.0)
        # Watchdog: whatever happens, this loop is over within 10 s wall-clock, so a
        # regression in the pause branch fails the test instead of hanging the suite.
        @async (sleep(10.0); stop!(ctl))

        sleep(0.2)
        @test current_state(eng).t == 0.0               # frozen: sim time did not advance
        @test ctl.running[]                             # …but the loop is alive
        ctl.paused[] = false
        wait(task)
        @test isapprox(current_state(eng).t, 1.0; atol = 0.021)   # resumed and finished
    end

    @testset "run_realtime! paces to wall-clock at rtf = 1" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        t_wall = @elapsed run_realtime!(eng, nothing; rtf = 1.0, duration = 0.2)
        @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
        # Lower bound is the real assertion (it did sleep rather than sprint); the
        # upper bound is deliberately loose — timer resolution and CI load are noisy.
        @test 0.15 < t_wall < 3.0
        # Twice the speed must take less wall-clock time for the same sim duration.
        eng2 = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        t_wall2 = @elapsed run_realtime!(eng2, nothing; rtf = 4.0, duration = 0.2)
        @test t_wall2 < t_wall
    end

    @testset "run_realtime! picks up an rtf change mid-run" begin
        # The pacing reads control.rtf[] fresh on every pass precisely so the UI's
        # speed slider takes effect immediately. Pin that down: start paced (slow
        # enough to be unmistakably sleeping), then switch to Inf from a state
        # callback — if the loop had captured rtf once at entry, the remaining steps
        # would still crawl and the elapsed time would blow past the bound.
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        ctl = RealtimeControl(; rtf = 0.1)               # 0.2 s of sim ⇒ 2 s wall-clock
        Observables.on(_ -> (ctl.rtf[] = Inf), obs)      # …unless the first step frees it
        t_wall = @elapsed run_realtime!(eng, obs; control = ctl, duration = 0.2)
        @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
        @test t_wall < 1.0                               # ≫ the ~1.8 s a stale rtf would cost
    end

    @testset "core dependency closure is UI-free (no Makie)" begin
        # The structural invariant (docs/SPEC.md §3.1): the core may reach Observables
        # — that is the seam live state crosses — but never a plotting package. The
        # positive half matters as much as the negative: without it this testset
        # would pass vacuously if `Pkg.dependencies()` ever returned nothing useful.
        names = [d.name for d in values(Pkg.dependencies())]
        @test "Observables" in names                     # positive control
        # The M2 network deps are named explicitly as *further* positive controls:
        # they arrived with ~60 transitive packages, and this scan is only evidence
        # about that closure if the closure it read actually contains them.
        @test "NetworkDynamics" in names
        @test "Graphs" in names
        @test !any(n -> occursin("Makie", n), names)     # the actual invariant
        # Makie is the invariant the SPEC names, but it is not the only way a UI
        # package could enter — a transitive plotting dep would violate §3.1 just
        # as much, and would not contain the string "Makie".
        @test !any(n -> n in ("Plots", "GR", "PyPlot", "PlotlyJS", "UnicodePlots"),
                   names)
    end

end
