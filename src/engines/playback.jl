# Run-then-playback: the second execution mode (docs/SPEC.md §2, §3.3), and the
# half of the `SimulationEngine` contract that until M4 had no implementation
# anywhere. `interface.jl` has documented `solve!`/`state_series` since the
# scaffold; `grep solve!` across `src/` found the docstring, the CommonSolve
# import, and nothing else.
#
# WHAT MAKES THIS A SECOND MODE AND NOT MERELY A FASTER LOOP. `run_realtime!`
# drives the integrator with `step!(integ, dt, true)`, which forces it to *land*
# on every `dt` boundary: the adaptive step-size controller is truncated once per
# output sample, whether the dynamics call for it or not. Playback lets the solver
# choose its own steps (`step!(integ)`, no target) and builds the output grid by
# evaluating each completed step's own interpolant. Same equations, same events,
# same callbacks, genuinely different numerical path — which is what gives
# "real-time and playback agree to solver tolerance" any content at all. Force the
# playback path onto the same step boundaries and the agreement check becomes a
# tautology that would pass against almost any bug.
#
# WHY SCHEDULED EVENTS GO THROUGH `inject!` RATHER THAN A `PresetTimeCallback`
# (decision D8, docs/plans/m4-context.md). `m4-plan.md` step 1 says "compiled to a
# `PresetTimeCallback`". That is not reachable here without changing the engines'
# types: both engines are parametric on their concrete integrator, the callback
# set is fixed at `init` time, and an already-built integrator does not take a new
# callback. Doing it anyway would mean either a second integrator type per engine
# or a schedule field threaded through both constructors.
#
# The tstop route is not a workaround for that, though — it is the better
# mechanism for what D4 actually asks. A `PresetTimeCallback` needs its own
# affect, i.e. a SECOND way for a scheduled trip to reach the engine, beside the
# `inject!` the real-time loop uses. Two paths that must stay identical is exactly
# the shape D4 exists to forbid. Landing the integrator exactly on the event
# instant with `add_tstop!` and then calling the very same `inject!` gives one
# path, and it is the path `run_realtime!` already exercises. (`inject!` also
# already does its own `derivative_discontinuity!` / `auto_dt_reset!` at the
# boundary, which is the work a callback's `u_modified!` would have signalled.)
#
# WHAT STAYS A CALLBACK, AND WHY THE DISTINCTION IS LOAD-BEARING. `perturbations`
# carries SCHEDULED events only. Every state-triggered protection scheme — M3's
# load-shedding ladders and out-of-step relays — stays exactly where the engine
# constructor puts it, as a root-finding solver callback, in both modes. Nothing
# here pre-bakes protection into a schedule, and nothing may: a relay fires on the
# system's own state at an instant nobody can know in advance, so a playback run
# whose protection had been flattened into preset times would be a DIFFERENT
# SYSTEM from the real-time run of the same scenario, and every comparison in M4
# would be measuring that difference instead of the thing it claims to measure.

# The output-grid recording hook. Each playback-capable engine adds one method:
# record one sample from an EXPLICIT `(t, u)` rather than from wherever the
# integrator happens to be, because the samples this file records are interpolated
# points *inside* a completed step, not the step's endpoint. Each engine's own
# `_record!` is then the `(integrator.t, integrator.u)` case of it, so there is one
# recording path with two entry points and no second copy of the channel layout.
function _record_at! end

# Largest number of solver steps one `solve!` may take before it gives up. Not a
# tuning knob: it is the "every long-running loop self-terminates on a fixed step
# count, never on a condition" rule (M3, standing) applied at the source, so that
# a `dt` collapse surfaces as a named error instead of a hung session.
const _PLAYBACK_MAXITERS = 1_000_000

# The solver tolerances every engine is built with, and the `calck` flag that
# decides whether a step's interpolation coefficients exist at all. Both live here
# rather than in one engine because both engines need them identically, and both
# only became load-bearing when playback arrived.
#
# WHY THE TOLERANCES ARE NAMED AT ALL. They are OrdinaryDiffEq's own `Float64`
# defaults, so pinning them changes nothing numerically. What changes is that they
# become a KEYWORD ARGUMENT: until M4 neither constructor forwarded anything to
# `init`, so "run it again at a tighter tolerance" — the standing M3 rule that a
# number below the solver's own tolerance is not a result until it survives the
# tolerance changing — was not expressible against these engines at all. A rule
# that cannot be executed is not a rule.
const _ENGINE_RELTOL = 1.0e-3
const _ENGINE_ABSTOL = 1.0e-6

# WHY `calck = true`, EXPLICITLY. OrdinaryDiffEq decides for itself whether to
# keep each step's interpolation coefficients, and with `dense = false`,
# `save_everystep = false` and no `saveat` it decides NO — unless a root-finding
# callback happens to be present, which flips it back on. Measured on this repo:
# `SwingEngine(net)` came out with `calck = false` and the same engine with one
# out-of-step relay armed came out with `calck = true`.
#
# That is the trap. Playback reads samples from *inside* a completed step, so
# without the coefficients it silently falls back to a lower-order reconstruction
# — and the accuracy of a recorded trajectory would then depend on whether the
# scenario happened to arm a relay. Behaviour that changes with an unrelated
# configuration switch, quietly and only in the third decimal, is exactly what
# nobody would think to test. Setting it true makes every engine interpolate the
# same way.
#
# It is `calck`, NOT `dense = true`: `dense` stores the interpolation data for the
# whole history, which is the unbounded growth both constructors' comments already
# refuse. `calck` keeps only the current step's.
const _ENGINE_CALCK = true

# The horizon, validated. `tspan[1]` must be where the engine actually is: an
# engine carries its integrator's position, so solving "from 0" an engine that has
# already been stepped to 3 s would silently produce a trajectory whose time base
# is a lie.
function _playback_span(eng::SimulationEngine, tspan)
    length(tspan) == 2 || throw(ArgumentError(
        "solve!: tspan must be (t_start, t_end), got $(tspan)"))
    t0, t1 = Float64(first(tspan)), Float64(last(tspan))
    t_now = current_state(eng).t
    t0 == t_now || throw(ArgumentError(
        "solve!: tspan starts at $t0 but the engine is at t = $t_now. " *
        "Playback continues from where the engine is; pass ($t_now, t_end)."))
    t1 > t0 || throw(ArgumentError(
        "solve!: tspan must run forwards, got ($t0, $t1)"))
    return t0, t1
end

# `time => event` pairs, validated and put in time order.
#
# MergeSort, explicitly: two events at the same instant must apply in the order
# the caller wrote them (a generator trip and a load step at one instant do not
# commute through `inject!`), and Julia's default algorithm for a numeric key is
# not stable. This is a handful of events on a cold path; the guarantee is free.
function _playback_schedule(perturbations, t0::Float64, t1::Float64)
    sched = Tuple{Float64,PerturbationEvent}[]
    for p in perturbations
        p isa Pair || throw(ArgumentError(
            "solve!: perturbations must be `time => event` pairs, got $(typeof(p))"))
        ev = last(p)
        ev isa PerturbationEvent || throw(ArgumentError(
            "solve!: perturbations must be `time => event` pairs, but the value " *
            "for time $(first(p)) is a $(typeof(ev)), not a PerturbationEvent"))
        t = Float64(first(p))
        isfinite(t) || throw(ArgumentError("solve!: event time must be finite, got $t"))
        t0 <= t <= t1 || throw(ArgumentError(
            "solve!: event scheduled at t = $t lies outside the horizon [$t0, $t1]"))
        push!(sched, (t, ev))
    end
    sort!(sched; by = first, alg = Base.Sort.MergeSort)
    return sched
end

# The output grid, in `(t0, t1]`.
#
# `t0` is deliberately NOT on it: every engine constructor already seeds its
# recorder with the pre-disturbance sample at `t0`, so putting it on the grid
# would record that instant twice. An explicit grid containing `t0` is accepted
# and that one entry dropped, for the same reason.
function _playback_grid(t0::Float64, t1::Float64, saveat::Real)
    dt = Float64(saveat)
    (isfinite(dt) && dt > 0) || throw(ArgumentError(
        "solve!: saveat must be a positive finite step (or an explicit grid), got $saveat"))
    # `+ 1e-9` is in units of steps, so a horizon that is an exact multiple of
    # `dt` does not lose its last sample to floating-point shortfall.
    n = floor(Int, (t1 - t0) / dt + 1e-9)
    grid = Vector{Float64}(undef, n)
    @inbounds for k in 1:n
        # `min` because `t0 + n*dt` can land a few ulps past `t1`, and a grid point
        # the loop can never reach is a silently missing sample.
        grid[k] = min(t0 + k * dt, t1)
    end
    return grid
end

function _playback_grid(t0::Float64, t1::Float64, saveat::AbstractVector{<:Real})
    grid = Float64[]
    sizehint!(grid, length(saveat))
    prev = t0
    for (k, g) in enumerate(saveat)
        gf = Float64(g)
        t0 <= gf <= t1 || throw(ArgumentError(
            "solve!: saveat[$k] = $gf lies outside the horizon [$t0, $t1]"))
        k == 1 || gf > prev || throw(ArgumentError(
            "solve!: saveat must be strictly increasing, but saveat[$k] = $gf " *
            "does not exceed saveat[$(k - 1)] = $prev"))
        prev = gf
        gf == t0 && continue        # already recorded at construction (see above)
        push!(grid, gf)
    end
    return grid
end

# Apply every scheduled event due at or before `t`, starting at cursor `si`, and
# return the new cursor. `<=` rather than `==` is a safety net: the tstops added
# below make the integrator land exactly on each event instant, and if one were
# ever missed the event would be applied late rather than dropped silently.
function _playback_apply!(eng::SimulationEngine,
                          sched::Vector{Tuple{Float64,PerturbationEvent}},
                          si::Int, t::Float64)
    @inbounds while si <= length(sched) && sched[si][1] <= t
        inject!(eng, sched[si][2])
        si += 1
    end
    return si
end

"""
    _playback!(eng, tspan, perturbations, saveat; maxiters) -> state_series(eng)

The shared playback driver. Both engines' `solve!` methods are one line each on
top of this, so the loop below — and in particular the record-then-apply ordering
the comment inside it exists to protect — has exactly one implementation.
"""
function _playback!(eng::E, tspan, perturbations, saveat;
                    maxiters::Integer = _PLAYBACK_MAXITERS) where {E<:SimulationEngine}
    t0, t1 = _playback_span(eng, tspan)
    sched = _playback_schedule(perturbations, t0, t1)
    grid = _playback_grid(t0, t1, saveat)
    integ = eng.integrator

    # Land exactly on every event instant, and on the horizon end. Without these
    # the solver would step straight over an event time and `_playback_apply!`
    # would fire it late — which is precisely the anti-vacuity mutation this
    # step's test performs deliberately.
    for (t_ev, _) in sched
        t_ev > t0 && OrdinaryDiffEq.add_tstop!(integ, t_ev)
    end
    OrdinaryDiffEq.add_tstop!(integ, t1)

    # THE OUTPUT GRID GOES TO THE INTEGRATOR, NOT TO A LOOP HERE, AND THIS COST A
    # ROUND TO LEARN. The obvious implementation is to step freely and then read
    # each grid point off the finished step's interpolant with `integ(t)`. It is
    # wrong, subtly and only sometimes:
    #
    # When a `ContinuousCallback` fires — a shed stage, an out-of-step relay — the
    # framework shortens the step to the root, runs the affect (which steps a
    # PARAMETER), and marks the state modified, which makes it recompute the
    # end-of-step derivative against the NEW parameters. That retroactively bends
    # the interpolant across the interval that has just closed. Measured on a
    # two-stage ladder: every sample inside the step a shed ended was wrong by up
    # to 3.4e-2 Hz, six times the agreement band, while the samples on either side
    # of that one step were right to 1e-9 — and the error did not shrink cleanly
    # with the tolerance, because its size is set by the step length, which moves
    # around unpredictably as the tolerance changes.
    #
    # `savevalues!` inside the framework's own `apply_callback!` runs AFTER the
    # step is shortened to the root and BEFORE the affect — the one instant at
    # which the interpolant is both complete and still valid, and an instant no
    # caller can reach from outside `step!`. So the grid is handed over with
    # `add_saveat!` and the samples are drained back out of `integ.sol` below.
    # Note that this needs `calck` (above), which is the second reason it is set.
    #
    # This does NOT put the solver back on forced steps: `saveat` interpolates
    # inside freely chosen steps, unlike a tstop, so the playback path stays a
    # genuinely different numerical path from `run_realtime!`'s truncated one.
    for g in grid
        SciMLBase.add_saveat!(integ, g)
    end
    # Everything already in `sol` (the initial point `init` saved) is somebody
    # else's; only what arrives from here on is ours to record.
    nsaved = length(integ.sol.t)

    # Anything scheduled for the very first instant applies before the first step,
    # matching `run_realtime!`, which drains its queue at the top of its loop.
    si = _playback_apply!(eng, sched, 1, t0)
    iters = 0

    while integ.t < t1
        iters += 1
        iters <= maxiters || error(
            nameof(E), " playback exceeded ", maxiters, " solver steps at t = ",
            integ.t, " (horizon end ", t1, "). The step size has collapsed; that ",
            "is a bug, not a horizon that needs more iterations.")
        step!(integ)
        # Fail loud, not silent — the same guard both engines' `step!` carries. A
        # failed integration would otherwise leave this loop spinning on a frozen
        # `t` until the iteration cap trips, with a far less useful message.
        if !SciMLBase.successful_retcode(integ.sol.retcode)
            error(nameof(E), " playback integration failed: retcode = ",
                  integ.sol.retcode, " at t = ", integ.t)
        end

        # ORDER IS LOAD-BEARING, AND THIS IS THE ONLY PLACE THAT SAYS SO. Drain
        # what the step saved FIRST, then apply what is scheduled at this instant.
        # A scheduled `inject!` changes the online set and with it the COI weights
        # `_record_at!` uses, so a sample drained after it would be weighted by a
        # machine set from the wrong side of a trip. It also matches
        # `run_realtime!` sample for sample: there too the sample AT an event
        # instant is the pre-event one, because the queue is drained only after the
        # previous step has already recorded.
        #
        # The same argument bounds what a CALLBACK may do, and the bound holds
        # today: a shed steps a power parameter and an out-of-step relay opens a
        # line, neither of which changes which machines are online. A future
        # protection scheme that tripped a GENERATOR from a callback would break
        # this — samples inside its step would carry the post-trip weights — and
        # would need the weights snapshotted per sample instead.
        @inbounds while nsaved < length(integ.sol.t)
            nsaved += 1
            _record_at!(eng, integ.sol.t[nsaved], integ.sol.u[nsaved])
        end
        si = _playback_apply!(eng, sched, si, integ.t)
    end

    return state_series(eng)
end
