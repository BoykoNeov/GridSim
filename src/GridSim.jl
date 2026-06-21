"""
    GridSim

Headless core of the GridSim power-grid simulator: domain model, perturbation
events, and the `SimulationEngine` abstraction. **No UI / plotting dependency**
lives here — that invariant is enforced structurally (the UI lives in `ui/`,
which depends on this package, never the reverse). See `docs/SPEC.md`.
"""
module GridSim

# --- domain model (M1: minimal aggregate model; later: PowerSystems adapter) ---
include("model/system_model.jl")

# --- perturbation events (live injection) ---
include("events/events.jl")

# --- the durable SimulationEngine abstraction (SPEC §3.3) ---
include("engines/interface.jl")

# Concrete engines are added per milestone. M1's `FrequencyResponseEngine`
# (engines/frequency_response.jl) and the real-time orchestration loop
# (orchestration/realtime_loop.jl) require DifferentialEquations.jl plus
# closed-form numerical validation, so they are implemented in the M1 code
# batch — not scaffolded here. See docs/plans/m1-plan.md.

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

end # module GridSim
