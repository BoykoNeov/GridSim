# The durable abstraction (docs/SPEC.md §3.3).
#
# The orchestration layer talks to every fidelity/mode through this one
# interface. Real-time engines implement `init!`/`step!`/`inject!`; playback
# engines implement `init!`/`solve!`/`state_series`. The UI is mode-agnostic.
#
# These are generic functions with no methods yet — each concrete engine adds
# the subset its mode needs. This file is a *contract*, not an implementation;
# it carries no numerics and is safe to ship at scaffold time. The first
# concrete engine (FrequencyResponseEngine) is built in the M1 code batch.

"""
    SimulationEngine

Abstract supertype for all simulation engines, across both execution modes
(real-time injection and run-then-playback) and all fidelity tiers.
"""
abstract type SimulationEngine end

# --- lifecycle -----------------------------------------------------------

"""
    init!(engine, model; t0=0.0, dt)

Build the engine's problem/integrator from a domain `model`. Real-time engines
construct a steppable integrator here.
"""
function init! end

"""
    step!(engine, dt)

Advance a real-time engine by `dt` (wall-clock-paced by the orchestration loop),
recording the trajectory point.
"""
function step! end

"""
    solve!(engine, tspan; perturbations=[])

Solve a whole horizon offline (playback engines). Perturbations are supplied up
front rather than injected live.
"""
function solve! end

# --- state access (mode-agnostic) ---------------------------------------

"""
    current_state(engine)

Named state at "now" — e.g. `(t, f, Δω, RoCoF, ΔPm)` for the frequency engine.
"""
function current_state end

"""
    state_series(engine)

The full recorded trajectory (after `solve!`, or accumulated by `step!`), for
playback/plotting.
"""
function state_series end

# --- live perturbation (real-time engines) ------------------------------

"""
    inject!(engine, event::PerturbationEvent)

Apply a queued perturbation at a step boundary. For real-time engines the
continuous state is preserved across the event where the physics allows it
(true for M1's COI model — only parameters change).
"""
function inject! end
