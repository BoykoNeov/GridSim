"""
    GridSimUI

The GLMakie windows for GridSim's real-time engines (`docs/SPEC.md` §7.7).

There are **two**, one per fidelity tier, and the model picks which: a
`SystemModel` opens the aggregate window (a live `f(t)` plot, a RoCoF trace,
numeric readouts, per-unit trip controls, play/pause, a speed slider and an
inertia indicator), a `NetworkModel` opens the multi-machine one (per-machine
frequency traces with the centre-of-inertia aggregate overlaid, rotor angles
relative to that aggregate, event markers, and buttons for both a machine trip
and a line trip).

They are siblings rather than one window with a runtime switch, because the two
engines do not accept the same events — the set of controls a window can offer is
a property of the engine, not of the `SimulationEngine` interface, so dispatch on
the model type is what settles it (see `network_window.jl`).

Deliberately a **separate package/environment** from the core. The dependency
points one way only — `GridSimUI` uses `GridSim`, never the reverse — which is
how `docs/SPEC.md` §3.1 ("core has zero UI dependency") is enforced structurally
rather than by convention. A dependency-closure test in the core asserts the
other half: no Makie anywhere below `GridSim`.

Two entry points:

Two entry points, each with a method per model type:

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
# M2's network tier. `PerturbationEvent` rides along because `smoke_render`'s
# network method takes a timeline of *events* rather than of unit ids — this
# engine accepts two kinds, and naming the type is how a caller says which.
using GridSim: NetworkModel, SwingEngine, TripLine, machine_ids,
               PerturbationEvent, EngineEvent, event_log, n_events, describe_event
# M3's armed mechanisms. The window does not *create* any of these — it forwards
# them to the engine and then draws what the engine's own logs report, which is
# why only the ladder accessors are needed and not `ShedLadder` itself. Every name
# here was checked against `GLMakie` before a line of the panel was written (M3
# step 7); none of the thirteen candidates collides, and the explicit `using
# GridSim: x` above shadows anything that later would.
using GridSim: GenerationRamp, OutOfStepTrip, shed_ladder, shed_log

include("window.jl")
include("network_window.jl")

export launch, smoke_render, wait_for_close

end # module GridSimUI
