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

# --- domain model (M1: minimal aggregate model; later: PowerSystems adapter) ---
include("model/system_model.jl")

# --- perturbation events (live injection) ---
include("events/events.jl")

# --- the durable SimulationEngine abstraction (SPEC §3.3) ---
include("engines/interface.jl")

# --- M1's FrequencyResponseEngine ---
# Center-of-inertia aggregate frequency model: `aggregates`, the engine struct,
# and init! / step! / current_state / inject!. The real-time orchestration loop
# (orchestration/realtime_loop.jl) is still a placeholder. See docs/plans/m1-plan.md.
include("engines/frequency_response.jl")

# --- domain model ---
export GeneratingUnit, SystemModel, example_system

# --- events ---
export PerturbationEvent, TripGenerator, StepLoad

# --- engine interface ---
# `step!`/`solve!` are CommonSolve's generics (imported in engines/interface.jl
# so we share one generic with the SciML stack); we re-export them here alongside
# our own verbs so `using GridSim` surfaces the whole interface.
export SimulationEngine
export init!, step!, solve!, current_state, state_series, inject!

# --- M1 concrete engine ---
export FrequencyResponseEngine

end # module GridSim
