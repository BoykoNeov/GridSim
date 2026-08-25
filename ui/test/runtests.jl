# Tests for the GLMakie window (docs/SPEC.md §7.7).
#
# Everything here runs **offscreen** (`GLMakie.activate!(visible = false)`), which
# is what makes the window checkable at all in a session with no screen — and in
# CI. The controls are driven the way a user drives them: setting `b.clicks[]`
# runs the very handler a real click runs, so the click → `EventQueue` → `inject!`
# path is exercised end to end rather than simulated.
#
# What is deliberately NOT re-tested here: the physics and the pacing. Both are
# asserted in the core suite (`../../test/runtests.jl`), and duplicating them
# would only add a second place to update.

using Test
using GLMakie
using GridSimUI
using GridSim: example_system, current_state, state_series, system_inertia,
               is_online, run_realtime!, TripGenerator
using GridSim: three_machine_ring, two_machine_system, SwingEngine, TripLine,
               StepLoad, PerturbationEvent, machine_ids, event_log, n_events,
               inject!, init!

GLMakie.activate!(visible = false)

const BUILD = GridSimUI._build_window
const NBUILD = GridSimUI._build_network_window

# Fire a widget's handler exactly as a click does.
click!(b) = (b.clicks[] = b.clicks[] + 1)

@testset "GridSimUI" begin

    @testset "RollingTrace drops the oldest point at capacity" begin
        tr = GridSimUI.RollingTrace(4)
        for i in 1:10
            push!(tr, float(i), float(-i))
        end
        v = tr.points[]
        @test length(v) == 4                     # bounded, unlike the engine's own vectors
        @test v[1][1] ≈ 7.0                      # points 1–6 rolled off the front
        @test v[end][1] ≈ 10.0
    end

    @testset "a freshly built window sits at the undisturbed origin" begin
        sys = example_system()
        win = BUILD(sys; window_seconds = 10.0)
        s = win.state[]
        @test s.t == 0.0
        @test s.f ≈ sys.f0
        @test s.RoCoF ≈ 0.0
        @test all(is_online(win.engine, u.id) for u in sys.units)
        @test isempty(win.queue)
        # Nothing has been started: no window shown, no task spawned.
        @test win.control.running[]
        @test !win.control.paused[]
    end

    @testset "a trip button click queues the event; the loop applies it" begin
        sys = example_system()
        win = BUILD(sys; window_seconds = 12.0, rtf = Inf)
        id, btn = win.widgets.unit_buttons[1]
        @test id === :G1

        H_before = system_inertia(win.engine)
        click!(btn)
        # The click only *queues* — nothing is injected mid-integration.
        @test length(win.queue) == 1
        @test is_online(win.engine, :G1)

        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 10.0)

        @test !is_online(win.engine, :G1)               # AC #3: the trip landed
        @test system_inertia(win.engine) < H_before     # AC #6: inertia visibly drops
        @test win.state[].f < sys.f0 - 0.5              # and frequency dipped
        @test occursin("G1", btn.label[]) && occursin("offline", btn.label[])
    end

    @testset "the displayed nadir is the true minimum, not a sampled one" begin
        # The window repaints at ~30 fps while the loop publishes far faster, so the
        # deepest point of the dip almost never coincides with a repaint. The readout
        # must still show it — that is why the nadir is accumulated in the state
        # handler rather than read off whatever state a repaint happens to sample.
        sys = example_system()
        win = BUILD(sys; window_seconds = 12.0, rtf = Inf)
        click!(win.widgets.unit_buttons[1][2])
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 10.0)
        win.refresh!(; force = true)

        true_nadir = minimum(state_series(win.engine).f)
        m = match(r"nadir\s+([0-9.]+) Hz", win.readout[])
        @test m !== nothing
        @test parse(Float64, m.captures[1]) ≈ true_nadir atol = 5e-4
        @test true_nadir < sys.f0 - 1.0                 # the dip is a real one
    end

    @testset "pause, stop and the speed slider are wired to the control block" begin
        win = BUILD(example_system(); window_seconds = 10.0)

        click!(win.widgets.pause)
        @test win.control.paused[]                      # loop freezes simulation time
        @test win.widgets.pause.label[] == "resume"
        click!(win.widgets.pause)
        @test !win.control.paused[]
        @test win.widgets.pause.label[] == "pause"

        set_close_to!(win.widgets.speed, 3.0)
        @test win.control.rtf[] ≈ 3.0                   # slider moves speed mid-run

        click!(win.widgets.stop)
        @test !win.control.running[]                    # loop returns after this step
    end

    @testset "pinned y-limits stay pinned; unpinned ones expand to the dip" begin
        # Expand-only limits are right for a live window but wrong for *comparing*
        # two runs: each picture fills its own frame, so a dip three times deeper
        # draws the same shape as a shallow one. `ylims_f`/`ylims_rocof` pin both
        # runs to one scale — this asserts the pin actually holds against a dip
        # that would otherwise force the box open.
        ylo_of(ax) = ax.finallimits[].origin[2]

        sys = example_system()
        pinned = BUILD(sys; window_seconds = 12.0, rtf = Inf,
                       ylims_f = (47.9, 50.35), ylims_rocof = (-4.0, 2.0))
        click!(pinned.widgets.unit_buttons[1][2])          # G1: the deep, saturating trip
        run_realtime!(pinned.engine, pinned.state; control = pinned.control,
                      queue = pinned.queue, duration = 10.0)
        pinned.refresh!(; force = true)
        @test ylo_of(pinned.axes.frequency) ≈ 47.9 atol = 1e-3
        @test ylo_of(pinned.axes.rocof) ≈ -4.0 atol = 1e-3
        # The pin is only meaningful if the run really did go outside the default box.
        @test minimum(state_series(pinned.engine).f) < 47.9

        loose = BUILD(sys; window_seconds = 12.0, rtf = Inf)
        click!(loose.widgets.unit_buttons[1][2])
        run_realtime!(loose.engine, loose.state; control = loose.control,
                      queue = loose.queue, duration = 10.0)
        loose.refresh!(; force = true)
        # Unpinned, the same run must have pushed the box open past its f0 − 2.0 start.
        @test ylo_of(loose.axes.frequency) < sys.f0 - 2.0
    end

    @testset "smoke_render writes a PNG of the same window" begin
        dir = mktempdir()
        path = joinpath(dir, "smoke.png")
        out = smoke_render(; path = path, trips = [(1.0, :G4)], duration = 6.0)
        @test out == path
        @test isfile(path)
        @test filesize(path) > 10_000                   # a real rendered frame, not a stub
    end

    # --- M2 step 7: the multi-machine window ---------------------------------

    @testset "the model type picks the window, and with it the controls" begin
        # Step 7's second decision, asserted rather than described. The two engines
        # do not accept the same events — `TripLine` has no method on the aggregate
        # view (a SystemModel has no branches) and `StepLoad` has none on the swing
        # engine (a classical-tier load is a machine) — so the set of buttons is a
        # property of the engine, settled by dispatch on the model type.
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 10.0)
        @test win.engine isa SwingEngine
        @test length(win.widgets.machine_buttons) == length(net.machines)
        @test length(win.widgets.line_buttons) == length(net.branches)

        m1 = BUILD(example_system(); window_seconds = 10.0)
        @test !(m1.engine isa SwingEngine)
        @test !haskey(m1.widgets, :line_buttons)        # no lines to offer

        # The vocabulary really does diverge in both directions — this is what the
        # per-window control sets are protecting against.
        @test_throws MethodError inject!(m1.engine, TripLine(:B1, :B2))
        @test_throws MethodError inject!(win.engine, StepLoad(0.05))
    end

    @testset "a network window starts flat, at nominal, with everything in service" begin
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 10.0)
        s = win.state[]
        @test s.t == 0.0
        @test s.f_coi ≈ net.f0 atol = 1e-9
        @test all(m -> is_online(win.engine, m.id), net.machines)
        @test all(br -> is_online(win.engine, br.from, br.to), net.branches)
        @test isempty(win.queue)
        @test isempty(event_log(win.engine))
        @test win.event_text[] == "(none yet)"
    end

    @testset "both kinds of trip button queue their own event and land" begin
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 30.0, rtf = Inf)

        # A line button first: this is the event the aggregate window cannot offer.
        from, to, lbtn = win.widgets.line_buttons[1]
        click!(lbtn)
        @test length(win.queue) == 1                    # queued, not injected
        @test is_online(win.engine, from, to)
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 4.0)
        @test !is_online(win.engine, from, to)
        # The label is greyed on the RENDER path, which is throttled to ~30 fps —
        # and a flat-out run of a few seconds can finish inside a single frame
        # interval. Forcing a frame is what the live window does on its next tick.
        win.refresh!(; force = true)
        @test occursin("open", lbtn.label[])

        # ...and a machine button, which both windows have.
        H_before = system_inertia(win.engine)
        id, mbtn = win.widgets.machine_buttons[1]
        click!(mbtn)
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 6.0)
        @test !is_online(win.engine, id)
        @test system_inertia(win.engine) < H_before     # inertia visibly drops
        win.refresh!(; force = true)
        @test occursin("offline", mbtn.label[])
        @test win.state[].f_coi < net.f0 - 0.1          # and the system decelerates
    end

    @testset "the window shows which line opened and when — the traces cannot" begin
        # The point of the event log: play a run back and the channels say nothing
        # about a line trip. The markers and the event list are the only place that
        # information appears, and they come from the ENGINE's log, so a scripted
        # run marks the same instants a clicked one would.
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 30.0, rtf = Inf)
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 2.0)
        push!(win.queue, TripLine(:B1, :B2))
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 3.0)
        win.refresh!(; force = true)

        log = event_log(win.engine)
        @test length(log) == 1
        @test occursin("trip line B1–B2", win.event_text[])
        @test occursin("2.0", win.event_text[])         # the instant, not just the fact
        # Nothing in the recorded trajectory carries it.
        @test !any(n -> occursin("trip", String(n)),
                   propertynames(state_series(win.engine)))
    end

    @testset "a departed rotor is drawn but scales nothing" begin
        # The first render of this window put a survivor spread of 0.1 rad on an
        # axis 300 rad tall: a tripped machine's angle relative to the COI grows
        # without bound, and driving expand-only limits from every machine let the
        # dead one flatten every trace the panel exists to show.
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 30.0, rtf = Inf)
        click!(win.widgets.machine_buttons[1][2])       # trip G1
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 12.0)
        win.refresh!(; force = true)

        s = win.state[]
        rel = s.δ .- s.δ_coi
        @test abs(rel[1]) > 5                           # the tripped rotor is long gone
        # ...yet the angle axis is still sized for the survivors.
        lims = win.axes.angle.finallimits[]
        half = lims.widths[2] / 2
        @test half < 1.0
        @test half > maximum(abs, rel[2:3])             # and they are inside it
        # The read-out agrees: both machine-to-machine figures skip the dead rotor.
        m = match(r"max \|δ−COI\|\s+([0-9.]+) rad", win.readout[])
        @test m !== nothing
        @test parse(Float64, m.captures[1]) ≈ maximum(abs, rel[2:3]) atol = 1e-2
    end

    @testset "an all-offline system reads NaN and leaves the nadir finite" begin
        # `f_coi` is NaN once no machine is left to average — the engine's honest
        # answer. A NaN loses every comparison, which is what keeps the running
        # nadir and the axis box from being poisoned by it; the read-out shows the
        # NaN rather than a fabricated zero, because a blank or a 0.0 there would
        # read as a working system.
        net = two_machine_system()
        win = NBUILD(net; window_seconds = 20.0, rtf = Inf)
        for (_, b) in win.widgets.machine_buttons
            click!(b)
        end
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 5.0)
        win.refresh!(; force = true)

        @test isnan(win.state[].f_coi)
        @test occursin("NaN", win.readout[])
        m = match(r"nadir\s+([0-9.]+) Hz", win.readout[])
        @test m !== nothing && isfinite(parse(Float64, m.captures[1]))
        @test isfinite(win.axes.frequency.finallimits[].origin[2])
    end

    @testset "the network window's pinned limits stay pinned" begin
        ylo_of(ax) = ax.finallimits[].origin[2]
        net = three_machine_ring()
        pinned = NBUILD(net; window_seconds = 20.0, rtf = Inf,
                        ylims_f = (46.0, 50.5), ylims_δ = (-0.4, 0.4))
        click!(pinned.widgets.machine_buttons[1][2])
        run_realtime!(pinned.engine, pinned.state; control = pinned.control,
                      queue = pinned.queue, duration = 12.0)
        pinned.refresh!(; force = true)
        @test ylo_of(pinned.axes.frequency) ≈ 46.0 atol = 1e-3
        @test ylo_of(pinned.axes.angle) ≈ -0.4 atol = 1e-3
        # Only meaningful because the run really did leave the default box.
        @test pinned.state[].f_coi < 49.0
    end

    @testset "smoke_render draws the same network window, both events in one run" begin
        dir = mktempdir()
        path = joinpath(dir, "network.png")
        out = smoke_render(three_machine_ring(); path = path,
                           events = Tuple{Float64,PerturbationEvent}[
                               (2.0, TripLine(:B1, :B2)),
                               (8.0, TripGenerator(:G1))],
                           duration = 16.0)
        @test out == path
        @test isfile(path)
        @test filesize(path) > 10_000                   # a real rendered frame
    end

end
