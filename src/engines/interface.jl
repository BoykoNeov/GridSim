# The durable abstraction (docs/SPEC.md §3.3).
#
# The orchestration layer talks to every fidelity/mode through this one
# interface. Real-time engines implement `init!`/`step!`/`inject!`; playback
# engines implement `init!`/`solve!`/`state_series`. The UI is mode-agnostic.
#
# `init!`, `current_state`, `state_series`, and `inject!` are GridSim-owned
# generic functions with no methods yet — each concrete engine adds the subset
# its mode needs. `step!` and `solve!` are NOT ours to define: they belong to
# CommonSolve.jl (the zero-dependency interface package that SciMLBase →
# OrdinaryDiffEq/DifferentialEquations all re-export). We `import` and extend
# those so that the engine's `step!(integrator, dt, true)` and our
# `step!(engine, dt)` are methods of one generic — no name collision once a
# DiffEq package is loaded. See docs/plans/m1-plan.md (Pitfalls).
#
# This file is a *contract*, not an implementation; it carries no numerics and
# is safe to ship at scaffold time. The first concrete engine
# (FrequencyResponseEngine) is built in the M1 code batch.

# `step!`/`solve!` come from CommonSolve so we share one generic with the SciML
# stack. (CommonSolve exports `init` — without the bang — so our `init!` below
# stays uniquely GridSim's and needs no import.)
import CommonSolve: step!, solve!

"""
    SimulationEngine

Abstract supertype for all simulation engines, across both execution modes
(real-time injection and run-then-playback) and all fidelity tiers.
"""
abstract type SimulationEngine end

# --- lifecycle -----------------------------------------------------------

"""
    init!(EngineType, model; t0=0.0, dt, ...) -> engine

Build an engine's problem/integrator from a domain `model`. Real-time engines
construct a steppable integrator here. Dispatched on the engine **type** and
returning a freshly built instance (rather than mutating one in place): an engine
parameterised on its concrete integrator type cannot exist before that integrator
does, so there is no half-built instance to mutate — `init!` is the constructor of
record. See `engines/frequency_response.jl` for the canonical implementation.
"""
function init! end

# step!(engine, dt)
#   Advance a real-time engine by `dt` (wall-clock-paced by the orchestration
#   loop), recording the trajectory point. Extends CommonSolve.step! — the
#   method is added by each real-time engine in its own batch.
#
# solve!(engine, tspan; perturbations=[], saveat=timestep(engine))
#   Solve a whole horizon offline (playback engines), recording onto a chosen
#   output grid and returning the trajectory. Extends CommonSolve.solve!. The
#   shared driver is `engines/playback.jl`; each engine adds a one-line method.
#
#   `perturbations` carries SCHEDULED events only — `t => event` pairs, applied at
#   exactly that instant through the same `inject!` the real-time loop uses.
#
#   IT DOES NOT CARRY PROTECTION, AND AN EARLIER VERSION OF THIS COMMENT SAID
#   OTHERWISE. Until M4 the line above read "perturbations are supplied up front
#   rather than injected live", which was written before there was anything to
#   falsify it. M3 falsified it: a load-shedding ladder and an out-of-step relay
#   fire on the system's own state, at an instant nobody can know in advance, so
#   there is no "up front" to supply them at. They stay exactly where the engine
#   constructor puts them — as root-finding solver callbacks — in BOTH execution
#   modes. Playback changes who drives the integrator, not what the physics is
#   allowed to do; if it changed the latter, a playback run and a real-time run of
#   one scenario would be two different systems and no comparison between them
#   would mean anything (m4-context.md D4).

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

"""
    timestep(engine) -> Float64

The engine's natural real-time step (s). The orchestration loop asks for this
rather than hard-coding a `dt`, so each fidelity tier can carry its own sensible
cadence and the loop stays engine-agnostic. Real-time engines implement it; a
caller may still override the loop's `dt` explicitly.
"""
function timestep end

# --- live perturbation (real-time engines) ------------------------------

"""
    inject!(engine, event::PerturbationEvent)

Apply a queued perturbation at a step boundary. For real-time engines the
continuous state is preserved across the event where the physics allows it
(true for M1's COI model — only parameters change).
"""
function inject! end

# --- the frequency read-outs (M7 step 6) ------------------------------------

"""
    coi_rocof(engine) -> Float64

The **instantaneous** centre-of-inertia RoCoF in Hz/s at the engine's current state,
`f0·dω_coi/dt`, read off the model's OWN right-hand side — never differenced from
recorded samples (a difference of samples is a windowed RoCoF with the window set to
the sample step, which would quietly turn the three read-outs below into two).

It is the first of the **three RoCoFs** this repo reports under three names, and
never as "the" RoCoF (M7 Hurdle 10 claim 2):

  1. `coi_rocof(engine)` — the derivative of the inertia-weighted system frequency.
     What the closed forms predict (`RoCoF₀ = −f0·ΔP/(2·H_sys)` at an event). A
     LIVE read: read it right after `inject!` for the value at `t⁺`.
  2. the **windowed** centre-of-inertia RoCoF — `windowed_rocof` on `f_coi` over a
     stated window, what an operator's report quotes (ENTSO-E's 500 ms).
  3. the **PLL-measured** RoCoF — the same `windowed_rocof`, same window, on a PLL's
     frequency estimate at a bus: what a relay there actually reads. A phase jump,
     which changes no frequency anywhere, reads in it as a spike.

2 and 3 are [`rocof_readouts`](@ref), side by side. 1 is not recorded as a channel,
deliberately: the reference oracle mirrors `state_series(::DetailedEngine)` channel
for channel, and a right-hand-side derivative has no counterpart there.

Refuses by name when no inertia is online — the weights sum to zero and there is no
system frequency to differentiate (Hurdle 10 claim 3). The live `f_coi` channel of a
`SwingEngine` with everything tripped still reads `NaN`, the M2 decision the network
window's test pins; the refusal lives in the read-outs M7 added.
"""
function coi_rocof end
