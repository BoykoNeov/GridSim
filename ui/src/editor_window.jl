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
# Makie `Textbox` has no `visible`, and a machine has nine editable numbers where
# a branch has two. The boxes are read on "apply" from what is displayed, not from
# the submitted string, so a user need not press Enter in each of nine boxes.

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

    linesegments!(ax, sel_segs; color = (C_CURSOR, 0.5), linewidth = 8)
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

    # ---- controls column ----------------------------------------------------------
    gc = fig[1, 2] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 2, Fixed(340))

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
    rowgap!(panel, 4)
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
        push!(prows, Label(panel[1, 1:2], @sprintf("%s  %s  %s", kind, id, where);
                           halign = :left, tellwidth = false, font = :bold))
        r = 2
        function row!(name, value)
            push!(prows, Label(panel[r, 1], name; halign = :right, tellwidth = true,
                               font = MONO_FONT, fontsize = 13))
            # Compact rows: nine of these must fit above the bar with the two
            # buttons beneath them (they did not, at the default height).
            tb = Textbox(panel[r, 2]; stored_string = value, width = 150, height = 28,
                         fontsize = 13, tellwidth = false)
            push!(prows, tb)
            r += 1
            return tb
        end
        pboxes[:id] = row!("id", String(id))
        for f in editable_fields(kind)
            pboxes[f] = row!(String(f), _fmt(getfield(x, f)))
        end
        b_apply = Button(panel[r, 1:2]; label = "apply")
        on(b_apply.clicks) do _
            apply_panel!()
        end
        push!(prows, b_apply); pbuttons[:apply] = b_apply
        b_del = Button(panel[r + 1, 1:2]; label = "delete")
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
    b_run = Button(gs[1, 12]; label = "run ▶", width = 90)
    validation_text = Observable("")
    Label(gs[2, 1:12], validation_text; halign = :left, tellwidth = false, fontsize = 12)
    Label(gs[3, 1:12], status; halign = :left, tellwidth = false, fontsize = 12,
          color = C_SWING)
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
                 tb_name, tb_sbase, tb_f0, tb_path, b_save, b_load, b_fit, b_run)
    # The canvas's observables, so a test can ask what the picture holds rather
    # than what the state holds — the two are meant to agree, and only reading
    # both can say so.
    plots = (; bus_pts, mach_pts, load_pts, branch_segs, stub_segs, sel_pts, sel_segs,
               pend_pts)
    return (; fig, ax, ed, tool, pending, status, validation_text, widgets, plots, last_run,
              refresh! = do_refresh!, fit!, canvas_press!, canvas_drag!, canvas_release!,
              rebuild_panel!)
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
                  select = nothing, background = nothing, extent = nothing) -> path

Build the same editor window offscreen over `net` and save a PNG to `path` — how
the window is checked in a session with no screen. `select = (kind, id)` opens
the property panel on that element so the render shows it.
"""
function editor_render(; path::AbstractString,
                       net::NetworkModel = three_machine_ring(),
                       layout = nothing, select = nothing,
                       background::Union{Nothing,AbstractString} = nothing,
                       extent = nothing,
                       title::AbstractString = "GridSim — scenario editor")
    GLMakie.activate!(; visible = false)
    ed = ScenarioEditor(net; layout = layout)
    ed.selection = select
    win = _build_editor_window(ed; background = background, extent = extent, title = title)
    win.refresh!()
    mkpath(dirname(path))
    # One throwaway frame first: the first offscreen frame of a fresh window drew
    # three of nine text boxes with squashed glyphs (the atlas had not caught up),
    # and the second frame is clean.
    Makie.colorbuffer(win.fig)
    save(path, win.fig)
    return path
end
