# Focused runner: the double-outage window's testsets (ui/test/double_outage_tests.jl) alone,
# with every helper ui/test/runtests.jl defines at top level (its testsets skipped). Run
# with the precompile workload off:
#   set GRIDSIM_UI_PRECOMPILE=0 & julia --project=W:/Claude_projects/GridSim/ui <this file>
let path = raw"W:\Claude_projects\GridSim\ui\test\runtests.jl"
    top = Meta.parseall(read(path, String); filename = path)
    for e in top.args
        skip = e isa Expr && e.head === :macrocall && e.args[1] === Symbol("@testset")
        skip || Core.eval(Main, e)
    end
end
@testset "double-outage window" begin
    include(raw"W:\Claude_projects\GridSim\ui\test\double_outage_tests.jl")
end
