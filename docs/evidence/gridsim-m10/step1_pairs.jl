# M10 step 1: the two-line DC factors on the report grids — det M at every pair, the
# gap against rebuild-and-re-solve, the additive shortcut's error, and the near-cut
# scaling. Predictions in step1_predictions.md, written before this ran.
#
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m10/step1_pairs.jl
using GridSim, Printf
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")

without(net, ids) = NetworkModel(net.S_base, net.f0, net.buses,
    filter(b -> !(b.id in ids), net.branches), net.machines, net.loads;
    slack = net.slack, inverters = net.inverters)

# Rebuilt flows in `net`'s branch order (removed entries 0), or `nothing` if refused
# as disconnected.
function rebuilt(net, k, l)
    ids = (net.branches[k].id, net.branches[l].id)
    rest = try
        without(net, ids)
    catch e
        e isa ArgumentError && occursin("not connected", e.msg) || rethrow()
        return nothing
    end
    out = zeros(length(net.branches))
    out[[j for j in eachindex(net.branches) if j != k && j != l]] = dc_powerflow(rest).flow
    return out
end

function report(name, net)
    s, s1 = dc_line_pair_outages(net), dc_line_outages(net)
    f = s.base.flow
    println("== ", name)
    @printf("  %-9s %5s %12s %12s %12s\n", "pair", "cut", "det M", "gap/band", "shortcut/band")
    for (p, (k, l)) in pairs(s.pairs)
        id = string(s.base.branches[k], "+", s.base.branches[l])
        bf = rebuilt(net, k, l)
        if s.splits[p]
            @printf("  %-9s %5s %12.3e %12s %12s  refused=%s\n", id, "cut", s.det[p], "-", "-",
                    bf === nothing)
            continue
        end
        scale = max(maximum(abs, f), maximum(abs, bf))
        band = 100 * eps() * scale
        gap = maximum(abs.(s.flow[p] .- bf)) / band
        sc = if s1.splits[k] || s1.splits[l]
            NaN
        else
            short = f .+ (s1.flow[k] .- f) .+ (s1.flow[l] .- f)
            short[k] = short[l] = 0.0
            maximum(abs.(short .- s.flow[p])) / band
        end
        @printf("  %-9s %5s %12.3e %12.3f %12.3e  refused=%s\n", id, "", s.det[p], gap, sc,
                bf === nothing)
    end
end

report("case9", case9())
report("mesh", mesh())

# Near-cut: the mesh plus a weak A–D path of reactance Xw; AB+AC then leaves A on it.
# Exact reference: A–D carries G1's whole 1.5 pu; the rest is the four-bus grid with
# that injection moved to D.
println("== near-cut (mesh + A–D at Xw), pair AB+AC")
m0 = mesh()
four = NetworkModel(100.0, 50.0, [b for b in m0.buses if b.id !== :A],
    [b for b in m0.branches if !(b.id in (:AB, :AC))],
    [GridSim._machine_with(m0.machines[1]; bus = :D); m0.machines[2:end]], m0.loads; slack = :C)
for Xw in (1e3, 1e5, 1e7)
    net = NetworkModel(m0.S_base, m0.f0, m0.buses,
        [m0.branches; Branch(:AD, :A, :D, Xw, 500.0)], m0.machines, m0.loads; slack = m0.slack)
    s = dc_line_pair_outages(net)
    ids = [b.id for b in net.branches]
    p = findfirst(==((findfirst(==(:AB), ids), findfirst(==(:AC), ids))), s.pairs)
    exact = zeros(length(ids))
    for (j, b) in pairs(four.branches)
        exact[findfirst(==(b.id), ids)] = dc_powerflow(four).flow[j]
    end
    exact[findfirst(==(:AD), ids)] = 1.5
    k, l = s.pairs[p]
    bf = rebuilt(net, k, l)
    scale = maximum(abs, exact)
    gap = maximum(abs.(s.flow[p] .- exact))
    P = GridSim._dc_transfer_factors(net, inv.(branch_topology(net).X))
    @printf("  Xw=%.0e  cut=%s  det M=%.3e  margins=%.3f,%.3f  gap=%.3e  gap/near-band=%.3f  gap/ordinary-band=%.3e  rebuild-vs-exact=%.3e\n",
            Xw, s.splits[p], s.det[p], 1 - P[k, k], 1 - P[l, l], gap,
            gap / (100eps() * scale / abs(s.det[p])), gap / (100eps() * scale),
            maximum(abs.(bf .- exact)))
end
