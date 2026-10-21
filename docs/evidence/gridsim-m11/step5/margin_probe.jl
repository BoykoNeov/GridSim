# Anti-vacuity for section 2: the AC optimum at margin 0 handed to the same flat-run start.
using GridSim, Printf
module ND; include(raw"W:\Claude_projects\GridSim\scripts\network_dispatch.jl"); end
for (key, label, build) in ND.FIXTURES, loads in ND.LOADS
    net = build(loads)
    a = ac_opf(net; margin_V = 0.0, margin_S = 0.0)
    a.outcome === :locally_optimal || continue
    bind = ND._binds(a)
    res = try
        sched = dispatch_schedule(net, a)
        f = ac_powerflow(sched)
        init!(DetailedEngine, sched; powerflow = f)
        "starts"
    catch e
        "REFUSED: " * first(split(sprint(showerror, e), '.'))
    end
    @printf("%-6s %-15s %-16s %s\n", key, loads, bind, res)
end
