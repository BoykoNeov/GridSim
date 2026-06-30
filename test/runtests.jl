using GridSim
using Test
import CommonSolve
import OrdinaryDiffEq

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

end
