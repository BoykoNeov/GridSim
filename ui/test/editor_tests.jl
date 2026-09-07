# The scenario editor (`../src/editor.jl`, `../src/editor_window.jl`).
#
# Two halves, tested two ways. The STATE is driven through its own operations,
# and what is asserted is that a scenario built by hand IS the fixture the core
# ships, record for record — the same equality the scenario-file tests use. The
# WINDOW is driven through its widgets (`b.clicks[]`, as the other windows) and
# through the data-coordinate handlers the mouse callbacks call, so the tool →
# canvas → state path is the one a click takes. One test pushes a real mouse
# event through the scene, to prove the callbacks are wired to those handlers.

const EBUILD = GridSimUI._build_editor_window
const element = GridSimUI.element

emsg(f) = try
    f()
    "NO ERROR THROWN"
catch err
    err isa ArgumentError ? err.msg : rethrow()
end

@testset "editor: a scenario built by hand is the fixture, record for record" begin
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 1.0; id = :B1); add_bus!(ed, 0.87, -0.5; id = :B2)
    add_bus!(ed, -0.87, -0.5; id = :B3)
    add_machine!(ed, :B1; id = :G1, S_rated = 300.0, H = 4.0, D = 2.0, Xd′ = 0.30,
                 E′ = 1.05, P0 = 80.0)
    add_machine!(ed, :B2; id = :G2, S_rated = 200.0, H = 3.0, D = 2.0, Xd′ = 0.20,
                 E′ = 1.03, P0 = 30.0)
    add_machine!(ed, :B3; id = :G3, S_rated = 500.0, H = 5.0, D = 2.0, Xd′ = 0.50,
                 E′ = 1.04, P0 = -110.0)
    add_branch!(ed, :B1, :B2; id = :L12, X = 0.25, rating = 500.0)
    add_branch!(ed, :B2, :B3; id = :L23, X = 0.25, rating = 500.0)
    add_branch!(ed, :B3, :B1; id = :L31, X = 0.25, rating = 500.0)
    net = build_model(ed)
    ring = three_machine_ring()
    @test net.buses == ring.buses
    @test net.machines == ring.machines
    @test net.branches == ring.branches
    v = validation(ed)
    @test v.ok && occursin("3 buses, 3 lines, 3 machines, 0 loads", v.message)
end

@testset "editor: an unbalanced draft says by how much, and cannot be saved" begin
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 0.0; id = :B1); add_bus!(ed, 1.0, 0.0; id = :B2)
    add_branch!(ed, :B1, :B2)
    add_machine!(ed, :B1; P0 = 50.0); add_machine!(ed, :B2; P0 = -30.0)
    @test power_balance(ed) == 20.0
    v = validation(ed)
    @test !v.ok && occursin("≠ 0", v.message)          # the MODEL's guard, verbatim
    @test occursin("≠ 0", emsg(() -> save!(ed, joinpath(mktempdir(), "draft.toml"))))
    set_field!(ed, :machine, :G2, :P0, -50.0)
    set_field!(ed, :machine, :G2, :Pmax, -50.0)
    @test validation(ed).ok && power_balance(ed) == 0.0
    # A load counts against the machines, with the load's own sign convention.
    add_load!(ed, :B2; P0 = 20.0)
    @test power_balance(ed) == -20.0
end

@testset "editor: fresh ids span all kinds; refusals carry the constructor's message" begin
    ed = ScenarioEditor()
    @test add_bus!(ed, 0.0, 0.0) === :B1
    @test add_bus!(ed, 1.0, 0.0) === :B2
    @test add_machine!(ed, :B1) === :G1
    @test occursin("already in use", emsg(() -> add_bus!(ed, 2.0, 0.0; id = :G1)))
    # `H = 0` is refused by `Machine` itself, with its own words, and the old
    # record is untouched — an edit that fails leaves nothing half-applied.
    @test occursin("divides by 2H", emsg(() -> set_field!(ed, :machine, :G1, :H, 0.0)))
    @test element(ed, :machine, :G1).H == 4.0
    @test occursin("no bus", emsg(() -> add_load!(ed, :B9)))
    add_load!(ed, :B1; P0 = 10.0)
    @test occursin("already carries a load", emsg(() -> add_load!(ed, :B1)))
    add_branch!(ed, :B1, :B2)
    @test occursin("already connected", emsg(() -> add_branch!(ed, :B2, :B1)))
    @test occursin("self-loop", emsg(() -> add_branch!(ed, :B1, :B1)))
    @test occursin("not editable", emsg(() -> set_field!(ed, :machine, :G1, :bus, :B2)))
    @test occursin("no field", emsg(() -> set_field!(ed, :bus, :B1, :H, 1.0)))
end

@testset "editor: removing a bus takes its attachments; renaming one carries them" begin
    ed = ScenarioEditor(three_machine_ring())
    add_load!(ed, :B2; id = :LD, P0 = 0.0)
    rename!(ed, :bus, :B2, :North)
    @test element(ed, :machine, :G2).bus === :North
    @test element(ed, :load, :LD).bus === :North
    @test count(br -> br.from === :North || br.to === :North, ed.branches) == 2
    @test haskey(ed.layout, :North) && !haskey(ed.layout, :B2)
    @test validation(ed).ok                       # still one connected, balanced model
    ed.selection = (:bus, :North)
    remove!(ed, :bus, :North)
    @test [m.id for m in ed.machines] == [:G1, :G3]
    @test isempty(ed.loads)
    @test [br.id for br in ed.branches] == [:L31]
    @test ed.selection === nothing && !haskey(ed.layout, :North)
    @test occursin("no bus", emsg(() -> remove!(ed, :bus, :North)))
end

@testset "editor: a model with no layout goes on a circle; moving a bus moves no physics" begin
    ed = ScenarioEditor(three_machine_ring())
    @test length(ed.layout) == 3
    @test isapprox(ed.layout[:B1][1], 0.0; atol = 1e-12)   # first bus at the top
    @test ed.layout[:B1][2] ≈ 1.0
    before = build_model(ed)
    move_bus!(ed, :B1, 5.0, 5.0)
    after = build_model(ed)
    @test after.buses == before.buses && after.machines == before.machines &&
          after.branches == before.branches
    @test ed.layout[:B1] == (5.0, 5.0)
    # A partial layout keeps what it was given and places the rest.
    ed2 = ScenarioEditor(three_machine_ring(); layout = Layout(:B2 => (9.0, 9.0)))
    @test ed2.layout[:B2] == (9.0, 9.0) && length(ed2.layout) == 3
end

@testset "editor: save and open round-trip the model AND the map" begin
    dir = mktempdir(); path = joinpath(dir, "ring.toml")
    ed = ScenarioEditor(three_machine_ring(); name = "ring")
    move_bus!(ed, :B2, 3.0, -1.0)
    @test save!(ed, path) == path
    ed2 = load!(ScenarioEditor(), path)
    @test build_model(ed2).machines == three_machine_ring().machines
    @test ed2.layout == ed.layout
    @test ed2.name == "ring" && ed2.S_base == 100.0 && ed2.f0 == 50.0
end

# ---- the window -------------------------------------------------------------------

@testset "editor window: the canvas draws what the state holds, and only that" begin
    ed = ScenarioEditor(load_bus_system())          # two machines, one load, three lines
    win = EBUILD(ed)
    @test length(win.plots.bus_pts[]) == 3
    @test length(win.plots.mach_pts[]) == 2
    @test length(win.plots.load_pts[]) == 1
    @test length(win.plots.branch_segs[]) == 6      # two endpoints per line
    @test isempty(win.plots.sel_pts[])              # nothing selected yet
    @test occursin("valid", win.validation_text[])
    remove!(win.ed, :load, :L3); win.refresh!()
    @test isempty(win.plots.load_pts[])
    @test occursin("invalid", win.validation_text[])   # the balance broke
end

@testset "editor window: the tools drive the canvas through the handlers the mouse calls" begin
    win = EBUILD(ScenarioEditor())
    tb = win.widgets.tool_buttons
    @test win.tool[] === :select
    click!(tb[:bus]); @test win.tool[] === :bus
    @test occursin("▸", tb[:bus].label[]) && !occursin("▸", tb[:select].label[])
    win.canvas_press!(0.0, 0.0); win.canvas_press!(1.0, 0.0)
    @test [b.id for b in win.ed.buses] == [:B1, :B2]
    @test win.ed.selection == (:bus, :B2)
    @test length(win.plots.bus_pts[]) == 2

    click!(tb[:machine])
    win.canvas_press!(0.0, 0.0)
    @test element(win.ed, :machine, :G1).bus === :B1
    @test win.ed.selection == (:machine, :G1)
    n = length(win.ed.machines)
    win.canvas_press!(0.5, 0.5)                      # nowhere near a bus
    @test length(win.ed.machines) == n && occursin("click a bus", win.status[])

    click!(tb[:load])
    win.canvas_press!(1.0, 0.0)
    @test element(win.ed, :load, :L1).bus === :B2

    click!(tb[:branch])
    win.canvas_press!(0.0, 0.0)
    @test win.pending[] === :B1 && length(win.plots.pend_pts[]) == 1
    win.canvas_press!(1.0, 0.0)
    @test win.pending[] === nothing && isempty(win.plots.pend_pts[])
    @test Set((element(win.ed, :branch, :T1).from, element(win.ed, :branch, :T1).to)) ==
          Set((:B1, :B2))
    @test win.ed.selection == (:branch, :T1) && length(win.plots.sel_segs[]) == 2
    win.canvas_press!(0.0, 0.0); win.canvas_press!(0.0, 0.0)      # same bus twice cancels
    @test win.pending[] === nothing && occursin("cancelled", win.status[])
    @test length(win.ed.branches) == 1
    # A second circuit is refused and the refusal lands in the status line.
    win.canvas_press!(0.0, 0.0); win.canvas_press!(1.0, 0.0)
    @test length(win.ed.branches) == 1 && occursin("already connected", win.status[])
    @test win.pending[] === nothing

    click!(tb[:select])
    win.canvas_press!(0.0, 0.0)
    @test win.ed.selection == (:bus, :B1)
    @test win.canvas_drag!(0.2, 0.3)                 # dragging the pressed bus
    @test win.ed.layout[:B1] == (0.2, 0.3)
    win.canvas_release!()
    @test !win.canvas_drag!(0.9, 0.9)                # nothing held any more
    @test win.ed.layout[:B1] == (0.2, 0.3)
    # Small glyphs win a click over the bus under them.
    g = GridSimUI._glyph_positions(win.ed)
    p = g.machines[:G1]
    win.canvas_press!(p[1], p[2])
    @test win.ed.selection == (:machine, :G1)
    @test !win.canvas_drag!(0.0, 0.0)                # a machine does not drag
    win.canvas_press!(5.0, 5.0)
    @test win.ed.selection === nothing

    click!(tb[:delete])
    q = g.loads[:L1]
    win.canvas_press!(q[1], q[2])
    @test isempty(win.ed.loads) && occursin("deleted load L1", win.status[])
    win.canvas_press!(5.0, 5.0)
    @test occursin("nothing there", win.status[])
end

@testset "editor window: the property panel edits through the constructor" begin
    ed = ScenarioEditor(three_machine_ring())
    ed.selection = (:machine, :G1)
    win = EBUILD(ed)
    boxes = win.widgets.panel_boxes
    @test Set(keys(boxes)) == Set((:id, GridSimUI.editable_fields(:machine)...))
    @test boxes[:P0].displayed_string[] == "80"
    @test boxes[:R].displayed_string[] == "Inf"
    boxes[:H].displayed_string[] = "6.5"
    boxes[:id].displayed_string[] = "Gen1"
    click!(win.widgets.panel_buttons[:apply])
    @test element(win.ed, :machine, :Gen1).H == 6.5
    @test win.ed.selection == (:machine, :Gen1)
    @test occursin("applied to machine Gen1", win.status[])
    # The panel was rebuilt for the renamed element; the boxes are new objects.
    boxes = win.widgets.panel_boxes
    @test boxes[:id].displayed_string[] == "Gen1"
    boxes[:H].displayed_string[] = "0"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not applied", win.status[]) && occursin("2H", win.status[])
    @test element(win.ed, :machine, :Gen1).H == 6.5
    boxes[:H].displayed_string[] = "six"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not a number", win.status[])
    # Nothing selected: the panel says so and has no boxes.
    click!(win.widgets.panel_buttons[:delete])
    @test win.ed.selection === nothing
    @test isempty(win.widgets.panel_boxes) && isempty(win.widgets.panel_buttons)
    @test !any(m -> m.id === :Gen1, win.ed.machines)
    # A branch panel offers a branch's fields.
    win.ed.selection = (:branch, :L23); win.refresh!()
    @test Set(keys(win.widgets.panel_boxes)) == Set((:id, :X, :rating))
end

@testset "editor window: run hands the constructor's model to the runner, or says why not" begin
    got = Ref{Any}(nothing)
    win = EBUILD(ScenarioEditor(three_machine_ring()); runner = net -> (got[] = net; :stub))
    click!(win.widgets.b_run)
    @test got[] isa NetworkModel && got[].machines == three_machine_ring().machines
    @test win.last_run[] === :stub && occursin("running", win.status[])
    remove!(win.ed, :machine, :G3); win.refresh!()
    got[] = nothing
    click!(win.widgets.b_run)
    @test got[] === nothing && occursin("cannot run", win.status[]) && occursin("≠ 0", win.status[])
    # The bar's bases are read on run, and a bad one stops it before the model.
    win.widgets.tb_sbase.displayed_string[] = "hundred"
    click!(win.widgets.b_run)
    @test occursin("not a number", win.status[]) && win.ed.S_base == 100.0
end

@testset "editor window: save file and open file go through the bar" begin
    dir = mktempdir(); path = joinpath(dir, "edited.toml")
    win = EBUILD(ScenarioEditor(three_machine_ring()))
    click!(win.widgets.b_save)
    @test occursin("no file name", win.status[]) && !isfile(path)
    win.widgets.tb_path.displayed_string[] = path
    win.widgets.tb_name.displayed_string[] = "ring, edited"
    move_bus!(win.ed, :B3, -2.0, -2.0)
    click!(win.widgets.b_save)
    @test isfile(path) && occursin("saved", win.status[])
    sc = read_scenario(path)
    @test sc.name == "ring, edited" && sc.layout[:B3] == (-2.0, -2.0)

    win2 = EBUILD(ScenarioEditor())
    @test isempty(win2.plots.bus_pts[])
    win2.widgets.tb_path.displayed_string[] = path
    click!(win2.widgets.b_load)
    @test occursin("opened", win2.status[])
    @test length(win2.ed.buses) == 3 && length(win2.plots.bus_pts[]) == 3
    @test win2.widgets.tb_name.displayed_string[] == "ring, edited"
    @test win2.ed.layout[:B3] == (-2.0, -2.0)
    win2.widgets.tb_path.displayed_string[] = joinpath(dir, "missing.toml")
    click!(win2.widgets.b_load)
    @test occursin("not opened", win2.status[]) && length(win2.ed.buses) == 3
end

@testset "editor window: a real mouse press on the canvas reaches the same handler" begin
    win = EBUILD(ScenarioEditor())
    Makie.colorbuffer(win.fig)                       # solve the layout so pixels mean something
    click!(win.widgets.tool_buttons[:bus])
    px = Makie.shift_project(win.ax.scene, Point3f(0.25, -0.25, 0.0))
    ev = events(win.fig.scene)
    ev.mouseposition[] = (px[1], px[2])
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    @test length(win.ed.buses) == 1
    xy = win.ed.layout[:B1]
    @test isapprox(xy[1], 0.25; atol = 0.01) && isapprox(xy[2], -0.25; atol = 0.01)
    # And a press OUTSIDE the axis does nothing to the scenario.
    ev.mouseposition[] = (1.0, 1.0)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    @test length(win.ed.buses) == 1
end

@testset "editor_render writes a PNG of the same window" begin
    dir = mktempdir()
    path = joinpath(dir, "editor.png")
    out = editor_render(; path = path, select = (:bus, :B2))
    @test out == path
    @test isfile(path) && filesize(path) > 10_000
end
