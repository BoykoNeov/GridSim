# The network-dispatch window (M11 step 5, the user's choice) — the report drawn: for each
# case9 fixture, the network-free dispatch beside the DC and the AC network optimum, and the
# answer chosen drawn on the grid with what binds marked.
#
# THE REPORT IS NOT COPIED HERE. Fixtures, solves, rows and the flat runs come from
# `scripts/network_dispatch.jl`, included into a submodule as the double-outage window
# includes its script (`double_outage_window.jl`, whose header says why). The read-out is the
# script's own row; a test asserts it `===` the one the table cell came from.
#
# WHAT IS DRAWN, AND WHAT IS NOT.
#
#   - LEFT: the grid. Bus positions are render state and live here (M10's case9 layout,
#     reused). Each line is drawn by its loading at the answer chosen — DC: `|flow|` against
#     the rating; AC: `|S|` at the larger end — and a line AT its limit is red and says so. In
#     AC each bus carries its `|V|`, and a bus on the band is ringed red; DC has no voltages
#     (it assumes 1 pu everywhere) and draws none. Each generator carries its output.
#   - RIGHT OF IT: the three outputs under the network-free dispatch, the DC optimum and the AC
#     one, side by side — what the network moves.
#   - BOTTOM: the six fixtures on the load model chosen, one row each. Green: an answer with
#     nothing at a limit; amber: an answer ON a limit; red: the flow refuses M6's dispatch, or
#     Ipopt finds no AC point. Click a row to select it.
#   - NO TIME TRACES. The flat runs' numbers are in the read-out; a flat line is not a picture.
#
# THE CAVEATS TRAVEL WITH THE NUMBERS (the read-out's foot): the ratings are invented, the
# limits are case9's without line charging, every AC answer is Ipopt's local one, and on the
# default loads an AC cost below the network-free one is load not served (D11).
#
# BUILD COST. The script's twelve rows (three solves each) and eleven flat runs, once; every
# click after that is a lookup.

module NetworkDispatchReport
# The report script, verbatim — see the file header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "..", "..", "scripts", "network_dispatch.jl"))
end

const _NDR = NetworkDispatchReport

const ND_KEYS = Tuple(k for (k, _, _) in _NDR.FIXTURES)
const ND_LOADS = _NDR.LOADS
const ND_ANSWERS = (:dc, :ac)
const ND_ANSWER_NAMES = Dict(:dc => "DC network optimum", :ac => "AC network optimum")
const ND_SHORT = Dict(:published => "published", :L82 => "L82 100 MVA", :L89 => "L89 50 MVA",
                      :L94 => "L94 60 MVA", :x150 => "loads 1.5×", :x175 => "loads 1.75×")
const ND_POSITIONS = DO_POSITIONS[:case9]
const ND_BAR_COLOURS = (C_MUTED, C_AGGREGATE, C_SWING)     # network-free, DC, AC
# The ring's buses; the other three are the generators' spurs. Labels go INSIDE the ring for
# a ring bus and outside it for a spur bus, generators outward — measured on the rendered
# window, where labels on the line's side of a bus collided with the lines' own.
const ND_RING = (:B4, :B5, :B6, :B7, :B8, :B9)
_nd_unit(p) = p / sqrt(p[1]^2 + p[2]^2)

# A line's colour by its loading: muted when idle, toward the aggregate orange at its rating.
_nd_mix(a::RGBf, b::RGBf, t::Real) = RGBf(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                                          a.b + (b.b - a.b) * t)

# The script's rows and flat runs, once.
function _nd_report()
    rows = _NDR.report_rows()
    return (; rows, flat = _NDR.flat_rows(rows))
end

_nd_row(rep, key, loads) = only(r for r in rep.rows if r.key === key && r.loads === loads)
_nd_flat(rep, key, loads) =
    (i = findfirst(r -> r.key === key && r.loads === loads, rep.flat);
     i === nothing ? nothing : rep.flat[i].flat)

# A cell's colour: an answer with nothing at a limit, an answer on one, or none.
function _nd_colour(answer)
    if answer isa DCOPF
        answer.outcome === :optimal || return C_FAIL
        return isempty(answer.at_limit) ? C_PASS : C_AMBER
    elseif answer isa ACOPF
        answer.outcome === :locally_optimal || return C_FAIL
        return isempty(answer.at_limit) && isempty(answer.at_band) ? C_PASS : C_AMBER
    end
    return answer.outcome === :secure ? C_PASS : C_FAIL      # M6's dispatch, to the flow
end

# The table's columns: (heading, the cell's text, its colour) for one row of the script.
const ND_COLUMNS = (
    ("network-free \$/h", R -> _NDR._cost(R.ed.cost), R -> C_NONE),
    ("… handed to the AC flow",
     R -> R.flowed.outcome === :secure ? _NDR._cost(R.flowed.cost) :
          "REFUSED: " * _NDR._refusal(R.flow_detail),
     R -> _nd_colour(R.flowed)),
    ("DC optimum \$/h, binds",
     R -> _NDR._cost(R.dc.cost) * "  " * _NDR._binds(R.dc), R -> _nd_colour(R.dc)),
    ("AC optimum \$/h, binds",
     R -> R.ac.outcome === :locally_optimal ? _NDR._cost(R.ac.cost) * "  " * _NDR._binds(R.ac) :
          "no AC point found (Ipopt, local)",
     R -> _nd_colour(R.ac)),
)

function _build_network_dispatch_window(; kwargs...)
    themed(() -> _build_network_dispatch_window_impl(; kwargs...))
end

function _build_network_dispatch_window_impl(; fixture::Symbol = :L89,
                                             loads::Symbol = :constant_power,
                                             answer::Symbol = :ac, cache = Dict{Symbol,Any}())
    fixture in ND_KEYS || throw(ArgumentError(
        "network-dispatch window: fixture must be one of $(join(ND_KEYS, ", ")), got :$fixture."))
    loads in ND_LOADS || throw(ArgumentError(
        "network-dispatch window: loads must be :constant_power or :default, got :$loads."))
    answer in ND_ANSWERS || throw(ArgumentError(
        "network-dispatch window: answer must be :dc or :ac, got :$answer."))
    rep = get!(_nd_report, cache, :report)

    fig = Figure(size = (1700, 1000))
    ax_g = Axis(fig[1, 1]; aspect = DataAspect())
    ax_b = Axis(fig[1, 2]; ylabel = "output (MW)", xticks = (1:3, ["G1", "G2", "G3"]))
    ax_t = Axis(fig[2, 1:2])
    for ax in (ax_g, ax_t)
        hidedecorations!(ax); hidespines!(ax)
    end
    for ax in (ax_g, ax_t, ax_b)
        deregister_interaction!(ax, :rectanglezoom)
        deregister_interaction!(ax, :scrollzoom)
        deregister_interaction!(ax, :dragpan)
    end
    rowsize!(fig.layout, 1, Relative(0.64))
    colsize!(fig.layout, 1, Relative(0.42))

    choice = (; fixture = Observable(fixture), loads = Observable(loads),
              answer = Observable(answer))

    # ---- the controls, the read-out, the caveat --------------------------------------
    gc = fig[1:2, 3] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 3, Fixed(450))
    section_label!(gc[1, 1], "load model")
    gl = gc[2, 1] = GridLayout()
    load_buttons = Dict(l => Button(gl[1, i]; label = "") for (i, l) in enumerate(ND_LOADS))
    section_label!(gc[3, 1], "drawn on the grid")
    ga = gc[4, 1] = GridLayout()
    answer_buttons = Dict(a => Button(ga[1, i]; label = "") for (i, a) in enumerate(ND_ANSWERS))
    section_label!(gc[5, 1], "fixture (or click a row of the table)")
    gf = gc[6, 1] = GridLayout()
    fixture_buttons = Dict(k => Button(gf[div(i - 1, 3) + 1, mod1(i, 3)]; label = "")
                           for (i, k) in enumerate(ND_KEYS))
    section_label!(gc[7, 1], "the selected fixture (\$/h, MW)")
    readout = Label(gc[8, 1], ""; halign = :left, valign = :top, justification = :left,
                    tellwidth = false, fontsize = 11.5, font = MONO_FONT)
    caveat = Label(gc[9, 1],
        "The line ratings L82 100, L89 50 and L94 60 MVA are INVENTED: on case9 as " *
        "published no line limit binds. case9 here has no line charging, so the load limits " *
        "(B9 on the 0.9 pu floor at 1.5×, no AC point at 1.75×) are this case9's, not " *
        "MATPOWER's published one, which solves at 1.75×. Every AC answer is Ipopt's LOCAL " *
        "one. On the default loads an AC cost below the network-free one is load NOT SERVED " *
        "at the sagging voltages, not generation saved (m11-context.md D11). The flat run is " *
        "the AC optimum's schedule in the detailed tier, no event: it shows a steady state, " *
        "not that any governor is right.";
        halign = :left, tellwidth = false, fontsize = 11, color = C_MUTED, word_wrap = true,
        justification = :left)

    # ---- the table --------------------------------------------------------------------
    cellw = [1.5, 1.4, 3.3, 2.0, 2.6]        # the label column, then ND_COLUMNS
    x0 = cumsum([0.0; cellw])
    cell_text = Ref(Matrix{String}(undef, 0, 0))
    cell_colour = Ref(Matrix{RGBf}(undef, 0, 0))
    cell_row = Ref(Any[])
    selected_box = Observable(Rect2f(0, 0, 0, 0))
    N = length(ND_KEYS)
    y(i) = N - i
    function draw_table!()
        empty!(ax_t)
        l = choice.loads[]
        T = Matrix{String}(undef, N, length(ND_COLUMNS))
        C = Matrix{RGBf}(undef, N, length(ND_COLUMNS))
        rows = Any[_nd_row(rep, k, l) for k in ND_KEYS]
        for (i, r) in enumerate(rows), (c, (_, txt, col)) in enumerate(ND_COLUMNS)
            T[i, c], C[i, c] = txt(r.row), col(r.row)
        end
        cell_text[], cell_colour[], cell_row[] = T, C, rows
        for (i, k) in enumerate(ND_KEYS)
            text!(ax_t, x0[1] + 0.05, y(i) + 0.5; text = ND_SHORT[k], align = (:left, :center),
                  fontsize = 12, font = :bold)
            for c in eachindex(ND_COLUMNS)
                poly!(ax_t, Rect2f(x0[c + 1] + 0.02, y(i) + 0.06, cellw[c + 1] - 0.04, 0.88);
                      color = C[i, c], strokewidth = 0)
                text!(ax_t, x0[c + 1] + 0.06, y(i) + 0.5; text = T[i, c],
                      align = (:left, :center), fontsize = 10.5, font = MONO_FONT)
            end
        end
        for (c, (h, _, _)) in enumerate(ND_COLUMNS)
            text!(ax_t, x0[c + 1] + 0.06, N + 0.35; text = h, align = (:left, :center),
                  fontsize = 11, font = :bold, color = C_MUTED)
        end
        ax_t.title[] = "every fixture, $(_NDR.LOAD_NAMES[l]) — green: an answer, nothing at " *
                       "a limit · amber: an answer ON a limit · red: refused, or no answer"
        poly!(ax_t, selected_box; color = :transparent, strokecolor = C_EVENT, strokewidth = 2.4)
        limits!(ax_t, 0, x0[end], -0.1, N + 0.8)
        return nothing
    end

    # ---- the grid sketch ----------------------------------------------------------------
    line_loading = Observable(Dict{Symbol,Float64}())
    banner = Observable("")
    function draw_grid!(R, label)
        empty!(ax_g)
        net = R.net
        a = choice.answer[] === :dc ? R.dc : R.ac
        P(b) = Point2f(ND_POSITIONS[b]...)
        S = net.S_base
        solved = a isa DCOPF ? a.outcome === :optimal : a.outcome === :locally_optimal
        load = Dict{Symbol,Float64}()
        for (e, br) in pairs(net.branches)
            ratio = !solved ? NaN : a isa DCOPF ? abs(a.flow[e]) * S / br.rating :
                                   a.mva[e] * S / br.rating
            load[br.id] = ratio
            on_limit = solved && br.id in a.at_limit
            c = on_limit ? C_WARN : isnan(ratio) ? C_GRID :
                _nd_mix(C_MUTED, C_AGGREGATE, clamp(ratio, 0, 1))
            lines!(ax_g, [P(br.from), P(br.to)]; color = c,
                   linewidth = on_limit ? 6.0 : 1.5 + 4.0 * (isnan(ratio) ? 0.0 : clamp(ratio, 0, 1)))
            mid = (P(br.from) + P(br.to)) / 2
            lbl = String(br.id) * (isnan(ratio) ? "" : @sprintf(" %.0f%%", 100ratio)) *
                  (on_limit ? " AT LIMIT" : "")
            # A ring line's label outside the ring; a spur's beside it.
            d = P(br.to) - P(br.from)
            at = br.from in ND_RING && br.to in ND_RING ? mid + 0.16f0 * _nd_unit(mid) :
                 mid + 0.2f0 * _nd_unit(Point2f(-d[2], d[1]))
            text!(ax_g, at; text = lbl, fontsize = 10, color = on_limit ? C_WARN : C_MUTED,
                  font = on_limit ? :bold : :regular, align = (:center, :center))
        end
        line_loading[] = load
        floor = a isa ACOPF && solved ? Set(a.at_band) : Set{Symbol}()
        for bs in net.buses
            ringed = bs.id in floor
            scatter!(ax_g, [P(bs.id)]; color = ringed ? C_FAIL : C_GRID, markersize = 30,
                     strokewidth = ringed ? 3.0 : 1.5, strokecolor = ringed ? C_WARN : C_EVENT)
            text!(ax_g, P(bs.id); text = String(bs.id), align = (:center, :center), fontsize = 11,
                  font = :bold)
            if a isa ACOPF && solved
                v = a.Vm[findfirst(==(bs.id), a.buses)]
                u = _nd_unit(P(bs.id))
                text!(ax_g, P(bs.id) + (bs.id in ND_RING ? -0.27f0 : 0.27f0) * u;
                      text = @sprintf("%.4f", v), align = (:center, :center), fontsize = 9.5,
                      font = MONO_FONT,
                      color = ringed ? C_WARN : C_MUTED)
            end
        end
        for (k, mc) in pairs(net.machines)
            u = _nd_unit(P(mc.bus))
            q = P(mc.bus) + 0.5f0 * u
            scatter!(ax_g, [q]; marker = :circle, markersize = 20, color = :white,
                     strokewidth = 1.5, strokecolor = C_SWING)
            text!(ax_g, q; text = String(mc.id), align = (:center, :center), fontsize = 9,
                  color = C_SWING)
            # Above or below its marker, never further out sideways (the edge clips it).
            solved && text!(ax_g, q + Point2f(0, 0.2f0 * sign(u[2])); text = @sprintf("%.1f MW", a.P[k] * S),
                            align = (:center, :center), fontsize = 10, font = MONO_FONT,
                            color = C_SWING)
        end
        for ld in net.loads
            scatter!(ax_g, [P(ld.bus) + 0.24f0 * _nd_unit(P(ld.bus))]; marker = :dtriangle,
                     markersize = 13, color = C_MUTED)
        end
        banner[] = solved ? (a isa DCOPF ? "DC: no voltages — every |V| is 1 pu by assumption" : "") :
                   "Ipopt found no AC point here — its LOCAL word, not a proof that none exists"
        isempty(banner[]) || text!(ax_g, 0.5, 0.01; text = banner[], space = :relative,
                                   align = (:center, :bottom), fontsize = 12,
                                   color = solved ? C_MUTED : C_WARN, word_wrap_width = 520)
        xs = [p[1] for p in values(ND_POSITIONS)]; ys = [p[2] for p in values(ND_POSITIONS)]
        limits!(ax_g, minimum(xs) - 0.75, maximum(xs) + 0.75, minimum(ys) - 1.1, maximum(ys) + 0.6)
        ax_g.title[] = "$(ND_ANSWER_NAMES[choice.answer[]]) — $label, " *
                       _NDR.LOAD_NAMES[choice.loads[]]
        return nothing
    end

    # ---- the outputs ------------------------------------------------------------------
    bars = Observable(zeros(3, 3))          # (machine, answer): network-free, DC, AC
    function draw_bars!(R)
        empty!(ax_b)
        S = R.net.S_base
        M = fill(NaN, 3, 3)
        M[:, 1] = R.ed.P .* S
        M[:, 2] = R.dc.P .* S
        R.ac.outcome === :locally_optimal && (M[:, 3] = R.ac.P .* S)
        bars[] = M
        xs, hs, gs = Int[], Float64[], Int[]
        for k in 1:3, j in 1:3
            isnan(M[k, j]) && continue
            push!(xs, k); push!(hs, M[k, j]); push!(gs, j)
        end
        barplot!(ax_b, xs, hs; dodge = gs, color = [ND_BAR_COLOURS[g] for g in gs])
        for (j, name) in enumerate(("network-free", "DC optimum", "AC optimum"))
            text!(ax_b, 0.02, 0.98 - 0.06 * (j - 1); text = "■ " * name, space = :relative,
                  align = (:left, :top), fontsize = 12, color = ND_BAR_COLOURS[j])
        end
        R.ac.outcome === :locally_optimal ||
            text!(ax_b, 0.98, 0.98; text = "no AC point found", space = :relative,
                  align = (:right, :top), fontsize = 12, color = C_WARN)
        ylims!(ax_b, 0, 1.18 * maximum(filter(!isnan, M)))
        ax_b.title[] = "what the network moves"
        return nothing
    end

    # ---- drawing ------------------------------------------------------------------
    row = Observable{Any}(nothing)
    function redraw!()
        k, l = choice.fixture[], choice.loads[]
        for (x, b) in load_buttons
            b.label[] = (x === l ? "▸ " : "") * (x === :default ? "default" : "constant power")
        end
        for (x, b) in answer_buttons
            b.label[] = (x === choice.answer[] ? "▸ " : "") * (x === :dc ? "DC optimum" : "AC optimum")
        end
        for (x, b) in fixture_buttons
            b.label[] = (x === k ? "▸ " : "") * ND_SHORT[x]
        end
        draw_table!()
        i = findfirst(==(k), ND_KEYS)
        r = cell_row[][i]
        row[] = r
        selected_box[] = Rect2f(0.0, y(i), x0[end], 1.0)
        draw_grid!(r.row, r.label)
        draw_bars!(r.row)
        readout.text[] = _nd_readout(r, _nd_flat(rep, k, l))
        return nothing
    end

    # A press at data coordinates (x, y) of the table: select that row's fixture. The
    # margins select nothing. Returned so tests drive it directly.
    function table_press!(x::Real, yy::Real)
        (0 < x < x0[end] && 0 < yy < N) || return nothing
        i = N - ceil(Int, yy) + 1
        choice.fixture[] = ND_KEYS[i]
        return ND_KEYS[i]
    end
    on(events(ax_t.scene).mousebutton; priority = 10) do ev
        (ev.button == Mouse.left && ev.action == Mouse.press) || return Consume(false)
        is_mouseinside(ax_t.scene) || return Consume(false)
        p = mouseposition(ax_t.scene)
        table_press!(p[1], p[2])
        return Consume(true)
    end

    for (x, b) in load_buttons
        on(_ -> (choice.loads[] = x), b.clicks)
    end
    for (x, b) in answer_buttons
        on(_ -> (choice.answer[] = x), b.clicks)
    end
    for (x, b) in fixture_buttons
        on(_ -> (choice.fixture[] = x), b.clicks)
    end
    for o in choice
        on(_ -> redraw!(), o)
    end
    redraw!()

    widgets = (; load_buttons, answer_buttons, fixture_buttons)
    plots = (; cell_text, cell_colour, cell_row, selected_box, line_loading, banner, bars)
    return (; fig, axes = (; g = ax_g, b = ax_b, t = ax_t), choice, row, cache, widgets, plots,
              readout, caveat, redraw!, table_press!)
end

# The read-out for one row: the script's own numbers, formatted as its table prints them.
function _nd_readout(r, flat)
    R, S = r.row, r.row.net.S_base
    fl = R.flowed
    lines = String[r.label,
                   "loads      $(_NDR.LOAD_NAMES[r.loads])",
                   "free       $(_NDR._cost(R.ed.cost))   $(_NDR._gens(R.ed.P, S))",
                   "  to flow  " * (fl.outcome === :secure ?
                                    @sprintf("%s  losses %.2f MW, load shift %+.2f MW",
                                             _NDR._cost(fl.cost), fl.losses * S, fl.load_shift * S) :
                                    "REFUSED: " * _NDR._refusal(R.flow_detail)),
                   "DC         $(_NDR._cost(R.dc.cost)) ($(_NDR._delta(R.dc.cost - R.ed.cost)))   " *
                   "$(_NDR._gens(R.dc.P, S))",
                   "  binds    $(_NDR._binds(R.dc))"]
    a = R.ac
    if a.outcome === :locally_optimal
        push!(lines, "AC         $(_NDR._cost(a.cost)) ($(_NDR._delta(a.cost - R.ed.cost)))   " *
                     "$(_NDR._gens(a.P, S))",
              "  binds    $(_NDR._binds(a))",
              @sprintf("  losses   %.2f MW, load shift %+.2f MW", a.losses * S, a.load_shift * S))
    else
        push!(lines, "AC         no point found — Ipopt's local word,",
              "           $(first(split(a.status, " / ")))")
    end
    if flat !== nothing
        push!(lines, @sprintf("flat run   drift %.1e, Pm gap %.1e pu", flat.drift, flat.Pm_gap),
              @sprintf("G1 reserve %.2f MW in the engine (schedule's %.2f)",
                       flat.headroom[1] * S, flat.headroom_schedule[1] * S))
    else
        push!(lines, "flat run   none: no AC optimum to hand over")
    end
    return join(lines, '\n')
end

"""
    network_dispatch(; fixture = :L89, loads = :constant_power, answer = :ac) -> window

Open the network-dispatch window (M11 step 5): `scripts/network_dispatch.jl` drawn. For each
case9 fixture — published, three INVENTED line ratings, the loads at 1.5× and 1.75× — the
network-free dispatch beside the DC and the AC network optimum, as a table you can click;
for the fixture selected, the answer chosen drawn on the grid (each line by its loading, a
line at its limit and a bus on the voltage floor in red, every generator's output) and the
three outputs side by side. Controls: the load model, DC or AC on the grid, the fixture.

Builds by running the script's solves and its eleven flat runs once.

    julia --project=ui -e "using GridSimUI; wait_for_close(network_dispatch())"
"""
function network_dispatch(; kwargs...)
    GLMakie.activate!(; visible = true, title = "GridSim — network dispatch")
    win = _build_network_dispatch_window(; kwargs...)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    network_dispatch_render(; path, fixture = :L89, loads = :constant_power, answer = :ac) -> path

Build the network-dispatch window offscreen and save a PNG — how it is checked without a
screen.
"""
function network_dispatch_render(; path::AbstractString, kwargs...)
    GLMakie.activate!(; visible = false)
    win = _build_network_dispatch_window(; kwargs...)
    mkpath(dirname(path))
    Makie.colorbuffer(win.fig)          # one throwaway frame (the text atlas, as elsewhere)
    save(path, win.fig)
    return path
end
