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
#   inject!(eng, ::TripGenerator) -> drop unit, recompute aggregates, ΔP_dist -= P_k/S_base
#
# The numerical guard against small adaptive-step overshoot above `headroom`
# (an `isoutofdomain` predicate / thin callback on the integrator) lands with
# `init!` in the next step — it rides on top of the derivative saturation below,
# and is stable precisely because the derivative is already zeroed at the ceiling.

"""
    aggregates(model::SystemModel, online) -> (; H_sys, R_eq, D, Tg, headroom)

Center-of-inertia aggregates for the units in `online`, on the system base
`model.S_base` (docs/SPEC.md §7.2). `online` is any collection of unit ids
(`Symbol`s) that membership-tests with `in` (e.g. a `Set{Symbol}`).

  - `H_sys = Σ Hᵢ·(Sᵢ/S_base)`      — system inertia constant (s), on system base.
  - `1/R_eq = Σ (1/Rᵢ)·(Sᵢ/S_base)` — aggregate droop gain (pu/pu); `R_eq` is its
    reciprocal. With no online units (or no droop) `R_eq = Inf` (zero gain).
  - `headroom = Σ (Pmaxᵢ − P0ᵢ)/S_base` — aggregate up-reserve (pu on S_base);
    the ceiling at which `ΔPm` saturates (the governors can ramp no further).
  - `D`, `Tg` are system-wide constants, passed through from `model`.

Every one of these is recomputed after a `TripGenerator`: a tripped unit takes
its inertia, its droop gain, **and its own headroom** out of the pool. Pure
function of the model and the online set — the engine calls it at `init!` and
again after every trip to refresh its parameter struct.
"""
function aggregates(model::SystemModel, online)
    S_base = model.S_base
    H_sys = 0.0
    inv_R_eq = 0.0
    headroom = 0.0
    for u in model.units
        u.id in online || continue
        w = u.S_rated / S_base          # unit's MVA weight on the system base
        H_sys += u.H * w
        inv_R_eq += (1.0 / u.R) * w
        headroom += (u.Pmax - u.P0) / S_base   # up-reserve, pu on system base
    end
    R_eq = inv_R_eq == 0.0 ? Inf : 1.0 / inv_R_eq
    return (; H_sys, R_eq, D = model.D, Tg = model.Tg, headroom)
end

"""
    FRParams

Mutable parameter block for the frequency-response ODE. Holds the center-of-
inertia aggregates plus the running disturbance imbalance. **Mutable so live
events can change it** (a `TripGenerator` recomputes the aggregates and bumps
`ΔP_dist`) while the integrator keeps the continuous state `(Δω, ΔPm)` — but
every field is concrete (`Float64`), so the RHS hot path stays type-stable
(docs/SPEC.md §4 "Type stability"; m1-plan.md "Pitfalls").

  - `H_sys`   — system inertia (s), on `S_base`.
  - `R_eq`    — aggregate droop (pu/pu); `Inf` ⇒ no droop gain.
  - `D`       — load damping (pu/pu).
  - `Tg`      — governor/turbine lag (s).
  - `ΔP_dist` — persistent power imbalance (pu on `S_base`); a generation trip
                drives it negative (lost generation), so frequency dips.
  - `headroom`— aggregate up-reserve (pu on `S_base`); `ΔPm` saturates here.
"""
mutable struct FRParams
    H_sys::Float64
    R_eq::Float64
    D::Float64
    Tg::Float64
    ΔP_dist::Float64
    headroom::Float64
end

"""
    fr_rhs!(du, u, p::FRParams, t)

In-place RHS of the two-state center-of-inertia frequency model (docs/SPEC.md
§7.2). State `u = (Δω, ΔPm)` — per-unit frequency deviation and the governors'
aggregate extra mechanical power (pu on `S_base`). Both are *deviations* from the
pre-disturbance operating point, so the system starts at the origin.

  - Swing:    `dΔω/dt  = (ΔPm − D·Δω + ΔP_dist) / (2·H_sys)`
  - Governor: `dΔPm/dt = (−Δω/R_eq − ΔPm) / Tg`,  **saturated at `headroom`**.

The headroom saturation is realised as a **saturation in the derivative**, not a
post-hoc clamp of the state: when `ΔPm` is already at the ceiling and the governor
term would push it higher, that derivative component is zeroed. This is the
correctness landmine carried forward from review — clamping the *state* while its
derivative still drives upward corrupts the integration (the integrator keeps
accumulating against a value you silently overwrote). Zeroing the *derivative*
also gives **release for free**: once `Δω` recovers and the governor term turns
negative, the condition stops firing and `ΔPm` comes off the ceiling on its own.
"""
function fr_rhs!(du, u, p::FRParams, t)
    Δω, ΔPm = u[1], u[2]
    # Swing equation: net torque / (2·H) sets the rate of change of speed.
    du[1] = (ΔPm - p.D * Δω + p.ΔP_dist) / (2 * p.H_sys)
    # Governor/turbine first-order lag toward the droop-commanded power.
    # (R_eq = Inf ⇒ −Δω/R_eq = 0; no droop response, no NaN.)
    dΔPm = (-Δω / p.R_eq - ΔPm) / p.Tg
    # Saturation in the derivative: hold ΔPm at the aggregate up-headroom.
    if ΔPm >= p.headroom && dΔPm > 0
        dΔPm = 0.0
    end
    du[2] = dΔPm
    return nothing
end
