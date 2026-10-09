# M9 step 3, D7 finding 2: each generator trip's re-initialisation outcome on the
# constant-power report grids. Run at HEAD and with mutate.py's T1b applied: case9 G1
# is refused by name at HEAD and stalls (NetworkInitError) at x1.1 R.
#   julia --project=W:/Claude_projects/GridSim probe_trip_refusals.jl
using GridSim
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const O = OutageScreenScript
for (nm, f) in (("case9", O.case9), ("mesh", O.mesh))
    net = f(; loads = :constant_power); sol = ac_powerflow(net)
    for m in net.machines
        eng = init!(DetailedEngine, net; powerflow = sol, reltol = 1e-8, abstol = 1e-10, solver = GridSim.OrdinaryDiffEq.FBDF())
        r = try inject!(eng, TripGenerator(m.id)); "ok" catch e; first(sprint(showerror, e), 90) end
        println(nm, " ", m.id, ": ", r)
    end
end
