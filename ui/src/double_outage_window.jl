# The double-outage window (M10 step 6, the user's choice) — the report drawn: every pair
# of elements of one report grid as a table you can click, and for the pair selected, the
# grid itself with what was lost crossed out and each piece left coloured by its verdict.
#
# THE REPORT IS NOT COPIED HERE. Grids, screens, rows and verdicts come from
# `scripts/double_outage_screen.jl`, included into a submodule as the frequency-screen
# window includes its script (`frequency_screen_window.jl`, whose header says why). The
# read-out is the script's own row; a test asserts it `===` the row the table cell says.
#
# WHAT IS DRAWN, AND WHAT IS NOT.
#
#   - LEFT: the pair table. Row = the element lost first, column = the second. "Both at
#     once" is one event, so cell (A, B) and cell (B, A) are the same row; "one after the
#     other" reads them as two orders. Each cell is coloured by the pair's ONE verdict at
#     the view chosen (m10-context.md D12.3, amended): green only where every running
#     piece passes, red where any fails, amber where every running piece passes but
#     customers are cut off, grey where something is not judged — and the cell's text
#     says which. A pair that IS one outage (a generator and the line it hangs on) is
#     marked "=" and the generator, never drawn as a double.
#   - RIGHT OF IT: the grid. Bus positions are render state and live here, never in the
#     script (D12.5); each bus is coloured by the piece it ends up in, matched to the row
#     BY BUS ID. A running piece is labelled with its settled Δf and verdict; a dead one
#     with what it took (load lost, sources lost).
#   - NO TIME TRACES. M10 runs no dynamic simulation per pair (D5): every number here is a
#     settled value from a screen, and a curve would suggest otherwise.
#
# Expect grey on case9 in AC "one after the other": after L14, L94 and G1 (and L45 on
# constant-power loads) the restored state is out of the voltage band, so 43 / 32 ordered
# pairs have no state after both (report claim o). That is the result, not a gap.
#
# BUILD COST. The four screens of both grids take well under a second once compiled; the
# window builds both grids at once and every click after that is a lookup.

module DoubleOutageReport
# The report script, verbatim — see the file header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "..", "..", "scripts", "double_outage_screen.jl"))
end

const _DOR = DoubleOutageReport

const DO_GRIDS = (:case9, :mesh)
const DO_TIMINGS = (:both, :sequential)
const DO_TIMING_NAMES = Dict(:both => "both at once", :sequential => "one after the other")
const DO_VIEWS = (:dc, :cp, :def)
const DO_VIEW_NAMES = Dict(:dc => "DC", :cp => "AC, constant-power loads",
                           :def => "AC, default loads")
const DO_DEFAULT_PAIR = Dict(:case9 => (:L45, :L67), :mesh => (:AB, :AC))
# Where each bus is drawn: render state (D12.5). case9 as its ring with three spurs, the
# mesh as M8 step 5 drew it.
const DO_POSITIONS = Dict(
    :case9 => Dict(:B4 => (0.0, -1.0), :B5 => (-0.87, -0.5), :B6 => (-0.87, 0.5),
                   :B7 => (0.0, 1.0), :B8 => (0.87, 0.5), :B9 => (0.87, -0.5),
                   :B1 => (0.0, -1.8), :B3 => (-1.7, 0.9), :B2 => (1.7, 0.9)),
    :mesh => Dict(:A => (-1.2, 0.0), :B => (0.0, 0.8), :C => (0.0, -0.8),
                  :D => (1.1, -0.2), :E => (2.0, 0.8)))
const C_AMBER = RGBf(0.98, 0.80, 0.45)
const C_DARK = RGBf(0.30, 0.30, 0.32)

# A pair's verdict → its cell colour (D12.3, amended).
function _do_colour(v::Symbol)
    v === :pass && return C_PASS
    v === :fail && return C_FAIL
    v === :pass_load_lost && return C_AMBER
    return C_NONE
end

# What a cell says: the worst Δf where something is judged, else the verdict's short name.
const DO_SHORT = Dict(:not_applicable => "n/a", :unjudged => "?", :already_lost => "AL",
                      :not_restored => "NR", :base_refused => "BR")
function _do_cell_text(side, same_as::Symbol)
    v = side.verdict
    # Three decimals below 1 Hz: at two, -0.2028 prints as a red "-0.20".
    t = v in (:pass, :fail, :pass_load_lost) ?
        (abs(side.worst) < 1 ? @sprintf("%+.3f", side.worst) : @sprintf("%+.2f", side.worst)) :
        get(DO_SHORT, v, String(v))
    v === :pass_load_lost && (t *= "!")
    same_as === :none || (t = "=" * String(same_as) * " " * t)
    return t
end

# One grid's report: the screens and the script's rows, both timings.
function _do_report(grid::Symbol)
    f = only(f for (k, _, f) in _DOR.GRIDS if k === grid)
    G = _DOR.grid_screens(f)
    both = _DOR.simultaneous_rows(G)
    seq = _DOR.sequential_rows(G; both)
    ids = G.dcseq.id
    return (; G, both, seq, ids, net = G.net)
end

# The row a cell (first, second) reads, at a timing.
function _do_lookup(rep, timing::Symbol, a::Symbol, b::Symbol)
    rows = timing === :both ? rep.both : rep.seq
    timing === :both && return only(r for r in rows if Set((r.first, r.second)) == Set((a, b)))
    return only(r for r in rows if (r.first, r.second) === (a, b))
end
# `same_as` lives on the unordered pair; a sequential cell borrows it.
_do_same_as(rep, a, b) = _do_lookup(rep, :both, a, b).same_as

function _build_double_outage_window(; kwargs...)
    themed(() -> _build_double_outage_window_impl(; kwargs...))
end

function _build_double_outage_window_impl(; grid::Symbol = :case9, timing::Symbol = :both,
                                          view::Symbol = :dc, pair = nothing,
                                          cache = Dict{Symbol,Any}())
    grid in DO_GRIDS || throw(ArgumentError(
        "double-outage window: grid must be :case9 or :mesh, got :$grid."))
    timing in DO_TIMINGS || throw(ArgumentError(
        "double-outage window: timing must be :both or :sequential, got :$timing."))
    view in DO_VIEWS || throw(ArgumentError(
        "double-outage window: view must be :dc, :cp or :def, got :$view."))
    report(g) = get!(() -> _do_report(g), cache, g)
    foreach(report, DO_GRIDS)
    pair = pair === nothing ? DO_DEFAULT_PAIR[grid] : Tuple(pair)
    ids0 = report(grid).ids
    (length(pair) == 2 && pair[1] !== pair[2] && all(in(ids0), pair)) || throw(ArgumentError(
        "double-outage window: pair must be two different elements of $grid " *
        "($(join(ids0, ", "))), got $pair."))

    fig = Figure(size = (1700, 1000))
    ax_m = Axis(fig[1, 1]; aspect = DataAspect())
    ax_g = Axis(fig[1, 2]; aspect = DataAspect())
    for ax in (ax_m, ax_g)
        hidedecorations!(ax); hidespines!(ax)
        deregister_interaction!(ax, :rectanglezoom)
        deregister_interaction!(ax, :scrollzoom)
        deregister_interaction!(ax, :dragpan)
    end
    colsize!(fig.layout, 1, Relative(0.40))

    choice = (; grid = Observable(grid), timing = Observable(timing), view = Observable(view),
              pair = Observable(pair))

    # ---- the controls, the legend, the read-out, the caveat ---------------------------
    gc = fig[1, 3] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 3, Fixed(440))
    section_label!(gc[1, 1], "grid")
    gg = gc[2, 1] = GridLayout()
    grid_buttons = Dict(g => Button(gg[1, i]; label = "") for (i, g) in enumerate(DO_GRIDS))
    section_label!(gc[3, 1], "timing")
    gt = gc[4, 1] = GridLayout()
    timing_buttons = Dict(t => Button(gt[1, i]; label = "") for (i, t) in enumerate(DO_TIMINGS))
    section_label!(gc[5, 1], "fidelity")
    gv = gc[6, 1] = GridLayout()
    view_buttons = Dict(v => Button(gv[1, i]; label = "") for (i, v) in enumerate(DO_VIEWS))
    section_label!(gc[7, 1], "a pair's colour (every running piece, settled Δf)")
    legend_rows = ((C_PASS, "every running piece passes (|Δf| ≤ 0.2 Hz)"),
                   (C_FAIL, "a running piece FAILS"),
                   (C_AMBER, "every running piece passes, but customers are\ncut off (cell marked !)"),
                   (C_NONE, "not judged: n/a (two lines, nothing split),\n? (no value), " *
                            "NR not restored, BR base\nrefused, AL already lost"),
                   (C_DARK, "on the grid: a dead piece (no frequency)"))
    gleg = gc[8, 1] = GridLayout()
    legend = Label[]
    for (i, (c, s)) in enumerate(legend_rows)
        Box(gleg[i, 1]; color = c, width = 16, height = 12, strokewidth = 0, valign = :top)
        push!(legend, Label(gleg[i, 2], s; halign = :left, justification = :left,
                            tellwidth = false, fontsize = 11))
    end
    push!(legend, Label(gleg[length(legend_rows) + 1, 1:2],
                        "\"=G1\": the pair IS one outage, that generator (D4)";
                        halign = :left, tellwidth = false, fontsize = 11))
    # The colour is the frequency verdict ALONE. M8's line-and-voltage outcome sits beside
    # it, per piece, and the two are never combined (m9-context.md D2.5) — so a green cell
    # can hide a bus outside the voltage band (case9 default loads, L14+L45).
    push!(legend, Label(gleg[length(legend_rows) + 2, 1:2],
                        "The colour judges FREQUENCY ONLY. Lines and voltages (M8's check)\n" *
                        "are each piece's (secure / overload / voltage) in the list and the\n" *
                        "read-out: a green cell can still have a bus outside the voltage band.";
                        halign = :left, justification = :left, tellwidth = false,
                        fontsize = 11, font = :bold, color = C_WARN))
    rowgap!(gleg, 3)
    section_label!(gc[9, 1], "the selected pair")
    readout = Label(gc[10, 1], ""; halign = :left, valign = :top, justification = :left,
                    tellwidth = false, fontsize = 12, font = MONO_FONT)
    caveat = Label(gc[11, 1], _DOR.CAVEAT * " Every pair here is screened statically: no " *
                   "dynamic run per pair is drawn.";
                   halign = :left, tellwidth = false, fontsize = 11, color = C_MUTED,
                   word_wrap = true, justification = :left)

    # ---- the pair table ----------------------------------------------------------------
    # Rebuilt on every change of grid, timing or view: the table is cheap (≤ 132 cells),
    # and rebuilding is how nothing of the previous view can survive.
    cell_text = Ref(Matrix{String}(undef, 0, 0))
    cell_colour = Ref(Matrix{RGBf}(undef, 0, 0))
    cell_row = Ref(Matrix{Any}(undef, 0, 0))
    selected_box = Observable(Rect2f(0, 0, 0, 0))
    function draw_table!()
        empty!(ax_m)
        rep = report(choice.grid[])
        ids = rep.ids
        N = length(ids)
        T = Matrix{String}(fill("", N, N)); C = fill(C_GRID, N, N); R = Matrix{Any}(fill(nothing, N, N))
        for i in 1:N, j in 1:N
            i == j && continue
            r = _do_lookup(rep, choice.timing[], ids[i], ids[j])
            side = getfield(r, choice.view[])
            R[i, j] = r
            T[i, j] = _do_cell_text(side, _do_same_as(rep, ids[i], ids[j]))
            C[i, j] = _do_colour(side.verdict)
        end
        cell_text[], cell_colour[], cell_row[] = T, C, R
        y(i) = N - i                                       # row 1 at the top
        for i in 1:N, j in 1:N
            poly!(ax_m, Rect2f(j - 1 + 0.03, y(i) + 0.03, 0.94, 0.94); color = C[i, j],
                  strokewidth = 0)
            i == j || text!(ax_m, j - 0.5, y(i) + 0.5; text = T[i, j], align = (:center, :center),
                            fontsize = N > 10 ? 8.5 : 10, font = MONO_FONT)
        end
        for (k, id) in enumerate(ids)
            text!(ax_m, -0.15, y(k) + 0.5; text = String(id), align = (:right, :center),
                  fontsize = 11, font = :bold)
            text!(ax_m, k - 0.5, N + 0.15; text = String(id), align = (:center, :bottom),
                  fontsize = 11, font = :bold)
        end
        text!(ax_m, N / 2, N + 0.9; text = choice.timing[] === :both ?
              "row + column, both at once (the table is symmetric)" :
              "row lost first, 50 Hz restored, then column",
              align = (:center, :bottom), fontsize = 12, color = C_MUTED)
        poly!(ax_m, selected_box; color = :transparent, strokecolor = C_EVENT, strokewidth = 2.6)
        limits!(ax_m, -1.3, N + 0.1, -0.2, N + 1.6)
        ax_m.title[] = "$(choice.grid[]) — $(DO_TIMING_NAMES[choice.timing[]]) — $(DO_VIEW_NAMES[choice.view[]])"
        return nothing
    end

    # ---- the grid sketch -----------------------------------------------------------------
    bus_colour = Observable(Dict{Symbol,RGBf}())
    piece_labels = Observable(String[])
    banner = Observable("")
    function draw_grid!(rep, r, side)
        empty!(ax_g)
        net = rep.net.cp
        pos = DO_POSITIONS[choice.grid[]]
        P(b) = Point2f(pos[b]...)
        a, b = r.first, r.second
        lost = Set((a, b))
        # The pieces, by bus id.
        piece_of = Dict{Symbol,Int}()
        for (k, p) in pairs(side.pieces), bs in p.buses
            piece_of[bs] = k
        end
        cols = Dict{Symbol,RGBf}()
        screened = side.outcome === :screened
        for bs in net.buses
            k = get(piece_of, bs.id, 0)
            p = k == 0 ? nothing : side.pieces[k]
            cols[bs.id] = !screened || p === nothing ? C_NONE :
                          p.kind !== :live ? C_DARK :
                          p.verdict === :pass ? C_PASS : p.verdict === :fail ? C_FAIL : C_NONE
        end
        bus_colour[] = cols
        for br in net.branches
            gone = br.id in lost
            lines!(ax_g, [P(br.from), P(br.to)]; color = gone ? C_WARN : C_MUTED,
                   linewidth = gone ? 2.0 : 2.4, linestyle = gone ? :dash : :solid)
            mid = (P(br.from) + P(br.to)) / 2
            text!(ax_g, mid; text = String(br.id), fontsize = 10, color = gone ? C_WARN : C_MUTED,
                  align = (:left, :bottom), offset = (5, 3))
            gone && scatter!(ax_g, [mid]; marker = :xcross, markersize = 18, color = C_WARN)
        end
        bus_pts = [P(bs.id) for bs in net.buses]
        scatter!(ax_g, bus_pts; color = [cols[bs.id] for bs in net.buses], markersize = 30,
                 strokewidth = 1.5, strokecolor = C_EVENT)
        for bs in net.buses
            text!(ax_g, P(bs.id); text = String(bs.id), align = (:center, :center), fontsize = 11,
                  font = :bold)
        end
        for mc in net.machines
            q = P(mc.bus) + Point2f(0.0, 0.24)
            gone = mc.id in lost
            scatter!(ax_g, [q]; marker = :circle, markersize = 20, color = :white,
                     strokewidth = 1.5, strokecolor = gone ? C_WARN : C_SWING)
            text!(ax_g, q; text = String(mc.id), align = (:center, :center), fontsize = 9,
                  color = gone ? C_WARN : C_SWING)
            gone && scatter!(ax_g, [q]; marker = :xcross, markersize = 22, color = C_WARN)
        end
        for ld in net.loads
            scatter!(ax_g, [P(ld.bus) + Point2f(0.0, -0.22)]; marker = :dtriangle,
                     markersize = 13, color = C_MUTED)
        end
        labels = String[]
        xs = [p[1] for p in bus_pts]; ys = [p[2] for p in bus_pts]
        x0, y0 = minimum(xs) - 0.5, minimum(ys) - 0.55
        if screened
            for (k, p) in pairs(side.pieces)
                t = p.kind === :live ?
                    (p.verdict in (:pass, :fail) ?
                     @sprintf("Δf %+.4f Hz %s (%s)", p.Δf, _DOR._t(p.verdict), p.outcome) :
                     "$(_DOR._t(p.verdict)) ($(p.outcome))") :
                    p.kind === :load_lost ? @sprintf("LOAD LOST %.1f MW", p.load_mw) :
                    p.kind === :sources_lost ? @sprintf("sources lost %.1f MW", p.sources_mw) :
                    "empty"
                push!(labels, t)
                # Listed under the grid, each beside its piece's colour: labels placed on
                # the drawing collide with the branch names.
                yk = y0 - 0.24 * (k - 1)
                scatter!(ax_g, [Point2f(x0, yk)]; marker = :rect, markersize = 14,
                         color = cols[first(p.buses)], strokewidth = 1, strokecolor = C_EVENT)
                text!(ax_g, Point2f(x0 + 0.12, yk); text = "{" * join(p.buses, ",") * "}  " * t,
                      align = (:left, :center), fontsize = 11, font = MONO_FONT)
            end
        end
        piece_labels[] = labels
        banner[] = screened ? "" :
            "no state after both losses — $(_DOR._t(side.outcome)): " *
            (side.outcome === :not_restored ? "50 Hz could not be restored after $a " *
             "(refused, or the restored state is out of the voltage band), so $b is not screened" :
             side.outcome === :already_lost ? "$b was already lost with $a" :
             "the restored model's base was refused")
        isempty(banner[]) || text!(ax_g, 0.5, 0.02; text = banner[], space = :relative,
                                   align = (:center, :bottom), fontsize = 13, color = C_WARN,
                                   word_wrap_width = 480)
        nlist = max(length(side.pieces), 3)
        limits!(ax_g, minimum(xs) - 0.7, maximum(xs) + 0.7, y0 - 0.24 * nlist - 0.1,
                maximum(ys) + 0.6)
        ax_g.title[] = choice.timing[] === :both ? "$a and $b lost at once" :
                       "$a lost, 50 Hz restored, then $b"
        return nothing
    end

    # ---- drawing ------------------------------------------------------------------
    row = Observable{Any}(nothing)
    function redraw!()
        g = choice.grid[]
        rep = report(g)
        a, b = choice.pair[]
        if !(a in rep.ids && b in rep.ids)          # a grid change: its default pair
            choice.pair.val = DO_DEFAULT_PAIR[g]
            a, b = choice.pair[]
        end
        for (x, bt) in grid_buttons
            bt.label[] = (x === g ? "▸ " : "") * String(x)
        end
        for (x, bt) in timing_buttons
            bt.label[] = (x === choice.timing[] ? "▸ " : "") * DO_TIMING_NAMES[x]
        end
        for (x, bt) in view_buttons
            bt.label[] = (x === choice.view[] ? "▸ " : "") *
                         (x === :dc ? "DC" : x === :cp ? "AC const P" : "AC default")
        end
        draw_table!()
        r = _do_lookup(rep, choice.timing[], a, b)
        side = getfield(r, choice.view[])
        row[] = r
        N = length(rep.ids)
        i, j = findfirst(==(a), rep.ids), findfirst(==(b), rep.ids)
        selected_box[] = Rect2f(j - 1, N - i, 1, 1)
        draw_grid!(rep, r, side)
        readout.text[] = _do_readout(rep, r, choice.timing[], choice.view[])
        return nothing
    end

    # A press at data coordinates (x, y) of the table: select that cell's pair. The
    # diagonal and the margins select nothing. Returned so tests drive it directly.
    function matrix_press!(x::Real, y::Real)
        ids = report(choice.grid[]).ids
        N = length(ids)
        (0 < x < N && 0 < y < N) || return nothing
        j = ceil(Int, x); i = N - ceil(Int, y) + 1
        i == j && return nothing
        choice.pair[] = (ids[i], ids[j])
        return (ids[i], ids[j])
    end
    on(events(ax_m.scene).mousebutton; priority = 10) do ev
        (ev.button == Mouse.left && ev.action == Mouse.press) || return Consume(false)
        is_mouseinside(ax_m.scene) || return Consume(false)
        p = mouseposition(ax_m.scene)
        matrix_press!(p[1], p[2])
        return Consume(true)
    end

    for (x, bt) in grid_buttons
        on(_ -> (choice.grid[] = x), bt.clicks)
    end
    for (x, bt) in timing_buttons
        on(_ -> (choice.timing[] = x), bt.clicks)
    end
    for (x, bt) in view_buttons
        on(_ -> (choice.view[] = x), bt.clicks)
    end
    for o in choice
        on(_ -> redraw!(), o)
    end
    redraw!()

    widgets = (; grid_buttons, timing_buttons, view_buttons)
    plots = (; cell_text, cell_colour, cell_row, selected_box, bus_colour, piece_labels, banner)
    return (; fig, axes = (; m = ax_m, g = ax_g), choice, row, cache, widgets, plots,
              readout, legend, caveat, redraw!, matrix_press!)
end

# The read-out for one pair at one view: the script's own row, as its tables print it.
function _do_readout(rep, r, timing::Symbol, view::Symbol)
    side = getfield(r, view)
    same = _do_same_as(rep, r.first, r.second)
    lines = String[timing === :both ? "$(r.first) + $(r.second), both at once" :
                   "$(r.first), then 50 Hz restored, then $(r.second)",
                   "view      $(DO_VIEW_NAMES[view])",
                   "verdict   $(_DOR._t(side.verdict))" *
                   (isnan(side.worst) ? "" : @sprintf(", worst Δf %+.4f Hz", side.worst))]
    same === :none || push!(lines, "one outage: the pair IS losing $same (D4)")
    if timing === :both
        # M8's comparison: line loadings and voltages, NOT frequency — so "agree" can sit
        # beside a frequency verdict DC and AC split on.
        view === :dc || push!(lines, "lines/V   DC vs AC: $(getfield(r.class, view))")
    else
        o = getfield(r.order, view)
        o === :none || push!(lines, "vs both at once: $o")
    end
    side.outcome === :screened || push!(lines, "no state after both: $(_DOR._t(side.outcome))")
    for p in side.pieces
        push!(lines, "{" * join(p.buses, ",") * "} " *
              (p.kind !== :live ? (p.kind === :load_lost ? @sprintf("LOAD LOST %.1f MW", p.load_mw) :
                                   p.kind === :sources_lost ? @sprintf("sources lost %.1f MW", p.sources_mw) :
                                   "empty") :
               p.verdict in (:pass, :fail) ?
               @sprintf("%+.4f Hz %s (%s)", p.Δf, _DOR._t(p.verdict), p.outcome) :
               "$(_DOR._t(p.verdict)) ($(p.outcome))"))
    end
    return join(lines, '\n')
end

"""
    double_outages(; grid = :case9, timing = :both, view = :dc, pair = nothing) -> window

Open the double-outage window (M10 step 6): `scripts/double_outage_screen.jl` drawn. Every
pair of elements of a report grid as a table — both at once, or one after the other with
50 Hz restored in between — each cell coloured by the pair's settled-frequency verdict at
the view chosen (DC, or AC on either load model); click a cell to see that pair on the
grid, with what was lost crossed out and every piece left coloured and labelled.

    julia --project=ui -e "using GridSimUI; wait_for_close(double_outages())"
"""
function double_outages(; kwargs...)
    GLMakie.activate!(; visible = true, title = "GridSim — double outages")
    win = _build_double_outage_window(; kwargs...)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    double_outages_render(; path, grid = :case9, timing = :both, view = :dc, pair = nothing) -> path

Build the double-outage window offscreen and save a PNG — how it is checked without a
screen.
"""
function double_outages_render(; path::AbstractString, kwargs...)
    GLMakie.activate!(; visible = false)
    win = _build_double_outage_window(; kwargs...)
    mkpath(dirname(path))
    Makie.colorbuffer(win.fig)          # one throwaway frame (the text atlas, as elsewhere)
    save(path, win.fig)
    return path
end
