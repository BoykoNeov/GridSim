# Claim r's probe (m10-context.md D13, "What D13 measured"): the V/O marks per side on both grids,
# green pairs carrying a mark, and AC overloads against the pair comparison's ac_over.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim
module R
include(raw"W:\Claude_projects\GridSim\scripts\double_outage_screen.jl")
end
for (key, _, f) in R.GRIDS
    G = R.grid_screens(f); both = R.simultaneous_rows(G); seq = R.sequential_rows(G; both)
    for (nm, rows) in (("both", both), ("seq", seq)), k in R.SIDES
        ls = [getfield(r, k).lines for r in rows]
        green_marked = count(r -> getfield(r, k).verdict === :pass && getfield(r, k).lines !== :secure && getfield(r, k).lines !== :none, rows)
        println("$key $nm $k: ", join(["$l=$(count(==(l), ls))" for l in sort!(unique(ls))], " "), "  | green with a mark: $green_marked")
    end
    # AC overload vs the comparison's ac_over
    for k in (:cp, :def)
        c = getfield(G.cmp, k)
        bad = [p for (p, r) in pairs(both) if (getfield(r, k).lines in (:overload, :overload_voltage)) != !isempty(c.ac_over[p])]
        println("  $k overload vs ac_over mismatches: ", length(bad))
    end
end
R.print_header()
