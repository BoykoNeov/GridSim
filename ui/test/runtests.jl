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
# M3 step 7's annotated panel. The engine's own logs are what the picture is
# asserted against, so the accessors come in here as well as into the window.
using GridSim: LoadShedStage, GenerationRamp, shed_ladder, shed_log
# M4 step 3's playback overlay. The window only DISPLAYS what these return, so the
# tests compare against the core's own read rather than against a second copy of
# the arithmetic living here.
using GridSim: FrequencyResponseEngine, solve!, coi_model,
               divergence, system_frequency, tolerance_band

GLMakie.activate!(visible = false)

const BUILD = GridSimUI._build_window
const NBUILD = GridSimUI._build_network_window

# Fire a widget's handler exactly as a click does.
click!(b) = (b.clicks[] = b.clicks[] + 1)

# ---- M3 step 7's fixture: a ladder walked PART of the way down ------------
#
# Four stages armed, three reachable, one not. Both halves matter — a fixture
# where everything fires cannot tell "marks what fired" from "marks what was
# armed", which is the shape of tripwire this milestone has needed five times.
# Top level rather than inside the testset because `const` is not a thing a local
# scope has, and because two testsets share it.
const SHED_DT = 0.02
const SHED_STAGES = [LoadShedStage(49.8, 0.01; label = :s_49_8),
                     LoadShedStage(49.6, 0.01; label = :s_49_6),
                     LoadShedStage(49.4, 0.01; label = :s_49_4),
                     LoadShedStage(49.2, 0.01; label = :s_49_2)]
const SHED_RAMP = GenerationRamp(-0.1, 0.0, 2.0)   # −10 MW over 2 s, on a 100 MVA base

function shed_window(; kwargs...)
    win = NBUILD(two_machine_system(); dt = SHED_DT, rtf = Inf,
                 window_seconds = 20.0,
                 shed = [:G1 => SHED_STAGES], ramp = [:G1 => SHED_RAMP],
                 kwargs...)
    run_realtime!(win.engine, win.state; control = win.control,
                  queue = win.queue, duration = 12.0)
    win.refresh!(; force = true)
    return win
end


# ---- M4 step 3's fixtures: the playback window over a solved pair ---------
#
# Two scenarios, and the CONTRAST between them is the point (see the "biggest gap"
# testset). The line trip is what `playback` ships: the swing tier rings, the
# aggregate tier is handed nothing at all, and the gap is the residual swing
# content. The generator trip is the run both tiers accept, whose far larger gap
# is a settling-level difference and NOT the lesson.
const PBUILD = GridSimUI._build_playback_window
const PWIN = GridSimUI._playback_window

pb_line() = PWIN(three_machine_ring(); horizon = 20.0, perturbations = nothing,
                 aggregate_perturbations = nothing, saveat = 0.02,
                 reltol = 1e-3, abstol = 1e-6)
pb_gen() = PWIN(three_machine_ring(); horizon = 60.0,
                perturbations = [1.0 => TripGenerator(:G1)],
                aggregate_perturbations = nothing, saveat = 0.02,
                reltol = 1e-3, abstol = 1e-6)

# "Is this Label in the figure?" — the read-out column is a nested `GridLayout`, so
# a Label there is not in `fig.layout.content` directly. Asserting against the
# layout rather than against an observable is the difference between checking the
# picture and checking the log (M3 step 7).
function in_layout(gl, obj)
    for c in gl.content
        c.content === obj && return true
        c.content isa GridLayout && in_layout(c.content, obj) && return true
    end
    return false
end

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

    @testset "the picture takes every published state, not every repaint" begin
        # M1 pins this through its nadir read-out: the deepest point of a dip almost
        # never coincides with a ~30 fps repaint, so anything sized from the sampled
        # state clips the very feature the window exists to show.
        #
        # THE AGGREGATE CANNOT CARRY THAT CLAIM IN THIS TIER, which is why this test
        # is shaped differently rather than copied. With no governors, a generator
        # trip declines monotonically — its nadir IS the final sample, so an
        # equality test would pass even for a read-out sampled at repaint time and
        # would prove nothing. And a line trip, which does recover, moves the COI by
        # 9.8 µHz (measured on this ring): three orders below anything the read-out
        # displays. So the claim is pinned where it does bite — the trace buffers.
        net = three_machine_ring()
        win = NBUILD(net; window_seconds = 20.0, rtf = Inf, dt = 0.02)
        # Count publications independently of the window, so the assertion is the
        # claim itself rather than an arithmetic guess at how many steps the loop
        # will take (it takes one more than `duration/dt` often enough — the sim
        # clock accumulates in floating point).
        published = Ref(0)
        on(_ -> published[] += 1, win.state)
        push!(win.queue, TripLine(:B1, :B2))
        run_realtime!(win.engine, win.state; control = win.control,
                      queue = win.queue, duration = 12.0)
        win.refresh!(; force = true)

        # Every published state is in the buffer, plus the seed point from build.
        # A run this fast repaints a couple of times at most, so a buffer filled on
        # the repaint path instead of the state path would hold single digits — the
        # count below is ~600.
        pts = win.traces.angle[1].points[]
        @test published[] > 500                         # the run really was long
        @test length(pts) == published[] + 1

        # ...and it holds an interior peak that no repaint sampled: the line trip
        # swings the angle out and rings back down, so the largest excursion is in
        # the middle of the run, not at either end.
        y = [abs(p[2]) for p in pts]
        @test maximum(y) > 1.2 * y[end]
        @test argmax(y) > 1 && argmax(y) < length(y)
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

    # ---- M3 step 7: the shed-annotated panel (report Fig 3-67) -------------

    @testset "the panel marks the ladder's root-found instants, not sampled ones" begin
        win = shed_window()
        @test length(win.shed_panels) == 1
        panel = win.shed_panels[1]
        @test panel.machine === :G1
        # Every ARMED stage gets a threshold line, fired or not.
        @test panel.thresholds == [st.threshold_hz for st in SHED_STAGES]

        log = shed_log(shed_ladder(win.engine, :G1))
        # Positive control: the fixture must actually walk part of the ladder, or
        # every assertion below holds vacuously against an empty marker set.
        @test 0 < length(log.t) < length(SHED_STAGES)

        pts = panel.fired[]
        @test length(pts) == length(log.t)
        # The claim worth pinning is the COORDINATES, not the count: each marker is
        # the log's own instant and the log's own threshold, to the bit. Sampling
        # the plotted trace instead would land within `dt` of these and pass a
        # count-only test.
        @test all(k -> pts[k][1] == Float32(log.t[k]), eachindex(log.t))
        @test all(k -> pts[k][2] == Float32(log.threshold_hz[k]), eachindex(log.t))
        # PRECONDITION, not a picture check: the log's own instants must lie off
        # the `dt` grid, or the two assertions above could not tell an exact marker
        # from a sampled one and would pass either way.
        @test any(t -> abs(t / SHED_DT - round(t / SHED_DT)) > 1e-6, log.t)
        # ...and the same claim about the PICTURE, which is what the reader sees.
        # Loose in `dt` units because a `Point2f` is Float32 — the gap being caught
        # is a whole grid step, not a rounding one.
        @test any(k -> (u = pts[k][1] / Float32(SHED_DT);
                        abs(u - round(u)) > 1.0f-3), eachindex(pts))

        # The written list is the same log, in MW at the seam and nowhere else.
        @test occursin(String(log.label[1]), win.shed_text[])
        @test occursin("−1 MW", win.shed_text[])        # 0.01 pu on a 100 MVA base
        # A shed is not an injected event, so the OTHER log stays empty. The two
        # are drawn in one panel and never merged.
        @test n_events(win.engine) == 0
        @test win.event_text[] == "(none yet)"
    end

    @testset "an unarmed model grows no phantom thresholds" begin
        # The failure this catches: hlines driven by the stage table rather than by
        # what is armed would put twelve Iberian thresholds across every window.
        win = NBUILD(three_machine_ring(); window_seconds = 10.0)
        @test isempty(win.shed_panels)
        @test win.shed_text[] == "(none yet)"
    end

    @testset "show_coi = false drops the aggregate from the plot AND the read-out" begin
        # On a two-area model the inertia-weighted mean is not a frequency (D5), and
        # suppressing only the line would move that number to the top of the column
        # where it reads as the answer.
        on_ = shed_window()
        @test occursin("f_COI", on_.readout[])
        @test !occursin("no aggregate", on_.readout[])

        off = shed_window(; show_coi = false)
        @test !occursin("f_COI", off.readout[])
        @test !occursin("nadir", off.readout[])
        @test occursin("no aggregate", off.readout[])
        # Everything else the read-out carries is unchanged — this is a suppression,
        # not a second read-out that can drift from the first.
        @test occursin("max |δ−COI|", off.readout[])
        @test occursin("H_sys", off.readout[])
    end

    @testset "smoke_render carries the armed mechanisms into the file" begin
        dir = mktempdir()
        path = joinpath(dir, "fig367.png")
        out = smoke_render(two_machine_system(); path = path, dt = SHED_DT,
                           duration = 12.0, show_coi = false,
                           shed = [:G1 => SHED_STAGES],
                           ramp = [:G1 => SHED_RAMP])
        @test out == path
        @test filesize(path) > 10_000
    end

    # ---- M4 step 3: the playback window ------------------------------------
    #
    # A different window from the two above, and tested differently for the same
    # reason it is different: nothing here is running. There is no queue to push
    # into and no loop to drive, so the "click a button, run the loop, assert what
    # landed" shape does not apply. What replaces it is exactness — every number the
    # window shows is a recorded sample verbatim, so the checks are `===` rather
    # than `atol`, and a tolerance-based check would pass against the off-by-one
    # index that is the actual bug available here.

    @testset "the playback window is built over solved series and cannot run" begin
        win = pb_line()
        # The four pieces of real-time machinery, all absent. Not an omission: each
        # exists to manage a run in progress, and this window's run finished before
        # the figure existed. Their absence is what makes "render state is not
        # simulation state" structural here — the window cannot reach an engine.
        @test !haskey(win, :control)
        @test !haskey(win, :queue)
        @test !haskey(win, :engine)
        @test !haskey(win, :refresh!)
        # ...and in particular there is exactly ONE control, the time cursor. A band
        # slider would let a reader scrub, look at the gap, and then pick the band
        # that puts the departure where they expected it, which is precisely the
        # discipline M4 step 2 made `band` a required keyword to protect.
        @test keys(win.widgets) == (:time,)
    end

    @testset "two series on different grids are refused, never quietly resampled" begin
        # The refusal lives in the core (`analysis/postprocess.jl`) and this asserts
        # the window inherits it at BUILD time rather than drawing two mismatched
        # traces on one axis. Straight-line resampling was measured at 33.7× the
        # agreement band (M4 step 2), so a silently interpolated overlay would put
        # that error straight into the quantity the window exists to display.
        sa = (; t = [0.0, 0.5, 1.0], f_coi = [50.0, 49.9, 49.8])
        sb = (; t = [0.0, 0.6, 1.0], f = [50.0, 49.9, 49.8])
        @test_throws ArgumentError PBUILD(sa, sb; band = 1e-3, reltol = 1e-3)
        msg = try
            PBUILD(sa, sb; band = 1e-3, reltol = 1e-3)
            "NO ERROR THROWN"
        catch e
            e isa ArgumentError ? e.msg : "NOT-ArgumentError: $(typeof(e))"
        end
        @test occursin("different grids", msg)
        @test occursin("nothing here resamples", msg)
    end

    @testset "the cursor is exact, and the drawn line is what says so" begin
        win = pb_line()
        i = 314
        set_close_to!(win.widgets.time, i)
        @test win.cursor[].i == i
        # `===` on purpose. Nothing here is interpolated, so exactness is available;
        # an `atol` check passes against an off-by-one index, which is the bug this
        # window can actually have.
        @test win.cursor[].t === win.t[i]
        @test win.cursor[].f_swing === win.swing.f_coi[i]
        @test win.cursor[].f_agg === win.agg.f[i]
        @test win.cursor[].gap === abs(win.swing.f_coi[i] - win.agg.f[i])
        # ...and the same claim about the PICTURE. `cursor` is what the read-out
        # formats; these two are the vertical lines a reader actually sees, asserted
        # against their own plotted argument rather than against the observable that
        # feeds them.
        @test win.cursor_lines.frequency[1][] == [win.t[i]]
        @test win.cursor_lines.gap[1][] == [win.t[i]]

        # ANTI-VACUITY: every assertion above would also hold for a cursor that
        # never moves. Move it.
        before = win.readout[]
        set_close_to!(win.widgets.time, i + 40)
        @test win.readout[] != before
        @test win.cursor[].t === win.t[i + 40]
        @test win.cursor_lines.frequency[1][] == [win.t[i + 40]]
    end

    @testset "the plotted gap and the written summary are one arithmetic" begin
        # The picture and the read-out must not be able to disagree about where the
        # largest disagreement is. Same expression, so this is an equality to the
        # bit and not a tolerance.
        win = pb_line()
        @test length(win.gap) == length(win.t)
        @test maximum(win.gap) === win.read.max
        @test win.t[argmax(win.gap)] === win.read.t_max
        @test win.read.n == length(win.t)
    end

    @testset "the band is derived from the solve and shown with its derivation" begin
        win = pb_line()
        @test win.band === tolerance_band(system_frequency(win.swing); reltol = 1e-3)
        # A band whose provenance is not on the screen is a magic number, and
        # `t_depart` is only an answer relative to it.
        @test occursin("3 · reltol · excursion", win.summary_label.text[])
        @test occursin("1e-03", win.summary_label.text[])
        @test in_layout(win.fig.layout, win.summary_label)
        @test in_layout(win.fig.layout, win.readout_label)
        # CONTROL FOR THE HELPER: every "is it in the picture" check above is
        # worthless if `in_layout` cannot say no. A Label built into a different
        # figure is exactly the state the mutation test produces.
        @test !in_layout(win.fig.layout, Label(Figure()[1, 1], "elsewhere"))
    end

    @testset "the shipped scenario is the one whose gap IS the swing content" begin
        # The line trip opens one side of the ring. The swing tier rings; the
        # aggregate view has no branches, so it is handed nothing at all and stays
        # at exactly nominal — which makes the whole gap the residual inter-machine
        # swing content, the one lesson SPEC §7.6 lets this pair claim.
        win = pb_line()
        @test all(==(50.0), win.agg.f)            # not "close to": it saw no event
        @test win.read.max > 100 * win.band       # measured 333× at this tolerance
        # Nothing departs before anything happens, and the departure is prompt.
        @test win.read.t_depart > 1.0
        @test win.read.t_depart < 1.1
        # ...and it really is a swing, on two independent signatures: the rotors
        # pull apart, and the gap decays away instead of settling somewhere new.
        d = win.swing.δ_G1 .- win.swing.δ_G2
        @test maximum(abs.(d .- d[1])) > 0.1      # measured ~0.28 rad
        @test maximum(win.gap[(end - 50):end]) < 0.3 * win.read.max
    end

    @testset "the two tiers did not get the same events, and the picture says so" begin
        # The asymmetry IS the fidelity boundary here, so an unlabelled event list
        # would let a reader take "trip line B3–B1" as something both curves
        # responded to and read the whole gap as a modelling difference.
        win = pb_line()
        @test win.asymmetric
        @test isempty(win.aggregate_times)
        @test length(win.events) == 1
        @test occursin("DID NOT GET THE SAME ONES", win.event_label.text[])
        @test occursin("[swing tier only]", win.event_label.text[])
        @test occursin("trip line B3–B1", win.event_label.text[])
        @test in_layout(win.fig.layout, win.event_label)

        # ANTI-VACUITY: a scenario both tiers DO receive must not be marked. Without
        # this, "the picture flags an asymmetry" cannot be told from "the picture
        # always flags one", which is the same shape of vacuity M3 caught five times.
        g = pb_gen()
        @test !g.asymmetric
        @test g.aggregate_times == [1.0]
        @test !occursin("swing tier only", g.event_label.text[])
        @test occursin("both tiers", g.event_label.text[])
    end

    @testset "the biggest gap this pair can draw is the one that is NOT the lesson" begin
        # THE FINDING OF THIS STEP, asserted rather than written down. The first
        # render of this window shipped the generator trip, whose gap reaches 0.857 Hz
        # — by far the largest number the window has ever shown, and V4c derived it as
        # the aggregate keeping the tripped machine's damping. It is bookkeeping, not
        # a swing, and a window whose headline number needs a footnote saying "this
        # is not the thing" is the failure this repo keeps catching.
        line, gen = pb_line(), pb_gen()
        @test gen.read.max > 100 * line.read.max          # 0.857 Hz against 1.08e-3
        # It arrives and STAYS: a settling-level difference, not a decaying swing.
        @test gen.gap[end] > 0.99 * gen.read.max
        # Where the shipped scenario's gap decays away, as a swing does.
        @test maximum(line.gap[(end - 50):end]) < 0.3 * line.read.max
    end

    @testset "the caption is in the picture and states what the pair cannot show" begin
        # Read the LABEL, not an observable the figure might not contain — M3 step 7
        # caught exactly one check reading the log where it should have read the
        # picture, and a caption is the easiest place to repeat it.
        win = pb_line()
        @test in_layout(win.fig.layout, win.caption)
        txt = win.caption.text[]
        @test txt == win.caption_text
        @test occursin("inter-machine swings", txt)
        @test occursin("NOT voltage coupling", txt)
        @test occursin("NOT inverter (IBR)", txt)
        @test occursin("not by itself evidence of a swing", txt)
        @test occursin("D5", txt)
    end

    @testset "the cursor snaps to a recorded sample, never between two" begin
        # The slider indexes samples precisely so no displayed number is a value
        # nobody computed. `_cursor_to_time!` is the only time-addressed entry, and
        # it rounds to a sample rather than interpolating to the time asked for.
        win = pb_line()
        i = GridSimUI._cursor_to_time!(win, 1.4749)
        @test win.cursor[].t === win.t[i]
        @test abs(win.t[i] - 1.4749) <= 0.01 + 1e-9      # nearest on a 0.02 s grid
        @test GridSimUI._cursor_to_time!(win, -5.0) == firstindex(win.t)
        @test GridSimUI._cursor_to_time!(win, 1.0e6) == lastindex(win.t)
        # ...and the placement rule `playback_render` uses, pinned here because the
        # render discards its window: the saved frame's cursor sits at the largest
        # disagreement, which is the only instant worth a frame with no reader.
        set_close_to!(win.widgets.time, argmax(win.gap))
        @test win.cursor[].t === win.read.t_max
    end

    @testset "the read says identical when it is handed one run twice" begin
        # ANTI-VACUITY for the whole overlay: everything above measures a gap, and
        # none of it distinguishes "measured a real gap" from "always reports one".
        win = pb_line()
        same = PBUILD(win.swing, (; t = win.swing.t, f = win.swing.f_coi);
                      band = win.band, reltol = 1e-3)
        @test all(==(0.0), same.gap)
        @test same.read.max == 0.0
        @test isnan(same.read.t_depart)
        @test occursin("never", same.summary_label.text[])
        @test !same.asymmetric || isempty(same.events)
    end

    @testset "an event the aggregate tier has no method for fails loudly" begin
        # Documents the design that was REJECTED. Filtering the aggregate's event
        # list automatically (keep what it has a `hasmethod` for) reads well and is
        # wrong: a method missing BY MISTAKE would be silently reclassified as a
        # fidelity boundary, which is the one error this comparison exists to find.
        # Hand a line trip to both tiers and it is a `MethodError`, not a shrug.
        @test_throws MethodError PWIN(three_machine_ring(); horizon = 2.0,
            perturbations = [1.0 => TripLine(:B3, :B1)],
            aggregate_perturbations = [1.0 => TripLine(:B3, :B1)],
            saveat = 0.02, reltol = 1e-3, abstol = 1e-6)
    end

    @testset "one event list without the other is refused" begin
        # The two lists are stated together or neither is: a caller who names only
        # the aggregate's list has almost certainly not thought about the swing
        # tier's, and the default scenario is not a sensible partner for it.
        @test_throws ArgumentError playback_render(; path = tempname() * ".png",
            aggregate_perturbations = [1.0 => TripGenerator(:G1)])
    end

    @testset "playback_render writes a PNG of the same window" begin
        dir = mktempdir()
        path = joinpath(dir, "playback.png")
        out = playback_render(; path = path, horizon = 8.0)
        @test out == path
        @test isfile(path)
        @test filesize(path) > 10_000                   # a real rendered frame
    end

end
