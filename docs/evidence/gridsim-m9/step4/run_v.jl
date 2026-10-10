# Focused runner: the M9 testsets alone, against the main tree.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/run_m9.jl
using GridSim, Test
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq; const SciMLBase = GridSim.SciMLBase
const NetworkDynamics = GridSim.NetworkDynamics; const Graphs = GridSim.Graphs
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
# Copied from the suite's own files, so the focused run need not load them whole.
let src = read(raw"W:\Claude_projects\GridSim\test\m6_steady_state.jl", String)
    i = findfirst("function _worst_drift", src).start
    include_string(Main, src[i:findnext("\nend\n", src, i).stop])
end
let src = read(raw"W:\Claude_projects\GridSim\test\m8_screening.jl", String)
    i = findfirst("function _m8_genmesh", src).start
    include_string(Main, src[i:findnext("\nend\n", src, i).stop])
end
let src = read(raw"W:\Claude_projects\GridSim\test\m8_outage_screen.jl", String)
    i = findfirst("function _m8_tight", src).start
    include_string(Main, src[i:findnext("\nend\n", src, i).stop])
end
cd(raw"W:\Claude_projects\GridSim")
ts = @testset "m9v" begin
    include(raw"W:\Claude_projects\GridSim\test\m9_frequency_verdict.jl")
end
