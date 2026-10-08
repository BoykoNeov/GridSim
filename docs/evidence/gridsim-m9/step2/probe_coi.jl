using GridSim
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
net = ratio_ring(D1 = 1.0)
lossy = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating; R = 0.3 * b.X) for b in net.branches], net.machines)
m = try; coi_model(lossy); catch e; e; end
println("coi_model(lossy) -> ", typeof(m))
