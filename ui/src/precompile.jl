# Precompile workload: build every window offscreen once, at package precompile
# time, so a session does not pay for it at launch.
#
# MEASURED BEFORE THIS FILE EXISTED (2026-09-05, Julia 1.12.6, GLMakie 0.13.13):
# `using GridSimUI` 10.4 s, then the FIRST network `smoke_render` 76.5 s, the first
# aggregate one 23.9 s, the first `playback_render` 4.9 s — about two minutes of
# compilation before a user saw the first multi-machine window. The engines step
# in ~1 µs; every second of that was Makie specialising on this package's plot
# and widget calls. Measured after: see `ui/README.md` ("Startup").
#
# Follows GLMakie's own `precompiles.jl` pattern: activate an invisible screen,
# do the work, then `closeall` and `Makie.cleanup_globals()` so no screen, font or
# task state is serialised into the cache. `__init__` does not run during
# precompilation, so the cleanup is mandatory rather than tidy.
#
# GUARDED. Precompilation needs an OpenGL context for the render half, which a
# headless CI runner may not have. Set `GRIDSIM_UI_PRECOMPILE=0` to skip the
# workload entirely; a failure inside it is caught and reported, never fatal —
# the package still loads, it just compiles at first use as before.
using PrecompileTools

@setup_workload begin
    if get(ENV, "GRIDSIM_UI_PRECOMPILE", "1") != "0"
        @compile_workload begin
            try
                GLMakie.activate!(; visible = false)
                tmp = tempname() * ".png"

                # M1 window: build, drive through the real loop, repaint, render.
                smoke_render(; path = tmp, duration = 2.0, trips = [(0.5, :G1)],
                             shed = [LoadShedStage(49.8, 0.02)])

                # Network window with everything armed: shed panel, ramp, both
                # trip kinds — the branches `_build_network_window` only takes
                # when a ladder is present are the ones worth compiling.
                stages = [LoadShedStage(49.8, 0.01; label = :s_49_8)]
                smoke_render(two_machine_system(); path = tmp, duration = 2.0,
                             shed = [:G1 => stages],
                             ramp = [:G1 => GenerationRamp(-0.1, 0.0, 1.0)],
                             events = Tuple{Float64,PerturbationEvent}[
                                 (0.5, TripLine(:B1, :B2))])
                smoke_render(three_machine_ring(); path = tmp, duration = 2.0,
                             events = Tuple{Float64,PerturbationEvent}[
                                 (0.5, TripGenerator(:G1))])

                # Playback overlay, default scenario, short horizon.
                playback_render(; path = tmp, horizon = 2.0)

                rm(tmp; force = true)
            catch err
                @warn "GridSimUI precompile workload skipped" exception = (err, catch_backtrace())
            finally
                try
                    GLMakie.closeall()
                catch
                end
                Makie.cleanup_globals()
            end
        end
    end
end
