# The real-time orchestration loop (docs/SPEC.md §7.5, m1-plan.md step 5).
#
# Responsibilities, and nothing else: drain the pending perturbation events into
# the engine at a step boundary, advance the engine by one `dt`, publish the new
# state to an `Observable` the UI can subscribe to, and pace the whole thing to
# wall-clock time. It is engine-agnostic — it only speaks the `SimulationEngine`
# verbs (`step!`, `current_state`, `inject!`, `timestep`), so every future
# fidelity tier drops straight in.
#
# INVARIANT: this file must NEVER import Makie or any UI/plotting package.
# `Observables.jl` is a standalone package (Makie depends on it, not the reverse),
# so publishing live state through it keeps the core UI-free. `test/runtests.jl`
# asserts the dependency closure contains Observables and no Makie.
#
# Threading: the loop is designed to run as a **cooperative task** (`@async`),
# not on a separate thread — the UI batch drives GLMakie, which is not safe to
# mutate off the main thread, and the `Observable` write here is exactly what
# triggers a redraw. Every blocking stretch below therefore `yield()`s or
# `sleep()`s so the UI task keeps running. The queue is lock-guarded anyway: it
# costs nothing at 50 Hz and leaves the door open to a `Threads.@spawn` loop
# whose events are pushed from elsewhere.

# `push!`, `isempty`, `length` and `empty!` belong to Base. Defining them here
# without importing would create *new* GridSim generics that shadow Base's for
# every call site in the package — the same collision class already resolved for
# `step!`/`solve!` via CommonSolve (see engines/interface.jl). `drain!` is not in
# Base, so it stays a GridSim-owned generic.
import Base: push!, isempty, length, empty!

"""
    EventQueue()

Thread-safe FIFO of pending `PerturbationEvent`s. The UI (or a script) `push!`es
events from wherever it likes; the real-time loop `drain!`s them at a step
boundary and hands each to `inject!`. Nothing is ever applied mid-step.

The element type is the abstract `PerturbationEvent` — deliberately: this is the
cold path (a handful of user clicks), never the RHS hot path, and the alternative
would be an engine-specific union. Events are applied by dynamic dispatch on
`inject!` regardless.
"""
mutable struct EventQueue
    lock::ReentrantLock
    events::Vector{PerturbationEvent}
end

EventQueue() = EventQueue(ReentrantLock(), PerturbationEvent[])

# Returned by `drain!` when nothing is pending — avoids allocating a fresh empty
# vector on every one of the ~50 steps per second that carry no event. Callers
# only ever iterate the result, never mutate it.
const _NO_EVENTS = PerturbationEvent[]

"""
    push!(q::EventQueue, ev::PerturbationEvent) -> q

Queue an event for the next step boundary. Safe to call from any task.
"""
function push!(q::EventQueue, ev::PerturbationEvent)
    lock(q.lock) do
        push!(q.events, ev)
    end
    return q
end

"""
    drain!(q::EventQueue) -> Vector{PerturbationEvent}

Atomically take everything pending and leave the queue empty, returning the
events in submission order. Implemented as a *swap* under the lock (hand out the
existing vector, install a fresh one) so the critical section is O(1) and the
caller can iterate at leisure without holding the lock.
"""
function drain!(q::EventQueue)
    lock(q.lock) do
        isempty(q.events) && return _NO_EVENTS
        evs = q.events
        q.events = PerturbationEvent[]
        return evs
    end
end

isempty(q::EventQueue) = lock(() -> isempty(q.events), q.lock)
length(q::EventQueue) = lock(() -> length(q.events), q.lock)
empty!(q::EventQueue) = (lock(() -> empty!(q.events), q.lock); q)

"""
    RealtimeControl(; rtf = 1.0, running = true, paused = false)

Live controls for `run_realtime!`, held as `Observable`s so the UI can bind a
play/pause toggle and a speed slider straight to them and the running loop picks
the change up on its very next pass (docs/SPEC.md §7.7).

  - `running` — set to `false` to end the loop (it returns after the current step).
  - `paused`  — `true` freezes simulation time; the loop idles, stays responsive,
                and re-anchors its wall-clock pacing on resume so it does not
                "owe" the paused seconds and sprint to catch up.
  - `rtf`     — real-time factor: `1.0` is wall-clock speed, `2.0` twice as fast,
                `0.25` slow motion. `Inf` means *as fast as possible* (no sleeping)
                — that is the headless/batch mode, and it shares the exact same
                code path as the paced UI run.

All three fields are concretely typed `Observable`s (docs/SPEC.md §4).
"""
struct RealtimeControl
    running::Observables.Observable{Bool}
    paused::Observables.Observable{Bool}
    rtf::Observables.Observable{Float64}
end

RealtimeControl(; rtf::Real = 1.0, running::Bool = true, paused::Bool = false) =
    RealtimeControl(Observables.Observable(running), Observables.Observable(paused),
                    Observables.Observable(Float64(rtf)))

"""
    stop!(ctl::RealtimeControl)

Ask the loop to finish (it returns after the step in flight). Idempotent.
"""
stop!(ctl::RealtimeControl) = (ctl.running[] = false; ctl)

# Publish the state to whatever the caller supplied. Dispatch, not a
# `Union{Observable,Nothing}` field — `state_obs` stays a function argument so no
# struct gains an abstract field (docs/SPEC.md §4). Headless callers pass
# `nothing` and pay nothing.
_publish!(::Nothing, s) = nothing
_publish!(obs::Observables.Observable, s) = (obs[] = s; nothing)

# Wall-clock pacing for one step. `deadline` is the absolute `time()` at which
# this step's real-time budget expires; block until then, yielding so a co-running
# UI task keeps drawing, then return the deadline to carry forward.
#
# The return value is the *re-anchoring* half: if the step overran its budget by
# more than `max_lag`, we abandon the debt and restart the clock from now. Without
# that, a slow patch (a GC pause, a heavy redraw, a machine hiccup) leaves the
# loop permanently behind and it sprints through the backlog at full speed — the
# opposite of the smooth playback the pacing exists to provide.
function _pace(deadline::Float64, max_lag::Float64)
    while true
        remaining = deadline - time()
        remaining <= 0 && break
        # `sleep` resolution is ~1 ms (worse on Windows), so hand the last
        # millisecond to a yielding spin rather than oversleeping past it.
        remaining > 2e-3 ? sleep(remaining - 1e-3) : yield()
    end
    now = time()
    return now > deadline + max_lag ? now : deadline
end

"""
    run_realtime!(engine, state_obs = nothing;
                  rtf = 1.0, control = RealtimeControl(; rtf), queue = EventQueue(),
                  dt = timestep(engine), duration = Inf, max_lag = 0.25)
        -> (; engine, control, queue)

Drive a real-time engine, publishing each new state to `state_obs` and pacing to
wall-clock time (docs/SPEC.md §7.5). One pass of the loop is:

    drain the event queue → inject! each event → step!(engine, dt)
      → publish current state to the Observable → sleep to the wall-clock deadline

`state_obs` is an `Observable` the UI subscribes to (its value is whatever
`current_state(engine)` returns), or `nothing` for a headless run.

Stops when any of: `duration` seconds of **simulation** time have elapsed,
`control.running[]` goes `false`, or the engine's own `step!` throws. Returns the
engine together with the `control` and `queue` actually used, so a caller that
let them default can still reach them (e.g. to `stop!` a loop it launched with
`@async`).

Keyword arguments:

  - `rtf` — seeds `control.rtf`; ignored if you pass your own `control` (the
    control observable is the single source of truth once it exists). `Inf` runs
    flat out — headless scripts and tests want this, and it is the same code path
    as a paced run, so the loop is exercised identically either way.
  - `dt` — the simulation step handed to `step!`; defaults to the engine's own.
  - `duration` — simulation seconds to run *from now*. `Inf` (the default) runs
    until `control.running[]` is cleared, so an unattended caller should always
    set one — a `duration = Inf` loop with no other task to stop it never returns.
  - `max_lag` — wall-clock seconds of accumulated lateness tolerated before the
    pacing clock re-anchors instead of trying to catch up.

Intended to run as a cooperative task (`@async run_realtime!(...)`) alongside a
GLMakie window on the main thread; every wait inside yields.
"""
function run_realtime!(engine::SimulationEngine, state_obs = nothing;
                       rtf::Real = 1.0,
                       control::RealtimeControl = RealtimeControl(; rtf),
                       queue::EventQueue = EventQueue(),
                       dt::Real = timestep(engine),
                       duration::Real = Inf,
                       max_lag::Real = 0.25)
    dtf = Float64(dt)
    max_lagf = Float64(max_lag)
    t_stop = current_state(engine).t + Float64(duration)
    deadline = time()

    while control.running[] && current_state(engine).t < t_stop
        if control.paused[]
            # Frozen: simulation time does not advance and no events are applied.
            # Idle briefly (keeps the task responsive without burning a core) and
            # re-anchor the pacing clock so the pause is not counted as debt.
            sleep(0.01)
            deadline = time()
            continue
        end

        for ev in drain!(queue)
            inject!(engine, ev)
        end

        s = step!(engine, dtf)
        _publish!(state_obs, s)

        # Read the speed fresh every pass — the UI slider moves mid-run, so any
        # deadline derived once from a start time would be wrong the moment it does.
        r = control.rtf[]
        if isfinite(r) && r > 0
            deadline = _pace(deadline + dtf / r, max_lagf)
        else
            # rtf = Inf (or nonsensical): no pacing. Still yield, so a co-running
            # UI/driver task is not starved by a flat-out headless loop.
            deadline = time()
            yield()
        end
    end

    return (; engine, control, queue)
end
