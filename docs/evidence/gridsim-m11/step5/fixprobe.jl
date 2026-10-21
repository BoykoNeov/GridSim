using GridSim, Printf
module S; include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl"); end
for (name, f) in (("case9", S.case9), ("mesh", S.mesh)), loads in (:constant_power, :default)
    net = f(; loads)
    base = ac_powerflow(net)
    r0 = GridSim._responders(net); r = GridSim._responders(net, base)
    eng = init!(DetailedEngine, net; powerflow = base)
    hr = [eng.params[i] for i in eng.hr_pidx]
    k = only(net.machines_at_bus[net.bus_index[net.slack]])
    @printf("%-5s %-15s slack %s shift %+8.4f MW | headroom sched %8.4f  screen %8.4f  detailed %8.4f MW | others same: %s %s\n",
            name, loads, net.machines[k].id, r.shift[k]*100, r0.h[k]*100, r.h[k]*100, hr[k]*100,
            all(r.h[j] === r0.h[j] for j in eachindex(r.h) if j != k),
            all(hr[j] === machine_arrays(net).headroom[j] for j in eachindex(hr) if j != k))
end
