using GridSim
using Test
import CommonSolve
import OrdinaryDiffEq
import SciMLBase

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

end
