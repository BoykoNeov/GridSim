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
            @test refuses(() -> coi_model(net))
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
            @test r === :refused || n in views
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
