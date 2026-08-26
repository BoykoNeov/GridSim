"""
    GridSim

Headless core of the GridSim power-grid simulator: domain model, perturbation
events, and the `SimulationEngine` abstraction. **No UI / plotting dependency**
lives here — that invariant is enforced structurally (the UI lives in `ui/`,
which depends on this package, never the reverse). See `docs/SPEC.md`.
"""
module GridSim

# OrdinaryDiffEq supplies the integrator the FrequencyResponseEngine wraps
# (`ODEProblem`, `init`, `Tsit5`, and the `step!`/`solve!` methods it re-exports
# from CommonSolve). Imported here so `engines/frequency_response.jl` can reach it.
import OrdinaryDiffEq
# SciMLBase is the public home of the integrator-control verbs we need at event
# boundaries: `derivative_discontinuity!` (signal a discrete state/parameter jump so
# the FSAL derivative cache is invalidated) and `successful_retcode` (detect an
# aborted integration). OrdinaryDiffEq does not re-export these at top level.
import SciMLBase
# Observables is how live state crosses the core→UI seam (docs/SPEC.md §3.1): the
# orchestration loop writes each new state into an Observable and the UI reacts.
# It is a standalone package — Makie depends on it, not the reverse — so it is
# safe in the UI-free core. NOT `using`: the loop refers to `Observables.Observable`
# explicitly so nothing about the seam is implicit.
import Observables
# Graphs supplies the plain graph type NetworkDynamics builds a `Network` on, and
# — already at model-construction time — the connectivity check that rejects a
# network split into islands. Imported (not `using`) so every call site says
# `Graphs.` and nothing about the graph layer is implicit.
import Graphs
# NetworkDynamics compiles the M2 network model into the ODE the SwingEngine
# integrates: one vertex model per machine, one edge model per branch, coupling
# carried on graph edges rather than in an admittance matrix (D3). Imported (not
# `using`) so every call site names it — including `NetworkDynamics.SII`, the
# symbolic-indexing interface the engine uses to resolve flat state/parameter
# positions instead of assuming a memory layout.
import NetworkDynamics

# --- domain model (M1: minimal aggregate model; later: PowerSystems adapter) ---
include("model/system_model.jl")

# --- M2's canonical network model (buses / branches / machines) ---
# The aggregate `SystemModel` above is not replaced: at M2 step 6 it becomes a
# compiled *view* of this one (`coi_model`), per SPEC §3.2.
include("model/network_model.jl")

# --- perturbation events (live injection) ---
include("events/events.jl")

# --- protection schemes (armed, state-triggered — not user-injected) ---
# Low-frequency load shedding as a root-finding ContinuousCallback per stage.
include("protection/load_shedding.jl")
# Out-of-step (pole-slip) tripping of a tie, likewise root-found (M3 step 4, D6).
include("protection/out_of_step.jl")

# --- scenario inputs (scheduled, armed at construction — not user-injected) ---
# A generation loss that arrives over seconds rather than instantly (M3 step 5, D7).
include("scenarios/generation_ramp.jl")

# --- the durable SimulationEngine abstraction (SPEC §3.3) ---
include("engines/interface.jl")

# --- shared bounded trajectory recording (engines/recorder.jl) ---
# Every engine records through this rather than growing its own vectors: a live
# run that is never stopped would otherwise allocate without bound. Internal (not
# exported) — engines expose their history through `state_series`.
include("engines/recorder.jl")

# --- M1's FrequencyResponseEngine ---
# Center-of-inertia aggregate frequency model: `aggregates`, the engine struct,
# and init! / step! / current_state / inject!. See docs/plans/m1-plan.md.
include("engines/frequency_response.jl")

# --- M2's SwingEngine ---
# Multi-machine classical (network swing) model on NetworkDynamics: per-machine
# (δ, ω) coupled through the branches, plus the inertia-weighted aggregate.
include("engines/swing.jl")

# --- post-processing reads over a recorded trajectory ---
# Engine-agnostic; notably the 500 ms windowed RoCoF that report figures use.
include("analysis/postprocess.jl")

# --- real-time orchestration (event queue + wall-clock-paced loop) ---
# Engine-agnostic: speaks only the SimulationEngine verbs. Uses Observables to
# publish live state; never Makie (see the invariant note in the file itself).
include("orchestration/realtime_loop.jl")

# --- domain model ---
export GeneratingUnit, SystemModel, example_system

# --- M2 network model ---
# `machine_arrays`/`branch_arrays` are the derived struct-of-arrays views the
# engine integrates against (and the only place the per-unit conversion to the
# system base happens). All of these names were checked clear against GLMakie's
# exports before being added — the collision hazard that cost a round in M1.
export Bus, Branch, Machine, NetworkModel
export machine_arrays, branch_arrays, machine_at
export two_machine_system, three_machine_ring
# The aggregate view, compiled down from the network model (SPEC §3.2, D4) — never
# a hand-maintained parallel copy. This is what lets M1's engine run on an M2 model.
export coi_model

# --- events ---
export PerturbationEvent, TripGenerator, StepLoad, TripLine

# --- protection ---
export LoadShedStage, ShedLadder, shed_log, shed_total, shed_ladder
# Out-of-step protection: the inert setting, the live relay, its log and the
# engine's accessor. All four checked clear against GLMakie's exports before being
# added (`intersect(names(GridSim), names(GLMakie))` is still empty) — the collision
# hazard that cost a round in M1. `disarm!` stays internal for `ShedLadder`'s reason.
export OutOfStepTrip, OutOfStepRelay, out_of_step_log, out_of_step_relay

# --- scenario inputs ---
# The scheduled generation ramp and the engine's read-back of what was armed (M3
# step 5). Both checked clear against GLMakie's exports before being added — the
# collision hazard that has now cost a round twice. Deliberately only two names: a
# `ramp_magnitude(r) = r.rate * r.duration` helper was considered and dropped, since
# a one-line product is not worth a third export to keep clear.
export GenerationRamp, generation_ramp

# --- post-processing ---
export windowed_rocof

# --- engine interface ---
# `step!`/`solve!` are CommonSolve's generics (imported in engines/interface.jl
# so we share one generic with the SciML stack); we re-export them here alongside
# our own verbs so `using GridSim` surfaces the whole interface.
export SimulationEngine
export init!, step!, solve!, current_state, state_series, inject!, timestep

# --- M1 concrete engine ---
export FrequencyResponseEngine
# Live reads the UI needs and the interface verbs do not cover (H_sys indicator,
# per-unit trip-button state) — exported so `ui/` never touches engine fields.
export system_inertia, is_online

# --- M2 concrete engine ---
# `machine_ids` is the per-machine counterpart of `system_inertia`/`is_online`:
# the read `ui/` needs to label traces without touching engine fields. Both names
# checked clear against GLMakie's exports before being added.
export SwingEngine, machine_ids
# The applied-event record the trajectory deliberately does not carry (a line trip
# leaves no channel behind, and a one-sample marker is what decimation deletes —
# see the head of `engines/swing.jl`). `describe_event` gives a window and a
# headless report one shared wording for an event.
#
# All five checked clear against GLMakie's exports, and two names were rejected on
# the way: the obvious `events` is NOT clear (hence `event_log`), and the obvious
# `describe` is clear of GLMakie but is exactly the kind of generic verb another
# package in the same session will also export (DataFrames does), so it is
# `describe_event` — a collision that costs nothing to avoid and a round to fix.
export EngineEvent, event_log, n_events, n_events_dropped, describe_event

# --- real-time orchestration ---
# (`push!`/`isempty`/`length`/`empty!` on an EventQueue are Base generics we
# extend, not ours to export.)
export EventQueue, drain!, RealtimeControl, stop!, run_realtime!

end # module GridSim
