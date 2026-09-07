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

A **third** window is the other execution mode rather than a third tier: the
playback overlay (`playback_window.jl`, M4 step 3) draws two *already-solved*
series of one scenario — the network swing tier against the aggregate view
compiled down from the same model — with a slider that scrubs a cursor through
the run and the cross-tier divergence read beside it. It has no event queue, no
control block and no repaint throttle, because nothing in it is running.

A **fourth** (`voltage_window.jl`, M5 step 8) is the same execution mode one tier
up: the classical tier against the detailed (DAE) one, with **bus voltage
magnitude** drawn beside the frequency both tiers report. It exists to keep the
voltage half of a promise `docs/plans/m4-plan.md` wrote on M5's behalf — the third
window's own caption says its pair can never show voltage, because neither of its
tiers carries one as an unknown. The inverter half of that promise is *not* kept
and does not become kept by proximity (`m5-context.md` D12).

The first two are siblings rather than one window with a runtime switch, because
the two engines do not accept the same events — the set of controls a window can offer is
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

...and the same pair again for playback, under their own verbs, because the model
type cannot say which mode was wanted: [`playback`](@ref) and
[`playback_render`](@ref).
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
# M4's playback mode. `solve!` and `state_series` are the run-then-play half of
# the engine interface; `coi_model` compiles the aggregate view down from the
# network model (never a parallel copy); `divergence`, `system_frequency` and
# `tolerance_band` are step 2's cross-tier read, and this window only DISPLAYS
# what they return. `three_machine_ring` rides along as the default fixture — a
# single synchronous area, which is the precondition the overlay needs (D5).
# All seven checked against GLMakie's exports by the core's own
# `intersect(names(GridSim), names(GLMakie))` test before being named here.
using GridSim: solve!, state_series, coi_model,
               divergence, system_frequency, tolerance_band, three_machine_ring
# M5 step 8's voltage-visible window (`voltage_window.jl`). `DetailedEngine` is the
# tier that carries bus voltage as an algebraic unknown; `governed_ring` is the ONE
# core definition that produces both this window's models (its `detailed` keyword
# sets exactly the fields `SwingEngine` refuses); `machine_at` is how the bus a
# voltage channel names is tied to the machine whose constant is drawn beside it —
# by lookup and never by position, because a transposed mapping on this fixture
# draws a nearly identical picture. `GenerationRamp` is the disturbance, armed at
# construction on both tiers because it is the only strong one they both accept.
# All four checked clear against GLMakie's exports before being named here — the
# standing check, empty on Julia 1.12.6 / GLMakie 0.13.13.
using GridSim: DetailedEngine, governed_ring, machine_at
# The precompile workload (`precompile.jl`) drives the armed network window on
# the two-machine fixture; nothing in the windows themselves needs this name.
using GridSim: two_machine_system
# The scenario editor (`editor.jl`, `editor_window.jl`). It builds the model the
# other windows are handed, so it needs the four record types and the model's own
# constructor, plus the file pair and the `Layout` alias for the map positions.
# All checked clear against GLMakie's exports (the standing check, 2026-09-07).
using GridSim: Bus, Branch, Machine, Load, Layout, write_scenario, read_scenario

# The shared look (fonts, colours, widget shapes, the two-label read-out) — one
# file, applied by every builder through `themed`. Included first because the
# windows reference its constants at definition time.
include("theme.jl")
include("window.jl")
include("network_window.jl")
include("playback_window.jl")
include("voltage_window.jl")
include("editor.jl")
include("editor_window.jl")

export launch, smoke_render, wait_for_close
# M4 step 3, a DIFFERENT VERB rather than a third `launch` method: both execution
# modes run on the same `NetworkModel`, so the model type cannot pick between
# them. The core draws the same line the same way — `run_realtime!` against
# `solve!` — so the UI mirrors it instead of inventing a type to dispatch on.
export playback, playback_render
# M5 step 8, the fourth window and the second in playback mode: the classical tier
# against the detailed one with BUS VOLTAGE drawn, which is the half of M4's written
# promise this milestone owed. Its own verb pair again, for M4's reason — the model
# type cannot say which execution mode, or which tier pair, was wanted.
export voltage_playback, voltage_playback_render
# The scenario editor — a window with no engine in it, whose product is the model
# the others start from. Its editing operations are exported too, because they are
# the same functions the mouse handlers call, and a script (or a test) building a
# scenario should not have to reach through a figure to do it.
export editor, editor_render, ScenarioEditor,
       add_bus!, add_machine!, add_load!, add_branch!, move_bus!, remove!, rename!,
       set_field!, build_model, validation, power_balance, save!, load!

# Last, after every entry point exists: build each window once at precompile
# time so a session does not pay ~2 minutes of Makie specialisation at launch.
include("precompile.jl")

end # module GridSimUI
