# The network-dispatch window (`../src/network_dispatch_window.jl`, M11 step 5).
#
# What is asserted is that the window DRAWS THE REPORT and nothing of its own: its rows are
# the script's (equal, field by field, to a fresh run of the script), the row the read-out
# shows is `===` the one the selected table row came from, every cell's text and colour say
# what that row says, and the grid draws each line's loading from the answer chosen.
#
# One cache of reports is shared by every window built here.

const NDBUILD = GridSimUI._build_network_dispatch_window
const _NDR_T = GridSimUI.NetworkDispatchReport
const _ND_CACHE = Dict{Symbol,Any}()
_ndw(; kw...) = NDBUILD(; cache = _ND_CACHE, kw...)

@testset "network-dispatch window: the rows are the script's, every cell says what its row says" begin
    win = _ndw(; fixture = :L89, loads = :constant_power, answer = :ac)
    rep = win.cache[:report]
    # The script's own path, run here independently of the window's cache.
    fresh = _NDR_T.report_rows()
    @test [(r.key, r.loads) for r in rep.rows] == [(r.key, r.loads) for r in fresh]
    for (a, b) in zip(rep.rows, fresh)
        A, B = a.row, b.row
        @test isequal(A.ed.P, B.ed.P) && isequal(A.dc.P, B.dc.P) && isequal(A.ac.P, B.ac.P)
        @test isequal(A.ed.cost, B.ed.cost) && isequal(A.dc.cost, B.dc.cost) &&
              isequal(A.ac.cost, B.ac.cost)
        @test A.flowed.outcome === B.flowed.outcome && isequal(A.flowed.cost, B.flowed.cost)
        @test A.ac.status == B.ac.status && A.dc.at_limit == B.dc.at_limit &&
              A.ac.at_limit == B.ac.at_limit && A.ac.at_band == B.ac.at_band
    end
    @test length(rep.flat) == 11
    # The selected row, the read-out, and every cell, on both load models.
    seen = Set{GridSimUI.RGBf}()
    for loads in GridSimUI.ND_LOADS
        win.choice.loads[] = loads
        rows = win.plots.cell_row[]
        @test [r.key for r in rows] == collect(GridSimUI.ND_KEYS)
        @test all(r.loads === loads for r in rows)
        i = findfirst(==(win.choice.fixture[]), GridSimUI.ND_KEYS)
        @test win.row[] === rows[i]
        @test win.readout.text[] ==
              GridSimUI._nd_readout(win.row[], GridSimUI._nd_flat(rep, win.row[].key, loads))
        T, C = win.plots.cell_text[], win.plots.cell_colour[]
        for (r, R) in enumerate(rows), (c, (_, txt, col)) in enumerate(GridSimUI.ND_COLUMNS)
            @test T[r, c] == txt(R.row) && C[r, c] == col(R.row)
            push!(seen, C[r, c])
        end
        # The colour rule, read off the row and not the cell: amber exactly where an answer
        # binds, red exactly where there is none.
        for (r, R) in enumerate(rows)
            ac = R.row.ac
            @test C[r, 4] == (ac.outcome !== :locally_optimal ? GridSimUI.C_FAIL :
                              isempty(ac.at_limit) && isempty(ac.at_band) ? GridSimUI.C_PASS :
                              GridSimUI.C_AMBER)
            @test C[r, 2] == (R.row.flowed.outcome === :secure ? GridSimUI.C_PASS : GridSimUI.C_FAIL)
        end
    end
    # The anti-vacuity half: every colour of the rule appears, so the checks above could
    # not pass on a table painted one way.
    @test GridSimUI.C_PASS in seen && GridSimUI.C_AMBER in seen && GridSimUI.C_FAIL in seen
end

@testset "network-dispatch window: the grid draws the answer chosen" begin
    win = _ndw(; fixture = :L89, loads = :constant_power, answer = :ac)
    R = win.row[].row
    S = R.net.S_base
    for (e, br) in pairs(R.net.branches)
        @test win.plots.line_loading[][br.id] == R.ac.mva[e] * S / br.rating
    end
    @test abs(win.plots.line_loading[][:L89] - 1) < 1e-4          # ON its (margined) rating
    @test win.plots.banner[] == ""
    win.choice.answer[] = :dc
    for (e, br) in pairs(R.net.branches)
        @test win.plots.line_loading[][br.id] == abs(R.dc.flow[e]) * S / br.rating
    end
    @test occursin("no voltages", win.plots.banner[])
    @test win.plots.bars[][:, 1] == R.ed.P .* S && win.plots.bars[][:, 2] == R.dc.P .* S
    @test win.plots.bars[][:, 3] == R.ac.P .* S
    # No AC point: nothing drawn as if there were, and the solver's word, not "infeasible".
    win.choice.answer[] = :ac
    win.choice.fixture[] = :x175
    @test win.row[].row.ac.outcome === :locally_infeasible
    @test all(isnan, values(win.plots.line_loading[]))
    @test occursin("LOCAL", win.plots.banner[])
    @test all(isnan, win.plots.bars[][:, 3])
    @test occursin("no point found", win.readout.text[])
end

@testset "network-dispatch window: the controls" begin
    win = _ndw(; fixture = :published, loads = :default, answer = :dc)
    click!(win.widgets.fixture_buttons[:L94])
    @test win.choice.fixture[] === :L94 && win.row[].key === :L94
    click!(win.widgets.load_buttons[:constant_power])
    @test win.choice.loads[] === :constant_power && win.row[].loads === :constant_power
    click!(win.widgets.answer_buttons[:ac])
    @test win.choice.answer[] === :ac
    # A press on the table: the row under it; the margins select nothing.
    N = length(GridSimUI.ND_KEYS)
    @test win.table_press!(1.0, N - 0.5) === GridSimUI.ND_KEYS[1]
    @test win.choice.fixture[] === GridSimUI.ND_KEYS[1]
    @test win.table_press!(1.0, 0.5) === GridSimUI.ND_KEYS[end]
    @test win.table_press!(-1.0, 0.5) === nothing && win.table_press!(1.0, N + 0.5) === nothing
    @test win.choice.fixture[] === GridSimUI.ND_KEYS[end]
    # The caveats travel with the numbers.
    for word in ("INVENTED", "line charging", "LOCAL", "NOT SERVED")
        @test occursin(word, win.caveat.text[])
    end
    @test_throws ArgumentError _ndw(; fixture = :nope)
    @test_throws ArgumentError _ndw(; loads = :zip)
    @test_throws ArgumentError _ndw(; answer = :both)
end

@testset "network-dispatch window: renders offscreen" begin
    path = joinpath(mktempdir(), "nd.png")
    @test GridSimUI.network_dispatch_render(; path, cache = _ND_CACHE) == path
    @test filesize(path) > 0
end
