# The frequency-screen window (M9 step 7) — the report's section 4, drawn: for every
# generator outage of the two report grids, M8's line-and-voltage outcome beside the
# frequency verdict, and for the outage selected, the dynamic run the dip and the rate
# were read from.
#
# THE REPORT IS NOT COPIED HERE. The fixtures, the screens, the runs and every number
# come from `scripts/outage_screen.jl`, included into a submodule exactly as the
# low-inertia window includes its study (`low_inertia_window.jl`, whose header says
# why: a second copy is the parallel model SPEC §3.2 forbids). So this package depends
# on that file too, and moving it breaks the load. The read-out is the script's own row
# (`frequency_rows`) and the traces are the dip runs' own samples (`FrequencyTrace`);
# a test asserts both `isequal`.
#
# WHAT IS DRAWN, AND WHAT IS NOT.
#
#   - TOP: every surviving machine's frequency (thin) and the centre of inertia (bold)
#     over the whole run, with the preset's two limits as lines below nominal and
#     where each screen says the frequency SETTLES. That last pair is the picture's
#     reason to exist: on the mesh's G1 both screens call the outage secure and the
#     trace slides past both limits; on the default loads the run stops ABOVE the AC
#     screen's settled line (load relief, report claim h).
#   - MIDDLE: the first `FS_ZOOM` s after the trip — the dip starting and the rate of
#     fall the read-out reports. The rate is a number in the read-out, NOT a line on
#     the plot: no rate limit is sourced (m9-context.md D3), and a drawn threshold
#     would look like one.
#   - BOTTOM: all twelve outages side by side, one row each, cells coloured by verdict.
#     A pass is green and a FAIL red ONLY where the report judges; a refusal, a part with
#     no limit, and the rate are grey. The selected outage is outlined.
#
# Only the limits BELOW nominal are drawn: the verdict judges the size either way, but
# every outage here loses generation, so the frequency only falls (a test asserts it).
#
# A REFUSED RUN DRAWS NOTHING. Three outages are refused by the dynamic tier at the
# trip (report claim j); `generator_dips` keeps no samples for them, so the two plots
# are emptied and the refusal named in their place. Nothing of the previous selection
# survives a change.
#
# THE RUNS ARE THE SCRIPT'S, AT ITS OWN TOLERANCES. One grid's six runs take 0.2–3.4 s
# once compiled (m9-context.md D9); each (grid, loads) is run once, the first time the
# overview needs it — so the window runs all four at build, and every later click is a
# lookup.

module FrequencyReport
# The report script, verbatim — see the file header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "..", "..", "scripts", "outage_screen.jl"))
end

const _FRS = FrequencyReport

const FS_GRIDS = (:case9, :mesh)
const FS_LOADS = (:constant_power, :default)
const FS_NAMES = Dict(:case9 => "case9", :mesh => "mesh",
                      :constant_power => "constant-power loads", :default => "default loads")
# How long after the trip the middle panel shows: the dip of every uncapped outage
# here is over by 1.4 s (m9-context.md D1), and both rate windows end inside it.
const FS_ZOOM = 3.0
const FS_MACHINE_COLOURS = (C_SWING, C_INERTIA, RGBf(0.55, 0.30, 0.75))
const C_PASS = RGBf(0.78, 0.91, 0.80)
const C_FAIL = RGBf(0.96, 0.76, 0.76)
const C_NONE = RGBf(0.92, 0.92, 0.93)

# One grid's report: the screen, the dip runs (both tolerances, with their samples) and
# the script's own rows.
function _fs_report(grid::Symbol, loads::Symbol)
    net = getfield(_FRS, grid)(; loads)
    s = outage_screen(net)
    d = generator_dips(net, s)
    return (; net, s, d, rows = _FRS.frequency_rows(net; s, dips = d))
end

# The overview's columns: (heading, the cell's text, its colour) for one row.
_fs_judged(v::Symbol) = v === :pass ? C_PASS : v === :fail ? C_FAIL : C_NONE
_fs_screen(o::Symbol) = o === :secure ? C_PASS : C_FAIL
const FS_COLUMNS = (
    ("lines/V DC", r -> String(r.dc), r -> _fs_screen(r.dc)),
    ("lines/V AC", r -> String(r.ac), r -> _fs_screen(r.ac)),
    ("settled DC", r -> _FRS._f(r.Δf_dc, "%.4f") * " " * _FRS._v(r.settled_dc),
     r -> _fs_judged(r.settled_dc)),
    ("settled AC", r -> _FRS._f(r.Δf_ac, "%.4f") * " " * _FRS._v(r.settled_ac),
     r -> _fs_judged(r.settled_ac)),
    ("dip (worst machine)",
     r -> r.dyn === :measured ? _FRS._f(r.Δf_dip, "%.3f") * " " * _FRS._v(r.dip) :
          "$(r.dyn) ($(r.reason))",
     r -> _fs_judged(r.dip)),
    ("rate 500 ms (not judged)",
     r -> r.dyn === :measured ? _FRS._f(r.rate[1], "%.3f") * " Hz/s" : "—", _ -> C_NONE),
)

function _build_frequency_screen_window(; kwargs...)
    themed(() -> _build_frequency_screen_window_impl(; kwargs...))
end

function _build_frequency_screen_window_impl(; grid::Symbol = :mesh,
                                              loads::Symbol = :constant_power,
                                              lost::Symbol = :G1,
                                              cache = Dict{Tuple{Symbol,Symbol},Any}())
    grid in FS_GRIDS || throw(ArgumentError(
        "frequency-screen window: grid must be :case9 or :mesh, got :$grid."))
    loads in FS_LOADS || throw(ArgumentError(
        "frequency-screen window: loads must be :constant_power or :default, got :$loads."))
    report(g, l) = get!(() -> _fs_report(g, l), cache, (g, l))
    keys_all = [(g, l) for g in FS_GRIDS for l in FS_LOADS]
    foreach(k -> report(k...), keys_all)
    ids = [m.id for m in report(grid, loads).net.machines]
    lost in ids || throw(ArgumentError(
        "frequency-screen window: $grid has machines $(join(ids, ", ")), not :$lost."))
    lim = continental_europe_limits()

    fig = Figure(size = (1600, 1080))
    ax_f = Axis(fig[1, 1]; xlabel = "time (s)", ylabel = "frequency (Hz)")
    ax_z = Axis(fig[2, 1]; xlabel = "time (s)", ylabel = "frequency (Hz)")
    ax_o = Axis(fig[3, 1]; title = "every generator outage, side by side " *
                "(green pass, red FAIL where judged; grey: refused, no limit, or not judged)")
    hidedecorations!(ax_o); hidespines!(ax_o)
    rowsize!(fig.layout, 1, Relative(0.40))
    rowsize!(fig.layout, 2, Relative(0.24))

    # ---- the traces: one line per machine slot, the centre of inertia over them ------
    nmach = maximum(length(report(k...).net.machines) for k in keys_all)
    mach = [Observable(Point2f[]) for _ in 1:nmach]
    mach_z = [Observable(Point2f[]) for _ in 1:nmach]
    coi, coi_z = Observable(Point2f[]), Observable(Point2f[])
    for j in 1:nmach
        c = FS_MACHINE_COLOURS[mod1(j, length(FS_MACHINE_COLOURS))]
        lines!(ax_f, mach[j]; color = (c, 0.8), linewidth = 1.2, label = "G$j")
        lines!(ax_z, mach_z[j]; color = (c, 0.8), linewidth = 1.2)
    end
    lines!(ax_f, coi; color = C_EVENT, linewidth = 2.6, label = "centre of inertia")
    lines!(ax_z, coi_z; color = C_EVENT, linewidth = 2.6)

    # The preset's limits below nominal, and where each screen says frequency settles.
    f0 = report(grid, loads).net.f0
    lim_lines = (; settled = f0 - lim.settled, dip = f0 - lim.dip)
    for ax in (ax_f, ax_z)
        hlines!(ax, [f0]; color = (C_MUTED, 0.6), linewidth = 1)
        hlines!(ax, [lim_lines.settled]; color = C_AGGREGATE, linestyle = :dash,
                linewidth = 1.6, label = @sprintf("settled limit (%.1f Hz)", lim.settled))
        hlines!(ax, [lim_lines.dip]; color = C_WARN, linestyle = :dash, linewidth = 1.6,
                label = @sprintf("dip limit (%.1f Hz)", lim.dip))
    end
    settle_dc, settle_ac = Observable(Float64[]), Observable(Float64[])
    hlines!(ax_f, settle_dc; color = C_MUTED, linestyle = :dot, linewidth = 2.2,
            label = "DC screen settles")
    hlines!(ax_f, settle_ac; color = C_SWING, linestyle = :dot, linewidth = 2.2,
            label = "AC screen settles")
    trip = Observable(Float64[])
    vlines!(ax_f, trip; color = (C_EVENT, 0.5), linestyle = :dash)
    vlines!(ax_z, trip; color = (C_EVENT, 0.5), linestyle = :dash)
    refusal = Observable("")
    for ax in (ax_f, ax_z)
        text!(ax, 0.5, 0.5; text = refusal, space = :relative, align = (:center, :center),
              fontsize = 15, color = C_WARN, word_wrap_width = 700)
    end
    Legend(fig[1, 2], ax_f; tellheight = false, valign = :top, halign = :left)

    # ---- the overview: twelve rows, one per outage -----------------------------------
    ncol = length(FS_COLUMNS)
    overview = [(g, l, r) for (g, l) in keys_all for r in report(g, l).rows]
    nrow = length(overview)
    cellw = [1.6, 1.2, 1.2, 1.7, 1.7, 2.3, 2.2]      # the label column, then FS_COLUMNS
    x0 = cumsum([0.0; cellw])
    cell_text = Matrix{String}(undef, nrow, ncol)
    cell_colour = Matrix{RGBf}(undef, nrow, ncol)
    for (i, (g, l, r)) in enumerate(overview), (c, (_, txt, col)) in enumerate(FS_COLUMNS)
        cell_text[i, c], cell_colour[i, c] = txt(r), col(r)
    end
    y(i) = nrow - i                                   # row 1 at the top
    for (i, (g, l, r)) in enumerate(overview)
        text!(ax_o, x0[1] + 0.05, y(i) + 0.5;
              text = "$(FS_NAMES[g]) $(l === :default ? "def" : "cp") $(r.id)",
              align = (:left, :center), fontsize = 12, font = MONO_FONT)
        for c in 1:ncol
            poly!(ax_o, Rect2f(x0[c + 1] + 0.02, y(i) + 0.06, cellw[c + 1] - 0.04, 0.88);
                  color = cell_colour[i, c], strokewidth = 0)
            text!(ax_o, x0[c + 1] + 0.08, y(i) + 0.5; text = cell_text[i, c],
                  align = (:left, :center), fontsize = 11, font = MONO_FONT)
        end
    end
    for (c, (h, _, _)) in enumerate(FS_COLUMNS)
        text!(ax_o, x0[c + 1] + 0.08, nrow + 0.4; text = h, align = (:left, :center),
              fontsize = 11, font = :bold, color = C_MUTED)
    end
    selected_box = Observable(Rect2f(0, 0, 0, 0))
    poly!(ax_o, selected_box; color = :transparent, strokecolor = C_EVENT, strokewidth = 2.2)
    limits!(ax_o, 0, x0[end], -0.1, nrow + 0.9)

    # ---- the controls and the read-out ----------------------------------------------
    gc = fig[2:3, 2] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 2, Fixed(430))
    choice = (; grid = Observable(grid), loads = Observable(loads), lost = Observable(lost))
    section_label!(gc[1, 1], "grid")
    gg = gc[2, 1] = GridLayout()
    grid_buttons = Dict(g => Button(gg[1, i]; label = "") for (i, g) in enumerate(FS_GRIDS))
    section_label!(gc[3, 1], "loads")
    gl = gc[4, 1] = GridLayout()
    load_buttons = Dict(l => Button(gl[1, i]; label = "") for (i, l) in enumerate(FS_LOADS))
    section_label!(gc[5, 1], "generator lost")
    gm = gc[6, 1] = GridLayout()
    lost_buttons = Dict(Symbol(:G, j) => Button(gm[1, j]; label = "") for j in 1:nmach)
    section_label!(gc[7, 1], "the selected outage (Hz, Hz/s)")
    rk = "lines/V DC\nlines/V AC\nsettled DC\nsettled AC\nsettled pair\ndip worst\n" *
         "dip COI\ndynamic run\nrate 500 ms\nrate 1 s"
    gr = gc[8, 1] = GridLayout()
    ro = readout_block!(gr, rk; fontsize = 12)
    Label(gc[9, 1], "Limits: continental_europe_limits() — settled $(lim.settled) Hz, dip " *
          "$(lim.dip) Hz, from SO GL Annex III Table 1. These are DESIGN VALUES for a " *
          "whole synchronous area after its 3,000 MW reference incident, not a pass/fail " *
          "rule for one outage on a small grid: with the invented droop and damping here, " *
          "a pass or a FAIL describes that droop. No rate-of-fall limit is sourced, so the " *
          "rate is reported and not judged. The dip and the rate are every surviving " *
          "machine's, from a detailed-tier run (reltol 1e-8 drawn); a verdict counts only " *
          "where the 1e-6 run agrees. \"lines/V\" is M8's outcome, unchanged: secure means " *
          "the lines and voltages are within limits, and nothing about frequency.";
          halign = :left, tellwidth = false, fontsize = 11, color = C_MUTED,
          word_wrap = true, justification = :left)

    # ---- drawing ------------------------------------------------------------------
    row = Observable{Any}(nothing)
    function redraw!()
        g, l, id = choice.grid[], choice.loads[], choice.lost[]
        rep = report(g, l)
        k = findfirst(m -> m.id === id, rep.net.machines)
        k === nothing && (id = rep.net.machines[1].id; k = 1)
        for (x, b) in grid_buttons
            b.label[] = (x === g ? "▸ " : "") * FS_NAMES[x]
        end
        for (x, b) in load_buttons
            b.label[] = (x === l ? "▸ " : "") * (x === :default ? "default" : "constant power")
        end
        for (x, b) in lost_buttons
            j = findfirst(m -> m.id === x, rep.net.machines)
            b.label[] = j === nothing ? "—" :
                        (x === id ? "▸ " : "") * @sprintf("%s (%.0f MW)", x, rep.net.machines[j].P0)
        end
        r = rep.rows[k]
        row[] = r
        # Clear everything first: nothing from the last selection may survive this one.
        foreach(o -> o[] = Point2f[], mach); foreach(o -> o[] = Point2f[], mach_z)
        coi[] = Point2f[]; coi_z[] = Point2f[]
        refusal[] = ""
        settle_dc[] = isfinite(r.Δf_dc) ? [f0 + r.Δf_dc] : Float64[]
        settle_ac[] = isfinite(r.Δf_ac) ? [f0 + r.Δf_ac] : Float64[]
        tt = rep.d.t_trip
        trip[] = [tt]
        tr = rep.d.trace[k]
        zoom = (tt - 0.2, tt + FS_ZOOM)
        if r.dyn === :measured
            inz = findall(t -> zoom[1] <= t <= zoom[2], tr.t)
            for j in eachindex(rep.net.machines)
                j == k && continue                   # the machine lost is never drawn
                mach[j][] = Point2f.(tr.t, tr.f[:, j])
                mach_z[j][] = Point2f.(tr.t[inz], tr.f[inz, j])
            end
            coi[] = Point2f.(tr.t, tr.f_coi)
            coi_z[] = Point2f.(tr.t[inz], tr.f_coi[inz])
            # The whole run, the two limits and both settled lines always in view.
            ys = [vec(tr.f[:, [j for j in axes(tr.f, 2) if j != k]]); lim_lines.dip; f0;
                  settle_dc[]; settle_ac[]]
            lo, hi = extrema(ys); pad = 0.06 * (hi - lo)
            limits!(ax_f, 0, tr.t[end], lo - pad, hi + pad)
            zs = [vec(tr.f[inz, [j for j in axes(tr.f, 2) if j != k]]); f0]
            zlo, zhi = extrema(zs); zpad = max(0.08 * (zhi - zlo), 0.02)
            limits!(ax_z, zoom..., zlo - zpad, zhi + zpad)
        else
            why = r.reason === :voltage ?
                  "a bus left the voltage band the instant after the trip" :
                  "it measured nothing"
            refusal[] = "the dynamic run refused this outage — $(r.dyn) ($(r.reason)): " *
                        "$why, so there is no dip and no rate to draw"
            ys = [lim_lines.dip; f0; settle_dc[]; settle_ac[]]
            lo, hi = extrema(ys); pad = 0.1 * (hi - lo)
            limits!(ax_f, 0, tt + 10, lo - pad, hi + pad)
            limits!(ax_z, zoom..., lim_lines.dip - 0.1, f0 + 0.1)
        end
        ax_f.title[] = "frequency after losing $id — $(FS_NAMES[g]), $(FS_NAMES[l])"
        ax_z.title[] = @sprintf("the first %.0f s after the trip", FS_ZOOM)
        i = findfirst(x -> x[1] === g && x[2] === l && x[3].id === id, overview)
        selected_box[] = Rect2f(0.0, y(i), x0[end], 1.0)
        ro.values[] = _fs_readout(r, rep.d, k)
        return nothing
    end

    for (x, b) in grid_buttons
        on(_ -> (choice.grid[] = x), b.clicks)
    end
    for (x, b) in load_buttons
        on(_ -> (choice.loads[] = x), b.clicks)
    end
    for (x, b) in lost_buttons
        on(_ -> (choice.lost[] = x), b.clicks)
    end
    for o in choice
        on(_ -> redraw!(), o)
    end
    redraw!()

    widgets = (; grid_buttons, load_buttons, lost_buttons)
    plots = (; mach, mach_z, coi, coi_z, settle_dc, settle_ac, refusal, selected_box,
               lim_lines, cell_text, cell_colour, overview)
    return (; fig, axes = (; f = ax_f, z = ax_z, o = ax_o), choice, row, cache, widgets,
              plots, readout = ro, redraw!)
end

# The read-out for one row: the script's own numbers, formatted as its table prints them.
function _fs_readout(r, d, k)
    f, v = _FRS._f, _FRS._v
    measured = r.dyn === :measured
    rate(i) = measured ? @sprintf("%s %.3f (COI %.3f)", r.rate_worst[i], r.rate[i],
                                  r.rate_coi[i]) : "—"
    return join([String(r.dc), String(r.ac),
                 f(r.Δf_dc, "%.4f") * " " * v(r.settled_dc),
                 f(r.Δf_ac, "%.4f") * " " * v(r.settled_ac),
                 String(r.settled),
                 measured ? @sprintf("%s %.3f %s", r.dip_worst, r.Δf_dip, v(r.dip)) :
                            "$(r.dyn) ($(r.reason))",
                 measured ? f(r.Δf_dip_coi, "%.3f") : "—",
                 measured ? @sprintf("stopped %.1f s after the trip", d.t_stop[k] - d.t_trip) :
                            String(r.dyn),
                 rate(1), rate(2)], '\n')
end

"""
    frequency_screen(; grid = :mesh, loads = :constant_power, lost = :G1) -> window

Open the frequency-screen window (M9 step 7): `scripts/outage_screen.jl`'s section 4
drawn. Every generator outage of the two report grids side by side — M8's
line-and-voltage outcome at each fidelity beside the frequency verdict against
`continental_europe_limits()` — and, for the outage selected, every surviving machine's
frequency from the detailed-tier run the dip and the rate were read from, against the
two limits and where each screen says the frequency settles. Controls: the grid, the
load model, the generator lost.

Builds by running all four grids' dynamic runs once (seconds, once compiled); every
click after that is a lookup.

    julia --project=ui -e "using GridSimUI; wait_for_close(frequency_screen())"
"""
function frequency_screen(; kwargs...)
    GLMakie.activate!(; visible = true, title = "GridSim — frequency screen")
    win = _build_frequency_screen_window(; kwargs...)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    frequency_screen_render(; path, grid = :mesh, loads = :constant_power, lost = :G1) -> path

Build the frequency-screen window offscreen and save a PNG — how it is checked without
a screen.
"""
function frequency_screen_render(; path::AbstractString, kwargs...)
    GLMakie.activate!(; visible = false)
    win = _build_frequency_screen_window(; kwargs...)
    mkpath(dirname(path))
    Makie.colorbuffer(win.fig)          # one throwaway frame (the text atlas, as elsewhere)
    save(path, win.fig)
    return path
end
