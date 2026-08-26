# Out-of-step (pole-slip) protection — the relay that disconnects a tie the moment
# the two areas it joins stop running together.
# See docs/plans/entsoe-iberia-reproduction.md §3 and docs/plans/m3-context.md D6.
#
# WHAT IT WATCHES. On this tier a machine's rotor angle IS its bus voltage angle
# (constant `E′` behind `Xd′`, see `model/network_model.jl`), so the angle across a
# branch is `δ_from − δ_to` and the power it carries is `K·sin(δ_from − δ_to)`. Two
# areas are "in step" while that difference is bounded. When the tie cannot carry
# what the disturbance asks of it, the difference grows without bound: the transfer
# peaks at `K` (90°), falls back through zero (180°) and REVERSES — the areas are
# now pulling against each other, and the tie is a liability rather than a link.
# Real protection opens it. This relay is the tier's version of that: a threshold on
# `|δ_from − δ_to|`, root-found, latching, firing the existing `TripLine` path.
#
# WHY A ROOT-FINDING CALLBACK: the same two reasons as `load_shedding.jl` — the
# separation instant is a headline number in the ENTSO-E report (12:33:21.54) and a
# per-step comparison would only ever be accurate to `dt`; and physics belongs in
# the engine, not in the engine-agnostic orchestration loop (docs/SPEC.md §7.5).
#
# WHY THE THRESHOLD LIVES HERE AND NOT ON `Branch` (M3 step 4, settling the open
# question in `m3-context.md`). `Branch` already carries a `rating` the dynamics do
# not read, so there is an obvious pull to hang a `slip_threshold` beside it. It is
# the wrong place, for the reason the shedding ladder is not a field of `Machine`:
# a threshold is a **setting of a defence plan**, not a property of a conductor.
# Keeping it off the topology is what lets ONE `NetworkModel` be run with the plan
# armed and disarmed — which is not a convenience, it is the counterfactual every
# test in this file is built on, and step 6's sweep varies the threshold across
# cells of one model. A relay is therefore passed at engine construction
# (`out_of_step = [(:B1, :B3) => OutOfStepTrip(2π/3)]`), exactly as a ladder is.
#
# WHAT THIS MODULE DOES NOT KNOW: the state layout, and how to open a branch. Both
# arrive as functions from the engine that owns them (`δdiff` / `trip!` below) —
# the same seam `load_shedding.jl` uses, and for the same reason.
#
# THE ONE MODEL INVARIANT IT LEANS ON: exactly one machine per bus, so a bus has a
# rotor angle at all. `NetworkModel` enforces it today. A later tier with load buses
# (M2b's network reduction) would leave a branch end with no `δ` to read, and this
# relay would need a real voltage angle rather than a rotor angle — worth knowing
# before it is discovered.

"""
    OutOfStepTrip(threshold_rad; label = :out_of_step)

The **setting** of one out-of-step relay: trip the branch when the angle across it
exceeds `threshold_rad` in magnitude. Inert — it holds no live state, so the same
setting may be handed to any number of engines (`OutOfStepRelay` is the live half).

`threshold_rad` is a *scenario parameter, not a constant of the tier* (D6). The
report's separation is a pole slip, which the probe detected as the 90° crossing
followed by protection at ≈120–180°; step 6's sweep varies it. Both ends of that
range are legal here and neither is a default worth pretending is settled.

`label` is carried through to the log purely for annotation (e.g. `:tie_ES_FR`).

Not a `PerturbationEvent`: those are *user-injected* disturbances, this is an
*armed protection scheme* that fires on the system's own state — the same
distinction `LoadShedStage` draws.
"""
struct OutOfStepTrip
    threshold_rad::Float64
    label::Symbol

    function OutOfStepTrip(threshold_rad::Real; label::Symbol = :out_of_step)
        # A denominator-free guard, but a real one: a non-positive threshold is
        # crossed by `|δ_from − δ_to| ≥ 0` at every instant including the flat
        # start, so the relay would trip the tie before the run began. It also
        # rules out the one place `abs` is not differentiable being the root
        # itself — away from zero the kink is a *maximum* of the condition and so
        # carries no sign change, which is what lets the export swing pass through
        # it safely.
        threshold_rad > 0 || throw(ArgumentError(
            "OutOfStepTrip: threshold_rad ($threshold_rad) must be > 0 rad — a " *
            "non-positive threshold is already crossed at the flat start."))
        return new(Float64(threshold_rad), label)
    end
end

"""
    OutOfStepRelay

Live state of one out-of-step relay, **bound to one named branch** by its bus pair.
Mutable and **shared**: the callback closes over this exact object and the engine
holds it as a field — the same construction trick `ShedLadder` uses, and for the
same chicken-and-egg reason (the callbacks are built before the integrator, which
is built before the engine).

Because the latch and the log are live state, an engine **builds its own relays**
from `OutOfStepTrip` settings rather than accepting a pre-built one: handing the
same relay to two engines would silently share one latch and one log.

  - `from` / `to` — the branch's own bus names, in the model's order (not the
        caller's, so two runs that protect the same tie agree on what the log says).
  - `threshold_rad` / `label` — as given.
  - `armed` — the latch. `false` once fired, and never re-armed: a tie that has
        been opened does not re-close because the angle came back.
  - `t_tripped` / `δ_tripped` — the log: the **root-found** instant and the signed
        angle across the branch at it. `NaN` while the relay has not fired, which
        is what distinguishes *fired* from *disarmed without firing*.
"""
mutable struct OutOfStepRelay
    from::Symbol
    to::Symbol
    threshold_rad::Float64
    label::Symbol
    armed::Bool
    t_tripped::Float64
    δ_tripped::Float64
end
OutOfStepRelay(from::Symbol, to::Symbol, s::OutOfStepTrip) =
    OutOfStepRelay(from, to, s.threshold_rad, s.label, true, NaN, NaN)

"""
    out_of_step_log(r::OutOfStepRelay) -> (; tripped, t, δ, threshold_rad, label, armed)

What this relay did, for an annotated figure (step 7) and for a test to assert on.

  - `tripped` — whether it fired. A relay can end a run `armed == false` **without**
    having fired (its branch was opened by something else, or a generator trip took
    away the rotor whose angle it was reading), and the two must not read alike.
  - `t` / `δ` — the root-found instant and the signed angle across the branch at it;
    `|δ|` should equal `threshold_rad` to solver tolerance, which is the direct check
    that the root was found on the intended quantity.

Per relay, deliberately, and not pooled across a network: "when did the system
separate?" has one answer per tie, and pooling them is the conflation `shed_log`
rejects for the frequency.
"""
out_of_step_log(r::OutOfStepRelay) =
    (; tripped = !isnan(r.t_tripped), t = r.t_tripped, δ = r.δ_tripped,
       threshold_rad = r.threshold_rad, label = r.label, armed = r.armed)

"""
    disarm!(r::OutOfStepRelay) -> r

Latch the relay without firing it, leaving the log untouched. Two things do this,
both of them "the signal this relay reads has stopped meaning what it measures":

  - the branch being **opened by anything else** (a user `TripLine`, another
    relay) — there is nothing left to protect, and an un-disarmed relay would go on
    root-finding and then claim a protection operation that opened nothing;
  - a **generator trip at either end** — see `inject!(::SwingEngine, ::TripGenerator)`.
"""
function disarm!(r::OutOfStepRelay)
    r.armed = false
    return r
end

# --- callback construction ------------------------------------------------
#
# Condition `g = threshold − |δ_from − δ_to|`: positive while the two ends are in
# step, negative once they are not. So the trip is a DOWNWARD crossing and goes in
# the `affect_neg!` slot, with `affect!` (the upward crossing) `nothing` — the same
# shape as a shed stage, and asserted by test rather than trusted from the
# positional signature.
#
# THE DISARMED CONSTANT, WHICH IS *NOT* THE LADDER'S. A shed stage holds `-1.0`
# because that is the sign it had immediately after firing. A relay has two ways to
# end up latched and they had opposite signs:
#
#   - fired      ⇒ `g < 0` (the angle is past the threshold and still growing), so
#                  `-1.0`, and returning `+1.0` here would manufacture a fresh
#                  downward crossing at the latch instant ⇒ a double trip;
#   - disarmed   ⇒ `g > 0` (it never reached the threshold), so `+1.0`, and
#     unfired      returning `-1.0` here would manufacture a downward crossing at
#                  the disarm instant. The affect's own `armed` check would swallow
#                  it, so nothing would go visibly wrong — but the rootfinder would
#                  still interpolate back and split the step, which perturbs the
#                  step sequence of every run that disarms a relay. That is exactly
#                  the class of silent difference this milestone's bit-identity
#                  checks exist to catch, so the sign is chosen rather than copied.
#
# `t_tripped` is the discriminator, and the affect writes it BEFORE it opens the
# branch, so the two are never momentarily inconsistent.
function _out_of_step_callback(r::OutOfStepRelay, δdiff, trip!)
    condition = function (u, t, integrator)
        r.armed || return isnan(r.t_tripped) ? 1.0 : -1.0
        return r.threshold_rad - abs(δdiff(u))
    end
    affect_neg! = function (integrator)
        r.armed || return nothing              # belt and braces
        r.t_tripped = integrator.t             # the root-found instant, not `dt`-quantised
        r.δ_tripped = δdiff(integrator.u)
        # Opening the branch is what DISARMS this relay: `trip!` runs the engine's
        # own `inject!(::TripLine)`, which latches every relay on the branch it
        # actually opened. One rule ("a relay on an open branch is latched") covers
        # the user trip, another relay's trip and this one, instead of three.
        trip!(integrator)
        return nothing
    end
    # `save_positions=(false,false)` for `load_shedding.jl`'s reason: the engine runs
    # with `save_everystep=false` and keeps its own trajectory, so there is nothing
    # to save into.
    return SciMLBase.ContinuousCallback(condition, nothing, affect_neg!;
                                        save_positions = (false, false))
end

"""
    out_of_step_callbacks(bound::AbstractVector) -> CallbackSet

A `CallbackSet` of one downward-crossing `ContinuousCallback` per relay, from a
vector of `(relay, δdiff, trip!)` triples — one per protected branch. No relays
gives an empty `CallbackSet` (zero runtime cost, uniform code path).

Relay order is the caller's, so the callback set is deterministic; a `Dict` keyed
by bus pair would not be. Same rule as `shed_callbacks`, same reason.
"""
function out_of_step_callbacks(bound::AbstractVector)
    # `Any[]` is construction-time only — each relay's closures have their own
    # type, and the `CallbackSet` this splats into is a concretely-typed tuple.
    cbs = Any[]
    for (r, δdiff, trip!) in bound
        push!(cbs, _out_of_step_callback(r, δdiff, trip!))
    end
    return SciMLBase.CallbackSet(cbs...)
end
