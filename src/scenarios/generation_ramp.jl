# Generation lost (or gained) as a RAMP rather than an instant — M3 step 5, D7.
#
# The ENTSO-E Iberian cascade did not arrive as one step: it arrived over ≈2.46 s
# as cluster after cluster disconnected. M2 could only express an instant
# (`TripGenerator` zeroes a machine's `Pm` in one breath), so reproducing the event
# meant either misrepresenting its shape or approximating it.
#
# WHY NOT A STAIRCASE OF TRIPS (the alternative, rejected — D7). The obvious
# approximation is N discrete trips spread over the window. It is rejected because
# M3 adds **root-finding protection**: the shed ladder (step 3) and the out-of-step
# relay (step 4) both locate an exact instant by root-finding a continuous signal.
# A staircase puts a jump discontinuity into that very signal every 1/N of the
# window, so the instants those relays report would be artefacts of the slice count
# — a number that moves when you change N and looks like a result. That is exactly
# the class of error step 6's sweep exists to rule out, so it must not be built into
# the input the sweep varies.
#
# THE COST, STATED. The vertex RHS now carries a scenario input: three parameters
# per machine that describe a disturbance rather than a machine. Accepted, because
# the alternative puts a numerical artefact in the headline result.
#
# WHY THIS IS ARMED AT CONSTRUCTION AND IS NOT A `PerturbationEvent`. A
# `PerturbationEvent` is something a *user* does to a running engine at the moment
# they do it; the engine timestamps it from its own clock. A ramp is a **scheduled**
# disturbance with a start time chosen in advance — it is scenario data, the same
# kind of thing as a shed ladder's thresholds, and it is armed the same way
# (`SwingEngine(net; ramp = [...])`). That also makes it reproducible: two runs of
# the same script ramp at the same instant without anything having to be injected
# on cue.
#
# UNITS: pu/s ON THE SYSTEM BASE, not MW/s. `Machine.P0` is in MW because it is
# *model* data, and `machine_arrays` is the single place model data converts to the
# system base (see the note at the head of `model/network_model.jl`). A ramp is not
# model data — it is an engine-armed setting, like `LoadShedStage`'s `ΔP_pu`, which
# is in pu for the same reason. Taking MW/s here would open a second conversion
# site beside the one the invariant names.

"""
    GenerationRamp(rate, t_start, duration)

A scheduled linear change in one machine's mechanical power, armed at construction
(`SwingEngine(net; ramp = [:G1 => GenerationRamp(...)])`) rather than injected.

The machine's effective mechanical power becomes

    Pm_eff(t) = Pm + rate · clamp(t − t_start, 0, duration)

so it holds `Pm` until `t_start`, moves linearly for `duration` seconds, and then
holds the new value `Pm + rate·duration` forever. Continuous everywhere — the ramp's
two ends are corners in the slope, never jumps (see the file header for why that
distinction is the whole point).

  - `rate`     — pu/s **on the system base** `S_base`. **Negative is generation
                 lost**, which is the case this exists for; positive is generation
                 arriving. Zero is legal and is exactly the un-ramped machine.
  - `t_start`  — s, simulation time the ramp begins. Must be at or after the
                 engine's `t0` (the engine enforces it, since only the engine knows
                 `t0`): a ramp already under way when the run starts would be baked
                 into the steady state the engine is placed on, and the resulting
                 swing would look like physics rather than like a mis-signed input.
  - `duration` — s, how long it takes. Strictly positive and finite: a
                 zero-duration ramp is the instantaneous step this type exists to
                 avoid, and an infinite one has no total magnitude for step 6's
                 sweep to vary.

The total delivered change is `rate · duration` (pu, signed). Path does not matter
to where the system settles — only that total does — which is what makes the
closed-form settling check in `test/` a validation of the ramp's *magnitude* and
not just of its shape.

**Headroom does not move with the ramp, deliberately.** A machine's governor still
saturates at `headroom = Pmax − P0`, so its total mechanical ceiling while ramping
is `Pmax + rate·(elapsed)` — the ceiling travels *down* with the generation that is
leaving. That is the right physics for a fleet losing units, and it is what `Pmax`
already means on an aggregated area machine: a net-injection ceiling, not a
nameplate (decision D4).

Not a `PerturbationEvent` — see the file header.
"""
struct GenerationRamp
    rate::Float64        # pu/s on S_base; negative = generation lost
    t_start::Float64     # s
    duration::Float64    # s

    # Guarded per rule with its own message, the M2/M3 discipline: a bad ramp
    # usually breaks more than one rule at once, and "it threw" would not say which.
    # `t_start ≥ t0` is NOT here — it is the engine's, because only the engine knows
    # `t0`, and a ramp is a legal object independent of which run it is armed on.
    function GenerationRamp(rate::Real, t_start::Real, duration::Real)
        isfinite(rate) || throw(ArgumentError(
            "GenerationRamp: rate ($rate) must be finite (pu/s on S_base). " *
            "Negative is generation lost."))
        isfinite(t_start) || throw(ArgumentError(
            "GenerationRamp: t_start ($t_start) must be finite (s) — a ramp that " *
            "never starts is not a ramp, it is an un-ramped machine."))
        duration > 0 || throw(ArgumentError(
            "GenerationRamp: duration ($duration) must be > 0 s. A zero-duration " *
            "ramp is the instantaneous step this type exists to avoid — it puts a " *
            "jump into the signal the protection relays root-find on."))
        isfinite(duration) || throw(ArgumentError(
            "GenerationRamp: duration ($duration) must be finite (s) — an unbounded " *
            "ramp has no total magnitude `rate·duration` for a sweep to vary."))
        return new(Float64(rate), Float64(t_start), Float64(duration))
    end
end
