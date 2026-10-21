# The M11 step-4 testset alone, in the reference environment (with step 2's file first,
# whose helpers it reuses).  julia --project=W:/Claude_projects/GridSim/reference run_step4.jl
using Test, GridSim, GridSimReference
include("W:/Claude_projects/GridSim/reference/test/m11_dc_opf_oracle.jl")
include("W:/Claude_projects/GridSim/reference/test/m11_ac_opf_oracle.jl")
