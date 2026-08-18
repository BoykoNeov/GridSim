"""
    GridSimUI

The GLMakie window for GridSim's real-time engines (`docs/SPEC.md` §7.7): a live
`f(t)` plot, numeric readouts, per-unit trip controls, play/pause, a speed
slider, and an inertia indicator.

Deliberately a **separate package/environment** from the core. The dependency
points one way only — `GridSimUI` uses `GridSim`, never the reverse — which is
how `docs/SPEC.md` §3.1 ("core has zero UI dependency") is enforced structurally
rather than by convention. A dependency-closure test in the core asserts the
other half: no Makie anywhere below `GridSim`.

Two entry points:

  - [`launch`](@ref) — open the real window and drive it in real time.
  - [`smoke_render`](@ref) — build the *same* window offscreen, run a scripted
    trip timeline flat out, and save a PNG. That is how the window is checked in
    a session with no screen to look at.
"""
module GridSimUI

using GLMakie
using Printf: @sprintf

# Explicit, name-by-name imports from the core — not `using GridSim`. Deliberate:
# two large export sets in one scope clash silently, because Julia only reports an
# ambiguity when the contested name is *referenced*, i.e. mid-file at run time.
# The M1 task list flagged exactly this hazard for `stop!`, `timestep`, `drain!`,
# `shed_log`, `shed_total`, `windowed_rocof`, `LoadShedStage`, `ShedLadder` against
# GLMakie. Naming what we use settles it up front: an explicit `using M: x` binds
# the name in this module and outright shadows anything a wholesale `using` brings
# in, so the collision cannot bite later.
using GridSim: SystemModel, GeneratingUnit, example_system,
               FrequencyResponseEngine, LoadShedStage,
               TripGenerator, StepLoad,
               EventQueue, RealtimeControl, run_realtime!,
               init!, current_state, inject!, timestep, stop!,
               system_inertia, is_online

include("window.jl")

export launch, smoke_render, wait_for_close

end # module GridSimUI
