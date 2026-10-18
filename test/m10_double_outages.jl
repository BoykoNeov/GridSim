# ─────────────────────────────────────────────────────────────────────────────
# M10 step 1: the two-line DC factors (`dc_line_pair_outages`), checked against the
# brute force they stand in for — rebuild the model without both branches and solve
# again. Every prediction was written BEFORE the code ran
# (`docs/evidence/gridsim-m10/step1_predictions.md`).
#
# Bands, stated first: 100·eps·max|f| on an ordinary pair (M8 step 2's), and that over
# |det M| on a nearly-cut pair.
#
# The fixture with connected pairs is the REPORT mesh (`OutageScreenScript.mesh`, seven
# branches, 19 of its 21 pairs connected) — not M8 step 2's six-branch `_m8_mesh`, whose
# spur D–E cuts every pair it is in. case9 has no connected pair at all (m10-context.md
# D1); both grids are the report script's, the ones step 0's census counted.
# ─────────────────────────────────────────────────────────────────────────────

const _M10_MESH = OutageScreenScript.mesh
const _M10_CASE9 = OutageScreenScript.case9

# Brute force for the pair `(k, l)`: every branch's flow after rebuilding without both,
# in `net`'s branch order with entries `k` and `l` zero — placed BY ID, never by
# position — or `nothing` where the model is refused as disconnected.
function _m10_rebuilt(net::NetworkModel, k::Int, l::Int)
    ids = (net.branches[k].id, net.branches[l].id)
    rest = try
        NetworkModel(net.S_base, net.f0, net.buses, filter(b -> !(b.id in ids), net.branches),
                     net.machines, net.loads; slack = net.slack, inverters = net.inverters)
    catch e
        e isa ArgumentError && occursin("not connected", e.msg) || rethrow()
        return nothing
    end
    out = zeros(length(net.branches))
    sol = dc_powerflow(rest)
    for (j, id) in pairs(sol.branches)
        out[findfirst(b -> b.id === id, net.branches)] = sol.flow[j]
    end
    return out
end

# Worst `gap / band` over every connected pair; checks the cut set against the rebuild
# refusals and the two removed entries along the way.
function _m10_vs_rebuilt(net::NetworkModel)
    s = dc_line_pair_outages(net)
    worst = 0.0
    for (p, (k, l)) in pairs(s.pairs)
        bf = _m10_rebuilt(net, k, l)
        @test s.splits[p] == (bf === nothing)
        bf === nothing && continue
        band = 100 * eps() * max(maximum(abs, s.base.flow), maximum(abs, bf))
        worst = max(worst, maximum(abs.(s.flow[p] .- bf)) / band)
        @test s.flow[p][k] === 0.0 && s.flow[p][l] === 0.0
    end
    return worst
end

# The additive shortcut for a connected pair whose lines are not bridges: both
# single-outage moves from M8's screen added to the base.
function _m10_shortcut(s1::DCLineOutages, k::Int, l::Int)
    f = s1.base.flow
    short = f .+ (s1.flow[k] .- f) .+ (s1.flow[l] .- f)
    short[k] = short[l] = 0.0
    return short
end

# Two triangles sharing bus C: A–B–C and C–D–E. A transfer inside one triangle puts no
# flow on the other — structurally, through the shared vertex — so every cross pair is
# the shortcut's exact case. The reference is A, NOT the shared C: with C as the
# reference the reduced matrix is block-diagonal and the zeros would be exact by
# construction rather than round-off.
_m10_bowtie() = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)],
    [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:BC, :B, :C, 0.15, 500.0),
     Branch(:CA, :C, :A, 0.22, 500.0), Branch(:CD, :C, :D, 0.12, 500.0),
     Branch(:DE, :D, :E, 0.18, 500.0), Branch(:EC, :E, :C, 0.27, 500.0)],
    [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 100.0),
     Machine(:G2, :D, 150.0, 4.0, 2.0, 0.25, 1.04, 50.0)],
    [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0), Load(:LE, :E, 70.0, 20.0, 0.0, 0.0, 1.0)];
    slack = :A)

@testset "M10 step 1 — two-line DC factors, cut pairs from the graph" begin

    @testset "the pair code's per-branch solve IS dc_line_outages's, bit for bit" begin
        # Two copies of one loop (m10-context.md D7: M8's function is left untouched,
        # so its gate holds by construction). This holds them together: the same
        # operations in the same order give the same bits.
        for net in (_M10_MESH(), _M10_CASE9())
            P = GridSim._dc_transfer_factors(net, inv.(branch_topology(net).X))
            s1 = dc_line_outages(net)
            f = s1.base.flow
            @test all(1.0 - P[k, k] === s1.margin[k] for k in eachindex(f))
            for k in findall(!, s1.splits)
                post = [f[e] + P[e, k] / s1.margin[k] * f[k] for e in eachindex(f)]
                post[k] = 0.0
                @test post == s1.flow[k] && all(post .=== s1.flow[k])
            end
        end
    end

    @testset "cut pairs come from the graph and equal the rebuild refusals" begin
        c9, mesh = _M10_CASE9(), _M10_MESH()
        s9, sm = dc_line_pair_outages(c9), dc_line_pair_outages(mesh)
        @test length(s9.pairs) == 36 && all(s9.splits)
        @test all(isempty, s9.flow)
        idm = sm.base.branches
        @test Set((idm[k], idm[l]) for (k, l) in sm.pairs[sm.splits]) == Set([(:AB, :AC), (:DE, :BE)])
        @test count(sm.splits) == 2 && count(!, sm.splits) == 19
        # Every split is a rebuild refusal and every refusal a split, on both grids.
        for net in (c9, mesh)
            s = dc_line_pair_outages(net)
            @test all(s.splits[p] == (_m10_rebuilt(net, k, l) === nothing)
                      for (p, (k, l)) in pairs(s.pairs))
        end
        # A pair can cut the grid while neither line is a bridge: case9's 15 ring pairs.
        br = GridSim._bridge_mask(c9)
        @test count(!br[k] && !br[l] for (k, l) in s9.pairs) == 15
        # At a cut, det M is round-off (measured ≤ 2.6e-16, negative, zero AND positive
        # among case9's 36) — which is why it is never tested for a split.
        @test all(abs.(s9.det) .<= 10eps()) && all(abs.(sm.det[sm.splits]) .<= 10eps())
        # And a connected pair's is not: floor set AFTER measuring (smallest 0.0527, at
        # AB+DE), not a prediction — ten orders above the cuts' round-off either way.
        @test all(abs.(sm.det[.!sm.splits]) .> 1e-3)
    end

    @testset "the mesh: the two-line factors ARE rebuild-and-re-solve, to round-off" begin
        net = _M10_MESH()
        @test _m10_vs_rebuilt(net) <= 1           # measured worst 0.119
        # Not vacuous for a transposed M: M is symmetric only when the two lines'
        # reactances are equal (AB/DE, AC/BE here), and the other connected pairs are
        # checked too. The count is set AFTER measuring (17 of 19 above 0.01; the two
        # equal-reactance pairs at 0.0 and 1.4e-16), not predicted; what shows the check
        # is not vacuous is the transposition sabotage going red here.
        P = GridSim._dc_transfer_factors(net, inv.(branch_topology(net).X))
        s = dc_line_pair_outages(net)
        asym = [abs(P[k, l] - P[l, k]) for (p, (k, l)) in pairs(s.pairs) if !s.splits[p]]
        @test count(>(0.01), asym) >= 10
    end

    @testset "the additive shortcut is measurably wrong on the mesh" begin
        # Measured on every one of the 19 connected pairs, 9.8e11 to 2.5e13 times the
        # band; the size was not predicted (Hurdle 18.2), only that it is not round-off.
        net = _M10_MESH()
        s, s1 = dc_line_pair_outages(net), dc_line_outages(net)
        @test !any(s1.splits)
        band = 100 * eps() * maximum(abs, s.base.flow)
        gaps = [maximum(abs.(_m10_shortcut(s1, k, l) .- s.flow[p])) / band
                for (p, (k, l)) in pairs(s.pairs) if !s.splits[p]]
        @test length(gaps) == 19 && all(gaps .> 1e6)
    end

    @testset "control: two lines whose transfers do not cross — the shortcut is exact" begin
        net = _m10_bowtie()
        s, s1 = dc_line_pair_outages(net), dc_line_outages(net)
        @test _m10_vs_rebuilt(net) <= 1
        P = GridSim._dc_transfer_factors(net, inv.(branch_topology(net).X))
        tri(k) = k <= 3 ? 1 : 2
        band = 100 * eps() * maximum(abs, s.base.flow)
        for (p, (k, l)) in pairs(s.pairs)
            if tri(k) == tri(l)
                @test s.splits[p]                   # two sides of a triangle cut a vertex off
                continue
            end
            @test !s.splits[p]
            @test abs(P[k, l]) <= 10eps() && abs(P[l, k]) <= 10eps()
            @test maximum(abs.(_m10_shortcut(s1, k, l) .- s.flow[p])) <= band
        end
        @test count(s.splits) == 6 && count(!, s.splits) == 9
    end

    @testset "a nearly-cut pair: answered, not thresholded; the error grows as 1/|det M|" begin
        # A weak branch A–D of reactance Xw makes AB+AC no longer a cut. Each line's own
        # margin stays moderate (the other line is a way round it); only det M is small.
        #
        # The exact answer needs no ill-conditioned solve: A then hangs off A–D alone,
        # which carries G1's whole 1.5 pu, and the rest is the four-bus grid with that
        # injection moved to D. That, and not the rebuild, is the oracle — the rebuild
        # DRIFTS here (below), unlike M8 step 2's near-bridge.
        m0 = _M10_MESH()
        four = NetworkModel(100.0, 50.0, [b for b in m0.buses if b.id !== :A],
            [b for b in m0.branches if !(b.id in (:AB, :AC))],
            [GridSim._machine_with(m0.machines[1]; bus = :D); m0.machines[2:end]], m0.loads;
            slack = :C)
        ff = dc_powerflow(four)
        weak(Xw, slack) = NetworkModel(m0.S_base, m0.f0, m0.buses,
            [m0.branches; Branch(:AD, :A, :D, Xw, 500.0)], m0.machines, m0.loads; slack)
        ids = [b.id for b in weak(1.0, :A).branches]
        exact = zeros(length(ids))
        for (j, id) in pairs(ff.branches)
            exact[findfirst(==(id), ids)] = ff.flow[j]
        end
        exact[findfirst(==(:AD), ids)] = 1.5
        scale = maximum(abs, exact)
        dets, gaps = Float64[], Float64[]
        for Xw in (1e3, 1e5, 1e7)
            net = weak(Xw, :A)
            s = dc_line_pair_outages(net)
            p = findfirst(==((1, 2)), s.pairs)             # AB+AC
            @test ids[1:2] == [:AB, :AC] && !s.splits[p]
            P = GridSim._dc_transfer_factors(net, inv.(branch_topology(net).X))
            @test 1 - P[1, 1] > 0.2 && 1 - P[2, 2] > 0.2   # measured 0.243, 0.486
            gap = maximum(abs.(s.flow[p] .- exact))
            @test gap <= 100 * eps() * scale / abs(s.det[p])   # measured 0.004–0.005 of it
            push!(dets, s.det[p]); push!(gaps, gap)
            # Attribution. With the reference on the main grid the rebuild is exact; with
            # it on the nearly cut-off bus every other angle is ~1.5·Xw and the flows are
            # differences of large numbers (measured 1.2e-11, 1.0e-9, 1.2e-7 — larger
            # than the factors' own error).
            @test maximum(abs.(_m10_rebuilt(weak(Xw, :C), 1, 2) .- exact)) <= 100 * eps() * scale
            Xw == 1e7 && @test maximum(abs.(_m10_rebuilt(net, 1, 2) .- exact)) > 1000 * 100 * eps() * scale
        end
        # det M ∝ 1/Xw (measured 4.86e-5, 4.86e-7, 4.86e-9) ...
        @test isapprox(dets[3] / dets[1], 1e-4; rtol = 1e-2)
        # ... and the signature: the error grows as det M shrinks (measured 2.8e-12,
        # 3.6e-10, 3.3e-8), and at 1e7 it is far outside the ORDINARY band (9.8e5 times).
        @test gaps[3] >= 100 * gaps[1]
        @test gaps[3] > 1000 * 100 * eps() * scale
    end

    @testset "an inverter is read through the base case, and the identity still holds" begin
        # M7's exported-surface walk calls this on an inverter model; the inverter only
        # moves the base flows, which come from `dc_powerflow`, and the rebuild carries
        # `net.inverters`. 30 MW of inverter offset by 30 MW more load at the same bus.
        m0 = _M10_MESH()
        ls = [l.id === :LD ? Load(:LD, :D, 150.0, 25.0, 0.0, 0.0, 1.0) : l for l in m0.loads]
        net = NetworkModel(m0.S_base, m0.f0, m0.buses, m0.branches, m0.machines, ls;
            slack = m0.slack, inverters = [Inverter(:pv, :D, :grid_following, 100.0, 30.0)])
        @test _m10_vs_rebuilt(net) <= 1
        a, b = dc_line_pair_outages(net), dc_line_pair_outages(m0)
        @test a.splits == b.splits
        scale = maximum(abs, b.base.flow)
        @test all(maximum(abs.(a.flow[p] .- b.flow[p]); init = 0.0) <= 100eps() * scale
                  for p in eachindex(a.flow))
    end
end
