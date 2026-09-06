using GridSim
using Test
import CommonSolve
import OrdinaryDiffEq
import SciMLBase
import Observables          # the core→UI seam; also the positive control for the no-Makie test
import Graphs               # to re-derive the graph the SwingEngine builds (edge ordering)
import NetworkDynamics      # to read SwingEngine state symbolically, independently of its index vectors
import Pkg                  # to inspect the dependency closure (no-Makie invariant)

# The Iberian scenario script is a DELIVERABLE, so its claims are asserted below.
# Included as a module so the scenario data stays single-sourced (no second copy of
# the event times living in the test file) without leaking the script's constants
# into the suite's namespace. The script guards `main()` behind PROGRAM_FILE, so
# including it defines everything and runs nothing.
module Iberia
include(joinpath(@__DIR__, "..", "scripts", "iberia_2025_04_28.jl"))
end

# The two-area Iberian case (M3 step 6) is the second deliverable script, and the
# same rule applies: its claims are asserted here rather than only printed. Its own
# module for the same reason — it carries a `SHED_MW` of its own, and two scripts
# sharing the suite's namespace would silently have one shadow the other.
module IberiaTwoArea
include(joinpath(@__DIR__, "..", "scripts", "iberia_two_area.jl"))
end

# The suite is split across files (M5 step 0b). Two Julia facts make the split
# work, and both are load-bearing:
#
#   1. `include` evaluates its file at MODULE top level, never in the local scope
#      of the block the call appears in. So every shared helper had to move to
#      `helpers.jl`, included at top level - below the modules above, above the
#      outer testset. A helper left inside the outer testset would be invisible to
#      the files included from it (docs/plans/README.md, Structure notes).
#   2. `@testset` nesting is DYNAMIC, not lexical: Test.jl keeps a task-local
#      stack, so a `@testset` in an included file registers as a child of whatever
#      testset is running when the `include` executes. That is why the includes
#      below sit inside the outer testset and the summary is still one tree.
#
# The files are included in the order the testsets ran BEFORE the split, which is
# not milestone order: M3 inserted its steps 1-5 ahead of M2's own tail (the line
# trips, the UI prerequisites and the COI view), so M2 and M3 each occupy two
# files. Preserving the execution order was chosen over grouping by milestone,
# because the gate for this refactor is that nothing changed but the boundaries.

include(joinpath(@__DIR__, "helpers.jl"))

@testset "GridSim scaffold" begin

    include(joinpath(@__DIR__, "scaffold.jl"))
    include(joinpath(@__DIR__, "m1_frequency.jl"))
    include(joinpath(@__DIR__, "orchestration.jl"))
    include(joinpath(@__DIR__, "m2_network.jl"))
    include(joinpath(@__DIR__, "m3_governors_protection.jl"))
    include(joinpath(@__DIR__, "m2_events_and_coi.jl"))
    include(joinpath(@__DIR__, "m3_two_area.jl"))
    include(joinpath(@__DIR__, "m4_playback.jl"))

end
