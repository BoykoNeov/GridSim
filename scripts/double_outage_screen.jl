# Double-outage screening, reported: every pair of elements of two grids — two lines, two
# generators, one of each — lost at once, and lost one after the other with frequency
# restored to 50 Hz in between, at both fidelities, a grid that splits answered piece by
# piece, the settled frequency of every live piece judged against the one sourced preset.
#
#   julia --project=. scripts/double_outage_screen.jl
#
# Plan + decisions: docs/plans/m10-plan.md step 6, docs/plans/m10-context.md D2–D4, D11,
# D12 (how a piece is judged, and the one colour per pair the window paints).
#
# THE GRIDS ARE M8's REPORT GRIDS, NOT A COPY. `scripts/outage_screen.jl` is included
# into a submodule of its own (`Single`): its fixtures are the ones every M8/M9 number was
# read on, and keeping it in its own module means none of its names is redefined here.
#
# WHAT IS NEW AGAINST THE SINGLE-OUTAGE REPORT, in one paragraph each:
#
#   PIECES. A pair can cut the grid. Each part left with a generator AND a load settles at
#   its own frequency, from its own governors (the user's choice, D2.3); a part with no
#   generator is LOAD LOST (its customers are in the dark); a part with no load is its
#   SOURCES LOST. case9 is a ring with three generators on spurs, so 45 of its 66 pairs
#   split it; the mesh splits on 2 of 45.
#
#   TWO TIMINGS (the user's choice, D2.1). "Both at once" is one event. "One after the
#   other" loses the first, restores 50 Hz in every live part (each unit taking extra
#   output in proportion to its governor gain, up to its limit — D3), and only then loses
#   the second. A restore can be refused (not enough headroom left), and in AC a restored
#   state can sit outside the voltage band, so some ordered pairs have no state after both.
#
#   THE VERDICT (D12). M9's settled rule per live piece, `|Δf| ≤ 0.2 Hz`, at each fidelity.
#   A piece with nothing to judge says why: `dead`, `n/a` (the event lost no generation and
#   split nothing — M9 D4's rule for a line), `restored` (untouched by the second loss),
#   `no value` (the screen refused or found no operating point).
#
# DC READS NO LOAD MODEL: its loads are fixed powers either way. So DC is printed once per
# grid, beside AC on both load models (a test asserts the two DC screens are the same).

using GridSim
using Printf

module Single
# The single-outage report, verbatim — see the header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "outage_screen.jl"))
end

const GRIDS = [(:case9, "case9 (no line charging, invented droop)", Single.case9),
               (:mesh, "mesh (invented, M8 step 5's fixture)", Single.mesh)]
# The three columns every table prints: DC once, AC on each load model.
const SIDES = (:dc, :cp, :def)
const SIDE_NAMES = Dict(:dc => "DC", :cp => "AC, constant-power loads",
                        :def => "AC, default loads")

# The preset's caveat, printed with every verdict here and drawn in the window beside them
# (`test/m10_report.jl` asserts both). M9's wording, for pieces.
const CAVEAT = "Limits: continental_europe_limits() — settled 0.2 Hz, from SO GL Annex III " *
    "Table 1. THESE ARE DESIGN VALUES for a whole synchronous area after its 3,000 MW " *
    "reference incident, not a pass/fail rule for one outage on a small grid — and a " *
    "split piece of case9 is smaller still. With the invented droop and damping here, a " *
    "pass or a FAIL describes that droop, not whether a real grid survives. Only the " *
    "settled value is judged: no dip or rate per pair (m10-context.md D5)."

# ---------------------------------------------------------------------------
# The screens of one grid
# ---------------------------------------------------------------------------

"""
    grid_screens(f) -> NamedTuple

Every screen the report reads for one grid constructor `f` (`Single.case9`, `Single.mesh`):
the models on both load models (`net.cp`, `net.def`), the DC pair and sequential screens
(once — DC reads no load model), and the AC ones per load model, with the DC/AC comparison.
"""
function grid_screens(f)
    cp, def = f(; loads = :constant_power), f(; loads = :default)
    dc, dcseq = dc_pair_outages(cp), dc_sequential_outages(cp)
    ac = (; cp = ac_pair_outages(cp), def = ac_pair_outages(def))
    acseq = (; cp = ac_sequential_outages(cp), def = ac_sequential_outages(def))
    cmp = (; cp = compare_pair_screens(cp, dc, ac.cp),
           def = compare_pair_screens(def, dc_pair_outages(def), ac.def))
    return (; net = (; cp, def), dc, dcseq, ac, acseq, cmp)
end

# ---------------------------------------------------------------------------
# The verdict per piece and per pair (D12)
# ---------------------------------------------------------------------------

const _LIM = continental_europe_limits()

# One piece at one fidelity: `applicable` is false where the event lost no generation and
# left the piece whole (D12.2), `untouched` where the second loss of a sequential pair did
# not reach it. AC's answered outcomes with no `Δω` outside those shapes throw, as M9's.
function piece_verdict(pc, fid::Symbol, applicable::Bool, untouched::Bool, f0::Float64)
    pc.kind === :live || return :dead
    untouched && return :restored
    applicable || return :not_applicable
    has = fid === :dc ? pc.outcome === :shared : pc.outcome in (:secure, :overload, :voltage)
    return GridSim._settled_verdict(pc.Δω * f0, has, _LIM.settled, "$fid piece")
end

"""
    piece_side(pc, fid, applicable, untouched, net) -> NamedTuple

One piece as the report prints it at one fidelity: its buses and kind, the screen's outcome,
`Δf` (Hz, signed; `NaN` where the screen has none), the verdict (D12.2), and what a dead
piece takes with it (`load_mw`, `sources_mw`).
"""
function piece_side(pc, fid::Symbol, applicable::Bool, untouched::Bool, net::NetworkModel;
                    verdict::Union{Symbol,Nothing} = nothing)
    v = verdict === nothing || pc.kind !== :live ? piece_verdict(pc, fid, applicable, untouched, net.f0) :
        verdict
    return (; buses = pc.buses, kind = pc.kind, outcome = pc.outcome, Δf = pc.Δω * net.f0,
            verdict = v,
            load_mw = pc.load_lost * net.S_base, sources_mw = pc.sources_lost * net.S_base)
end

"""
    pair_verdict(pieces, outcome = :screened) -> Symbol

The one verdict a pair gets at one fidelity (D12.3, amended): `:fail` if any live piece
fails; else `:pass` where every live piece passes or has nothing to judge (`n/a`,
`restored`) and at least one passes — `:pass_load_lost` instead where a piece is load lost;
`:not_applicable` where nothing is judged and nothing failed to be; `:unjudged` where a live
piece has no value. A sequential pair with no state after both losses gets its outcome
(`:already_lost`, `:not_restored`, `:base_refused`).
"""
function pair_verdict(pieces, outcome::Symbol = :screened)
    outcome === :screened || return outcome
    vs = [p.verdict for p in pieces if p.kind === :live]
    any(==(:fail), vs) && return :fail
    any(==(:no_value), vs) && return :unjudged
    any(==(:pass), vs) || return :not_applicable
    return any(p -> p.kind === :load_lost, pieces) ? :pass_load_lost : :pass
end

# The judged live piece furthest from nominal, `Δf` Hz, signed; `NaN` where none is judged.
function worst_Δf(pieces)
    xs = [p.Δf for p in pieces if p.verdict === :pass || p.verdict === :fail]
    return isempty(xs) ? NaN : xs[argmax(abs.(xs))]
end

_side(pieces, outcome::Symbol = :screened) =
    (; outcome, pieces, verdict = pair_verdict(pieces, outcome),
     worst = outcome === :screened ? worst_Δf(pieces) : NaN,
     load_mw = sum((p.load_mw for p in pieces); init = 0.0),
     sources_mw = sum((p.sources_mw for p in pieces); init = 0.0))

# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

"""
    simultaneous_rows(G = grid_screens(f)) -> Vector{NamedTuple}

One row per unordered pair, in the screens' order: the two element ids (`first`,
`second`), `same_as` (the machine whose single outage the pair IS, or `:none`), `splits`,
the DC/AC comparison's class per load model (`class.cp`, `class.def`), and per side
(`dc`, `cp`, `def`) the pieces (`piece_side`) and the pair's verdict, worst `Δf` and MW
lost.
"""
function simultaneous_rows(G)
    dc, net = G.dc, G.net
    m = length(net.cp.branches)
    rows = NamedTuple[]
    for (p, (i, j)) in pairs(dc.pairs)
        # A pair of lines that splits nothing lost no generation (D12.2).
        applicable = dc.splits[p] || i > m || j > m
        side(fid, pcs, n) = _side([piece_side(pc, fid, applicable, false, n) for pc in pcs])
        push!(rows, (; first = dc.id[i], second = dc.id[j], same_as = dc.same_as[p],
                     splits = dc.splits[p],
                     class = (; cp = G.cmp.cp.class[p], def = G.cmp.def.class[p]),
                     dc = side(:dc, dc.pieces[p], net.cp),
                     cp = side(:ac, G.ac.cp.pieces[p], net.cp),
                     def = side(:ac, G.ac.def.pieces[p], net.def)))
    end
    return rows
end

# The sequential pieces of ordered pair `p` at one fidelity, judged: which are untouched
# by the second loss, and whether the second loss was a line that left its piece whole.
function _sequential_side(s, p::Int, fid::Symbol, net::NetworkModel)
    a, b = s.pairs[p]
    # No state after both: the pieces are the state after the FIRST loss, and a running
    # one carries the pair's outcome as its verdict — never a pass read off a restored
    # 0.0 that the second loss never reached.
    s.outcome[p] === :screened ||
        return _side([piece_side(pc, fid, true, false, net; verdict = s.outcome[p])
                      for pc in s.pieces[p]], s.outcome[p])
    rs = s.restore[a]
    c = GridSim._element_piece(net, s.kind, b, rs.pieces)
    hit = Set(rs.pieces[c].buses)
    touched = [issubset(pc.buses, hit) for pc in s.pieces[p]]
    applicable = !(s.kind[b] === :branch && count(touched) == 1)
    return _side([piece_side(pc, fid, applicable, !touched[k], net)
                  for (k, pc) in pairs(s.pieces[p])])
end

"""
    sequential_rows(G = grid_screens(f); both = simultaneous_rows(G)) -> Vector{NamedTuple}

One row per ordered pair (`first` lost, 50 Hz restored, then `second`), in the screens'
order: per side (`dc`, `cp`, `def`) the outcome (`:screened`, `:already_lost`,
`:not_restored`, `:base_refused`), the pieces after both, the pair's verdict, worst `Δf`
and MW lost; and `order` per side — `:milder`, `:same` or `:worse` than both at once, by the
worst judged piece (`:none` where either has no judged piece).
"""
function sequential_rows(G; both = simultaneous_rows(G))
    s = G.dcseq
    bi = Dict((r.first, r.second) => r for r in both)
    rows = NamedTuple[]
    for (p, (a, b)) in pairs(s.pairs)
        x, y = s.id[a], s.id[b]
        r2 = get(bi, (x, y), get(bi, (y, x), nothing))
        sd = (; dc = _sequential_side(s, p, :dc, G.net.cp),
              cp = _sequential_side(G.acseq.cp, p, :ac, G.net.cp),
              def = _sequential_side(G.acseq.def, p, :ac, G.net.def))
        order = NamedTuple{SIDES}(Tuple(_order(getfield(sd, k).worst, getfield(r2, k).worst)
                                        for k in SIDES))
        push!(rows, (; first = x, second = y, sd..., order))
    end
    return rows
end

function _order(seq::Float64, both::Float64)
    (isnan(seq) || isnan(both)) && return :none
    abs(abs(seq) - abs(both)) <= 1e-9 * max(abs(seq), abs(both)) + 1e-12 && return :same
    return abs(seq) < abs(both) ? :milder : :worse
end

"""
    restore_rows(G = grid_screens(f)) -> Vector{NamedTuple}

One row per element: the grid after it alone, frequency restored (D3, D11), per side — the
outcome of each live piece, the units at their ceiling, and the units pushed below zero.
"""
function restore_rows(G)
    s = G.dcseq
    rows = NamedTuple[]
    for (e, id) in pairs(s.id)
        side(rs, ids) = (; outcomes = [pc.outcome for pc in rs.pieces if pc.kind === :live],
                         capped = ids[rs.capped], below_zero = rs.below_zero)
        push!(rows, (; id, dc = side(s.restore[e], G.dc.responders),
                     cp = side(G.acseq.cp.restore[e], G.ac.cp.responders),
                     def = side(G.acseq.def.restore[e], G.ac.def.responders)))
    end
    return rows
end

# ---------------------------------------------------------------------------
# Printing
# ---------------------------------------------------------------------------

const VERDICT_TEXT = Dict(:pass => "pass", :fail => "FAIL", :dead => "dead",
                          :not_applicable => "n/a", :restored => "restored",
                          :no_value => "no value", :pass_load_lost => "pass, LOAD LOST",
                          :unjudged => "unjudged", :already_lost => "already lost",
                          :not_restored => "not restored", :base_refused => "base refused")
_t(v::Symbol) = get(VERDICT_TEXT, v, String(v))
_hz(x) = isnan(x) ? "—" : @sprintf("%+.4f", x)
_buses(bs) = join(bs, ",")
_pair(r, sep) = "$(r.first)$(sep)$(r.second)"

function _piece_cell(p)
    p.kind === :live || return ""
    p.verdict in (:pass, :fail) && return @sprintf("%s %-4s %s", _hz(p.Δf), _t(p.verdict), p.outcome)
    return "$(_t(p.verdict)) ($(p.outcome))"
end

function _dead_text(r)
    out = String[]
    for (i, p) in pairs(r.dc.pieces)
        p.kind === :live && continue
        what = p.kind === :load_lost ? "LOAD LOST" : p.kind === :sources_lost ? "sources lost" : "empty"
        mw = p.kind === :load_lost ? (p.load_mw, r.cp.pieces[i].load_mw, r.def.pieces[i].load_mw) :
             (p.sources_mw, r.cp.pieces[i].sources_mw, r.def.pieces[i].sources_mw)
        push!(out, @sprintf("{%s} %s %.1f MW (AC %.1f / %.1f)", _buses(p.buses), what, mw...))
    end
    return join(out, "; ")
end

function print_simultaneous(io::IO, name, rows)
    n, ns = length(rows), count(r -> r.splits, rows)
    println(io, "\n### $name — $n pairs, $ns split the grid")
    @printf(io, "%-9s | %-26s | %-27s | %-27s | %-27s\n", "pair", "live piece (buses)",
            "DC  Δf Hz", "AC cp  Δf Hz", "AC def  Δf Hz")
    for r in rows
        tag = r.same_as === :none ? "" : "  = losing $(r.same_as) (one outage, D4)"
        if all(k -> getfield(r, k).verdict === :not_applicable, SIDES) && isempty(_dead_text(r))
            @printf(io, "%-9s | n/a: two lines, grid whole (AC cp %s, AC def %s)\n", _pair(r, "+"),
                    only(r.cp.pieces).outcome, only(r.def.pieces).outcome)
            continue
        end
        @printf(io, "%-9s | verdict: DC %s, AC cp %s, AC def %s%s\n", _pair(r, "+"),
                _t(r.dc.verdict), _t(r.cp.verdict), _t(r.def.verdict), tag)
        for (i, p) in pairs(r.dc.pieces)
            p.kind === :live || continue
            @printf(io, "%-9s | %-26s | %-27s | %-27s | %-27s\n", "", _buses(p.buses),
                    _piece_cell(p), _piece_cell(r.cp.pieces[i]), _piece_cell(r.def.pieces[i]))
        end
        d = _dead_text(r)
        isempty(d) || @printf(io, "%-9s | dead: %s\n", "", d)
    end
end

function print_restores(io::IO, name, rows)
    println(io, "\n### $name — the grid after each single loss, 50 Hz restored")
    @printf(io, "%-5s | %-34s | %-34s | %-34s\n", "lost", "DC", "AC cp", "AC def")
    cell(x) = join(String.(x.outcomes), ",") *
              (isempty(x.capped) ? "" : "; at ceiling " * join(x.capped, ",")) *
              (isempty(x.below_zero) ? "" : "; BELOW ZERO " * join(x.below_zero, ","))
    for r in rows
        @printf(io, "%-5s | %-34s | %-34s | %-34s\n", r.id, cell(r.dc), cell(r.cp), cell(r.def))
    end
end

function print_sequential(io::IO, name, rows)
    println(io, "\n### $name — $(length(rows)) ordered pairs (first lost, 50 Hz restored, then second)")
    @printf(io, "%-10s | %-36s | %-36s | %-36s\n", "order", "DC: worst Δf Hz, vs both at once",
            "AC cp", "AC def")
    function cell(x, o)
        x.outcome === :screened || return _t(x.outcome)
        return @sprintf("%s %s%s", _hz(x.worst), _t(x.verdict),
                        o === :none ? "" : ", $(o)")
    end
    for r in rows
        @printf(io, "%-10s | %-36s | %-36s | %-36s\n", _pair(r, "→"), cell(r.dc, r.order.dc),
                cell(r.cp, r.order.cp), cell(r.def, r.order.def))
    end
end

# `s` wrapped at `w` columns, each line indented by `ind`.
function _wrap(s::AbstractString, w::Int = 88, ind::AbstractString = " ")
    lines, cur = String[], ""
    for word in split(s)
        if !isempty(cur) && length(cur) + 1 + length(word) > w - length(ind)
            push!(lines, ind * cur)
            cur = String(word)
        else
            cur = isempty(cur) ? String(word) : cur * " " * word
        end
    end
    isempty(cur) || push!(lines, ind * cur)
    return join(lines, "\n")
end

function print_header(io::IO = stdout)
    println(io, """
Double-outage screening (M10 step 6): every pair of elements, at once and one after the
other, DC and AC, a split grid answered piece by piece
""")
    println(io, _wrap(CAVEAT))
    println(io, """

 DC reads no load model, so it is printed once; AC is printed on both load models. A
 piece's verdict: its settled Δf against 0.2 Hz, or why it has none — dead (no generator
 or no load: no frequency), n/a (the event lost no generation and split nothing),
 restored (the second loss did not reach it), no value (the screen refused or found no
 operating point). A pair's verdict: FAIL if any live piece fails; pass if every live
 piece passes or has nothing to judge — "pass, LOAD LOST" where customers are cut off;
 unjudged where a live piece has no value. Lost MW: DC (AC constant power / default).""")
end

# How many pairs got each verdict, per side.
function print_tally(io::IO, rows)
    for k in SIDES
        vs = [getfield(r, k).verdict for r in rows]
        println(io, "  ", rpad(SIDE_NAMES[k] * ":", 26),
                join(["$(_t(v)) $(count(==(v), vs))" for v in sort!(unique(vs))], ", "))
    end
end

function main()
    print_header()
    reports = [(name, G, simultaneous_rows(G)) for (_, name, f) in GRIDS for G in (grid_screens(f),)]
    println("\n== 1. Both at once ==")
    for (name, G, both) in reports
        print_simultaneous(stdout, name, both)
        print_tally(stdout, both)
    end
    println("\n== 2. One loss, then 50 Hz restored (what the second loss starts from) ==")
    for (name, G, _) in reports
        print_restores(stdout, name, restore_rows(G))
    end
    println("\n== 3. One after the other ==")
    for (name, G, both) in reports
        seq = sequential_rows(G; both)
        print_sequential(stdout, name, seq)
        print_tally(stdout, seq)
    end
    print_claims()
end

# Written AFTER sections 1–3 were read, each asserted in `test/m10_report.jl` at the
# precision it prints. The probes the claims rest on are in docs/evidence/gridsim-m10/step6/.
function print_claims(io::IO = stdout)
    println(io, """

== 4. What the tables say (each asserted in test/m10_report.jl) ==

 Every verdict below is judged against the preset and carries the caveat above: its
 number is a DESIGN VALUE for a whole synchronous area after a 3,000 MW incident, not a
 pass/fail rule for one outage on a small grid.

 k. Where the grid splits, and who is left in the dark. 45 of case9's 66 pairs split it
    (three of them are one outage under two names: a generator and the line it hangs on).
    Nine leave two running pieces, and in DC and in AC on constant-power loads each of
    the nine has one piece running fast and one slow; on the default loads L78+L94 has
    both fast. Three strand customers — L45+L56 (B5, 90 MW), L67+L78 (B7, 100 MW) and
    L89+L94 (B9, 125 MW) — and each FAILS at every fidelity, because the rest of the grid
    runs FAST (+0.2613, +0.2904, +0.3630 Hz in DC): losing customers is a surplus. So no
    pair here is "pass, LOAD LOST"; that rule guards a case these grids never reach. The
    mesh splits on 2 of its 45 pairs, AB+AC and DE+BE, each cutting off one generator.
 l. Under the preset nearly every pair fails; on the mesh, what passes sits close to the
    limit. case9: DC passes 5 of 66 — five of the nine two-piece splits (L45+L67, L56+L78,
    L56+L94, L67+L89, L78+L94), their worst pieces 0.0328 to 0.1210 Hz off nominal, well
    inside it — and AC on constant-power loads passes the same five; the default loads
    pass 20. The mesh: 19 pairs of lines split nothing and lose no
    generation (n/a). DC and default-load AC pass the same 8 pairs — G3 lost with any
    line, or cut off by DE+BE — DC at -0.1932 Hz each, and AC on constant-power loads
    fails all 8, at -0.2025 to -0.2475 Hz: the losses AC also has to cover.
 m. Where AC finds no operating point. On constant-power loads 24 of case9's pairs have
    no AC solution, every one of them losing a generator or the line it hangs on; on the
    default loads every pair has one. The mesh always has one.
 n. DC against AC, both at once. On case9 with constant-power loads the two agree on
    every pair both judge. On the default loads they disagree on 17: 16 times DC fails
    and AC passes (the sagging voltage lowers the draw: L14+L56 -0.4012 against
    -0.0083 Hz), once the other way — L45+L67, whose rising piece is +0.1210 Hz in DC and
    +0.2247 Hz in AC. On the mesh they disagree on the 8 pairs of claim l, constant-power
    loads only.
 o. What the second loss starts from. DC restores 50 Hz after every single loss of
    case9, and of the mesh all but G1 (150 MW against 45 MW of headroom left), which
    stops all 9 of its ordered pairs at every fidelity. In AC, case9's restored state is
    out of the voltage band after L14, L94 and G1 on both load models, and after L45 on
    constant-power loads, so 43 (constant power) and 32 (default) of its 132 ordered
    pairs have no state after both. Restoring after the mesh's G2 puts G3 at its ceiling.
 p. In DC the order never moves the worst piece's frequency: one after the other equals
    both at once on 90 of the 93 case9 ordered pairs where both have a number, and on all
    29 of the mesh's. The other three are one shape: a generator lost, 50 Hz restored,
    then the line it hung on (G1→L14, G2→L82, G3→L36), which cuts off an empty bus and
    leaves the frequency on target (printed ±0.0000: round-off of zero). Why: a first
    line loses no generation, so nothing is restored (L14, L36 and L82 are their
    generators' outages, D4), and every generator-first pair where the two timings agree
    ends with a governor at its cap, after which both leave the same deficit to damping.
 q. In AC the order matters, and which way follows the load model. One after the other
    is milder than both at once on 28 case9 and 18 mesh pairs with constant-power loads
    (worse on 10, all case9), and worse on 48 case9 and 16 mesh pairs with the default
    loads (milder on 25 and 2). It changes the verdict against both at once on 2 and 6
    case9 pairs (constant power, default) and 2 and 0 mesh pairs, and the two orders of
    one pair disagree once on each grid: case9 default loads, L45→L67 passes (+0.1986 Hz)
    and L67→L45 fails (+0.2100); the mesh with constant-power loads, DE→BE passes
    (-0.1970) and BE→DE fails (-0.2026). The largest move is case9 default loads L82→G3:
    -3.9910 Hz, against -1.5036 Hz both at once.
""")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
