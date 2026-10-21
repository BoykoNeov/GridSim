# M11 step 3 — the AC rating fixture, the optimiser alone: a ring line whose RECEIVING end
# carries the larger |S| at the unconstrained optimum, rated (invented) below it.
using GridSim, JuMP, HiGHS, Ipopt, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const c9 = OutageScreenScript.case9
function rated(net, id, mva)
    br = [Branch(b.id, b.from, b.to, b.X, b.id === id ? mva : b.rating; R = b.R) for b in net.branches]
    NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads; slack = net.slack)
end
for (id, mvas) in ((:L94, (65.0, 60.0, 50.0)), (:L56, (50.0, 45.0)))
    for loads in (:constant_power, :default), mva in mvas
        net = rated(c9(; costed = true, loads), id, mva)
        rs = [ac_opf(net; tol = t) for t in (1e-8, 1e-10)]
        r = rs[2]; e = findfirst(==(id), r.branches)
        @printf("%s at %.0f MVA, %s: %s cost %.6f P %s at_limit %s at_band %s q %s\n   |Sf| %.6f |St| %.6f MVA  limit %.6f   conv P %.1e flow %.1e\n",
                id, mva, loads, r.outcome, r.cost, string(round.(r.P .* 100; digits = 4)), r.at_limit,
                r.at_band, r.q_at_limit, hypot(r.flow[e], r.qflow[e]) * 100,
                hypot(r.flow_rev[e], r.qflow_rev[e]) * 100, r.limit[e] * 100,
                maximum(abs, rs[1].P .- r.P), maximum(abs, rs[1].flow .- r.flow))
        d = ac_opf(net; tol = 1e-10, start = dc_opf(net; regularization = 0.0))
        println("   DC start: ", d.outcome, " ", d.status)
    end
end
