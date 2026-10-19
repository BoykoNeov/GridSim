# Focused runner: M10 step 5's testset alone — every helper of test/m10_double_outages.jl
# defined, the step 1–4 testsets skipped (each is a top-level `@testset "M10 step N — …"`).
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Test
const Graphs = GridSim.Graphs
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
let path = raw"W:\Claude_projects\GridSim\test\m10_double_outages.jl"
    top = Meta.parseall(read(path, String); filename = path)
    for e in top.args
        skip = e isa Expr && e.head === :macrocall && e.args[1] === Symbol("@testset") &&
               any(a -> a isa String && occursin(r"^M10 step [1234] ", a), e.args)
        skip || Core.eval(Main, e)
    end
end
