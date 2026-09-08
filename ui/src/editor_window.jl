# The scenario editor window: place buses on a map, attach machines and loads,
# draw lines between buses, edit every number, save, load, and hand the result to
# the multi-machine window.
#
# It is a fourth kind of window and not a mode of the other three, because it is
# the only one that does not have an engine: the real-time windows drive one, the
# playback window is handed the output of one, and this one produces the MODEL
# they all start from. Nothing here integrates anything. `run` builds a
# `NetworkModel` through the ordinary constructor and calls `launch` on it — the
# same call a REPL user makes — so the editor can never run a model the
# constructor would refuse.
#
# THE CANVAS IS A MAKIE AXIS, and "map" means whatever is under the points. By
# default that is a plain plane; hand `background` a PNG (a country outline, a
# scan of a one-line diagram) and `extent = (x0, x1, y0, y1)` and the buses sit
# on it in its coordinates, which are the ones the `[layout]` table then records.
# GeoMakie/Tyler tiles are roadmap item 8 and are deliberately not pulled in here:
# an image is enough to place a bus on Iberia, and it costs no dependency.
#
# EVERY MOUSE ACTION LANDS IN A DATA-COORDINATE FUNCTION (`canvas_press!`,
# `canvas_drag!`, `canvas_release!`) that the window also returns, and the tests
# drive those directly — the same choice the real-time windows made with
# `b.clicks[]`: assert the handler a click runs, not a simulation of the mouse.
# The Axis's own left-drag rectangle zoom is switched off (it would fight the bus
# drag); right-drag still pans and the wheel still zooms.
#
# THE PROPERTY PANEL IS REBUILT PER SELECTION rather than hidden and shown: a
# Makie `Textbox` has no `visible`, and a machine has twelve editable numbers where
# a branch has three. The boxes are read on "apply" from what is displayed, not from
# the submitted string, so a user need not press Enter in each of twelve boxes.
#
# M6 STEP 5 ADDED TWO THINGS THAT ARE NOT EDITING. The **reference bus** is drawn
# on the map and chosen from the panel, because the scenario file refuses to invent
# one (m6-context.md D8) and a draft that has not declared one still has a derived
# one — drawing it is what keeps that choice from being made silently at a save.
# And **solve** runs `ac_powerflow` on the drawing: bus colour is |V|, an arrow per
# branch is the direction P leaves its `from` bus, and the read-out carries the
# slack's pickup. Every redraw clears that overlay, so a flow arrow cannot outlive
# the model it was solved from, and a refused solve — the COMMON case on a
# hand-drawn scenario — leaves the drawing exactly as it was, with the solver's own
# words in the status line.

const EDITOR_TOOLS = (:select, :bus, :machine, :load, :branch, :delete)

# Bus, machine and load glyph positions from the layout. Machines sit above their
# bus (spread sideways when a bus has several), the load below, at an offset that
# scales with the picture so a compact layout and a country-sized one both read.
function _glyph_offset(ed::ScenarioEditor)
    isempty(ed.layout) && return 0.08
    xs = [xy[1] for xy in values(ed.layout)]; ys = [xy[2] for xy in values(ed.layout)]
    return 0.08 * max(1.0, maximum(xs) - minimum(xs), maximum(ys) - minimum(ys))
end

function _glyph_positions(ed::ScenarioEditor)
    off = _glyph_offset(ed)
    buses = Dict{Symbol,Point2f}(id => Point2f(xy[1], xy[2]) for (id, xy) in ed.layout)
    machines = Dict{Symbol,Point2f}()
    per_bus = Dict{Symbol,Vector{Symbol}}()
    for m in ed.machines
        push!(get!(per_bus, m.bus, Symbol[]), m.id)
    end
    for (bus, ids) in per_bus
        n = length(ids)
        for (k, id) in enumerate(ids)
            p = buses[bus]
            machines[id] = Point2f(p[1] + (k - (n + 1) / 2) * 0.9off, p[2] + off)
        end
    end
    loads = Dict{Symbol,Point2f}(l.id => Point2f(buses[l.bus][1], buses[l.bus][2] - off)
                                 for l in ed.loads)
    return (; buses, machines, loads, off)
end

# Nearest element within `radius` of `(x, y)`, small glyphs first so a machine
# sitting near its bus is what a click on the machine selects.
function _hit(ed::ScenarioEditor, x::Real, y::Real, radius::Real)
    g = _glyph_positions(ed)
    p = Point2f(x, y)
    best = nothing; bestd = Float64(radius)
    for (kind, tbl) in ((:machine, g.machines), (:load, g.loads), (:bus, g.buses))
        for (id, q) in tbl
            d = hypot(q[1] - p[1], q[2] - p[2])
            if d < bestd
                best = (kind, id); bestd = d
            end
        end
        best === nothing || return best
    end
    # Branches last: distance to the segment, only if nothing else was close.
    for br in ed.branches
        a = g.buses[br.from]; b = g.buses[br.to]
        ab = b - a; ap = p - a
        t = clamp((ap[1] * ab[1] + ap[2] * ab[2]) /
                  max(ab[1]^2 + ab[2]^2, eps(Float32)), 0f0, 1f0)
        q = a + t * ab
        d = hypot(q[1] - p[1], q[2] - p[2])
        d < bestd && (best = (:branch, br.id); bestd = d)
    end
    return best
end

_fmt(v::Real) = @sprintf("%g", v)

function _build_editor_window(ed::ScenarioEditor; kwargs...)
    themed(() -> _build_editor_window_impl(ed; kwargs...))
end

function _build_editor_window_impl(ed::ScenarioEditor;
                                   title::AbstractString = "GridSim — scenario editor",
                                   background::Union{Nothing,AbstractString} = nothing,
                                   extent = nothing,
                                   runner = launch)
    fig = Figure(size = (1400, 900))
    ax = Axis(fig[1, 1]; title = title, aspect = DataAspect(),
              xlabel = "map x", ylabel = "map y")
    deregister_interaction!(ax, :rectanglezoom)

    if background !== nothing
        img = Makie.FileIO.load(background)
        x0, x1, y0, y1 = extent === nothing ? (0.0, Float64(size(img, 2)),
                                               0.0, Float64(size(img, 1))) : extent
        image!(ax, x0 .. x1, y0 .. y1, rotr90(img); alpha = 0.85)
    end

    # ---- the picture, as observables `refresh!` rewrites -----------------------
    branch_segs = Observable(Point2f[])
    branch_labels = Observable(Tuple{String,Point2f}[])
    stub_segs = Observable(Point2f[])
    bus_pts = Observable(Point2f[])
    bus_labels = Observable(Tuple{String,Point2f}[])
    mach_pts = Observable(Point2f[])
    mach_labels = Observable(Tuple{String,Point2f}[])
    load_pts = Observable(Point2f[])
    load_labels = Observable(Tuple{String,Point2f}[])
    sel_pts = Observable(Point2f[])
    sel_segs = Observable(Point2f[])
    pend_pts = Observable(Point2f[])
    # M6 step 5. The reference bus is drawn because it is a DISPATCH choice
    # (m5-context.md D13) that the scenario file will not invent (m6-context.md D8)
    # — and because a draft that has not declared one still HAS one, derived by
    # `NetworkModel`. Drawing the derived choice is what stops it being silent.
    slack_pts = Observable(Point2f[])
    slack_labels = Observable(Tuple{String,Point2f}[])
    # ...and the solve overlay: a coloured halo per bus, an arrow per branch. Both
    # are empty except while a solved answer is on screen, and `do_refresh!` empties
    # them, so a picture of a flow can never outlive the model it was solved from.
    solved_pts = Observable(Point2f[])
    solved_V = Observable(Float64[])
    solved_range = Observable((0.95, 1.05))
    flow_pts = Observable(Point2f[])
    flow_dirs = Observable(Vec2f[])
    # The marker angle is DERIVED from the direction vector rather than stored beside
    # it: a rotation and a direction that can disagree are two sources of truth about
    # which way the power goes, and the tests read the vector.
    flow_rot = lift(ds -> Float32[atan(d[2], d[1]) for d in ds], flow_dirs)

    linesegments!(ax, sel_segs; color = (C_CURSOR, 0.5), linewidth = 8)
    scatter!(ax, slack_pts; marker = :diamond, markersize = 34, color = :transparent,
             strokecolor = C_INERTIA, strokewidth = 2.5)
    scatter!(ax, solved_pts; marker = :circle, markersize = 30, color = solved_V,
             colormap = :viridis, colorrange = solved_range, strokewidth = 0)
    linesegments!(ax, branch_segs; color = C_MUTED, linewidth = 2.5)
    linesegments!(ax, stub_segs; color = (C_MUTED, 0.7), linewidth = 1.2)
    scatter!(ax, sel_pts; marker = :circle, markersize = 36,
             color = (C_CURSOR, 0.25), strokecolor = C_CURSOR, strokewidth = 2)
    scatter!(ax, pend_pts; marker = :circle, markersize = 36,
             color = (C_AGGREGATE, 0.2), strokecolor = C_AGGREGATE, strokewidth = 2)
    scatter!(ax, bus_pts; marker = :rect, markersize = 16, color = :white,
             strokecolor = :black, strokewidth = 1.5)
    scatter!(ax, mach_pts; marker = :circle, markersize = 20, color = C_SWING,
             strokecolor = :black, strokewidth = 1)
    scatter!(ax, load_pts; marker = :dtriangle, markersize = 20, color = C_AGGREGATE,
             strokecolor = :black, strokewidth = 1)
    text!(ax, bus_labels; offset = (10, 6), align = (:left, :bottom), fontsize = 13,
          font = :bold)
    text!(ax, mach_labels; offset = (0, 13), align = (:center, :bottom), fontsize = 11)
    text!(ax, load_labels; offset = (0, -13), align = (:center, :top), fontsize = 11)
    text!(ax, branch_labels; align = (:center, :bottom), offset = (0, 4), fontsize = 10,
          color = C_MUTED)
    text!(ax, slack_labels; offset = (0, -20), align = (:center, :top), fontsize = 11,
          color = C_INERTIA, font = :bold)
    # Direction, not magnitude: the head says which way P leaves the branch's `from`
    # bus, and the branch label carries the MW. A ROTATED SCATTER MARKER rather than
    # `arrows2d!`, which is the natural recipe and CANNOT BE BUILT EMPTY — with no
    # points it converts its mesh from a `Vector{Any}` and throws — and empty is this
    # overlay's resting state. The precompile workload caught that, on a window
    # nobody had solved; every other plot here is empty at construction too.
    scatter!(ax, flow_pts; marker = :rtriangle, markersize = 17, rotation = flow_rot,
             color = C_SWING, strokecolor = :white, strokewidth = 0.5)

    # ---- controls column ----------------------------------------------------------
    gc = fig[1, 2] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 2, Fixed(390))

    tool = Observable(:select)
    pending = Observable{Union{Nothing,Symbol}}(nothing)   # the branch tool's first bus
    drag = Ref{Union{Nothing,Symbol}}(nothing)
    status = Observable("")
    hint = Observable("")

    section_label!(gc[1, 1], "tool")
    gt = gc[2, 1] = GridLayout()
    tool_buttons = Dict{Symbol,Button}()
    for (i, t) in enumerate(EDITOR_TOOLS)
        b = Button(gt[(i - 1) ÷ 3 + 1, (i - 1) % 3 + 1]; label = String(t))
        on(b.clicks) do _
            tool[] = t
        end
        tool_buttons[t] = b
    end
    on(tool; update = true) do t
        for (k, b) in tool_buttons
            b.label[] = (k === t ? "▸ " : "") * String(k)
        end
        pending[] = nothing
        hint[] = t === :select ? "click to select, drag a bus to move it" :
                 t === :bus ? "click the map to place a bus" :
                 t === :machine ? "click a bus to attach a machine" :
                 t === :load ? "click a bus to attach a load" :
                 t === :branch ? "click two buses to connect them" :
                 "click an element to delete it"
    end
    Label(gc[3, 1], hint; halign = :left, tellwidth = false, fontsize = 12, color = C_MUTED)

    # ---- the property panel, rebuilt per selection (file header) --------------------
    section_label!(gc[4, 1], "selected")
    panel = gc[5, 1] = GridLayout()
    rowgap!(panel, 2)
    prows = Any[]
    pboxes = Dict{Symbol,Textbox}()
    pbuttons = Dict{Symbol,Button}()

    refresh! = Ref{Function}(() -> nothing)

    function rebuild_panel!()
        foreach(delete!, prows); empty!(prows); empty!(pboxes); empty!(pbuttons)
        sel = ed.selection
        if sel === nothing
            push!(prows, Label(panel[1, 1], "nothing selected"; halign = :left,
                               tellwidth = false, color = C_MUTED))
            return
        end
        kind, id = sel
        x = element(ed, kind, id)
        where = kind === :bus ? "" :
                kind === :branch ? @sprintf("%s – %s", x.from, x.to) : "at bus $(x.bus)"
        push!(prows, Label(panel[1, 1:4], @sprintf("%s  %s  %s", kind, id, where);
                           halign = :left, tellwidth = false, font = :bold))
        # TWO FIELDS PER ROW, not one. A machine has twelve numbers since M6 step 5,
        # and a single column of twelve ran straight off the bottom of a 900-px
        # window and drew `Q_max`, `apply` and `delete` on top of the file buttons —
        # the same failure the original build hit at nine fields, met again three
        # fields later. Shrinking the rows bought 84 px and was not enough; the fix
        # is the shape, so the count can grow again without the window breaking.
        r = 2
        col = 1
        function row!(name, value)
            push!(prows, Label(panel[r, col]; text = name, halign = :right,
                               tellwidth = true, font = MONO_FONT, fontsize = 12))
            tb = Textbox(panel[r, col + 1]; stored_string = value, width = 108,
                         height = 24, fontsize = 12, tellwidth = false)
            push!(prows, tb)
            col == 1 ? (col = 3) : (col = 1; r += 1)
            return tb
        end
        # `id` takes a row of its own — it is the only text field among numbers, and
        # a rename sitting beside a reactance reads as one more parameter.
        pboxes[:id] = row!("id", String(id))
        col == 1 || (col = 1; r += 1)
        for f in editable_fields(kind)
            pboxes[f] = row!(String(f), _fmt(getfield(x, f)))
        end
        col == 1 || (col = 1; r += 1)
        b_apply = Button(panel[r, 1:4]; label = "apply")
        on(b_apply.clicks) do _
            apply_panel!()
        end
        push!(prows, b_apply); pbuttons[:apply] = b_apply
        r += 1
        # The reference bus is chosen HERE, on a selected bus, and not from a list in
        # the bar: it is a property of one bus, and every other property of one bus
        # is edited in this panel. "release" gives the declaration back to
        # `NetworkModel`'s derivation, which is what a fresh draft carries — both
        # directions reachable, because a user who declared the wrong one otherwise
        # has to delete the bus to undo it.
        if kind === :bus
            declared = ed.slack === id
            b_slack = Button(panel[r, 1:4];
                             label = declared ? "release slack" : "make slack")
            on(b_slack.clicks) do _
                s = ed.selection
                (s === nothing || s[1] !== :bus) && return
                if ed.slack === s[2]
                    set_slack!(ed, nothing)
                    status[] = "slack released — derived from the model again"
                else
                    set_slack!(ed, s[2])
                    status[] = "slack bus is $(s[2])"
                end
                last_sel[] = :unset          # the button's own label has to change
                refresh![]()
            end
            push!(prows, b_slack); pbuttons[:slack] = b_slack
            r += 1
        end
        b_del = Button(panel[r, 1:4]; label = "delete")
        on(b_del.clicks) do _
            s = ed.selection
            s === nothing && return
            remove!(ed, s...)
            refresh![]()
        end
        push!(prows, b_del); pbuttons[:delete] = b_del
        return
    end

    function apply_panel!()
        sel = ed.selection
        sel === nothing && return
        kind, id = sel
        try
            for f in editable_fields(kind)
                s = strip(pboxes[f].displayed_string[])
                v = tryparse(Float64, s)
                v === nothing && throw(ArgumentError("`$f`: \"$s\" is not a number."))
                set_field!(ed, kind, id, f, v)
            end
            new_id = Symbol(strip(pboxes[:id].displayed_string[]))
            new_id === id || rename!(ed, kind, id, new_id)
            status[] = "applied to $kind $(ed.selection[2])"
        catch err
            err isa ArgumentError || rethrow()
            status[] = "not applied — " * err.msg
        end
        refresh![]()
    end

    # ---- the scenario bar under the canvas: bases, file, run, status ---------------
    # Under the canvas and not in the column: with nine machine fields the column
    # already reaches the bottom of a 900-px window, and the first render had the
    # file and run controls clipped off the frame. A bar takes width, which the
    # canvas has to spare.
    gs = fig[2, 1:2] = GridLayout(tellwidth = false)
    Label(gs[1, 1], "name"; halign = :right, font = MONO_FONT, fontsize = 13)
    tb_name = Textbox(gs[1, 2]; stored_string = ed.name, placeholder = "scenario name",
                      width = 170, tellwidth = true)
    Label(gs[1, 3], "S_base"; halign = :right, font = MONO_FONT, fontsize = 13)
    tb_sbase = Textbox(gs[1, 4]; stored_string = _fmt(ed.S_base), width = 80, tellwidth = true)
    Label(gs[1, 5], "f0"; halign = :right, font = MONO_FONT, fontsize = 13)
    tb_f0 = Textbox(gs[1, 6]; stored_string = _fmt(ed.f0), width = 70, tellwidth = true)
    Label(gs[1, 7], "file"; halign = :right, font = MONO_FONT, fontsize = 13)
    tb_path = Textbox(gs[1, 8]; placeholder = "scenario.toml", width = 300, tellwidth = true)
    # "save file" / "open file", not "save" / "load": `load` is also a TOOL two
    # rows up, and a button that says only "load" beside it is a trap.
    b_save = Button(gs[1, 9]; label = "save file", width = 90)
    b_load = Button(gs[1, 10]; label = "open file", width = 90)
    b_fit = Button(gs[1, 11]; label = "fit view", width = 80)
    b_solve = Button(gs[1, 12]; label = "solve", width = 70)
    b_run = Button(gs[1, 13]; label = "run ▶", width = 90)
    validation_text = Observable("")
    solve_text = Observable("")
    Label(gs[2, 1:13], validation_text; halign = :left, tellwidth = false, fontsize = 12)
    Label(gs[3, 1:13], solve_text; halign = :left, tellwidth = false, fontsize = 12,
          color = C_INERTIA, font = MONO_FONT)
    # A REFUSED SOLVE IS THE COMMON PATH, not the rare one — a hand-drawn scenario
    # meets the |V| band long before it meets a convergence failure — and the
    # solver's refusals are several sentences long. So the status line WRAPS, at a
    # row whose height is fixed: a message that grows must not push the canvas
    # around, and the observable holds the whole text either way.
    # `word_wrap`, a Bool — a Label BLOCK has no `word_wrap_width`; that is the
    # `text!` primitive's attribute, and passing it here is an error rather than a
    # no-op. The block wraps to the width of the cell it is in.
    Label(gs[4, 1:13], status; halign = :left, tellwidth = false, tellheight = false,
          fontsize = 12, color = C_SWING, word_wrap = true, justification = :left)
    rowsize!(gs, 4, Fixed(52))
    rowgap!(gs, 2)

    # Bases and name are read whenever the model is built or saved, so a user need
    # not submit each box; a bad number is reported and the old value kept.
    function take_bases!()
        ed.name = strip(tb_name.displayed_string[])
        for (tb, f) in ((tb_sbase, :S_base), (tb_f0, :f0))
            v = tryparse(Float64, strip(tb.displayed_string[]))
            v === nothing && throw(ArgumentError("`$f`: \"$(tb.displayed_string[])\" is not a number."))
            setfield!(ed, f, v)
        end
    end

    function file_path()
        p = strip(tb_path.displayed_string[])
        isempty(p) && throw(ArgumentError("no file name — type one in the `file` box."))
        return String(p)
    end
    on(b_save.clicks) do _
        try
            take_bases!()
            p = save!(ed, file_path())
            status[] = "saved " * p
        catch err
            err isa ArgumentError || rethrow()
            status[] = "not saved — " * err.msg
        end
        refresh![]()
    end
    on(b_load.clicks) do _
        try
            p = file_path()
            load!(ed, p)
            tb_name.displayed_string[] = ed.name
            tb_sbase.displayed_string[] = _fmt(ed.S_base)
            tb_f0.displayed_string[] = _fmt(ed.f0)
            status[] = "opened " * p
            fit!()
        catch err
            err isa ArgumentError || rethrow()
            status[] = "not opened — " * err.msg
        end
        refresh![]()
    end
    on(b_fit.clicks) do _
        fit!()
    end
    # The last thing a run does before it exists is go through the constructor. The
    # runner is a parameter so the offscreen tests can hand in a stub and assert
    # what it was given, instead of opening a live window in a test.
    last_run = Ref{Any}(nothing)
    on(b_run.clicks) do _
        try
            take_bases!()
            net = build_model(ed)
            last_run[] = runner(net)
            status[] = @sprintf("running — %d machines, %d lines", length(net.machines),
                                length(net.branches))
        catch err
            err isa ArgumentError || rethrow()
            status[] = "cannot run — " * err.msg
        end
    end

    # ---- the steady-state solve, drawn on the map ----------------------------------
    # A steady state is a function of a model, not an engine, so this is a direct
    # call and not a trip through the mode router (`m6-tasks.md` step 2). What it
    # adds to the picture is the part a list of numbers cannot carry: WHERE the
    # voltage sags and WHICH WAY the power goes.
    last_solve = Ref{Any}(nothing)
    function solve_now!()
        try
            take_bases!()
            net = build_model(ed)
            s = ac_powerflow(net)
            # Refresh FIRST, then draw: the refresh clears the overlay, so the only
            # way a flow arrow can be on screen is that the model under it solved.
            refresh![]()
            last_solve[] = s
            g = _glyph_positions(ed)
            solved_pts[] = [g.buses[b] for b in s.buses]
            solved_V[] = copy(s.Vm)
            lo, hi = extrema(s.Vm)
            # A band that is never narrower than 0.02 pu: on a flat case every bus is
            # 1.0 and a range of zero would paint the whole map one arbitrary colour.
            mid = (lo + hi) / 2; half = max((hi - lo) / 2, 0.01)
            solved_range[] = (mid - half, mid + half)

            off = _glyph_offset(ed)
            mids = [(g.buses[s.from[e]] + g.buses[s.to[e]]) / 2 for e in eachindex(s.branches)]
            pts = Point2f[]; dirs = Vec2f[]
            for e in eachindex(s.branches)
                a = g.buses[s.from[e]]
                d = g.buses[s.to[e]] - a
                n = hypot(d[1], d[2])
                n == 0 && continue                        # two buses on one point
                sgn = s.flow[e] >= 0 ? 1.0f0 : -1.0f0     # `flow` LEAVES `from`
                # NOT the midpoint: the branch's MW label is there, and the first
                # render drew the marker straight through the digits.
                push!(pts, Point2f(a[1] + 0.38f0 * d[1], a[2] + 0.38f0 * d[2]))
                push!(dirs, Vec2f(sgn * 1.1f0 * off * d[1] / n,
                                  sgn * 1.1f0 * off * d[2] / n))
            end
            flow_pts[] = pts; flow_dirs[] = dirs
            # The numbers go on the glyphs they belong to — the arrow gives direction
            # and the label gives the magnitude, so neither has to carry both.
            branch_labels[] = [(@sprintf("%s %.1f MW", id, abs(s.flow[e]) * net.S_base),
                                mids[e]) for (e, id) in pairs(s.branches)]
            bus_labels[] = [(@sprintf("%s %.3f pu", b, s.Vm[v]), g.buses[b])
                            for (v, b) in pairs(s.buses)]

            gen = bus_generation(s, s.slack)
            sched = sum((m.P0 for m in ed.machines if m.bus === s.slack); init = 0.0)
            # A lossless network sums to about -1e-16 pu, which `%.2f` prints as
            # "-0.00 MW" — a minus sign in front of a quantity that cannot be
            # negative. Anything under a milliwatt is zero at this precision, and
            # saying so is better than showing the sign of a rounding error.
            loss_mw = sum(s.loss) * net.S_base
            abs(loss_mw) < 1.0e-6 && (loss_mw = 0.0)
            solve_text[] = @sprintf("solved — slack %s picks up %+.2f MW against a schedule of %+.1f MW; |V| %.4f–%.4f pu; losses %.2f MW; residual %.1e",
                                    s.slack, gen.P * net.S_base, sched, lo, hi,
                                    loss_mw, s.residual) *
                          (isempty(s.limited) ? "" :
                           "; held on a reactive limit: " * join(s.limited, ", "))
            status[] = "solved"
        catch err
            # BOTH kinds, and this is not tidiness: `ac_powerflow` refuses a bad
            # dispatch with an `ArgumentError` and a bad ANSWER — outside the voltage
            # band, unconverged, still switching — with an `ErrorException`, and the
            # second is the one a hand-drawn scenario meets first.
            (err isa ArgumentError || err isa ErrorException) || rethrow()
            refresh![]()           # the map goes back to the drawing, still editable
            status[] = "cannot solve — " * err.msg
        end
        return nothing
    end
    on(b_solve.clicks) do _
        solve_now!()
    end

    # ---- fit the view to the layout ------------------------------------------------
    function fit!()
        if isempty(ed.layout)
            limits!(ax, -1.5, 1.5, -1.5, 1.5)
            return
        end
        xs = [xy[1] for xy in values(ed.layout)]; ys = [xy[2] for xy in values(ed.layout)]
        off = _glyph_offset(ed)
        pad = 2.5off
        limits!(ax, minimum(xs) - pad, maximum(xs) + pad, minimum(ys) - pad, maximum(ys) + pad)
    end

    # ---- redraw everything from `ed` -----------------------------------------------
    last_sel = Ref{Any}(:unset)
    function do_refresh!()
        g = _glyph_positions(ed)
        segs = Point2f[]; blabels = Tuple{String,Point2f}[]
        for br in ed.branches
            a = g.buses[br.from]; b = g.buses[br.to]
            push!(segs, a, b)
            push!(blabels, (String(br.id), (a + b) / 2))
        end
        branch_segs[] = segs; branch_labels[] = blabels
        stubs = Point2f[]
        for m in ed.machines
            push!(stubs, g.buses[m.bus], g.machines[m.id])
        end
        for l in ed.loads
            push!(stubs, g.buses[l.bus], g.loads[l.id])
        end
        stub_segs[] = stubs
        bus_pts[] = [g.buses[b.id] for b in ed.buses]
        bus_labels[] = [(String(b.id), g.buses[b.id]) for b in ed.buses]
        mach_pts[] = [g.machines[m.id] for m in ed.machines]
        mach_labels[] = [(@sprintf("%s %+.0f MW", m.id, m.P0), g.machines[m.id])
                         for m in ed.machines]
        load_pts[] = [g.loads[l.id] for l in ed.loads]
        load_labels[] = [(@sprintf("%s %.0f MW", l.id, l.P0), g.loads[l.id])
                         for l in ed.loads]

        sel = ed.selection
        sel_pts[] = sel === nothing ? Point2f[] :
                    sel[1] === :bus ? [g.buses[sel[2]]] :
                    sel[1] === :machine ? [g.machines[sel[2]]] :
                    sel[1] === :load ? [g.loads[sel[2]]] : Point2f[]
        if sel !== nothing && sel[1] === :branch
            br = element(ed, :branch, sel[2])
            sel_segs[] = [g.buses[br.from], g.buses[br.to]]
        else
            sel_segs[] = Point2f[]
        end
        pend_pts[] = pending[] === nothing ? Point2f[] : [g.buses[pending[]]]

        # The reference bus, declared or derived, and SAID to be which. A derived
        # slack is still a dispatch choice; drawing it is what stops it being made
        # silently at the moment of a save (m6-context.md D8).
        es = effective_slack(ed)
        if es === nothing || !haskey(g.buses, es)
            slack_pts[] = Point2f[]; slack_labels[] = Tuple{String,Point2f}[]
        else
            slack_pts[] = [g.buses[es]]
            slack_labels[] = [(ed.slack === nothing ? "slack (derived)" : "slack",
                               g.buses[es])]
        end

        # Any redraw at all invalidates a solved overlay, because a redraw is what
        # every edit ends in. A flow arrow over a model that has since changed is
        # not a stale picture, it is a wrong one.
        last_solve[] = nothing
        solved_pts[] = Point2f[]; solved_V[] = Float64[]
        flow_pts[] = Point2f[]; flow_dirs[] = Vec2f[]
        solve_text[] = ""

        validation_text[] = validation(ed).message
        if sel != last_sel[]
            rebuild_panel!()
            last_sel[] = sel
        end
        return
    end
    refresh![] = do_refresh!

    # ---- the canvas actions, in DATA coordinates --------------------------------
    function canvas_press!(x::Real, y::Real)
        radius = 0.55 * _glyph_offset(ed)
        hit = _hit(ed, x, y, radius)
        t = tool[]
        try
            if t === :select
                ed.selection = hit
                drag[] = (hit !== nothing && hit[1] === :bus) ? hit[2] : nothing
            elseif t === :bus
                id = add_bus!(ed, x, y)
                ed.selection = (:bus, id)
                status[] = "placed bus $id"
            elseif t === :machine || t === :load
                if hit === nothing || hit[1] !== :bus
                    status[] = "click a bus to attach a $(t)"
                else
                    id = t === :machine ? add_machine!(ed, hit[2]) : add_load!(ed, hit[2])
                    ed.selection = (t, id)
                    status[] = "attached $t $id to bus $(hit[2])"
                end
            elseif t === :branch
                if hit === nothing || hit[1] !== :bus
                    status[] = "click a bus to start a line"
                elseif pending[] === nothing
                    pending[] = hit[2]
                    status[] = "line from $(hit[2]) — now click the other bus"
                elseif pending[] === hit[2]
                    pending[] = nothing
                    status[] = "line cancelled"
                else
                    id = add_branch!(ed, pending[], hit[2])
                    ed.selection = (:branch, id)
                    status[] = "connected $(pending[]) – $(hit[2]) as $id"
                    pending[] = nothing
                end
            elseif t === :delete
                if hit === nothing
                    status[] = "nothing there to delete"
                else
                    remove!(ed, hit...)
                    status[] = "deleted $(hit[1]) $(hit[2])"
                end
            end
        catch err
            err isa ArgumentError || rethrow()
            status[] = err.msg
            # A refused line does not leave its first bus armed: the next click
            # would otherwise start a line nobody began (the test caught it).
            pending[] = nothing
        end
        do_refresh!()
        return hit
    end
    function canvas_drag!(x::Real, y::Real)
        d = drag[]
        d === nothing && return false
        move_bus!(ed, d, x, y)
        do_refresh!()
        return true
    end
    canvas_release!() = (drag[] = nothing; nothing)

    # ---- the mouse, routed into the three above --------------------------------
    on(events(ax.scene).mousebutton; priority = 10) do ev
        ev.button == Mouse.left || return Consume(false)
        if ev.action == Mouse.press
            is_mouseinside(ax.scene) || return Consume(false)
            p = mouseposition(ax.scene)
            canvas_press!(p[1], p[2])
            return Consume(true)
        elseif ev.action == Mouse.release
            was = drag[] !== nothing
            canvas_release!()
            return Consume(was)
        end
        return Consume(false)
    end
    on(events(ax.scene).mouseposition; priority = 10) do _
        drag[] === nothing && return Consume(false)
        p = mouseposition(ax.scene)
        canvas_drag!(p[1], p[2])
        return Consume(true)
    end

    fit!()
    do_refresh!()

    widgets = (; tool_buttons, panel_boxes = pboxes, panel_buttons = pbuttons,
                 tb_name, tb_sbase, tb_f0, tb_path, b_save, b_load, b_fit, b_solve, b_run)
    # The canvas's observables, so a test can ask what the picture holds rather
    # than what the state holds — the two are meant to agree, and only reading
    # both can say so.
    plots = (; bus_pts, mach_pts, load_pts, branch_segs, stub_segs, sel_pts, sel_segs,
               pend_pts, slack_pts, slack_labels, bus_labels, branch_labels,
               solved_pts, solved_V, flow_pts, flow_dirs)
    return (; fig, ax, ed, tool, pending, status, validation_text, solve_text, widgets,
              plots, last_run, last_solve,
              refresh! = do_refresh!, fit!, solve_now!, canvas_press!, canvas_drag!,
              canvas_release!, rebuild_panel!)
end

"""
    editor(net = nothing; layout = nothing, file = nothing, background = nothing,
           extent = nothing) -> window

Open the scenario editor. Start from a model (`net`, with an optional `Layout`),
from a scenario `file` written by `write_scenario`, or from nothing. `background`
is a PNG drawn under the canvas — the map — and `extent = (x0, x1, y0, y1)` its
coordinates; a bus placed on it is recorded in those coordinates.

The `run` button builds the model and opens the multi-machine window on it —
`launch(net)`, the same call a REPL makes. Keep the process alive with
`wait_for_close(win)`:

    julia --project=ui -e "using GridSimUI, GridSim; wait_for_close(editor(three_machine_ring()))"
"""
function editor(net::Union{Nothing,NetworkModel} = nothing;
                layout = nothing, file::Union{Nothing,AbstractString} = nothing,
                background::Union{Nothing,AbstractString} = nothing, extent = nothing)
    ed = if file !== nothing
        load!(ScenarioEditor(), file)
    elseif net !== nothing
        ScenarioEditor(net; layout = layout)
    else
        ScenarioEditor()
    end
    GLMakie.activate!(; visible = true, title = "GridSim — scenario editor")
    win = _build_editor_window(ed; background = background, extent = extent)
    file === nothing || (win.widgets.tb_path.displayed_string[] = String(file))
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    editor_render(; path, net = three_machine_ring(), layout = nothing,
                  select = nothing, solve = false, background = nothing,
                  extent = nothing) -> path

Build the same editor window offscreen over `net` and save a PNG to `path` — how
the window is checked in a session with no screen. `select = (kind, id)` opens
the property panel on that element so the render shows it; `solve = true` runs the
**solve** button's own handler first, so the PNG shows the voltage colours, the
flow arrows and the read-out — or, if the case is refused, the status line saying
so, which is the same picture a user gets.
"""
function editor_render(; path::AbstractString,
                       net::NetworkModel = three_machine_ring(),
                       layout = nothing, select = nothing, solve::Bool = false,
                       background::Union{Nothing,AbstractString} = nothing,
                       extent = nothing,
                       title::AbstractString = "GridSim — scenario editor")
    GLMakie.activate!(; visible = false)
    ed = ScenarioEditor(net; layout = layout)
    ed.selection = select
    win = _build_editor_window(ed; background = background, extent = extent, title = title)
    win.refresh!()
    solve && win.solve_now!()
    mkpath(dirname(path))
    # One throwaway frame first: the first offscreen frame of a fresh window drew
    # three of nine text boxes with squashed glyphs (the atlas had not caught up),
    # and the second frame is clean.
    Makie.colorbuffer(win.fig)
    save(path, win.fig)
    return path
end
