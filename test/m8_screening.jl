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
