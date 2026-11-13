# Regenerate the figures the docs show, in one go, from the windows themselves:
#
#     julia --project=ui ui/scripts/figures.jl                 # into docs/images/
#     julia --project=ui ui/scripts/figures.jl W:\temp\claude\figs   # somewhere else, to look first
#
# Every figure is a frame of the window a user opens (`*_render` builds the same figure
# `launch`/`playback`/… displays) — never a separate plotting path. Until this script
# existed each figure was rendered by hand at the step that changed its window, so a change
# to the shared look (`src/theme.jl`, `src/grid_map.jl`) had no single way to refresh them
# all. After ANY change to those two files: run this into a scratch folder, LOOK at every
# picture, then run it for real.
#
# Not regenerated here, on purpose: `fig-editor-inverters.png` and
# `fig-m5s8-voltage-frozen-control.png` are one-off fixtures built by hand at their steps
# (M7 step 8, M5 step 8); `fig-3-67-two-area.png` and the two playback figures have their
# own scripts beside this one, which this script runs.

using GridSimUI, GridSim

const OUT = isempty(ARGS) ? normpath(joinpath(@__DIR__, "..", "..", "docs", "images")) : ARGS[1]
mkpath(OUT)
fig(name) = joinpath(OUT, name)

function render(name, f)
    t = @elapsed f(fig(name))
    println(rpad(name, 44), round(t; digits = 1), " s")
end

render("fig-editor-three-machine-ring.png", p -> editor_render(; path = p))
render("fig-editor-solved.png",
       p -> editor_render(; path = p, net = load_bus_system(), solve = true,
                          select = (:branch, :L23)))
render("fig-m5s8-voltage-detailed.png", p -> voltage_playback_render(; path = p))
render("fig-m7-low-inertia.png",
       p -> low_inertia_render(; path = p, topology = :chain, event = :G4, n = 1))
render("fig-m9-frequency-screen.png", p -> frequency_screen_render(; path = p))
render("fig-m10-double-outages.png",
       p -> double_outages_render(; path = p, view = :def, pair = (:L14, :L45)))
render("fig-m11-network-dispatch.png", p -> network_dispatch_render(; path = p))

# The two scripts that own their figures write into docs/images/ themselves; run them
# only when that is where this run is writing.
if isempty(ARGS)
    include(joinpath(@__DIR__, "playback_overlay.jl"))
    # `figure_3_67.jl` draws only when it is the program being run, so it gets a process
    # of its own (same project, same below-normal priority as this one).
    run(`$(Base.julia_cmd()) --project=$(dirname(@__DIR__)) $(joinpath(@__DIR__, "figure_3_67.jl"))`)
end
