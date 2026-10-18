# M10 step 0: every pair of line outages on case9 and the mesh, classified by what the
# pieces left behind hold (S = a source, L = a load, S+L = both). docs/plans/m10-context.md D1.
using GridSim, Graphs
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
function census(name, net)
    topo = branch_topology(net); n = length(net.buses); m = length(topo.src)
    srcbus = Set(net.bus_index[mc.bus] for mc in net.machines)
    loadbus = Set(net.bus_index[l.bus] for l in net.loads)
    bridges = GridSim._bridge_mask(net)
    kinds = Dict{String,Int}()
    for k in 1:m, l in k+1:m
        g = SimpleGraph(n)
        for e in 1:m
            (e == k || e == l) && continue
            add_edge!(g, topo.src[e], topo.dst[e])
        end
        cc = connected_components(g)
        tag(c) = any(v in srcbus for v in c) ? (any(v in loadbus for v in c) ? "S+L" : "S") :
                 (any(v in loadbus for v in c) ? "L" : "empty")
        t = length(cc) == 1 ? "connected" : join(sort(tag.(cc)), "|")
        nb = bridges[k] + bridges[l]
        key = string(nb, " bridge(s): ", t)
        kinds[key] = get(kinds, key, 0) + 1
        println("  ", name, " ", net.branches[k].id, "+", net.branches[l].id, " -> ", t)
    end
    println(name, " summary:"); for (k, v) in sort(collect(kinds)); println("   ", v, "  ", k); end
end
census("case9", case9()); census("mesh", mesh())
