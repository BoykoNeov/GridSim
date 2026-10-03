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

@testset "editor: an edit keeps the fields the panel does not show (M6 step 7)" begin
    # The editor shows no cost, so a rebuild that dropped one would say nothing on
    # screen. The old hand-listed `_with` did exactly that; every path that rebuilds
    # a machine is driven here — a field edit, a machine rename, and a bus rename
    # that re-attaches it.
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 0.0)
    add_machine!(ed, :B1; P0 = 50.0, Pmax = 250.0,
                 cost_c2 = 0.11, cost_c1 = 5.0, cost_c0 = 150.0, Pmin = 10.0)
    costed(m) = (m.cost_c2, m.cost_c1, m.cost_c0, m.Pmin) === (0.11, 5.0, 150.0, 10.0)
    set_field!(ed, :machine, :G1, :H, 6.0)
    @test element(ed, :machine, :G1).H == 6.0 && costed(element(ed, :machine, :G1))
    rename!(ed, :machine, :G1, :Gx)
    @test costed(element(ed, :machine, :Gx))
    rename!(ed, :bus, :B1, :Bx)
    @test element(ed, :machine, :Gx).bus === :Bx && costed(element(ed, :machine, :Gx))
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

# ---- inverters (M7 step 8) ----------------------------------------------------------
#
# Step 1 made the editor REFUSE a model with inverters, both ways in, because holding
# none it would have dropped them on the next save. This step lifts that refusal, and
# the tests that pinned it are rewritten on purpose into the round trip below — the
# lifted refusal showing up as failing tests, which is what it was there for.

# Every field away from its default, both modes, so a field dropped anywhere on the
# way through the editor shows up as a difference rather than as a default.
function _inv_fixture()
    gfm = Inverter(:IF, :B2, :grid_forming, 120.0, 40.0; Q0 = 5.0, K_p = 0.03,
                   τ_p = 0.2, K_q = 0.02, τ_q = 0.05, V_set = 1.02, X_c = 0.12,
                   K_pll_p = 51.0, K_pll_i = 701.0, τ_pll = 0.0021)
    gfl = Inverter(:IL, :B3, :grid_following, 80.0, 20.0; Q0 = -3.0, K_p = 0.04,
                   τ_p = 0.3, K_q = 0.01, τ_q = 0.07, V_set = 0.98, X_c = 0.09,
                   K_pll_p = 50.0, K_pll_i = 700.0, τ_pll = 0.002)
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)]
    br = [Branch(:L12, :B1, :B2, 0.1, 500.0), Branch(:L23, :B2, :B3, 0.15, 500.0)]
    return NetworkModel(100.0, 50.0, buses, br,
                        [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 40.0)],
                        [Load(:D3, :B3, 100.0, 10.0)];
                        inverters = [gfl, gfm], slack = :B1)
end
_same_inverter(a, b) = all(getfield(a, f) === getfield(b, f) for f in fieldnames(Inverter))

@testset "editor: a model with inverters opens, saves and reopens with every field (M7 step 8)" begin
    net = _inv_fixture()
    ed = ScenarioEditor(net; name = "inv")
    @test [i.id for i in ed.inverters] == [i.id for i in net.inverters]
    back = build_model(ed)
    @test all(_same_inverter(a, b) for (a, b) in zip(net.inverters, back.inverters))
    move_bus!(ed, :B3, 2.0, -1.0)
    path = save!(ed, joinpath(mktempdir(), "inv.toml"))
    ed2 = load!(ScenarioEditor(three_machine_ring(); name = "overwritten"), path)
    @test ed2.name == "inv" && ed2.layout == ed.layout && ed2.slack === :B1
    @test length(ed2.inverters) == 2
    @test all(_same_inverter(a, b) for (a, b) in zip(net.inverters, build_model(ed2).inverters))
    @test validation(ed2).ok && occursin("1 machines, 1 loads, 2 inverters", validation(ed2).message)
end

@testset "editor: inverters are attached, renamed, carried and removed like machines" begin
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 0.0); add_bus!(ed, 1.0, 0.0)
    @test add_inverter!(ed, :B1) === :I1
    @test element(ed, :inverter, :I1).mode === :grid_forming       # the default
    @test add_inverter!(ed, :B2; mode = :grid_following) === :I2
    @test add_machine!(ed, :B2) === :G1
    @test occursin("already in use", emsg(() -> add_bus!(ed, 2.0, 0.0; id = :I1)))
    @test occursin("no bus", emsg(() -> add_inverter!(ed, :B9)))
    # The constructor's own refusal, its words.
    @test occursin("exceeds", emsg(() -> add_inverter!(ed, :B1; S_rated = 10.0, P0 = 20.0)))
    @test occursin("mode must be", emsg(() -> add_inverter!(ed, :B1; mode = :grid_supporting)))
    rename!(ed, :bus, :B2, :East)
    @test element(ed, :inverter, :I2).bus === :East
    rename!(ed, :inverter, :I2, :Solar)
    @test element(ed, :inverter, :Solar).mode === :grid_following
    ed.selection = (:inverter, :Solar)
    remove!(ed, :bus, :East)
    @test [i.id for i in ed.inverters] == [:I1] && ed.selection === nothing
    @test isempty(ed.machines)
    remove!(ed, :inverter, :I1)
    @test isempty(ed.inverters)
end

@testset "editor: the balance counts inverters, with a machine's sign" begin
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 0.0; id = :A); add_bus!(ed, 1.0, 0.0; id = :B)
    add_branch!(ed, :A, :B)
    add_machine!(ed, :A; P0 = 0.0)
    add_load!(ed, :B; P0 = 30.0)
    @test power_balance(ed) == -30.0 && !validation(ed).ok
    # Balanced ONLY by the inverter: the status line and the model's guard agree.
    add_inverter!(ed, :B; mode = :grid_following, P0 = 30.0)
    @test power_balance(ed) == 0.0
    @test validation(ed).ok
end

@testset "editor: the derived reference bus with inverters agrees with the model" begin
    # `effective_slack` is a second copy of `NetworkModel`'s rule, and M7 widened the
    # rule: no machine → the first GRID-FORMING inverter's bus, in BUS order — never a
    # grid-following one. Each draft below is one way the copy could drift.
    function draft(specs)               # (bus, mode) per inverter, added in this order
        ed = ScenarioEditor()
        for (k, b) in enumerate((:A, :B, :C))
            add_bus!(ed, Float64(k), 0.0; id = b)
        end
        add_branch!(ed, :A, :B); add_branch!(ed, :B, :C)
        for (bus, mode) in specs
            add_inverter!(ed, bus; mode)
        end
        return ed
    end
    agree(ed) = effective_slack(ed) === build_model(ed).slack
    # Grid-forming inverters added OUT of bus order: the model sorts, so must the map.
    ed = draft([(:C, :grid_forming), (:B, :grid_forming)])
    @test effective_slack(ed) === :B && agree(ed)
    # A grid-following inverter on an earlier bus is never the reference.
    ed = draft([(:C, :grid_forming), (:A, :grid_following)])
    @test effective_slack(ed) === :C && agree(ed)
    # Only grid-following: nothing holds a voltage, so the first bus (the model's
    # fallback for a half-built draft; a solve then refuses it, by name).
    ed = draft([(:B, :grid_following), (:C, :grid_following)])
    @test effective_slack(ed) === :A && agree(ed)
    # A machine wins over any inverter, wherever it is.
    ed = draft([(:A, :grid_forming)]); add_machine!(ed, :C)
    @test effective_slack(ed) === :C && agree(ed)
    # A mode switch moves it.
    ed = draft([(:B, :grid_following), (:C, :grid_forming)])
    @test effective_slack(ed) === :C
    set_field!(ed, :inverter, :I1, :mode, :grid_forming)
    @test effective_slack(ed) === :B && agree(ed)
end

@testset "editor: an inverter's fields are its mode's, and an edit lands whole or not at all" begin
    ed = ScenarioEditor(_inv_fixture())
    gfm = element(ed, :inverter, :IF); gfl = element(ed, :inverter, :IL)
    @test GridSimUI.editable_fields(gfm) == (:S_rated, :P0, :V_set, :X_c, :K_p, :τ_p, :K_q, :τ_q)
    @test GridSimUI.editable_fields(gfl) == (:S_rated, :P0, :Q0, :K_pll_p, :K_pll_i, :τ_pll)
    @test occursin("depend on its mode", emsg(() -> GridSimUI.editable_fields(:inverter)))
    # A mode switch and back: the hidden half survives both rebuilds, bit for bit.
    set_field!(ed, :inverter, :IF, :mode, :grid_following)
    @test GridSimUI.editable_fields(element(ed, :inverter, :IF)) == GridSimUI.editable_fields(gfl)
    set_field!(ed, :inverter, :IF, :mode, :grid_forming)
    @test _same_inverter(element(ed, :inverter, :IF), gfm)
    # The rating ties S_rated, P0 and Q0 together: lowering the rating alone is refused
    # and leaves the record exactly as it was...
    @test occursin("exceeds", emsg(() -> set_field!(ed, :inverter, :IF, :S_rated, 30.0)))
    @test _same_inverter(element(ed, :inverter, :IF), gfm)
    # ...and lowering it WITH the dispatch, in one edit, is accepted. (`Q0 = 5` is
    # hidden on a grid-forming panel but still checked by the rating, and 30 MVA covers
    # √(20² + 5²) = 20.6.)
    set_fields!(ed, :inverter, :IF, (; S_rated = 30.0, P0 = 20.0))
    @test (element(ed, :inverter, :IF).S_rated, element(ed, :inverter, :IF).P0) == (30.0, 20.0)
    @test element(ed, :inverter, :IF).X_c == 0.12                    # the rest untouched
    @test occursin("not editable", emsg(() -> set_fields!(ed, :inverter, :IF, (; bus = :B1))))
    @test occursin("no field", emsg(() -> set_fields!(ed, :inverter, :IF, (; H = 1.0))))
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
    # A taken id refuses the WHOLE apply: the number in the same panel does not land
    # either. (The first one-rebuild apply wrote the numbers, then failed the rename,
    # and said "not applied" over a changed record — M7 step 8's review.)
    boxes[:H].displayed_string[] = "7"
    boxes[:id].displayed_string[] = "G2"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not applied", win.status[]) && occursin("already in use", win.status[])
    @test element(win.ed, :machine, :Gen1).H == 6.5
    @test win.ed.selection == (:machine, :Gen1)
    boxes[:id].displayed_string[] = "Gen1"; boxes[:H].displayed_string[] = "6.5"
    # Nothing selected: the panel says so and has no boxes.
    click!(win.widgets.panel_buttons[:delete])
    @test win.ed.selection === nothing
    @test isempty(win.widgets.panel_boxes) && isempty(win.widgets.panel_buttons)
    @test !any(m -> m.id === :Gen1, win.ed.machines)
    # A branch panel offers a branch's fields.
    win.ed.selection = (:branch, :L23); win.refresh!()
    @test Set(keys(win.widgets.panel_boxes)) == Set((:id, :X, :rating, :R))
end

@testset "editor window: the panel edits the three fields a solve reads, and R" begin
    # M6 step 5. `V_set`, `Q_min`, `Q_max` and the branch's `R` were carried by the
    # file and by `set_field!` before this step but were not in the panel, so a
    # scenario drawn on the map could not say anything a power flow would notice
    # beyond its dispatch.
    ed = ScenarioEditor(load_bus_system())
    ed.selection = (:machine, :G1)
    win = EBUILD(ed)
    boxes = win.widgets.panel_boxes
    @test Set(keys(boxes)) == Set((:id, GridSimUI.editable_fields(:machine)...))
    # ∓Inf is the DEFAULT of two of them, so every machine panel from now on shows a
    # box holding "Inf" — and `apply` reads every box, so a value that did not
    # survive `%g` and `tryparse` would silently become an error or a finite limit.
    @test boxes[:Q_min].displayed_string[] == "-Inf"
    @test boxes[:Q_max].displayed_string[] == "Inf"
    @test boxes[:V_set].displayed_string[] == "1"
    boxes[:V_set].displayed_string[] = "1.03"
    boxes[:Q_max].displayed_string[] = "0.4"
    click!(win.widgets.panel_buttons[:apply])
    @test element(win.ed, :machine, :G1).V_set == 1.03
    @test element(win.ed, :machine, :G1).Q_max == 0.4
    @test element(win.ed, :machine, :G1).Q_min == -Inf     # untouched, and still ∓Inf
    # ...and refused THROUGH THE CONSTRUCTOR, with its words, like every other field.
    # It has to be `Q_min` ABOVE `Q_max` and not a negative `Q_max`: a machine may
    # legitimately absorb reactive power at every operating point, so `Q_max = -2`
    # against the default `Q_min = -Inf` is a perfectly good record and the
    # constructor accepts it. The only guard here is the ordering of the pair.
    boxes[:Q_min].displayed_string[] = "1"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not applied", win.status[]) && occursin("Q_min", win.status[])
    @test element(win.ed, :machine, :G1).Q_min == -Inf
    @test element(win.ed, :machine, :G1).Q_max == 0.4
    boxes[:Q_min].displayed_string[] = "-Inf"
    boxes[:V_set].displayed_string[] = "0"
    boxes[:Q_max].displayed_string[] = "0.4"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("V_set", win.status[]) && element(win.ed, :machine, :G1).V_set == 1.03

    win.ed.selection = (:branch, :L12); win.refresh!()
    br = win.widgets.panel_boxes
    @test br[:R].displayed_string[] == "0"                 # a lossless line, written down
    br[:R].displayed_string[] = "0.01"
    click!(win.widgets.panel_buttons[:apply])
    @test element(win.ed, :branch, :L12).R == 0.01
    br[:R].displayed_string[] = "-0.01"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not applied", win.status[]) && element(win.ed, :branch, :L12).R == 0.01
end

@testset "editor: the reference bus is declared, drawn, and agrees with the model" begin
    ed = ScenarioEditor(load_bus_system())
    @test ed.slack === :B1                       # carried in from the fixture
    set_slack!(ed, nothing)
    @test ed.slack === nothing
    # With nothing declared the map still has to point somewhere, and where it points
    # is a SECOND copy of `NetworkModel`'s derivation rule. The two are asserted to
    # agree rather than assumed to: on drafts with machines, without them, and with
    # the first bus empty.
    @test effective_slack(ed) === build_model(ed).slack
    set_slack!(ed, :B3)
    @test effective_slack(ed) === :B3 === build_model(ed).slack
    @test occursin("no bus", emsg(() -> set_slack!(ed, :B9)))

    bare = ScenarioEditor()
    @test effective_slack(bare) === nothing      # nothing to point at at all
    add_bus!(bare, 0.0, 0.0; id = :A); add_bus!(bare, 1.0, 0.0; id = :B)
    add_branch!(bare, :A, :B)
    @test effective_slack(bare) === :A === build_model(bare).slack   # no machines: first bus
    add_machine!(bare, :B; P0 = 0.0)
    @test effective_slack(bare) === :B === build_model(bare).slack   # ...now the machine's

    # A deleted or renamed slack does not leave the map pointing at a bus that is
    # gone (the operations carried it from step 1; here it is the DRAWN one).
    ed2 = ScenarioEditor(load_bus_system()); set_slack!(ed2, :B2)
    rename!(ed2, :bus, :B2, :Middle)
    @test effective_slack(ed2) === :Middle
    remove!(ed2, :bus, :Middle)
    @test ed2.slack === nothing && effective_slack(ed2) === :B1
end

@testset "editor window: the slack is on the map and chosen from the panel" begin
    win = EBUILD(ScenarioEditor(load_bus_system()))
    g = GridSimUI._glyph_positions(win.ed)
    @test win.plots.slack_pts[] == [g.buses[:B1]]
    @test only(win.plots.slack_labels[])[1] == "slack"

    # Give the declaration up: the marker moves to the DERIVED bus and says so, which
    # is the whole reason it is drawn — a derived reference is still a dispatch
    # choice, and a save would otherwise write it without anyone having seen it.
    set_slack!(win.ed, nothing); win.refresh!()
    @test win.plots.slack_pts[] == [g.buses[:B1]]
    @test only(win.plots.slack_labels[])[1] == "slack (derived)"

    win.ed.selection = (:bus, :B3); win.refresh!()
    @test win.widgets.panel_buttons[:slack].label[] == "make slack"
    click!(win.widgets.panel_buttons[:slack])
    @test win.ed.slack === :B3 && occursin("slack bus is B3", win.status[])
    @test win.plots.slack_pts[] == [g.buses[:B3]]
    @test only(win.plots.slack_labels[])[1] == "slack"
    # ...and back, so a wrong declaration does not need the bus deleted to undo.
    @test win.widgets.panel_buttons[:slack].label[] == "release slack"
    click!(win.widgets.panel_buttons[:slack])
    @test win.ed.slack === nothing && occursin("released", win.status[])
    @test win.widgets.panel_buttons[:slack].label[] == "make slack"
    # A machine's panel has no such button: the reference is a property of a bus.
    win.ed.selection = (:machine, :G1); win.refresh!()
    @test !haskey(win.widgets.panel_buttons, :slack)

    # It survives a save and an open, which is what step 1 carried it through the
    # editor for — and now the map is where that is visible.
    dir = mktempdir(); path = joinpath(dir, "slack.toml")
    set_slack!(win.ed, :B3)
    win.widgets.tb_path.displayed_string[] = path
    click!(win.widgets.b_save)
    win2 = EBUILD(ScenarioEditor())
    win2.widgets.tb_path.displayed_string[] = path
    click!(win2.widgets.b_load)
    @test win2.ed.slack === :B3
    @test only(win2.plots.slack_labels[])[1] == "slack"
end

@testset "editor window: solve draws the flow, and a refusal leaves the drawing alone" begin
    win = EBUILD(ScenarioEditor(load_bus_system()))
    @test isempty(win.plots.flow_pts[]) && win.solve_text[] == ""
    click!(win.widgets.b_solve)
    s = win.last_solve[]
    @test s !== nothing && occursin("solved", win.status[])
    # One coloured halo per bus, one arrow per branch, and the numbers on the glyphs.
    @test length(win.plots.solved_pts[]) == 3 && win.plots.solved_V[] == s.Vm
    @test length(win.plots.flow_pts[]) == 3 && length(win.plots.flow_dirs[]) == 3
    @test all(occursin(" pu", t) for (t, _) in win.plots.bus_labels[])
    @test all(occursin(" MW", t) for (t, _) in win.plots.branch_labels[])
    # The arrow points the way P LEAVES `from`, which is the one thing a magnitude
    # label cannot say. Asserted against the sign of the solved flow, per branch,
    # rather than against a picture: a reversed convention draws an equally tidy map.
    g = GridSimUI._glyph_positions(win.ed)
    @test count(e -> abs(s.flow[e]) > 1e-9, eachindex(s.branches)) == 3   # nothing is idle
    for e in eachindex(s.branches)
        along = g.buses[s.to[e]] - g.buses[s.from[e]]
        d = win.plots.flow_dirs[][e]
        @test sign(d[1] * along[1] + d[2] * along[2]) == sign(s.flow[e])
    end
    # The slack's pickup is a SOLVED number and the read-out says so against the
    # schedule it is not equal to — on a lossless network they agree, and this
    # fixture is lossless, so the line is checked for both halves being present.
    @test occursin("picks up", win.solve_text[]) && occursin("residual", win.solve_text[])
    @test occursin("B1", win.solve_text[])

    # ANY edit invalidates it. A flow arrow over a changed model is not a stale
    # picture, it is a wrong one.
    move_bus!(win.ed, :B2, 4.0, 4.0); win.refresh!()
    @test isempty(win.plots.flow_pts[]) && isempty(win.plots.solved_pts[])
    @test win.last_solve[] === nothing && win.solve_text[] == ""

    # A refusal `ac_powerflow` raises as an `ArgumentError`: the reference bus has no
    # machine on it. `NetworkModel` allows that (a half-built draft must stay
    # constructible), so this is the tier's refusal and not the constructor's.
    set_slack!(win.ed, :B3)                       # the load bus
    click!(win.widgets.b_solve)
    @test win.last_solve[] === nothing
    @test occursin("cannot solve", win.status[]) && occursin("carries no machine", win.status[])
    @test isempty(win.plots.flow_pts[])
    # ...and the editor is still an editor: the drawing is untouched and the next
    # click still places a bus (the scenario editor's own lesson — a refused line
    # once left its first bus armed).
    @test length(win.plots.bus_pts[]) == 3
    click!(win.widgets.tool_buttons[:bus])
    win.canvas_press!(9.0, 9.0)
    @test length(win.ed.buses) == 4

    # And the OTHER kind, which is the one a hand-drawn scenario meets first: a case
    # that converges outside the voltage band is an `ErrorException`, not an
    # `ArgumentError`, so catching only the latter would crash the window.
    set_slack!(win.ed, :B1)
    remove!(win.ed, :bus, :B4)
    set_field!(win.ed, :load, :L3, :P0, 900.0)
    # `Pmax` first: it is the headroom ceiling, so raising `P0` past the old one is
    # refused by `Machine` before the draft can become the case this test needs.
    set_field!(win.ed, :machine, :G1, :Pmax, 860.0)
    set_field!(win.ed, :machine, :G1, :P0, 860.0)
    win.refresh!()
    click!(win.widgets.b_solve)
    @test win.last_solve[] === nothing && occursin("cannot solve", win.status[])
    @test occursin("|V|", win.status[]) || occursin("Newton", win.status[])
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

@testset "editor window: the inverter tool, its glyph, its panel and its mode button" begin
    win = EBUILD(ScenarioEditor())
    tb = win.widgets.tool_buttons
    @test haskey(tb, :inverter)
    click!(tb[:bus]); win.canvas_press!(0.0, 0.0); win.canvas_press!(1.0, 0.0)
    click!(tb[:inverter])
    @test win.tool[] === :inverter
    win.canvas_press!(0.5, 0.5)                                       # nowhere near a bus
    @test isempty(win.ed.inverters) && occursin("click a bus to attach an inverter", win.status[])
    win.canvas_press!(0.0, 0.0)
    @test element(win.ed, :inverter, :I1).bus === :B1
    @test win.ed.selection == (:inverter, :I1)
    @test length(win.plots.inv_pts[]) == 1 && length(win.plots.sel_pts[]) == 1
    g = GridSimUI._glyph_positions(win.ed)
    @test win.plots.sel_pts[] == [g.inverters[:I1]]                    # highlighted
    @test occursin("GFM", only(win.plots.inv_labels[])[1])
    @test only(win.plots.inv_fill[]) != RGBAf(1, 1, 1, 1)             # filled: sets a voltage

    # A machine on the SAME bus shares the row above it: two glyphs, two places, and a
    # click on each selects that one.
    click!(tb[:machine]); win.canvas_press!(0.0, 0.0)
    g = GridSimUI._glyph_positions(win.ed)
    @test g.machines[:G1] != g.inverters[:I1]
    @test hypot((g.machines[:G1] - g.inverters[:I1])...) > 0.5 * g.off
    click!(tb[:select])
    p = g.inverters[:I1]; win.canvas_press!(p[1], p[2])
    @test win.ed.selection == (:inverter, :I1)
    p = g.machines[:G1]; win.canvas_press!(p[1], p[2])
    @test win.ed.selection == (:machine, :G1)

    # The panel offers the grid-forming fields and a mode button.
    win.ed.selection = (:inverter, :I1); win.refresh!()
    boxes = win.widgets.panel_boxes
    @test Set(keys(boxes)) == Set((:id, GridSimUI.editable_fields(element(win.ed, :inverter, :I1))...))
    @test haskey(boxes, :K_p) && !haskey(boxes, :K_pll_p)
    @test win.widgets.panel_buttons[:mode].label[] == "switch to grid-following"
    click!(win.widgets.panel_buttons[:mode])
    @test element(win.ed, :inverter, :I1).mode === :grid_following
    # ...and the panel was REBUILT for the new mode, not left showing the old fields.
    boxes = win.widgets.panel_boxes
    @test haskey(boxes, :K_pll_p) && !haskey(boxes, :K_p)
    @test win.widgets.panel_buttons[:mode].label[] == "switch to grid-forming"
    @test occursin("GFL", only(win.plots.inv_labels[])[1])
    @test only(win.plots.inv_fill[]) == RGBAf(1, 1, 1, 1)             # hollow: follows one

    # Apply lowers the rating and the dispatch TOGETHER, which only a one-rebuild apply
    # can accept; and a refused apply leaves every field as it was.
    set_fields!(win.ed, :inverter, :I1, (; P0 = 80.0))
    win.ed.selection = nothing; win.refresh!(); win.ed.selection = (:inverter, :I1); win.refresh!()
    boxes = win.widgets.panel_boxes
    @test boxes[:P0].displayed_string[] == "80"
    boxes[:S_rated].displayed_string[] = "30"
    boxes[:P0].displayed_string[] = "25"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("applied to inverter I1", win.status[])
    @test (element(win.ed, :inverter, :I1).S_rated, element(win.ed, :inverter, :I1).P0) == (30.0, 25.0)
    boxes = win.widgets.panel_boxes
    boxes[:S_rated].displayed_string[] = "10"
    boxes[:τ_pll].displayed_string[] = "0.5"
    click!(win.widgets.panel_buttons[:apply])
    @test occursin("not applied", win.status[]) && occursin("exceeds", win.status[])
    @test element(win.ed, :inverter, :I1).S_rated == 30.0
    @test element(win.ed, :inverter, :I1).τ_pll != 0.5                 # nothing half-applied
end

@testset "editor window: solve and run on a draft with inverters" begin
    # The reference bus is a grid-forming inverter's: the read-out's schedule is ITS
    # dispatch, not the "+0.0 MW" a machines-only sum printed.
    ed = ScenarioEditor()
    add_bus!(ed, 0.0, 0.0; id = :A); add_bus!(ed, 1.0, 0.0; id = :B)
    add_branch!(ed, :A, :B; X = 0.1)
    add_inverter!(ed, :A; id = :IF, P0 = 30.0)
    add_load!(ed, :B; P0 = 50.0, Q0 = 5.0)
    add_inverter!(ed, :B; id = :IL, mode = :grid_following, P0 = 20.0)
    win = EBUILD(ed)
    @test validation(win.ed).ok
    click!(win.widgets.b_solve)
    @test win.last_solve[] !== nothing
    @test occursin("slack A", win.solve_text[]) && occursin("schedule of +30.0 MW", win.solve_text[])
    # Run: the multi-machine window's engine refuses a grid-following inverter as a
    # tier boundary, and the refusal reaches the status line instead of the REPL. A
    # draft with NO load, because that tier refuses a load too, for its own reason —
    # and the inverter refusal is checked first, so it is the one a user sees.
    ed2 = ScenarioEditor()
    add_bus!(ed2, 0.0, 0.0; id = :A); add_bus!(ed2, 1.0, 0.0; id = :B)
    add_branch!(ed2, :A, :B; X = 0.1)
    add_inverter!(ed2, :A; id = :IF, P0 = 30.0)
    add_inverter!(ed2, :B; id = :IL, mode = :grid_following, P0 = -30.0)
    win2 = EBUILD(ed2; runner = net -> init!(SwingEngine, net))
    click!(win2.widgets.b_run)
    @test occursin("cannot run", win2.status[]) && occursin("tier boundary", win2.status[])
    # With the grid-following one switched to grid-forming the same runner accepts it,
    # and the status counts the inverters.
    set_field!(win2.ed, :inverter, :IL, :mode, :grid_forming); win2.refresh!()
    click!(win2.widgets.b_run)
    @test occursin("running — 0 machines, 2 inverters", win2.status[])
end

@testset "the multi-machine window a run opens: a grid-forming inverter is tripped as itself" begin
    # What `run ▶` hands a grid-forming draft to. The first render drew the inverter's
    # trace but offered no button to trip it and counted it among "3 machines".
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)]
    br = [Branch(:L12, :B1, :B2, 0.1, 500.0), Branch(:L23, :B2, :B3, 0.15, 500.0),
          Branch(:L31, :B3, :B1, 0.12, 500.0)]
    net = NetworkModel(100.0, 50.0, buses, br,
                       [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 30.0),
                        Machine(:G3, :B3, 100.0, 3.0, 2.0, 0.3, 1.0, 0.0)], Load[];
                       inverters = [Inverter(:IF, :B2, :grid_forming, 120.0, -30.0)])
    win = GridSimUI._build_network_window(net; window_seconds = 10.0, rtf = Inf)
    @test occursin("2 machines, 1 inverters", win.status[])
    @test [id for (id, _) in win.widgets.machine_buttons] == [:G1, :G3, :IF]
    @test occursin("(inverter)", win.widgets.machine_buttons[3][2].label[])
    click!(win.widgets.machine_buttons[3][2])
    run_realtime!(win.engine, win.state; control = win.control, queue = win.queue,
                  duration = 1.0)
    win.refresh!(; force = true)
    @test !is_online(win.engine, :IF) && is_online(win.engine, :G1)
    @test occursin("offline", win.widgets.machine_buttons[3][2].label[])
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
    # ...and one with the solve already run, which is the render the step's figure
    # comes from. `solve = true` runs the button's own handler, so a PNG that came
    # out cannot be showing a code path the window does not have.
    solved = joinpath(dir, "editor-solved.png")
    @test editor_render(; path = solved, net = load_bus_system(),
                          select = (:branch, :L23), solve = true) == solved
    @test isfile(solved) && filesize(solved) > 10_000
end
