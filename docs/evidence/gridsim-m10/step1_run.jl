# Focused runner: the M10 testsets alone. julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Test
const Graphs = GridSim.Graphs
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
include(raw"W:\Claude_projects\GridSim\test\m10_double_outages.jl")
