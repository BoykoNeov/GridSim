using GridSim
using Test

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

end
