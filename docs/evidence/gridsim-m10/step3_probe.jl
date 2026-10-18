# M10 step 3 — two things the first run did not answer as predicted, probed.
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m10/step3_probe.jl > step3_probe.out.txt
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const S = OutageScreenScript

pairidx(s, a, b) = (i = findfirst(==(a), s.id); j = findfirst(==(b), s.id);
                    findfirst(==((min(i, j), max(i, j))), s.pairs))

println("== 1. case9: four paths to G1 and G2 gone")
for loads in (:constant_power, :default)
    net = S.case9(; loads)
    s = ac_pair_outages(net)
    for (a, b) in ((:L14, :L82), (:L14, :G2), (:L82, :G1), (:G1, :G2))
        p = pairidx(s, a, b)
        pc = only(pc for pc in s.pieces[p] if pc.kind === :live)
        @printf("%-15s %-6s %-10s Δω %.15e  reason %-8s  capped %s  low %s  over %s\n", loads, "$a+$b",
                pc.outcome, pc.Δω, pc.reason, s.capped[p],
                join((@sprintf("%s %.12f", l.bus, l.Vm) for l in pc.low), ","),
                join((@sprintf("%s %.6f", o.id, o.mva) for o in pc.over), ","))
        println("    pickups ", s.pickup[p])
    end
end

println("\n== 2. mesh: AB+AC against G1 alone")
for loads in (:constant_power, :default)
    net = S.mesh(; loads)
    s, g = ac_pair_outages(net), ac_generator_outages(net)
    p = pairidx(s, :AB, :AC)
    pc = only(pc for pc in s.pieces[p] if pc.kind === :live)
    k = findfirst(==(:G1), g.machines)
    @printf("%-15s pair %-8s Δω %.12f   G1 alone %-8s Δω %.12f   pair − G1 %.3e\n", loads,
            pc.outcome, pc.Δω, g.outcome[k], g.Δω[k], pc.Δω - g.Δω[k])
    println("    capped pair ", s.capped[p], "  G1 alone ", g.capped[k])
    if pc.solution !== nothing && g.solution[k] !== nothing
        a, b = pc.solution, g.solution[k]
        @printf("    losses: pair %.6f  G1 alone %.6f  (base %.6f)\n", sum(a.loss), sum(b.loss),
                sum(s.base.loss))
        @printf("    load draw: pair %.6f  G1 alone %.6f\n", sum(a.Pload), sum(b.Pload))
        for (j, br) in pairs(b.branches)
            br in (:AB, :AC) && @printf("    G1 alone: %s carries %.6f pu, loss %.6f pu\n", br, b.flow[j], b.loss[j])
        end
    end
end
