# The M11 step-2 testset alone, in the reference environment (for iteration and the
# sabotages).  julia --project=W:/Claude_projects/GridSim/reference run_step2.jl
using Test, GridSim, GridSimReference
include("W:/Claude_projects/GridSim/reference/test/m11_dc_opf_oracle.jl")
