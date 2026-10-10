# M9 step 5: the replacement controls for Hurdle 16.5, after the planned one (mesh-default
# G2 `Unstable`) vanished under chunking. (a) Step 3's stall reproducer as MODEL DATA:
# case9 constant power, every Branch.R x1.1, losing G1. (b) A failed integration via
# init!'s own maxiters.
#   julia --project=W:/Claude_projects/GridSim probe_stall.jl
using GridSim
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
n = OS.case9(; loads = :constant_power)
for f in (1.0, 1.1, 1.2)
    net = NetworkModel(n.S_base, n.f0, n.buses,
                       [Branch(b.id, b.from, b.to, b.X, b.rating; R = f * b.R) for b in n.branches],
                       n.machines, n.loads; slack = n.slack)
    ac = try ac_generator_outages(net) catch e; println("R x$f: AC screen threw ", typeof(e)); continue end
    d = generator_dips(net, ac)
    println("R x$f: AC ", ac.outcome, " | dips ", d.outcome, " ", d.reason)
end
net = OS.mesh(; loads = :constant_power)
base = ac_powerflow(net)
for mi in (10, 100, 1000)
    r = GridSim._dip_run(net, base, :G1, 1.0, 4.25, 1e-8, 1e-10; maxiters = mi)
    println("maxiters $mi: ", r[1], " ", r[2], " retcode ", r[3].integrator.sol.retcode, " t ", r[3].integrator.t)
end
