# M10 step 1: the near-cut probe that found the rebuild drifting with the reference on the cut-off bus (step1_predictions.md, P6).
using GridSim, Printf
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
m0 = mesh()
four = NetworkModel(100.0, 50.0, [b for b in m0.buses if b.id !== :A],
    [b for b in m0.branches if !(b.id in (:AB, :AC))],
    [GridSim._machine_with(m0.machines[1]; bus = :D); m0.machines[2:end]], m0.loads; slack = :C)
for slack in (:A, :C), Xw in (1e3, 1e5, 1e7)
    net = NetworkModel(m0.S_base, m0.f0, m0.buses, [m0.branches; Branch(:AD, :A, :D, Xw, 500.0)], m0.machines, m0.loads; slack)
    ids = [b.id for b in net.branches]
    s = dc_line_pair_outages(net); p = findfirst(==((1, 2)), s.pairs)
    exact = zeros(length(ids)); ff = dc_powerflow(four).flow
    for (j, b) in pairs(four.branches); exact[findfirst(==(b.id), ids)] = ff[j]; end
    exact[end] = 1.5
    rest = NetworkModel(net.S_base, net.f0, net.buses, filter(b -> !(b.id in (:AB, :AC)), net.branches), net.machines, net.loads; slack)
    bf = zeros(length(ids)); bf[3:end] = dc_powerflow(rest).flow
    @printf("slack=%s Xw=%.0e  ours-vs-exact=%.3e  rebuild-vs-exact=%.3e  maxθ=%.3e\n", slack, Xw,
            maximum(abs.(s.flow[p] .- exact)), maximum(abs.(bf .- exact)), maximum(abs, dc_powerflow(rest).θ))
end
