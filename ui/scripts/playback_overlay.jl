# Regenerates the two playback-overlay figures checked into `docs/images/`
# (M4 step 3). Run from the repo root:
#
#     julia --project=ui ui/scripts/playback_overlay.jl
#
# TWO FIGURES, AND THE CONTRAST BETWEEN THEM IS THE POINT. They are the same
# window over the same model, differing only in the disturbance, and they say
# opposite things about how to read a gap:
#
#   line-trip — the shipped default. `TripLine(:B3, :B1)` opens one side of the
#   ring. The machines swing against each other and the centre-of-inertia
#   frequency rings by about 1 mHz, decaying away; the aggregate tier has no
#   branches, so it is handed nothing at all and sits at exactly 50 Hz. The whole
#   gap is the residual inter-machine swing content — the one lesson of the three
#   SPEC §7.6 names that this pair can support.
#
#   generator-trip — the run BOTH tiers accept, and a warning. Its gap reaches
#   0.857 Hz, roughly 800× the first figure's, and it is NOT the lesson: V4c
#   derived it as the aggregate keeping the tripped machine's damping in its
#   denominator, so it arrives and stays rather than decaying. It is bookkeeping
#   wearing the largest number on the screen.
#
# Checked in as a pair for that reason. A doc that claims the two tiers part
# company over swings, illustrated by the figure where they part company over
# something else, is exactly the promotion this milestone keeps catching.

using GLMakie
using GridSimUI
using GridSim: TripGenerator

const OUT = joinpath(@__DIR__, "..", "..", "docs", "images")

GLMakie.activate!(visible = false)

line = playback_render(; path = joinpath(OUT, "fig-m4-playback-line-trip.png"),
                       horizon = 20.0)
println("wrote ", line, "  (", filesize(line), " bytes)")

gen = playback_render(; path = joinpath(OUT, "fig-m4-playback-generator-trip.png"),
                      perturbations = [1.0 => TripGenerator(:G1)], horizon = 60.0)
println("wrote ", gen, "  (", filesize(gen), " bytes)")
