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

# ─────────────────────────────────────────────────────────────────────────────
# M10 step 2: every pair of elements in DC, a split grid answered piece by piece
# (`dc_pair_outages`). Predictions and bands were written first:
# `docs/evidence/gridsim-m10/step2_predictions.md`.
#
# Two oracles, neither of them the screen's own code: each live piece rebuilt as its own
# model (its imbalance read from the equipment list, its shares from `pickup_shares` on
# that model, its flows from `dc_powerflow`), and the swing tier, which settles each
# piece at its own frequency with no rule written down at all.
# ─────────────────────────────────────────────────────────────────────────────

# case9 shaped for the swing tier, which carries exactly one machine per bus and no
# `Load`: the three loads become negative-P0 machines, the three empty buses zero-P0
# fillers, and every branch is lossless (the swing tier reads R since M9 step 2; the
# DC rule is exact only without it). The load-machines and fillers are damped, so they
# share too — the static screen is run on THIS model, never on the report grid.
function _m10_swing_case9()
    c9 = _M10_CASE9()
    br = [Branch(b.id, b.from, b.to, b.X, b.rating) for b in c9.branches]
    ms = [c9.machines;
          [Machine(l.id, l.bus, 100.0, 1.0, 1.0, 0.25, 1.0, -l.P0) for l in c9.loads];
          [Machine(Symbol(:F, i), Symbol(:B, i), 100.0, 1.0, 0.5, 0.25, 1.0, 0.0) for i in (4, 6, 8)]]
    NetworkModel(c9.S_base, c9.f0, c9.buses, br, ms; slack = c9.slack)
end

# M8 step 4's swing-tier mesh, copied (the focused runner does not load M8's test
# file): loads are negative-P0 machines, and losing G2 caps G3's governor.
#   system base:  G1 1/R 60, D 3.0, headroom .70 | G2 37.5, 3.0, .40 | G3 20, 1.8, .05
function _m10_genmesh()
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.05, 150.0, 0.05, 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0, 0.04, 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5, 0.25, 1.00, -120.0),
          Machine(:G3, :E, 120.0, 3.5, 1.5, 0.25, 1.02, 40.0, 0.06, 45.0, 0.6)]
    br = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
          Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
          Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0),
          Branch(:BE, :B, :E, 0.20, 500.0)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms; slack = :A)
end

# A triangle A–B–C with an inverter alone at C (D4): a grid-following one leaves a piece
# with nothing to set its frequency, a grid-forming one a piece with a source and no load.
function _m10_inverter_corner(mode::Symbol)
    iv = mode === :grid_forming ? Inverter(:I3, :C, :grid_forming, 100.0, 20.0; K_p = 0.1) :
                                  Inverter(:I3, :C, :grid_following, 100.0, 20.0)
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C)],
        [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:BC, :B, :C, 0.15, 500.0),
         Branch(:CA, :C, :A, 0.20, 500.0)],
        [Machine(:G1, :A, 200.0, 5.0, 1.0, 0.25, 1.0, 60.0, 0.05, 200.0)],
        [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0)]; slack = :A, inverters = [iv])
end

# The pair's index by element ids, in either order.
function _m10_pair(s::DCPairOutages, a::Symbol, b::Symbol)
    i, j = findfirst(==(a), s.id), findfirst(==(b), s.id)
    return findfirst(==((min(i, j), max(i, j))), s.pairs)
end

_m10_live(s::DCPairOutages, p::Int) = [pc for pc in s.pieces[p] if pc.kind === :live]

# Brute force for one live piece that shared: the piece built as its own model.
#   - its imbalance read from the EQUIPMENT LIST (its surviving machines' and
#     inverters' P0 less its loads), never from the screen's base-flow reading;
#   - its shares from `pickup_shares` on the piece at its schedule, the imbalance
#     carried by a balancing dummy machine with no droop and no damping, then lost;
#   - its flows from `dc_powerflow` on the piece with every unit at schedule + pickup,
#     placed by branch id.
function _m10_piece_check(net::NetworkModel, s::DCPairOutages, p::Int, pc::DCPiece)
    i, j = s.pairs[p]
    gone = (s.id[i], s.id[j])
    inp(bus) = bus in pc.buses
    Sb = net.S_base
    bs = [bu for bu in net.buses if inp(bu.id)]
    brs = [br for br in net.branches if inp(br.from) && inp(br.to) && !(br.id in gone)]
    ms = [mc for mc in net.machines if inp(mc.bus) && !(mc.id in gone)]
    ivs = [iv for iv in net.inverters if inp(iv.bus)]
    ls = [l for l in net.loads if inp(l.bus)]
    Σ = sum(mc.P0 for mc in ms; init = 0.0) + sum(iv.P0 for iv in ivs; init = 0.0) -
        sum(l.P0 for l in ls; init = 0.0)
    scale = (sum(abs(mc.P0) for mc in net.machines; init = 0.0) +
             sum(abs(iv.P0) for iv in net.inverters; init = 0.0) +
             sum(l.P0 for l in net.loads; init = 0.0)) / Sb
    @test abs(pc.imbalance - (-Σ / Sb)) <= 100eps() * scale
    slack = net.slack in pc.buses ? net.slack : pc.buses[1]
    resp = Dict(id => q for (q, id) in pairs(s.responders))
    dummy = Machine(:X_m10, slack, 100.0, 1.0, 0.0, 0.25, 1.0, -Σ)
    sh = pickup_shares(NetworkModel(Sb, net.f0, bs, brs, [ms; dummy], ls; slack,
                                    inverters = ivs), :X_m10)
    @test isapprox(sh.Δω, pc.Δω; rtol = 1e-12, atol = 1e-15)
    for (q, rid) in pairs(sh.responders)
        rid === :X_m10 && continue
        @test isapprox(s.pickup[p][resp[rid]], sh.pickup[q]; rtol = 1e-12, atol = 1e-15)
        @test s.capped[p][resp[rid]] == sh.capped[q]
    end
    up = [GridSim._machine_with(mc; P0 = mc.P0 + s.pickup[p][resp[mc.id]] * Sb,
                                Pmax = max(mc.Pmax, mc.P0 + s.pickup[p][resp[mc.id]] * Sb))
          for mc in ms]
    iup = [iv.mode === :grid_forming ?
           GridSim._inverter_with(iv; P0 = iv.P0 + s.pickup[p][resp[iv.id]] * Sb) : iv
           for iv in ivs]
    isempty(brs) && return nothing
    sol = dc_powerflow(NetworkModel(Sb, net.f0, bs, brs, up, ls; slack, inverters = iup))
    band = 100eps() * max(maximum(abs, s.base.flow), maximum(abs, sol.flow))
    for (e, bid) in pairs(sol.branches)
        @test abs(s.flow[p][findfirst(==(bid), s.id)] - sol.flow[e]) <= band
    end
    return nothing
end

# Every live piece that shared, on every pair of `net`; returns how many were checked.
function _m10_brute_all(net::NetworkModel)
    s = dc_pair_outages(net)
    checked = 0
    for p in eachindex(s.pairs), pc in s.pieces[p]
        (pc.kind === :live && pc.outcome === :shared) || continue
        _m10_piece_check(net, s, p, pc)
        checked += 1
    end
    return checked
end

# The swing tier's events for pair `p`: its two elements, and every machine in a piece
# whose sources are lost, all at the same instant (Hurdle 19.4). A stranded load-machine
# is NOT tripped: it is the swing tier's load, and only the rest is checked (19.3).
function _m10_events(net::NetworkModel, s::DCPairOutages, p::Int)
    evs = Any[]
    for e in s.pairs[p]
        if s.kind[e] === :branch
            br = net.branches[e]
            push!(evs, TripLine(br.from, br.to))
        else
            push!(evs, TripGenerator(s.id[e]))
        end
    end
    for pc in s.pieces[p], mc in net.machines
        pc.kind === :sources_lost && mc.bus in pc.buses &&
            !(TripGenerator(mc.id) in evs) && push!(evs, TripGenerator(mc.id))
    end
    return evs
end

# The swing tier after `first` at t = 0 and `second` at `t2` (none by default), read at
# each of `Ts`: every vertex's speed and governor state, and every bus's change in
# ELECTRICAL export (Σ branch_power out of it, after − before) — the network side, never
# the rule's formula. M8 step 4's `_m8_swing_settled`, with a second event.
function _m10_swing(net::NetworkModel, first, Ts; second = (), t2 = Inf)
    eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
    export_of(bus) = sum((br.from === bus ? branch_power(eng, br.from, br.to) :
                          br.to === bus ? branch_power(eng, br.to, br.from) : 0.0)
                         for br in net.branches)
    e0 = Dict(b.id => export_of(b.id) for b in net.buses)
    foreach(ev -> inject!(eng, ev), first)
    pending = !isempty(second)
    out = []
    for T in Ts
        if pending && T > t2
            while eng.integrator.t < t2 - 1e-9
                step!(eng, 0.05)
            end
            foreach(ev -> inject!(eng, ev), second)
            pending = false
        end
        while eng.integrator.t < T - 1e-9
            step!(eng, 0.05)
        end
        st = current_state(eng)
        push!(out, (; Δexport = Dict(b.id => export_of(b.id) - e0[b.id] for b in net.buses),
                      ω = copy(st.ω), ΔPm = copy(st.ΔPm)))
    end
    return out
end

# Every machine the swing check reads, with its piece: the survivors of live pieces
# that shared. Lost machines and everything in a dead piece are left out by name.
function _m10_survivors(net::NetworkModel, s::DCPairOutages, p::Int)
    gone = Set(s.id[e] for e in s.pairs[p])
    out = Tuple{Int,Symbol,DCPiece}[]          # (vertex, machine id, piece)
    for pc in s.pieces[p]
        (pc.kind === :live && pc.outcome === :shared) || continue
        for mc in net.machines
            mc.bus in pc.buses && !(mc.id in gone) &&
                push!(out, (net.bus_index[mc.bus], mc.id, pc))
        end
    end
    return out
end

@testset "M10 step 2 — every pair in DC, a split grid piece by piece" begin

    @testset "the pairs, counted and classified before anything is shared" begin
        c9, mesh = _M10_CASE9(), _M10_MESH()
        s9, sm = dc_pair_outages(c9), dc_pair_outages(mesh)
        @test length(s9.pairs) == 66 && length(sm.pairs) == 45
        @test s9.id == [[b.id for b in c9.branches]; [mc.id for mc in c9.machines]]
        kinds(s, p) = Tuple(sort([pc.kind for pc in s.pieces[p] if pc.kind !== :empty]))
        both(s, p, k) = s.kind[s.pairs[p][1]] === k && s.kind[s.pairs[p][2]] === k
        ll = [p for p in eachindex(s9.pairs) if both(s9, p, :branch)]
        @test length(ll) == 36 && all(s9.splits[ll])
        @test count(p -> kinds(s9, p) == (:live, :live), ll) == 9
        @test count(p -> kinds(s9, p) == (:live, :load_lost), ll) == 3
        @test count(p -> kinds(s9, p) == (:live, :sources_lost), ll) == 21
        @test count(p -> kinds(s9, p) == (:live, :sources_lost, :sources_lost), ll) == 3
        lg = [p for p in eachindex(s9.pairs) if s9.kind[s9.pairs[p][1]] !== s9.kind[s9.pairs[p][2]]]
        @test length(lg) == 27 && count(s9.splits[lg]) == 9
        gg = [p for p in eachindex(s9.pairs) if both(s9, p, :machine)]
        @test length(gg) == 3 && !any(s9.splits[gg])
        # D4: three pairs are one event, a bridge with the lone machine it cuts off.
        @test Set((s9.id[s9.pairs[p][1]], s9.same_as[p]) for p in eachindex(s9.pairs)
                  if s9.same_as[p] !== :none) == Set([(:L14, :G1), (:L82, :G2), (:L36, :G3)])
        @test all(==(:none), sm.same_as)
        # The mesh: only AB+AC and DE+BE split, each cutting off a lone generator.
        @test Set((sm.id[sm.pairs[p][1]], sm.id[sm.pairs[p][2]]) for p in findall(sm.splits)) ==
              Set([(:AB, :AC), (:DE, :BE)])
        @test all(kinds(sm, p) == (:live, :sources_lost) for p in findall(sm.splits))
        # Every live piece of both report grids shared: the invented droop is damped.
        live = [pc for ps in [s9.pieces; sm.pieces] for pc in ps if pc.kind === :live]
        @test !isempty(live) && all(pc -> pc.outcome === :shared, live)
    end

    @testset "a pair that leaves the grid whole is M8's rule on two losses" begin
        for net in (_M10_MESH(), _M10_CASE9(), _m10_genmesh())
            s, s2 = dc_pair_outages(net), dc_line_pair_outages(net)
            r = GridSim._responders(net)
            nb = length(net.branches)
            for p in findall(!, s.splits)
                i, j = s.pairs[p]
                pc = only(s.pieces[p])
                pc.kind === :live || continue
                lostP = (s.kind[i] === :machine ? r.P[i - nb] : 0.0) +
                        (s.kind[j] === :machine ? r.P[j - nb] : 0.0)
                # Exactly the lost schedule: no cut, so nothing crossed one.
                @test pc.imbalance === lostP
                if s.kind[j] === :branch
                    # Two lines: step 1's rank-two flows, the same vector of bits.
                    @test pc.Δω === 0.0 && all(iszero, s.pickup[p])
                    @test s.flow[p] == s2.flow[findfirst(==((i, j)), s2.pairs)]
                end
            end
        end
        # A whole grid with no load left is not live (D4): genmesh's LB+LD takes both
        # loads, and its generators' output is lost with nowhere to go. Measured, not
        # predicted: the predictions assumed every whole-grid pair was live.
        net = _m10_genmesh()
        s = dc_pair_outages(net)
        pc = only(s.pieces[_m10_pair(s, :LB, :LD)])
        @test pc.kind === :sources_lost && pc.imbalance === 0.0
        @test pc.sources_lost ≈ 2.5 rtol = 1e-14
        @test count(p -> all(q -> q.kind !== :live, s.pieces[p]), eachindex(s.pairs)) == 1
    end

    @testset "case9 L45+L67: one piece rises, the other falls (D1's arithmetic)" begin
        c9 = _M10_CASE9()
        s = dc_pair_outages(c9)
        p = _m10_pair(s, :L45, :L67)
        g3, rest = s.pieces[p][2], s.pieces[p][1]
        @test Set(g3.buses) == Set([:B3, :B5, :B6])
        surplus = (315.0 * 270.0 / 820.0 - 90.0) / 100.0
        # G3: 1/R = 20·2.7, D = 2.7 on the system base; G1 + G2: 52.5 + 63.
        @test g3.imbalance ≈ -surplus rtol = 1e-12
        @test rest.imbalance ≈ surplus rtol = 1e-12
        @test g3.Δω ≈ surplus / 56.7 rtol = 1e-12
        @test rest.Δω ≈ -surplus / 115.5 rtol = 1e-12
        @test g3.Δω > 0 > rest.Δω
    end

    @testset "brute force: every live piece rebuilt as its own model" begin
        # How many live pieces each grid offers — measured after the first run, a floor
        # so a screen that stops producing live pieces cannot pass by checking none. The
        # grid-following triangle has ONE: every other pair strands its only source.
        for (net, n) in ((_M10_CASE9(), 75), (_M10_MESH(), 45), (_m10_swing_case9(), 162),
                         (_m10_genmesh(), 65), (_m10_inverter_corner(:grid_forming), 5),
                         (_m10_inverter_corner(:grid_following), 1))
            @test _m10_brute_all(net) == n
        end
    end

    @testset "a dead piece carries nothing, and the pair's own branches nothing" begin
        # The docstring's promise, held on every pair of every fixture: the brute force
        # reads live pieces only, so without this a dead piece's branches could keep
        # their base flows and pass. (No fixture has a live piece that fails to settle,
        # so the `NaN` half is not reached here.)
        checked = 0
        for net in (_M10_CASE9(), _M10_MESH(), _m10_swing_case9(), _m10_genmesh(),
                    _m10_inverter_corner(:grid_forming), _m10_inverter_corner(:grid_following))
            s = dc_pair_outages(net)
            for p in eachindex(s.pairs)
                @test all(s.flow[p][e] === 0.0 for e in s.pairs[p] if s.kind[e] === :branch)
                for pc in s.pieces[p]
                    pc.kind === :live && continue
                    for (e, br) in pairs(net.branches)
                        br.from in pc.buses || continue
                        @test s.flow[p][e] === 0.0
                        checked += 1
                    end
                end
            end
        end
        @test checked > 0
    end

    @testset "a pair that is one outage is that outage (D4), within a band" begin
        # The screen sizes the rest's loss from the bridge's base flow, M8 from the
        # machine's schedule: the same number to the base solve's round-off.
        c9 = _M10_CASE9()
        s, g = dc_pair_outages(c9), dc_generator_outages(c9)
        for p in findall(!=(:none), s.same_as)
            k = findfirst(==(s.same_as[p]), g.machines)
            pc = only(_m10_live(s, p))
            @test isapprox(pc.Δω, g.Δω[k]; rtol = 1e-12)
            @test isapprox(s.pickup[p], g.pickup[k]; rtol = 1e-12, atol = 1e-15)
            band = 100eps() * maximum(abs, g.flow[k])
            @test maximum(abs.(s.flow[p] .- g.flow[k])) <= band
        end
    end

    @testset "different paths to one event give one answer" begin
        # case9: G1 and G2 both gone, four ways — two lines, a line and a machine
        # either way round, two machines. Only G3's piece is live in every one.
        c9 = _M10_CASE9()
        s = dc_pair_outages(c9)
        ps = [_m10_pair(s, a, b) for (a, b) in ((:L14, :L82), (:L14, :G2), (:L82, :G1), (:G1, :G2))]
        ref = ps[4]
        lv(p) = only(_m10_live(s, p))
        for p in ps[1:3]
            @test isapprox(lv(p).Δω, lv(ref).Δω; rtol = 1e-12)
            @test isapprox(s.pickup[p], s.pickup[ref]; rtol = 1e-12, atol = 1e-15)
            @test maximum(abs.(s.flow[p] .- s.flow[ref])) <= 100eps() * maximum(abs, s.flow[ref])
        end
        # The mesh's AB+AC cuts off A, the reference bus, with G1 alone on it: the one
        # report-grid pair whose reference's own piece dies. Its FREQUENCY is G1's single
        # outage; its flows are NOT (predicted they would be, measured wrong): with only
        # G1 gone, A stays in the mesh and carries a loop flow in on one line and out on
        # the other, and losing both lines closes that path. The brute force checks them.
        mesh = _M10_MESH()
        sm, gm = dc_pair_outages(mesh), dc_generator_outages(mesh)
        p = _m10_pair(sm, :AB, :AC)
        dead = only(pc for pc in sm.pieces[p] if pc.kind === :sources_lost)
        @test dead.buses == [:A]
        @test dead.sources_lost ≈ 1.5 rtol = 1e-14
        k = findfirst(==(:G1), gm.machines)
        @test isapprox(only(_m10_live(sm, p)).Δω, gm.Δω[k]; rtol = 1e-12)
        @test isapprox(sm.pickup[p], gm.pickup[k]; rtol = 1e-12, atol = 1e-15)
        ab, ac = findfirst(==(:AB), sm.id), findfirst(==(:AC), sm.id)
        @test abs(gm.flow[k][ab] + gm.flow[k][ac]) <= 100eps() * maximum(abs, gm.flow[k])
        @test abs(gm.flow[k][ab]) > 0.1
        @test sm.flow[p][ab] === 0.0 && sm.flow[p][ac] === 0.0
    end

    @testset "a piece with only a grid-following inverter is not live (D4)" begin
        for mode in (:grid_following, :grid_forming)
            net = _m10_inverter_corner(mode)
            s = dc_pair_outages(net)
            p = _m10_pair(s, :BC, :CA)
            corner = only(pc for pc in s.pieces[p] if pc.buses == [:C])
            @test corner.kind === (mode === :grid_following ? :load_lost : :sources_lost)
            @test corner.sources_lost ≈ 0.2 rtol = 1e-14
            @test corner.load_lost === 0.0
            # Either way the rest loses the inverter's 20 MW; G1 alone makes it up.
            rest = only(_m10_live(s, p))
            @test rest.imbalance ≈ 0.2 rtol = 1e-12
            @test s.pickup[p][1] ≈ 0.2 rtol = 1e-12
        end
    end

    @testset "load lost: the stranded load's import comes back as a surplus" begin
        # The swing fixture's L45+L56 strands B5's load-machine: a P0 < 0 machine is a
        # load, so B5 is load lost (D6.3) and the rest rises by its 90 MW.
        net = _m10_swing_case9()
        s = dc_pair_outages(net)
        p = _m10_pair(s, :L45, :L56)
        b5 = only(pc for pc in s.pieces[p] if pc.buses == [:B5])
        @test b5.kind === :load_lost
        @test b5.load_lost ≈ 0.9 rtol = 1e-14
        rest = only(_m10_live(s, p))
        @test rest.imbalance ≈ -0.9 rtol = 1e-12
        @test rest.Δω > 0
        # The report grid's own load is a `Load`: the same verdict.
        s9 = dc_pair_outages(_M10_CASE9())
        q = _m10_pair(s9, :L45, :L56)
        @test only(pc for pc in s9.pieces[q] if pc.buses == [:B5]).kind === :load_lost
    end

    @testset "the swing tier settles each piece where the screen puts it (band 1e-7, stated first)" begin
        band = 1e-7
        cases = [(_m10_swing_case9(), [(:L45, :L67), (:L45, :L56), (:L45, :L94), (:L14, :L82),
                                       (:L67, :G1), (:G1, :G2), (:L36, :G3)]),
                 (_m10_genmesh(), [(:AB, :AC), (:G2, :BC), (:G2, :LD), (:AB, :CD)])]
        for (net, list) in cases
            s = dc_pair_outages(net)
            for (a, b) in list
                p = _m10_pair(s, a, b)
                surv = _m10_survivors(net, s, p)
                @test !isempty(surv)
                for o in _m10_swing(net, _m10_events(net, s, p), (300.0, 450.0))
                    for (v, mid, pc) in surv
                        q = findfirst(==(mid), s.responders)
                        @test abs(o.ω[v] - pc.Δω) <= band
                        @test abs(o.Δexport[net.machines[q].bus] - s.pickup[p][q]) <= band
                    end
                end
            end
        end
        # The two pieces of L45+L67 really do go opposite ways in the run too.
        net = _m10_swing_case9()
        s = dc_pair_outages(net)
        o = last(_m10_swing(net, _m10_events(net, s, _m10_pair(s, :L45, :L67)), (300.0,)))
        @test o.ω[net.bus_index[:B3]] > 0 > o.ω[net.bus_index[:B1]]
    end

    @testset "order: trip, settle, trip, settle lands where both at once does (18.4)" begin
        band = 1e-7
        cases = [(_m10_genmesh(), [(:G2, :LD), (:G2, :BC), (:AB, :CD), (:G2, :G3)], true),
                 (_m10_swing_case9(), [(:L45, :L67), (:L67, :G1)], false)]
        for (net, list, genmesh) in cases
            s = dc_pair_outages(net)
            for (a, b) in list
                p = _m10_pair(s, a, b)
                evs = _m10_events(net, s, p)
                # These pairs cut nothing off, so A's and B's own events are the pair's.
                @test length(evs) == 2
                ia = findfirst(==(a), s.id) == s.pairs[p][1] ? 1 : 2
                A, B = evs[ia], evs[3 - ia]
                both = _m10_swing(net, evs, (300.0, 450.0))
                seq = _m10_swing(net, [A], (300.0, 600.0, 750.0); second = [B], t2 = 300.0)
                gone = Set(s.id[e] for e in s.pairs[p])
                for (o1, o2) in zip(both, seq[2:3]), (v, mc) in pairs(net.machines)
                    mc.id in gone && continue
                    @test abs(o1.ω[v] - o2.ω[v]) <= band
                    @test abs(o1.Δexport[mc.bus] - o2.Δexport[mc.bus]) <= band
                end
                if genmesh && a === :G2
                    # The positive control: after G2 alone, G3's governor sits at its
                    # 0.05 pu headroom — the cap binds between the two losses.
                    @test abs(seq[1].ΔPm[5] - 0.05) <= 1e-9
                end
            end
        end
        # G2 then LD: the cap binds after G2 and lets go after LD (the surplus), so a
        # path dependence would show here if anywhere.
        net = _m10_genmesh()
        s = dc_pair_outages(net)
        p = _m10_pair(s, :G2, :LD)
        @test only(s.pieces[p]).imbalance < 0 && !any(s.capped[p])
    end

    @testset "an inverter model is read through the base case" begin
        # M7's exported-surface walk calls this on an inverter model.
        net = _m10_inverter_corner(:grid_forming)
        s = dc_pair_outages(net)
        @test s.responders == [:G1, :I3]
        @test all(pc.outcome === :shared for ps in s.pieces for pc in ps if pc.kind === :live)
    end
end
