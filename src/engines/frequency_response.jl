# PLACEHOLDER — implemented in the M1 code batch (NOT scaffolded).
#
# This is M1's first concrete engine: a real-time-steppable center-of-inertia
# aggregate frequency-response model (docs/SPEC.md §7.2, §7.4). It is intentionally
# left unimplemented at scaffold time because it carries numerics that must be
# validated against closed-form references (§7.6) before it can be trusted, and
# Julia/DifferentialEquations were not yet available when the repo was scaffolded.
#
# Implementation plan: docs/plans/m1-plan.md.
#
# Key correctness note carried forward from review (see m1-plan.md "Pitfalls"):
#   The "clamp ΔPm to aggregate headroom" requirement MUST be realised as a
#   saturation in the derivative / a solver callback — NOT as post-hoc clamping
#   of the state variable. Clamping a state without touching its derivative
#   corrupts the integration (the integrator keeps accumulating against a value
#   you silently overwrote).
#
# Outline (to satisfy the SimulationEngine contract, engines/interface.jl):
#   mutable struct FrequencyResponseEngine <: SimulationEngine ... end
#   init!(eng, model; t0, dt)   -> build ODEProblem + DiffEq integrator (Tsit5)
#   step!(eng, dt)              -> step!(integrator, dt, true); record (t, f, RoCoF)
#   current_state(eng)         -> (t, f, Δω, RoCoF, ΔPm)
#   inject!(eng, ::TripGenerator) -> drop unit, recompute H_sys/R_eq, ΔP_dist -= P_k/S_base
