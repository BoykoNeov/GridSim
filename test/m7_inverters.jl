# M7 — inverter-based resources (docs/plans/m7-plan.md, m7-context.md).
#
# Step 1: the `Inverter` type enters the canonical model under the invariant that no
# existing number moves (that half is the rest of the suite plus the criterion
# capture, not this file), and every consumer that has not yet learned inverters
# REFUSES a model carrying one, by name — rather than running it with the inverter
# silently absent. This file is the other half: the type, the model's bookkeeping,
# and one refusal test per consumer.

# A two-bus model with one of each kind of generation: a machine at B1 (the
# reference), and at B2 a 100 MW load met half by the machine through the line and
# half by an inverter on the load's own bus. Balanced ONLY with the inverter counted.
function _m7_pair(; mode::Symbol = :grid_following, P_inv::Real = 50.0)
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0)]
    branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
    machines = [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 100.0 - P_inv)]
    loads = [Load(:D2, :B2, 100.0, 0.0)]
    inverters = [Inverter(:I2, :B2, mode, 100.0, P_inv)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads;
                        inverters = inverters)
end

@testset "M7 step 1 — the Inverter type and the model's bookkeeping" begin

    @testset "constructor: defaults, and every guard" begin
        i = Inverter(:I, :B, :grid_forming, 100.0, 60.0)
        @test i.mode === :grid_forming
        @test i.Q0 == 0.0
        # The defaults are the documented ones, and K_q = 0 is the degeneration.
        @test (i.K_p, i.τ_p, i.K_q, i.τ_q, i.V_set, i.X_c) == (0.05, 0.1, 0.0, 0.1, 1.0, 0.1)
        @test i.K_pll_p == 2π * 10 && i.K_pll_i == (2π * 10)^2 / 4
        # The PLL default is critically damped, as the docstring claims.
        @test i.K_pll_p / (2 * sqrt(i.K_pll_i)) ≈ 1.0 atol = 1e-12

        @test_throws ArgumentError Inverter(:I, :B, :grid_supporting, 100.0, 1.0)
        @test_throws ArgumentError Inverter(:I, :B, :grid_forming, 0.0, 0.0)
        # |P0 + jQ0| ≤ S_rated, both components counted.
        @test_throws ArgumentError Inverter(:I, :B, :grid_forming, 100.0, 101.0)
        @test_throws ArgumentError Inverter(:I, :B, :grid_following, 100.0, 80.0; Q0 = 70.0)
        @test Inverter(:I, :B, :grid_following, 100.0, 80.0; Q0 = 60.0).Q0 == 60.0
        @test Inverter(:I, :B, :grid_following, 100.0, -80.0).P0 == -80.0   # charging
        for kw in ((; K_p = 0.0), (; τ_p = 0.0), (; K_q = -0.01), (; τ_q = 0.0),
                   (; V_set = 0.0), (; X_c = 0.0), (; K_pll_p = 0.0), (; K_pll_i = 0.0))
            # Guarded in BOTH modes, whichever one reads the field.
            @test_throws ArgumentError Inverter(:I, :B, :grid_forming, 100.0, 1.0; kw...)
            @test_throws ArgumentError Inverter(:I, :B, :grid_following, 100.0, 1.0; kw...)
        end
        @test_throws ArgumentError Inverter(:I, :B, :grid_forming, 100.0, NaN)
    end

    @testset "NetworkModel carries inverters, sorted by bus, and counts them" begin
        net = _m7_pair()
        @test length(net.inverters) == 1
        @test net.inverters_at_bus == [Int[], [1]]
        @test [i.id for i in inverters_at(net, :B2)] == [:I2]
        @test isempty(inverters_at(net, :B1))
        @test_throws ArgumentError inverters_at(net, :B9)

        # Every pre-M7 construction still builds a model with no inverters.
        @test isempty(two_machine_system().inverters)
        @test all(isempty, two_machine_system().inverters_at_bus)

        # Stored by bus whatever order they were given in.
        buses = [Bus(:A, 1.0), Bus(:B, 1.0), Bus(:C, 1.0)]
        br = [Branch(:AB, :A, :B, 0.1, 1.0), Branch(:BC, :B, :C, 0.1, 1.0)]
        invs = [Inverter(:iC, :C, :grid_forming, 10.0, 5.0),
                Inverter(:iA, :A, :grid_forming, 10.0, -5.0)]
        net3 = NetworkModel(100.0, 50.0, buses, br, Machine[]; inverters = invs)
        @test [i.id for i in net3.inverters] == [:iA, :iC]
        @test net3.inverters_at_bus == [[1], Int[], [2]]
    end

    @testset "the balance guard counts the inverter — anti-vacuity" begin
        # Positive control: balanced with the inverter counted → constructs.
        @test _m7_pair() isa NetworkModel
        # The same data with the inverter's injection NOT in the model: the machine
        # still produces 50 MW against a 100 MW load, so the guard must reject it.
        # If the guard ignored inverters, the first model would have been rejected
        # and this one accepted — the mirror image, which is what this pins.
        buses = [Bus(:B1, 230.0), Bus(:B2, 230.0)]
        branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
        machines = [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 50.0)]
        loads = [Load(:D2, :B2, 100.0, 0.0)]
        @test_throws ArgumentError NetworkModel(100.0, 50.0, buses, branches,
                                                machines, loads)
        # And an inverter pushing too much is rejected with the inverter term named.
        err = try
            NetworkModel(100.0, 50.0, buses, branches, machines, loads;
                         inverters = [Inverter(:I2, :B2, :grid_following, 100.0, 60.0)])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError && occursin("Σ inverters.P0", err.msg)
    end

    @testset "ids: duplicates, machine collisions, and a missing bus" begin
        buses = [Bus(:B1, 230.0), Bus(:B2, 230.0)]
        branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
        m = [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 0.0)]
        a = Inverter(:I, :B2, :grid_forming, 10.0, 0.0)
        @test_throws ArgumentError NetworkModel(100.0, 50.0, buses, branches, m;
                                                inverters = [a, a])
        @test_throws ArgumentError NetworkModel(100.0, 50.0, buses, branches, m;
            inverters = [Inverter(:G1, :B2, :grid_forming, 10.0, 0.0)])
        @test_throws ArgumentError NetworkModel(100.0, 50.0, buses, branches, m;
            inverters = [Inverter(:I, :B9, :grid_forming, 10.0, 0.0)])
    end

    @testset "bus roles and the default reference bus" begin
        # A grid-forming inverter SETS a voltage → a generator bus; a grid-following
        # one on its own does not → a load bus. The machine bus is the slack.
        @test bus_roles(_m7_pair(mode = :grid_forming)) == [:slack, :generator]
        @test bus_roles(_m7_pair(mode = :grid_following)) == [:slack, :load]
        @test bus_role(_m7_pair(mode = :grid_forming), :B2) === :generator
        @test bus_role(_m7_pair(mode = :grid_following), :B2) === :load

        # With no machine, the default reference is the first grid-forming inverter's
        # bus — never a grid-following one's, and the first bus when there is neither.
        buses = [Bus(:A, 1.0), Bus(:B, 1.0), Bus(:C, 1.0)]
        br = [Branch(:AB, :A, :B, 0.1, 1.0), Branch(:BC, :B, :C, 0.1, 1.0)]
        fol = Inverter(:fA, :A, :grid_following, 10.0, -5.0)
        frm = Inverter(:fC, :C, :grid_forming, 10.0, 5.0)
        @test NetworkModel(100.0, 50.0, buses, br, Machine[];
                           inverters = [fol, frm]).slack === :C
        @test NetworkModel(100.0, 50.0, buses, br, Machine[];
                           inverters = [Inverter(:fA, :A, :grid_following, 10.0, 0.0)]
                           ).slack === :A          # buses[1], not "the GFL bus"
        # A machine anywhere keeps the pre-M7 default, whatever inverters exist.
        @test _m7_pair(mode = :grid_forming).slack === :B1
    end

    @testset "every unbuilt consumer refuses by name" begin
        # One test per consumer. Each asserts the refusal NAMES the inverter: a
        # generic error would pass `@test_throws` for the wrong reason (a missing
        # method, a failed solve) and hide that the consumer never looked.
        names_it(e) = e isa ArgumentError && occursin("I2", e.msg)
        refuses(f) = try; f(); false; catch e; names_it(e); end
        for mode in (:grid_forming, :grid_following)
            net = _m7_pair(mode = mode)
            # Step 3 built the grid-forming vertex; grid-following stays refused here
            # for good (a tier boundary) — its own testset checks the message.
            mode === :grid_following && @test refuses(() -> SwingEngine(net))
            # Step 4 taught the detailed tier and the power flows the grid-forming
            # kind (their own testsets check what they do with it); grid-following
            # waits for step 5.
            if mode === :grid_following
                @test refuses(() -> init!(DetailedEngine, net))
                @test refuses(() -> ac_powerflow(net))
                @test refuses(() -> dc_powerflow(net))
                @test refuses(() -> bus_injections(net))   # exported on its own
            end
            @test refuses(() -> economic_dispatch(net))
        end
        # The swing tier's message says the grid-following refusal is a boundary,
        # not unbuilt work (m7-context.md D3).
        msg = try; SwingEngine(_m7_pair()); ""; catch e; e.msg; end
        @test occursin("tier boundary", msg)
    end

    @testset "the exported surface, walked rather than grepped" begin
        # The first consumer list was built by grepping for `net.machines`; it
        # missed `bus_injections`, which returned a non-balancing vector without an
        # error. So the surface is walked: every EXPORTED function with a
        # one-argument `NetworkModel` method is called on an inverter model and
        # must either refuse naming the inverter or be on the list of views that
        # are about machines, loads or branches only by definition. A new export
        # that silently drops inverters fails here by not being on either list.
        views = Set([:branch_topology, :load_arrays, :machine_arrays, :cost_arrays,
                     :bus_roles, :branch_arrays])
        # Consumers a later M7 step has TAUGHT inverters (their own testsets check
        # what they do with them). Growing this set is how a step lifts a refusal.
        learned = Set([:coi_model])
        net = _m7_pair()
        walked = 0
        for n in names(GridSim)
            f = getfield(GridSim, n)
            (f isa Function || f isa Type) || continue
            # A method that NAMES `NetworkModel` in its signature — not `hasmethod`,
            # which also matches every type's generic `convert` fallback
            # (`TripGenerator(net)` "has a method" and throws a MethodError).
            any(m -> (s = Base.unwrap_unionall(m.sig);
                      length(s.parameters) == 2 && s.parameters[2] === NetworkModel),
                methods(f)) || continue
            r = try; f(net); :returned; catch e
                e isa ArgumentError && occursin("I2", e.msg) ? :refused : :threw
            end
            walked += 1
            @test r === :refused || n in views || n in learned
        end
        # Non-vacuity: a walk that matched nothing would pass everything. Eleven
        # exported functions take a model as their only argument today.
        @test walked >= 11
        # `bus_roles` is on the view list because it DOES count inverters, not
        # because it ignores them.
        @test bus_roles(net) == [:slack, :load]
    end

    @testset "a rebuild carries the inverters through" begin
        # `dispatch_schedule` rebuilds the model field by field; a hand-listed
        # rebuild is exactly where a new collection gets dropped. The dispatch is
        # computed on the inverter-free twin (the dispatch itself refuses inverters),
        # which `_assert_dispatch_of` accepts because it checks machines and base.
        cost = (; cost_c2 = 0.01, cost_c1 = 10.0, cost_c0 = 0.0, Pmin = 0.0)
        mk(P) = Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, P, Inf, 150.0; cost...)
        buses = [Bus(:B1, 230.0), Bus(:B2, 230.0)]
        branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
        twin = NetworkModel(100.0, 50.0, buses, branches, [mk(100.0)],
                            [Load(:D2, :B2, 100.0, 0.0)])
        with = NetworkModel(100.0, 50.0, buses, branches, [mk(50.0)],
                            [Load(:D2, :B2, 100.0, 0.0)];
                            inverters = [Inverter(:I2, :B2, :grid_following, 100.0, 50.0)])
        ed = economic_dispatch(twin)
        # The twin's dispatch puts 100 MW on G1; the rebuild of `with` therefore no
        # longer balances — and that refusal is the proof the inverter was CARRIED
        # (had it been dropped, 100 MW against 100 MW would have constructed).
        @test_throws ArgumentError dispatch_schedule(with, ed)
    end
end

@testset "M7 step 1 — inverters in the scenario file" begin
    dir = mktempdir()

    @testset "the field list is the struct's" begin
        # The writer and reader walk `_INVERTER_NUMERIC`; a field added to the struct
        # and not to the list would be silently dropped on save.
        @test Set(fieldnames(Inverter)) ==
              Set((:id, :bus, :mode, GridSim._INVERTER_NUMERIC...))
    end

    @testset "round trip, both kinds, every field" begin
        buses = [Bus(:A, 400.0), Bus(:B, 400.0), Bus(:C, 400.0)]
        br = [Branch(:AB, :A, :B, 0.1, 1.0), Branch(:BC, :B, :C, 0.15, 1.0)]
        invs = [Inverter(:gfm, :A, :grid_forming, 120.0, 40.0; Q0 = 5.0, K_p = 0.03,
                         τ_p = 0.2, K_q = 0.02, τ_q = 0.05, V_set = 1.02, X_c = 0.12),
                Inverter(:gfl, :C, :grid_following, 80.0, 20.0; Q0 = -3.0,
                         K_pll_p = 50.0, K_pll_i = 700.0)]
        net = NetworkModel(100.0, 50.0, buses, br, Machine[],
                           [Load(:dB, :B, 60.0, 10.0)]; inverters = invs, slack = :A)
        path = write_scenario(joinpath(dir, "inv.toml"), net)
        back = read_scenario(path).net
        @test back.slack === :A
        @test length(back.inverters) == 2
        for (a, b) in zip(net.inverters, back.inverters), f in fieldnames(Inverter)
            @test getfield(a, f) === getfield(b, f)
        end
        # `τ` is not a bare TOML key; it is spelled `tau` on disk.
        txt = read(path, String)
        @test occursin("tau_p", txt) && !occursin("τ", txt)
    end

    @testset "a hand-written minimal record takes the constructor's defaults" begin
        path = joinpath(dir, "min.toml")
        write(path, """
            S_base = 100.0
            f0 = 50.0
            slack = "A"
            [[buses]]
            id = "A"
            V_base = 400.0
            [[inverters]]
            id = "i"
            bus = "A"
            mode = "grid_forming"
            S_rated = 50.0
            P0 = 0.0
            """)
        i = only(read_scenario(path).net.inverters)
        d = Inverter(:i, :A, :grid_forming, 50.0, 0.0)
        for f in fieldnames(Inverter)
            @test getfield(i, f) === getfield(d, f)
        end
        # A bad mode fails in the constructor, not in the reader.
        write(path, replace(read(path, String), "grid_forming" => "grid_hopeful"))
        @test_throws ArgumentError read_scenario(path)
    end

    @testset "a model with no inverters writes the file it always did" begin
        path = write_scenario(joinpath(dir, "none.toml"), two_machine_system())
        @test !occursin("inverters", read(path, String))
    end
end

# ---------------------------------------------------------------------------------
# Step 2 — the aggregate tier (m7-plan.md step 2, m7-context.md D4/D9)
# ---------------------------------------------------------------------------------

# A four-bus chain, one generating element per bus (the aggregate's precondition):
# a governed machine, a grid-forming inverter, a load written as a negative-P0
# machine (M2a's convention — `coi_model` refuses `Load`), and a grid-following
# inverter. Every expected number below is computed BY HAND from these literals,
# never through `aggregates`, so the checks cannot read their answer from the code.
#
#   H_sys (all online) = (4·300 + τ/(2K_p)·200 + 0.5·500 + 0·100)/100
#                      = (1200 + 1·200 + 250)/100            = 16.5 s
#   machine damping    = (2·300 + 1·500)/100                 = 11
#   grid-forming 1/K_p = 20 on its own base → 20·200/100     = 40
#   1/R_eq             = (1/0.05)·300/100                    = 60,  headroom 0.6 pu
function _m7_mixed()
    buses = [Bus(Symbol(:B, k), 230.0) for k in 1:4]
    branches = [Branch(:L12, :B1, :B2, 0.1, 500.0), Branch(:L23, :B2, :B3, 0.1, 500.0),
                Branch(:L34, :B3, :B4, 0.1, 500.0)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.3, 1.0, 100.0, 0.05, 160.0, 1.0),
                Machine(:LD, :B3, 500.0, 0.5, 1.0, 0.3, 1.0, -200.0)]
    inverters = [Inverter(:IF, :B2, :grid_forming, 200.0, 60.0),     # K_p 0.05, τ_p 0.1
                 Inverter(:IL, :B4, :grid_following, 100.0, 40.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines; inverters = inverters)
end

@testset "M7 step 2 — the aggregate tier: inertia that is there, and inertia that is not" begin
    net = _m7_mixed()
    sys = coi_model(net)

    @testset "the compiled units" begin
        u = Dict(x.id => x for x in sys.units)
        @test Set(keys(u)) == Set([:G1, :LD, :IF, :IL])
        # Grid-forming: the droop/swing equivalence used as the view (D4).
        @test u[:IF].H == 0.1 / (2 * 0.05) && u[:IF].D == 1 / 0.05
        @test u[:IF].R == Inf && u[:IF].Pmax == u[:IF].P0 == 60.0
        # Grid-following: no rotor, no response — entsoe §1 (a)'s PV block.
        @test u[:IL].H == 0.0 && u[:IL].D == 0.0 && u[:IL].R == Inf
        # Machines keep their damping in the system constant (D9's asymmetry).
        @test u[:G1].D == 0.0 && sys.D ≈ 11.0
    end

    @testset "RoCoF₀, closed form, with both kinds present" begin
        # Trip the grid-following inverter: 40 MW lost, no inertia lost.
        r = trip_and_run(sys, :IL)
        @test r.RoCoF0 ≈ -50 * 0.4 / (2 * 16.5)
        # Trip the grid-forming one: 60 MW lost AND its 1 s·(200/100) of virtual inertia.
        r = trip_and_run(sys, :IF)
        @test r.RoCoF0 ≈ -50 * 0.6 / (2 * 14.5)
    end

    @testset "settling, closed form — and the tripped inverter's damping LEAVES (D9)" begin
        # Grid-following trip: every damping term stays online.
        r = trip_and_run(sys, :IL)
        Δω = -0.4 / (11 + 40 + 60)
        @test r.ΔPm_end < 0.6 - 1e-3                      # precondition: unsaturated
        @test isapprox(r.Δω_end, Δω; rtol = 1e-6)
        # Grid-forming trip: its 40 of damping goes with it.
        r = trip_and_run(sys, :IF)
        Δω_leaves = -0.6 / (11 + 60)
        Δω_stays  = -0.6 / (11 + 40 + 60)                 # what M2's constant-D would give
        @test r.ΔPm_end < 0.6 - 1e-3
        @test isapprox(r.Δω_end, Δω_leaves; rtol = 1e-6)
        # The check discriminates: the two readings are 56 % apart, far outside rtol.
        @test !isapprox(r.Δω_end, Δω_stays; rtol = 0.1)
    end

    @testset "a grid-following inverter's contribution is EXACTLY zero, not small" begin
        all_on = Set(x.id for x in sys.units)
        a = GridSim.aggregates(sys, all_on)
        b = GridSim.aggregates(sys, setdiff(all_on, (:IL,)))
        @test a.H_sys === b.H_sys && a.D === b.D && a.R_eq === b.R_eq &&
              a.headroom === b.headroom
    end

    @testset "displacement: |RoCoF₀| rises by H_sys/(H_sys − H·S/S_base)" begin
        # Four machines, a load, and a fixed 30 MW grid-following unit to trip. Each
        # machine in turn is displaced by a grid-following inverter of the SAME
        # dispatch and rating; the tripped unit carries no inertia, so the post-trip
        # H_sys is the pre-trip one and the ratio is exactly the closed form.
        specs = [(:M1, 300.0, 4.0, 120.0), (:M2, 200.0, 6.0, 80.0),
                 (:M3, 150.0, 2.5, 60.0), (:M4, 400.0, 3.0, 110.0)]
        function fleet(displaced::Union{Nothing,Symbol})
            ids = [first.(specs); :LD; :T]
            buses = [Bus(Symbol(:b, id), 230.0) for id in ids]
            branches = [Branch(Symbol(:l, k), buses[k].id, buses[k+1].id, 0.1, 900.0)
                        for k in 1:length(buses)-1]
            ms = Machine[Machine(:LD, :bLD, 1000.0, 0.2, 0.0, 0.3, 1.0, -400.0)]
            invs = Inverter[Inverter(:T, :bT, :grid_following, 50.0, 30.0)]
            for (id, S, H, P) in specs
                id === displaced ?
                    push!(invs, Inverter(id, Symbol(:b, id), :grid_following, S, P)) :
                    push!(ms, Machine(id, Symbol(:b, id), S, H, 0.0, 0.3, 1.0, P))
            end
            return coi_model(NetworkModel(100.0, 50.0, buses, branches, ms;
                                          inverters = invs))
        end
        H_sys = (4.0 * 300 + 6.0 * 200 + 2.5 * 150 + 3.0 * 400 + 0.2 * 1000) / 100
        base = trip_and_run(fleet(nothing), :T; T = 0.02).RoCoF0
        @test base ≈ -50 * 0.3 / (2 * H_sys)
        for (id, S, H, _) in specs
            disp = trip_and_run(fleet(id), :T; T = 0.02).RoCoF0
            @test disp / base ≈ H_sys / (H_sys - H * S / 100)
        end
    end

    @testset "no inertia online is refused, never integrated (Hurdle 10, D5)" begin
        # Only grid-following inverters: nothing to follow, no weights to average.
        buses = [Bus(:A, 1.0), Bus(:B, 1.0)]
        br = [Branch(:AB, :A, :B, 0.1, 1.0)]
        gfl_only = NetworkModel(100.0, 50.0, buses, br, Machine[];
            inverters = [Inverter(:pv, :A, :grid_following, 50.0, 20.0),
                         Inverter(:bat, :B, :grid_following, 50.0, -20.0)])
        msg = try; coi_model(gfl_only); ""; catch e; e.msg; end
        @test occursin("nothing to follow", msg) && occursin("pv", msg)
        # The engine refuses a zero-inertia model built directly.
        z = SystemModel(100.0, 50.0, 1.0, 1.0,
                        [GeneratingUnit(:pv, 50.0, 0.0, 20.0, Inf, 20.0),
                         GeneratingUnit(:bat, 50.0, 0.0, -20.0, Inf, -20.0)])
        @test_throws ArgumentError init!(FrequencyResponseEngine, z)
        # A trip INTO zero inertia is refused and moves nothing.
        one_gfm = coi_model(NetworkModel(100.0, 50.0, buses, br, Machine[];
            inverters = [Inverter(:gf, :A, :grid_forming, 50.0, 20.0),
                         Inverter(:bat, :B, :grid_following, 50.0, -20.0)]))
        eng = init!(FrequencyResponseEngine, one_gfm; dt = 0.02)
        before = (copy(eng.online), eng.params.H_sys, eng.params.ΔP_dist)
        msg = try; inject!(eng, TripGenerator(:gf)); ""; catch e; e.msg; end
        @test occursin("no inertia online", msg)
        @test (eng.online, eng.params.H_sys, eng.params.ΔP_dist) == before
        # The all-inverter model WITH a grid-forming unit is a legal aggregate.
        @test sum(u.H for u in one_gfm.units) == 1.0
    end

    @testset "the pre-M7 unit is the unit it was" begin
        u = GeneratingUnit(:X, 100.0, 3.0, 50.0, 0.05, 80.0)
        @test u.D === 0.0
        @test_throws ArgumentError GeneratingUnit(:X, 100.0, 3.0, 50.0, 0.05, 80.0, -1.0)
    end
end

# ---------------------------------------------------------------------------------
# Step 3 — the grid-forming inverter in the swing tier (m7-plan.md step 3, Hurdle 11)
# ---------------------------------------------------------------------------------

# A three-bus ring: a machine, a grid-forming inverter, and a load written as a
# negative-P0 machine. The inverter sits on its OWN 150 MVA base (≠ S_base) so that a
# per-unit conversion left out would show. `:machine` builds the SAME network with
# the inverter replaced by a machine whose numbers are converted BY HAND, here, from
# the equivalence 2H = τ_p/K_p, D = 1/K_p on the inverter's own base — never through
# the code under test.
const _S_INV = 150.0
const _KP, _TP = 0.05, 0.1
function _m7_ring(src::Symbol; K_p = _KP)
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)]
    br = [Branch(:L12, :B1, :B2, 0.2, 900.0), Branch(:L23, :B2, :B3, 0.25, 900.0),
          Branch(:L13, :B1, :B3, 0.3, 900.0)]
    ms = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.3, 1.02, 80.0),
          Machine(:G3, :B3, 400.0, 3.0, 1.0, 0.3, 1.0, -140.0)]
    src === :inverter && return NetworkModel(100.0, 50.0, buses, br, ms;
        inverters = [Inverter(:S2, :B2, :grid_forming, _S_INV, 60.0; K_p = K_p,
                              τ_p = _TP, V_set = 1.01)])
    push!(ms, Machine(:S2, :B2, _S_INV, _TP / (2 * K_p), 1 / K_p, 0.3, 1.01, 60.0))
    return NetworkModel(100.0, 50.0, buses, br, ms)
end

# Largest gap over a line trip, angles taken against bus 1 (the fixpoint's gauge is
# arbitrary, so only differences mean anything).
function _m7_equiv_gap(; reltol, abstol, T = 5.0, dt = 0.01)
    a = SwingEngine(_m7_ring(:inverter); reltol, abstol)
    b = SwingEngine(_m7_ring(:machine); reltol, abstol)
    inject!(a, TripLine(:B1, :B2)); inject!(b, TripLine(:B1, :B2))
    gδ = 0.0; gω = 0.0; exc = 0.0
    for _ in 1:round(Int, T / dt)
        sa = step!(a, dt); sb = step!(b, dt)
        gδ = max(gδ, maximum(abs, (sa.δ .- sa.δ[1]) .- (sb.δ .- sb.δ[1])))
        gω = max(gω, maximum(abs, sa.ω .- sb.ω))
        exc = max(exc, abs(sa.ω[2]))
    end
    return (; gδ, gω, exc)
end

@testset "M7 step 3 — grid-forming in the swing tier, checked by its exact equivalence" begin

    @testset "it builds, sits flat, and names what it is" begin
        eng = SwingEngine(_m7_ring(:inverter); reltol = 1e-9, abstol = 1e-12)
        @test machine_ids(eng) == [:G1, :S2, :G3]
        s0 = current_state(eng)
        @test maximum(abs, s0.ω) < 1e-10          # on its fixpoint: no speed anywhere
        for _ in 1:100; step!(eng, 0.01); end
        @test maximum(abs, current_state(eng).ω) < 1e-9   # …and stays there
        # Its COI weight is the virtual inertia τ_p/(2K_p) on its own base, weighted
        # by S_rated/S_base: 1 s · 1.5.
        @test eng.w[2] ≈ _TP / (2 * _KP) * _S_INV / 100
    end

    @testset "equivalence to the hand-converted machine: a gap that is solver error only" begin
        # Measured (m7-tasks.md step 3): 6.5e-11 / 2.4e-12 / 5.3e-14 rad at reltol
        # 1e-6 / 1e-9 / 1e-11, on a speed excursion of 1.4e-3. NOT round-off, as the
        # plan said: the two models integrate different state variables, so the
        # adaptive steps differ — the gap is the solver's, and the check is that it
        # MOVES WITH THE TOLERANCE (the convergence rule), not that it is small once.
        loose = _m7_equiv_gap(; reltol = 1e-6, abstol = 1e-9)
        tight = _m7_equiv_gap(; reltol = 1e-11, abstol = 1e-13)
        @test tight.exc > 1e-3                        # the disturbance is not vacuous
        @test tight.gδ < 1e-12 && tight.gω < 1e-13    # band stated before measuring: 1e-12
        @test tight.gδ < loose.gδ / 100               # …and it falls with the tolerance
        @test tight.gω < loose.gω / 100
    end

    @testset "the check can read a disagreement (anti-vacuity in the test itself)" begin
        # K_p on the inverter differs from the one the machine was converted with:
        # the same network with a 10 % droop error must open a gap far outside the
        # band. (The executed source mutations — wrong base, filter removed — are
        # recorded in m7-tasks.md; this one lives here because it needs no edit.)
        a = SwingEngine(_m7_ring(:inverter; K_p = 0.055); reltol = 1e-11, abstol = 1e-13)
        b = SwingEngine(_m7_ring(:machine); reltol = 1e-11, abstol = 1e-13)
        inject!(a, TripLine(:B1, :B2)); inject!(b, TripLine(:B1, :B2))
        g = 0.0
        for _ in 1:500
            sa = step!(a, 0.01); sb = step!(b, 0.01)
            g = max(g, maximum(abs, sa.ω .- sb.ω))
        end
        @test g > 1e-6
    end

    @testset "where the equivalence breaks, predicted: a setpoint step (Hurdle 11 claim 2)" begin
        # Raise the setpoint (inverter) / mechanical power (machine) by ΔP = 0.1 pu on
        # the system base, at an event boundary, and read the speed WITHOUT stepping.
        # The inverter's ω = −K_p·(P_filt − P_set) is not a state: it jumps by
        # K_p_sys·ΔP = (0.05·100/150)·0.1. The machine's speed is a state: it cannot.
        for (src, expected) in ((:inverter, _KP * 100 / _S_INV * 0.1), (:machine, 0.0))
            eng = SwingEngine(_m7_ring(src); reltol = 1e-9, abstol = 1e-12)
            before = current_state(eng).ω[2]
            eng.params[eng.Pm_pidx[2]] += 0.1
            GridSim.SciMLBase.derivative_discontinuity!(eng.integrator, true)
            @test current_state(eng).ω[2] - before ≈ expected atol = 1e-12
        end
    end

    @testset "cross-check against the aggregate (step 2's deferred check)" begin
        # At a trip instant the swing tier's COI frequency derivative is an exact
        # identity: −f0·P_k/(2·H_sys_post), with the grid-forming inverter weighted at
        # its virtual inertia. Read off the RHS at the event boundary, no step taken.
        for (k, P_k) in ((:G1, 0.8), (:S2, 0.6))
            eng = SwingEngine(_m7_ring(:inverter); reltol = 1e-10, abstol = 1e-12)
            inject!(eng, TripGenerator(k))
            u = eng.integrator.u; p = eng.integrator.p
            du = similar(u); eng.nw(du, u, p, eng.integrator.t)
            rate = sum(eng.w[i] * (eng.droop[i] == 0 ? du[eng.ω_idx[i]] :
                                   -eng.droop[i] * du[eng.ω_idx[i]])
                       for i in eachindex(eng.w)) / eng.Σw
            agg = trip_and_run(coi_model(_m7_ring(:inverter)), k; T = 0.02).RoCoF0
            @test 50 * rate ≈ agg rtol = 1e-8
            @test agg ≈ -50 * P_k / (2 * eng.Σw)     # and the closed form both obey
        end
        # Settling after the grid-forming trip: both tiers drop its damping (the swing
        # tier because the vertex leaves, the aggregate because D9 makes it), so both
        # land on Δω = −0.6/(2·3 + 1·4). (A MACHINE trip would not agree — M2's
        # recorded asymmetry — which is why only this trip is compared.)
        eng = SwingEngine(_m7_ring(:inverter); reltol = 1e-8, abstol = 1e-10)
        inject!(eng, TripGenerator(:S2))
        for _ in 1:3000; step!(eng, 0.02); end
        agg = trip_and_run(coi_model(_m7_ring(:inverter)), :S2)
        @test current_state(eng).ω_coi ≈ -0.6 / 10 rtol = 1e-4
        @test agg.Δω_end ≈ -0.6 / 10 rtol = 1e-6
    end

    @testset "refusals: grid-following, two sources on a bus, shed/ramp on an inverter" begin
        buses = [Bus(:A, 1.0), Bus(:B, 1.0)]
        br = [Branch(:AB, :A, :B, 0.2, 1.0)]
        g = [Machine(:G, :A, 100.0, 4.0, 1.0, 0.3, 1.0, 20.0)]
        gfl = NetworkModel(100.0, 50.0, buses, br, g;
                           inverters = [Inverter(:pv, :B, :grid_following, 50.0, -20.0)])
        msg = try; SwingEngine(gfl); ""; catch e; e.msg; end
        @test occursin("pv", msg) && occursin("tier boundary", msg)
        two = NetworkModel(100.0, 50.0, buses, br,
            [g; Machine(:G2, :B, 100.0, 4.0, 1.0, 0.3, 1.0, -30.0)];
            inverters = [Inverter(:gf, :B, :grid_forming, 50.0, 10.0)])
        @test occursin("carries 2 sources", try; SwingEngine(two); ""; catch e; e.msg; end)
        net = _m7_ring(:inverter)
        @test_throws ArgumentError SwingEngine(net;
            shed = [:S2 => [LoadShedStage(49.0, 10.0)]])
        @test_throws ArgumentError SwingEngine(net;
            ramp = [:S2 => GenerationRamp(0.1, 1.0, 1.0)])
    end

    @testset "no pre-M7 model changes path" begin
        # Every model without inverters takes the old branch: droop all zero, so the
        # speed read-out is the state itself, and the recorded channels are the old
        # ones. (The rest of the suite plus M5's criterion capture are the real gate.)
        eng = SwingEngine(three_machine_ring())
        @test all(==(0.0), eng.droop)
        @test current_state(eng).ω == eng.integrator.u[eng.ω_idx]
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — the grid-forming inverter in the power flows and the detailed tier.
#
# The power flows' twin is step 3's ring with the inverter replaced by a Machine
# carrying the same P0 and V_set — the only two numbers a power flow reads of either
# — and, the ONE place the two differ (m7-context.md D10), the inverter's reactive
# capability at its dispatch as the machine's Q limits, converted BY HAND here from
# the rating: √(S_rated² − P0²)/S_base. `capped = false` drops them, which is the
# anti-vacuity twin: it shows what the inverter would have been asked for.
#
# The twin is ALSO the detailed tier's equivalence oracle (step 4's second half), so
# it carries the rest of Hurdle 11's conversion, by hand, on the inverter's own base:
# `H = τ_p/(2K_p)`, `D = 1/K_p`, and `X′d = X_c` — the classical detailed machine is
# a constant voltage behind `X′d`, which is the grid-forming inverter at `K_q = 0`.
# Its `E′` (1.0) is unread: both are started from `ac_powerflow`, which derives it.
const _XC = 0.1
function _m7_pf_ring(src::Symbol; S_inv = _S_INV, V_set = 1.01, capped = true,
                     K_q = 0.0)
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)]
    br = [Branch(:L12, :B1, :B2, 0.2, 900.0), Branch(:L23, :B2, :B3, 0.25, 900.0),
          Branch(:L13, :B1, :B3, 0.3, 900.0)]
    ms = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.3, 1.02, 80.0),
          Machine(:G3, :B3, 400.0, 3.0, 1.0, 0.3, 1.0, -140.0)]
    src === :inverter && return NetworkModel(100.0, 50.0, buses, br, ms;
        inverters = [Inverter(:S2, :B2, :grid_forming, S_inv, 60.0; V_set = V_set,
                              K_p = _KP, τ_p = _TP, K_q = K_q, X_c = _XC)])
    q = sqrt(S_inv^2 - 60.0^2) / 100
    push!(ms, Machine(:S2, :B2, S_inv, _TP / (2 * _KP), 1 / _KP, _XC, 1.0, 60.0;
                      V_set = V_set, Q_min = capped ? -q : -Inf, Q_max = capped ? q : Inf))
    return NetworkModel(100.0, 50.0, buses, br, ms)
end

_m7_same(a::ACPowerFlow, b::ACPowerFlow) =
    a.Vm == b.Vm && a.θ == b.θ && a.Pgen == b.Pgen && a.Qgen == b.Qgen &&
    a.roles == b.roles && a.limited == b.limited && a.flow == b.flow

@testset "M7 step 4 — the power flows learn the grid-forming inverter" begin

    @testset "AC: bit-identical to the machine twin, and the cap far from binding" begin
        a = ac_powerflow(_m7_pf_ring(:inverter))
        @test _m7_same(a, ac_powerflow(_m7_pf_ring(:machine)))
        # Nothing binds, so ONE solve happened on both sides, and the uncapped twin
        # is the same answer again — the limit is present and not acting.
        @test _m7_same(a, ac_powerflow(_m7_pf_ring(:machine; capped = false)))
        @test isempty(a.limited) && a.roles[2] === :generator
        @test bus_voltage(a, :B2) == 1.01                  # it holds its V_set
        @test bus_generation(a, :B2).P ≈ 0.6 atol = 1e-12
        # Measured (D10): 0.158 pu asked against a 1.375 pu capability.
        @test abs(bus_generation(a, :B2).Q) < sqrt(1.5^2 - 0.6^2) / 5
    end

    @testset "AC: the rating binds, and the inverter is the CAPPED machine (D10)" begin
        # 65 MVA at 60 MW leaves √(65² − 60²) = 25 MVAr; at V_set = 1.05 the bus is
        # asked for 0.539 pu (measured on the uncapped twin), so the switch fires.
        a = ac_powerflow(_m7_pf_ring(:inverter; S_inv = 65.0, V_set = 1.05))
        @test a.limited == [:B2] && a.roles[2] === :load
        @test bus_generation(a, :B2).Q ≈ 0.25 atol = 1e-9
        @test bus_voltage(a, :B2) < 1.05                   # it could not hold V_set
        @test _m7_same(a, ac_powerflow(_m7_pf_ring(:machine; S_inv = 65.0, V_set = 1.05)))
        # Anti-vacuity: WITHOUT the rating the same bus takes 0.539 pu and holds 1.05.
        u = ac_powerflow(_m7_pf_ring(:machine; S_inv = 65.0, V_set = 1.05, capped = false))
        @test isempty(u.limited) && bus_generation(u, :B2).Q > 0.5
    end

    @testset "DC: the inverter is an injection like a machine's" begin
        @test dc_powerflow(_m7_pf_ring(:inverter)).θ == dc_powerflow(_m7_pf_ring(:machine)).θ
        P = bus_injections(_m7_pf_ring(:inverter))
        @test P == bus_injections(_m7_pf_ring(:machine))
        @test P[2] == 0.6 && abs(sum(P)) < 1e-15
    end

    @testset "AC: a grid-forming SLACK is checked against its rating (D10's blind spot)" begin
        # No machine at all: the grid-forming inverter is the default reference, and
        # the slack's reactive limit is not enforced by switching — so the rating is
        # checked after the solve. A CONSTANT-POWER 40 MW + 30 MVAr load plus the
        # line's I²X needs ~51.6 MVA (40 MW, 32.7 MVAr solved): a 60 MVA inverter holds
        # it, a 50 MVA one is refused by name. (Constant power so the hand estimate is
        # the load's own number: the default constant-impedance load draws P0·|V|² at
        # the solved 0.97 pu and needs only 48.5 MVA — measured, and why it is not
        # the fixture.)
        mk(S) = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)],
                             [Branch(:AB, :A, :B, 0.1, 500.0)], Machine[],
                             [Load(:D, :B, 40.0, 30.0, 0.0, 0.0, 1.0)];
                             inverters = [Inverter(:gf, :A, :grid_forming, S, 40.0)])
        @test mk(60.0).slack === :A
        ok = ac_powerflow(mk(60.0))
        g = bus_generation(ok, :A)
        @test g.P ≈ 0.4 atol = 1e-12
        @test 0.5 < hypot(g.P, g.Q) < 0.52
        msg = try; ac_powerflow(mk(50.0)); ""; catch e; e.msg; end
        @test occursin("slack bus A", msg) && occursin("rated 50.0 MVA", msg)
    end

    @testset "grid-following is still refused by the power flows (step 5)" begin
        net = _m7_pair(mode = :grid_following)
        for f in (ac_powerflow, dc_powerflow, bus_injections)
            msg = try; f(net); ""; catch e; e.msg; end
            @test occursin("I2", msg) && occursin("step 5", msg)
        end
    end
end

# The equivalence run: inverter and hand-converted machine twin, BOTH started from
# `ac_powerflow` (bit-identical flows, the previous testset), a line trip, one grid.
function _m7_det_gap(; reltol, abstol, K_q = 0.0, T = 5.0)
    a = init!(DetailedEngine, _m7_pf_ring(:inverter; K_q);
              powerflow = ac_powerflow(_m7_pf_ring(:inverter; K_q)), reltol, abstol)
    b = init!(DetailedEngine, _m7_pf_ring(:machine);
              powerflow = ac_powerflow(_m7_pf_ring(:machine)), reltol, abstol)
    sa, sb = current_state(a), current_state(b)
    # At t = 0: the same voltages and the same source angle, EXACTLY — the two start
    # from bit-identical flows through the same `E∠δ = V + jX·I` construction.
    t0 = max(maximum(abs, sa.V .- sb.V),
             abs((sa.δ_inv[1] - sa.δ[1]) - (sb.δ[2] - sb.δ[1])))
    grid = 0.0:0.01:T
    for e in (a, b)
        solve!(e, (0.0, T); perturbations = [1.0 => TripLine(:B1, :B2)], saveat = grid)
    end
    A, B = state_series(a), state_series(b)
    gδ = maximum(abs, (A.δ_S2 .- A.δ_G1) .- (B.δ_S2 .- B.δ_G1))
    gω = maximum(abs, A.ω_S2 .- B.ω_S2)
    gV = maximum(maximum(abs, getproperty(A, s) .- getproperty(B, s))
                 for s in (:V_B1, :V_B2, :V_B3))
    return (; t0, gδ, gω, gV, exc = maximum(abs, A.ω_S2))
end

@testset "M7 step 4 — grid-forming in the detailed tier, voltage droop live" begin

    @testset "it builds on its own steady state, holds V_set at the bus, sits flat" begin
        eng = init!(DetailedEngine, _m7_pf_ring(:inverter))
        s = current_state(eng)
        @test s.V[2] ≈ 1.01 atol = 1e-12          # V_set is the BUS voltage (D11)
        @test s.E_inv[1] > s.V[2]                  # it forms more behind X_c to export Q
        @test abs(s.ω_inv[1]) < 1e-15
        # Channels: the machines', then the inverter's three, then the buses'.
        @test collect(keys(state_series(eng))) ==
            [:t, :δ_G1, :δ_G3, :ω_G1, :ω_G3, :E′q_G1, :E′q_G3, :E′d_G1, :E′d_G3,
             :Efd_G1, :Efd_G3, :δ_S2, :ω_S2, :E_S2, :V_B1, :V_B2, :V_B3, :δ_coi, :f_coi]
        solve!(eng, (0.0, 2.0))
        ss = state_series(eng)
        @test maximum(abs, ss.ω_S2) < 1e-12
        @test maximum(abs, ss.V_B2 .- s.V[2]) < 1e-12
        # Its COI weight is the virtual inertia, by hand: (4·300 + 3·400)/100 machines
        # + τ_p/(2K_p)·150/100 = 1.5 for the inverter.
        @test system_inertia(eng) ≈ 24.0 + 1.5 atol = 1e-12
        @test machine_ids(eng) == [:G1, :G3]      # machines only, as before
    end

    @testset "its steady state agrees with ac_powerflow where both hold the bus voltage" begin
        # Every source a grid-forming inverter, so the engine's own static solve and
        # the separately written power flow hold THE SAME unknowns: two independent
        # solves of one schedule. (With a machine they differ by design — the
        # machine's static vertex holds E′, the power flow its V_set.) The gauge
        # differs — the engine pins the slack inverter's formed angle, the power flow
        # its bus angle — so angles are compared as differences.
        net = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0), Bus(:C, 1.0)],
            [Branch(:AC, :A, :C, 0.2, 500.0), Branch(:BC, :B, :C, 0.25, 500.0),
             Branch(:AB, :A, :B, 0.3, 500.0)], Machine[], [Load(:D, :C, 90.0, 20.0)];
            inverters = [Inverter(:iA, :A, :grid_forming, 150.0, 50.0; V_set = 1.02),
                         Inverter(:iB, :B, :grid_forming, 100.0, 40.0)])
        eng = init!(DetailedEngine, net)             # no machine at all: iA is the slack
        pf = ac_powerflow(net)
        u = eng.integrator.u
        V = [complex(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]]) for v in 1:3]
        @test maximum(abs, abs.(V) .- pf.Vm) < 1e-11
        @test maximum(abs, (angle.(V) .- angle(V[1])) .- pf.θ) < 1e-11
        # …and the seeded engine is the same operating point.
        eng2 = init!(DetailedEngine, net; powerflow = pf)
        @test maximum(abs, current_state(eng2).V .- current_state(eng).V) < 1e-11
        @test maximum(abs, current_state(eng2).E_inv .- current_state(eng).E_inv) < 1e-11
    end

    @testset "equivalence at K_q = 0: exact at t = 0, solver error after (Hurdle 11)" begin
        # Pre-registered from step 3: the two integrate different states, so the gap
        # after the trip is the SOLVER's, and the check is that it falls with the
        # tolerance. Measured: 6.1e-8 / 9.8e-10 / 9.3e-12 rad at reltol 1e-6/1e-8/1e-10.
        loose = _m7_det_gap(; reltol = 1e-6, abstol = 1e-8)
        tight = _m7_det_gap(; reltol = 1e-10, abstol = 1e-12)
        @test tight.t0 == 0.0 && loose.t0 == 0.0
        @test tight.exc > 1e-3                        # the trip is not vacuous
        @test tight.gδ < 1e-10 && tight.gω < 1e-11 && tight.gV < 1e-9
        @test tight.gδ < loose.gδ / 100 && tight.gV < loose.gV / 100
    end

    @testset "K_q live: the equivalence ends, and the voltage droops by hand's gain" begin
        g = _m7_det_gap(; reltol = 1e-10, abstol = 1e-12, K_q = 0.05)
        @test g.gδ > 1e-5 && g.gV > 1e-4             # ~4e7 × the K_q = 0 gap
        # E = V_ref − K_q·Q_filt at every instant, with K_q converted BY HAND to the
        # system base (0.05·100/150). Read against the Q_filt STATE, so a flipped sign
        # or an unconverted gain in the droop law cannot agree with itself here.
        net = _m7_pf_ring(:inverter; K_q = 0.05)
        eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net),
                    reltol = 1e-10, abstol = 1e-12)
        E0 = current_state(eng).E_inv[1]; Q0 = eng.integrator.u[eng.gfm.Qf_idx[1]]
        solve!(eng, (0.0, 3.0); perturbations = [0.5 => TripLine(:B1, :B2)])
        E1 = current_state(eng).E_inv[1]; Q1 = eng.integrator.u[eng.gfm.Qf_idx[1]]
        @test abs(E1 - E0) > 1e-4
        @test E1 - E0 ≈ -(0.05 * 100 / 150) * (Q1 - Q0) rtol = 1e-9
    end

    @testset "a setpoint step moves its frequency instantly (Hurdle 11 claim 2)" begin
        eng = init!(DetailedEngine, _m7_pf_ring(:inverter))
        before = current_state(eng)
        eng.params[eng.gfm.Pset_pidx[1]] += 0.1
        after = current_state(eng)
        @test after.ω_inv[1] - before.ω_inv[1] ≈ 0.05 * 100 / 150 * 0.1 atol = 1e-15
        # …and the COI frequency sees it at its virtual-inertia weight, machines at rest.
        @test after.ω_coi ≈ 1.5 * after.ω_inv[1] / 25.5 atol = 1e-15
    end

    @testset "a line trip re-solves the network and HOLDS the inverter's states" begin
        eng = init!(DetailedEngine, _m7_pf_ring(:inverter; K_q = 0.05))
        s0 = current_state(eng)
        inject!(eng, TripLine(:B1, :B2))
        s1 = current_state(eng)
        @test s1.δ_inv == s0.δ_inv && s1.E_inv == s0.E_inv   # differential: held
        @test abs(s1.V[2] - s0.V[2]) > 1e-4                  # algebraic: re-solved (9.3e-4)
        du = similar(eng.integrator.u)
        eng.nw(du, eng.integrator.u, eng.params, eng.integrator.t)
        @test maximum(abs, du[eng.Vre_idx]) < 1e-10          # on the post-trip network
        @test maximum(abs, du[eng.Vim_idx]) < 1e-10
    end

    @testset "the rating at this tier: the own steady state refuses, the power flow caps (D10)" begin
        # 65 MVA at 60 MW, V_set = 1.05: holding the bus there needs 0.539 pu of Q
        # against a 0.25 pu capability. The engine's own solve has no reactive limit,
        # so it refuses by name and points at the capped path — which builds, sits
        # exactly at the rating, and is flat.
        net = _m7_pf_ring(:inverter; S_inv = 65.0, V_set = 1.05)
        msg = try; init!(DetailedEngine, net); ""; catch e; e.msg; end
        @test occursin("S2", msg) && occursin("powerflow = ac_powerflow", msg)
        eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net))
        u = eng.integrator.u
        V = complex(u[eng.Vre_idx[2]], u[eng.Vim_idx[2]])
        s = current_state(eng)
        I = (s.E_inv[1] * cis(s.δ_inv[1]) - V) / (im * 0.1 * 100 / 65)   # X_c by hand
        @test abs(V * conj(I)) ≈ 0.65 rtol = 1e-9
        solve!(eng, (0.0, 1.0))
        @test maximum(abs, state_series(eng).ω_S2) < 1e-12
    end

    @testset "refusals, each by name" begin
        msg = try; init!(DetailedEngine, _m7_pair(mode = :grid_following)); ""; catch e; e.msg; end
        @test occursin("I2", msg) && occursin("step 5", msg)
        buses = [Bus(:A, 1.0), Bus(:B, 1.0)]
        br = [Branch(:AB, :A, :B, 0.2, 500.0)]
        g = [Machine(:G, :A, 100.0, 4.0, 1.0, 0.3, 1.0, 20.0)]
        two = NetworkModel(100.0, 50.0, buses, br,
            [g; Machine(:G2, :B, 100.0, 4.0, 1.0, 0.3, 1.0, -30.0)];
            inverters = [Inverter(:gf, :B, :grid_forming, 50.0, 10.0)])
        @test occursin("carries 2 sources",
                       try; init!(DetailedEngine, two); ""; catch e; e.msg; end)
        net = _m7_pf_ring(:inverter)
        for kw in ((; shed = [:S2 => [LoadShedStage(49.0, 10.0)]]),
                   (; ramp = [:S2 => GenerationRamp(0.1, 1.0, 1.0)]))
            m = try; init!(DetailedEngine, net; kw...); ""; catch e; e.msg; end
            @test occursin("grid-forming inverter", m) && occursin("S2", m)
        end
        # A relay between a machine and an inverter WATCHES THE INVERTER'S ANGLE: its
        # start guard fires exactly when the threshold is below |δ_G1 − δ_S2|.
        s = current_state(init!(DetailedEngine, net))
        d = abs(s.δ[1] - s.δ_inv[1])
        @test_throws ArgumentError init!(DetailedEngine, net;
                                         out_of_step = [(:B1, :B2) => 0.99d])
        @test init!(DetailedEngine, net; out_of_step = [(:B1, :B2) => 1.01d]) isa DetailedEngine
    end

    @testset "found, not planned: the relay read a machine's angle by BUS number" begin
        # M5 step 7's binder indexed the machine-indexed δ by a bus vertex. On a model
        # whose middle bus carries no machine, a relay on B1–B2 read G3's rotor angle as
        # B2's (measured: its start guard fired at 0.99·|δ_G1 − δ_G3| and its message
        # called that number "the angle across that branch"), and one on B2–B3 threw a
        # BoundsError. Every relay fixture had a machine on every bus. Now: refused by
        # name, because a bus with no source has no angle to watch.
        net = NetworkModel(100.0, 50.0, [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
            [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0),
             Branch(:L13, :B1, :B3, 0.25, 500.0)],
            [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 80.0),
             Machine(:G3, :B3, 400.0, 5.0, 2.0, 0.30, 1.04, 30.0)],
            [Load(:D2, :B2, 110.0, 30.0)])
        for pr in ((:B1, :B2), (:B2, :B3))
            m = try; init!(DetailedEngine, net; out_of_step = [pr => 1.0]); ""; catch e; e.msg; end
            @test occursin("bus B2 carries no machine", m)
        end
        # A relay between the two machines is untouched.
        @test init!(DetailedEngine, net; out_of_step = [(:B1, :B3) => 1.0]) isa DetailedEngine
    end
end
