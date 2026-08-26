# Report Figure 3-67, from this repo's own two-area run. Milestone 3 step 7.
#
#   julia --project=ui ui/scripts/figure_3_67.jl
#
# WHAT THIS DRAWS. ENTSO-E's Fig 3-67 (p.178) is the Iberian frequency trace with
# the defence plan's thresholds across it and a mark wherever a stage actually
# fired. This is that figure, produced by the model instead of by the event: the
# frequency panel of the ordinary multi-machine window, opened on the two-area
# Iberian case with its cascade ramp and its defence plan armed.
#
# WHICH RUN. Exactly the nominal cell of `scripts/iberia_two_area.jl`'s sweep, with
# `shed = true` — same model, same ramp, same twelve stages, same `dt = 0.01`. The
# only thing this file adds is the window. It is ONE CELL of a grid, with all the
# caveats section 3 of that script prints about single cells; the sweep is the
# result, and this is a picture of one point in it.
#
# WHAT THE PICTURE SHOWS, said here so it cannot be read as more than it is:
#
#   THE DEFENCE PLAN ARRESTS THE FALL AND DOES NOT SAVE THE TIE. Six of twelve
#   stages fire, 5,072 MW of the armed 15,532 MW, and the Iberian minimum comes up
#   from 46.09 Hz unarmed to 49.14 Hz. The peninsula still loses synchronism all
#   the same — the angle panel runs away, and the frame ends 25.2 rad, four pole
#   slips, deep. Shedding and separation are separate outcomes on this model, and
#   the figure is one of them being prevented while the other is not.
#
#   THE TIE IS UNPROTECTED IN THIS CELL, because the sweep runs it that way: slip
#   is detected afterwards, by post-processing `|δ_IB − δ_CE| > π`, and no relay
#   opens anything. The angle passes 90° at 3.13 s and 180° at 4.26 s — past 180°
#   the synchronising power has reversed — so the oscillation from ~4.3 s on is a
#   tie SLIPPING, not a system separated. The real one opened at 12:33:21.54.
#   `render(; relay = true)` arms M3 step 4's out-of-step relay instead, which
#   opens the tie at 3.72 s and leaves two islands; that is the closer picture of
#   the event and it is NOT the run the sweep reports, which is why it is not the
#   one checked in.
#
#   THERE IS NO AGGREGATE FREQUENCY LINE. The window's centre-of-inertia overlay
#   is off (`show_coi = false`): an inertia-weighted mean over Iberia and
#   Continental Europe is not a frequency once the two are separating, which is
#   decision D5 and is the entire reason the defence plan binds to `:IB` and not to
#   `f_coi`. The LOWER panel still measures angles against that same weighted mean,
#   and that is a different use and still a valid one — an absolute rotor angle is
#   gauge-arbitrary and unplottable, while a difference from any common reference
#   is not. The suppression is of the aggregate as a *frequency*, not of the
#   aggregate as an angle datum.
#
#   IT ENDS AT 10 s, not at the sweep's 20 s. The same run, drawn to half way; the
#   whole story — the 4.1 s ramp, six sheds between 3.23 s and 4.76 s, the slip at
#   4.26 s and four pole slips by 10 s — is inside it, and at 20 s every annotation
#   is squeezed into the left fifth of the frame.
#
# Fidelity boundary: docs/plans/entsoe-iberia-reproduction.md §7.6. Voltage is
# constant behind a reactance here, so the final collapse to blackout is out of
# scope at any point of this figure.

using GridSimUI
using GridSim: LoadShedStage, GenerationRamp, OutOfStepTrip

# The model, the cascade and the defence plan live in exactly ONE place — the
# script that derives them and prints their provenance. Including it defines them
# without running its sweep (`main` is guarded on `PROGRAM_FILE`).
const CORE_SCRIPT = normpath(joinpath(@__DIR__, "..", "..", "scripts",
                                      "iberia_two_area.jl"))
include(CORE_SCRIPT)

const OUT = normpath(joinpath(@__DIR__, "..", "..", "docs", "images",
                              "fig-3-67-two-area.png"))

# Ten seconds of the sweep's twenty; see the header. `dt` is the sweep's.
const SPAN = 10.0

# Pinned, not expand-only, for two reasons. The armed and unarmed renders of this
# figure are meant to be COMPARED, and with per-run limits each would fill its own
# frame — the trap `smoke_render`'s docstring names for swing amplitude. And the
# frequency box is pinned to reach 47.7 Hz, BELOW anything this run touches, so
# that all twelve armed thresholds are in frame: the six that never fired are the
# figure's other half, and an expand-only box would crop them off exactly because
# nothing happened there.
const YLIMS_F = (47.7, 50.35)
# Wide enough for both renders' runaway (|δ−COI| reaches 22.0 rad unprotected and
# 24.8 rad with the relay armed), so neither picture clips the divergence it exists
# to show. Asymmetric because the split is: Iberia carries 13 % of the pair's
# inertia, so it does 87 % of the moving away from their weighted mean.
const YLIMS_D = (-27.0, 9.0)

"""
    render(; relay = false, path = OUT, span = SPAN) -> path

Render the annotated frequency panel offscreen and save it.

`relay = false` is the sweep's own configuration and the one checked in.
`relay = true` arms step 4's out-of-step protection on the tie at 2π/3, which
opens it at the root-found instant and leaves two islands — a different run, and
the header says why it is not the default.
"""
function render(; relay::Bool = false, path::AbstractString = OUT,
                  span::Real = SPAN)
    net  = two_area_model()
    # `cascade_ramp`, not the expression rewritten — the header's claim that this
    # is the sweep's own cell then holds by construction rather than by two copies
    # happening to agree. Same reason the model and the stages are not copied here.
    ramp = cascade_ramp()
    oos  = relay ? [(:ES, :FR) => OutOfStepTrip(2π / 3)] :
                   Pair{Tuple{Symbol,Symbol},OutOfStepTrip}[]
    title = string("Iberia, 28 Apr 2025 — two-area model, defence plan armed",
                   relay ? "  (tie relay armed)" : "  (tie unprotected — it slips)")
    return smoke_render(net; path = path, dt = DT, duration = span,
                        shed = [:IB => defence_plan()],
                        ramp = [:IB => ramp],
                        out_of_step = oos,
                        show_coi = false,
                        ylims_f = YLIMS_F, ylims_δ = YLIMS_D,
                        title = title)
end

function main()
    out = render()
    println("wrote ", out, "  (", filesize(out) ÷ 1024, " kB)")
    return nothing
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
