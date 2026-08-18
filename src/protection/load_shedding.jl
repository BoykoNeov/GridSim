# Low-frequency demand disconnection (LFDD) — the automatic defence-plan ladder
# that sheds blocks of load when frequency falls through fixed thresholds.
# See docs/plans/entsoe-iberia-reproduction.md §3.1.
#
# WHY A ROOT-FINDING CALLBACK, NOT AN `f < threshold` CHECK IN THE LOOP:
#
#   1. A `ContinuousCallback` root-finds the *exact* crossing instant. A per-step
#      comparison is only accurate to `dt` and cannot produce the annotated shed
#      times the ENTSO-E report charts (Fig 3-67) carry.
#   2. Physics belongs in the engine. The orchestration loop is engine-agnostic
#      by design (docs/SPEC.md §7.5) and must stay that way.
#
# THIS IS THE SANCTIONED CALLBACK PATH, NOT THE FORBIDDEN ONE. The project's
# carried-forward correctness rule bans *post-hoc clamping of a state variable*
# (which corrupts the integration). A load-shedding stage is a real, discrete,
# physical event that steps a *parameter* (`ΔP_dist`) at a root-found instant —
# the same class as `inject!`, not the same class as overwriting `u` behind the
# integrator's back.

"""
    LoadShedStage(threshold_hz, ΔP_pu; label = :shed)

One armed stage of a low-frequency load-shedding ladder: when frequency falls
**through** `threshold_hz` (downward crossings only), disconnect `ΔP_pu` of load
(pu on `S_base`, positive = load removed). Fires at most once — see `ShedLadder`.

`label` is carried through to the shed log purely for annotation (e.g. `:ES_49_5`).

Not a `PerturbationEvent`: those are *user-injected* disturbances, this is an
*armed protection scheme* that fires on the system's own state.
"""
struct LoadShedStage
    threshold_hz::Float64
    ΔP_pu::Float64
    label::Symbol
end
LoadShedStage(threshold_hz::Real, ΔP_pu::Real; label::Symbol = :shed) =
    LoadShedStage(Float64(threshold_hz), Float64(ΔP_pu), label)

"""
    ShedLadder(stages)

Live state of a load-shedding ladder: which stages are still `armed`, and the log
of what fired when. Mutable and **shared** — the callbacks close over this exact
object and the engine holds it as a field, the same sharing trick that lets
`inject!` reach the running integrator's `params` (see `FrequencyResponseEngine`).
That sharing exists to resolve a construction chicken-and-egg: the callbacks must
be built *before* the integrator, which is built before the engine.

Every field is a concretely-typed `Vector`, so nothing here is a type-stability
cliff (docs/SPEC.md §4).

  - `stages`  — the armed ladder, as given.
  - `armed`   — per-stage latch; `false` once fired, and never re-armed (a stage
                does not fire twice if frequency recovers and falls again).
  - `t_fired` / `i_fired` — the shed log, in firing order: root-found instant and
                the index into `stages`.
"""
struct ShedLadder
    stages::Vector{LoadShedStage}
    armed::Vector{Bool}
    t_fired::Vector{Float64}
    i_fired::Vector{Int}
end
ShedLadder(stages::Vector{LoadShedStage}) =
    ShedLadder(stages, fill(true, length(stages)), Float64[], Int[])
ShedLadder() = ShedLadder(LoadShedStage[])

"""
    shed_log(ladder::ShedLadder) -> (; t, label, threshold_hz, ΔP_pu)

The stages that actually fired, in firing order, with their root-found instants.
This is what annotates a frequency chart (report Fig 3-67) and what a test asserts
against — the recorded trajectory is only sampled every `dt`, the log is exact.
"""
function shed_log(ladder::ShedLadder)
    st = ladder.stages
    return (; t = copy(ladder.t_fired),
            label = [st[i].label for i in ladder.i_fired],
            threshold_hz = [st[i].threshold_hz for i in ladder.i_fired],
            ΔP_pu = [st[i].ΔP_pu for i in ladder.i_fired])
end

"""
    shed_total(ladder::ShedLadder) -> Float64

Total load shed so far (pu on `S_base`).
"""
shed_total(ladder::ShedLadder) = sum(ladder.stages[i].ΔP_pu for i in ladder.i_fired;
                                     init = 0.0)

# --- callback construction ------------------------------------------------
#
# One `ContinuousCallback` per stage inside a `CallbackSet`, rather than a single
# `VectorContinuousCallback`: with a ladder of ~12 stages the per-stage closure
# (each owning its own index) is far easier to reason about than the vector form's
# disarmed-sentinel bookkeeping, and the cost is irrelevant at this size.
#
# THE LATCH SIGN, which is the one subtle thing here: a disarmed stage's condition
# must keep the sign it had *immediately after firing* — negative, because the
# stage fires on a downward crossing of `f − threshold`. Returning `+1.0` when
# disarmed would manufacture a sign change at the disarm instant, which the
# rootfinder reads as a fresh crossing ⇒ a double shed. A negative constant also
# means a stage correctly refuses to re-arm when frequency recovers back above its
# threshold.

# Downward crossings only, so the shed goes in the `affect_neg!` slot and `affect!`
# (the upward crossing) is `nothing`. Asserted by test, not trusted from the
# positional signature.
function _shed_callback(ladder::ShedLadder, i::Int, f0::Float64)
    stage = ladder.stages[i]
    condition = function (u, t, integrator)
        ladder.armed[i] || return -1.0        # latched: hold the post-fire sign
        return f0 * (1 + u[1]) - stage.threshold_hz
    end
    affect_neg! = function (integrator)
        ladder.armed[i] || return nothing     # belt and braces
        ladder.armed[i] = false
        # Shedding load RAISES frequency. `ΔP_dist` is generation-minus-load, so
        # removing load is a POSITIVE step — the mirror of `StepLoad`'s
        # `ΔP_dist -= ΔP_pu`. (Pinned by an equivalence test against `StepLoad`.)
        integrator.p.ΔP_dist += stage.ΔP_pu
        push!(ladder.t_fired, integrator.t)
        push!(ladder.i_fired, i)
        # NOTE — no `derivative_discontinuity!` here, unlike `inject!`. The parameters
        # jump while `u` does not, which is exactly the stale-FSAL hazard `inject!`
        # has to arm against by hand; but `apply_callback!` sets
        # `integrator.derivative_discontinuity = true` BEFORE invoking the affect for a
        # `ContinuousCallback` (DiffEqBase `src/callbacks.jl`), so the cache is already
        # invalidated on this path. Verified, not assumed: with the call removed, a
        # 10x `dt` refinement of the shed scenario agrees to ~5e-14 relative.
        # That would be an easy thing to get silently wrong, because the error would be
        # INVISIBLE to any readout assertion — `current_state` recomputes RoCoF
        # algebraically from `_dΔω`, so it would report the right post-shed value while
        # the integration drifted. The guard is therefore a `dt`-refinement test
        # ("shed event is integrated, not just recorded"), which keeps holding this
        # path honest if the framework behaviour ever changes or the shed moves out of
        # a callback.
        return nothing
    end
    # `save_positions=(false,false)`: the engine runs with `save_everystep=false`
    # and keeps its own trajectory, so there is nothing to save into and no reason
    # to grow `integrator.sol` on every shed.
    return SciMLBase.ContinuousCallback(condition, nothing, affect_neg!;
                                        save_positions = (false, false))
end

"""
    shed_callbacks(ladder::ShedLadder, f0) -> CallbackSet

A `CallbackSet` of one downward-crossing `ContinuousCallback` per stage, closing
over `ladder` so firing latches the stage and appends to the shed log. An empty
ladder gives an empty `CallbackSet` (zero runtime cost, uniform code path).
"""
shed_callbacks(ladder::ShedLadder, f0::Real) =
    SciMLBase.CallbackSet(ntuple(i -> _shed_callback(ladder, i, Float64(f0)),
                                 length(ladder.stages))...)
