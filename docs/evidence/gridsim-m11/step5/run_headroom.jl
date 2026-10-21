# Focused runner: M11 step 5's headroom tests alone.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv run_headroom.jl
using GridSim, Test
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
_r_with_R(net::NetworkModel, f::Real) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating; R = f * b.X) for b in net.branches],
    net.machines, net.loads; slack = net.slack, inverters = net.inverters)
_r_pair(; R = 0.04, slack = :B1) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0)],
    [Branch(:L21, :B2, :B1, 0.25, 500.0; R)],
    [Machine(:G1, :B1, 200.0, 4.0, 2.0, 0.10, 1.05, 60.0),
     Machine(:G2, :B2, 100.0, 3.0, 1.5, 0.075, 0.98, -60.0)]; slack)
include(raw"W:\Claude_projects\GridSim\test\m11_headroom.jl")
