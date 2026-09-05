# One look for the three windows, and one place it is decided.
#
# Before this file each window chose its own fonts, colours and widget shapes
# inline, and the three had drifted: the read-outs were `@sprintf`-aligned columns
# drawn in a proportional font (so the columns did not align), the buttons sat
# centred and narrow in a 300-px column, and the playback window's legend was
# placed inside the axis where the shipped generator-trip render has it lying on
# top of the data. Everything below is render state (docs/SPEC.md §3) and is
# applied by wrapping each builder in `with_theme(GRIDSIM_THEME)`, which is scoped:
# it never leaks into a caller's own Makie session.
#
# Two rules that are not cosmetic:
#
#   THE READ-OUT IS TWO LABELS, NOT ONE, AND THE VALUES REFRESH AT 10 HZ. Setting a
#   `Label`'s text re-runs Makie's glyph layout for the whole string — measured at
#   ~700 µs and ~480 KB per call for the seven-line network read-out, regardless of
#   `tellheight`/fixed sizes (M4 follow-up, 2026-09-05), and it was 85 % of a
#   repaint's allocation. The names never change, so they are a Label written
#   once; only the values column is rewritten, and only every `READOUT_INTERVAL`.
#   Numbers changing thirty times a second are unreadable anyway.
#
#   MONOSPACE FOR NUMBERS, ALWAYS FROM MAKIE'S OWN ASSETS. `@sprintf("%7.3f")`
#   only aligns in a fixed-width face, and a system font name would make the
#   picture depend on the machine. DejaVu Sans Mono ships inside Makie.

const MONO_FONT = joinpath(Makie.assetpath("fonts"), "DejaVuSansMono.ttf")

# How often the numeric read-out is rewritten. Independent of `REDRAW_INTERVAL`:
# the traces still take every published state and repaint at ~30 fps.
const READOUT_INTERVAL = 0.1

# Colours, named once so the three windows agree on what a swing tier, an
# aggregate, an event and a warning look like.
const C_AGGREGATE = RGBf(0.93, 0.45, 0.08)   # aggregate tier / RoCoF / dashed overlays
const C_SWING     = RGBf(0.12, 0.47, 0.85)   # network tier, and M1's own f(t)
const C_EVENT     = RGBf(0.25, 0.25, 0.25)
const C_WARN      = RGBf(0.72, 0.13, 0.13)
const C_INERTIA   = RGBf(0.18, 0.55, 0.34)
const C_CURSOR    = RGBf(0.13, 0.60, 0.40)
const C_MUTED     = RGBf(0.40, 0.40, 0.42)
const C_GRID      = RGBf(0.88, 0.89, 0.91)

const GRIDSIM_THEME = Theme(
    fontsize = 14,
    figure_padding = (14, 18, 12, 12),
    backgroundcolor = RGBf(0.985, 0.985, 0.99),
    Axis = (
        backgroundcolor = :white,
        titlesize = 17, titlealign = :left, titlegap = 8,
        xlabelsize = 14, ylabelsize = 14,
        xticklabelsize = 12, yticklabelsize = 12,
        xgridcolor = C_GRID, ygridcolor = C_GRID,
        xminorgridvisible = false, yminorgridvisible = false,
        rightspinevisible = false, topspinevisible = false,
        leftspinecolor = C_MUTED, bottomspinecolor = C_MUTED,
        xtickcolor = C_MUTED, ytickcolor = C_MUTED,
        spinewidth = 1.0,
    ),
    Legend = (
        framevisible = false, labelsize = 12, padding = (4, 4, 2, 2),
        patchsize = (22, 8), rowgap = 2,
    ),
    Button = (
        buttoncolor = RGBf(0.94, 0.95, 0.97),
        buttoncolor_hover = RGBf(0.86, 0.90, 0.97),
        buttoncolor_active = RGBf(0.78, 0.84, 0.95),
        strokecolor = RGBf(0.72, 0.75, 0.80), strokewidth = 1,
        cornerradius = 4, labelcolor = :gray10, fontsize = 13,
        # Fill the control column instead of sitting centred and narrow in it.
        width = Relative(1.0),
    ),
    Slider = (color_active = C_SWING, color_active_dimmed = RGBf(0.70, 0.80, 0.95)),
    Label = (fontsize = 14,),
)

"""
    themed(build) -> whatever `build` returns

Run a window builder under `GRIDSIM_THEME`. `with_theme` is scoped, so a caller
that builds a figure of their own afterwards gets Makie's default look back.
"""
themed(build) = with_theme(build, GRIDSIM_THEME)

"""
    readout_block!(gl, keys; values = Observable(""), fontsize = 15)
        -> (; values, keys_label, values_label)

Put a two-column numeric read-out into layout `gl`: a static column of `keys`
(one per line, written once) and a live column showing `values`. The caller
writes the values, one line per key, right-aligned by `@sprintf` widths — both
columns are monospace, so the rows line up. See the file header for why this is
two labels and not one. `values` may be handed in (a `lift` of a cursor, say) or
left to be created here.
"""
function readout_block!(gl, keys::AbstractString;
                        values::Observable{String} = Observable(""),
                        fontsize::Real = 15)
    # The key column sizes itself to its longest name (`tellwidth = true`); the
    # values start right after it, left-aligned, and line up among themselves by
    # their `@sprintf` widths — the same shape as the static summary blocks, so
    # a column of read-outs reads as one table rather than two.
    keys_label = Label(gl[1, 1], keys; halign = :left, valign = :top,
                       justification = :left, tellwidth = true, font = MONO_FONT,
                       fontsize = fontsize, color = C_MUTED)
    values_label = Label(gl[1, 2], values; halign = :left, valign = :top,
                         justification = :left, tellwidth = false, font = MONO_FONT,
                         fontsize = fontsize)
    colgap!(gl, 10)
    return (; values, keys_label, values_label)
end

"""
    readout_text(keys, values) -> String

The two columns of a `readout_block!` joined row by row — what the read-out
*says*, as one string a test or a caller can search. It is built from the same
two strings the labels draw, so it cannot disagree with the picture.
"""
function readout_text(keys::AbstractString, values::AbstractString)
    ks = split(keys, '\n'); vs = split(values, '\n')
    n = max(length(ks), length(vs))
    rows = (string(rpad(i <= length(ks) ? ks[i] : "", 12), " ",
                   i <= length(vs) ? vs[i] : "") for i in 1:n)
    return join(rows, '\n')
end

"""
    section_label!(cell, text)

A small-caps-style heading for a group of controls — the "trip a unit" /
"events" lines — so the control column reads as sections rather than as a stack
of equally weighted widgets.
"""
section_label!(cell, text::AbstractString) =
    Label(cell, uppercase(text); halign = :left, tellwidth = false, fontsize = 11,
          color = C_MUTED, font = :bold)
