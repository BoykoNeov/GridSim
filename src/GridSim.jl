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
# LinearAlgebra supplies the `Diagonal` mass matrices the detailed (DAE) tier's
# vertex models carry: a zero row is an algebraic constraint, a one is a
# differential equation. An stdlib, so it adds nothing to the dependency closure
# the no-Makie invariant test walks.
import LinearAlgebra
# SparseArrays supplies the one thing M6 step 2 needs and the repo has never needed
# before: a matrix WE assemble. Every sparse structure to date has been
# NetworkDynamics' — so this is the first place `CLAUDE.md`'s "sparse from day one,
# never a dense Y-bus" binds our own code rather than a dependency's. An stdlib,
# already in the manifest transitively via the SciML stack, so it is a direct
# dependency at zero new packages (m6-context.md D2, measured at step 0 and
# confirmed by `Pkg.add`: "No packages added to or removed from Manifest").
import SparseArrays

# --- domain model (M1: minimal aggregate model; later: PowerSystems adapter) ---
include("model/system_model.jl")

# --- M2's canonical network model (buses / branches / machines) ---
# The aggregate `SystemModel` above is not replaced: at M2 step 6 it becomes a
# compiled *view* of this one (`coi_model`), per SPEC §3.2.
include("model/network_model.jl")
# The model on disk (TOML, a stdlib) with the editor's map positions beside it
# and never inside it — SPEC §3.5, render state is not simulation state.
include("model/scenario_file.jl")

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

# --- the shared run-then-playback driver (M4 step 1) ---
# The second execution mode, and the half of the engine contract that had no
# implementation anywhere until M4. Included BEFORE the engines because it
# declares the `_record_at!` hook each of them adds a method to, and each engine's
# `solve!` is one line on top of `_playback!`.
include("engines/playback.jl")

# --- M1's FrequencyResponseEngine ---
# Center-of-inertia aggregate frequency model: `aggregates`, the engine struct,
# and init! / step! / current_state / inject!. See docs/plans/m1-plan.md.
include("engines/frequency_response.jl")

# --- M2's SwingEngine ---
# Multi-machine classical (network swing) model on NetworkDynamics: per-machine
# (δ, ω) coupled through the branches, plus the inertia-weighted aggregate.
include("engines/swing.jl")

# The detailed (DAE) tier: algebraic bus voltages, machines on terminal buses, a
# stiff solver (M5 step 1). AFTER swing.jl, which owns `EngineEvent`, `_bus_pair`
# and the event-log cap this engine reuses rather than copies.
include("engines/detailed.jl")

# --- M6's steady-state ladder: the grid before anything moves ------------------
# NOT an engine and deliberately not in the mode router: a steady state is a
# function of a MODEL, nothing here steps in time, and `SimulationEngine`'s verbs
# would all be meaningless on it. Included after the engines only so that
# `branch_power`'s primary definition is still the classical tier's — the DC solve
# adds a method to that generic rather than inventing a second name for the same
# physical quantity (M5 step 7's rule).
include("steadystate/dc_powerflow.jl")

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
# M5 step 1 (docs/plans/m5-context.md D3): the canonical model gained a `Load` at a
# bus and buses that carry no machine, so it gained the views and accessors that
# make either readable. `branch_topology` is `branch_arrays` minus `K` — the part
# that needs no machine at either end — and `machines_at`/`load_at` are the
# bus-indexed lookups `machine_at` can no longer stand in for.
#
# All five checked clear against GLMakie's exports before being added, the standing
# check since M1: `Load`, `load_arrays`, `branch_topology`, `machines_at`, `load_at`.
export Load, load_arrays, branch_topology, machines_at, load_at
export two_machine_system, three_machine_ring
# The scenario file: a `NetworkModel` round-tripped through TOML, with the map
# layout as a separate return rather than a field of `Bus`. `Layout` is a type
# alias the editor names in a signature. All three checked clear against GLMakie's
# exports before being added (2026-09-07) — the standing check.
export write_scenario, read_scenario, Layout
# M6 step 1 — a bus's role in a power flow, DERIVED from the declared slack and
# what is attached rather than stored (`m6-context.md` D3). Both checked clear
# against GLMakie's exports before being added (2026-09-07) — the standing check
# since M1, when a collision cost a round.
export bus_roles, bus_role
# M6 step 2 — the linear (DC) power flow. `bus_injections` joins the derived-view
# family (`machine_arrays`, `load_arrays`, `branch_topology`): the net scheduled
# injection per bus, in pu, computed in the one place the conversion happens.
# `branch_power` is deliberately NOT here — the DC solve adds a method to the
# generic the two dynamic tiers already answer to. All four checked clear against
# `names(GLMakie)` before being added (2026-09-07) — the standing check since M1.
export DCPowerFlow, dc_powerflow, bus_angle, bus_injections
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
# `divergence`, `system_frequency` and `tolerance_band` are M4 step 2's cross-tier
# read. They went through the same `intersect(names(GridSim), names(GLMakie))`
# check as every earlier export — empty, on Julia 1.12.6 / GLMakie 0.13.13
# (2026-09-02, the session that merged step 2; it could not be run in the session
# that wrote it).
export windowed_rocof, divergence, system_frequency, tolerance_band
# `convergence_band` moved here from `reference/src/oracle.jl` in M5 step 2, where it
# was `oracle_band`: the derivation (each side's error estimated by its OWN
# convergence, summed through the triangle inequality) has nothing to do with
# PowerDynamics, and the internal classical-vs-detailed comparison is the same
# explicit-against-stiff shape. `oracle_band` is now a one-line call to it.
# Checked clear against GLMakie's exports before being added — the standing check.
export convergence_band

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
# The active power on one branch, `from → to`, in pu — ONE name for both tiers
# (M5 step 7). `K·sin(δ)` at the classical tier and `Re(V·conj(I))` at the detailed
# one are the same physical quantity, and the milestone's criterion compares them
# across the two, so writing them out twice at two call sites is exactly the
# orientation/sign mistake this export exists to make impossible. Checked clear
# against GLMakie's exports before being added — the standing check since M1.
export branch_power, branch_power_series
# The detailed (DAE) tier (M5 step 1). `DetailedEngine` and `load_bus_system` both
# checked clear against GLMakie's exports before being added — the standing check
# since M1. Everything else it answers to (`init!`, `solve!`, `state_series`,
# `inject!`, `current_state`, `is_online`, `event_log`, `system_inertia`) is an
# existing generic it adds a method to, which is the whole point of the interface.
export DetailedEngine
export load_bus_system
# M5 step 4's two fixtures. They live in `src` rather than in a test file
# because BOTH the core suite and `reference/` need them, and a fixture
# maintained in two places is the forked-data hazard SPEC §3.2 forbids —
# `detailed_pair` in particular was a `reference/test` local until step 4.
export detailed_pair, infinite_bus_system
# M5 step 5's fixture, here for the same reason: `reference/` runs the unlimited
# exciter against PowerDynamics on it, and the core suite runs the limited one.
export regulator_bus_system
# M5 step 8's fixture — the M3 governed ring, promoted out of `test/helpers.jl`
# when a THIRD consumer appeared (the UI's voltage window and its tests). Its
# `detailed` keyword makes one definition produce both models the cross-tier
# comparison needs. Checked clear against GLMakie's exports before being added —
# the standing check.
export governed_ring
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
