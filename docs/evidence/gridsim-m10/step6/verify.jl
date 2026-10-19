# Kept as step 6's evidence (m10-context.md D12, "What step 6 measured"); re-run on the committed
# code, output in verify.out.txt.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Printf
module R
include(raw"W:\Claude_projects\GridSim\scripts\double_outage_screen.jl")
end
for (key, name, f) in R.GRIDS
    G = R.grid_screens(f)
    both = R.simultaneous_rows(G)
    seq = R.sequential_rows(G; both)
    println("== $key")
    for r in both
        lv = [p for p in r.dc.pieces if p.kind === :live]
        length(lv) == 2 || continue
        s = [(k, sign.([p.Δf for p in getfield(r, k).pieces if p.kind === :live])) for k in R.SIDES]
        println("  2 live $(r.first)+$(r.second): ", join(["$k $(v)" for (k, v) in s], "  "),
                "  verdicts ", r.dc.verdict, " ", r.cp.verdict, " ", r.def.verdict)
    end
    # DC sequential :same with first a machine: is any governor capped after both?
    s = G.dcseq
    m = length(G.net.cp.branches)
    nocap = String[]
    for (p, (a, b)) in pairs(s.pairs)
        r = seq[p]
        (a > m && r.order.dc === :same) || continue
        any(s.capped[p]) || push!(nocap, "$(s.id[a])→$(s.id[b])")
    end
    println("  DC same, machine first, nothing capped after both: ", isempty(nocap) ? "none" : join(nocap, " "))
    # line first in DC: restore pickups all zero?
    lf = [s.id[a] for a in 1:m if any(!=(0.0), s.restore[a].pickup)]
    println("  DC line-first restores with a nonzero pickup: ", isempty(lf) ? "none" : join(lf, " "))
    # cp no-solution pairs
    ns = ["$(r.first)+$(r.second)" for r in both if r.cp.verdict === :unjudged]
    println("  cp unjudged both ($(length(ns))): ", join(ns, " "))
    # seq outcomes not_restored firsts
    for k in (:cp, :def)
        acs = getproperty(G.acseq, k)
        firsts = unique([acs.id[a] for (p, (a, b)) in pairs(acs.pairs) if acs.outcome[p] === :not_restored])
        println("  $k not restored after: ", join(firsts, " "), " ; count ", count(==(:not_restored), acs.outcome))
    end
    # sanity: DC pair screens equal across load models (fieldwise)
    d2 = dc_pair_outages(G.net.def)
    eqf(a, b) = typeof(a) === typeof(b) && (isstructtype(typeof(a)) && !(a isa AbstractArray) && fieldcount(typeof(a)) > 0 ?
                all(eqf(getfield(a, x), getfield(b, x)) for x in fieldnames(typeof(a))) :
                a isa AbstractArray ? (size(a) == size(b) && all(eqf(x, y) for (x, y) in zip(a, b))) : isequal(a, b))
    println("  DC pair screens equal across load models: ", eqf(G.dc, d2), "; sequential: ", eqf(G.dcseq, dc_sequential_outages(G.net.def)))
end
