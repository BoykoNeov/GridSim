# Focused runner: M10 step 6's report test (test/m10_report.jl) alone — every helper of
# test/m10_double_outages.jl defined (its testsets skipped), and the two script modules the
# suite defines.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Test
const Graphs = GridSim.Graphs
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
module DoubleOutageScript
include(raw"W:\Claude_projects\GridSim\scripts\double_outage_screen.jl")
end
let path = raw"W:\Claude_projects\GridSim\test\m10_double_outages.jl"
    top = Meta.parseall(read(path, String); filename = path)
    for e in top.args
        skip = e isa Expr && e.head === :macrocall && e.args[1] === Symbol("@testset")
        skip || Core.eval(Main, e)
    end
end
include(raw"W:\Claude_projects\GridSim\test\m10_report.jl")
