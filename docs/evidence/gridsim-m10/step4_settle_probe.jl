# M10 step 4: the identity's six runs (TripElements at 1 s, settled to 400 s) — which complete,
# at which tolerance and solver, and how settled each piece is at 200/300/400 s. The first
# test run lost constant-power L45+L56 to a step-size collapse at t = 367.66 s (FBDF, reltol
# 1e-10) with every state's weighted error ~1e-43.
using GridSim
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
import OrdinaryDiffEq

lines(net, ids) = [(b.from, b.to) for id in ids for b in net.branches if b.id === id]
function run(loads, ids, solver, tol)
    net = case9(; loads)
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = tol,
                abstol = tol / 100, solver = solver)
    solve!(eng, (0.0, 1.0); saveat = 0.5)
    inject!(eng, TripElements(lines = lines(net, ids)))
    ωs = Vector{Float64}[]
    for T in (200.0, 300.0, 400.0)
        try
            solve!(eng, (eng.integrator.t, T); saveat = 0.5)
        catch e
            return "FAILED at t = $(round(eng.integrator.t; digits = 2))"
        end
        push!(ωs, copy(current_state(eng).ω))
    end
    return "ok; max|Δω| 200→300 = $(maximum(abs, ωs[2] - ωs[1])), 300→400 = $(maximum(abs, ωs[3] - ωs[2]))"
end
cases = [(:constant_power, (:L56, :L78)), (:constant_power, (:L45, :L56)),
         (:default, (:L45, :L67)), (:default, (:L56, :L78)), (:default, (:L67, :L89)),
         (:default, (:L45, :L56))]
for (loads, ids) in cases
    println("== $loads $(join(ids, '+'))")
    for (sname, solver, tol) in (("FBDF 1e-10", OrdinaryDiffEq.FBDF(), 1e-10),
                                 ("FBDF 1e-9", OrdinaryDiffEq.FBDF(), 1e-9),
                                 ("Rodas5P 1e-10", OrdinaryDiffEq.Rodas5P(), 1e-10))
        println("   ", rpad(sname, 14), run(loads, ids, solver, tol))
    end
end
