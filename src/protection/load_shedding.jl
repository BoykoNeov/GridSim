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
# physical event that steps a *parameter* at a root-found instant — the same class
# as `inject!`, not the same class as overwriting `u` behind the integrator's back.
#
# WHICH FREQUENCY, AND WHOSE POWER (M3 step 3, decision D5). Until M3 this file
# hard-coded M1's state layout: the condition read `u[1]` (the one aggregate speed
# deviation) and the affect stepped the one global `ΔP_dist`. On a multi-machine
# network that is **wrong in a way that still runs**. `f_coi` across a pair of areas
# that is separating is an inertia-weighted average of two frequencies that are
# diverging — `engines/swing.jl`'s own header calls that read-out meaningless — so a
# ladder driven by it produces a plausible trace and sheds at the wrong instants,
# with Iberia's ladder firing partly on Continental Europe's inertia.
#
# So a ladder **binds to one named machine**: its condition reads that machine's own
# speed and its affect steps that machine's own power. This module knows neither
# state layout. The two bindings are passed in as functions by the engine that owns
# the layout (`speed`/`apply!` below), which is what lets the same ladder code serve
# M1's aggregate — where the named machine is the whole system — and M2/M3's network.
#
# WHY SHEDS ARE NOT `EngineEvent`s. The event log (`engines/swing.jl`) records what
# a *user* injected, because a played-back trajectory cannot reconstruct it. A shed
# is already recorded, more precisely, in the ladder's own log: `t_fired` is the
# root-found instant, not the `dt`-quantised one an event stamp would carry, and it
# arrives with the stage's threshold and block size. Folding the two would either
# lose that precision or give the event log a second meaning. Step 7's annotated
# panel reads `shed_log`; the two logs are plotted together, not merged.

"""
    LoadShedStage(threshold_hz, ΔP_pu; label = :shed)

One armed stage of a low-frequency load-shedding ladder: when frequency falls
**through** `threshold_hz` (downward crossings only), disconnect `ΔP_pu` of load
(pu on `S_base`, positive = load removed). Fires at most once — see `ShedLadder`.

The frequency in question is that of the machine its ladder is bound to, never a
system-wide average (`ShedLadder`, decision D5).

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
    AGGREGATE_MACHINE

The `machine` a ladder carries on M1's aggregate `FrequencyResponseEngine`: a
**sentinel**, not a bus name. That engine has exactly one speed and one power
imbalance for the whole system, so "the named machine" *is* the system and there is
no per-machine frequency for a name to select. `SwingEngine` rejects it by name,
because there every ladder must select a real machine.
"""
const AGGREGATE_MACHINE = :system

"""
    ShedLadder(machine, stages)
    ShedLadder(stages)            # bound to `AGGREGATE_MACHINE`

Live state of a load-shedding ladder **bound to one named machine**: which stages
are still `armed`, and the log of what fired when. Mutable and **shared** — the
callbacks close over this exact object and the engine holds it as a field, the same
sharing trick that lets `inject!` reach the running integrator's parameters. That
sharing exists to resolve a construction chicken-and-egg: the callbacks must be
built *before* the integrator, which is built before the engine.

Because the latch and the log are live state, an engine **builds its own ladders**
from stages rather than accepting a pre-built one: handing the same object to two
engines would silently share one latch and one log between two runs.

Every field is a concretely-typed `Vector`, so nothing here is a type-stability
cliff (docs/SPEC.md §4).

  - `machine` — the bound machine id; `AGGREGATE_MACHINE` on M1's aggregate engine.
  - `stages`  — the armed ladder, as given.
  - `armed`   — per-stage latch; `false` once fired, and never re-armed (a stage
                does not fire twice if frequency recovers and falls again).
  - `t_fired` / `i_fired` — the shed log, in firing order: root-found instant and
                the index into `stages`.
"""
struct ShedLadder
    machine::Symbol
    stages::Vector{LoadShedStage}
    armed::Vector{Bool}
    t_fired::Vector{Float64}
    i_fired::Vector{Int}
end
ShedLadder(machine::Symbol, stages::Vector{LoadShedStage}) =
    ShedLadder(machine, stages, fill(true, length(stages)), Float64[], Int[])
ShedLadder(stages::Vector{LoadShedStage}) = ShedLadder(AGGREGATE_MACHINE, stages)
ShedLadder() = ShedLadder(LoadShedStage[])

"""
    shed_log(ladder::ShedLadder) -> (; t, label, threshold_hz, ΔP_pu)

The stages that actually fired, in firing order, with their root-found instants.
This is what annotates a frequency chart (report Fig 3-67) and what a test asserts
against — the recorded trajectory is only sampled every `dt`, the log is exact.

Per ladder, deliberately: on a multi-area model "when did it shed?" has one answer
per area, and pooling them is the same conflation D5 rejects for the frequency.
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

"""
    disarm!(ladder::ShedLadder) -> ladder

Latch every stage without firing any of them, leaving the log untouched. This is
what a *generator* trip does to the ladder bound to that machine — see
`inject!(::SwingEngine, ::TripGenerator)` for why the alternative is worse.
"""
function disarm!(ladder::ShedLadder)
    fill!(ladder.armed, false)
    return ladder
end

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
# threshold. It is equally what makes `disarm!` safe to call mid-run from a trip.

# Downward crossings only, so the shed goes in the `affect_neg!` slot and `affect!`
# (the upward crossing) is `nothing`. Asserted by test, not trusted from the
# positional signature.
#
# `speed(u)` returns the bound machine's per-unit speed deviation out of the state
# vector, and `apply!(integrator, ΔP_pu)` steps the bound machine's power parameter.
# Both come from the engine, because both are statements about a state layout this
# module deliberately does not know (D5).
function _shed_callback(ladder::ShedLadder, i::Int, f0::Float64, speed, apply!)
    stage = ladder.stages[i]
    condition = function (u, t, integrator)
        ladder.armed[i] || return -1.0        # latched: hold the post-fire sign
        return f0 * (1 + speed(u)) - stage.threshold_hz
    end
    affect_neg! = function (integrator)
        ladder.armed[i] || return nothing     # belt and braces
        ladder.armed[i] = false
        # Shedding load RAISES frequency, so the step is POSITIVE in both bindings:
        # M1 steps `ΔP_dist` (generation-minus-load) — the mirror of `StepLoad`'s
        # `ΔP_dist -= ΔP_pu`, pinned by an equivalence test against it — and the
        # network engine steps that machine's `Pm`, which on this tier is a NET
        # injection, so removing load raises it by exactly the same amount.
        apply!(integrator, stage.ΔP_pu)
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
        # a callback. It is written once per ENGINE, not once per project: M1's test
        # pins the framework's behaviour, and the network engine's own refinement test
        # pins that this path reaches it too — there `p` is a flat `Vector` and the
        # affect writes an index, not a field of a mutable struct.
        return nothing
    end
    # `save_positions=(false,false)`: the engine runs with `save_everystep=false`
    # and keeps its own trajectory, so there is nothing to save into and no reason
    # to grow `integrator.sol` on every shed.
    return SciMLBase.ContinuousCallback(condition, nothing, affect_neg!;
                                        save_positions = (false, false))
end

"""
    shed_callbacks(ladder::ShedLadder, f0, speed, apply!) -> CallbackSet
    shed_callbacks(bound::AbstractVector, f0) -> CallbackSet

A `CallbackSet` of one downward-crossing `ContinuousCallback` per stage, closing
over each ladder so firing latches the stage and appends to that ladder's log. An
empty ladder gives an empty `CallbackSet` (zero runtime cost, uniform code path).

The second form takes a vector of `(ladder, speed, apply!)` triples — one per bound
machine — and is what a multi-machine engine passes. Ladder order, and stage order
within a ladder, is the caller's, so the callback set is deterministic; a `Dict`
keyed by machine id would not be.
"""
function shed_callbacks(bound::AbstractVector, f0::Real)
    f0f = Float64(f0)
    # `Any[]` is construction-time only: each stage's closures have their own type,
    # so nothing concrete could hold them, and the `CallbackSet` this splats into is
    # a tuple that is concretely typed by construction.
    cbs = Any[]
    for (ladder, speed, apply!) in bound
        for i in eachindex(ladder.stages)
            push!(cbs, _shed_callback(ladder, i, f0f, speed, apply!))
        end
    end
    return SciMLBase.CallbackSet(cbs...)
end

shed_callbacks(ladder::ShedLadder, f0::Real, speed, apply!) =
    shed_callbacks([(ladder, speed, apply!)], f0)
