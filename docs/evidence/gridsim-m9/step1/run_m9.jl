# Focused runner: the M9 step 1 testsets alone, against the main tree.
#   julia --project=W:/temp/claude/gridsim-m8/testenv W:/temp/claude/gridsim-m9/step1/run_m9.jl
using GridSim, Test
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
# m6_steady_state.jl's helper, copied here so the focused run need not load that file.
function _worst_drift(ser)
    worst, chan = 0.0, :none
    for ch in keys(ser)
        ch === :t && continue
        v = getproperty(ser, ch)
        d = maximum(abs, v .- v[1])
        d > worst && ((worst, chan) = (d, ch))
    end
    return worst, chan
end
cd(raw"W:\Claude_projects\GridSim")
ts = @testset "m9" begin include(raw"W:\Claude_projects\GridSim\test\m9_line_resistance.jl") end
