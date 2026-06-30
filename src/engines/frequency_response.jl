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
# The numerical guard against small adaptive-step overshoot above `headroom` is an
# `isoutofdomain` predicate on the integrator (see `_fr_outofdomain` / `init!`
# below): it *rejects and retries* an offending step, never overwriting the state,
# so it is consistent with the no-post-hoc-clamp rule and rides on top of the
# derivative saturation. It cannot stall, because the derivative is already zeroed
# at the ceiling (`du[2]=0` there ⇒ the solution sits at `ΔPm=headroom`, which is
# `== headroom`, not `> headroom`, so the predicate does not fire).
#
# The engine struct + init!/step!/current_state/inject! live at the bottom of this
# file (built in the M1 code batch; see docs/plans/m1-plan.md step 4).

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

# ---------------------------------------------------------------------------
# FrequencyResponseEngine — the real-time-steppable engine (docs/SPEC.md §7.4,
# m1-plan.md step 4). Wraps an OrdinaryDiffEq integrator over `fr_rhs!`, exposes
# the `SimulationEngine` verbs, and lets a `TripGenerator` change the live system
# while the continuous state `(Δω, ΔPm)` carries through untouched.
# ---------------------------------------------------------------------------

const _FR_DT0 = 0.02   # default real-time step (s)

# `isoutofdomain` guard: reject any proposed step that lifts ΔPm above the
# aggregate headroom (with a roundoff tolerance so a step landing exactly on the
# ceiling is not spuriously rejected). This only ever rejects+retries a step —
# it never writes the state — so it is NOT the forbidden post-hoc clamp; the
# derivative saturation in `fr_rhs!` does the physical work, this just absorbs
# adaptive-step overshoot on top of it.
_fr_outofdomain(u, p::FRParams, t) = u[2] > p.headroom + 1e-10

"""
    FrequencyResponseEngine{I} <: SimulationEngine

Real-time center-of-inertia frequency engine. Type parameter `I` is the concrete
integrator type — pinning it keeps the per-`dt` `step!(eng)` boundary type-stable
(the RHS hot path is already stable via the concrete `FRParams`). Built through
the `init!`/constructor below, never by filling fields by hand.

Fields: the canonical `model`; the live `online` unit set; the **shared** mutable
`params` (the very object the integrator holds — `eng.integrator.p === eng.params`,
which is what lets `inject!` change the system without disturbing the continuous
state); the real-time `dt`; the `integrator`; `f0`; the recorded trajectory
(`ts`, `fs`, `rocofs`, `pms`) and the running `nadir` frequency.
"""
mutable struct FrequencyResponseEngine{I} <: SimulationEngine
    model::SystemModel
    online::Set{Symbol}
    params::FRParams
    dt::Float64
    integrator::I
    f0::Float64
    ts::Vector{Float64}
    fs::Vector{Float64}
    rocofs::Vector{Float64}
    pms::Vector{Float64}
    nadir::Float64
end

"""
    FrequencyResponseEngine(model; t0=0.0, dt=0.02, solver=Tsit5())

Build a ready-to-step engine from `model`. All units start online; the parameter
block starts at zero disturbance (`ΔP_dist = 0`, so the system sits at the origin
until the first `inject!`). The integrator is `init`-ed (not `solve`-d) so the
orchestration loop can interleave events and redraws (docs/SPEC.md §6).
"""
function FrequencyResponseEngine(model::SystemModel; t0::Real = 0.0,
                                 dt::Real = _FR_DT0,
                                 solver = OrdinaryDiffEq.Tsit5())
    online = Set(u.id for u in model.units)
    a = aggregates(model, online)
    params = FRParams(a.H_sys, a.R_eq, a.D, a.Tg, 0.0, a.headroom)
    t0f = Float64(t0)
    # Large *finite* tspan: we drive the integrator with `step!(integ, dt, true)`,
    # so the end is never reached, and a finite bound keeps OrdinaryDiffEq's
    # adaptive initial-step heuristic well-behaved (with `Inf`, `dtmax=Inf` and the
    # zero derivative at the origin make the auto-guess unreliable). We also seed an
    # explicit initial `dt` for the same reason, and turn off the integrator's own
    # saved solution (`save_everystep`/`dense`) — we keep our own trajectory
    # vectors, and the integrator's would grow unbounded over a long live run.
    prob = OrdinaryDiffEq.ODEProblem(fr_rhs!, [0.0, 0.0], (t0f, t0f + 1.0e6), params)
    integrator = OrdinaryDiffEq.init(prob, solver;
                                     dt = Float64(dt),
                                     isoutofdomain = _fr_outofdomain,
                                     save_everystep = false, dense = false)
    f0 = model.f0
    # Seed the trajectory with the pre-disturbance point (Δω=0 ⇒ f=f0, RoCoF=0).
    return FrequencyResponseEngine(model, online, params, Float64(dt), integrator,
                                   f0, Float64[t0f], Float64[f0], Float64[0.0],
                                   Float64[0.0], f0)
end

"""
    init!(FrequencyResponseEngine, model; t0=0.0, dt=0.02, solver=Tsit5())

Interface entry point. Dispatching on the engine **type** (not an instance) and
returning a freshly built, fully-typed engine resolves the construction
chicken-and-egg: the struct is parametric on the concrete integrator type, which
is only known once the integrator exists, so there is no half-built engine to
mutate in place. See `interface.jl` for the contract.
"""
init!(::Type{FrequencyResponseEngine}, model::SystemModel; kwargs...) =
    FrequencyResponseEngine(model; kwargs...)

"""
    current_state(eng::FrequencyResponseEngine) -> (; t, f, Δω, RoCoF, ΔPm)

Named state at "now", in engineering units at the boundary: `f = f0·(1+Δω)` (Hz)
and `RoCoF = f0·dΔω/dt` (Hz/s). Pure read of the integrator — no stepping.

(If every unit is tripped, `H_sys = 0` and `RoCoF` is `±Inf`; that all-offline
edge is out of M1 scope.)
"""
function current_state(eng::FrequencyResponseEngine)
    Δω = eng.integrator.u[1]
    ΔPm = eng.integrator.u[2]
    p = eng.params
    # dΔω/dt — MUST stay identical to `du[1]` in `fr_rhs!` (kept explicit rather
    # than `get_du` so RoCoF is predictable and allocation-free).
    dΔω = (ΔPm - p.D * Δω + p.ΔP_dist) / (2 * p.H_sys)
    f = eng.f0 * (1 + Δω)
    RoCoF = eng.f0 * dΔω
    return (t = eng.integrator.t, f = f, Δω = Δω, RoCoF = RoCoF, ΔPm = ΔPm)
end

# Append the current state to the trajectory and update the running nadir.
function _record!(eng::FrequencyResponseEngine)
    s = current_state(eng)
    push!(eng.ts, s.t)
    push!(eng.fs, s.f)
    push!(eng.rocofs, s.RoCoF)
    push!(eng.pms, s.ΔPm)
    s.f < eng.nadir && (eng.nadir = s.f)
    return s
end

"""
    step!(eng::FrequencyResponseEngine, dt=eng.dt) -> (; t, f, Δω, RoCoF, ΔPm)

Advance the real-time engine by exactly `dt`, record the trajectory point, and
return the new state. Extends `CommonSolve.step!`, sharing one generic with the
integrator's own `step!(integrator, dt, true)` (docs/plans/m1-plan.md "Pitfalls").
"""
function step!(eng::FrequencyResponseEngine, dt::Real = eng.dt)
    step!(eng.integrator, Float64(dt), true)   # advance exactly dt
    return _record!(eng)
end

"""
    state_series(eng::FrequencyResponseEngine) -> (; t, f, RoCoF, ΔPm)

The full recorded trajectory accumulated by `step!` (for plotting/playback).
"""
state_series(eng::FrequencyResponseEngine) =
    (; t = eng.ts, f = eng.fs, RoCoF = eng.rocofs, ΔPm = eng.pms)

# Locate a unit by id in the canonical model (small linear scan; M1 systems are
# tiny). Throws if absent — a trip of a non-existent unit is a caller bug.
function _find_unit(model::SystemModel, id::Symbol)
    for u in model.units
        u.id === id && return u
    end
    throw(KeyError(id))
end

"""
    inject!(eng::FrequencyResponseEngine, ev::TripGenerator) -> eng

Take a unit offline live: drop it from `online`, recompute the COI aggregates into
the **shared** `params` (so the running integrator sees them immediately), and add
its lost generation as a persistent negative imbalance `ΔP_dist -= P0/S_base`. The
continuous state `(Δω, ΔPm)` is deliberately untouched — at the COI fidelity only
parameters change across a trip, so no algebraic re-init is needed (m1-plan.md).
A trip of an already-offline unit is a no-op.
"""
function inject!(eng::FrequencyResponseEngine, ev::TripGenerator)
    ev.id in eng.online || return eng        # already offline ⇒ nothing to do
    unit = _find_unit(eng.model, ev.id)
    delete!(eng.online, ev.id)
    a = aggregates(eng.model, eng.online)
    p = eng.params                            # === eng.integrator.p (shared object)
    p.H_sys = a.H_sys
    p.R_eq = a.R_eq
    p.D = a.D
    p.Tg = a.Tg
    p.headroom = a.headroom
    p.ΔP_dist -= unit.P0 / eng.model.S_base   # lost generation ⇒ frequency dips
    return eng
end

"""
    inject!(eng::FrequencyResponseEngine, ev::StepLoad) -> eng

Apply a persistent load step (pu on `S_base`) by bumping the running imbalance.
Aggregates are unchanged — only the disturbance moves. (Nice-to-have beyond the
core trip scenario; docs/SPEC.md §7.4.)
"""
function inject!(eng::FrequencyResponseEngine, ev::StepLoad)
    eng.params.ΔP_dist += ev.ΔP_pu
    return eng
end
