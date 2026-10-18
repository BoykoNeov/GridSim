# M10 step 0: the detailed tier with two case9 lines tripped at the same instant, as two
# back-to-back TripLine injects (the only way the tier can do it today). Prints every
# refusal and keeps going, ON PURPOSE, to show what a refused trip leaves behind.
# docs/plans/m10-context.md D1.
using GridSim
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
import OrdinaryDiffEq
function run(net, pair; T = 60.0)
    base = ac_powerflow(net)
    eng = init!(DetailedEngine, net; powerflow = base, reltol = 1e-8, abstol = 1e-10,
                solver = OrdinaryDiffEq.FBDF())
    solve!(eng, (0.0, 1.0); saveat = 0.05)
    for (a, b) in pair
        r = try inject!(eng, TripLine(a, b)); "ok" catch e; sprint(showerror, e)[1:min(end, 300)] end
        println("   trip $a-$b at t=", eng.integrator.t, ": ", r)
    end
    r = try solve!(eng, (1.0, T); saveat = 0.05); "ok" catch e; sprint(showerror, e)[1:min(end, 300)] end
    println("   solve to $T: ", r, "  t_end=", eng.integrator.t)
    s = state_series(eng)
    ks = [k for k in keys(s) if startswith(String(k), "ω_") || startswith(String(k), "f_")]
    for k in ks
        v = s[k]; println("   ", rpad(k, 10), " at 1.0: ", v[findfirst(>=(1.0), s.t)], "  end: ", v[end], "  at T-5: ", v[findlast(<=(T - 5), s.t)])
    end
end
for lm in (:constant_power, :default)
    net = case9(loads = lm)
    println("== $lm: two live islands, L45+L67  (B3,B5,B6 | rest)")
    run(net, [(:B4, :B5), (:B6, :B7)])
    println("== $lm: strands load bus B5, L45+L56")
    run(net, [(:B4, :B5), (:B5, :B6)])
end
