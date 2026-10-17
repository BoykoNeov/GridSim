# The frequency-screen window (`../src/frequency_screen_window.jl`, M9 step 7).
#
# What is asserted is that the window DRAWS THE REPORT and nothing of its own: its
# read-out row is the script's `frequency_rows` row (`isequal` — one computation, not
# two), its traces are the dip runs' own samples (`==`, every point), its limit lines
# are the preset's, every overview cell says what its row says, and a refused outage
# leaves nothing of the previous selection on screen.
#
# One cache of runs is shared by every window built here, so the four grids' dynamic
# runs happen once for the file.

const FBUILD = GridSimUI._build_frequency_screen_window
const _FR = GridSimUI.FrequencyReport
const _FS_CACHE = Dict{Tuple{Symbol,Symbol},Any}()
_fsw(; kw...) = FBUILD(; cache = _FS_CACHE, kw...)

@testset "frequency-screen window: the row is the script's, the traces are the runs'" begin
    win = _fsw(; grid = :mesh, loads = :constant_power, lost = :G1)
    rep = win.cache[(:mesh, :constant_power)]
    # The script's default path, run here independently of the window's cache.
    fresh = _FR.frequency_rows(_FR.mesh(; loads = :constant_power))
    @test isequal(win.row[], fresh[1])
    @test isequal(rep.rows, fresh)
    tr = rep.d.trace[1]
    @test isempty(win.plots.mach[1][])                     # the machine lost is not drawn
    for j in (2, 3)
        @test win.plots.mach[j][] == Point2f.(tr.t, tr.f[:, j])
    end
    @test win.plots.coi[] == Point2f.(tr.t, tr.f_coi)
    # The zoom is the same samples, cut to the window after the trip.
    tt = rep.d.t_trip
    @test all(p -> tt - 0.2 - 1e-9 <= p[1] <= tt + GridSimUI.FS_ZOOM + 1e-9, win.plots.coi_z[])
    @test length(win.plots.coi_z[]) == count(t -> tt - 0.2 <= t <= tt + GridSimUI.FS_ZOOM, tr.t)
    # Both screens' settled lines are each screen's own value.
    @test win.plots.settle_dc[] == [50.0 + win.row[].Δf_dc]
    @test win.plots.settle_ac[] == [50.0 + win.row[].Δf_ac]
    # The read-out says what the row says, as the report's table prints it.
    vals = split(win.readout.values[], '\n')
    @test vals[3] == _FR._f(win.row[].Δf_dc, "%.4f") * " FAIL"
    @test occursin(_FR._f(win.row[].Δf_dip, "%.3f"), vals[6]) && occursin("FAIL", vals[6])
    @test occursin(_FR._f(win.row[].rate[1], "%.3f"), vals[9])
    @test occursin(_FR._f(win.row[].rate[2], "%.3f"), vals[10])
end

@testset "frequency-screen window: the limits are the preset's, and always in view" begin
    lim = GridSimUI.continental_europe_limits()
    win = _fsw(; grid = :mesh, loads = :default, lost = :G3)
    @test win.plots.lim_lines.settled == 50.0 - lim.settled
    @test win.plots.lim_lines.dip == 50.0 - lim.dip
    # Mesh-default G3 dips 0.15 Hz: an autoscaled axis would cut both limit lines off.
    l = win.axes.f.finallimits[]
    @test l.origin[2] <= win.plots.lim_lines.dip
    # Every outage here makes the frequency fall — why only the lower limits are drawn.
    for x in values(win.cache), r in x.rows
        @test !(r.Δf_dc > 0) && !(r.Δf_ac > 0) && !(r.Δf_dip > 0)
    end
    # Default loads, the mesh's G1: the run stops ABOVE the AC screen's settled line
    # (report claim h) — the line is drawn where the screen puts it, not clipped away.
    win.choice.lost[] = :G1
    l = win.axes.f.finallimits[]
    @test l.origin[2] <= win.plots.settle_ac[][1]
    @test win.plots.coi[][end][2] > win.plots.settle_ac[][1]
    # The preset's caveat is on screen wherever its lines are: in the figure's layout,
    # not just a Label built and never placed, and naming the preset's own numbers.
    @test in_layout(win.fig.layout, win.caveat)
    t = win.caveat.text[]
    @test occursin("DESIGN VALUES", t)
    @test occursin("not a pass/fail rule for one outage on a small grid", t)
    @test occursin("settled $(lim.settled) Hz, dip $(lim.dip) Hz", t)
end

@testset "frequency-screen window: every overview cell says what its row says" begin
    win = _fsw()
    ov = win.plots.overview
    @test length(ov) == 12
    for (i, (g, l, r)) in enumerate(ov)
        @test r === win.cache[(g, l)].rows[findfirst(x -> x.id === r.id, win.cache[(g, l)].rows)]
        @test win.plots.cell_text[i, 1] == String(r.dc)
        @test win.plots.cell_text[i, 2] == String(r.ac)
        @test startswith(win.plots.cell_text[i, 3], _FR._f(r.Δf_dc, "%.4f"))
        @test startswith(win.plots.cell_text[i, 4], _FR._f(r.Δf_ac, "%.4f"))
        # Green and red only where the report judges.
        for (c, v) in ((3, r.settled_dc), (4, r.settled_ac), (5, r.dip))
            col = win.plots.cell_colour[i, c]
            @test col == (v === :pass ? GridSimUI.C_PASS : v === :fail ? GridSimUI.C_FAIL :
                          GridSimUI.C_NONE)
        end
        @test win.plots.cell_colour[i, 6] == GridSimUI.C_NONE          # the rate, not judged
        if r.dyn === :measured
            @test startswith(win.plots.cell_text[i, 5], _FR._f(r.Δf_dip, "%.3f"))
        else
            @test win.plots.cell_text[i, 5] == "$(r.dyn) ($(r.reason))"
            @test win.plots.cell_colour[i, 5] == GridSimUI.C_NONE
        end
    end
    # The anti-vacuity half: the overview has every colour in it, so the check above
    # could not pass on a window that painted everything one way.
    cols = Set(win.plots.cell_colour[:, 3:5])
    @test GridSimUI.C_PASS in cols && GridSimUI.C_FAIL in cols && GridSimUI.C_NONE in cols
end

@testset "frequency-screen window: the controls, and a refusal leaves nothing behind" begin
    win = _fsw(; grid = :mesh, loads = :constant_power, lost = :G1)
    w = win.widgets
    @test startswith(w.grid_buttons[:mesh].label[], "▸")
    @test startswith(w.lost_buttons[:G1].label[], "▸")
    @test !isempty(win.plots.mach[2][])
    # case9, constant power, G2: secure in both screens, refused by the dynamic run.
    click!(w.grid_buttons[:case9]); click!(w.lost_buttons[:G2])
    @test win.choice.grid[] === :case9 && win.choice.lost[] === :G2
    @test startswith(w.lost_buttons[:G2].label[], "▸") && !startswith(w.lost_buttons[:G1].label[], "▸")
    r = win.row[]
    @test (r.ac, r.dyn, r.reason) === (:secure, :refused_at_trip, :voltage)
    @test all(o -> isempty(o[]), win.plots.mach) && all(o -> isempty(o[]), win.plots.mach_z)
    @test isempty(win.plots.coi[]) && isempty(win.plots.coi_z[])
    @test occursin("refused_at_trip (voltage)", win.plots.refusal[])
    @test split(win.readout.values[], '\n')[6] == "refused_at_trip (voltage)"
    # The settled lines are still drawn: both screens did settle.
    @test length(win.plots.settle_ac[]) == 1
    # The selected row is outlined in the overview.
    i = findfirst(x -> x[1] === :case9 && x[2] === :constant_power && x[3].id === :G2,
                  win.plots.overview)
    @test win.plots.selected_box[].origin[2] == length(win.plots.overview) - i
    # Back to a measured outage: drawn again, the refusal cleared, nothing re-run.
    before = win.cache[(:case9, :constant_power)]
    click!(w.lost_buttons[:G3])
    @test isempty(win.plots.refusal[]) && !isempty(win.plots.coi[])
    @test win.cache[(:case9, :constant_power)] === before
    click!(w.load_buttons[:default])
    @test win.choice.loads[] === :default && win.row[] === win.cache[(:case9, :default)].rows[3]
end

@testset "frequency_screen_render writes a PNG of the same window" begin
    path = joinpath(mktempdir(), "frequency-screen.png")
    @test frequency_screen_render(; path, cache = _FS_CACHE) == path
    @test isfile(path) && filesize(path) > 10_000
end
