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
            @test refuses(() -> SwingEngine(net))
            @test refuses(() -> init!(DetailedEngine, net))
            @test refuses(() -> ac_powerflow(net))
            @test refuses(() -> dc_powerflow(net))
            @test refuses(() -> bus_injections(net))   # exported on its own
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
