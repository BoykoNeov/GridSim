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

# ─────────────────────────────────────────────────────────────────────────────
# M10 step 3: every pair in AC, a split grid answered piece by piece (`ac_pair_outages`).
# Predictions and bands were written first: `docs/evidence/gridsim-m10/step3_predictions.md`.
#
# B = 1e-10, solution against solution (M8 step 5's B1), on Δω, pickups, |V| by bus id and
# flows by branch id — never angles: the compared solves hold different references.
# ─────────────────────────────────────────────────────────────────────────────

const _M10_B = 1e-10

_m10_grid(f, loads) = f(; loads)
_m10_ac_live(s::ACPairOutages, p::Int) = [pc for pc in s.pieces[p] if pc.kind === :live]

# The pair's index by element ids, in either order (`_m10_pair` for the AC screen).
function _m10_pair(s::ACPairOutages, a::Symbol, b::Symbol)
    i, j = findfirst(==(a), s.id), findfirst(==(b), s.id)
    return findfirst(==((min(i, j), max(i, j))), s.pairs)
end

# Two AC answers to one event, within B: Δω, every pickup, |V| at every bus of `a` and
# both ends' P and Q on every branch of `a`, each read BY ID in `b`. A branch only `b`
# has must carry nothing (an open bridge to an empty bus).
function _m10_same_ac(a::ACPowerFlow, aΔω, apk, b::ACPowerFlow, bΔω, bpk)
    B = _M10_B
    @test abs(aΔω - bΔω) <= B
    @test maximum(abs, apk .- bpk) <= B
    @test all(bus in b.buses for bus in a.buses)
    for (v, bus) in pairs(a.buses)
        @test abs(a.Vm[v] - b.Vm[findfirst(==(bus), b.buses)]) <= B
    end
    for (e, br) in pairs(a.branches)
        j = findfirst(==(br), b.branches)
        @test abs(a.flow[e] - b.flow[j]) <= B && abs(a.flow_rev[e] - b.flow_rev[j]) <= B
        @test abs(a.qflow[e] - b.qflow[j]) <= B && abs(a.qflow_rev[e] - b.qflow_rev[j]) <= B
    end
    for (j, br) in pairs(b.branches)
        br in a.branches && continue
        @test abs(b.flow[j]) <= B && abs(b.qflow[j]) <= B
    end
end

# The same comparison on whatever both answers carry, whether or not they solved: the
# outcome, Δω (both `NaN` when neither settled), every pickup, every out-of-band bus `a`
# names — each read by id in `b`, which may name more (a cut-off empty bus, sitting at
# its neighbour's voltage) — and the solutions, where there are any.
function _m10_same_answer(apc::ACPiece, apk, b_outcome, bΔω, bpk, blow, bsol)
    B = _M10_B
    @test apc.outcome === b_outcome
    @test (isnan(apc.Δω) && isnan(bΔω)) || abs(apc.Δω - bΔω) <= B
    @test maximum(abs, apk .- bpk) <= B
    for l in apc.low
        j = findfirst(m -> m.bus === l.bus, blow)
        @test j !== nothing && abs(l.Vm - blow[j].Vm) <= B
    end
    (apc.solution === nothing || bsol === nothing) && return nothing
    _m10_same_ac(apc.solution, apc.Δω, apk, bsol, bΔω, bpk)
end

# The responders of a piece, by position in `s.responders`: machines on its buses that
# the pair did not take, and its grid-forming inverters.
function _m10_piece_responders(net::NetworkModel, s::ACPairOutages, p::Int, pc::ACPiece)
    gone = Set(s.id[e] for e in s.pairs[p])
    rb = GridSim._responders(net).bus
    return [q for q in eachindex(s.responders)
            if net.buses[rb[q]].id in pc.buses && !(s.responders[q] in gone)]
end

# The per-piece losses identity (step3_predictions.md), every term read off the base
# solution, the piece's solution and the model — never off the screen's setup:
#   Σ pickups = lost base output + Δ load draw + Δ internal losses − base export across the cut,
# the export read at THIS piece's end of each cut branch. Returns (dload, dloss).
function _m10_identity(net::NetworkModel, s::ACPairOutages, p::Int, pc::ACPiece)
    b, sol = s.base, pc.solution
    nb = length(net.branches)
    inp(bus) = bus in pc.buses
    vb(bus) = findfirst(==(bus), b.buses)
    lostP = 0.0
    for e in s.pairs[p]
        e > nb || continue
        mc = net.machines[e - nb]
        inp(mc.bus) || continue
        # What it produced: its schedule, or the slack's solved output (no grid-following
        # inverter sits on a report grid's slack).
        lostP += mc.bus === net.slack ? b.Pgen[vb(mc.bus)] : mc.P0 / net.S_base
    end
    dload = sum(sol.Pload) - sum(b.Pload[vb(bus)] for bus in pc.buses)
    loss_b, exp_b = 0.0, 0.0
    for (e, br) in pairs(net.branches)
        f, t = inp(br.from), inp(br.to)
        f && t && (loss_b += b.loss[e])
        f && !t && (exp_b += b.flow[e])
        t && !f && (exp_b += b.flow_rev[e])
    end
    dloss = sum(sol.loss; init = 0.0) - loss_b
    Σpk = sum(s.pickup[p][q] for q in _m10_piece_responders(net, s, p, pc); init = 0.0)
    bound = length(pc.buses) * (max(b.residual, eps()) + max(sol.residual, eps()))
    @test abs(Σpk - lostP - dload - dloss + exp_b) <= bound
    return (dload, dloss)
end

# M8's ladder rungs, copied (the focused runner does not load M8's test file): lossless;
# every machine at V_set = 1; a zero-power, governor-free, undamped machine holding
# 1 pu on every bus without a source.
_m10_lossless(net::NetworkModel) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net.branches], net.machines,
    net.loads; slack = net.slack, inverters = net.inverters)
function _m10_A0(net::NetworkModel)
    l = _m10_lossless(net)
    src = Set(m.bus for m in l.machines)
    ms = [[GridSim._machine_with(m; V_set = 1.0) for m in l.machines];
          [Machine(Symbol(:H_, b.id), b.id, 100.0, 5.0, 0.0, 0.2, 1.0, 0.0)
           for b in l.buses if !(b.id in src)]]
    return NetworkModel(l.S_base, l.f0, l.buses, l.branches, ms, l.loads; slack = l.slack,
                        inverters = l.inverters)
end

@testset "M10 step 3 — every pair in AC, a split grid piece by piece" begin

    @testset "the pairs and pieces are step 2's; dead pieces are read from the AC base" begin
        for f in (_M10_CASE9, _M10_MESH), loads in (:constant_power, :default)
            net = _m10_grid(f, loads)
            dc, ac = dc_pair_outages(net), ac_pair_outages(net)
            @test ac.id == dc.id && ac.pairs == dc.pairs && ac.same_as == dc.same_as
            @test ac.splits == dc.splits && ac.responders == dc.responders
            for p in eachindex(dc.pairs)
                @test [(pc.buses, pc.kind) for pc in ac.pieces[p]] ==
                      [(pc.buses, pc.kind) for pc in dc.pieces[p]]
            end
        end
        # case9's slack machine cut off alone (L14 with any ring line): what it takes with
        # it is its SOLVED base output — the schedule plus the base losses it carried.
        net = _m10_grid(_M10_CASE9, :constant_power)
        dc, ac = dc_pair_outages(net), ac_pair_outages(net)
        p = _m10_pair(ac, :L14, :L45)
        a1 = only(pc for pc in ac.pieces[p] if pc.buses == [:B1])
        d1 = only(pc for pc in dc.pieces[p] if pc.buses == [:B1])
        @test a1.kind === :sources_lost && a1.sources_lost === ac.base.Pgen[1]
        @test a1.sources_lost - d1.sources_lost > 1e-3       # the base losses
        @test a1.solution === nothing && isnan(a1.Δω)
    end

    @testset "every live piece's solution holds its own buses and in-service branches only" begin
        for f in (_M10_CASE9, _M10_MESH), loads in (:constant_power, :default)
            net = _m10_grid(f, loads)
            s = ac_pair_outages(net)
            for p in eachindex(s.pairs), pc in _m10_ac_live(s, p)
                gone = Set(s.id[e] for e in s.pairs[p])
                # An outaged branch is never judged against a rating.
                @test !any(d -> d.id in gone, pc.over)
                pc.solution === nothing && continue
                sol = pc.solution
                @test sol.buses == pc.buses
                @test sol.branches == [br.id for br in net.branches
                                       if br.from in pc.buses && br.to in pc.buses && !(br.id in gone)]
                @test sol.slack === (net.slack in pc.buses ? net.slack : pc.buses[1])
                @test sol.θ[findfirst(==(sol.slack), sol.buses)] == 0.0
            end
        end
    end

    @testset "a pair that is one outage (D4) is M8's single AC outage, within B" begin
        for loads in (:constant_power, :default)
            net = _m10_grid(_M10_CASE9, loads)
            s, g = ac_pair_outages(net), ac_generator_outages(net)
            ps = findall(!=(:none), s.same_as)
            @test length(ps) == 3
            for p in ps
                k = findfirst(==(s.same_as[p]), g.machines)
                pc = only(_m10_ac_live(s, p))
                _m10_same_answer(pc, s.pickup[p], g.outcome[k], g.Δω[k], g.pickup[k], g.low[k],
                                 g.solution[k])
            end
        end
    end

    @testset "four paths to G1 and G2 gone give one answer, within B" begin
        # Measured after the first run, not predicted: no path solves. On constant-power
        # loads G3 alone cannot hold the voltage and every Newton solve fails; on the
        # default loads the load falls with the voltage and all four solve outside the
        # band, to one Δω. So the comparison is on the answer each gives, solved or not.
        for (loads, want) in ((:constant_power, :no_solution), (:default, :voltage))
            net = _m10_grid(_M10_CASE9, loads)
            s = ac_pair_outages(net)
            ps = [_m10_pair(s, a, b) for (a, b) in ((:L14, :L82), (:L14, :G2), (:L82, :G1), (:G1, :G2))]
            ref = only(_m10_ac_live(s, ps[4]))
            @test length(ref.buses) == 9 && ref.outcome === want
            loads === :default && @test ref.Δω < 0 && length(ref.low) == 7
            for p in ps[1:3]
                pc = only(_m10_ac_live(s, p))
                _m10_same_answer(pc, s.pickup[p], ref.outcome, ref.Δω, s.pickup[ps[4]], ref.low,
                                 ref.solution)
            end
            # A cut-off empty bus sits at its neighbour's voltage (M8 D9's premise).
            V(bus) = (j = findfirst(l -> l.bus === bus, ref.low); j === nothing ? NaN : ref.low[j].Vm)
            loads === :default && @test abs(V(:B1) - V(:B4)) <= _M10_B && abs(V(:B2) - V(:B8)) <= _M10_B
        end
    end

    @testset "the mesh's AB+AC is NOT G1's outage in AC, even in frequency" begin
        # Step 2 found them equal in DC frequency and different only in flows (a loop flow
        # through A). In AC they differ in frequency too — predicted. The prediction gave
        # the reason as the loop flow's own losses, and had the SIGN wrong: A is a parallel
        # path, so keeping it LOWERS the total losses (measured 0.0270 against 0.0341 pu on
        # constant power). Which way Δω then moves depends on the load model, measured:
        # constant power, the pair settles lower (more loss to pick up); default loads, the
        # pair settles HIGHER, because its lower voltages cut the load draw by more than the
        # losses rise.
        for loads in (:constant_power, :default)
            net = _m10_grid(_M10_MESH, loads)
            s, g = ac_pair_outages(net), ac_generator_outages(net)
            pc = only(_m10_ac_live(s, _m10_pair(s, :AB, :AC)))
            k = findfirst(==(:G1), g.machines)
            @test pc.outcome === g.outcome[k] === :secure
            @test abs(pc.Δω - g.Δω[k]) > 1e3 * _M10_B
            a, b = pc.solution, g.solution[k]
            @test sum(a.loss) > sum(b.loss)
            if loads === :constant_power
                @test pc.Δω < g.Δω[k]
            else
                @test pc.Δω > g.Δω[k]
                @test sum(b.Pload) - sum(a.Pload) > sum(a.loss) - sum(b.loss)
            end
        end
    end

    @testset "pickups = lost output + load shift + loss change − export across the cut, per piece" begin
        moved_load = moved_loss = checked = 0
        for f in (_M10_CASE9, _M10_MESH), loads in (:constant_power, :default)
            net = _m10_grid(f, loads)
            s = ac_pair_outages(net)
            for p in eachindex(s.pairs), pc in _m10_ac_live(s, p)
                (isfinite(pc.Δω) && pc.solution !== nothing) || continue
                dload, dloss = _m10_identity(net, s, p, pc)
                loads === :constant_power && @test abs(dload) <= 1e-14
                moved_load += abs(dload) > 1e-3
                moved_loss += abs(dloss) > 1e-3
                checked += 1
            end
        end
        @test checked > 0 && moved_load > 0 && moved_loss > 0
    end

    @testset "lossless, constant power: every piece's Δω and pickups ARE step 2's, within B" begin
        for f in (_M10_CASE9, _M10_MESH)
            net = _m10_lossless(_m10_grid(f, :constant_power))
            dc, ac = dc_pair_outages(net), ac_pair_outages(net)
            checked = 0
            for p in eachindex(ac.pairs)
                for (a, d) in zip(ac.pieces[p], dc.pieces[p])
                    a.kind === :live || continue
                    if a.outcome in (:no_response, :reserve_exhausted)
                        @test a.outcome === d.outcome
                        continue
                    end
                    # A whole grid that lost two lines has no Δω in AC, by design.
                    isfinite(a.Δω) || continue
                    @test d.outcome === :shared
                    @test abs(a.Δω - d.Δω) <= _M10_B
                    checked += 1
                end
                any(pc -> isfinite(pc.Δω), ac.pieces[p]) &&
                    @test maximum(abs, ac.pickup[p] .- dc.pickup[p]) <= _M10_B
            end
            @test checked > 0
        end
    end

    @testset "every bus at 1 pu, lossless: a tree piece's flows ARE step 2's, a meshed one's are not" begin
        for f in (_M10_CASE9, _M10_MESH)
            net = _m10_A0(_m10_grid(f, :constant_power))
            dc, ac = dc_pair_outages(net), ac_pair_outages(net)
            trees = loops = 0
            for p in eachindex(ac.pairs), pc in _m10_ac_live(ac, p)
                pc.solution === nothing && continue
                sol = pc.solution
                gap = maximum((abs(sol.flow[e] - dc.flow[p][findfirst(==(br), dc.id)])
                               for (e, br) in pairs(sol.branches)); init = 0.0)
                if length(sol.branches) == length(sol.buses) - 1
                    @test gap <= _M10_B
                    trees += 1
                else
                    loops += gap > 1e3 * _M10_B
                end
            end
            # The mesh has no tree piece: any two of its seven lines leave a loop.
            @test loops > 0
            f === _M10_CASE9 && @test trees > 0
        end
        # The helpers make case9's three stranded loads live pieces with nothing that
        # responds — at both fidelities.
        net = _m10_A0(_m10_grid(_M10_CASE9, :constant_power))
        dc, ac = dc_pair_outages(net), ac_pair_outages(net)
        for (a, b, bus) in ((:L45, :L56, :B5), (:L67, :L78, :B7), (:L89, :L94, :B9))
            p = _m10_pair(ac, a, b)
            pa = only(pc for pc in ac.pieces[p] if pc.buses == [bus])
            pd = only(pc for pc in dc.pieces[p] if pc.buses == [bus])
            @test pa.kind === pd.kind === :live
            @test pa.outcome === pd.outcome === :no_response
        end
    end

    @testset "DC against AC per pair, by id" begin
        for loads in (:constant_power, :default)
            net = _m10_grid(_M10_CASE9, loads)
            dc, ac = dc_pair_outages(net), ac_pair_outages(net)
            cmp = compare_pair_screens(net, dc, ac)
            @test length(cmp.class) == 66
            @test all(c -> c in (:refused, :refusals_differ, :dc_blind, :agree, :dc_missed,
                                 :dc_false_alarm, :mixed), cmp.class)
            # A collapsed pair classifies as its machine's single outage does.
            gc = compare_generator_screens(net, dc_generator_outages(net), ac_generator_outages(net))
            for p in findall(!=(:none), ac.same_as)
                @test cmp.class[p] === gc.class[findfirst(==(ac.same_as[p]), gc.machines)]
            end
            # Where AC solved every live piece and DC settled, the miss is read by id; the
            # pair's own branches read zero in both.
            for p in eachindex(cmp.pairs)
                isempty(cmp.reactive[p]) && continue
                @test all(>=(-1e-12), cmp.reactive[p])
                @test all(cmp.reactive[p][e] === 0.0 for e in ac.pairs[p] if ac.kind[e] === :branch)
            end
        end
        net = _m10_grid(_M10_MESH, :constant_power)
        @test_throws ArgumentError compare_pair_screens(net, dc_pair_outages(net),
            ac_pair_outages(_m10_grid(_M10_CASE9, :constant_power)))
    end

    @testset "inverters: pieces as step 2's, and the identity on every piece that solved" begin
        # The report grids carry no inverter, so this is the only place the per-piece code's
        # inverter half runs: which inverters a piece holds, their position in it, and a
        # grid-forming one as a piece's ONLY responder, off the reference bus.
        checked = 0
        for mode in (:grid_forming, :grid_following)
            net = _m10_inverter_corner(mode)
            dc, ac = dc_pair_outages(net), ac_pair_outages(net)
            for p in eachindex(dc.pairs)
                @test [(pc.buses, pc.kind) for pc in ac.pieces[p]] ==
                      [(pc.buses, pc.kind) for pc in dc.pieces[p]]
                for pc in _m10_ac_live(ac, p)
                    (isfinite(pc.Δω) && pc.solution !== nothing) || continue
                    _m10_identity(net, ac, p, pc)
                    checked += 1
                end
            end
            p = _m10_pair(ac, :BC, :CA)
            corner = only(pc for pc in ac.pieces[p] if pc.buses == [:C])
            @test corner.kind === (mode === :grid_following ? :load_lost : :sources_lost)
            @test corner.sources_lost ≈ 0.2 rtol = 1e-14
            mode === :grid_forming || continue
            # AB+CA leaves {B, C}: the load and the grid-forming inverter alone, the model's
            # slack cut off with G1. The inverter carries the whole load.
            bc = only(_m10_ac_live(ac, _m10_pair(ac, :AB, :CA)))
            @test bc.buses == [:B, :C] && bc.solution !== nothing && bc.solution.slack === :B
            i3 = findfirst(==(:I3), ac.responders)
            @test ac.pickup[_m10_pair(ac, :AB, :CA)][i3] > 0.5
        end
        @test checked > 0
    end

    @testset "the base is refused as ac_generator_outages refuses it" begin
        m0 = _M10_MESH()
        two = NetworkModel(m0.S_base, m0.f0, m0.buses, m0.branches,
            [m0.machines; Machine(:G4, :A, 50.0, 3.0, 1.0, 0.25, 1.0, 0.0; V_set = 1.05)], m0.loads;
            slack = m0.slack)
        msg = try; ac_pair_outages(two); ""; catch e; e.msg; end
        @test startswith(msg, "ac_pair_outages: the slack bus :A carries 2 sources")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# M10 step 4: one event, one re-solve (Hurdle 20) — `TripElements` in the detailed tier,
# and in the swing tier. Predictions and bands were written BEFORE these ran
# (`docs/evidence/gridsim-m10/step4_predictions.md`); what the spike measured first is
# `m10-context.md` D10.
#
# The oracle is M9's losses identity TAKEN PER PIECE, with the load-draw term carried so
# that the default loads can serve too (on constant power one two-piece pair survives the
# trip instant in this tier, L56+L78 — D10):
#     ω_dyn − Δω_AC = −[(L_dyn + D_dyn) − (L_AC + D_AC)] / Σw_piece,
# each side's internal losses `L` and load draw `D` read from its own solution — the
# engine's both-ends branch power and the model's ZIP data at its voltages; the AC piece's
# own `ACPowerFlow`.
# ─────────────────────────────────────────────────────────────────────────────

const _M10_FBDF = OrdinaryDiffEq.FBDF

# The detailed tier on `net`, from its AC base, at reltol `tol` (abstol 100× tighter).
_m10_de(net::NetworkModel; base = ac_powerflow(net), tol = 1e-8, solver = _M10_FBDF()) =
    init!(DetailedEngine, net; powerflow = base, reltol = tol, abstol = tol / 100, solver)

# A `TripElements` of case9's lines, by id.
_m10_trip(net::NetworkModel, ids::Symbol...) =
    TripElements(lines = [(b.from, b.to) for id in ids for b in net.branches if b.id === id])

# Everything a refused event must leave as it was.
_m10_engine_state(eng::DetailedEngine) =
    (copy(eng.params), copy(eng.p_static), copy(eng.u_static), copy(eng.integrator.u),
     sort!(collect(eng.lines_online)), sort!(collect(eng.online)), copy(eng.w), eng.Σw,
     event_log(eng), copy(eng.deenergised), eng.integrator.t)

# The out-of-step relay fixture of `m5_detailed.jl` (governed ring, relay on B1–B2), with
# G1 ramped UP so that L12's trip pushes more power over L31 (`step4_relay_probe.jl`: L31
# carries 63.4 MVA at the start and 105.8 just after the trip) and L31 rated `r31` MVA.
_m10_relay_ring(r31) = let g = governed_ring()
    NetworkModel(g.S_base, g.f0, g.buses,
                 [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0),
                  Branch(:L31, :B3, :B1, 0.25, r31)], g.machines)
end
_m10_relay_de(net) = init!(DetailedEngine, net; dt = 0.01,
    ramp = [:G1 => GenerationRamp(2.0 / 3.0, 1.0, 3.0)], reltol = 1e-8, abstol = 1e-10,
    maxiters = 10_000_000, out_of_step = [(:B1, :B2) => OutOfStepTrip(0.20; label = :oos)])

# One live piece of a settled run, against its AC answer: `(lhs, rhs, rhs_Σw, rhs_L, ω)`.
# `rhs_Σw` divides by the WHOLE grid's Σw, `rhs_L` charges the whole grid's losses — the
# two ways of not taking the identity per piece, kept for the anti-vacuity checks.
function _m10_piece_identity(eng::DetailedEngine, net::NetworkModel, pc::ACPiece)
    inp(bus) = bus in pc.buses
    ma, st = machine_arrays(net), current_state(eng)
    ks = [k for (k, m) in pairs(net.machines) if inp(m.bus) && is_online(eng, m.id)]
    ωs = st.ω[ks]
    @test maximum(ωs) - minimum(ωs) <= 1e-10          # one piece, one frequency
    for k in ks                                         # no governor at its cap
        @test st.ΔPm[k] < ma.headroom[k] - 1e-6
    end
    ω = sum(ωs) / length(ωs)
    Σw = sum(ma.invR[k] + ma.D[k] for k in ks)
    Σw_all = sum(ma.invR[k] + ma.D[k] for (k, m) in pairs(net.machines) if is_online(eng, m.id))
    both(b) = branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
    L = sum(both(b) for b in net.branches if inp(b.from) && inp(b.to) &&
                                             is_online(eng, b.from, b.to); init = 0.0)
    L_all = sum(both(b) for b in net.branches if is_online(eng, b.from, b.to))
    # The draw, from the MODEL's ZIP data at the engine's voltages — not the engine's own
    # load slot: P·(a_z|V|² + a_i|V| + a_p).
    D = sum(l.P0 / net.S_base * (l.a_z * st.V[net.bus_index[l.bus]]^2 +
                                 l.a_i * st.V[net.bus_index[l.bus]] + l.a_p)
            for l in net.loads if inp(l.bus); init = 0.0)
    ac = sum(pc.solution.loss) + sum(pc.solution.Pload)
    lhs = ω - pc.Δω
    return (; lhs, rhs = -(L + D - ac) / Σw, rhs_Σw = -(L + D - ac) / Σw_all,
              rhs_L = -(L_all + D - ac) / Σw, ω)
end

@testset "M10 step 4 — one event, one re-solve" begin

    @testset "TripElements refuses what is not one event" begin
        @test_throws ArgumentError TripElements()
        @test_throws ArgumentError TripElements(lines = [(:B4, :B4)])
        @test_throws ArgumentError TripElements(lines = [(:B4, :B5), (:B5, :B4)])
        @test_throws ArgumentError TripElements(sources = [:G1, :G1])
        ev = TripElements(lines = [(:B4, :B5)], sources = ["G3"])
        @test ev.lines == [(:B4, :B5)] && ev.sources == [:G3]
        @test describe_event(EngineEvent(1.0, :deenergise, :B5, Symbol(""))) == "de-energise B5"
    end

    @testset "positive control: refused as two trips, runs as one (default loads, L45+L67)" begin
        net = _M10_CASE9(loads = :default)
        eng = _m10_de(net)
        solve!(eng, (0.0, 1.0); saveat = 0.05)
        # Step 0's refusal, through the single trip: L45 alone sags B5 below the band…
        msg = try inject!(eng, TripLine(:B4, :B5)); "" catch e; e.msg end
        @test occursin("bus B5 solved to |V| = 0.89", msg)
        # …and since M10 a refused trip leaves the line in service, nothing logged.
        @test is_online(eng, :B4, :B5) && n_events(eng) == 0
        inject!(eng, _m10_trip(net, :L45, :L67))
        @test [(e.kind, e.a, e.b) for e in event_log(eng)] ==
              [(:trip_line, :B4, :B5), (:trip_line, :B6, :B7)]
        @test !is_online(eng, :B4, :B5) && !is_online(eng, :B6, :B7)
        @test isempty(deenergised_buses(eng))
        solve!(eng, (1.0, 30.0); saveat = 0.05)
        ω = current_state(eng).ω
        @test ω[3] > 0 > ω[1] && ω[2] < 0          # G3's piece up, the rest down (D1)
    end

    @testset "a refused event changes nothing: the run on is its never-asked twin, bit for bit" begin
        cases = [(_M10_CASE9(loads = :default), TripLine(:B4, :B5)),
                 (_M10_CASE9(loads = :constant_power), _m10_trip(_M10_CASE9(), :L45, :L67)),
                 (_M10_CASE9(loads = :constant_power), TripGenerator(:G1))]
        for (net, ev) in cases
            a, b = _m10_de(net), _m10_de(net)
            solve!(a, (0.0, 1.0); saveat = 0.05)
            solve!(b, (0.0, 1.0); saveat = 0.05)
            before = _m10_engine_state(b)
            err = try inject!(b, ev); nothing catch e; e end
            @test err isa ErrorException && occursin("outside [0.9, 1.1]", err.msg)
            @test isequal(_m10_engine_state(b), before)
            solve!(a, (1.0, 6.0); saveat = 0.05)
            solve!(b, (1.0, 6.0); saveat = 0.05)
            @test isequal(state_series(a), state_series(b))
            @test isequal(_m10_engine_state(a), _m10_engine_state(b))
        end
    end

    @testset "the out-of-step relay's refused trip: nothing done, and the run stops" begin
        # Positive control: rated 500 MVA, the relay opens L12 and the run goes on.
        ok = _m10_relay_de(_m10_relay_ring(500.0))
        solve!(ok, (0.0, 6.0))
        @test out_of_step_log(out_of_step_relay(ok, :B1, :B2)).tripped
        @test !out_of_step_relay(ok, :B1, :B2).armed       # its own trip latched it
        @test !is_online(ok, :B1, :B2) && n_events(ok) == 1
        # L31 rated 85 MVA: the re-solve after L12's trip refuses it (105.8 MVA).
        eng = _m10_relay_de(_m10_relay_ring(85.0))
        p0, ps0 = copy(eng.params), copy(eng.p_static)
        err = try solve!(eng, (0.0, 6.0)); nothing catch e; e end
        @test err isa ErrorException && occursin("branch L31 carries", err.msg)
        @test is_online(eng, :B1, :B2) && n_events(eng) == 0
        @test eng.params == p0 && eng.p_static == ps0      # status back at 1.0, both networks
        lg = out_of_step_log(out_of_step_relay(eng, :B1, :B2))
        @test !lg.tripped && lg.armed && isnan(lg.t)       # the relay did not operate
        # The integrator stopped mid-step at the root it found; the run cannot go on.
        @test occursin("cannot go on", try solve!(eng, (eng.integrator.t, 6.0)); "" catch e; e.msg end)
        @test occursin("cannot go on", try inject!(eng, TripLine(:B2, :B3)); "" catch e; e.msg end)
        @test occursin("cannot go on", try inject!(eng, TripGenerator(:G2)); "" catch e; e.msg end)
        @test occursin("cannot go on",
                       try inject!(eng, TripElements(sources = [:G2])); "" catch e; e.msg end)
    end

    @testset "a user's TripLine latches the relay on its line; a refused one does not" begin
        # Asked in the reverse bus order, before the ramp: the line opens, the relay is
        # latched without firing, and the log names the line in the model's order. Left
        # armed, it would read the angle across the open line (≈ 2.3 rad by t = 6 against
        # its 0.20) and claim a protection operation that opened nothing.
        eng = _m10_relay_de(_m10_relay_ring(500.0))
        solve!(eng, (0.0, 0.5))
        inject!(eng, TripLine(:B2, :B1))
        solve!(eng, (0.5, 6.0))
        lg = out_of_step_log(out_of_step_relay(eng, :B1, :B2))
        @test !lg.tripped && !lg.armed && isnan(lg.t)
        @test [(e.kind, e.a, e.b) for e in event_log(eng)] == [(:trip_line, :B1, :B2)]
        # During the ramp with L31 rated 85 MVA, the same trip is refused (L31 would carry
        # 87.1 MVA): the latch goes back with the line, and the relay still operates later.
        eng = _m10_relay_de(_m10_relay_ring(85.0))
        solve!(eng, (0.0, 1.5))
        err = try inject!(eng, TripLine(:B2, :B1)); nothing catch e; e end
        @test err isa ErrorException && occursin("branch L31 carries", err.msg)
        lg = out_of_step_log(out_of_step_relay(eng, :B1, :B2))
        @test is_online(eng, :B1, :B2) && n_events(eng) == 0
        @test !lg.tripped && lg.armed
        err = try solve!(eng, (1.5, 6.0)); nothing catch e; e end   # it fires, and is refused
        @test err isa ErrorException && occursin("105.7", err.msg)
    end

    @testset "a dead piece is switched off, not solved (L45+L56, both load models)" begin
        for loads in (:constant_power, :default)
            net = _M10_CASE9(; loads)
            eng = _m10_de(net; solver = OrdinaryDiffEq.Rodas5P())   # a grounded bus: D10
            solve!(eng, (0.0, 1.0); saveat = 0.05)
            inject!(eng, _m10_trip(net, :L45, :L56))
            @test deenergised_buses(eng) == [:B5]
            @test [(e.kind, e.a) for e in event_log(eng)] ==
                  [(:trip_line, :B4), (:trip_line, :B5), (:deenergise, :B5)]
            ser = solve!(eng, (1.0, 30.0); saveat = 0.05)
            @test all(==(0.0), ser.V_B5[ser.t .> 1.0])          # exactly zero, throughout
            @test all(v -> 0.9 < v < 1.1, current_state(eng).V[[1:4; 6:9]])
            # What went: B5's load, 90 MW in the model. Its loss as the rest of the grid
            # sees it is the identity testset's (L45+L56): every machine RISES.
            @test only(l.P0 for l in net.loads if l.bus === :B5) == 90.0
            @test all(>(0), current_state(eng).ω)
        end
    end

    @testset "a generator cut off alone is tripped in the same event (19.4): it IS its outage" begin
        net = _M10_CASE9(loads = :constant_power)
        base = ac_powerflow(net)
        # Rodas5P: FBDF's step collapses, isolated, where a bus is grounded (D10).
        a, b = (_m10_de(net; base, tol = 1e-10, solver = OrdinaryDiffEq.Rodas5P()) for _ in 1:2)
        solve!(a, (0.0, 1.0); saveat = 0.5)
        solve!(b, (0.0, 1.0); saveat = 0.5)
        inject!(a, _m10_trip(net, :L36))
        inject!(b, TripGenerator(:G3))
        @test [(e.kind, e.a) for e in event_log(a)] ==
              [(:trip_line, :B3), (:trip_generator, :G3), (:deenergise, :B3)]
        @test !is_online(a, :G3) && deenergised_buses(a) == [:B3]
        solve!(a, (1.0, 400.0); saveat = 0.5)
        solve!(b, (1.0, 400.0); saveat = 0.5)
        sa, sb = current_state(a), current_state(b)
        @test maximum(abs, sa.ω[1:2] .- sb.ω[1:2]) <= 1e-9
        @test maximum(abs, sa.V[[1:2; 4:9]] .- sb.V[[1:2; 4:9]]) <= 1e-9
        @test sa.V[3] == 0.0 && sb.V[3] > 0.9               # B3 grounded, or floating at B6
        @test sa.ω[1] < -1e-3                               # the loss is real
    end

    @testset "per piece, the settled run IS step 3's AC piece, through the losses identity" begin
        cases = [(:constant_power, :L56, :L78), (:constant_power, :L45, :L56),
                 (:default, :L45, :L67), (:default, :L56, :L78), (:default, :L67, :L89),
                 (:default, :L45, :L56)]
        nchecked, updown = 0, 0
        for (loads, x, y) in cases
            net = _M10_CASE9(; loads)
            s = ac_pair_outages(net)
            p = _m10_pair(s, x, y)
            live = _m10_ac_live(s, p)
            # The precondition: every live piece secure, no governor capped (M9's).
            @test all(pc -> pc.outcome === :secure, live) && !any(s.capped[p])
            # Rodas5P, not FBDF: FBDF's step size collapses, isolated, on the two cases with
            # a de-energised bus — constant power at 1e-10 (t = 367.66 s, or 228.73 s with the
            # run split differently), default loads at 1e-9 but not at 1e-10 — where Rodas5P
            # completes all six (`step4_settle_probe.jl`, m10-context.md D10).
            eng = _m10_de(net; base = s.base, tol = 1e-10, solver = OrdinaryDiffEq.Rodas5P())
            solve!(eng, (0.0, 1.0); saveat = 0.5)
            inject!(eng, _m10_trip(net, x, y))
            solve!(eng, (1.0, 300.0); saveat = 0.5)
            ω300 = [_m10_piece_identity(eng, net, pc).ω for pc in live]
            solve!(eng, (300.0, 400.0); saveat = 0.5)
            ωs = Float64[]
            for (i, pc) in pairs(live)
                r = _m10_piece_identity(eng, net, pc)
                @test abs(r.ω - ω300[i]) <= 1e-10                  # settled
                @test r.lhs ≈ r.rhs rtol = 1e-6
                @test abs(r.lhs) > 1e3 * abs(r.lhs - r.rhs)        # not 0 ≈ 0
                if length(live) == 2                               # per piece, or not at all
                    @test abs(r.lhs - r.rhs_Σw) > 1e3 * abs(r.lhs - r.rhs)
                    @test abs(r.lhs - r.rhs_L) > 1e3 * abs(r.lhs - r.rhs)
                end
                push!(ωs, r.ω)
                nchecked += 1
            end
            length(ωs) == 2 && (updown += prod(sign, ωs) < 0)
        end
        @test nchecked == 10            # four two-piece splits, and two dead pieces' rest
        @test updown == 4               # every two-piece split: one piece up, one down
    end

    @testset "inverters: a tripped grid-forming one is no source, a grid-following one goes with its piece" begin
        # Step 2's corner triangle with a 10 MW load added at A, so that cutting {B, C} off
        # leaves A live. The report grids carry no inverter; only this reaches the event's
        # inverter half (`step4_predictions.md`, the review addendum).
        corner(mode) = let c = _m10_inverter_corner(mode)
            NetworkModel(c.S_base, c.f0, c.buses, c.branches,
                [Machine(:G1, :A, 200.0, 5.0, 1.0, 0.25, 1.0, 70.0, 0.05, 200.0)],
                [c.loads; Load(:LA, :A, 10.0, 0.0, 0.0, 0.0, 1.0)];
                slack = :A, inverters = c.inverters)
        end
        cut = TripElements(lines = [(:A, :B), (:C, :A)])
        # Grid-forming: tripped first, so {B, C} holds load and no live source.
        net = corner(:grid_forming)
        eng = _m10_de(net; solver = OrdinaryDiffEq.Rodas5P())
        inject!(eng, TripGenerator(:I3))
        inject!(eng, cut)
        @test deenergised_buses(eng) == [:B, :C]
        @test [(e.kind, e.a) for e in event_log(eng)] == [(:trip_generator, :I3),
              (:trip_line, :A), (:trip_line, :C), (:deenergise, :B), (:deenergise, :C)]
        solve!(eng, (0.0, 10.0); saveat = 0.5)
        @test current_state(eng).V[2:3] == [0.0, 0.0] && current_state(eng).ω[1] > 0
        # Grid-following: lost with its piece, in the same event.
        net = corner(:grid_following)
        eng = _m10_de(net; solver = OrdinaryDiffEq.Rodas5P())
        inject!(eng, cut)
        @test !is_online(eng, :I3) && deenergised_buses(eng) == [:B, :C]
        @test [(e.kind, e.a) for e in event_log(eng)] == [(:trip_line, :A), (:trip_line, :C),
              (:trip_generator, :I3), (:deenergise, :B), (:deenergise, :C)]
        solve!(eng, (0.0, 10.0); saveat = 0.5)
        # Zero to the last subnormal, not to the bit: with the PLL's states on the grounded
        # buses the integrated voltages sit at 5e-324 (measured; case9's passive B5 and the
        # grid-forming case above hold an exact 0.0).
        @test maximum(abs, current_state(eng).V[2:3]) <= 1e-300
    end

    @testset "names, refusals, and elements already out" begin
        net = _M10_CASE9(loads = :default)
        eng = _m10_de(net)
        st = _m10_engine_state(eng)
        @test_throws KeyError inject!(eng, TripElements(sources = [:G9]))
        @test_throws ArgumentError inject!(eng, TripElements(lines = [(:B1, :B9)]))
        msg = try inject!(eng, TripElements(sources = [:G1, :G2, :G3])); "" catch e; e.msg end
        @test occursin("no piece of the grid", msg)
        @test isequal(_m10_engine_state(eng), st)
        inject!(eng, _m10_trip(net, :L45, :L56))
        n = n_events(eng)
        inject!(eng, TripElements(lines = [(:B5, :B4)]))      # already out: passed over
        @test n_events(eng) == n
    end

    @testset "the swing tier: the single trips at one instant, and the graph's lost machines" begin
        # This tier re-solves nothing at an event, so TripElements runs the single trips
        # — step 2's hand-written list (`_m10_events`) is what it must be, to the bit.
        net = _m10_swing_case9()
        s = dc_pair_outages(net)
        for (x, y) in ((:L45, :L67), (:L14, :L82), (:L36, :L67))
            p = _m10_pair(s, x, y)
            e1 = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
            e2 = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
            foreach(ev -> inject!(e1, ev), _m10_events(net, s, p))
            inject!(e2, _m10_trip(net, x, y))
            for e in (e1, e2)
                while e.integrator.t < 20.0 - 1e-9
                    step!(e, 0.05)
                end
            end
            @test isequal(state_series(e1), state_series(e2))
            @test event_log(e1) == event_log(e2)
        end
        # …a stranded load-machine (19.3) goes too: it is load lost, not a source.
        e = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
        inject!(e, _m10_trip(net, :L45, :L56))
        @test !is_online(e, only(m.id for m in net.machines if m.bus === :B5 && m.P0 < 0))
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# M10 step 5: fail, restore 50 Hz, fail again (`dc_restore`, `ac_restore`, and the two
# sequential screens). Predictions and bands were written first:
# `docs/evidence/gridsim-m10/step5_predictions.md`.
#
# The checks read the RESTORED MODEL and the equipment list, never the restore's own
# arithmetic: a restored piece balances, its shares follow the governor gains, a unit at
# a limit sits on it to the bit. The second loss on the restored model is the pair
# screens' one-element case BY CONSTRUCTION (m10-context.md D11.6) — nothing here
# pretends to check that; the detailed tier run from the restored model is the
# independent check.
# ─────────────────────────────────────────────────────────────────────────────

# Two triangles A–B–C and D–E–F joined only by C–D, 40 MW crossing left to right. Losing
# C–D leaves two live pieces: the left one restores DOWN (G3 meets its Pmin), the right
# one UP (G4 meets its Pmax). Gains on the system base: G1 40, G3 20 | G2 30, G4 20; every
# machine's D/(1/R) is the same, so damping cannot be told from gain here.
_m10_tie() = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E, :F)],
    [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:BC, :B, :C, 0.12, 500.0),
     Branch(:CA, :C, :A, 0.15, 500.0), Branch(:CD, :C, :D, 0.20, 500.0),
     Branch(:DE, :D, :E, 0.10, 500.0), Branch(:EF, :E, :F, 0.12, 500.0),
     Branch(:FD, :F, :D, 0.15, 500.0)],
    [Machine(:G1, :A, 200.0, 5.0, 1.0, 0.25, 1.0, 80.0, 0.05, 150.0),
     Machine(:G3, :C, 100.0, 4.0, 1.0, 0.25, 1.0, 30.0, 0.05, 60.0; Pmin = 20.0),
     Machine(:G2, :D, 150.0, 4.0, 1.0, 0.25, 1.0, 50.0, 0.05, 120.0),
     Machine(:G4, :F, 100.0, 4.0, 1.0, 0.25, 1.0, 40.0, 0.05, 45.0)],
    [Load(:LB, :B, 70.0, 20.0, 0.0, 0.0, 1.0), Load(:LE, :E, 130.0, 30.0, 0.0, 0.0, 1.0)];
    slack = :A)

# The corner triangle with a second machine and a 30 MVA grid-forming inverter (gain 15
# on the system base): losing G1 would give I3 17.1 MW of its 10 MW to the rating.
_m10_inverter_cap() = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C)],
    [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:BC, :B, :C, 0.15, 500.0),
     Branch(:CA, :C, :A, 0.20, 500.0)],
    [Machine(:G1, :A, 200.0, 5.0, 1.0, 0.25, 1.0, 40.0, 0.05, 200.0),
     Machine(:G2, :B, 100.0, 5.0, 1.0, 0.25, 1.0, 20.0, 0.05, 100.0)],
    [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0)]; slack = :A,
    inverters = [Inverter(:I3, :C, :grid_forming, 30.0, 20.0; K_p = 0.02)])

# genmesh with G1 at 180 MW and G3 at 10 MW: losing the load-machine LB restores DOWN
# and pushes G3 below zero — unless `Pmin` is given.
function _m10_low_g3(; Pmin = NaN)
    g = _m10_genmesh()
    ms = [m.id === :G1 ? GridSim._machine_with(m; P0 = 180.0) :
          m.id === :G3 ? GridSim._machine_with(m; P0 = 10.0, Pmin) : m for m in g.machines]
    NetworkModel(g.S_base, g.f0, g.buses, g.branches, ms; slack = g.slack)
end

# What a restored piece must be, read off its rebuilt model and the equipment list:
# balanced, shares by gain, every limit met to the bit, flows those of `dc_powerflow` on
# it. Returns the number of units that moved.
function _m10_restored_check(net::NetworkModel, rs::DCRestore, c::Int)
    R, pc = rs.models[c], rs.pieces[c]
    S = net.S_base
    r = GridSim._responders(net)
    imb(n) = sum(m.P0 for m in n.machines; init = 0.0) +
             sum(i.P0 for i in n.inverters; init = 0.0) - sum(l.P0 for l in n.loads; init = 0.0)
    @test abs(imb(R)) <= abs(imb(net)) + 1e-9                   # frequency on target
    @test all(b -> b in pc.buses, (bu.id for bu in R.buses)) && length(R.buses) == length(pc.buses)
    moved, ratio = 0, Float64[]
    for (q, u) in pairs(r.ids)
        u === rs.element && continue
        net.buses[r.bus[q]].id in pc.buses || continue
        unit = q <= r.n_machines ? only(m for m in R.machines if m.id === u) :
                                   only(i for i in R.inverters if i.id === u)
        orig = q <= r.n_machines ? net.machines[q] : only(i for i in net.inverters if i.id === u)
        rs.pickup[q] == 0.0 || (moved += 1)
        if rs.capped[q]
            @test unit.P0 === (q <= r.n_machines ? orig.Pmax :
                               sqrt(orig.S_rated^2 - orig.Q0^2))
        elseif rs.floored[q]
            @test unit.P0 === min(orig.P0, orig.Pmin)
        elseif r.g[q] > 0.0
            push!(ratio, rs.pickup[q] / r.g[q])
            @test unit.P0 ≈ orig.P0 + rs.pickup[q] * S rtol = 1e-14 atol = 1e-12
        else
            @test rs.pickup[q] == 0.0 && unit.P0 === orig.P0     # no governor: no share
        end
    end
    isempty(ratio) || @test maximum(ratio) - minimum(ratio) <= 1e-12 * maximum(abs, ratio)
    sol = dc_powerflow(R)
    band = 100eps() * max(maximum(abs, filter(!isnan, rs.flow); init = 0.0),
                          maximum(abs, sol.flow; init = 0.0))
    for (e, bid) in pairs(sol.branches)
        @test abs(rs.flow[findfirst(br -> br.id === bid, net.branches)] - sol.flow[e]) <= band
    end
    return moved
end

# The AC restore's losses identity for one restored piece (step 3's `_m10_identity`,
# with the restore's single element and its pickups): every term off the base solution,
# the restored solution and the model.
function _m10_restore_identity(net::NetworkModel, base::ACPowerFlow, rs::ACRestore, pc::ACPiece)
    sol = pc.solution
    inp(bus) = bus in pc.buses
    vb(bus) = findfirst(==(bus), base.buses)
    lostP = sum((m.bus === net.slack ? base.Pgen[vb(m.bus)] : m.P0 / net.S_base
                 for m in net.machines if m.id === rs.element && inp(m.bus)); init = 0.0)
    dload = sum(sol.Pload) - sum(base.Pload[vb(bus)] for bus in pc.buses)
    loss_b, exp_b = 0.0, 0.0
    for (e, br) in pairs(net.branches)
        f, t = inp(br.from), inp(br.to)
        f && t && (loss_b += base.loss[e])
        f && !t && (exp_b += base.flow[e])
        t && !f && (exp_b += base.flow_rev[e])
    end
    dloss = sum(sol.loss; init = 0.0) - loss_b
    rb = GridSim._responders(net)
    Σpk = sum((rs.pickup[q] for q in eachindex(rb.ids)
               if inp(net.buses[rb.bus[q]].id) && rb.ids[q] !== rs.element); init = 0.0)
    bound = length(pc.buses) * (max(base.residual, eps()) + max(sol.residual, eps()))
    @test abs(Σpk - lostP - dload - dloss + exp_b) <= bound
    return Σpk
end

@testset "M10 step 5 — fail, restore 50 Hz, fail again" begin

    @testset "the restore is exact: on target, shares by gain, every limit to the bit (21.1)" begin
        nets = [_M10_MESH(), _M10_CASE9(), _m10_tie(), _m10_inverter_cap(), _m10_low_g3(),
                _m10_low_g3(Pmin = 0.0), _m10_genmesh()]
        nrestored, nmoved = 0, 0
        for net in nets, e in [[b.id for b in net.branches]; [m.id for m in net.machines]]
            rs = dc_restore(net, e)
            for c in eachindex(rs.pieces)
                rs.models[c] === nothing && continue
                nmoved += _m10_restored_check(net, rs, c)
                nrestored += 1
            end
        end
        @test nrestored > 0 && nmoved > 0
        # The cap binds (mesh, G2 lost): G3 at its 45 MW to the bit, G1 takes the rest.
        rs = dc_restore(_M10_MESH(), :G2)
        R = only(rs.models)
        @test only(m.P0 for m in R.machines if m.id === :G3) === 45.0
        @test only(m.P0 for m in R.machines if m.id === :G1) ≈ 205.0 rtol = 1e-14
        @test rs.capped == [false, false, true]
        # Nothing binds (mesh, G3 lost): 40 MW by gain, 60 : 37.5.
        rs = dc_restore(_M10_MESH(), :G3)
        @test rs.pickup[1:2] .* 100 ≈ [40 * 60 / 97.5, 40 * 37.5 / 97.5] rtol = 1e-13
        # An inverter at its rating (D11.3): I3 at 30 MW to the bit, G2 takes the rest.
        rs = dc_restore(_m10_inverter_cap(), :G1)
        R = only(rs.models)
        @test only(R.inverters).P0 === 30.0 && rs.capped == [false, false, true]
        @test only(m.P0 for m in R.machines if m.id === :G2) ≈ 50.0 rtol = 1e-14
    end

    @testset "per piece across a split: one piece down to a floor, the other up to a cap" begin
        net = _m10_tie()
        rs = dc_restore(net, :CD)
        @test [pc.outcome for pc in rs.pieces] == [:restored, :restored]
        @test [pc.buses for pc in rs.pieces] == [[:A, :B, :C], [:D, :E, :F]]
        @test rs.pieces[1].imbalance ≈ -0.4 rtol = 1e-12        # the left exported 40 MW
        @test rs.pieces[2].imbalance ≈ 0.4 rtol = 1e-12
        L, Rt = rs.models
        P(n, id) = only(m.P0 for m in n.machines if m.id === id)
        @test P(L, :G3) === 20.0 && P(Rt, :G4) === 45.0          # the floor, the cap
        @test P(L, :G1) ≈ 50.0 rtol = 1e-14
        @test P(Rt, :G2) ≈ 85.0 rtol = 1e-14
        @test findall(rs.floored) == [2] && findall(rs.capped) == [4]
        @test [r.id for r in L.machines] == [:G1, :G3] && L.slack === :A
        @test [r.id for r in Rt.machines] == [:G2, :G4] && Rt.slack === :D
        # A second loss in one piece leaves the other on target, untouched.
        s = dc_sequential_outages(net)
        p = findfirst(==((findfirst(==(:CD), s.id), findfirst(==(:G1), s.id))), s.pairs)
        @test s.outcome[p] === :screened
        right = only(pc for pc in s.pieces[p] if :E in pc.buses)
        @test right.outcome === :restored && right.Δω === 0.0
        left = only(pc for pc in s.pieces[p] if :B in pc.buses)
        @test left.outcome === :shared && left.Δω < 0
    end

    @testset "a restore can be refused where the settle answers (21.2)" begin
        net = _M10_MESH()
        rs = dc_restore(net, :G1)
        @test only(rs.pieces).outcome === :restore_refused && only(rs.models) === nothing
        @test isnan(only(rs.pieces).Δω) && all(==(0.0), rs.pickup)
        @test dc_generator_outages(net).outcome[1] === :shared   # the settle answers it
        s = dc_sequential_outages(net)
        g1 = findfirst(==(:G1), s.id)
        @test all(s.outcome[p] === :not_restored for (p, (a, _)) in pairs(s.pairs) if a == g1)
        @test count(==(:not_restored), s.outcome) == 9
        ar = ac_restore(net, :G1)
        @test only(ar.pieces).outcome === :restore_refused && only(ar.models) === nothing
        # Nothing with a governor: no response, by name.
        @test only(dc_restore(_m10_bowtie(), :G1).pieces).outcome === :no_response
    end

    @testset "Pmin honoured on the way down; a unit below zero is flagged (D3)" begin
        rs = dc_restore(_m10_low_g3(), :LB)
        @test rs.below_zero == [:G3]
        R = only(rs.models)
        g3 = only(m for m in R.machines if m.id === :G3)
        @test g3.P0 ≈ 10.0 - 130.0 * 20 / 117.5 rtol = 1e-13
        @test g3.P0 < 0
        rs = dc_restore(_m10_low_g3(Pmin = 0.0), :LB)
        @test isempty(rs.below_zero) && rs.floored[findfirst(==(:G3), [m.id for m in _m10_genmesh().machines])]
        @test only(m.P0 for m in only(rs.models).machines if m.id === :G3) === 0.0
        # After the second loss's settle too: G2 then LB on the low-G3 grid.
        s = dc_sequential_outages(_m10_low_g3())
        p = findfirst(==((findfirst(==(:G2), s.id), findfirst(==(:LB), s.id))), s.pairs)
        @test s.outcome[p] === :screened && :G3 in s.below_zero[p]
    end

    @testset "line first, nothing to restore: A then B IS both at once (DC)" begin
        for (net, expect) in ((_M10_MESH(), 63), (_M10_CASE9(), 66))
            s, pr = dc_sequential_outages(net), dc_pair_outages(net)
            n = 0
            for (p, (a, b)) in pairs(s.pairs)
                (s.kind[a] === :branch && length(s.restore[a].pieces) == 1) || continue
                @test s.restore[a].pieces[1].imbalance === 0.0 && all(==(0.0), s.restore[a].pickup)
                q = findfirst(==((min(a, b), max(a, b))), pr.pairs)
                ls = Dict(Set(pc.buses) => pc for pc in s.pieces[p] if pc.kind === :live)
                lp = Dict(Set(pc.buses) => pc for pc in pr.pieces[q] if pc.kind === :live)
                @test keys(ls) == keys(lp)
                scale = max(maximum(abs, filter(!isnan, pr.flow[q]); init = 0.0),
                            maximum((abs(pc.Δω) for pc in values(lp) if !isnan(pc.Δω)); init = 0.0))
                band = 100eps() * max(scale, 1.0)
                for k in keys(lp)
                    @test ls[k].outcome === lp[k].outcome
                    @test (isnan(ls[k].Δω) && isnan(lp[k].Δω)) || abs(ls[k].Δω - lp[k].Δω) <= band
                end
                @test maximum(abs, s.pickup[p] .- pr.pickup[q]) <= band
                @test all(isnan(x) && isnan(y) || abs(x - y) <= band
                          for (x, y) in zip(s.flow[p], pr.flow[q]))
                n += 1
            end
            @test n == expect
        end
    end

    @testset "AC: the restore's losses identity, and ac_powerflow gives the restored state back" begin
        nrestored = 0
        for f in (_M10_MESH, _M10_CASE9), loads in (:constant_power, :default)
            net = f(; loads)
            base = ac_powerflow(net)
            for e in [[b.id for b in net.branches]; [m.id for m in net.machines]]
                rs = ac_restore(net, e)
                for (c, pc) in pairs(rs.pieces)
                    pc.solution === nothing && continue
                    @test pc.Δω === 0.0
                    Σpk = _m10_restore_identity(net, base, rs, pc)
                    @test Σpk != 0.0                             # every loss moves something
                    b = rs.bases[c]
                    @test b !== nothing
                    b === nothing && continue
                    for (v, bus) in pairs(pc.solution.buses)
                        j = findfirst(==(bus), b.buses)
                        @test abs(pc.solution.Vm[v] - b.Vm[j]) <= _M10_B
                        @test abs(pc.solution.Pgen[v] - b.Pgen[j]) <= _M10_B
                    end
                    nrestored += 1
                end
            end
        end
        @test nrestored > 0
    end

    @testset "order (21.4): the orders differ by what the first loss alone would settle to" begin
        # Written AFTER the table (step5_pairs.out.txt) and the probe that explained it
        # (step5_offset_probe.out.txt). Restoring cancels the first loss's own settled
        # deviation before the second, so per live piece, with no governor capped,
        #     Δω(both at once) − Δω(A then B) = −Σ(restore pickups after A) / Σ(1/R + D),
        # both sums over the piece's surviving units. Exact in DC; in AC exact to the
        # solver on case9, whose machines all have the same D·R — restoring and settling
        # then move them in the same proportions — and NOT on the mesh, whose do not.
        cases = [(_M10_CASE9(), :dc, 39, 1e-12), (_M10_MESH(), :dc, 7, 1e-12),
                 (_M10_CASE9(loads = :constant_power), :ac, 26, 1e-10),
                 (_M10_CASE9(loads = :default), :ac, 41, 1e-10),
                 (_M10_MESH(loads = :constant_power), :ac, 8, 1e-3),
                 (_M10_MESH(loads = :default), :ac, 9, 1e-3)]
        for (net, fid, expect, tol) in cases
            seq = fid === :dc ? dc_sequential_outages(net) : ac_sequential_outages(net)
            sim = fid === :dc ? dc_pair_outages(net) : ac_pair_outages(net)
            r = GridSim._responders(net)
            ok(pc) = !isnan(pc.Δω) && pc.outcome === (fid === :dc ? :shared : :secure)
            n, worst = 0, 0.0
            for (p, (a, b)) in pairs(seq.pairs)
                seq.outcome[p] === :screened || continue
                q = findfirst(==((min(a, b), max(a, b))), sim.pairs)
                ls = Dict(Set(pc.buses) => pc for pc in seq.pieces[p] if pc.kind === :live)
                lb = Dict(Set(pc.buses) => pc for pc in sim.pieces[q] if pc.kind === :live)
                (keys(ls) == keys(lb) && all(ok, values(ls)) && all(ok, values(lb))) || continue
                (any(seq.capped[p]) || any(sim.capped[q])) && continue
                for (k, pc) in ls
                    u = [i for i in eachindex(r.ids) if net.buses[r.bus[i]].id in k &&
                         !(r.ids[i] in (seq.id[a], seq.id[b]))]
                    pred = -sum(seq.restore[a].pickup[u]) / sum(r.g[u] .+ r.d[u])
                    pred == 0.0 && continue
                    worst = max(worst, abs(lb[k].Δω - pc.Δω - pred) / abs(pred))
                    n += 1
                end
            end
            @test n == expect
            @test worst <= tol
            # The mesh's AC gap is the law only approximately: its D·R differ (registered).
            fid === :ac && net.buses[1].id === :A && @test worst > 1e-5
        end
        # DC, both report grids: wherever both orders were screened the WORSE order is
        # both at once (a line first restores nothing; every machine pair caps), and the
        # final dispatch of the two orders is the same on case9 — whose equal D·R hide
        # the difference between restoring and settling — but not on the mesh.
        for (net, nboth, nsame) in ((_M10_CASE9(), 63, 63), (_M10_MESH(), 36, 22))
            seq, sim = dc_sequential_outages(net), dc_pair_outages(net)
            idx = Dict(ab => p for (p, ab) in pairs(seq.pairs))
            worstΔω(ps) = maximum((abs(pc.Δω) for pc in ps if pc.kind === :live); init = 0.0)
            n, same = 0, 0
            for (q, (a, b)) in pairs(sim.pairs)
                pab, pba = idx[(a, b)], idx[(b, a)]
                (seq.outcome[pab] === :screened && seq.outcome[pba] === :screened) || continue
                w = max(worstΔω(seq.pieces[pab]), worstΔω(seq.pieces[pba]))
                @test abs(w - worstΔω(sim.pieces[q])) <= 1e-12 * max(w, 1e-300)
                same += maximum(abs, seq.pickup[pab] .- seq.pickup[pba]) <= 1e-11
                n += 1
            end
            @test n == nboth && same == nsame
        end
    end

    @testset "the detailed tier run from the restored model settles where the screen says" begin
        # Hurdle 21's only independent check (not cuttable): the detailed tier initialised on
        # the AC restored model, the second element tripped, each piece's settled frequency
        # against the sequential screen's through step 4's per-piece losses identity. The
        # cases are the spike's (`step5_dynamic_spike.jl`), chosen from the screen's table —
        # final pieces :secure, nothing capped; on constant power L78→G2 and L89→G2 are
        # refused at the trip instant in this tier (B2 sags to 0.879 / 0.894 pu, field flux
        # against V_set — the gap M9 and step 4 met), so they are not here.
        cases = [(:default, :L78, :G2), (:default, :L56, :G3), (:default, :L56, :L78),
                 (:default, :L45, :L67), (:constant_power, :L56, :G3),
                 (:constant_power, :L56, :L78)]
        nchecked, updown = 0, 0
        for (loads, a, b) in cases
            net = _M10_CASE9(; loads)
            s = ac_sequential_outages(net)
            ia, ib = findfirst(==(a), s.id), findfirst(==(b), s.id)
            p = findfirst(==((ia, ib)), s.pairs)
            @test s.outcome[p] === :screened
            rs = s.restore[ia]
            c = only(i for (i, pc) in pairs(rs.pieces) if pc.kind === :live)
            R = rs.models[c]
            live = [pc for pc in s.pieces[p] if pc.kind === :live]
            @test all(pc -> pc.outcome === :secure, live) && !any(s.capped[p])
            eng = _m10_de(R; base = rs.bases[c], tol = 1e-10, solver = OrdinaryDiffEq.Rodas5P())
            solve!(eng, (0.0, 1.0); saveat = 0.5)
            inject!(eng, s.kind[ib] === :machine ? TripGenerator(b) :
                         TripElements(lines = [(br.from, br.to) for br in R.branches if br.id === b]))
            solve!(eng, (1.0, 300.0); saveat = 0.5)
            ω300 = [_m10_piece_identity(eng, R, pc).ω for pc in live]
            solve!(eng, (300.0, 400.0); saveat = 0.5)
            ωs = Float64[]
            for (i, pc) in pairs(live)
                r = _m10_piece_identity(eng, R, pc)
                @test abs(r.ω - ω300[i]) <= 1e-10                  # settled
                @test r.lhs ≈ r.rhs rtol = 1e-6
                @test abs(r.lhs) > 1e3 * abs(r.lhs - r.rhs)        # not 0 ≈ 0
                if length(live) == 2                               # per piece, or not at all
                    @test abs(r.lhs - r.rhs_Σw) > 1e3 * abs(r.lhs - r.rhs)
                    @test abs(r.lhs - r.rhs_L) > 1e3 * abs(r.lhs - r.rhs)
                end
                push!(ωs, r.ω)
                nchecked += 1
            end
            length(ωs) == 2 && (updown += prod(sign, ωs) < 0)
        end
        @test nchecked == 9 && updown == 3      # three splits, each one piece up, one down
    end

    @testset "inverters: a grid-forming one restores to its rating, a grid-following one holds" begin
        # AC on the inverter-cap fixture: I3 at its rating to the bit in the restored model,
        # the identity and ac_powerflow's give-back as on the report grids.
        net = _m10_inverter_cap()
        base = ac_powerflow(net)
        rs = ac_restore(net, :G1)
        pc = only(rs.pieces)
        @test pc.outcome === :secure && rs.capped == [false, false, true]
        R = only(rs.models)
        @test only(R.inverters).P0 === 30.0
        _m10_restore_identity(net, base, rs, pc)
        b = only(rs.bases)
        for (v, bus) in pairs(pc.solution.buses)
            @test abs(pc.solution.Vm[v] - b.Vm[findfirst(==(bus), b.buses)]) <= _M10_B
        end
        # M7's two-bus pair (the exported-surface walk's model): both screens return on both
        # kinds (`step5_m7walk.jl`). A grid-following inverter has nothing to follow once G1
        # or the line goes — its piece is load lost; a grid-forming one restores alone, to
        # exactly its 100 MVA rating.
        pair(mode) = NetworkModel(100.0, 50.0, [Bus(:B1, 230.0), Bus(:B2, 230.0)],
            [Branch(:L12, :B1, :B2, 0.2, 500.0)],
            [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 50.0)], [Load(:D2, :B2, 100.0, 0.0)];
            inverters = [Inverter(:I2, :B2, mode, 100.0, 50.0)])
        for f in (dc_sequential_outages, ac_sequential_outages)
            s = f(pair(:grid_following))
            @test all(==(:already_lost), s.outcome)
            @test all(rs -> any(pc -> pc.kind === :load_lost, rs.pieces), s.restore)
            s = f(pair(:grid_forming))
            for rs in s.restore
                @test only(only(m for m in rs.models if m !== nothing).inverters).P0 === 100.0
            end
            @test s.outcome == [:already_lost, :screened]
        end
    end

    @testset "names and refusals" begin
        @test_throws ArgumentError dc_restore(_M10_MESH(), :nope)
        @test_throws ArgumentError ac_restore(_M10_MESH(), :nope)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# M10 step 6 — the report's one fix to the screens (m10-context.md D12.1)
# ─────────────────────────────────────────────────────────────────────────────

@testset "M10 step 6 — a refused piece keeps no pickups and no flags" begin

    @testset "the mesh's G1: the AC restore is refused, and says nothing is capped" begin
        for loads in (:constant_power, :default)
            net = _M10_MESH(; loads)
            ar, dr = ac_restore(net, :G1), dc_restore(net, :G1)
            @test only(ar.pieces).outcome === only(dr.pieces).outcome === :restore_refused
            # Before the fix AC said G2 and G3 were capped while their pickups were zero.
            @test !any(ar.capped) && !any(ar.floored) && all(==(0.0), ar.pickup)
            @test ar.capped == dr.capped
            s = ac_sequential_outages(net)
            g1 = findfirst(==(:G1), s.id)
            for (p, (a, _)) in pairs(s.pairs)
                a == g1 || continue
                @test s.outcome[p] === :not_restored && !any(s.capped[p])
            end
        end
    end

    @testset "every AC pair keeps pickups and flags exactly where the sequential mask does" begin
        # One rule, two places: `_ac_outage_set` keeps a live piece's entries where it has
        # a solution or a settled Δω; `ac_sequential_outages` masks with `_answered_mask`
        # on the same predicate. Asserted equal on every pair of both report grids.
        ok = pc -> pc.solution !== nothing || !isnan(pc.Δω)
        nkept = 0
        for f in (_M10_CASE9, _M10_MESH), loads in (:constant_power, :default)
            net = f(; loads)
            a = ac_pair_outages(net)
            r = GridSim._responders(net)
            m = length(net.branches)
            for (p, (i, j)) in pairs(a.pairs)
                lost_ids = Int[e - m for e in (i, j) if e > m]
                keep = GridSim._answered_mask(net, r, a.pieces[p], lost_ids, ok)
                @test !any(a.capped[p] .& .!keep)
                @test all(a.pickup[p][.!keep] .== 0.0)
                nkept += count(keep)
            end
        end
        @test nkept > 0                       # the mask is not empty everywhere
    end
end
