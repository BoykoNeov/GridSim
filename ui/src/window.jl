# The live window for M1 (docs/SPEC.md §7.7): an f(t) trace with a reference line
# at f0, a RoCoF trace beneath it, numeric readouts (f, RoCoF, running nadir), one
# trip button per unit, play/pause, a speed slider, and an inertia bar that drops
# the moment a unit is lost.
#
# Two invariants from docs/SPEC.md shape everything here:
#
#   §3.1  The dependency points one way. This package uses GridSim; the core never
#         sees Makie. Live state crosses the seam through the `Observable` the
#         orchestration loop writes — not a socket, not a second process.
#   §3    Render state ≠ simulation state. The engine owns (Δω, ΔPm) and its own
#         complete trajectory; the rolling plot buffers, the on-screen nadir, the
#         redraw clock and the axis limits below are *render* state and die with
#         the window.

# How often the picture may repaint. The loop publishes a state every `dt` (50 Hz
# at the default dt = 0.02, ten times that with the speed slider at maximum) —
# far more often than a screen can usefully redraw. The buffers below take every
# published state; only the repaint is rate-limited, so nothing is dropped from
# the picture, it just arrives in batches.
const REDRAW_INTERVAL = 1 / 30

"""
    RollingTrace(capacity)

Fixed-capacity plot history for one series, oldest point dropped when full.

The engine's own `ts`/`fs`/`rocofs` vectors grow without bound (a known, deferred
core issue) — plotting straight from them would re-upload an ever-longer array on
every frame and compress the time axis into an unreadable smear over a long run.
A bounded buffer plus a moving x-window fixes both, and is render state by
construction (docs/SPEC.md §3).

`points` is the `Observable` Makie draws. `push!` mutates it *without* notifying:
the redraw is triggered separately, on the throttled path.
"""
struct RollingTrace
    points::Observable{Vector{Point2f}}
    capacity::Int
end

RollingTrace(capacity::Integer) = RollingTrace(Observable(Point2f[]), Int(capacity))

function Base.push!(tr::RollingTrace, x::Real, y::Real)
    v = tr.points[]
    push!(v, Point2f(x, y))
    # `popfirst!` on a Julia Vector is amortised O(1) (it advances the array's own
    # offset), so the rolling window costs nothing per step.
    length(v) > tr.capacity && popfirst!(v)
    return tr
end

"""
    _build_window(model; dt, rtf, window_seconds, shed, title)

Assemble the figure, the engine, and the live wiring, and return them as a named
tuple `(; fig, engine, control, queue, state, status, refresh!)`.

Shared by both entry points on purpose: the PNG that `smoke_render` saves is a
picture of the very window `launch` opens, not of a separate "test figure" that
could drift away from it.

Nothing is started here — no window is displayed and no task is spawned. The
caller decides whether this figure goes on a screen or into a file.

The look is `GRIDSIM_THEME` (`theme.jl`), applied through `themed` so it is scoped
to the build and never leaks into a caller's own Makie session.
"""
_build_window(model::SystemModel; kwargs...) =
    themed(() -> _build_window_impl(model; kwargs...))

function _build_window_impl(model::SystemModel;
                       dt::Real = 0.02,
                       rtf::Real = 1.0,
                       window_seconds::Real = 60.0,
                       shed::Vector{LoadShedStage} = LoadShedStage[],
                       title::AbstractString = "GridSim — real-time frequency response",
                       ylims_f = nothing,
                       ylims_rocof = nothing)
    engine = init!(FrequencyResponseEngine, model; dt = dt, shed = shed)
    queue = EventQueue()
    control = RealtimeControl(; rtf = rtf)

    s0 = current_state(engine)
    state = Observable(s0)
    status = Observable("armed — all units online")

    f0 = model.f0
    w = Float64(window_seconds)
    capacity = max(64, ceil(Int, w / Float64(dt)) + 2)
    ftrace = RollingTrace(capacity); push!(ftrace, s0.t, s0.f)
    rtrace = RollingTrace(capacity); push!(rtrace, s0.t, s0.RoCoF)

    fig = Figure(size = (1240, 780))

    ax_f = Axis(fig[1, 1]; title = title, ylabel = "frequency (Hz)",
                xticklabelsvisible = false)
    ax_r = Axis(fig[2, 1]; xlabel = "simulation time (s)", ylabel = "RoCoF (Hz/s)")
    linkxaxes!(ax_f, ax_r)

    hlines!(ax_f, [f0]; color = (C_MUTED, 0.7), linestyle = :dash)   # nominal reference
    nadir_line = Observable([f0])
    hlines!(ax_f, nadir_line; color = (C_WARN, 0.6), linestyle = :dot)
    lines!(ax_f, ftrace.points; color = C_SWING, linewidth = 2)

    hlines!(ax_r, [0.0]; color = (C_MUTED, 0.7), linestyle = :dash)
    lines!(ax_r, rtrace.points; color = C_AGGREGATE, linewidth = 1.5)

    # ---- controls column ---------------------------------------------------
    gc = fig[1:2, 2] = GridLayout(tellheight = false, valign = :top)

    # The read-out: names written once, values rewritten at `READOUT_INTERVAL`
    # (theme.jl explains the cost that split). `readout` is the composite a test
    # or a caller reads — exactly the two labels' rows joined, never a third text.
    keys = "t\nf\nRoCoF\nnadir\nH_sys"
    gro = gc[1, 1] = GridLayout()
    ro = readout_block!(gro, keys)
    readout = Observable("")

    H0 = system_inertia(engine)
    hbar = Observable([H0])
    ax_h = Axis(gc[2, 1]; ylabel = "H_sys (s)", height = 110,
                xticksvisible = false, xticklabelsvisible = false,
                xgridvisible = false)
    # A ghost of the pre-disturbance inertia behind the live bar: without a fixed
    # reference the drop is only visible to someone who watched it happen.
    barplot!(ax_h, [1], [H0]; color = (C_INERTIA, 0.18), width = 0.6)
    barplot!(ax_h, [1], hbar; color = C_INERTIA, width = 0.6)
    ylims!(ax_h, 0, H0 * 1.2)
    xlims!(ax_h, 0.2, 1.8)

    gb = gc[3, 1] = GridLayout()
    section_label!(gb[1, 1], "trip a unit")
    unit_buttons = Tuple{Symbol,Button}[]
    for (i, u) in enumerate(model.units)
        b = Button(gb[i + 1, 1]; label = @sprintf("%s  —  %.0f MW", u.id, u.P0),
                   tellwidth = false)
        # Queue it, never `inject!` from the click handler: events are applied at a
        # step boundary by the loop, so a click can never land mid-integration.
        on(b.clicks) do _
            push!(queue, TripGenerator(u.id))
            status[] = string("queued: trip ", u.id)
        end
        push!(unit_buttons, (u.id, b))
    end

    gp = gc[4, 1] = GridLayout()
    b_pause = Button(gp[1, 1]; label = "pause", tellwidth = false)
    on(b_pause.clicks) do _
        control.paused[] = !control.paused[]
        b_pause.label[] = control.paused[] ? "resume" : "pause"
        status[] = control.paused[] ? "paused — sim time frozen" : "running"
    end
    b_stop = Button(gp[1, 2]; label = "stop", tellwidth = false)
    on(b_stop.clicks) do _
        stop!(control)
        status[] = "stopped — close window to exit"
    end

    section_label!(gc[5, 1], "speed (× real time)")
    # Finite range on purpose: `rtf = Inf` means "no pacing at all", which starves
    # the renderer — that mode belongs to headless runs, not to a slider.
    sl = Slider(gc[6, 1]; range = 0.1:0.1:10.0,
                startvalue = clamp(Float64(rtf), 0.1, 10.0), tellwidth = false)
    on(sl.value) do v
        control.rtf[] = Float64(v)
    end
    Label(gc[7, 1], lift(v -> @sprintf("%.1f×   (step %.0f ms)", v, 1000 * timestep(engine)),
                         sl.value);
          halign = :left, tellwidth = false, font = MONO_FONT, fontsize = 13)
    # `word_wrap` needs a bounded width to wrap against — hence the fixed control
    # column below; without it a long status line runs off the edge of the figure.
    Label(gc[8, 1], status; halign = :left, justification = :left, tellwidth = false,
          color = C_WARN, word_wrap = true)

    # Sized only now: `rowsize!`/`colsize!` address cells that must already exist,
    # and column 2 is created by the controls layout above.
    rowsize!(fig.layout, 2, Relative(0.28))
    colsize!(fig.layout, 2, Fixed(300))
    rowgap!(gc, 12)

    # ---- render state (never simulation state) -----------------------------
    nadir = Ref(s0.f)          # running minimum of what has been *shown*
    last_draw = Ref(0.0)       # wall clock of the last repaint
    last_readout = Ref(0.0)    # wall clock of the last read-out rewrite
    ylo = Ref(f0 - 2.0)        # frequency axis box, expand-only
    yhi = Ref(f0 + 0.6)
    rspan = Ref(0.5)           # RoCoF axis half-height, expand-only
    rmax = Ref(0.0)            # largest |RoCoF| *published*, not merely drawn
    greyed = Set{Symbol}()     # units whose button has already been marked offline

    # Pinned axes disable the expand-only logic below. Expand-only is right for a
    # live window — nobody can choose limits for a run that has not happened yet —
    # but it is wrong for *comparing* two runs: each picture ends up on its own
    # scale, so a dip three times deeper draws exactly the same shape as a shallow
    # one. Anything rendering a comparison must pin both runs to one scale.
    fixed_f = ylims_f !== nothing
    fixed_r = ylims_rocof !== nothing
    fixed_f ? ylims!(ax_f, ylims_f[1], ylims_f[2]) : ylims!(ax_f, ylo[], yhi[])
    fixed_r ? ylims!(ax_r, ylims_rocof[1], ylims_rocof[2]) : ylims!(ax_r, -rspan[], rspan[])

    # Repaint, at most once every `REDRAW_INTERVAL` unless forced. Reads the latest
    # published state; the buffers were already filled by the state handler.
    function refresh!(; force::Bool = false)
        now = time()
        (force || now - last_draw[] ≥ REDRAW_INTERVAL) || return nothing
        last_draw[] = now
        s = state[]

        # x: a window that moves with the run, so a multi-minute session stays
        # readable instead of collapsing into a smear.
        xlims!(ax_f, max(0.0, s.t - w), max(w, s.t))

        # y: expand-only, and driven by the running extremes the *state handler*
        # accumulates — never by `s`, the state that happens to be current at this
        # repaint. The dip's deepest point almost always falls between two
        # repaints (30 fps against 50–500 states/s), so sizing the box from the
        # sampled state clips exactly the feature the window exists to show.
        # Recomputing autolimits per state, the other option, is both a real
        # sluggishness source and a picture that jitters; growing the box only
        # when an extreme approaches its edge keeps the scale stable and makes two
        # runs visually comparable.
        if !fixed_f && nadir[] < ylo[] + 0.25
            ylo[] = nadir[] - 0.5
            ylims!(ax_f, ylo[], yhi[])
        end
        if !fixed_r && rmax[] > 0.9 * rspan[]
            rspan[] = 1.25 * rmax[]
            ylims!(ax_r, -rspan[], rspan[])
        end

        nadir_line[] = [nadir[]]
        hbar[] = [system_inertia(engine)]
        # Text is the expensive part of a repaint (theme.jl), so the numbers are
        # rewritten on their own, slower clock. Everything the read-out shows is
        # still exact — the nadir is the running minimum over every state.
        if force || now - last_readout[] ≥ READOUT_INTERVAL
            last_readout[] = now
            vals = @sprintf("%8.2f s\n%8.3f Hz\n%8.3f Hz/s\n%8.3f Hz\n%8.3f s",
                            s.t, s.f, s.RoCoF, nadir[], system_inertia(engine))
            ro.values[] = vals
            readout[] = readout_text(keys, vals)
        end

        for (id, b) in unit_buttons
            if !(id in greyed) && !is_online(engine, id)
                push!(greyed, id)
                b.label[] = string(id, "  —  offline")
            end
        end

        # One notify per trace per repaint: the buffers were mutated in place.
        notify(ftrace.points)
        notify(rtrace.points)
        return nothing
    end

    # The seam itself: the loop writes a state, this reacts. Runs on the loop's
    # task, which is an `@async` task on the main thread — the reason the core
    # loop is cooperative rather than `Threads.@spawn`ed, since GLMakie must not
    # be driven from another thread.
    on(state) do s
        push!(ftrace, s.t, s.f)
        push!(rtrace, s.t, s.RoCoF)
        # Every published state updates the extremes, even the ones no repaint ever
        # samples — this is what keeps the nadir readout exact and the axes honest.
        s.f < nadir[] && (nadir[] = s.f)
        abs(s.RoCoF) > rmax[] && (rmax[] = abs(s.RoCoF))
        refresh!()
    end

    refresh!(; force = true)
    # `widgets` is exported so the package's own tests can drive the controls the
    # way a user does — setting `b.clicks[]` runs the same handler a real click
    # runs, which is the only way to check the click path without a screen.
    widgets = (; unit_buttons, pause = b_pause, stop = b_stop, speed = sl)
    axes = (; frequency = ax_f, rocof = ax_r, inertia = ax_h)
    # `readout` rides along so a test can assert what the window actually *shows*
    # — in particular that the displayed nadir is the true minimum over every
    # published state, not whichever state a repaint happened to sample.
    return (; fig, engine, control, queue, state, status, readout, refresh!, widgets,
              axes)
end

"""
    launch(model = example_system(); dt = 0.02, rtf = 1.0, window_seconds = 60.0,
           shed = LoadShedStage[], duration = Inf)

Open the live window and start the real-time loop, returning
`(; fig, engine, control, queue, state, status, refresh!, task)`.

The window is interactive immediately: trip buttons queue a `TripGenerator` for
the next step boundary, pause freezes simulation time (the loop re-anchors its
pacing on resume so it never sprints to catch up), and the slider changes speed
mid-run because the loop re-reads `control.rtf[]` every pass.

From a shell, this must be followed by something that blocks, or the process
exits and takes the window with it:

    julia --project=ui -e "using GridSimUI; wait_for_close(launch())"
"""
function launch(model::SystemModel = example_system();
                dt::Real = 0.02,
                rtf::Real = 1.0,
                window_seconds::Real = 60.0,
                shed::Vector{LoadShedStage} = LoadShedStage[],
                duration::Real = Inf)
    GLMakie.activate!(; visible = true, title = "GridSim")
    win = _build_window(model; dt = dt, rtf = rtf, window_seconds = window_seconds,
                        shed = shed)
    # Keep the screen handle: it is what a caller needs to grab a frame from the
    # *visible* renderer (`Makie.colorbuffer(screen)`) rather than from an offscreen
    # rebuild, and it is the natural thing to wait on.
    screen = display(win.fig)

    # Closing the window must end the loop. With `duration = Inf` the loop runs
    # until `control.running[]` clears, so without this the task outlives the
    # window and spins forever on a figure nobody can see.
    on(events(win.fig.scene).window_open) do open
        open || stop!(win.control)
    end

    # `@async`, never `Threads.@spawn`: GLMakie is not safe to drive off the main
    # thread, and the Observable write inside the loop is exactly what triggers the
    # redraw. `errormonitor` plus the status line close the hazard the M1 task list
    # deferred to this batch — a throw inside a task nobody waits on is otherwise
    # silent, and the window would just stop updating with no explanation.
    task = Base.errormonitor(@async begin
        try
            run_realtime!(win.engine, win.state; control = win.control,
                          queue = win.queue, duration = duration)
            win.status[] = "simulation finished"
        catch err
            win.status[] = "simulation stopped: " * sprint(showerror, err)
            rethrow()
        end
    end)

    return (; win..., screen, task)
end

"""
    wait_for_close(win)

Block until the user closes the window, then ask the loop to stop. What a
`julia -e` one-liner needs so the process does not exit the instant the window
opens.
"""
function wait_for_close(win)
    while events(win.fig.scene).window_open[]
        sleep(0.1)
    end
    # A playback window has no `control`, because it has no loop to stop: the run
    # finished before the figure existed (M4 step 3). Guarded rather than given a
    # dummy control block — a `RealtimeControl` that nothing reads would be a
    # piece of machinery whose only content is that it does nothing.
    haskey(win, :control) && stop!(win.control)
    return win
end

"""
    smoke_render(model = example_system(); path, dt = 0.02, trips = [(2.0, :G1)],
                 duration = 20.0, shed = LoadShedStage[], title = …) -> path

Build the *same* window offscreen, drive it through a scripted trip timeline as
fast as the machine allows, and save a PNG to `path`.

This is how the window is verified from a session with no screen to look at, and
what turns "the UI code compiles" into a picture of an actual dip. Trips go
through the `EventQueue` and the real loop — the identical path a button click
takes — so the render exercises the live wiring, not a bypass.

Pass `ylims_f` / `ylims_rocof` as `(lo, hi)` to pin the axes instead of letting
them size themselves to the run. Required whenever two renders are meant to be
*compared*: with per-run limits each picture fills its own frame, so a dip three
times deeper draws the same shape as a shallow one and the comparison shows
nothing.
"""
function smoke_render(model::SystemModel = example_system();
                      path::AbstractString,
                      dt::Real = 0.02,
                      trips::Vector{Tuple{Float64,Symbol}} = [(2.0, :G1)],
                      duration::Real = 20.0,
                      shed::Vector{LoadShedStage} = LoadShedStage[],
                      title::AbstractString = "GridSim — real-time frequency response",
                      ylims_f = nothing,
                      ylims_rocof = nothing)
    GLMakie.activate!(; visible = false)
    # `window_seconds = duration` keeps the whole run inside the rolling buffer and
    # the x-window, so the saved frame shows the entire event rather than its tail.
    win = _build_window(model; dt = dt, rtf = Inf, window_seconds = duration,
                        shed = shed, title = title,
                        ylims_f = ylims_f, ylims_rocof = ylims_rocof)
    win.control.rtf[] = Inf     # flat out: no wall-clock pacing for a file render

    t_now = 0.0
    for (t_trip, id) in sort(trips; by = first)
        seg = Float64(t_trip) - t_now
        seg > 0 && run_realtime!(win.engine, win.state; control = win.control,
                                 queue = win.queue, duration = seg)
        push!(win.queue, TripGenerator(id))
        t_now = max(t_now, Float64(t_trip))
    end
    rest = Float64(duration) - t_now
    rest > 0 && run_realtime!(win.engine, win.state; control = win.control,
                              queue = win.queue, duration = rest)

    win.refresh!(; force = true)
    mkpath(dirname(path))
    save(path, win.fig)
    return path
end
