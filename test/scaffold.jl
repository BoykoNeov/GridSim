# Scaffold-level tests: they exercise the durable contracts (data model, events,
# engine interface) that ship at initialization. The physics validation for M1
# (closed-form initial RoCoF and settling deviation, docs/SPEC.md §7.6) is added
# alongside FrequencyResponseEngine in the M1 code batch.

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
