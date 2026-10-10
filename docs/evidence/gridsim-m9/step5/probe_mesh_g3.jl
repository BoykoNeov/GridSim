# M9 step 5: why does mesh-default G3 never meet the stopping rule? Trace f_coi and
# coi_rocof after the trip, lossless copy, FBDF 1e-8, 0.5 s chunks (generator_dips'
# own run), out to 400 s, at the reltol given (default 1e-8).
#   julia --project=W:/Claude_projects/GridSim probe_mesh_g3.jl [reltol]
using GridSim, Printf
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
n = OS.mesh(; loads = :default)
net = NetworkModel(n.S_base, n.f0, n.buses,
                   [Branch(b.id, b.from, b.to, b.X, b.rating) for b in n.branches],
                   n.machines, n.loads; slack = n.slack)
ma = machine_arrays(net)
τ = 2 * sum(ma.H[1:2]) / sum(ma.D[1:2])
println("tau = ", τ)
rt = isempty(ARGS) ? 1e-8 : parse(Float64, ARGS[1])
println("reltol = ", rt)
eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = rt,
            abstol = rt / 100, solver = GridSim.OrdinaryDiffEq.FBDF())
solve!(eng, (0.0, 1.0); saveat = 0.01)
inject!(eng, TripGenerator(:G3))
t = 1.0
while t < 400.0
    solve!(eng, (t, t + 0.5); saveat = 0.01)
    global t = eng.integrator.t
    if abs(rem(t, 20.0)) < 1e-9 || (35 < t < 45)
        s = current_state(eng)
        @printf("t %7.2f  f-f0 %+.9f  rocof %+.3e  tau*|rocof| %.3e  Efd %s  V %s\n", t,
                s.f_coi - 50, coi_rocof(eng), τ * abs(coi_rocof(eng)),
                string(round.(s.Efd; digits = 5)), string(round.(s.V; digits = 5)))
    end
end
