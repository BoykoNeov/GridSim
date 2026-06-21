# M1's first concrete engine: a real-time-steppable center-of-inertia aggregate
# frequency-response model (docs/SPEC.md §7.2, §7.4). Built incrementally in the
# M1 code batch; see docs/plans/m1-plan.md.
#
# Key correctness note carried forward from review (see m1-plan.md "Pitfalls"):
#   The "clamp ΔPm to aggregate headroom" requirement MUST be realised as a
#   saturation in the derivative / a solver callback — NOT as post-hoc clamping
#   of the state variable. Clamping a state without touching its derivative
#   corrupts the integration (the integrator keeps accumulating against a value
#   you silently overwrote).
#
# Still to come in later steps of this batch:
#   mutable struct FrequencyResponseEngine <: SimulationEngine ... end
#   init!(eng, model; t0, dt)   -> build ODEProblem + Tsit5 integrator
#   step!(eng, dt)              -> step!(integrator, dt, true); record (t, f, RoCoF)
#   current_state(eng)         -> (t, f, Δω, RoCoF, ΔPm)
#   inject!(eng, ::TripGenerator) -> drop unit, recompute H_sys/R_eq, ΔP_dist -= P_k/S_base

"""
    aggregates(model::SystemModel, online) -> (; H_sys, R_eq, D, Tg)

Center-of-inertia aggregates for the units in `online`, on the system base
`model.S_base` (docs/SPEC.md §7.2). `online` is any collection of unit ids
(`Symbol`s) that membership-tests with `in` (e.g. a `Set{Symbol}`).

  - `H_sys = Σ Hᵢ·(Sᵢ/S_base)`      — system inertia constant (s), on system base.
  - `1/R_eq = Σ (1/Rᵢ)·(Sᵢ/S_base)` — aggregate droop gain (pu/pu); `R_eq` is its
    reciprocal. With no online units (or no droop) `R_eq = Inf` (zero gain).
  - `D`, `Tg` are system-wide constants, passed through from `model`.

Pure function of the model and the online set — the engine calls it at `init!`
and again after every `TripGenerator` to refresh its parameter struct.
"""
function aggregates(model::SystemModel, online)
    S_base = model.S_base
    H_sys = 0.0
    inv_R_eq = 0.0
    for u in model.units
        u.id in online || continue
        w = u.S_rated / S_base          # unit's MVA weight on the system base
        H_sys += u.H * w
        inv_R_eq += (1.0 / u.R) * w
    end
    R_eq = inv_R_eq == 0.0 ? Inf : 1.0 / inv_R_eq
    return (; H_sys, R_eq, D = model.D, Tg = model.Tg)
end
