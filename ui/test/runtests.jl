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

GLMakie.activate!(visible = false)

const BUILD = GridSimUI._build_window

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

    @testset "smoke_render writes a PNG of the same window" begin
        dir = mktempdir()
        path = joinpath(dir, "smoke.png")
        out = smoke_render(; path = path, trips = [(1.0, :G4)], duration = 6.0)
        @test out == path
        @test isfile(path)
        @test filesize(path) > 10_000                   # a real rendered frame, not a stub
    end

end
