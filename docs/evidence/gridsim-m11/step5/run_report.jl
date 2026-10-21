# Focused runner: M11 step 5's report tests alone (reference env: it has JuMP, HiGHS, Ipopt).
using GridSim, Test
module NetworkDispatchScript
include(raw"W:\Claude_projects\GridSim\scripts\network_dispatch.jl")
end
const _OPF_L82_MVA = 100.0      # as test/m11_dc_opf.jl
const _OPF_L89_MVA = 50.0
const _AC_L94_MVA = 60.0        # as test/m11_ac_opf.jl
include(raw"W:\Claude_projects\GridSim\test\m11_report.jl")
