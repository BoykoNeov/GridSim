# Focused runner: the M11 core testsets (with M6's dispatch file, whose helpers they use).
#   julia --project=W:/temp/claude/gridsim-m11-step3/probeenv run_m11.jl [ac]
using GridSim, Test
import JuMP, HiGHS, Ipopt
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
cd(raw"W:\Claude_projects\GridSim")
ts = @testset "m11" begin
    include(raw"W:\Claude_projects\GridSim\test\m6_economic_dispatch.jl")
    include(raw"W:\Claude_projects\GridSim\test\m11_dc_opf.jl")
    include(raw"W:\Claude_projects\GridSim\test\m11_ac_opf.jl")
end
