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

# --- domain model (M1: minimal aggregate model; later: PowerSystems adapter) ---
include("model/system_model.jl")

# --- perturbation events (live injection) ---
include("events/events.jl")

# --- the durable SimulationEngine abstraction (SPEC §3.3) ---
include("engines/interface.jl")

# --- M1's FrequencyResponseEngine ---
# Center-of-inertia aggregate frequency model: `aggregates`, the engine struct,
# and init! / step! / current_state / inject!. See docs/plans/m1-plan.md.
include("engines/frequency_response.jl")

# --- real-time orchestration (event queue + wall-clock-paced loop) ---
# Engine-agnostic: speaks only the SimulationEngine verbs. Uses Observables to
# publish live state; never Makie (see the invariant note in the file itself).
include("orchestration/realtime_loop.jl")

# --- domain model ---
export GeneratingUnit, SystemModel, example_system

# --- events ---
export PerturbationEvent, TripGenerator, StepLoad

# --- engine interface ---
# `step!`/`solve!` are CommonSolve's generics (imported in engines/interface.jl
# so we share one generic with the SciML stack); we re-export them here alongside
# our own verbs so `using GridSim` surfaces the whole interface.
export SimulationEngine
export init!, step!, solve!, current_state, state_series, inject!, timestep

# --- M1 concrete engine ---
export FrequencyResponseEngine

# --- real-time orchestration ---
# (`push!`/`isempty`/`length`/`empty!` on an EventQueue are Base generics we
# extend, not ours to export.)
export EventQueue, drain!, RealtimeControl, stop!, run_realtime!

end # module GridSim
