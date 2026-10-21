# run with --project=W:/temp/claude/gridsim-m11-resolve/core  (GridSim dev + PowerModels)
using GridSim, PowerModels
PowerModels.silence()
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
sched(net, P) = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
    [GridSim._machine_with(m; P0 = P[k]) for (k, m) in pairs(net.machines)], net.loads; slack = net.slack)
# Check 1: DC flows at the same dispatch, ours (1/X) against PowerModels' (x/(r^2+x^2)).
P = [86.564, 134.378, 94.058]; P[1] = 315.0 - P[2] - P[3]
dc = dc_powerflow(sched(case9(), P))
d = PowerModels.parse_file(raw"W:\temp\claude\gridsim-m11-resolve\data\case9.m")
for (i, p) in enumerate(P); d["gen"][string(i)]["pg"] = p / 100; end
PowerModels.update_data!(d, PowerModels.compute_dc_pf(d)["solution"])
pmf = PowerModels.calc_branch_flow_dc(d)["branch"]
order = Dict("L14"=>"1","L45"=>"2","L56"=>"3","L36"=>"4","L67"=>"5","L78"=>"6","L82"=>"7","L89"=>"8","L94"=>"9")
println("Check 1 — DC flow MW at Pg = ", P, "  (ours 1/X | PowerModels x/(r²+x²) | diff | R/X)")
for (j, id) in enumerate(dc.branches)
    br = d["branch"][order[string(id)]]
    ours, theirs = 100dc.flow[j], 100pmf[order[string(id)]]["pf"]
    println("  ", rpad(id, 4), lpad(round(ours, digits = 3), 9), lpad(round(theirs, digits = 3), 9),
            lpad(round(ours - theirs, digits = 3), 8), "   ", round(br["br_r"] / br["br_x"], digits = 3))
end
# Check 3: our ac_powerflow at 1.75x load, the DC-OPF dispatch at that load.
for (s, Pd) in ((1.5, [135.91, 198.23, 138.36]), (1.75, [160.58, 230.16, 160.52]), (2.0, [191.61, 250.0, 188.39]))
    net = sched(case9(; mw = s * 315), Pd)
    try
        sol = ac_powerflow(net)
        gi = [findfirst(==(m.bus), sol.buses) for m in net.machines]
        println("Check 3 s=$s: solved. roles at gen buses ", sol.roles[gi], " limited ", sol.limited,
                " Vm(gen) ", round.(sol.Vm[gi], digits = 4), " Qgen MVAr ", round.(100sol.Qgen, digits = 1),
                " min Vm ", round(minimum(sol.Vm), digits = 4))
    catch e
        println("Check 3 s=$s: REFUSED — ", first(sprint(showerror, e), 300))
    end
end
