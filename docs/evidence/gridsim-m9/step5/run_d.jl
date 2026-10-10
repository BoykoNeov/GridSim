# Focused runner (M9 step 5): the step-4 verdict testsets and the step-5 dip testsets,
# against the main tree.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv run_d.jl
using GridSim, Test
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq; const SciMLBase = GridSim.SciMLBase
const NetworkDynamics = GridSim.NetworkDynamics; const Graphs = GridSim.Graphs
include("W:/Claude_projects/GridSim/test/helpers.jl")
module OutageScreenScript
include("W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
# Copied from the suite's own files, so the focused run need not load them whole.
for (file, fn) in (("m6_steady_state.jl", "function _worst_drift"),
                   ("m8_screening.jl", "function _m8_genmesh"),
                   ("m8_outage_screen.jl", "function _m8_tight"))
    src = read("W:/Claude_projects/GridSim/test/" * file, String)
    i = findfirst(fn, src).start
    include_string(Main, src[i:findnext("\nend\n", src, i).stop])
end
cd("W:/Claude_projects/GridSim")
ts = @testset "m9d" begin
    include("W:/Claude_projects/GridSim/test/m9_frequency_verdict.jl")
    include("W:/Claude_projects/GridSim/test/m9_dips.jl")
end
