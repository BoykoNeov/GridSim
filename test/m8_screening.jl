# ─────────────────────────────────────────────────────────────────────────────
# M8 — single-outage screening (m8-plan.md, m8-context.md)
#
# Step 1: the AC solve's checks RETURN a verdict, and `_ac_powerflow_outcome`
# classifies a solve instead of throwing on it (D3). That `ac_powerflow` itself did
# not move by a bit is proved OUTSIDE this suite, by digest, before and after the
# edit: every field of 83 solves and every refusal's full text, and M5's 169
# criterion values (m8-tasks.md step 1). What is asserted here is that the two entry
# points are ONE solve read two ways, and that the screen's vocabulary says what the
# solve found.
#
# The fixture is `_ed_case9` (test/m6_economic_dispatch.jl): case9 WITHOUT line
# charging, so never called case9, and every voltage below carries that caveat. Part
# of each sag is the missing shunt and not the outage (m8-context.md D0, Hurdle 13.4).
# ─────────────────────────────────────────────────────────────────────────────

# `net` with branch `id` removed and everything else the same. A bridge leaves a
# disconnected model, which `NetworkModel` refuses, so that outage throws here.
_m8_without(net::NetworkModel, id::Symbol) = NetworkModel(net.S_base, net.f0, net.buses,
    filter(b -> b.id !== id, net.branches), net.machines, net.loads;
    slack = net.slack, inverters = net.inverters)

# `net` with every branch rating scaled by `k`. At their own ratings no case9 outage
# overloads (measured at step 1), so the overload is constructed.
_m8_rated(net::NetworkModel, k::Real) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, k * b.rating; R = b.R) for b in net.branches],
    net.machines, net.loads; slack = net.slack, inverters = net.inverters)

# `net` with every machine's reactive range set to `±q` pu.
_m8_qlim(net::NetworkModel, q::Real) = NetworkModel(net.S_base, net.f0, net.buses,
    net.branches, [GridSim._machine_with(m; Q_min = -q, Q_max = q) for m in net.machines],
    net.loads; slack = net.slack, inverters = net.inverters)

const _M8_RING = (:L45, :L56, :L67, :L78, :L89, :L94)   # case9's non-bridge lines

# What `ac_powerflow` throws on `net`, or `nothing` when it returns.
_m8_thrown(f) = try; f(); nothing; catch e; e; end

@testset "M8 step 1 — the AC checks return a verdict, ac_powerflow unmoved" begin

    @testset "the outcome IS ac_powerflow's solve, read two ways" begin
        # Every fixture: `:secure` exactly when `ac_powerflow` returns, with every field
        # `==` (exactness is available, because it is the same code); any other
        # outcome exactly when it throws, with the message its `detail` names first.
        # BLIND BY CONSTRUCTION to a precedence change: both read one ordered body, so
        # a reorder moves them together. The precedence testset below carries that.
        for load in (315.0, 400.0), zip in (false, true), k in (1.0, 0.6),
            out in (nothing, _M8_RING...)
            base = _m8_rated(_ed_case9(; load, zip_default = zip), k)
            net = out === nothing ? base : _m8_without(base, out)
            r = GridSim._ac_powerflow_outcome(net)
            e = _m8_thrown(() -> ac_powerflow(net))
            if r.outcome === :secure
                s = ac_powerflow(net)
                @test e === nothing && r.detail === nothing
                @test all(getfield(r.solution, f) == getfield(s, f)
                          for f in fieldnames(ACPowerFlow))
            elseif r.outcome === :voltage
                @test e isa ErrorException && r.solution === nothing &&
                      startswith(e.msg, "ac_powerflow: bus $(r.detail[1].bus) solved to " *
                                        "|V| = $(r.detail[1].Vm) pu")
            elseif r.outcome === :overload
                @test e isa ErrorException && r.solution isa ACPowerFlow &&
                      startswith(e.msg, "ac_powerflow: branch $(r.detail[1].id) carries " *
                                        "$(r.detail[1].mva) MVA")
            else
                @test r.outcome === :no_solution && r.solution === nothing &&
                      e isa ErrorException && e.msg == r.detail.message
            end
        end
    end

    @testset "case9's step-0 outages, by name (no line charging)" begin
        # Step 0's table (m8-context.md D1), now as outcomes rather than exceptions.
        net = _ed_case9()                                   # 315 MW, constant power
        @test GridSim._ac_powerflow_outcome(net).outcome === :secure
        for out in (:L56, :L67, :L78, :L89)
            @test GridSim._ac_powerflow_outcome(_m8_without(net, out)).outcome === :secure
        end
        r = GridSim._ac_powerflow_outcome(_m8_without(net, :L45))
        @test r.outcome === :voltage && [d.bus for d in r.detail] == [:B5]
        @test r.detail[1].Vm ≈ 0.8730414946677753 atol = 1e-9
        r = GridSim._ac_powerflow_outcome(_m8_without(net, :L94))
        @test r.outcome === :voltage && [d.bus for d in r.detail] == [:B9]
        @test r.detail[1].Vm ≈ 0.7574234847593181 atol = 1e-9

        # 400 MW: four voltage refusals, one secure (L67), one non-convergence (L94).
        # Step 0's prose said "five of six for voltage"; its own log says four, and so
        # does this (m8-context.md D1, corrected at step 1).
        hot = _ed_case9(; load = 400.0)
        o(out) = GridSim._ac_powerflow_outcome(_m8_without(hot, out))
        @test [o(x).outcome for x in _M8_RING] ==
              [:voltage, :voltage, :secure, :voltage, :voltage, :no_solution]
        @test o(:L94).detail.reason === :newton
        # EVERY bus outside the band is listed, not only the one `ac_powerflow` names.
        @test [d.bus for d in o(:L56).detail] == [:B5, :B9]

        # The bridges never reach the solve: the model itself refuses them, so
        # `:splits` is decided from the graph (step 2), never returned from here.
        for out in (:L14, :L36, :L82)
            @test_throws ArgumentError _m8_without(net, out)
        end
    end

    @testset "a constructed overload lists EVERY branch over, and keeps its solution" begin
        # Ratings at 60 %, 400 MW, L67 out: four branches over. Each listed one is
        # over, each unlisted one is not, recomputed here from the returned flows at
        # both ends (the rating binds the heavier end of a lossy branch).
        net = _m8_without(_m8_rated(_ed_case9(; load = 400.0), 0.6), :L67)
        r = GridSim._ac_powerflow_outcome(net)
        @test r.outcome === :overload
        @test [d.id for d in r.detail] == [:L14, :L56, :L82, :L94]    # branch order
        @test all(d.kind === :branch for d in r.detail)
        s = r.solution
        mva = [100.0 * max(hypot(s.flow[e], s.qflow[e]), hypot(s.flow_rev[e], s.qflow_rev[e]))
               for e in eachindex(s.branches)]
        over = [s.branches[e] for e in eachindex(mva) if mva[e] > net.branches[e].rating]
        @test over == [d.id for d in r.detail]
        for d in r.detail
            e = findfirst(==(d.id), s.branches)
            @test d.mva ≈ mva[e] rtol = 1e-14
            @test d.rating == net.branches[e].rating
        end
        # It is in band: the overload is the outcome only because the band passed.
        @test all(0.9 .<= s.Vm .<= 1.1)
        # And `ac_powerflow` refuses the same model, naming the first.
        @test occursin("branch L14 carries", _m8_thrown(() -> ac_powerflow(net)).msg)
    end

    @testset "precedence: the band masks an overload on the same solve (D3)" begin
        # 400 MW, L89 out, ratings as published: B9 sags to 0.854 pu AND L56 carries
        # more than its 150 MVA. The band runs first, so the outcome is `:voltage`.
        # This fixture is the one where the order is visible; on L45 at 315 MW nothing
        # is over a rating, so swapping the order could not change that answer, and
        # the plan's "L45 reports `:overload` or `:secure`" was unreachable (step 1).
        net = _m8_without(_ed_case9(; load = 400.0), :L89)
        r = GridSim._ac_powerflow_outcome(net)
        @test r.outcome === :voltage && [d.bus for d in r.detail] == [:B9]

        # The masked overload is real, read off the same solve's first round. The
        # reactive limits here are ±3 pu and do not bind, so the first round IS the
        # solve, which the bit-equal magnitude shows.
        c, x0 = GridSim._ac_first_round(net)
        Vm, θ = GridSim._ac_expand(c, first(GridSim._ac_newton(c, x0, 1e-12, 200)))
        @test Vm[net.bus_index[:B9]] == r.detail[1].Vm
        V = Vm .* cis.(θ)
        b = net.branches[findfirst(x -> x.id === :L56, net.branches)]
        f, t = net.bus_index[b.from], net.bus_index[b.to]
        I = inv(complex(b.R, b.X)) * (V[f] - V[t])
        @test 100.0 * max(abs(V[f] * conj(I)), abs(V[t] * conj(-I))) > b.rating
    end

    @testset "switching is part of the outcome's solve, not skipped (D3)" begin
        # `_ac_first_round` skips reactive-limit switching, so it is a different model
        # (D3's rejected alternative). On ±0.3 pu limits both generator buses bind,
        # and the outcome's solution says so.
        net = _m8_qlim(_ed_case9(), 0.3)
        r = GridSim._ac_powerflow_outcome(net)
        @test r.outcome === :secure && r.solution.limited == [:B2, :B3]
        # And a switching loop that cannot settle is `:no_solution`, by reason, with
        # the message `ac_powerflow` throws given the same keyword.
        r0 = GridSim._ac_powerflow_outcome(net; max_switch_rounds = 0)
        @test r0.outcome === :no_solution && r0.detail.reason === :switching
        @test _m8_thrown(() -> ac_powerflow(net; max_switch_rounds = 0)).msg == r0.detail.message
    end

    @testset "the refusals D3's table did not name, each decided by name" begin
        # A grid-forming slack over its rating: `:overload`, kind `:inverter_slack`.
        # The network solved; the source cannot carry it (M7's fixture, 50 vs 60 MVA).
        mk(S) = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)],
                             [Branch(:AB, :A, :B, 0.1, 500.0)], Machine[],
                             [Load(:D, :B, 40.0, 30.0, 0.0, 0.0, 1.0)];
                             inverters = [Inverter(:gf, :A, :grid_forming, S, 40.0)])
        @test GridSim._ac_powerflow_outcome(mk(60.0)).outcome === :secure
        r = GridSim._ac_powerflow_outcome(mk(50.0))
        @test r.outcome === :overload && r.solution isa ACPowerFlow
        @test only(r.detail).kind === :inverter_slack && only(r.detail).id === :A
        @test only(r.detail).rating == 50.0 && 50.0 < only(r.detail).mva < 52.0
        @test occursin("rated 50.0 MVA", _m8_thrown(() -> ac_powerflow(mk(50.0))).msg)

        # A slack bus with no voltage source still THROWS, from both entry points:
        # what a screen does when it loses the reference's source is steps 4–6's
        # decision (Hurdle 14.2), not this function's.
        bare = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)],
                            [Branch(:AB, :A, :B, 0.1, 500.0)],
                            [Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 40.0, Inf, 50.0)],
                            [Load(:D, :B, 40.0, 30.0)]; slack = :A)
        @test_throws ArgumentError GridSim._ac_powerflow_outcome(bare)
        @test_throws ArgumentError ac_powerflow(bare)
    end

    @testset "a residual over the threshold is `:no_solution`, and strips an overload's solution" begin
        # Reached through the solve by loosening the Newton's own `abstol`: at 1e-6 it
        # stops at an iterate whose residual is ~3e-7, above the 1e-10 the check
        # demands (measured at step 1; at 1e-7 and tighter it lands at ~1e-14). First
        # written as "unreachable through the solve", which was never tried.
        net = _ed_case9()
        r = GridSim._ac_powerflow_outcome(net; abstol = 1e-6)
        @test r.outcome === :no_solution && r.detail.reason === :residual
        @test _m8_thrown(() -> ac_powerflow(net; abstol = 1e-6)).msg == r.detail.message
        @test GridSim._ac_powerflow_outcome(net; abstol = 1e-7).outcome === :secure
        # On an overload the ratings run before the residual, so the outcome stays
        # `:overload` with its branches listed, but the solution is withheld: an
        # unverified solve's flows are not a result.
        hot = _m8_without(_m8_rated(_ed_case9(; load = 400.0), 0.6), :L67)
        r = GridSim._ac_powerflow_outcome(hot; abstol = 1e-6)
        @test r.outcome === :overload && r.solution === nothing
        @test [d.id for d in r.detail] == [:L14, :L56, :L82, :L94]
        @test GridSim._ac_powerflow_outcome(hot).solution isa ACPowerFlow
    end

    @testset "the verdict pieces return every offender; the throwing checks take the first" begin
        # Back-off is `:no_solution` by reason, but no fixture reaches it through the
        # solve (M6 D12 found the same), so its piece is checked directly, like the
        # other three. The residual is reached through the solve (testset above).
        net = three_machine_ring()
        Vm = [0.5, 1.0, 1.2]
        @test GridSim._voltage_band_violations(net, Vm) == [1, 3]
        e = _m8_thrown(() -> GridSim._check_voltage_band(net, Vm, "unit"))
        @test startswith(e.msg, "unit: bus $(net.buses[1].id) solved to |V| = 0.5 pu")
        flows = [100.0, 0.0, 100.0]
        @test GridSim._rating_violations(net, flows) == [1, 3]
        e = _m8_thrown(() -> GridSim._check_branch_ratings(net, flows, "unit"))
        @test startswith(e.msg, "unit: branch $(net.branches[1].id) carries")
        @test GridSim._residual_ok(0.0) && !GridSim._residual_ok(1.0)
        # Both switched buses on the wrong side of their setpoints: both listed.
        @test GridSim._ac_backoff_violations([2, 3], [true, false],
                                             [1.0, 1.10, 0.90], [1.0, 1.05, 0.95]) == [1, 2]
        @test GridSim._ac_backoff_violations([2, 3], [true, false],
                                             [1.0, 1.00, 1.00], [1.0, 1.05, 0.95]) == Int[]
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: the DC line-outage factors (`dc_line_outages`), checked against the
# brute force they stand in for — rebuild the model without the branch and solve
# again. Both share `_dc_susceptance` and `bus_injections`, so a fault THERE is
# invisible to this comparison by construction; M6 step 2's independent three-bus
# check carries those (m8-context.md D0, Hurdle 13.1).
#
# Bands, stated before any gap was seen (m8-tasks.md step 2): 100·eps·max|f| on an
# ordinary grid, and 100·eps·max|f| / (1 − PTDF_kk) on a nearly-split one.
# ─────────────────────────────────────────────────────────────────────────────

# Step 0's meshed fixture: A–B–C–D with B and C of degree 3 and unequal reactances,
# plus a spur D–E, so exactly one bridge. Constant-power loads; the DC solve reads
# only `P` anyway.
_m8_mesh_branches() = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
                       Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
                       Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0)]
_m8_mesh(branches = _m8_mesh_branches(); slack = :A, loadE = :E,
         buses = (:A, :B, :C, :D, :E)) =
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in buses], branches,
                 [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 150.0),
                  Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0)],
                 [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0),
                  Load(:LD, :D, 90.0, 25.0, 0.0, 0.0, 1.0),
                  Load(:LE, loadE, 40.0, 10.0, 0.0, 0.0, 1.0)]; slack)

# Brute force for outage `k`: every branch's flow after rebuilding without it, in
# `net`'s branch order with entry `k` zero, or `nothing` where the model is refused
# as disconnected (that refusal, and no other, is a split).
function _m8_rebuilt(net::NetworkModel, k::Int)
    rest = try
        _m8_without(net, net.branches[k].id)
    catch e
        e isa ArgumentError && occursin("not connected", e.msg) || rethrow()
        return nothing
    end
    out = zeros(length(net.branches))
    out[[j for j in eachindex(net.branches) if j != k]] = dc_powerflow(rest).flow
    return out
end

# Worst `gap / band` over every non-split outage, with the band divided by the
# margin when `near`. Also checks the split set against the brute-force refusals.
function _m8_vs_rebuilt(net::NetworkModel; near = false)
    s = dc_line_outages(net)
    worst = 0.0
    for k in eachindex(net.branches)
        bf = _m8_rebuilt(net, k)
        @test s.splits[k] == (bf === nothing)
        bf === nothing && continue
        scale = max(maximum(abs, s.base.flow), maximum(abs, bf))
        band = 100 * eps() * scale / (near ? s.margin[k] : 1.0)
        worst = max(worst, maximum(abs.(s.flow[k] .- bf)) / band)
        @test s.flow[k][k] === 0.0
    end
    return worst
end

@testset "M8 step 2 — DC line-outage factors, bridges from the graph" begin

    @testset "one sparse factorisation: the reduced matrix holds what the branch list predicts" begin
        # n + 2m for the full matrix (M6 step 2), less the reference bus's diagonal and
        # its 2·degree off-diagonals. A, the mesh's reference, has degree 2; case9's B1
        # has degree 1.
        for (net, deg) in ((_m8_mesh(), 2), (_ed_case9(), 1))
            n, m = length(net.buses), length(net.branches)
            Br, keep = GridSim._dc_reduced_susceptance(net, inv.(branch_topology(net).X))
            @test size(Br) == (n - 1, n - 1) && length(keep) == n - 1
            @test SparseArrays.nnz(Br) == n + 2m - 1 - 2deg
            @test !(net.bus_index[net.slack] in keep)
        end
    end

    @testset "splits come from the graph and equal the rebuild refusals" begin
        mesh = dc_line_outages(_m8_mesh())
        @test mesh.base.branches[mesh.splits] == [:DE]
        @test isempty(mesh.flow[6])
        c9 = dc_line_outages(_ed_case9())
        @test Set(c9.base.branches[c9.splits]) == Set([:L14, :L36, :L82])
        @test all(isempty, c9.flow[c9.splits])
        # At a bridge `1 − PTDF_kk` is round-off — which is why it is never tested.
        @test all(abs.(c9.margin[c9.splits]) .<= 10eps())
        # On a single ring with everything else radial, a ring line's margin is its
        # own reactance over the ring's total — a closed form that shares no code with
        # the rebuild, so it is the one check on the margin itself. (A first `> 0.1`
        # floor, set after seeing the numbers, was replaced at review.)
        ring = [b.id in _M8_RING for b in _ed_case9().branches]
        @test ring == .!c9.splits
        Xr = [b.X for b in _ed_case9().branches[ring]]
        @test maximum(abs.(c9.margin[ring] .- Xr ./ sum(Xr))) <= 100eps()
        # A bridge declared the other way round is still found: the match is on the
        # unordered bus pair, and `Graphs.bridges` orders its own pairs.
        rev = [_m8_mesh_branches()[1:5]; Branch(:DE, :E, :D, 0.10, 500.0)]
        @test dc_line_outages(_m8_mesh(rev)).splits == [false, false, false, false, false, true]
    end

    @testset "meshed fixture: the factors ARE rebuild-and-re-solve, to round-off" begin
        net = _m8_mesh()
        s = dc_line_outages(net)
        @test s.base.flow == dc_powerflow(net).flow
        @test _m8_vs_rebuilt(net) <= 1
        # Not a ring: some factor lies strictly between 0 and ±1, so a set of wrong
        # reactances cannot hide here the way it hides on case9 (next testset).
        lodf = [(s.flow[k][e] - s.base.flow[e]) / s.base.flow[k]
                for k in eachindex(s.splits) if !s.splits[k] for e in eachindex(s.splits) if e != k]
        @test any(x -> 0.05 < abs(x) < 0.95, lodf)
    end

    @testset "case9: the same identity, on a ring whose factors are all 0 or ±1" begin
        net = _ed_case9()
        s = dc_line_outages(net)
        @test _m8_vs_rebuilt(net) <= 1
        # Hurdle 13.2, structurally: losing a ring line sends ALL of its flow the other
        # way round, whatever the reactances are. A consistently wrong set of them
        # changes nothing on this fixture (m8-tasks.md step 2's sabotage run).
        for k in findall(!, s.splits), e in eachindex(s.splits)
            e == k && continue
            x = abs((s.flow[k][e] - s.base.flow[e]) / s.base.flow[k])
            @test min(x, abs(x - 1)) <= 1e-12
        end
    end

    @testset "an inverter is read through the base case, and the identity still holds" begin
        # Found by M7's walk of the exported surface, not planned: the screen takes a
        # model, so it must either refuse inverters or handle them. It handles them —
        # an inverter only moves the base flows, which come from `dc_powerflow`, and
        # the rebuild carries `net.inverters` through `_m8_without`.
        mk_inv(P) = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)],
            _m8_mesh_branches(),
            [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 150.0),
             Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0)],
            [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0), Load(:LD, :D, 90.0 + P, 25.0, 0.0, 0.0, 1.0),
             Load(:LE, :E, 40.0, 10.0, 0.0, 0.0, 1.0)]; slack = :A,
            inverters = [Inverter(:pv, :D, :grid_following, 100.0, P)])
        net = mk_inv(30.0)
        @test _m8_vs_rebuilt(net) <= 1
        # The inverter's 30 MW is in the base, offset by 30 MW more load at the same
        # bus: the flows match the inverter-free mesh, so it was counted, not dropped.
        @test isapprox(dc_line_outages(net).base.flow, dc_line_outages(_m8_mesh()).base.flow;
                       atol = 100eps())
    end

    @testset "the reference bus moves no flow" begin
        a, c = dc_line_outages(_m8_mesh()), dc_line_outages(_m8_mesh(; slack = :C))
        @test a.splits == c.splits
        scale = maximum(abs, a.base.flow)
        @test all(maximum(abs.(a.flow[k] .- c.flow[k]); init = 0.0) <= 100eps() * scale
                  for k in eachindex(a.flow))
    end

    @testset "a nearly-split grid: answered, not thresholded; the error is the factors', growing as 1/margin" begin
        # A second path C–E of reactance Xw makes D–E no longer a bridge. Its margin is
        # about X_DE/Xw. The checker's 1e-6 clamp would call the 1e7 case a split; the
        # graph does not.
        #
        # The exact answer for losing D–E needs no ill-conditioned solve: E then hangs
        # off C alone, so C–E carries E's 40 MW and the rest is the four-bus grid with
        # that load moved to C.
        exact4 = dc_powerflow(_m8_mesh(_m8_mesh_branches()[1:5]; loadE = :C,
                                       buses = (:A, :B, :C, :D))).flow
        exact = [exact4; 0.0; 0.4]
        gaps = Float64[]
        for Xw in (1e3, 1e5, 1e7)
            net = _m8_mesh([_m8_mesh_branches(); Branch(:CE, :C, :E, Xw, 500.0)])
            s = dc_line_outages(net)
            @test !any(s.splits)
            @test isapprox(s.margin[6], 0.1 / Xw; rtol = 1e-2)
            @test _m8_vs_rebuilt(net; near = true) <= 1
            # Attribution: the rebuild is exact to round-off at every Xw, so the whole
            # gap is the factors' (predicted the other way at step 2, and wrong).
            scale = maximum(abs, s.base.flow)
            @test maximum(abs.(_m8_rebuilt(net, 6) .- exact)) <= 100eps() * scale
            push!(gaps, maximum(abs.(s.flow[6] .- exact)))
        end
        # The signature: the error grows as the margin shrinks (measured 7.9e-13,
        # 2.3e-11, 4.5e-9), and at 1e7 it is far outside the ORDINARY band (measured
        # 1.8e5 times it).
        @test gaps[3] >= 100 * gaps[1]
        @test gaps[3] > 1000 * 100eps() * maximum(abs, exact)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: the AC line screen (`ac_line_outages`) and what the DC shortcut missed
# (`compare_line_screens`). Every number below was predicted or measured BEFORE this
# file was written (`docs/evidence/gridsim-m8/step3_predictions.md`). case9 here is
# `_ed_case9`: NO LINE CHARGING, so every case9 voltage carries that caveat — part of
# each sag is the missing shunt and not the outage (m8-context.md D0, Hurdle 13.4).
# ─────────────────────────────────────────────────────────────────────────────

# `net` with the named branches re-rated (MVA), everything else the same.
_m8_rerate(net::NetworkModel; ratings...) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, get(ratings, b.id, b.rating); R = b.R)
     for b in net.branches], net.machines, net.loads; slack = net.slack, inverters = net.inverters)

# The ladder's rungs (m8-context.md D6), one change each. Every rung is checked to
# leave no reactive limit bound, so case9's ±3 pu limits are inert throughout.
_m8_lossless(net::NetworkModel) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net.branches], net.machines,
    net.loads; slack = net.slack, inverters = net.inverters)
_m8_flatV(net::NetworkModel) = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
    [GridSim._machine_with(m; V_set = 1.0) for m in net.machines], net.loads;
    slack = net.slack, inverters = net.inverters)
# A zero-P machine with unlimited Q at V_set = 1 on every bus WITHOUT a source — load
# buses and junction buses both (case9's B4, B6, B8 carry nothing and would sag too).
function _m8_helpers(net::NetworkModel)
    src = Set(m.bus for m in net.machines)
    hs = [Machine(Symbol(:H_, b.id), b.id, 100.0, 5.0, 0.0, 0.2, 1.0, 0.0)
          for b in net.buses if !(b.id in src)]
    return NetworkModel(net.S_base, net.f0, net.buses, net.branches, [net.machines; hs],
                        net.loads; slack = net.slack, inverters = net.inverters)
end
# A0 lossless, every bus at 1 pu; A1 + R; A2 + published V_set; A3 − helpers (the
# published model); A4 + default constant-impedance loads.
_m8_ladder(pub, pubzip) = [_m8_helpers(_m8_flatV(_m8_lossless(pub))),
                           _m8_helpers(_m8_flatV(pub)), _m8_helpers(pub), pub, pubzip]

# Step 3's mesh: step 2's topology with an INVENTED resistance R = X/10 and invented
# V_set 1.05 / 1.04 (declared; this fixture is not a published case). R = X/5 was
# tried first and its own base case sagged out of band once the helpers came off.
_m8_mesh3(; zip = false) = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)],
    [Branch(b.id, b.from, b.to, b.X, b.rating; R = b.X / 10) for b in _m8_mesh_branches()],
    [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 150.0; V_set = 1.05),
     Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0; V_set = 1.04)],
    [Load(:LB, :B, 80.0, 20.0, (zip ? (1.0, 0.0, 0.0) : (0.0, 0.0, 1.0))...),
     Load(:LD, :D, 90.0, 25.0, (zip ? (1.0, 0.0, 0.0) : (0.0, 0.0, 1.0))...),
     Load(:LE, :E, 40.0, 10.0, (zip ? (1.0, 0.0, 0.0) : (0.0, 0.0, 1.0))...)]; slack = :A)

# Worst |Σ (P_ac,from − f_dc)| over the buses: zero exactly when the AC−DC flow
# difference is a pure loop flow. AC solution read BY ID.
function _m8_divergence(net::NetworkModel, dcflow, sol::ACPowerFlow)
    div = zeros(length(net.buses))
    for (e, b) in pairs(net.branches)
        j = findfirst(==(b.id), sol.branches)
        j === nothing && continue
        d = sol.flow[j] - dcflow[e]
        div[net.bus_index[b.from]] += d
        div[net.bus_index[b.to]] -= d
    end
    return maximum(abs, div)
end

# Both screens and the comparison, in one call.
function _m8_screens(net::NetworkModel)
    dc, ac = dc_line_outages(net), ac_line_outages(net)
    return dc, ac, compare_line_screens(net, dc, ac)
end

const _M8_C9 = (:L14, :L45, :L56, :L36, :L67, :L78, :L82, :L89, :L94)   # branch order

@testset "M8 step 3 — the AC line screen, and what the DC shortcut missed" begin

    @testset "each outage IS the outcome solve on the rebuilt model; bridges never solved" begin
        # The AC counterpart of step 2's rebuild identity, with `==` on every field:
        # the screen is the same code on the same model, so exactness is available.
        for net in (_ed_case9(), _ed_case9(; load = 400.0), _ed_case9(; zip_default = true),
                    _m8_mesh3(), _m8_rerate(_ed_case9(); L94 = 100.0))
            ac = ac_line_outages(net)
            @test ac.branches == [b.id for b in net.branches]
            s0 = ac_powerflow(net)
            @test all(getfield(ac.base, f) == getfield(s0, f) for f in fieldnames(ACPowerFlow))
            @test ac.splits == dc_line_outages(net).splits
            for (k, b) in pairs(net.branches)
                if ac.splits[k]
                    @test ac.outcome[k] === :splits && ac.solution[k] === nothing
                    continue
                end
                r = GridSim._ac_powerflow_outcome(_m8_without(net, b.id))
                @test ac.outcome[k] === r.outcome
                if r.solution === nothing
                    @test ac.solution[k] === nothing
                else
                    @test all(getfield(ac.solution[k], f) == getfield(r.solution, f)
                              for f in fieldnames(ACPowerFlow))
                end
                @test ac.over[k] == (r.outcome === :overload ? r.detail : [])
                @test ac.low[k] == (r.outcome === :voltage ? r.detail : [])
                @test ac.reason[k] === (r.outcome === :no_solution ? r.detail.reason : :none)
            end
        end
    end

    @testset "a refused base case refuses the whole screen, with ac_powerflow's message" begin
        # D3: outages from an operating point the network cannot hold say nothing.
        bad = _m8_rated(_ed_case9(), 0.5)
        e = _m8_thrown(() -> ac_powerflow(bad))
        @test e isa ErrorException
        @test _m8_thrown(() -> ac_line_outages(bad)).msg == e.msg
        # And the comparison refuses two screens that are not of the model it is given.
        dc, ac = dc_line_outages(_ed_case9()), ac_line_outages(_ed_case9())
        @test_throws ArgumentError compare_line_screens(_m8_mesh3(), dc, ac)
        @test_throws ArgumentError compare_line_screens(_ed_case9(), dc_line_outages(_m8_mesh3()), ac)
    end

    @testset "case9's voltage demonstration: what a screen of P alone cannot see (no line charging)" begin
        # Hurdle 13.4. At the published 315 MW every DC flow is inside its rating
        # (worst 79.3 %), and the AC solve refuses two outages for VOLTAGE: B5 at
        # 0.873 pu after L45, B9 at 0.757 pu after L94. Part of each sag is the line
        # charging this model does not carry; the claim is structural — the DC screen
        # has no channel through which a voltage problem could appear.
        dc, ac, c = _m8_screens(_ed_case9())
        @test c.branches == collect(_M8_C9)
        @test isempty(c.dc_base_over)
        @test c.class == [:splits, :dc_blind, :agree, :splits, :agree, :agree, :splits,
                          :agree, :dc_blind]
        @test all(==(:secure), c.dc_outcome[.!c.splits])
        @test [d.bus for d in ac.low[2]] == [:B5] && [d.bus for d in ac.low[9]] == [:B9]
        # No AC flows on a voltage refusal, so no miss is reported there.
        @test isempty(c.real[2]) && isempty(c.reactive[9]) && isempty(c.real[1])
        @test all(length(c.real[k]) == 9 for k in (3, 5, 6, 8))

        # 400 MW: the one DC overload (L89 out, L56 at 100.7 %) is an outage AC
        # refuses for voltage anyway; four voltage refusals, one non-convergence.
        dc, ac, c = _m8_screens(_ed_case9(; load = 400.0))
        @test c.class == [:splits, :dc_blind, :dc_blind, :splits, :agree, :dc_blind,
                          :splits, :dc_blind, :dc_blind]
        @test c.dc_over[8] == [:L56] && c.ac_outcome[8] === :voltage
        @test 150.0 < 100abs(dc.flow[8][3]) < 1.01 * 150.0
        @test c.ac_outcome[9] === :no_solution && ac.reason[9] === :newton
    end

    @testset "positive control: an outage that overloads at BOTH fidelities, and one secure at both" begin
        # Without this a screen reporting `:secure` everywhere passes, and so does one
        # reporting `:overload` everywhere. L94 rated 100 MVA (not case9's 250): its
        # base is 61.3 MW / 77.5 MVA; L89 out puts it at 125.0 / 144.6 and L67 out at
        # 109.8 / 121.1; L56 and L78 out leave it under at both (measured).
        # L94's DC flow runs AGAINST its declared direction, so a judgement that
        # forgot the magnitude would pass it.
        net = _m8_rerate(_ed_case9(); L94 = 100.0)
        dc, ac, c = _m8_screens(net)
        @test isempty(c.dc_base_over)
        @test all(dc.flow[k][9] < -1.0 for k in (5, 8))
        for k in (5, 8)                                   # L67, L89
            @test c.dc_outcome[k] === :overload && c.ac_outcome[k] === :overload
            @test c.dc_over[k] == c.ac_over[k] == [:L94] && c.class[k] === :agree
        end
        for k in (3, 6)                                   # L56, L78
            @test c.dc_outcome[k] === c.ac_outcome[k] === :secure && c.class[k] === :agree
        end
        @test c.class[2] === c.class[9] === :dc_blind     # L45, L94: voltage, as before
    end

    @testset "DC misses an overload, and it is the REACTIVE part that crosses the rating" begin
        # L14 rated 150 MVA: L89 out puts 96.0 MW on it in DC, 105.3 MW of real power in
        # AC (the slack's output also covers the losses), and 159.7 MVA. L14 is G1's
        # connection: it carries the slack's reactive output, which a flow of P alone
        # cannot see.
        net = _m8_rerate(_ed_case9(); L14 = 150.0)
        dc, ac, c = _m8_screens(net)
        @test c.class == [:splits, :dc_blind, :agree, :splits, :agree, :agree, :splits,
                          :dc_missed, :dc_blind]
        @test c.ac_over[8] == [:L14] && isempty(c.dc_over[8])
        sol = ac.solution[8]
        j = findfirst(==(:L14), sol.branches)
        S = max(hypot(sol.flow[j], sol.qflow[j]), hypot(sol.flow_rev[j], sol.qflow_rev[j]))
        # The split is a decomposition: its parts add up to the whole miss.
        @test c.reactive[8][1] + c.real[8][1] ≈ S - abs(dc.flow[8][1]) rtol = 1e-14
        # Real power alone, at either fidelity, is under the rating; the reactive part
        # takes the AC flow over it.
        @test 100 * (abs(dc.flow[8][1]) + c.real[8][1]) < 150.0
        @test 100 * (abs(dc.flow[8][1]) + c.real[8][1] + c.reactive[8][1]) > 150.0
        # Read by id. L14 sits BEFORE the outaged L89, where position and id agree, so
        # the checks above cannot see a position bug (sabotage T1 left them green).
        # L94 sits after it: model index 9, solution index 8.
        j94 = findfirst(==(:L94), sol.branches)
        @test j94 == 8
        @test c.real[8][9] == max(abs(sol.flow[j94]), abs(sol.flow_rev[j94])) - abs(dc.flow[8][9])
    end

    @testset "the two rarer verdicts: a DC-only base overload, and :mixed" begin
        # A DC base over a rating is reported, not refused (D6): the AC base is secure.
        # Step 2's lossless mesh on default loads at V_set 1.05 / 1.04; the spur D–E
        # carries 40.0 MW in DC and 37.9 MVA in AC (measured), so a 39 MVA rating
        # separates them.
        mesh = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)],
            [_m8_mesh_branches()[1:5]; Branch(:DE, :D, :E, 0.10, 39.0)],
            [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 150.0; V_set = 1.05),
             Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0; V_set = 1.04)],
            [Load(:LB, :B, 80.0, 20.0), Load(:LD, :D, 90.0, 25.0), Load(:LE, :E, 40.0, 10.0)];
            slack = :A)
        _, ac, c = _m8_screens(mesh)
        @test c.dc_base_over == [:DE]
        @test 100 * (abs(dc_powerflow(mesh).flow[6]) + c.base_real[6] + c.base_reactive[6]) < 39.0
        # `:mixed`: default loads, L94 at 105 and L82 at 125 MVA. Losing L67 gives L94
        # 109.8 MW in DC against 100.4 MVA in AC (a false alarm) and L82 115.2 MW
        # against 132.3 MVA (a miss), on the same outage.
        z = _m8_rerate(_ed_case9(; zip_default = true); L94 = 105.0, L82 = 125.0)
        _, _, c = _m8_screens(z)
        @test c.class == [:splits, :agree, :dc_missed, :splits, :mixed, :agree, :splits,
                          :agree, :dc_blind]
        @test c.dc_over[5] == [:L94] && c.ac_over[5] == [:L82]
    end

    @testset "which loads let DC exceed the AC apparent power (measured, scoped)" begin
        # On the published constant-power case9 no AC apparent power falls below its
        # DC flow on any solved outage (smallest margin 0.16 MW at 315 MW). On the
        # default loads it does, by up to 12.7 MW. NOT a law of constant power: with
        # every bus held at 1 pu and R on (ladder rung A1) DC exceeds AC by 6.3 MW on
        # case9's constant-power loads, and on the mesh's A0 and A1 rungs by 0.15 and
        # 0.51 MW (step3_review.log).
        smin(c) = minimum(c.real[k][e] + c.reactive[k][e]
                          for k in eachindex(c.real) if !isempty(c.real[k])
                          for e in eachindex(c.real[k]) if e != k)
        @test smin(last(_m8_screens(_ed_case9()))) >= 0
        @test smin(last(_m8_screens(_ed_case9(; zip_default = true)))) < -0.1
        @test smin(last(_m8_screens(_m8_ladder(_ed_case9(), _ed_case9(; zip_default = true))[2]))) < -0.05
    end

    @testset "DC raises a false alarm — on the DEFAULT loads only" begin
        # L94 rated 105 MVA. On constant-power loads L67 out overloads it at both
        # fidelities (109.8 MW / 121.1 MVA). On case9's default constant-impedance
        # loads the AC voltages sag, the loads draw less, and the AC flow is 100.4 MVA
        # while the DC flow, which never moves a voltage, stays at 109.8 MW (M6 step
        # 7's lesson: a claim made on constant power must be re-run on the default).
        cp = compare_line_screens(_m8_rerate(_ed_case9(); L94 = 105.0),
                                  dc_line_outages(_m8_rerate(_ed_case9(); L94 = 105.0)),
                                  ac_line_outages(_m8_rerate(_ed_case9(); L94 = 105.0)))
        @test cp.class[5] === :agree && cp.ac_over[5] == [:L94]
        z = _m8_rerate(_ed_case9(; zip_default = true); L94 = 105.0)
        dc, ac, c = _m8_screens(z)
        @test c.class == [:splits, :agree, :agree, :splits, :dc_false_alarm, :agree,
                          :splits, :agree, :dc_blind]
        @test c.dc_over[5] == [:L94] && isempty(c.ac_over[5]) && c.ac_outcome[5] === :secure
        @test c.dc_over[8] == c.ac_over[8] == [:L94]      # L89 out: over at both
        # On those loads the DC flow on L94 exceeds the AC apparent power: the real-power
        # part is negative AND larger than the reactive part.
        @test c.real[5][9] < 0 && -c.real[5][9] > c.reactive[5][9]
    end

    @testset "the miss, one cause at a time (Hurdle 13.3)" begin
        # Rungs: A0 lossless with every bus held at 1 pu; A1 + R; A2 + published V_set;
        # A3 − the helper machines (the published model); A4 + default loads.
        for (pub, pubzip, tree) in ((_ed_case9(), _ed_case9(; zip_default = true), true),
                                    (_m8_mesh3(), _m8_mesh3(; zip = true), false))
            rungs = _m8_ladder(pub, pubzip)
            cs = Any[]
            for (r, net) in pairs(rungs)
                dc, ac, c = _m8_screens(net)
                push!(cs, c)
                # Precondition, asserted rather than trusted: no reactive limit bound
                # anywhere, so no rung is secretly a different switching state.
                @test isempty(ac.base.limited)
                @test all(isempty(s.limited) for s in ac.solution if s !== nothing)
                r == 1 || continue
                # A0: every magnitude IS 1 (every bus holds one), and the injections
                # are the DC ones exactly, so AC − DC is a pure LOOP flow: it sums to
                # zero at every bus (band: 10 × the Newton's 1e-12 abstol).
                for s in (ac.base, (s for s in ac.solution if s !== nothing)...)
                    @test all(==(1.0), s.Vm)
                end
                @test _m8_divergence(net, dc.base.flow, ac.base) <= 1e-11
                for k in findall(!, ac.splits)
                    @test _m8_divergence(net, dc.flow[k], ac.solution[k]) <= 1e-11
                end
                if tree
                    # case9's ring outages each leave a TREE, where a loop flow is
                    # zero: A0 is blind on every outage (measured ≤ 2.4e-14) — and not
                    # by construction, because its intact RING shows 5.0e-5.
                    @test all(maximum(abs, c.real[k]) <= 1e-11 for k in findall(!, c.splits))
                    @test maximum(abs, c.base_real) > 1e-6
                else
                    # The mesh keeps a loop after any one outage: the angle
                    # linearisation is visible (measured 2.4e-5 … 3.4e-3).
                    @test maximum(maximum(abs, c.real[k]) for k in findall(!, c.splits)) > 1e-6
                end
            end
            # Each rung moves the miss: a rung that changed nothing would make its
            # cause look absent. Compared on the intact model, which every rung solves.
            for r in 2:length(rungs)
                @test maximum(abs.(cs[r].base_real .- cs[r-1].base_real) .+
                              abs.(cs[r].base_reactive .- cs[r-1].base_reactive)) > 1e-3
            end
            # From A1 on the losses break the loop-flow identity (measured 3.7e-2 on
            # case9's intact model at A1): R is the first cause that is not angles.
        end
    end

    @testset "S_base invariance: the same physical case on two bases" begin
        # `_ed_case9(; S_base)` rescales X, R and the reactive limits, so it is the same
        # network. Outcomes, overloaded branches and every MW/MVA must not move.
        a = _m8_rerate(_ed_case9(); L94 = 100.0)
        b = _m8_rerate(_ed_case9(; S_base = 250.0); L94 = 100.0)
        _, aca, ca = _m8_screens(a)
        _, acb, cb = _m8_screens(b)
        @test ca.class == cb.class && ca.dc_outcome == cb.dc_outcome
        @test ca.ac_outcome == cb.ac_outcome && ca.dc_over == cb.dc_over && ca.ac_over == cb.ac_over
        for k in eachindex(ca.real)
            @test isapprox(100.0 .* ca.real[k], 250.0 .* cb.real[k]; rtol = 1e-9, atol = 1e-9)
            @test isapprox(100.0 .* ca.reactive[k], 250.0 .* cb.reactive[k]; rtol = 1e-9, atol = 1e-9)
            @test [d.mva for d in aca.over[k]] ≈ [d.mva for d in acb.over[k]] rtol = 1e-9
        end
    end

    @testset "a grid-forming slack pushed over its rating is something DC cannot see" begin
        # A triangle fed by a grid-forming slack. Losing a line raises the reactive
        # power the network absorbs, so the source's |P + jQ| rises with no branch
        # anywhere near its rating. The DC screen has no source rating to judge, so
        # the outage is `:dc_blind`, not `:agree`. The rating is set 0.1 % above the
        # intact model's own output, read off its solve: a constructed fixture.
        mk(S) = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0), Bus(:C, 1.0)],
            [Branch(:AB, :A, :B, 0.1, 500.0), Branch(:AC, :A, :C, 0.1, 500.0),
             Branch(:BC, :B, :C, 0.1, 500.0)], Machine[],
            [Load(:DB, :B, 40.0, 10.0, 0.0, 0.0, 1.0), Load(:DC, :C, 40.0, 10.0, 0.0, 0.0, 1.0)];
            inverters = [Inverter(:gf, :A, :grid_forming, S, 80.0)])
        s = ac_powerflow(mk(1000.0))
        v = findfirst(==(:A), s.buses)
        net = mk(1.001 * 100hypot(s.Pgen[v], s.Qgen[v]))
        dc, ac, c = _m8_screens(net)
        @test ac.outcome[1] === :overload && only(ac.over[1]).kind === :inverter_slack
        @test isempty(c.ac_over[1]) && c.dc_outcome[1] === :secure
        @test c.class[1] === :dc_blind
    end

    @testset "an inverter is screened like the load it offsets" begin
        # The AC screen takes a model, so M7's walk of the exported surface reaches it
        # (test/m7_inverters.jl). A grid-following inverter injects constant P + jQ0;
        # 30 MW of it at B5 with 30 MW more constant-power load at the same bus is the
        # inverter-free case9, so every outcome matches it.
        base = _ed_case9()
        withinv = NetworkModel(base.S_base, base.f0, base.buses, base.branches, base.machines,
            [l.id === :D5 ? Load(:D5, :B5, l.P0 + 30.0, l.Q0, 0.0, 0.0, 1.0) : l for l in base.loads];
            slack = base.slack, inverters = [Inverter(:pv, :B5, :grid_following, 50.0, 30.0)])
        a, b = ac_line_outages(base), ac_line_outages(withinv)
        @test a.outcome == b.outcome
        @test [d.bus for v in a.low for d in v] == [d.bus for v in b.low for d in v]
        @test isapprox([d.Vm for v in a.low for d in v], [d.Vm for v in b.low for d in v]; atol = 1e-9)
        for k in findall(s -> s !== nothing, a.solution)
            @test isapprox(a.solution[k].flow, b.solution[k].flow; atol = 1e-9)
        end
        # And it IS the outcome solve on the rebuilt model, inverter carried through.
        r = GridSim._ac_powerflow_outcome(_m8_without(withinv, :L56))
        @test b.solution[3].flow == r.solution.flow
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: generator outages in the DC screen, the lost power shared by droop and
# damping (`pickup_shares`, `dc_generator_outages`; m8-context.md D2, D7).
#
# What the swing tier's loads do was READ before any assertion (Hurdle 15.1): the tier
# refuses a `Load` outright and holds `E′` at every bus, so it has no voltage term at
# all, and a load is a negative-P0 machine whose only response is its `D`. So the
# oracle fixture is machines only, one per bus, lossless, and the DC screen reads the
# very same object.
#
# Closed-form values and the cross-tier band were written down before the first run
# (`docs/evidence/gridsim-m8/step4_predictions.md`): BAND 1e-7 pu on every pickup and
# on every survivor's speed. Measured: ≤ 1.5e-10 and ≤ 1.5e-12.
# ─────────────────────────────────────────────────────────────────────────────

# Every number INVENTED, and declared so. Step 2's mesh plus B–E, so no bridge and no
# cut VERTEX: the swing tier's trip zeroes every branch at the lost machine's bus, and
# the survivors must stay one grid. Machine bases differ from S_base and from each
# other, and R and D differ, so a weight on the wrong base or a dropped term moves an
# answer. Loads are negative-P0 machines (the swing tier's convention).
#   system base:  G1 1/R 60, D 3.0, headroom .70 | G2 37.5, 3.0, .40 | G3 20, 1.8, .05
#                 LB D 2.0 | LD D 1.5
function _m8_genmesh(; damp = 1.0, gov = true, gfm = false, slack = :A)
    R(r) = gov ? r : Inf
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0damp, 0.25, 1.05, 150.0, R(0.05), 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0damp, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0damp, 0.25, 1.04, 60.0, R(0.04), 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5damp, 0.25, 1.00, -120.0)]
    # The inverter variant puts a grid-forming inverter at E instead of G3: K_p on the
    # system base 0.125·100/300 = 1/24.
    invs = gfm ? [Inverter(:I3, :E, :grid_forming, 300.0, 40.0; K_p = 0.125, V_set = 1.02)] :
                 Inverter[]
    gfm || push!(ms, Machine(:G3, :E, 120.0, 3.5, 1.5damp, 0.25, 1.02, 40.0, R(0.06), 45.0, 0.6))
    br = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
          Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
          Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0),
          Branch(:BE, :B, :E, 0.20, 500.0)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms;
                 slack, inverters = invs)
end

# Brute force for one generator outage: the model without machine `k`, every
# responder's schedule raised by its pickup, solved again.
function _m8_gen_rebuilt(net::NetworkModel, k::Int, pk::Vector{Float64}, resp::Vector{Symbol})
    Sb = net.S_base
    ms = Machine[]
    for (i, m) in pairs(net.machines)
        i == k && continue
        P = m.P0 + pk[findfirst(==(m.id), resp)] * Sb
        push!(ms, Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, P, m.R,
                          max(m.Pmax, P), m.Tg))
    end
    invs = [GridSim._inverter_with(iv; P0 = iv.P0 + pk[findfirst(==(iv.id), resp)] * Sb)
            for iv in net.inverters]
    dc_powerflow(NetworkModel(Sb, net.f0, net.buses, net.branches, ms, net.loads;
                              slack = net.slack, inverters = invs)).flow
end

# The swing tier after tripping `lost`, read at `T`: each element's change in
# ELECTRICAL export (Σ branch_power out of its bus, after − before) — the network
# side, never `ΔPm − D·ω`, which is the rule's own formula — and every vertex's speed.
function _m8_swing_settled(net::NetworkModel, lost::Symbol, Ts)
    eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
    export_of(bus) = sum((br.from === bus ? branch_power(eng, br.from, br.to) :
                          br.to === bus ? branch_power(eng, br.to, br.from) : 0.0)
                         for br in net.branches)
    e0 = Dict(b.id => export_of(b.id) for b in net.buses)
    inject!(eng, TripGenerator(lost))
    out = []
    for T in Ts
        while eng.integrator.t < T - 1e-9
            step!(eng, 0.05)
        end
        st = current_state(eng)
        push!(out, (; Δexport = Dict(b.id => export_of(b.id) - e0[b.id] for b in net.buses),
                      ω = st.ω, ΔPm = st.ΔPm))
    end
    return out
end

@testset "M8 step 4 — generator outages in the DC screen, shared by droop and damping" begin
    net = _m8_genmesh()
    order = [:G1, :LB, :G2, :LD, :G3]       # machines sort by bus

    @testset "the swing tier has no load object and no voltage term (read first)" begin
        # The swing tier refuses a `Load` by name, so nothing there can draw by
        # voltage; the oracle fixture's loads are negative-P0 machines and both the DC
        # screen and the swing tier read that one object.
        withload = NetworkModel(100.0, 50.0, [Bus(:A, 230.0), Bus(:B, 230.0)],
            [Branch(:AB, :A, :B, 0.1, 500.0)],
            [Machine(:G1, :A, 100.0, 5.0, 1.0, 0.25, 1.0, 50.0),
             Machine(:M2, :B, 100.0, 5.0, 1.0, 0.25, 1.0, -40.0)],
            [Load(:D, :B, 10.0, 0.0, 0.0, 0.0, 1.0)])
        msg = try; SwingEngine(withload); ""; catch e; e.msg; end
        @test occursin("Load", msg) && occursin("negative", msg)
        @test SwingEngine(net) isa SwingEngine
        @test dc_powerflow(net).P ≈ [1.5, -1.3, 0.6, -1.2, 0.4]
    end

    @testset "closed form: uncapped, capped, a load lost, an inverter sharing" begin
        s = pickup_shares(net, :G3)
        @test s.responders == order
        @test s.Δω ≈ -0.4 / 107 rtol = 1e-14
        @test s.pickup ≈ [63, 2.0, 40.5, 1.5, 0] .* (0.4 / 107) rtol = 1e-14
        @test s.pickup[5] === 0.0 && !any(s.capped)
        @test sum(s.pickup) ≈ 0.4 rtol = 1e-14
        # G3's governor reaches its 0.05 headroom at x = 2.5e-3; past that the slope
        # loses its 1/R = 20.
        c = pickup_shares(net, :G2)
        x = 2.5e-3 + (0.6 - 88.3 * 2.5e-3) / 68.3
        @test c.Δω ≈ -x rtol = 1e-14
        @test c.capped == [false, false, false, false, true]
        # The cap is on the GOVERNOR only: capped G3 settles at headroom + D·|Δω|,
        # 1.45 MW above its Pmax, because damping is outside the saturation.
        @test c.pickup[5] ≈ 0.05 + 1.8x rtol = 1e-14
        @test 100 * c.pickup[5] > 45.0 - 40.0
        @test sum(c.pickup) ≈ 0.6 rtol = 1e-14
        # Losing a negative-P0 machine is a load trip: frequency rises, and every
        # governor commands less with no floor, as in the swing tier.
        l = pickup_shares(net, :LB)
        @test l.Δω ≈ 1.3 / 126.8 rtol = 1e-14
        @test all(l.pickup .<= 0)
        @test sum(l.pickup) ≈ -1.3 rtol = 1e-14
        # A grid-forming inverter shares by its droop gain 1/K_p (24 on the system
        # base), uncapped and undamped; leaving it out would change Δω.
        g = pickup_shares(_m8_genmesh(gfm = true), :G2)
        @test g.responders == [:G1, :LB, :G2, :LD, :I3]
        @test g.Δω ≈ -0.6 / 90.5 rtol = 1e-14
        @test g.pickup[5] ≈ 24 * 0.6 / 90.5 rtol = 1e-14
    end

    @testset "zero damping is droop alone; damping moves Δω by the predicted amount" begin
        z = pickup_shares(_m8_genmesh(damp = 0.0), :G3)
        @test z.Δω ≈ -0.4 / 97.5 rtol = 1e-14
        @test z.pickup ≈ [60, 0, 37.5, 0, 0] .* (0.4 / 97.5) rtol = 1e-14
        @test pickup_shares(net, :G3).Δω - z.Δω ≈ 0.4 / 97.5 - 0.4 / 107 rtol = 1e-12
    end

    @testset "the refusals are exactly two, named; a damped huge loss is reported" begin
        msg(f) = try; f(); ""; catch e; e isa ArgumentError ? e.msg : rethrow(); end
        # No governor and no damping: nothing responds.
        none = _m8_genmesh(damp = 0.0, gov = false)
        @test occursin("nothing left responds", msg(() -> pickup_shares(none, :G3)))
        @test all(==(:no_response), dc_generator_outages(none).outcome)
        # No damping, 0.45 pu of headroom left against a 1.5 pu loss.
        zd = _m8_genmesh(damp = 0.0)
        @test occursin("no damping is left", msg(() -> pickup_shares(zd, :G1)))
        zs = dc_generator_outages(zd)
        @test zs.outcome == [:reserve_exhausted, :shared, :shared, :shared, :shared]
        @test isnan(zs.Δω[1]) && isempty(zs.flow[1]) && all(iszero, zs.pickup[1])
        # The same loss with damping: both governors capped, a 6.3 Hz deviation —
        # reported, not refused (Hurdle 15.4).
        big = pickup_shares(net, :G1)
        x = 0.4 / 37.5 + (1.5 - (65.8 * 2.5e-3 + 45.8 * (0.4 / 37.5 - 2.5e-3))) / 8.3
        @test big.Δω ≈ -x rtol = 1e-12
        @test big.capped == [false, false, true, false, true]
        @test 50 * abs(big.Δω) > 6.0
        # ΣD = 0 and the headroom left EXACTLY equal to the loss: every Δω past the
        # last cap balances, and the smallest |Δω| (that cap) is returned.
        # Numbers exact in binary (1/R = 16, headroom 0.5, bend at 1/32), so the tie
        # is a tie and not a rounding either way.
        two(ms) = NetworkModel(100.0, 50.0, [Bus(:A, 230.0), Bus(:B, 230.0)],
                               [Branch(:AB, :A, :B, 0.1, 500.0)], ms)
        gov(P0) = Machine(:G1, :A, 100.0, 5.0, 0.0, 0.25, 1.0, P0, 0.0625, P0 + 50.0)
        tie = two([gov(50.0), Machine(:G2, :B, 100.0, 5.0, 0.0, 0.25, 1.0, 50.0),
                   Machine(:L, :B, 100.0, 5.0, 0.0, 0.25, 1.0, -100.0)])
        e = pickup_shares(tie, :G2)
        @test e.Δω === -1 / 32 && e.capped == [true, false, false]
        @test e.pickup[1] === 0.5
        # A load lost: frequency rises, no cap on the way up.
        @test pickup_shares(tie, :L).Δω === 1.0 / 16
        # The governor itself lost: only a governor-free, undamped machine is left.
        @test occursin("nothing left responds", msg(() -> pickup_shares(tie, :G1)))
        # A machine producing nothing leaves nothing to share, even with no responder.
        nul = two([Machine(:G1, :A, 100.0, 5.0, 0.0, 0.25, 1.0, 50.0),
                   Machine(:G0, :B, 100.0, 5.0, 0.0, 0.25, 1.0, 0.0),
                   Machine(:L, :B, 100.0, 5.0, 0.0, 0.25, 1.0, -50.0)])
        @test pickup_shares(nul, :G0).Δω === 0.0
        # case9 as M6 builds it carries no droop (`R = Inf`) and no damping, so every
        # generator outage is the first refusal: it needs droop data, invented and
        # declared, before it can screen one (Hurdle 15.4).
        c9 = dc_generator_outages(_ed_case9())
        @test c9.machines == [:G1, :G2, :G3] && all(==(:no_response), c9.outcome)
        # Inverter outages are not screened.
        @test occursin("not a machine", msg(() -> pickup_shares(_m8_genmesh(gfm = true), :I3)))
    end

    @testset "the screen's flows ARE rebuild-and-re-solve, to round-off" begin
        for nt in (net, _m8_genmesh(gfm = true))
            s = dc_generator_outages(nt)
            @test s.machines == [m.id for m in nt.machines]
            for k in eachindex(s.machines)
                @test s.outcome[k] === :shared
                @test s.pickup[k] == pickup_shares(nt, s.machines[k]).pickup
                bf = _m8_gen_rebuilt(nt, k, s.pickup[k], s.responders)
                @test maximum(abs.(s.flow[k] .- bf)) <= 100eps() * maximum(abs, bf)
            end
        end
    end

    @testset "a grid-following inverter is screened like the load it offsets" begin
        # It holds its P and answers no frequency deviation, so 30 MW of it at D with
        # 30 MW more load on LD is the inverter-free model: same responders, same
        # shares, same flows (M7's surface walk relies on this testset).
        gfl = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
            [m.id === :LD ? GridSim._machine_with(m; P0 = -150.0, Pmax = -150.0) : m
             for m in net.machines];
            slack = net.slack, inverters = [Inverter(:pv, :D, :grid_following, 50.0, 30.0)])
        a, b = dc_generator_outages(net), dc_generator_outages(gfl)
        @test a.responders == b.responders == order
        @test a.outcome == b.outcome
        for k in eachindex(a.machines)
            # Losing LD itself is losing 150 MW of load in the inverter model, not
            # 120: the same shares, scaled by 150/120.
            s = a.machines[k] === :LD ? 1.25 : 1.0
            @test isapprox(s * a.Δω[k], b.Δω[k]; rtol = 1e-14)
            @test isapprox(s .* a.pickup[k], b.pickup[k]; atol = 1e-15)
            a.machines[k] === :LD && continue
            @test isapprox(a.flow[k], b.flow[k]; atol = 1e-14)
        end
    end

    @testset "losing the slack bus's own machine: the reference is a gauge" begin
        # G1 sits on the slack bus A. The pickups rebalance every injection, so nothing
        # is left for the reference, and moving the reference moves no flow.
        a = dc_generator_outages(_m8_genmesh(slack = :A))
        d = dc_generator_outages(_m8_genmesh(slack = :D))
        @test a.outcome[1] === :shared
        for k in eachindex(a.flow)
            @test maximum(abs.(a.flow[k] .- d.flow[k])) <= 100eps() * maximum(abs, a.flow[k])
        end
    end

    @testset "the swing tier settles to the same pickups and Δω (band 1e-7, stated first)" begin
        band = 1e-7
        for (nt, lost) in ((net, :G3), (net, :G2), (_m8_genmesh(gfm = true), :G2))
            s = pickup_shares(nt, lost)
            bus_of = Dict(vcat([m.id => m.bus for m in nt.machines],
                               [i.id => i.bus for i in nt.inverters]))
            lostv = nt.bus_index[bus_of[lost]]
            # Settled, not passing through: the same answer at 300 s and at 450 s.
            for o in _m8_swing_settled(nt, lost, (300.0, 450.0))
                for (i, r) in pairs(s.responders)
                    r === lost && continue
                    @test abs(o.Δexport[bus_of[r]] - s.pickup[i]) <= band
                end
                # Every survivor's own speed, not only the average.
                for v in eachindex(nt.buses)
                    v == lostv || @test abs(o.ω[v] - s.Δω) <= band
                end
                # The capped governor sits at its headroom (the out-of-domain guard
                # lets it reach 9e-11 past it), and the machine above its Pmax.
                if lost === :G2 && isempty(nt.inverters)
                    @test abs(o.ΔPm[5] - 0.05) <= 1e-9
                    @test o.Δexport[:E] > 0.05 + band
                end
            end
        end
    end

    @testset "zero damping: the swing tier never settles, so the algebra is the check" begin
        # Measured, not assumed: with D = 0 only the governors act on the swings, and
        # in this fixture the machines are still swinging against each other after
        # 300 s (spread 3e-3 pu). `pickup_shares`' droop-alone answer is checked in
        # closed form above; here it is recorded that no settled run exists to hold
        # it against.
        o = only(_m8_swing_settled(_m8_genmesh(damp = 0.0), :G3, (300.0,)))
        @test maximum(o.ω[1:4]) - minimum(o.ω[1:4]) > 1e-4
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — generator outages in the AC screen, the lost power shared (m8-context.md D8).
# Predictions and bands were written first: docs/evidence/gridsim-m8/step5_predictions.md.
# ─────────────────────────────────────────────────────────────────────────────

# Step 4's mesh with real `Load`s at B and D (130 + j30, 120 + j25), one source per
# bus so the detailed tier can run it. Invented and declared. `r` sets R = r·X; `cp`
# picks constant-power loads over `Load`'s default constant impedance; `gfm` puts a
# grid-forming inverter at E instead of G3; `only_slack` leaves G1 the one responder
# (no governor or damping elsewhere, Pmax 400 so it never caps); `avr` gives every
# machine a field and a regulator (Td0′ 5 s, K_A 50, T_E 0.05 s).
#   system base:  G1 1/R 60, D 3.0, headroom .70 | G2 37.5, 3.0, .40 | G3 20, 1.8, .05
function _m8_acmesh(; r = 0.0, cp = true, slack = :A, gfm = false, S_inv = 300.0,
                      Q1max = Inf, gov = true, damp = 1.0, only_slack = false,
                      avr = false)
    R(x) = gov ? x : Inf
    o = only_slack
    ex = avr ? (; Td0′ = 5.0, K_A = 50.0, T_E = 0.05) : (;)
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0damp, 0.25, 1.05, 150.0, R(0.05),
                  o ? 400.0 : 220.0, 0.5; V_set = 1.05, Q_max = Q1max, ex...),
          Machine(:G2, :C, 150.0, 4.0, o ? 0.0 : 2.0damp, 0.25, 1.04, 60.0,
                  o ? Inf : R(0.04), 100.0, 0.4; V_set = 1.04, ex...)]
    invs = gfm ? [Inverter(:I3, :E, :grid_forming, S_inv, 40.0; K_p = 0.125, V_set = 1.02)] :
                 Inverter[]
    gfm || push!(ms, Machine(:G3, :E, 120.0, 3.5, o ? 0.0 : 1.5damp, 0.25, 1.02, 40.0,
                             o ? Inf : R(0.06), 45.0, 0.6; V_set = 1.02, ex...))
    br = [Branch(id, f, t, x, 500.0; R = r * x) for (id, f, t, x) in
          ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15),
           (:BD, :B, :D, 0.25), (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10),
           (:BE, :B, :E, 0.20))]
    ld(id, b, p, q) = cp ? Load(id, b, p, q, 0, 0, 1) : Load(id, b, p, q)
    ls = [ld(:LB, :B, 130.0, 30.0), ld(:LD, :D, 120.0, 25.0)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms, ls;
                 slack, inverters = invs)
end

# `m` with its fields copied and the named ones replaced — for the rebuilt models.
_m8_machine_with(m::Machine; P0 = m.P0, Pmax = max(m.Pmax, P0)) =
    Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, P0, m.R, Pmax, m.Tg;
            V_set = m.V_set, Q_min = m.Q_min, Q_max = m.Q_max)

# The detailed tier after tripping `lost` at 1 s, read at `T`: each bus's change in
# electrical export (network side, as step 4 reads the swing tier), every machine's
# speed, every bus's |V|. FBDF, not the default Rodas5P: on the default loads Rodas5P
# stalls (MaxIters) where G2's loss drives G3's governor onto its cap, at reltol 1e-10
# and at 1e-6 — the kink-landing stall `detailed.jl` records for the exciter limit, and
# its recorded workaround (D8, "What step 5 measured").
function _m8_detailed_settled(net::NetworkModel, lost::Symbol; T = 300.0)
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = 1e-10,
                abstol = 1e-12, solver = GridSim.OrdinaryDiffEq.FBDF())
    export_of(bus) = sum((br.from === bus ? branch_power(eng, br.from, br.to) :
                          br.to === bus ? branch_power(eng, br.to, br.from) : 0.0)
                         for br in net.branches)
    e0 = Dict(b.id => export_of(b.id) for b in net.buses)
    V0 = current_state(eng).V
    solve!(eng, (0.0, T); perturbations = [1.0 => TripGenerator(lost)], saveat = 1.0)
    st = current_state(eng)
    return (; Δexport = Dict(b.id => export_of(b.id) - e0[b.id] for b in net.buses),
            ω = st.ω, V0, V = st.V)
end

@testset "M8 step 5 — generator outages in the AC screen, a shared reference" begin
    lossy_zip = _m8_acmesh(r = 0.1, cp = false)
    B1 = 1e-10                                   # solution against solution (stated first)

    @testset "the base is ac_powerflow's: each machine loses what it produced there" begin
        base = ac_powerflow(lossy_zip)
        sc = ac_generator_outages(lossy_zip)
        @test sc.base.Vm == base.Vm && sc.base.Pgen == base.Pgen
        @test sc.machines == [:G1, :G2, :G3] && sc.responders == [:G1, :G2, :G3]
        # The slack's machine produced its schedule PLUS the base losses and the loads'
        # shift; the others their schedule.
        st1 = GridSim._ac_shared_setup(lossy_zip, base, 1)
        @test st1.P_lost == base.Pgen[1] && abs(st1.P_lost - 1.5) > 1e-2
        @test GridSim._ac_shared_setup(lossy_zip, base, 2).P_lost == 0.6
        @test all(==(:secure), sc.outcome)
        # A refused base refuses the screen, with ac_powerflow's own message.
        bad = _m8_acmesh(r = 0.1); bad = NetworkModel(bad.S_base, bad.f0, bad.buses,
            [Branch(b.id, b.from, b.to, b.X, 50.0; R = b.R) for b in bad.branches],
            bad.machines, bad.loads; slack = :A)
        msg(f) = try; f(); ""; catch e; e.msg; end
        @test msg(() -> ac_powerflow(bad)) == msg(() -> ac_generator_outages(bad)) != ""
    end

    @testset "all weight on the slack: the shared solve IS ac_powerflow on the rebuilt model" begin
        # Only G1 responds. Losing G3 must then be `ac_powerflow` on the model without
        # G3 and G1's schedule raised by its 40 MW: the same operating point by algebra.
        # `==` is not promised (one more unknown, one more equation: D8's correction);
        # band B1. MEASURED: bit-identical on both fixtures (the extra column reaches only
        # the reference's row, so the elimination does the same arithmetic elsewhere) —
        # recorded, not asserted, because it rests on the pivoting order.
        for (r, cp) in ((0.0, true), (0.1, false))
            net = _m8_acmesh(; r, cp, only_slack = true)
            base = ac_powerflow(net)
            o = GridSim._ac_generator_outcome(net, base, 3)
            @test o.outcome === :secure
            rb = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
                              [_m8_machine_with(net.machines[1]; P0 = 190.0), net.machines[2]],
                              net.loads; slack = :A)
            ap = ac_powerflow(rb)
            s = o.solution
            @test maximum(abs, s.Vm .- ap.Vm) <= B1
            @test maximum(abs, s.θ .- ap.θ) <= B1
            @test maximum(abs, s.flow .- ap.flow) <= B1
            @test maximum(abs, s.Pgen .- ap.Pgen) <= B1
            # THE SHARP CHECK, no band of its own: `ac_powerflow`'s answer, plugged into
            # the shared residual with the speed deviation read off the slack's output,
            # satisfies it to `ac_powerflow`'s own residual (M6 step 3's bound).
            st = GridSim._ac_shared_setup(net, base, 3)
            rd = GridSim._ac_shared_round(st, falses(3), Int[], Bool[])
            x = (ap.Pgen[1] - base.Pgen[1]) / rd.Pb[1]
            u = GridSim._ac_shared_unknowns(rd, ap.Vm, ap.θ, x)
            F = similar(u)
            GridSim._ac_shared_residual!(F, u, rd)
            @test maximum(abs, F) <= length(net.buses) * max(ap.residual, eps())
            @test abs(x + o.Δω) <= B1
            @test o.pickup[1] ≈ ap.Pgen[1] - base.Pgen[1] atol = B1
            @test o.pickup[2] == 0.0 && o.pickup[3] == 0.0
        end
    end

    @testset "pickup = lost power + change in losses + change in load draw (D8's correction)" begin
        # The plan's "lost power + change in losses" is false on the default loads; the
        # load term is the correction, and on the default loads it is asserted to MOVE.
        for (net, zip) in ((_m8_acmesh(r = 0.1), false), (lossy_zip, true),
                           (_m8_acmesh(), false))
            sc = ac_generator_outages(net)
            b = sc.base
            for k in eachindex(sc.machines)
                s = sc.solution[k]
                # What it produced, read off the base and the model — NOT off the
                # screen's own setup, which is the code a wrong lost power would be in.
                P_lost = k == 1 ? b.Pgen[1] : net.machines[k].P0 / net.S_base
                dloss = sum(s.loss) - sum(b.loss)
                dload = sum(s.Pload) - sum(b.Pload)
                bound = length(net.buses) * (max(b.residual, eps()) + max(s.residual, eps()))
                @test abs(sum(sc.pickup[k]) - P_lost - dloss - dload) <= bound
                if zip
                    @test abs(dload) > 1e-3
                else
                    @test abs(dload) <= 1e-14
                end
                any(br -> br.R > 0, net.branches) && @test abs(dloss) > 1e-3
            end
        end
    end

    @testset "lossless, constant power: the AC shares ARE the DC screen's" begin
        # No losses and no load shift leave the sharing rule alone deciding Δω — so the
        # AC screen and step 4's DC screen must agree, governor caps included (losing
        # G1 caps G2 and G3; losing G2 caps G3).
        net = _m8_acmesh()
        dc, ac = dc_generator_outages(net), ac_generator_outages(net)
        @test ac.capped == dc.capped
        @test findall(ac.capped[1]) == [2, 3] && findall(ac.capped[2]) == [3]
        for k in eachindex(dc.machines)
            @test abs(ac.Δω[k] - dc.Δω[k]) <= B1
            @test maximum(abs, ac.pickup[k] .- dc.pickup[k]) <= B1
        end
    end

    @testset "the governor cap is on the droop only: a capped machine settles above Pmax" begin
        sc = ac_generator_outages(lossy_zip)
        ma = machine_arrays(lossy_zip)
        x = -sc.Δω[2]                                   # G2 lost caps G3
        @test sc.capped[2] == [false, false, true]
        @test sc.pickup[2][3] == ma.headroom[3] + x * ma.D[3]
        @test sc.pickup[2][3] > ma.headroom[3] + 1e-4    # above Pmax, by the damping
        @test x * ma.invR[3] > ma.headroom[3]           # the droop alone is past the cap
        # and the uncapped G1 follows the droop-and-damping law exactly
        @test sc.pickup[2][1] == x * (ma.invR[1] + ma.D[1])
    end

    @testset "the reference is a gauge: moved, only the angles shift" begin
        base = ac_powerflow(lossy_zip)
        for k in 1:3
            a = GridSim._ac_generator_outcome(lossy_zip, base, k)
            c = GridSim._ac_generator_outcome(lossy_zip, base, k; reference = :C)
            @test c.solution.slack === :C && c.solution.θ[3] == 0.0
            @test abs(a.Δω - c.Δω) <= B1
            @test maximum(abs, a.pickup .- c.pickup) <= B1
            @test maximum(abs, a.solution.Vm .- c.solution.Vm) <= B1
            @test maximum(abs, a.solution.flow .- c.solution.flow) <= B1
            shift = c.solution.θ .- a.solution.θ
            @test maximum(shift) - minimum(shift) <= B1
            @test abs(shift[1]) > 1e-3                  # the angles DID move
        end
    end

    @testset "losing the reference bus's machine: no special case (D7, the user's choice)" begin
        sc = ac_generator_outages(lossy_zip)
        s = sc.solution[1]
        @test sc.outcome[1] === :secure
        @test s.slack === :A && s.θ[1] == 0.0          # it keeps the angle reference
        @test s.roles[1] === :load                     # and holds no voltage now
        @test s.Vm[1] < 1.05 - 1e-3                    # solved, not its old V_set
        @test :A ∉ s.limited
        @test sc.solution[2].roles[1] === :generator   # while its machine is there
        # `ac_powerflow` keeps its refusal of a slack with no source: the bypass lives
        # only inside the shared solve.
        m = lossy_zip.machines
        rb = NetworkModel(100.0, 50.0, lossy_zip.buses, lossy_zip.branches,
                          [_m8_machine_with(m[2]; P0 = 210.0), m[3]], lossy_zip.loads;
                          slack = :A)
        @test occursin("carries no machine",
                       try; ac_powerflow(rb); ""; catch e; e.msg; end)
        # case9, with INVENTED droop (R 0.05 and D 1 on each machine's base, rated at
        # its Pmax): losing G1 is screened, not thrown — the slack bus keeps its angle,
        # loses its voltage, and the outcome is a voltage refusal naming it.
        br(id, f, t, r, x) = Branch(id, Symbol(:B, f), Symbol(:B, t), x, 500.0; R = r)
        c9 = [br(:L14, 1, 4, 0.0, 0.0576), br(:L45, 4, 5, 0.017, 0.092),
              br(:L56, 5, 6, 0.039, 0.17), br(:L36, 3, 6, 0.0, 0.0586),
              br(:L67, 6, 7, 0.0119, 0.1008), br(:L78, 7, 8, 0.0085, 0.072),
              br(:L82, 8, 2, 0.0, 0.0625), br(:L89, 8, 9, 0.032, 0.161),
              br(:L94, 9, 4, 0.01, 0.085)]
        Pmax, Vg = (250.0, 300.0, 270.0), (1.04, 1.025, 1.025)
        ms = [Machine(Symbol(:G, i), Symbol(:B, i), Pmax[i], 5.0, 1.0, 0.2, 1.0,
                      315 * Pmax[i] / sum(Pmax), 0.05, Pmax[i]; V_set = Vg[i]) for i in 1:3]
        ls = [Load(:D5, :B5, 90.0, 30.0, 0, 0, 1), Load(:D7, :B7, 100.0, 35.0, 0, 0, 1),
              Load(:D9, :B9, 125.0, 50.0, 0, 0, 1)]
        net9 = NetworkModel(100.0, 50.0, [Bus(Symbol(:B, i), 345.0) for i in 1:9], c9, ms,
                            ls; slack = :B1)
        s9 = ac_generator_outages(net9)
        @test s9.outcome == [:voltage, :secure, :secure]
        @test :B1 in (l.bus for l in s9.low[1])
        @test isfinite(s9.Δω[1]) && s9.Δω[1] < 0      # the frequency it solved to is kept
    end

    @testset "the reference's reactive limit is enforced (the user's choice)" begin
        # G1's Q is 0.359 pu at the base and 0.597 after losing G2 (lossy, constant
        # power); a limit between them binds only in the outage, and only because the
        # reference is now an ordinary voltage-holding bus.
        net = _m8_acmesh(r = 0.1, Q1max = 0.478)
        sc = ac_generator_outages(net)
        @test isempty(sc.base.limited)
        s = sc.solution[2]
        @test sc.outcome[2] === :secure
        @test s.limited == [:A] && s.roles[1] === :load
        @test s.Qgen[1] ≈ 0.478 atol = 1e-12
        @test s.Vm[1] < 1.05 - 1e-3
        # `ac_powerflow` on the rebuilt model does NOT enforce the slack's limit: it holds
        # 1.05 pu and runs past it. The difference is the decision, shown on purpose.
        m = net.machines
        rb = NetworkModel(100.0, 50.0, net.buses, net.branches,
                          [_m8_machine_with(m[1]; P0 = 210.0), m[3]], net.loads; slack = :A)
        ap = ac_powerflow(rb)
        @test ap.Vm[1] == 1.05 && ap.Qgen[1] > 0.478 + 0.05 && isempty(ap.limited)
    end

    @testset "a grid-forming inverter's reactive limit follows its real power (the user's choice)" begin
        # I3 rated 45 MVA at 40 MW: √(45² − 40²) = 20.6 MVAr of reactive capability at
        # the base, where E needs 14.9 — no limit binds. Losing G2 raises its output to
        # 43.2 MW, and at THAT power its capability is 12.4 MVAr: it binds there, and
        # only because the power rose.
        net = _m8_acmesh(gfm = true, S_inv = 45.0)
        sc = ac_generator_outages(net)
        @test isempty(sc.base.limited)
        @test sc.responders == [:G1, :G2, :I3]
        s = sc.solution[2]
        @test sc.outcome[2] === :secure && s.limited == [:E]
        P, Q = s.Pgen[5], s.Qgen[5]
        @test P ≈ 0.4 + sc.pickup[2][3] atol = 1e-12
        @test hypot(P, Q) ≈ 0.45 rtol = 1e-12          # AT its rating, not past it
        @test Q < sqrt(0.45^2 - 0.4^2) - 0.05           # the base-power limit would not bind
        # Losing G1 hands it 100 MW: past its rating whatever its Q, so flagged.
        @test sc.outcome[1] === :overload
        @test only(sc.over[1]).kind === :inverter && only(sc.over[1]).id === :I3
        @test only(sc.over[1]).rating == 45.0 && only(sc.over[1]).mva > 45.0
        @test sc.solution[1] !== nothing               # the solved point is the result
    end

    @testset "the refusals: D7's two, and a reference bus with two sources" begin
        @test all(==(:no_response), ac_generator_outages(_m8_acmesh(gov = false, damp = 0.0)).outcome)
        s0 = ac_generator_outages(_m8_acmesh(damp = 0.0))
        @test s0.outcome == [:reserve_exhausted, :secure, :secure]
        @test isnan(s0.Δω[1]) && s0.solution[1] === nothing && all(iszero, s0.pickup[1])
        n0 = _m8_acmesh()
        two = NetworkModel(100.0, 50.0, n0.buses, n0.branches,
                           vcat(n0.machines, [Machine(:G4, :A, 50.0, 2.0, 1.0, 0.25, 1.05, 0.0;
                                                      V_set = 1.05)]), n0.loads; slack = :A)
        @test occursin("carries 2 sources", try; ac_generator_outages(two); ""; catch e; e.msg; end)
        # The governor half of back-off, predicted unreachable through a fixture
        # (capping raises x), so its piece is exercised directly.
        g, h = [10.0, 20.0, 5.0], [0.5, 1.0, 0.1]
        @test GridSim._governor_backoff_violations(Bool[1, 0, 1], 0.04, g, h) == [1]
        @test isempty(GridSim._governor_backoff_violations(Bool[1, 0, 1], 0.05, g, h))
    end

    @testset "a grid-following inverter is screened like the load it offsets" begin
        # 30 MW of grid-following inverter at D and 30 MW more constant-power load
        # there: the same equations, so the same screen.
        a = _m8_acmesh(r = 0.1)
        b = NetworkModel(100.0, 50.0, a.buses, a.branches, a.machines,
                         [a.loads[1], Load(:LD, :D, 150.0, 25.0, 0, 0, 1)]; slack = :A,
                         inverters = [Inverter(:F1, :D, :grid_following, 50.0, 30.0)])
        sa, sb = ac_generator_outages(a), ac_generator_outages(b)
        @test sb.responders == sa.responders           # it does not respond
        @test sb.outcome == sa.outcome
        for k in 1:3
            @test abs(sa.Δω[k] - sb.Δω[k]) <= B1
            @test maximum(abs, sa.pickup[k] .- sb.pickup[k]) <= B1
            @test maximum(abs, sa.solution[k].Vm .- sb.solution[k].Vm) <= B1
        end
    end

    @testset "the detailed tier: the same shares on constant power, load relief on the default" begin
        B4 = 1e-7                                      # step 4's band, at reltol 1e-10
        bus = [:A, :C, :E]
        ma = machine_arrays(_m8_acmesh())
        # CONSTANT POWER, lossless: the total is the lost power in both tiers, so Δω and
        # every share are the sharing rule's alone (D8: a re-test of D2, kept).
        net = _m8_acmesh()
        sc = ac_generator_outages(net)
        # Settled, not passing through: read at 300 s AND 450 s (the band is a claim
        # at reltol 1e-10 on FBDF; measured worst over every read here 8.1e-10).
        for lost in (:G2, :G3), T in (300.0, 450.0)    # G2's loss caps G3
            k = findfirst(==(lost), sc.machines)
            d = _m8_detailed_settled(net, lost; T)
            for i in 1:3
                i == k && continue
                @test abs(d.Δexport[bus[i]] - sc.pickup[k][i]) <= B4
                @test abs(d.ω[i] - sc.Δω[k]) <= B4
            end
        end
        # DEFAULT LOADS: the tiers hold voltage differently, so their load relief
        # differs. Predicted first: without a regulator the detailed tier's voltages
        # sag further, its loads draw less and it settles at a SMALLER |Δω|; with one,
        # the gap shrinks and keeps its sign. And it is load relief EXACTLY: the
        # sharing rule fed the detailed tier's own settled load draw gives its Δω.
        gaps = Float64[]
        for avr in (false, true)
            net = _m8_acmesh(cp = false; avr)
            sc = ac_generator_outages(net)
            ls = [(net.bus_index[l.bus], l.P0 / net.S_base) for l in net.loads]
            for lost in (:G2, :G3), T in (300.0, 450.0)
                k = findfirst(==(lost), sc.machines)
                d = _m8_detailed_settled(net, lost; T)
                @test abs(d.ω[mod1(k + 1, 3)]) < abs(sc.Δω[k]) - 1e-6
                T == 300.0 && push!(gaps, abs(sc.Δω[k]) - abs(d.ω[mod1(k + 1, 3)]))
                # Lossless: what the survivors pick up is the lost power plus the change
                # in what the constant-impedance loads draw at the detailed tier's |V|.
                dload = sum(P0 * (d.V[v]^2 - d.V0[v]^2) for (v, P0) in ls)
                alive = trues(3); alive[k] = false
                st, Δω, pk, _ = GridSim._pickup_solve(ma.invR, ma.D, ma.headroom, alive,
                                                      ma.Pm[k] + dload)
                @test st === :shared
                for i in 1:3
                    i == k && continue
                    @test abs(d.ω[i] - Δω) <= B4
                    @test abs(d.Δexport[bus[i]] - pk[i]) <= B4
                end
            end
        end
        @test gaps[3] < gaps[1] && gaps[4] < gaps[2]   # the regulator narrows it
    end

    # ── Review follow-ups (predictions in step5_predictions.md, before the runs) ──

    @testset "a base whose slack is already past its own reactive limit refuses the screen" begin
        # `ac_powerflow` lets the slack run past its limits; this screen enforces them,
        # so such a base would put every outage's reference on its limit whatever the
        # outage did. Refused by name (the user's choice, 2026-10-07). G1 makes 35.9
        # MVAr in this base.
        msg = try; ac_generator_outages(_m8_acmesh(r = 0.1, Q1max = 0.30)); "";
              catch e; e isa ArgumentError ? e.msg : ""; end
        @test occursin("slack bus :A", msg) && occursin("reactive limits", msg)
        @test ac_powerflow(_m8_acmesh(r = 0.1, Q1max = 0.30)).Vm[1] == 1.05   # it accepts it
        @test all(==(:secure), ac_generator_outages(_m8_acmesh(r = 0.1, Q1max = 0.478)).outcome)
    end

    @testset "a grid-forming inverter as the slack's one source" begin
        # Its base output is the SOLVED one (1.5302 pu: 150 MW plus the losses), and its
        # reactive limit follows that plus its share. Rated 175 MVA, K_p 0.05.
        n = _m8_acmesh(r = 0.1)
        net = NetworkModel(100.0, 50.0, n.buses, n.branches, n.machines[2:3], n.loads;
                           slack = :A, inverters = [Inverter(:I1, :A, :grid_forming, 175.0,
                                                             150.0; K_p = 0.05, V_set = 1.05)])
        sc = ac_generator_outages(net)
        b = sc.base
        @test sc.machines == [:G2, :G3] && sc.responders == [:G2, :G3, :I1]
        s = sc.solution[2]                             # G3 lost
        @test sc.outcome[2] === :secure && s.limited == [:A]
        @test hypot(s.Pgen[1], s.Qgen[1]) ≈ 1.75 rtol = 1e-12   # AT its rating
        @test s.Pgen[1] ≈ b.Pgen[1] + sc.pickup[2][3] atol = 1e-12
        bound = 5 * (max(b.residual, eps()) + max(s.residual, eps()))
        @test abs(sum(sc.pickup[2]) - 0.4 - (sum(s.loss) - sum(b.loss)) -
                  (sum(s.Pload) - sum(b.Pload))) <= bound
        # Losing G2 hands it more than its rating can carry.
        @test sc.outcome[1] === :overload && only(sc.over[1]).id === :I1
        @test only(sc.over[1]).kind === :inverter
    end

    @testset "a negative-P0 machine lost: frequency rises, nothing caps, DC agrees" begin
        # D8.9 says every machine is screened, a load-as-machine too; checked here. 30 MW
        # of LB's load moved onto a −30 MW machine at B (damping 2 on 100 MVA).
        n = _m8_acmesh()
        net = NetworkModel(100.0, 50.0, n.buses, n.branches,
                           vcat(n.machines, [Machine(:LM, :B, 100.0, 1.0, 2.0, 0.25, 1.0, -30.0)]),
                           [Load(:LB, :B, 100.0, 30.0, 0, 0, 1), n.loads[2]]; slack = :A)
        ac, dc = ac_generator_outages(net), dc_generator_outages(net)
        k = findfirst(==(:LM), ac.machines)
        @test ac.outcome[k] === :secure
        @test ac.Δω[k] > 0 && !any(ac.capped[k])
        @test abs(ac.Δω[k] - dc.Δω[k]) <= B1
        @test maximum(abs, ac.pickup[k] .- dc.pickup[k]) <= B1
        s = ac.solution[k]
        @test abs(sum(ac.pickup[k]) + 0.3 - (sum(s.loss) - sum(ac.base.loss))) <=
              5 * (max(ac.base.residual, eps()) + max(s.residual, eps()))
    end
end
