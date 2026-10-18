# M10 step 3 — every pair in AC on both report grids and both load models, piece by
# piece, beside step 2's DC answer. What the claims in m10-context.md "What step 3
# measured" were read from.
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m10/step3_pairs.jl > step3_pairs.out.txt
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end

const S = OutageScreenScript

name(s, p) = join((s.id[e] for e in s.pairs[p]), "+")

for (gname, f) in (("case9", S.case9), ("mesh", S.mesh)), loads in (:constant_power, :default)
    net = f(; loads)
    dc, ac = dc_pair_outages(net), ac_pair_outages(net)
    cmp = compare_pair_screens(net, dc, ac)
    println("\n== $gname, $loads loads — $(length(ac.pairs)) pairs")
    @printf("%-10s %-10s %-14s %-16s %12s %12s  %s\n", "pair", "class", "piece", "AC outcome",
            "Δω DC (pu)", "Δω AC (pu)", "AC over / low")
    for p in eachindex(ac.pairs)
        c = 0
        for (a, d) in zip(ac.pieces[p], dc.pieces[p])
            a.kind === :empty && continue
            c += 1
            extra = a.outcome === :overload ? join((o.id for o in a.over), ",") :
                    a.outcome === :voltage ? join((@sprintf("%s %.3f", l.bus, l.Vm) for l in a.low), ",") :
                    a.outcome === :no_solution ? string(a.reason) :
                    a.kind === :sources_lost ? @sprintf("lost %.2f MW", 100a.sources_lost) :
                    a.kind === :load_lost ? @sprintf("lost %.2f MW", 100a.load_lost) : ""
            @printf("%-10s %-10s %-14s %-16s %12.4e %12.4e  %s\n", c == 1 ? name(ac, p) : "",
                    c == 1 ? string(cmp.class[p]) : "", join(a.buses, ","), a.outcome,
                    d.Δω, a.Δω, extra)
        end
    end
    # Every class, counted.
    println("classes: ", join(("$k $(count(==(k), cmp.class))" for k in unique(cmp.class)), ", "))
    # Step 4's oracle needs a split with two live pieces, every one :secure, one rising and
    # one falling (m10-plan.md step 4).
    two = [name(ac, p) for p in eachindex(ac.pairs)
           if count(pc -> pc.kind === :live, ac.pieces[p]) == 2 &&
              all(pc -> pc.kind !== :live || pc.outcome === :secure, ac.pieces[p]) &&
              let w = [pc.Δω for pc in ac.pieces[p] if pc.kind === :live]
                  minimum(w) < 0 < maximum(w)
              end]
    println("two live pieces, both secure, one up and one down: ",
            isempty(two) ? "none" : join(two, ", "))
end
