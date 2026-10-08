using GridSim, Printf
module OutageScreenScript
include(joinpath("W:/Claude_projects/GridSim", "scripts", "outage_screen.jl"))
end
const OS = OutageScreenScript
net0 = OS.mesh(; loads = :default)
net = NetworkModel(net0.S_base, net0.f0, net0.buses, [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net0.branches], net0.machines, net0.loads; slack = net0.slack)
acg = ac_generator_outages(net)
println("AC screen outcomes: ", acg.outcome, " Δf Hz: ", acg.Δω .* 50)
OD = GridSim.OrdinaryDiffEq
for (name, solver, rt) in (("FBDF 1e-6", OD.FBDF(), 1e-6), ("Rodas5P 1e-8", OD.Rodas5P(), 1e-8), ("Rodas5P 1e-6", OD.Rodas5P(), 1e-6), ("FBDF 1e-10", OD.FBDF(), 1e-10))
    try
        eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = rt, abstol = rt/100, solver)
        s = solve!(eng, (0.0, 60.0); perturbations = [1.0 => TripGenerator(:G2)], saveat = 0.01)
        i = argmin(s.f_coi)
        @printf("%-14s ok: nadir %.4f Hz at %.2f s, end %.4f Hz, min V %.3f\n", name, eng.nadir - 50, s.t[i], s.f_coi[end] - 50,
                minimum(minimum(getproperty(s, Symbol(:V_, b.id))) for b in net.buses))
    catch e
        println(rpad(name, 14), " FAILED: ", sprint(showerror, e)[1:min(end, 160)])
    end
end
