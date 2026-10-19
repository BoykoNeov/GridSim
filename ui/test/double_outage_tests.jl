# The double-outage window (`../src/double_outage_window.jl`, M10 step 6).
#
# What is asserted is that the window DRAWS THE REPORT and nothing of its own: the row the
# read-out shows is the script's row (`===` the one the table cell came from, and equal to
# a fresh run of the script), every cell's colour and text say what its row says at the
# view chosen, the grid sketch colours each bus by the piece it is in, matched BY BUS ID,
# and a pair with no state after both losses draws no verdict of its own.
#
# One cache of reports is shared by every window built here.

const DBUILD = GridSimUI._build_double_outage_window
const _DOR_T = GridSimUI.DoubleOutageReport
const _DO_CACHE = Dict{Symbol,Any}()
_dow(; kw...) = DBUILD(; cache = _DO_CACHE, kw...)

@testset "double-outage window: the row is the script's, every cell says what its row says" begin
    win = _dow(; grid = :case9, timing = :both, view = :dc, pair = (:L45, :L67))
    rep = win.cache[:case9]
    # The script's own path, run here independently of the window's cache.
    G = _DOR_T.grid_screens(_DOR_T.Single.case9)
    fresh = _DOR_T.simultaneous_rows(G)
    @test isequal(rep.both, fresh)
    @test isequal(rep.seq, _DOR_T.sequential_rows(G; both = fresh))
    ids = rep.ids
    @test ids == [[b.id for b in rep.net.cp.branches]; [m.id for m in rep.net.cp.machines]]
    i, j = findfirst(==(:L45), ids), findfirst(==(:L67), ids)
    @test win.row[] === win.plots.cell_row[][i, j]
    # Every timing and view: each cell's colour is its row's verdict's, its text its
    # worst Δf (judged) or the verdict's short name; both-at-once is symmetric.
    for timing in GridSimUI.DO_TIMINGS, view in GridSimUI.DO_VIEWS
        win.choice.timing[] = timing; win.choice.view[] = view
        T, C, R = win.plots.cell_text[], win.plots.cell_colour[], win.plots.cell_row[]
        N = length(ids)
        for a in 1:N, b in 1:N
            a == b && continue
            r = R[a, b]
            if timing === :both
                @test Set((r.first, r.second)) == Set((ids[a], ids[b])) && R[b, a] === r
            else
                @test (r.first, r.second) === (ids[a], ids[b])
            end
            side = getfield(r, view)
            @test C[a, b] == GridSimUI._do_colour(side.verdict)
            # The line-and-voltage marker sits beside the colour (D13): its row's, or none.
            mk = _DOR_T.LINES_MARK[side.lines]
            @test isempty(mk) ? !occursin(r" (V|O|VO)$", T[a, b]) : endswith(T[a, b], " " * mk)
            if side.verdict in (:pass, :fail, :pass_load_lost)
                @test occursin(abs(side.worst) < 1 ? GridSimUI.@sprintf("%+.3f", side.worst) :
                               GridSimUI.@sprintf("%+.2f", side.worst), T[a, b])
            else
                @test occursin(GridSimUI.DO_SHORT[side.verdict], T[a, b])
                @test C[a, b] == GridSimUI.C_NONE
            end
        end
    end
    # The anti-vacuity half: the table holds every colour but amber (claim k: no pair on
    # these grids passes with customers cut off), so the check above could not pass on a
    # window that painted everything one way.
    win.choice.timing[] = :both; win.choice.view[] = :cp
    cols = Set(win.plots.cell_colour[])
    @test GridSimUI.C_PASS in cols && GridSimUI.C_FAIL in cols && GridSimUI.C_NONE in cols
    @test GridSimUI._do_colour(:pass_load_lost) == GridSimUI.C_AMBER
    @test GridSimUI.C_AMBER ∉ (GridSimUI.C_PASS, GridSimUI.C_FAIL, GridSimUI.C_NONE)
end

@testset "double-outage window: the grid sketch colours each bus by its piece, by id" begin
    # Every bus of both grids has a position (render state lives here, D12.5).
    for g in GridSimUI.DO_GRIDS
        rep = _dow(; grid = g).cache[g]
        @test Set(keys(GridSimUI.DO_POSITIONS[g])) == Set(b.id for b in rep.net.cp.buses)
    end
    # L45+L67 in DC: two running pieces, one passing up and one passing down.
    win = _dow(; grid = :case9, timing = :both, view = :dc, pair = (:L45, :L67))
    side = win.row[].dc
    cols = win.plots.bus_colour[]
    for p in side.pieces, b in p.buses
        @test cols[b] == (p.kind !== :live ? GridSimUI.C_DARK :
                          p.verdict === :pass ? GridSimUI.C_PASS :
                          p.verdict === :fail ? GridSimUI.C_FAIL : GridSimUI.C_NONE)
    end
    @test Set(keys(cols)) == Set(b for p in side.pieces for b in p.buses)
    @test length(win.plots.piece_labels[]) == 2
    @test all(occursin("pass", l) for l in win.plots.piece_labels[])
    # A pair that strands customers: B5 dark, labelled with its MW; the rest red.
    win.matrix_press!(findfirst(==(:L56), win.cache[:case9].ids) - 0.5,
                      length(win.cache[:case9].ids) - findfirst(==(:L45), win.cache[:case9].ids) + 0.5)
    @test win.choice.pair[] === (:L45, :L56)
    cols = win.plots.bus_colour[]
    @test cols[:B5] == GridSimUI.C_DARK && cols[:B4] == GridSimUI.C_FAIL
    @test any(l -> occursin("LOAD LOST 90.0 MW", l), win.plots.piece_labels[])
    @test occursin("LOAD LOST 90.0 MW", win.readout.text[])
end

@testset "double-outage window: a pair with no state after both draws no verdict" begin
    win = _dow(; grid = :case9, timing = :sequential, view = :cp, pair = (:G1, :G2))
    r = win.row[]
    @test r.cp.outcome === :not_restored
    @test all(c -> c == GridSimUI.C_NONE, values(win.plots.bus_colour[]))
    @test isempty(win.plots.piece_labels[])
    @test occursin("not restored", win.plots.banner[])
    @test !occursin("Hz pass", win.readout.text[]) && !occursin("worst Δf", win.readout.text[])
    # Back to a screened pair: the banner goes, the pieces come back.
    win.choice.pair[] = (:L56, :L78)
    @test isempty(win.plots.banner[]) && !isempty(win.plots.piece_labels[])
    # The collapse twin (D4) is marked in its cell and in the read-out, both timings.
    win.choice.pair[] = (:G1, :L14)
    ids = win.cache[:case9].ids
    i, j = findfirst(==(:G1), ids), findfirst(==(:L14), ids)
    @test startswith(win.plots.cell_text[][i, j], "=G1")
    @test occursin("IS losing G1", win.readout.text[])
end

@testset "double-outage window: the controls, the table press, the caveat" begin
    win = _dow(; grid = :case9, pair = (:L45, :L67))
    w = win.widgets
    @test startswith(w.grid_buttons[:case9].label[], "▸")
    @test startswith(w.view_buttons[:dc].label[], "▸")
    # The diagonal and the margins select nothing.
    N = length(win.cache[:case9].ids)
    @test win.matrix_press!(0.5, N - 0.5) === nothing && win.choice.pair[] === (:L45, :L67)
    @test win.matrix_press!(-0.5, 3.0) === nothing && win.matrix_press!(3.0, N + 0.5) === nothing
    # Row = first, column = second: the top-right cell is (first element, last element).
    ids = win.cache[:case9].ids
    @test win.matrix_press!(N - 0.5, N - 0.5) == (ids[1], ids[end])
    @test win.choice.pair[] === (ids[1], ids[end])
    @test win.plots.selected_box[] == Rect2f(N - 1, N - 1, 1, 1)
    # Changing grid moves to that grid's default pair; nothing is re-screened.
    before = win.cache[:mesh]
    click!(w.grid_buttons[:mesh])
    @test win.choice.grid[] === :mesh && win.choice.pair[] === GridSimUI.DO_DEFAULT_PAIR[:mesh]
    @test win.cache[:mesh] === before
    click!(w.timing_buttons[:sequential]); click!(w.view_buttons[:def])
    @test startswith(w.timing_buttons[:sequential].label[], "▸")
    @test win.row[] === only(r for r in win.cache[:mesh].seq if (r.first, r.second) === (:AB, :AC))
    # The preset's caveat, placed in the layout and naming its numbers.
    @test in_layout(win.fig.layout, win.caveat)
    t = win.caveat.text[]
    @test occursin("DESIGN VALUES", t) && occursin("settled 0.2 Hz", t)
    @test occursin("not a pass/fail rule for one outage on a small grid", t)
    @test all(l -> in_layout(win.fig.layout, l), win.legend)
    # The colour is frequency alone, and the legend says so: case9 default loads, L14+L45
    # is green with a running piece outside the voltage band (a note the user forwarded).
    @test any(l -> occursin("FREQUENCY ONLY", l.text[]), win.legend)
    r = only(r for r in win.cache[:case9].both if (r.first, r.second) === (:L14, :L45))
    @test r.def.verdict === :pass && any(p -> p.outcome === :voltage, r.def.pieces)
    # ...and the cell itself carries the V, green as it is (D13, the user's choice).
    click!(w.grid_buttons[:case9]); click!(w.timing_buttons[:both]); click!(w.view_buttons[:def])
    ids9 = win.cache[:case9].ids
    i, j = findfirst(==(:L14), ids9), findfirst(==(:L45), ids9)
    @test endswith(win.plots.cell_text[][i, j], " V") && win.plots.cell_colour[][i, j] == GridSimUI.C_PASS
    win.choice.pair[] = (:L14, :L45)
    @test occursin("lines/V   voltage", win.readout.text[])
    @test_throws ArgumentError _dow(; grid = :case9, pair = (:L45, :L45))
    @test_throws ArgumentError _dow(; grid = :mesh, pair = (:L45, :L67))
end

@testset "double-outage window: a real mouse press on a cell reaches the table" begin
    # The tests above call `matrix_press!` directly; this one proves a click gets there —
    # one MouseButtonEvent through the figure's events, at the pixel of a known cell (the
    # editor's offscreen route, `editor_tests.jl`).
    win = _dow(; grid = :case9, timing = :both, pair = (:L45, :L67))
    Makie.colorbuffer(win.fig)                       # solve the layout so pixels mean something
    ids = win.cache[:case9].ids
    N = length(ids)
    i, j = findfirst(==(:G1), ids), findfirst(==(:L82), ids)     # row G1, column L82
    px = Makie.shift_project(win.axes.m.scene, Point3f(j - 0.5, N - i + 0.5, 0.0))
    ev = events(win.fig.scene)
    ev.mouseposition[] = (px[1], px[2])
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    @test win.choice.pair[] === (:G1, :L82)
    @test Set((win.row[].first, win.row[].second)) == Set((:G1, :L82))
    # ...and a press outside the table selects nothing.
    ev.mouseposition[] = (1.0, 1.0)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    ev.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    @test win.choice.pair[] === (:G1, :L82)
end

@testset "double_outages_render writes a PNG of the same window" begin
    path = joinpath(mktempdir(), "double-outages.png")
    @test double_outages_render(; path, cache = _DO_CACHE) == path
    @test isfile(path) && filesize(path) > 10_000
end
