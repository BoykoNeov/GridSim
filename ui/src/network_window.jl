# The live window for M2's multi-machine swing engine (docs/plans/m2-plan.md §7).
#
# It is a SIBLING of the M1 window in `window.jl`, not a generalisation of it, and
# that is step 7's second decision. The two engines do not accept the same
# controls: `TripLine` on the aggregate view is a `MethodError` (a `SystemModel`
# has no branches) and `StepLoad` has no `SwingEngine` method (a classical-tier
# load is a machine, and there is no aggregate imbalance to move). The set of
# buttons a window can offer is therefore a property of the *engine*, not of the
# `SimulationEngine` interface — so it is settled by dispatch on the model type
# rather than by a runtime branch inside one window that pretends both fit.
#
# The same three invariants as `window.jl` shape it (SPEC §3.1, §3): the
# dependency points one way, live state crosses the seam through an `Observable`,
# and render state is not simulation state. Two more are specific to this tier:
#
#   HZ EVERYWHERE ON THE FREQUENCY AXIS. A machine's `ω` is a per-unit speed
#   deviation and the aggregate is Hz; they cannot share an axis as they stand.
#   Each machine is converted to `f0·(1 + ωᵢ)` at this boundary and nowhere else,
#   which is also the project convention (per-unit internally, engineering units
#   at the UI seam). The aggregate is then genuinely an overlay of the same
#   quantity rather than a second thing drawn in the same box.
#
#   ANGLES ARE DRAWN AGAINST THE AGGREGATE, NEVER RAW. `find_fixpoint` fixes the
#   gauge arbitrarily, so an absolute rotor angle is not a plottable number, and
#   after a generator trip every surviving angle grows without bound. `δᵢ − δ_coi`
#   is gauge-free and stays on screen. A reference *machine* would have been the
#   obvious alternative and is wrong twice over: pick the machine that later trips
#   and every trace goes to garbage, and the tripped machine diverges against any
#   single survivor regardless of which one is chosen. The aggregate degrades
#   gracefully in both cases — it tracks the surviving cluster, and a machine that
#   leaves it visibly separates, which is the honest picture.

# How many log entries the written event list shows at once. The dashed markers
# on the plots are never trimmed — this bounds only the text, which lives in a
# fixed-height column and would otherwise push the widgets below it off the figure.
const _EVENTS_SHOWN = 6

"""
    _build_network_window(net; dt, rtf, window_seconds, title, ylims_f, ylims_δ)

Assemble the figure, the `SwingEngine`, and the live wiring for a network model,
returning `(; fig, engine, control, queue, state, status, readout, refresh!,
widgets, axes)` — the same shape `_build_window` returns for M1, so both entry
points and both test suites drive a window the same way.

Shared by `launch` and `smoke_render` for the same reason the M1 builder is: the
PNG a headless session looks at has to be a picture of the window a user opens,
not of a test figure that can drift away from it.

Nothing is started here — no window is displayed and no task is spawned.
"""
function _build_network_window(net::NetworkModel;
                               dt::Real = 0.02,
                               rtf::Real = 1.0,
                               window_seconds::Real = 30.0,
                               title::AbstractString = "GridSim — multi-machine swing",
                               ylims_f = nothing,
                               ylims_δ = nothing)
    engine = init!(SwingEngine, net; dt = dt)
    queue = EventQueue()
    control = RealtimeControl(; rtf = rtf)

    ids = machine_ids(engine)
    n = length(ids)
    s0 = current_state(engine)
    state = Observable(s0)
    status = Observable(@sprintf("armed — %d machines, %d lines in service",
                                 n, length(net.branches)))

    f0 = net.f0
    w = Float64(window_seconds)
    capacity = max(64, ceil(Int, w / Float64(dt)) + 2)

    # One rolling buffer per machine per panel, plus the aggregate. Fixed capacity,
    # like M1's and for the same two reasons: the engine's own trajectory is bounded
    # but decimating (so it is not a plot source), and re-uploading an ever-longer
    # array every frame compresses the time axis into a smear.
    ftraces = [RollingTrace(capacity) for _ in 1:n]
    δtraces = [RollingTrace(capacity) for _ in 1:n]
    coitrace = RollingTrace(capacity)
    for i in 1:n
        push!(ftraces[i], s0.t, f0 * (1 + s0.ω[i]))
        push!(δtraces[i], s0.t, s0.δ[i] - s0.δ_coi)
    end
    push!(coitrace, s0.t, s0.f_coi)

    # Taller than the M1 window because the control column carries a second button
    # group and an event list. Sized to fit the shipped examples without clipping;
    # a network with many more machines or branches would still overflow the
    # column, which a scrolling control panel is the real answer to and this is
    # deliberately not (see the `valign` note below for what overflow then does).
    fig = Figure(size = (1360, 900))

    ax_f = Axis(fig[1, 1]; title = title, ylabel = "frequency (Hz)",
                xticklabelsvisible = false)
    ax_δ = Axis(fig[2, 1]; xlabel = "simulation time (s)",
                ylabel = "rotor angle − COI (rad)")
    linkxaxes!(ax_f, ax_δ)

    # Vertical markers wherever a perturbation was actually applied. Fed from the
    # engine's own event log — not from the click handler — so a scripted run and a
    # clicked one mark the same instants (see engines/swing.jl).
    event_times = Observable(Float64[])
    vlines!(ax_f, event_times; color = (:black, 0.35), linestyle = :dash)
    vlines!(ax_δ, event_times; color = (:black, 0.35), linestyle = :dash)

    hlines!(ax_f, [f0]; color = (:gray, 0.8), linestyle = :dash)   # nominal reference
    hlines!(ax_δ, [0.0]; color = (:gray, 0.8), linestyle = :dash)  # the COI itself

    palette = GLMakie.Makie.wong_colors()
    machine_color(i) = palette[mod1(i, length(palette))]
    for i in 1:n
        lines!(ax_f, ftraces[i].points; color = machine_color(i), linewidth = 1.2,
               label = String(ids[i]))
        lines!(ax_δ, δtraces[i].points; color = machine_color(i), linewidth = 1.2,
               label = String(ids[i]))
    end
    # Drawn last and heavier: the aggregate is the same quantity as the thin traces
    # (Hz), so it reads as their weighted centre rather than as a separate series.
    lines!(ax_f, coitrace.points; color = :black, linewidth = 2.5, label = "COI")
    axislegend(ax_f; position = :rb, framevisible = false, labelsize = 11,
               orientation = :horizontal)

    # ---- controls column ---------------------------------------------------
    # `valign = :top`, not the M1 window's default centring: this column carries
    # two button groups instead of one, so on a network with a few more branches
    # the content grows taller than the figure — centred, it then overflows at BOTH
    # ends and the read-out is the first thing to leave the frame (it did, in the
    # first render of this window). Top-aligned, growth runs off the bottom, where
    # the least important widgets already sit.
    gc = fig[1:2, 2] = GridLayout(tellheight = false, valign = :top)

    readout = Observable("")
    Label(gc[1, 1], readout; halign = :left, justification = :left,
          tellwidth = false, fontsize = 16, font = :regular)

    # The ghost bar behind the live one needs the PRE-disturbance inertia, and the
    # live accessor returns the shrinking sum — so it is captured here, at build
    # time, before any trip can land. Without a fixed reference the drop is only
    # visible to someone who watched it happen.
    H0 = system_inertia(engine)
    hbar = Observable([H0])
    ax_h = Axis(gc[2, 1]; ylabel = "H_sys (s)", height = 100,
                xticksvisible = false, xticklabelsvisible = false,
                xgridvisible = false)
    barplot!(ax_h, [1], [H0]; color = (:seagreen, 0.18), width = 0.6)
    barplot!(ax_h, [1], hbar; color = :seagreen, width = 0.6)
    ylims!(ax_h, 0, H0 * 1.2)
    xlims!(ax_h, 0.2, 1.8)

    # Two button groups, because this engine takes two kinds of event. Both queue
    # rather than inject: events are applied at a step boundary by the loop, so a
    # click can never land mid-integration.
    gm = gc[3, 1] = GridLayout()
    Label(gm[1, 1], "trip a machine"; halign = :left, tellwidth = false)
    machine_buttons = Tuple{Symbol,Button}[]
    for (i, m) in enumerate(net.machines)
        b = Button(gm[i + 1, 1]; label = @sprintf("%s  —  %+.0f MW", m.id, m.P0),
                   tellwidth = false)
        on(b.clicks) do _
            push!(queue, TripGenerator(m.id))
            status[] = string("queued: trip ", m.id)
        end
        push!(machine_buttons, (m.id, b))
    end

    gl = gc[4, 1] = GridLayout()
    Label(gl[1, 1], "trip a line"; halign = :left, tellwidth = false)
    line_buttons = Tuple{Symbol,Symbol,Button}[]
    for (i, br) in enumerate(net.branches)
        b = Button(gl[i + 1, 1]; label = @sprintf("%s  —  %s–%s", br.id, br.from, br.to),
                   tellwidth = false)
        on(b.clicks) do _
            push!(queue, TripLine(br.from, br.to))
            status[] = string("queued: trip line ", br.from, "–", br.to)
        end
        push!(line_buttons, (br.from, br.to, b))
    end

    gp = gc[5, 1] = GridLayout()
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

    Label(gc[6, 1], "speed (× real time)"; halign = :left, tellwidth = false)
    sl = Slider(gc[7, 1]; range = 0.1:0.1:10.0,
                startvalue = clamp(Float64(rtf), 0.1, 10.0), tellwidth = false)
    on(sl.value) do v
        control.rtf[] = Float64(v)
    end
    Label(gc[8, 1], lift(v -> @sprintf("%.1f×   (step %.0f ms)", v,
                                       1000 * timestep(engine)), sl.value);
          halign = :left, tellwidth = false)

    # What actually happened, in words, beside the dashed lines that mark when. The
    # traces cannot say which line opened — this and the markers are the only place
    # a played-back run learns it (see engines/swing.jl).
    Label(gc[9, 1], "events"; halign = :left, tellwidth = false)
    event_text = Observable("(none yet)")
    Label(gc[10, 1], event_text; halign = :left, justification = :left,
          tellwidth = false, fontsize = 13, word_wrap = true)

    Label(gc[11, 1], status; halign = :left, tellwidth = false, color = :firebrick,
          word_wrap = true)

    rowsize!(fig.layout, 2, Relative(0.42))
    colsize!(fig.layout, 2, Fixed(310))
    rowgap!(gc, 8)

    # ---- render state (never simulation state) -----------------------------
    nadir = Ref(s0.f_coi)      # running minimum of the aggregate, over every state
    last_draw = Ref(0.0)
    flo = Ref(f0 - 1.0)        # frequency box, expand-only
    fhi = Ref(f0 + 0.6)
    δspan = Ref(0.5)           # angle box half-height, expand-only
    fmin = Ref(f0)             # extremes over every PUBLISHED state, not every drawn one
    fmax = Ref(f0)
    δmax = Ref(0.0)
    greyed = Set{Symbol}()     # machines already marked offline
    greyed_lines = Set{Tuple{Symbol,Symbol}}()
    drawn_events = Ref(0)      # how many log entries the markers already show
    # A TRIPPED MACHINE IS DRAWN BUT SCALES NOTHING. Its rotor is decoupled and
    # undriven, so its angle relative to the COI grows without bound — the first
    # render of this window put a survivor spread of 0.1 rad on an axis 300 rad
    # tall, and every trace the panel exists to show was a flat line at zero. The
    # same argument applies to the frequency spread read-out: the difference
    # between a dead rotor coasting at nominal and a system sinking at 2.7 % is not
    # a spread, it is two unrelated numbers subtracted. So the extremes below are
    # accumulated over ONLINE machines only, and a machine that leaves simply walks
    # off the top of the frame — which is the honest picture of what happened.
    online = fill(true, n)

    fixed_f = ylims_f !== nothing
    fixed_δ = ylims_δ !== nothing
    fixed_f ? ylims!(ax_f, ylims_f[1], ylims_f[2]) : ylims!(ax_f, flo[], fhi[])
    fixed_δ ? ylims!(ax_δ, ylims_δ[1], ylims_δ[2]) : ylims!(ax_δ, -δspan[], δspan[])

    function refresh!(; force::Bool = false)
        now = time()
        (force || now - last_draw[] ≥ REDRAW_INTERVAL) || return nothing
        last_draw[] = now
        s = state[]

        xlims!(ax_f, max(0.0, s.t - w), max(w, s.t))

        # Expand-only, driven by the extremes the state handler accumulates rather
        # than by whichever state this repaint happened to sample — the dip's
        # deepest point almost never coincides with a frame. Note that every
        # comparison here is against a running extreme that is finite by
        # construction: `f_coi` is NaN once every machine is offline, and a NaN
        # never wins a `<`, so the box simply stops growing instead of collapsing.
        if !fixed_f && (fmin[] < flo[] + 0.15 || fmax[] > fhi[] - 0.15)
            flo[] = min(flo[], fmin[] - 0.4)
            fhi[] = max(fhi[], fmax[] + 0.4)
            ylims!(ax_f, flo[], fhi[])
        end
        if !fixed_δ && δmax[] > 0.9 * δspan[]
            δspan[] = 1.25 * δmax[]
            ylims!(ax_δ, -δspan[], δspan[])
        end

        hbar[] = [system_inertia(engine)]
        # Both machine-to-machine figures are over the ONLINE machines, for the
        # reason spelled out beside `online` above; with nothing online there is no
        # spread to report and they are NaN rather than a fabricated zero.
        live = findall(online)
        spread = isempty(live) ? NaN :
                 1000 * f0 * (maximum(s.ω[live]) - minimum(s.ω[live]))
        δwidest = isempty(live) ? NaN : maximum(abs, s.δ[live] .- s.δ_coi)
        # `f_coi` prints as NaN in the same case, deliberately: that is what the
        # engine reports when there is no weighted mean left to take, and a
        # fabricated 0.0 or a blanked field would both read as a working system.
        # The nadir beside it stays finite — NaN loses every comparison, so it
        # never becomes the running minimum.
        readout[] = @sprintf("t            %7.2f s\nf_COI        %7.3f Hz\nnadir        %7.3f Hz\nspread       %7.1f mHz\nmax |δ−COI|  %7.3f rad\nH_sys        %7.3f s\n(spread and |δ−COI| over online machines)",
                             s.t, s.f_coi, nadir[], spread, δwidest,
                             system_inertia(engine))

        for (id, b) in machine_buttons
            if !(id in greyed) && !is_online(engine, id)
                push!(greyed, id)
                b.label[] = string(id, "  —  offline")
            end
        end
        # `is_online(engine, from, to)` is a hash lookup as of step 7, and the
        # `greyed_lines` guard keeps even that out of the frame once a line is gone.
        for (from, to, b) in line_buttons
            key = (from, to)
            if !(key in greyed_lines) && !is_online(engine, from, to)
                push!(greyed_lines, key)
                b.label[] = string(from, "–", to, "  —  open")
            end
        end

        # Markers and the event list are rebuilt only when the log has grown — a
        # handful of entries, but this is the redraw path.
        if n_events(engine) != drawn_events[]
            log = event_log(engine)
            drawn_events[] = length(log)
            # EVERY event gets a marker — the plot is where "when" lives, and the
            # markers cost nothing. Only the written list is trimmed to the most
            # recent few, because it is text in a fixed-height column and an
            # untrimmed one would push the widgets below it off the figure.
            event_times[] = [e.t for e in log]
            shown = length(log) > _EVENTS_SHOWN ? log[(end - _EVENTS_SHOWN + 1):end] : log
            head = length(log) > _EVENTS_SHOWN ?
                   @sprintf("(+%d earlier)\n", length(log) - _EVENTS_SHOWN) : ""
            event_text[] = isempty(log) ? "(none yet)" :
                head * join((@sprintf("%6.2f s  %s", e.t, describe(e)) for e in shown), "\n")
        end

        for tr in ftraces; notify(tr.points); end
        for tr in δtraces; notify(tr.points); end
        notify(coitrace.points)
        return nothing
    end

    on(state) do s
        for i in 1:n
            # A `Set` lookup per machine per published state — the same read the
            # buttons use, and the mask the read-out reuses so the two cannot
            # disagree about who is still running.
            online[i] = is_online(engine, ids[i])
            fi = f0 * (1 + s.ω[i])
            push!(ftraces[i], s.t, fi)
            rel = s.δ[i] - s.δ_coi
            push!(δtraces[i], s.t, rel)
            online[i] || continue          # drawn above, but it scales nothing
            fi < fmin[] && (fmin[] = fi)
            fi > fmax[] && (fmax[] = fi)
            abs(rel) > δmax[] && (δmax[] = abs(rel))
        end
        push!(coitrace, s.t, s.f_coi)
        # NaN loses every comparison, so an all-offline system leaves the running
        # extremes at the last real values instead of poisoning them.
        s.f_coi < nadir[] && (nadir[] = s.f_coi)
        s.f_coi < fmin[] && (fmin[] = s.f_coi)
        s.f_coi > fmax[] && (fmax[] = s.f_coi)
        refresh!()
    end

    refresh!(; force = true)
    widgets = (; machine_buttons, line_buttons, pause = b_pause, stop = b_stop,
                 speed = sl)
    axes = (; frequency = ax_f, angle = ax_δ, inertia = ax_h)
    return (; fig, engine, control, queue, state, status, readout, event_text,
              refresh!, widgets, axes)
end

"""
    launch(net::NetworkModel; dt = 0.02, rtf = 1.0, window_seconds = 30.0,
           duration = Inf)

Open the live multi-machine window and start the real-time loop, returning
`(; fig, engine, control, queue, state, status, refresh!, task, screen)`.

Same verb as the M1 `launch`, dispatching on the model: a `NetworkModel` gets the
swing engine and both kinds of trip button, a `SystemModel` gets the aggregate
engine and its own. That the two windows offer different controls is a property of
the engines, not something either window decides at run time.

From a shell this must be followed by something that blocks:

    julia --project=ui -e "using GridSimUI, GridSim; wait_for_close(launch(three_machine_ring()))"
"""
function launch(net::NetworkModel;
                dt::Real = 0.02,
                rtf::Real = 1.0,
                window_seconds::Real = 30.0,
                duration::Real = Inf)
    GLMakie.activate!(; visible = true, title = "GridSim — network")
    win = _build_network_window(net; dt = dt, rtf = rtf,
                                window_seconds = window_seconds)
    screen = display(win.fig)

    on(events(win.fig.scene).window_open) do open
        open || stop!(win.control)
    end

    # `@async`, never `Threads.@spawn` — GLMakie is not safe to drive off the main
    # thread, and the Observable write inside the loop is what triggers the redraw.
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
    smoke_render(net::NetworkModel; path, dt = 0.02, events = [(2.0, TripLine(:B1, :B2))],
                 duration = 20.0, title = …, ylims_f = nothing, ylims_δ = nothing) -> path

Build the *same* multi-machine window offscreen, drive it through a scripted event
timeline flat out, and save a PNG to `path`.

This is how the window is verified from a session with no screen, and what turns
"the UI code compiles" into a picture of actual machines swinging against each
other. Events go through the `EventQueue` and the real loop — the identical path a
button click takes.

`events` is a vector of `(time, PerturbationEvent)`, not the M1 signature's
`(time, unit_id)`: this engine takes two kinds of event, and naming the event type
is how the caller says which. Mixing them in one timeline is the point —
`[(2.0, TripLine(:B1, :B2)), (6.0, TripGenerator(:G1))]` is a line trip the system
survives followed by the generator loss it does not.

Pass `ylims_f` / `ylims_δ` as `(lo, hi)` to pin the axes. Required whenever two
renders are meant to be *compared*: with per-run limits each picture fills its own
frame, so a swing three times larger draws the same shape as a small one.
"""
function smoke_render(net::NetworkModel;
                      path::AbstractString,
                      dt::Real = 0.02,
                      events::Vector{<:Tuple{Real,PerturbationEvent}} =
                          Tuple{Float64,PerturbationEvent}[],
                      duration::Real = 20.0,
                      window_seconds::Real = 0.0,
                      title::AbstractString = "GridSim — multi-machine swing",
                      ylims_f = nothing,
                      ylims_δ = nothing)
    GLMakie.activate!(; visible = false)
    # Default the rolling window to the whole run, so the saved frame shows the
    # entire event rather than its tail.
    ws = window_seconds > 0 ? Float64(window_seconds) : Float64(duration)
    win = _build_network_window(net; dt = dt, rtf = Inf, window_seconds = ws,
                                title = title, ylims_f = ylims_f, ylims_δ = ylims_δ)
    win.control.rtf[] = Inf     # flat out: no wall-clock pacing for a file render

    t_now = 0.0
    for (t_ev, ev) in sort(events; by = first)
        seg = Float64(t_ev) - t_now
        seg > 0 && run_realtime!(win.engine, win.state; control = win.control,
                                 queue = win.queue, duration = seg)
        push!(win.queue, ev)
        t_now = max(t_now, Float64(t_ev))
    end
    rest = Float64(duration) - t_now
    rest > 0 && run_realtime!(win.engine, win.state; control = win.control,
                              queue = win.queue, duration = rest)

    win.refresh!(; force = true)
    mkpath(dirname(path))
    save(path, win.fig)
    return path
end
