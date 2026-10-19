# ─────────────────────────────────────────────────────────────────────────────
# M10 step 6 — the report (`scripts/double_outage_screen.jl`)
#
# Every pair of elements of the two report grids, both at once and one after the other
# with 50 Hz restored in between, DC once and AC on both load models, judged per piece
# (m10-context.md D12). Asserted against the script's own row builders, so the numbers
# tested are the numbers printed. Every claim was written AFTER the tables were read and
# is asserted here at the precision it prints.
# ─────────────────────────────────────────────────────────────────────────────

const _DO = DoubleOutageScript

const _DO_G = Dict(key => _DO.grid_screens(f) for (key, _, f) in _DO.GRIDS)
const _DO_BOTH = Dict(k => _DO.simultaneous_rows(G) for (k, G) in _DO_G)
const _DO_SEQ = Dict(k => _DO.sequential_rows(G; both = _DO_BOTH[k]) for (k, G) in _DO_G)
const _DO_RESTORE = Dict(k => _DO.restore_rows(G) for (k, G) in _DO_G)

_do_pair(r) = "$(r.first)+$(r.second)"
_do_ord(r) = "$(r.first)→$(r.second)"
_do_row(grid, a, b) = only(r for r in _DO_BOTH[grid] if Set((r.first, r.second)) == Set((a, b)))
_do_seq(grid, a, b) = only(r for r in _DO_SEQ[grid] if (r.first, r.second) === (a, b))
_do_hz(x) = _DO._hz(x)
_do_judged(v) = v in (:pass, :fail, :pass_load_lost)
_do_live(side) = [p for p in side.pieces if p.kind === :live]

# Field by field, arrays element by element: two screens built from different models
# are distinct objects, so `isequal` on the structs would compare identities.
function _do_same(a, b; skip = ())
    typeof(a) === typeof(b) || return false
    a isa AbstractArray && return size(a) == size(b) && all(_do_same(x, y; skip) for (x, y) in zip(a, b))
    (a isa AbstractString || a isa Symbol || a isa Number || a === nothing) && return isequal(a, b)
    T = typeof(a)
    isstructtype(T) && fieldcount(T) > 0 || return isequal(a, b)
    return all(_do_same(getfield(a, f), getfield(b, f); skip) for f in fieldnames(T) if !(f in skip))
end

@testset "M10 step 6 — the report: every pair, both timings, per piece" begin

@testset "each column reads what its header says" begin
    for (key, G) in _DO_G
        nets = (; dc = G.net.cp, cp = G.net.cp, def = G.net.def)
        pair_screens = (; dc = G.dc, cp = G.ac.cp, def = G.ac.def)
        rows = _DO_BOTH[key]
        @test [(r.first, r.second) for r in rows] == [(G.dc.id[i], G.dc.id[j]) for (i, j) in G.dc.pairs]
        for (p, r) in pairs(rows), k in _DO.SIDES
            s, net = getfield(pair_screens, k), getfield(nets, k)
            side = getfield(r, k)
            @test [x.buses for x in side.pieces] == [pc.buses for pc in s.pieces[p]]
            @test [x.kind for x in side.pieces] == [pc.kind for pc in s.pieces[p]]
            @test [x.outcome for x in side.pieces] == [pc.outcome for pc in s.pieces[p]]
            @test isequal([x.Δf for x in side.pieces], [pc.Δω * net.f0 for pc in s.pieces[p]])
            @test [x.load_mw for x in side.pieces] == [pc.load_lost * net.S_base for pc in s.pieces[p]]
            @test r.same_as === s.same_as[p] && r.splits === s.splits[p]
        end
        @test [r.class.cp for r in rows] == G.cmp.cp.class
        @test [r.class.def for r in rows] == G.cmp.def.class
        seq = _DO_SEQ[key]
        @test [(r.first, r.second) for r in seq] == [(G.dcseq.id[a], G.dcseq.id[b]) for (a, b) in G.dcseq.pairs]
        for (p, r) in pairs(seq)
            @test r.dc.outcome === G.dcseq.outcome[p]
            @test r.cp.outcome === G.acseq.cp.outcome[p] && r.def.outcome === G.acseq.def.outcome[p]
            @test [x.buses for x in r.cp.pieces] == [pc.buses for pc in G.acseq.cp.pieces[p]]
        end
    end
end

@testset "DC is printed once because it reads no load model (D12.4)" begin
    for (key, G) in _DO_G
        @test _do_same(G.dc, dc_pair_outages(G.net.def))
        # The sequential screen keeps each restored piece's MODEL, whose loads are of the
        # load model asked for; every number in it is the same.
        d2 = dc_sequential_outages(G.net.def)
        @test _do_same(G.dcseq, d2; skip = (:restore,))
        @test all(_do_same(a, b; skip = (:models,)) for (a, b) in zip(G.dcseq.restore, d2.restore))
        # ...and the AC screens do read it: the anti-vacuity half.
        @test !_do_same(G.ac.cp, G.ac.def)
    end
end

@testset "the verdict per piece is M9's rule, and a name where there is none (D12.2)" begin
    lim = continental_europe_limits().settled
    for (key, G) in _DO_G, rows in (_DO_BOTH[key], _DO_SEQ[key]), r in rows, k in _DO.SIDES
        side = getfield(r, k)
        for p in side.pieces
            p.kind === :live || (@test p.verdict === :dead; continue)
            if p.verdict === :pass || p.verdict === :fail
                @test (abs(p.Δf) <= lim) == (p.verdict === :pass)
            else
                @test p.verdict in (:not_applicable, :restored, :no_value, :already_lost,
                                    :not_restored, :base_refused)
            end
        end
    end
    # A sequential pair with no state after both carries NO frequency: its pieces are the
    # state after the first loss, and a restored 0.0 there is not a settled value. (The
    # first version read it as a pass and compared it with both at once — found by
    # looking at the window, after these claims' numbers had passed.)
    for (key, rows) in _DO_SEQ, r in rows, k in _DO.SIDES
        side = getfield(r, k)
        side.outcome === :screened && continue
        @test isnan(side.worst) && side.verdict === side.outcome
        @test all(p -> p.verdict === side.outcome, _do_live(side))
        @test getfield(r.order, k) === :none
    end
    # ...and such sides exist at every fidelity, so the loop above is not empty.
    @test all(k -> any(r -> getfield(r, k).outcome !== :screened, _DO_SEQ[:case9]), _DO.SIDES)
    # Both at once: n/a exactly where two lines split nothing — and DC gives such a piece
    # exactly 0.0, AC NaN (M8's line convention), so the two cannot disagree on a number.
    for (key, rows) in _DO_BOTH, r in rows
        lines = r.first in [b.id for b in _DO_G[key].net.cp.branches] &&
                r.second in [b.id for b in _DO_G[key].net.cp.branches]
        na = lines && !r.splits
        @test all(p -> p.verdict === :not_applicable, _do_live(r.dc)) == na
        na && @test only(_do_live(r.dc)).Δf === 0.0 && isnan(only(_do_live(r.cp)).Δf)
    end
    # The pair's one verdict (D12.3, amended) on hand-built pieces: every branch of it.
    P(kind, verdict) = (; kind, verdict, Δf = verdict === :fail ? -0.3 : -0.1, load_mw = 0.0,
                        sources_mw = 0.0)
    @test _DO.pair_verdict([P(:live, :pass), P(:load_lost, :dead)]) === :pass_load_lost
    @test _DO.pair_verdict([P(:live, :pass), P(:sources_lost, :dead)]) === :pass
    @test _DO.pair_verdict([P(:live, :pass), P(:live, :fail), P(:load_lost, :dead)]) === :fail
    @test _DO.pair_verdict([P(:live, :fail), P(:live, :no_value)]) === :fail
    @test _DO.pair_verdict([P(:live, :pass), P(:live, :no_value)]) === :unjudged
    @test _DO.pair_verdict([P(:live, :pass), P(:live, :not_applicable)]) === :pass
    @test _DO.pair_verdict([P(:live, :not_applicable)]) === :not_applicable
    @test _DO.pair_verdict([P(:live, :pass)], :not_restored) === :not_restored
    # An answered AC piece with no Δf where one is owed is a broken contract, not a pass.
    bad = (; kind = :live, outcome = :secure, Δω = NaN)
    @test_throws ErrorException _DO.piece_verdict(bad, :ac, true, false, 50.0)
    @test _DO.piece_verdict(bad, :ac, false, false, 50.0) === :not_applicable
end

@testset "a piece the second loss never reaches is `restored`, not judged (D12.2)" begin
    # The report grids have no such piece (no single loss leaves two running pieces there,
    # D11.1), so the rule is checked on step 5's tie: two triangles joined by CD.
    tie(; loads = :constant_power) = _m10_tie()
    G = _DO.grid_screens(tie)
    seq = _DO.sequential_rows(G)
    row(a, b) = only(r for r in seq if (r.first, r.second) === (a, b))
    piece(side, b) = only(p for p in side.pieces if b in p.buses)
    for k in (:dc, :cp)
        r = row(:CD, :AB)                    # the left triangle loses a line and stays whole
        @test getfield(r, k).outcome === :screened
        @test piece(getfield(r, k), :D).verdict === :restored
        @test piece(getfield(r, k), :A).verdict === :not_applicable
        @test getfield(r, k).verdict === :not_applicable && isnan(getfield(r, k).worst)
        r = row(:CD, :G1)                    # the left triangle loses a generator
        @test piece(getfield(r, k), :D).verdict === :restored
        @test piece(getfield(r, k), :A).verdict in (:pass, :fail)
        @test getfield(r, k).worst === piece(getfield(r, k), :A).Δf
    end
    # The restored piece really is on target: its Δf is the restore's 0.0, not judged.
    @test piece(row(:CD, :G1).dc, :D).Δf === 0.0
end

@testset "lines and voltages beside the verdict, never in it (D13)" begin
    for (key, G) in _DO_G
        net = G.net.cp
        both = _DO_BOTH[key]
        for (p, r) in pairs(both)
            # DC, both at once: the pair comparison's own DC outcome, refusals :none.
            d = G.cmp.cp.dc_outcome[p]
            @test r.dc.lines === (d in (:secure, :overload) ? d : :none)
            for k in (:cp, :def)
                side, c = getfield(r, k), getfield(G.cmp, k)
                o = side.lines in (:overload, :overload_voltage)
                v = side.lines in (:voltage, :overload_voltage)
                @test o == !isempty(c.ac_over[p])
                @test v == any(pc -> pc.kind === :live && pc.outcome === :voltage,
                               getfield(G.ac, k).pieces[p])
            end
        end
        # DC, one after the other: the flows against the ratings, read here from the
        # equipment list (not through M8's helper), where every running piece answered.
        for (p, r) in pairs(_DO_SEQ[key])
            if r.dc.outcome !== :screened
                @test r.dc.lines === :none && r.cp.lines === :none && r.def.lines === :none
                continue
            end
            answered = all(x -> x.kind !== :live || x.outcome in (:shared, :restored),
                           G.dcseq.pieces[p])
            over = any(abs(G.dcseq.flow[p][e]) * net.S_base > b.rating
                       for (e, b) in pairs(net.branches))
            @test r.dc.lines === (answered ? (over ? :overload : :secure) : :none)
        end
    end
    # The rule's names, every one, on hand-built pieces (VO occurs on neither grid).
    P(o) = (; kind = :live, outcome = o)
    @test _DO.ac_lines([P(:voltage), P(:overload)]) === :overload_voltage
    @test _DO.ac_lines([P(:secure), P(:no_solution)]) === :none
    @test _DO.ac_lines([P(:voltage), P(:no_solution)]) === :voltage
    @test _DO.ac_lines([P(:secure), (; kind = :load_lost, outcome = :load_lost)]) === :secure
    @test _DO._mk((; lines = :overload_voltage)) == " [VO]" && _DO._mk((; lines = :none)) == ""
    # The note's example, printed: green in frequency, marked V.
    t = sprint(_DO.print_simultaneous, "case9", _DO_BOTH[:case9])
    @test occursin("L14+L45   | verdict: DC FAIL, AC cp FAIL [V], AC def pass [V]", t)
    @test occursin("L56+L82   | verdict: DC FAIL [O], AC cp FAIL [O], AC def FAIL [O]", t)
    @test occursin("[V] / [O] / [VO]", sprint(_DO.print_header))
end

@testset "claim r: green is frequency only, and the markers show what it leaves out" begin
    c9 = _DO_BOTH[:case9]
    marked(k) = count(r -> getfield(r, k).verdict === :pass && getfield(r, k).lines === :voltage, c9)
    passed(k) = count(r -> getfield(r, k).verdict === :pass, c9)
    @test (marked(:def), passed(:def)) == (18, 20)
    @test (marked(:cp), passed(:cp)) == (3, 5)
    @test !any(getfield(r, k).verdict === :pass && getfield(r, k).lines !== :secure
               for r in _DO_BOTH[:mesh] for k in _DO.SIDES)
    @test count(r -> r.dc.lines === :overload, c9) == 20
    @test count(r -> r.cp.lines === :overload, c9) == 2 && count(r -> r.def.lines === :overload, c9) == 2
end

@testset "the preset's caveat is printed with the verdicts, and repeated with the claims" begin
    h = sprint(_DO.print_header)
    c = sprint(_DO.print_claims)
    flat(s) = join(split(s), " ")
    @test occursin(flat(_DO.CAVEAT), flat(h))
    for t in (h, c)
        @test occursin("DESIGN VALUE", t)
        @test occursin("not a pass/fail rule for one outage on a small grid", flat(t))
    end
    @test occursin("settled 0.2 Hz", h) && continental_europe_limits().settled == 0.2
    # Every table prints the pair's verdict per side, and its dead pieces' MW.
    t = sprint(_DO.print_simultaneous, "case9", _DO_BOTH[:case9])
    @test occursin("L45+L56   | verdict: DC FAIL, AC cp FAIL, AC def FAIL", t)
    @test occursin("dead: {B5} LOAD LOST 90.0 MW (AC 90.0 / 90.0)", t)
end

@testset "claim k: where the grid splits, and who is left in the dark" begin
    c9, me = _DO_BOTH[:case9], _DO_BOTH[:mesh]
    @test length(c9) == 66 && count(r -> r.splits, c9) == 45
    @test sort([_do_pair(r) for r in c9 if r.same_as !== :none]) == ["L14+G1", "L36+G3", "L82+G2"]
    @test all(r -> r.splits, (r for r in c9 if r.same_as !== :none))
    two = [r for r in c9 if length(_do_live(r.dc)) == 2]
    @test [_do_pair(r) for r in two] == ["L45+L67", "L45+L78", "L45+L89", "L56+L78", "L56+L89",
                                         "L56+L94", "L67+L89", "L67+L94", "L78+L94"]
    for r in two, k in (:dc, :cp)
        @test sort(sign.([p.Δf for p in _do_live(getfield(r, k))])) == [-1.0, 1.0]
    end
    for r in two
        s = sort(sign.([p.Δf for p in _do_live(r.def)]))
        @test s == (_do_pair(r) == "L78+L94" ? [1.0, 1.0] : [-1.0, 1.0])
    end
    dark = [r for r in c9 if any(p -> p.kind === :load_lost, r.dc.pieces)]
    @test [_do_pair(r) for r in dark] == ["L45+L56", "L67+L78", "L89+L94"]
    for (r, bus, mw, hz) in zip(dark, (:B5, :B7, :B9), (90.0, 100.0, 125.0),
                                ("+0.2613", "+0.2904", "+0.3630"))
        for k in _DO.SIDES
            d = only(p for p in getfield(r, k).pieces if p.kind === :load_lost)
            @test d.buses == [bus] && round(d.load_mw; digits = 1) == mw
            @test getfield(r, k).verdict === :fail && getfield(r, k).worst > 0
        end
        @test _do_hz(r.dc.worst) == hz
    end
    # No pair anywhere is "pass, LOAD LOST": the amber rule guards a case not reached here.
    @test !any(getfield(r, k).verdict === :pass_load_lost
               for g in (:case9, :mesh) for rows in (_DO_BOTH[g], _DO_SEQ[g]) for r in rows
               for k in _DO.SIDES)
    @test length(me) == 45 && [_do_pair(r) for r in me if r.splits] == ["AB+AC", "DE+BE"]
    for (pair, bus) in (("AB+AC", :A), ("DE+BE", :E))
        r = only(x for x in me if _do_pair(x) == pair)
        @test only(p for p in r.dc.pieces if p.kind !== :live).buses == [bus]
        @test only(p for p in r.dc.pieces if p.kind !== :live).kind === :sources_lost
    end
end

@testset "claim l: nearly every pair fails; on the mesh what passes sits close" begin
    c9, me = _DO_BOTH[:case9], _DO_BOTH[:mesh]
    passes(rows, k) = [_do_pair(r) for r in rows if getfield(r, k).verdict === :pass]
    five = ["L45+L67", "L56+L78", "L56+L94", "L67+L89", "L78+L94"]
    @test passes(c9, :dc) == five && passes(c9, :cp) == five
    # ...well inside the limit on case9 — "close to the limit" is the mesh's alone.
    w5 = [abs(_do_row(:case9, Symbol.(split(p, "+"))...).dc.worst) for p in five]
    @test _do_hz(minimum(w5)) == "+0.0328" && _do_hz(maximum(w5)) == "+0.1210"
    @test all(p -> length(_do_live(_do_row(:case9, Symbol.(split(p, "+"))...).dc)) == 2, five)
    @test length(passes(c9, :def)) == 20
    @test count(r -> r.dc.verdict === :fail, c9) == 61
    @test all(k -> count(r -> getfield(r, k).verdict === :not_applicable, me) == 19, _DO.SIDES)
    eight = ["AB+G3", "AC+G3", "BC+G3", "BD+G3", "CD+G3", "DE+BE", "DE+G3", "BE+G3"]
    @test sort(passes(me, :dc)) == sort(eight) && sort(passes(me, :def)) == sort(eight)
    @test isempty(passes(me, :cp))
    rs = [only(r for r in me if _do_pair(r) == p) for p in eight]
    @test all(r -> _do_hz(r.dc.worst) == "-0.1932", rs)
    @test all(r -> r.cp.verdict === :fail, rs)
    @test _do_hz(maximum(r.cp.worst for r in rs)) == "-0.2025"
    @test _do_hz(minimum(r.cp.worst for r in rs)) == "-0.2475"
    # "G3 lost with any line": every one of the seven lines, once.
    @test sort([p for p in eight if endswith(p, "+G3")]) ==
          sort(["$(b.id)+G3" for b in _DO_G[:mesh].net.cp.branches])
end

@testset "claim m: where AC finds no operating point" begin
    c9 = _DO_BOTH[:case9]
    G = _DO_G[:case9]
    gens = Set(m.id for m in G.net.cp.machines)
    bridges = Set(G.net.cp.branches[e].id for (e, mid) in pairs(lone_source_bridges(G.net.cp).machine)
                  if mid !== :none)
    @test bridges == Set([:L14, :L36, :L82])
    un = [r for r in c9 if r.cp.verdict === :unjudged]
    @test length(un) == 24
    @test all(r -> any(x -> x in gens || x in bridges, (r.first, r.second)), un)
    @test all(r -> all(p -> p.outcome === :no_solution, filter(p -> p.verdict === :no_value, r.cp.pieces)), un)
    @test !any(r -> r.def.verdict === :unjudged, c9)
    @test !any(getfield(r, k).verdict === :unjudged for r in _DO_BOTH[:mesh] for k in _DO.SIDES)
end

@testset "claim n: DC against AC, both at once" begin
    differ(rows, k) = [r for r in rows if _do_judged(r.dc.verdict) &&
                       _do_judged(getfield(r, k).verdict) && r.dc.verdict !== getfield(r, k).verdict]
    c9 = _DO_BOTH[:case9]
    @test isempty(differ(c9, :cp))
    d = differ(c9, :def)
    @test length(d) == 17
    @test count(r -> r.dc.verdict === :fail && r.def.verdict === :pass, d) == 16
    other = only(r for r in d if r.dc.verdict === :pass)
    @test _do_pair(other) == "L45+L67" && other.def.verdict === :fail
    @test _do_hz(other.dc.worst) == "+0.1210" && _do_hz(other.def.worst) == "+0.2247"
    r = _do_row(:case9, :L14, :L56)
    @test _do_hz(r.dc.worst) == "-0.4012" && _do_hz(r.def.worst) == "-0.0083"
    me = _DO_BOTH[:mesh]
    @test sort([_do_pair(r) for r in differ(me, :cp)]) ==
          sort(["AB+G3", "AC+G3", "BC+G3", "BD+G3", "CD+G3", "DE+BE", "DE+G3", "BE+G3"])
    @test isempty(differ(me, :def))
end

@testset "claim o: what the second loss starts from" begin
    rc, rm = _DO_RESTORE[:case9], _DO_RESTORE[:mesh]
    @test all(r -> r.dc.outcomes == [:restored], rc)
    @test all(r -> r.dc.outcomes == (r.id === :G1 ? [:restore_refused] : [:restored]), rm)
    mesh = _DO_G[:mesh].net.cp
    mc(id) = only(m for m in mesh.machines if m.id === id)
    @test mc(:G1).P0 == 150.0 && (mc(:G2).Pmax - mc(:G2).P0) + (mc(:G3).Pmax - mc(:G3).P0) == 45.0
    for k in _DO.SIDES
        @test count(r -> r.first === :G1 && getfield(r, k).outcome === :not_restored, _DO_SEQ[:mesh]) == 9
        @test count(r -> getfield(r, k).outcome === :not_restored, _DO_SEQ[:mesh]) == 9
        @test only(r for r in rm if r.id === :G2) |> r -> getfield(r, k).capped == [:G3]
    end
    voltage(k) = Set(r.id for r in rc if getfield(r, k).outcomes == [:voltage])
    @test voltage(:cp) == Set([:L14, :L45, :L94, :G1]) && voltage(:def) == Set([:L14, :L94, :G1])
    for (k, n, firsts) in ((:cp, 43, voltage(:cp)), (:def, 32, voltage(:def)))
        nr = [r for r in _DO_SEQ[:case9] if getfield(r, k).outcome === :not_restored]
        @test length(nr) == n && Set(r.first for r in nr) == firsts
    end
    @test length(_DO_SEQ[:case9]) == 132
end

@testset "claim p: in DC the order never moves the worst piece" begin
    G = _DO_G[:case9]
    for (grid, nsame) in ((:case9, 90), (:mesh, 29))
        seq = _DO_SEQ[grid]
        @test count(r -> r.order.dc === :same, seq) == nsame
        @test !any(r -> r.order.dc === :worse, seq)
        mild = [r for r in seq if r.order.dc === :milder]
        @test [_do_ord(r) for r in mild] == (grid === :case9 ? ["G1→L14", "G2→L82", "G3→L36"] : String[])
        for r in mild
            @test _do_hz(abs(r.dc.worst)) == "+0.0000" && r.dc.verdict === :pass
            # The line is the generator's own bridge: it cuts off one bus, now empty.
            @test only(p for p in r.dc.pieces if p.kind !== :live).kind === :empty
            @test _do_row(grid, r.first, r.second).same_as === r.first
        end
        # Why: a first line restores nothing unless it IS a generator's outage...
        S = _DO_G[grid].dcseq
        m = length(_DO_G[grid].net.cp.branches)
        moved = [S.id[a] for a in 1:m if any(!=(0.0), S.restore[a].pickup)]
        @test moved == (grid === :case9 ? [:L14, :L36, :L82] : Symbol[])
        # ...and every pair that starts with a generator and lands where both at once does
        # ends with a governor at its cap.
        for (p, (a, b)) in pairs(S.pairs)
            (a > m && seq[p].order.dc === :same) || continue
            @test any(S.capped[p])
        end
    end
    # The control: the same rule finds AC orders that DO differ (claim q).
    @test count(r -> r.order.cp === :milder, _DO_SEQ[:case9]) > 0
end

@testset "claim q: in AC the order matters, and which way follows the load model" begin
    cnt(grid, k, o) = count(r -> getfield(r.order, k) === o, _DO_SEQ[grid])
    @test (cnt(:case9, :cp, :milder), cnt(:case9, :cp, :worse)) == (28, 10)
    @test (cnt(:mesh, :cp, :milder), cnt(:mesh, :cp, :worse)) == (18, 0)
    @test (cnt(:case9, :def, :worse), cnt(:case9, :def, :milder)) == (48, 25)
    @test (cnt(:mesh, :def, :worse), cnt(:mesh, :def, :milder)) == (16, 2)
    flips(grid, k) = count(_DO_SEQ[grid]) do r
        a = getfield(r, k).verdict
        b = getfield(_do_row(grid, r.first, r.second), k).verdict
        _do_judged(a) && _do_judged(b) && a !== b
    end
    @test (flips(:case9, :cp), flips(:case9, :def), flips(:mesh, :cp), flips(:mesh, :def)) == (2, 6, 2, 0)
    function split_orders(grid, k)
        out = String[]
        for r in _DO_SEQ[grid]
            r.first < r.second || continue
            o = _do_seq(grid, r.second, r.first)
            a, b = getfield(r, k).verdict, getfield(o, k).verdict
            _do_judged(a) && _do_judged(b) && a !== b && push!(out, "$(r.first)/$(r.second)")
        end
        return out
    end
    @test split_orders(:case9, :def) == ["L45/L67"] && isempty(split_orders(:case9, :cp))
    @test split_orders(:mesh, :cp) == ["BE/DE"] && isempty(split_orders(:mesh, :def))
    a, b = _do_seq(:case9, :L45, :L67), _do_seq(:case9, :L67, :L45)
    @test (a.def.verdict, _do_hz(a.def.worst)) == (:pass, "+0.1986")
    @test (b.def.verdict, _do_hz(b.def.worst)) == (:fail, "+0.2100")
    a, b = _do_seq(:mesh, :DE, :BE), _do_seq(:mesh, :BE, :DE)
    @test (a.cp.verdict, _do_hz(a.cp.worst)) == (:pass, "-0.1970")
    @test (b.cp.verdict, _do_hz(b.cp.worst)) == (:fail, "-0.2026")
    # The largest move, among pairs with a number in both timings.
    moves = [(abs(getfield(r, k).worst - getfield(_do_row(g, r.first, r.second), k).worst), g, k, r)
             for g in (:case9, :mesh) for k in _DO.SIDES for r in _DO_SEQ[g]
             if !isnan(getfield(r, k).worst) && !isnan(getfield(_do_row(g, r.first, r.second), k).worst)]
    _, g, k, r = moves[argmax([x[1] for x in moves])]
    @test (g, k, _do_ord(r)) == (:case9, :def, "L82→G3")
    @test _do_hz(r.def.worst) == "-3.9910" && _do_hz(_do_row(:case9, :L82, :G3).def.worst) == "-1.5036"
end

end
