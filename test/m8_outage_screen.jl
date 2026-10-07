# ─────────────────────────────────────────────────────────────────────────────
# M8 step 6 — the report (`scripts/outage_screen.jl`, m8-context.md D9)
#
# Two halves. First the layer the report is built on — the lone-source rule (D9, the
# user's choice) and the generator comparison — each class and each refusal on a
# fixture of its own, so a rule that answers the same thing everywhere cannot pass.
# Then the script's claims, asserted against the script's own functions (the
# `OutageScreenScript` module in `runtests.jl`), never a second copy of its fixtures.
# Every claim was written AFTER the four tables were read
# (`W:\temp\claude\gridsim-m8\step6_predictions.md` holds what was predicted first).
# ─────────────────────────────────────────────────────────────────────────────

const _OS = OutageScreenScript

# The most-loaded branch after outage row `r`, as a share of its rating, at each
# fidelity — the script's own column, read through the script's own function.
_m8_worst(s, net, r) = _OS.worst_loading(s, net, r)

# A pendant fixture: a triangle A–B–C carrying G1 (slack), G0 and the load, and a
# pendant bus P hung off C by line CP. What sits at P is the argument. G0 (zero output)
# is there so the main side is never a lone source itself: with G1 alone there, a rule
# that ignored loads would see a lone source on BOTH sides and decline for the wrong
# reason (the first sabotage run, MU2, measured exactly that).
function _m8_pendant(; at_p = :machine, island = 1)
    buses = [Bus(s, 230.0) for s in (:A, :B, :C, :P, :Q)][1:(island == 2 ? 5 : 4)]
    br = [Branch(:AB, :A, :B, 0.1, 500.0), Branch(:BC, :B, :C, 0.1, 500.0),
          Branch(:CA, :C, :A, 0.1, 500.0), Branch(:CP, :C, :P, 0.1, 500.0)]
    island == 2 && push!(br, Branch(:PQ, :P, :Q, 0.1, 500.0))
    gbus = island == 2 ? :Q : :P                 # the pendant machine sits at the far end
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.0, 100.0, 0.05, 250.0),
          Machine(:G0, :B, 100.0, 4.0, 1.0, 0.25, 1.0, 0.0, 0.05, 50.0)]
    ls = [Load(:LB, :B, 140.0, 20.0, 0.0, 0.0, 1.0)]
    invs = Inverter[]
    if at_p in (:machine, :machine_and_load, :two_machines)
        push!(ms, Machine(:GP, gbus, 100.0, 4.0, 1.0, 0.25, 1.0, 40.0, 0.05, 80.0))
    end
    at_p === :two_machines && push!(ms, Machine(:GP2, :P, 50.0, 4.0, 1.0, 0.25, 1.0, 0.0, 0.05, 40.0))
    at_p in (:machine_and_load, :load) && push!(ls, Load(:LP, :P, 40.0, 5.0, 0.0, 0.0, 1.0))
    at_p === :inverter && push!(invs, Inverter(:IP, :P, :grid_following, 60.0, 40.0))
    # G1's schedule balances whatever the rest injects and draws (`NetworkModel` refuses
    # an unbalanced schedule).
    P1 = sum(l.P0 for l in ls) - sum(m.P0 for m in ms[2:end]; init = 0.0) -
         sum(i.P0 for i in invs; init = 0.0)
    ms[1] = Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.0, P1, 0.05, 250.0)
    return NetworkModel(100.0, 50.0, buses, br, ms, ls; slack = :A, inverters = invs)
end

# Every class's fixture for the generator comparison: the script's case9 re-rated.
_m8_c9rated(; loads = :constant_power, kw...) = (n = _OS.case9(; loads);
    NetworkModel(n.S_base, n.f0, n.buses,
                 [Branch(b.id, b.from, b.to, b.X, get(kw, b.id, b.rating); R = b.R)
                  for b in n.branches], n.machines, n.loads; slack = n.slack))

# A mesh where losing G2 (60 MW) is covered by G1's 61 MW of headroom in DC but not in
# AC, whose added line losses push the need to 61.13 MW. No damping anywhere, so a
# capped governor leaves nothing to carry the rest (D7's second refusal).
function _m8_tight(h = 61.0)
    ms = [Machine(:G1, :A, 300.0, 5.0, 0.0, 0.25, 1.05, 150.0, 0.05, 150.0 + h, 0.5; V_set = 1.05),
          Machine(:G2, :C, 150.0, 4.0, 0.0, 0.25, 1.04, 60.0, Inf, 100.0, 0.4; V_set = 1.04),
          Machine(:G3, :E, 120.0, 3.5, 0.0, 0.25, 1.02, 40.0, Inf, 45.0, 0.6; V_set = 1.02)]
    br = [Branch(id, f, t, x, 500.0; R = 0.1x) for (id, f, t, x) in
          ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15),
           (:BD, :B, :D, 0.25), (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10), (:BE, :B, :E, 0.20))]
    ls = [Load(:LB, :B, 130.0, 30.0, 0, 0, 1), Load(:LD, :D, 120.0, 25.0, 0, 0, 1)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms, ls;
                 slack = :A)
end

_m8_gens(net) = compare_generator_screens(net, dc_generator_outages(net),
                                          ac_generator_outages(net))

@testset "M8 step 6 — the report: the lone-source rule, both comparisons, the claims" begin

    @testset "the rule maps case9's three generator lines by name, from the graph" begin
        src = lone_source_bridges(_OS.case9())
        ids = [b.id for b in _OS.case9().branches]
        @test Dict(ids[e] => src.machine[e] for e in eachindex(ids) if src.machine[e] !== :none) ==
              Dict(:L14 => :G1, :L36 => :G3, :L82 => :G2)
        # L82 is declared B8 → B2: the source is at its `to` end. A rule that took the
        # `from` side as the cut-off one would get exactly this line wrong.
        @test src.cut_off[findfirst(==(:L82), ids)] == [:B2]
        @test src.cut_off[findfirst(==(:L14), ids)] == [:B1]
        @test all(isempty, src.cut_off[src.machine .=== :none])
    end

    @testset "…and declines every cut-off side that is not ONE machine and nothing else" begin
        m(net) = lone_source_bridges(net).machine[findfirst(b -> b.id === :CP, net.branches)]
        @test m(_m8_pendant()) === :GP                         # positive control
        @test m(_m8_pendant(; at_p = :machine_and_load)) === :none
        @test m(_m8_pendant(; at_p = :load)) === :none
        @test m(_m8_pendant(; at_p = :inverter)) === :none
        @test m(_m8_pendant(; at_p = :two_machines)) === :none
        # Two buses cut off with one machine: still one source, and both buses are dead.
        two = _m8_pendant(; island = 2)
        s2 = lone_source_bridges(two)
        @test s2.machine == [:none, :none, :none, :GP, :GP]
        @test Set(s2.cut_off[4]) == Set([:P, :Q]) && s2.cut_off[5] == [:Q]
        # A lone source on BOTH sides: no one machine is "the" outage.
        pair = NetworkModel(100.0, 50.0, [Bus(:A, 230.0), Bus(:B, 230.0)],
                            [Branch(:AB, :A, :B, 0.1, 500.0)],
                            [Machine(:G1, :A, 100.0, 5.0, 1.0, 0.25, 1.0, 0.0),
                             Machine(:G2, :B, 100.0, 5.0, 1.0, 0.25, 1.0, 0.0)])
        @test lone_source_bridges(pair).machine == [:none]
        # Step 2's mesh: DE is a bridge to a LOAD bus, never mapped.
        @test lone_source_bridges(_m8_mesh()).machine == fill(:none, 6)
    end

    @testset "losing the line IS losing the generator: zero current, same voltage, both fidelities" begin
        # Each mapped line, read in its generator's outage with the line still in. 315 MW
        # covers L36 and L82; G1's loss there is a voltage refusal with no solution, so
        # L14 is read at 200 MW, where it solves — and at 315 through the refusal's own
        # bus list, which carries both ends.
        for (mw, lines) in ((315.0, (:L36, :L82)), (200.0, (:L14, :L36, :L82)))
            for loads in (:constant_power, :default)
                rows = Dict(c.line => c for c in _OS.rule_check(_OS.case9(; loads, mw)))
                for l in lines
                    # Claim (a) prints "at most 1e-15 pu" and "exactly 0.0 in AC".
                    @test rows[l].dc_flow <= 1e-15
                    @test rows[l].ac_flow <= 1e-12
                    @test rows[l].ΔV <= 1e-12
                end
                mw == 315.0 && @test all(rows[l].ac_flow == 0.0 for l in lines)
            end
        end
        c = only(c for c in _OS.rule_check(_OS.case9()) if c.line === :L14)
        @test c.ac_outcome === :voltage && isnan(c.ac_flow) && c.ΔV <= 1e-12
    end

    @testset "a mapped row IS its generator's row, with the dead buses left unjudged" begin
        for loads in (:constant_power, :default)
            net = _OS.case9(; loads)
            s = outage_screen(net)
            for (line, gen) in ((:L14, :G1), (:L36, :G3), (:L82, :G2))
                r, g = findfirst(==(line), s.id), findfirst(==(gen), s.id)
                @test s.via[r] === gen && s.kind[r] === :branch
                for f in (:dc_outcome, :ac_outcome, :class, :dc_over, :reason)
                    @test getfield(s, f)[r] == getfield(s, f)[g]
                end
                @test s.dc_flow[r] === s.dc_flow[g] && s.reactive[r] === s.reactive[g]
                @test s.Δω_dc[r] === s.Δω_dc[g] && s.Δω_ac[r] === s.Δω_ac[g]
            end
            # G1's own row judges B1 (it is live there, through L14); L14's row does not
            # (it is dead), and the verdict is the same because B1 sits at B4's voltage.
            g1, l14 = findfirst(==(:G1), s.id), findfirst(==(:L14), s.id)
            V = Dict(l.bus => l.Vm for l in s.low[g1])
            @test haskey(V, :B1) && V[:B1] == V[:B4]
            @test !any(l -> l.bus === :B1, s.low[l14])
            @test [l for l in s.low[g1] if l.bus !== :B1] == s.low[l14]
            # The graph facts underneath did not move.
            @test s.lines.class[findfirst(==(:L14), s.lines.branches)] === :splits
        end
        # A bridge to anything else stays a split in every column.
        s = outage_screen(_m8_pendant(; at_p = :machine_and_load))
        r = findfirst(==(:CP), s.id)
        @test (s.dc_outcome[r], s.ac_outcome[r], s.class[r], s.via[r]) ==
              (:splits, :splits, :splits, :none)
        @test isempty(s.dc_flow[r]) && isnan(s.Δω_dc[r])
    end

    @testset "the generator comparison: every class on a fixture of its own" begin
        # Both overload: L14 at 140 MVA (base 127.5 MVA AC); losing G2 puts 151.4 MW on
        # it in DC and 192.2 MVA in AC.
        g = _m8_gens(_m8_c9rated(; L14 = 140.0))
        @test g.class[2] === :agree && g.dc_over[2] == g.ac_over[2] == [:L14]
        # …and on a line whose flow runs AGAINST its declared direction (L94 is B9 → B4;
        # losing G2 sends 111.9 MW from B4 to B9), so a DC flow judged without its
        # magnitude would pass it.
        g = _m8_gens(_m8_c9rated(; L94 = 100.0))
        @test dc_generator_outages(_m8_c9rated(; L94 = 100.0)).flow[2][9] < -1.0
        @test g.class[2] === :agree && g.dc_over[2] == g.ac_over[2] == [:L94]
        # DC misses: L14 at 170 MVA, between the two.
        g = _m8_gens(_m8_c9rated(; L14 = 170.0))
        @test g.class[2] === :dc_missed && isempty(g.dc_over[2]) && g.ac_over[2] == [:L14]
        @test g.class[3] === :dc_missed                     # G3's loss too: 143.2 vs 180.0
        # …and the miss is reactive: L14 carries the slack's reactive output.
        e = 1
        @test g.reactive[2][e] * 100 > 170 - abs(dc_generator_outages(_m8_c9rated(; L14 = 170.0)).flow[2][e]) * 100
        # DC false alarm, on the DEFAULT loads: L67 at 112.7 MVA; losing G2 puts 113.1 MW
        # on it in DC and 112.4 MVA in AC, because the sagging voltage sheds load.
        g = _m8_gens(_m8_c9rated(; loads = :default, L67 = 112.7))
        @test g.class[2] === :dc_false_alarm && g.dc_over[2] == [:L67] && isempty(g.ac_over[2])
        # Blind: G1's loss is a voltage refusal on the published case.
        @test _m8_gens(_OS.case9()).class == [:dc_blind, :agree, :agree]
        # Blind: a grid-forming inverter pushed over its rating (step 5's I3 at 45 MVA,
        # losing G1).
        g = _m8_gens(_m8_acmesh(; gfm = true, S_inv = 45.0))
        @test g.dc_outcome[1] === :secure && g.ac_outcome[1] === :overload
        @test g.class[1] === :dc_blind && isempty(g.ac_over[1])
        # Both refuse: case9 as M6 builds it has no droop and no damping.
        g = _m8_gens(_ed_case9())
        @test g.class == fill(:refused, 3) && g.dc_outcome == g.ac_outcome == fill(:no_response, 3)
        # Only one refuses: 61 MW of headroom covers the 60 MW DC loses, not the
        # 61.13 MW AC needs once losses rise. With 62 MW both settle.
        g = _m8_gens(_m8_tight(61.0))
        @test (g.dc_outcome[2], g.ac_outcome[2], g.class[2]) == (:secure, :reserve_exhausted, :refusals_differ)
        @test _m8_gens(_m8_tight(62.0)).class[2] === :agree
        # Screens of another model are refused.
        a, b = _OS.case9(), _m8_tight()
        @test_throws ArgumentError compare_generator_screens(a, dc_generator_outages(b),
                                                             ac_generator_outages(a))
    end

    @testset "outage_screen on inverter models (why it is on M7's learned list)" begin
        # A grid-forming inverter answers frequency in both generator screens and is
        # over its rating when G1 is lost (step 5's I3 at 45 MVA): the row says so.
        s = outage_screen(_m8_acmesh(; gfm = true, S_inv = 45.0))
        g1 = findfirst(==(:G1), s.id)
        @test length(s.id) == 7 + 2 && s.kind[g1] === :machine
        @test s.class[g1] === :dc_blind && only(s.ac_over[g1]).kind === :inverter
        @test s.generators.machines == [:G1, :G2]
        # An inverter on the cut-off side keeps a bridge a split, in the full report.
        s = outage_screen(_m8_pendant(; at_p = :inverter))
        r = findfirst(==(:CP), s.id)
        @test s.class[r] === :splits && s.via[r] === :none
    end

    @testset "the script's fixtures are the ones they say they are" begin
        # case9: the branch data and loads are `_ed_case9`'s, number for number; the
        # machines differ ONLY in the invented droop, damping and rating.
        for loads in (:constant_power, :default)
            a, b = _OS.case9(; loads), _ed_case9(; zip_default = loads === :default)
            @test a.branches == b.branches && a.loads == b.loads && a.slack == b.slack
            for (x, y) in zip(a.machines, b.machines)
                @test (x.id, x.bus, x.P0, x.Pmax, x.V_set, x.Q_min, x.Q_max) ==
                      (y.id, y.bus, y.P0, y.Pmax, y.V_set, y.Q_min, y.Q_max)
                @test x.R == 0.05 && y.R == Inf && x.S_rated == x.Pmax
            end
        end
        # mesh: step 5's fixture, lossy.
        for (loads, cp) in ((:constant_power, true), (:default, false))
            a, b = _OS.mesh(; loads), _m8_acmesh(; r = 0.1, cp)
            @test a.branches == b.branches && a.machines == b.machines && a.loads == b.loads
        end
    end

    # ── The claims (`scripts/outage_screen.jl` section 3), each as printed ──────────

    screens = Dict((f, loads) => (net = getfield(_OS, f)(; loads); (net, outage_screen(net)))
                   for f in (:case9, :mesh), loads in (:constant_power, :default))

    @testset "claim a: a third of case9's line outages are decided by the rule" begin
        _, s = screens[(:case9, :constant_power)]
        lines = s.kind .=== :branch
        @test count(lines .& (s.via .!== :none)) == 3 && count(lines) == 9
        @test !any(s.class .=== :splits)                    # no line is left unanswered
        for k in (:constant_power, :default)
            @test all(screens[(:mesh, k)][2].via .=== :none)  # the mesh never needs it
        end
    end

    @testset "claim b: DC passes everything; every disagreement is a voltage refusal" begin
        for (key, (net, s)) in screens
            @test all(s.dc_outcome .=== :secure)
            @test all(c -> c in (:agree, :dc_blind), s.class)
            @test all(s.ac_outcome[s.class .=== :dc_blind] .=== :voltage)
        end
        blind(k) = Set(screens[k][2].id[screens[k][2].class .=== :dc_blind])
        @test blind((:case9, :constant_power)) == Set([:L14, :L45, :L94, :G1])
        @test blind((:case9, :default)) == Set([:L14, :L94, :G1])
        @test isempty(blind((:mesh, :constant_power))) && isempty(blind((:mesh, :default)))
        # L45 is the load model's call: 0.873 pu on constant power, secure on default.
        s = screens[(:case9, :constant_power)][2]
        @test only(s.low[findfirst(==(:L45), s.id)]).Vm ≈ 0.873 atol = 5e-4
    end

    @testset "claim c: where both say secure, DC understates the loading" begin
        # AC's most-loaded branch minus DC's, in points of rating, over every agreed row.
        function gaps(k)
            net, s = screens[k]
            return [100 * (d = _m8_worst(s, net, r); d[2] - d[1])
                    for r in eachindex(s.id) if s.class[r] === :agree]
        end
        # case9, constant power: up to 8.2 points (L78 out, 66.7 % → 74.9 %), and DC
        # never overstates — the understatement has one sign there.
        g = gaps((:case9, :constant_power))
        @test maximum(g) ≈ 8.24 atol = 0.01
        @test minimum(g) > 0
        net, s = screens[(:case9, :constant_power)]
        r = findfirst(==(:L78), s.id)
        @test 100 .* collect(_m8_worst(s, net, r)) ≈ [66.67, 74.90] atol = 0.01
        # Default loads: both ways, −3.0 to +3.3, because the sagging voltage sheds load.
        g = gaps((:case9, :default))
        @test minimum(g) ≈ -3.02 atol = 0.01
        @test maximum(g) ≈ 3.26 atol = 0.01
        # The most-loaded branch is the SAME branch at both fidelities on every agreed
        # row of all four tables, so "DC understates the most-loaded branch" compares
        # one line with itself (L78 out: L67 at both).
        worst_id(v) = v[argmax(v)]
        for (k, (net, s)) in screens, r in eachindex(s.id)
            s.class[r] === :agree || continue
            dc = [abs(s.dc_flow[r][e]) * net.S_base / b.rating for (e, b) in pairs(net.branches)]
            sol = s.via[r] !== :none ? s.ac_generators.solution[findfirst(==(s.via[r]), s.generators.machines)] :
                  s.kind[r] === :branch ? s.ac_lines.solution[r] :
                  s.ac_generators.solution[r - length(net.branches)]
            ac = Dict(id => max(hypot(sol.flow[j], sol.qflow[j]), hypot(sol.flow_rev[j], sol.qflow_rev[j])) *
                            net.S_base / net.branches[findfirst(b -> b.id === id, net.branches)].rating
                      for (j, id) in pairs(sol.branches))
            @test net.branches[argmax(dc)].id === argmax(ac)
        end
        # The mesh: never more than 2.1 points either way, on either load model.
        @test all(x -> 0 < x < 2.1, gaps((:mesh, :constant_power)))
        @test all(x -> 0 < x < 2.1, gaps((:mesh, :default)))
    end

    @testset "claim d: \"secure\" carries no frequency criterion" begin
        for k in (:constant_power, :default)
            net, s = screens[(:mesh, k)]
            g1 = findfirst(==(:G1), s.id)
            @test s.class[g1] === :agree && s.ac_outcome[g1] === :secure
            # Both governors capped (G2 at 40 MW, G3 at 5 MW of headroom); the other
            # 105 MW is carried by damping alone, Σ D = 4.8 pu: x = 1.05/4.8 exactly.
            @test s.Δω_dc[g1] ≈ -1.05 / 4.8 rtol = 1e-14
            @test s.Δω_dc[g1] * _OS.F0 ≈ -10.9375
            @test s.Δω_ac[g1] * _OS.F0 ≈ (k === :constant_power ? -11.22 : -11.06) atol = 0.005
            @test all(s.generators.ac_outcome .=== :secure)
        end
    end

    @testset "claim e: DC's settled frequency is neither bound on AC's" begin
        # On constant power the AC deviation is deeper in every generator outage, on
        # both grids (losses rise and must be covered too); on the default loads it is
        # shallower in five of six (the sagging voltage sheds load) — the mesh's G1, the
        # largest loss, is the exception.
        deeper(k) = (s = screens[k][2]; [s.Δω_ac[r] < s.Δω_dc[r] for r in eachindex(s.id) if s.kind[r] === :machine])
        @test all(deeper((:case9, :constant_power))) && all(deeper((:mesh, :constant_power)))
        @test deeper((:case9, :default)) == [false, false, false]
        @test deeper((:mesh, :default)) == [true, false, false]
        # DC's own number does not see the load model at all.
        for f in (:case9, :mesh)
            a, b = screens[(f, :constant_power)][2], screens[(f, :default)][2]
            @test isequal(a.Δω_dc, b.Δω_dc)
        end
        # The printed figures: deeper by 0.6–15.5 % on constant power (six outages)…
        ratio(k) = (s = screens[k][2]; [s.Δω_ac[r] / s.Δω_dc[r] for r in eachindex(s.id) if s.kind[r] === :machine])
        rs = [ratio((:case9, :constant_power)); ratio((:mesh, :constant_power))]
        @test 100 * (minimum(rs) - 1) ≈ 0.56 atol = 0.005
        @test 100 * (maximum(rs) - 1) ≈ 15.52 atol = 0.005
        # …case9's G1 at 0.401 against 0.463 Hz, and 0.195 Hz on the default loads,
        # about half of DC's (ratio 0.486).
        sc, sd = screens[(:case9, :constant_power)][2], screens[(:case9, :default)][2]
        g1 = findfirst(==(:G1), sc.id)
        @test sc.Δω_dc[g1] * _OS.F0 ≈ -0.401 atol = 5e-4
        @test sc.Δω_ac[g1] * _OS.F0 ≈ -0.463 atol = 5e-4
        @test sd.Δω_ac[g1] * _OS.F0 ≈ -0.195 atol = 5e-4
        @test sd.Δω_ac[g1] / sd.Δω_dc[g1] ≈ 0.486 atol = 5e-4
    end
end
