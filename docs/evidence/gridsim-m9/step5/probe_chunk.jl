# Probe (no src edits): does lossless mesh-default G2 still fail at FBDF 1e-8 when the
# post-trip run is chunked in 0.5 s solve! calls? And how long does a run take?
using GridSim
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
lossless(n) = NetworkModel(n.S_base, n.f0, n.buses,
                           [Branch(b.id, b.from, b.to, b.X, b.rating) for b in n.branches],
                           n.machines, n.loads; slack = n.slack)
const FBDF = GridSim.OrdinaryDiffEq.FBDF
function run(net, lost, rt; chunk, T = 150.0)
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = rt,
                abstol = rt / 100, solver = FBDF())
    if chunk === nothing
        try
            solve!(eng, (0.0, T); perturbations = [1.0 => TripGenerator(lost)], saveat = 0.01)
        catch e
            return "FAIL $(eng.integrator.sol.retcode) at $(eng.integrator.t)"
        end
    else
        solve!(eng, (0.0, 1.0); saveat = 0.01)
        inject!(eng, TripGenerator(lost))
        t = 1.0
        while t < T
            try
                solve!(eng, (t, t + chunk); saveat = 0.01)
            catch e
                return "FAIL $(eng.integrator.sol.retcode) at $(eng.integrator.t)"
            end
            t += chunk
        end
    end
    return "ok nadir $(eng.nadir - net.f0) end $(current_state(eng).f_coi - net.f0) rocof $(coi_rocof(eng))"
end
net = lossless(OS.mesh(; loads = :default))
for rt in (1e-8, 1e-6), chunk in (nothing, 0.5)
    t0 = time(); r = run(net, :G2, rt; chunk); println("mesh def G2 rt=$rt chunk=$chunk: $r  [$(round(time() - t0; digits = 1)) s]")
end
net = lossless(OS.mesh(; loads = :constant_power))
for rt in (1e-8, 1e-6)
    t0 = time(); r = run(net, :G1, rt; chunk = 0.5); println("mesh cp G1 rt=$rt: $r  [$(round(time() - t0; digits = 1)) s]")
end
