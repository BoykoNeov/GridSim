# The low-inertia window (`../src/low_inertia_window.jl`, M7 step 8).
#
# What is asserted is that the window DRAWS THE STUDY and nothing of its own: its
# read-out is the study's row (`isequal`, not `≈` — one computation, not two), its two
# inverter runs at zero share are one model built twice (`==`, every sample), a refused
# run leaves nothing of the previous setting on screen, and the meter panels never draw
# a point off their own scale without saying so in a number.
#
# A SHORT HORIZON throughout (`T = T_TRIP + 2`): every claim here is about how the window
# handles the runs, not about the physics after a second, and the study's own tolerance
# is kept so the equality with `study_cell` is an equality with the script's numbers.

const LBUILD = GridSimUI._build_low_inertia_window
const _LS = GridSimUI.LowInertiaStudy
const _LT = _LS.T_TRIP + 2.0

_strip(row) = Base.structdiff(row, NamedTuple{(:series,)})

@testset "low-inertia window: the read-out is the study's own row" begin
    win = LBUILD(; topology = :ring, event = :G4, n = 1, T = _LT)
    m = _LS.matched_dispatch(:ring; slack = _LS._slack(:G4))
    for (kind, k) in ((:machine, 0), (:grid_following, 1), (:grid_forming, 1))
        @test isequal(_strip(win.rows[kind]), _LS.study_cell(:ring, :G4, kind, k; T = _LT, match = m,
                                      reltol = GridSimUI.LI_RELTOL, abstol = GridSimUI.LI_ABSTOL))
        @test win.rows[kind].status === :ok
    end
    # The table says what the rows say, column by column.
    nad = [GridSimUI.@sprintf("%.3f", win.rows[k].nadir) for k in GridSimUI.LI_KINDS]
    @test occursin(join(lpad.(nad, 8), " "), win.readout[])
    @test occursin("G3 replaced", win.plots.displaced_text[])   # the study's order: smallest other unit first
end

@testset "low-inertia window: at zero share the two inverter runs are one model, drawn twice" begin
    win = LBUILD(; topology = :ring, event = :G4, n = 0, T = _LT)
    sf, sm, sx = (win.rows[k].series for k in (:grid_following, :grid_forming, :machine))
    @test sf.t == sm.t == sx.t
    @test sf.f_coi == sm.f_coi == sx.f_coi
    @test win.plots.coi[:grid_following][] == win.plots.coi[:grid_forming][]
    # ...and the moment one unit is displaced they are not — the check is not vacuous.
    win.choice.n[] = 1
    @test win.rows[:grid_following].series.f_coi != win.rows[:grid_forming].series.f_coi
    @test win.plots.coi[:grid_following][] != win.plots.coi[:grid_forming][]
end

@testset "low-inertia window: the controls re-run, and a refusal leaves nothing behind" begin
    win = LBUILD(; topology = :ring, event = :G4, n = 1, T = _LT)
    w = win.widgets
    @test startswith(w.event_buttons[:G4].label[], "▸")
    @test startswith(w.share_buttons[1].label[], "▸") && startswith(w.layout_buttons[:ring].label[], "▸")
    gfl_before = win.plots.coi[:grid_following][]
    @test maximum(p[1] for p in gfl_before) > _LS.T_TRIP + 1        # it ran past the trip

    # The big trip with two units displaced by grid-following inverters: refused (m7-context.md D16).
    click!(w.event_buttons[:G1]); click!(w.share_buttons[2])
    @test win.choice.event[] === :G1 && win.choice.n[] == 2
    @test startswith(w.event_buttons[:G1].label[], "▸") && !startswith(w.event_buttons[:G4].label[], "▸")
    r = win.rows[:grid_following]
    @test r.status === :refused && !isempty(r.reason)
    @test occursin("refused", win.plots.refusal[:grid_following][])
    @test occursin(r.reason, win.plots.refusal[:grid_following][])
    # Nothing of the previous run survives: whatever is drawn for the refused run stops
    # at the refusal, and the read-out's grid-following column is dashes.
    @test all(p -> p[1] <= _LS.T_TRIP + 1e-9, win.plots.coi[:grid_following][])
    @test all(o -> all(p -> p[1] <= _LS.T_TRIP + 1e-9, o[]), win.plots.meter_pts[:grid_following])
    nadir_line = only(filter(l -> startswith(l, "nadir"), split(win.readout[], '\n')))
    @test split(nadir_line)[end-1] == "—"
    # The grid-forming run at the same setting ran, and is drawn.
    @test win.rows[:grid_forming].status === :ok
    @test isempty(win.plots.refusal[:grid_forming][])
    # A run refused BEFORE it starts — every unit grid-following, nothing left to set a
    # voltage (D5) — has no samples at all, so only the clearing stands between the
    # screen and the previous setting's curves. The refusal above does not reach this:
    # a run refused at the trip still records its pre-trip second, which overwrites them.
    click!(w.share_buttons[4])
    r = win.rows[:grid_following]
    @test r.status === :refused && r.series === nothing && occursin("D5", r.reason)
    @test isempty(win.plots.coi[:grid_following][]) && isempty(win.plots.coi_zoom[:grid_following][])
    @test all(o -> isempty(o[]), win.plots.meter_pts[:grid_following])
    @test occursin("grid-following: ", win.status[])                 # named in the status line
    # A cached setting comes back without a re-run: the same row object.
    click!(w.event_buttons[:G4]); click!(w.share_buttons[1])
    @test win.rows[:grid_following] === win.cache[(:ring, :G4, :grid_following, 1)]
    @test isempty(win.plots.refusal[:grid_following][])
    click!(w.layout_buttons[:chain])
    @test win.choice.topology[] === :chain && haskey(win.cache, (:chain, :G4, :grid_forming, 1))
end

@testset "low-inertia window: a meter off the panel's scale is reported, never silently clipped" begin
    # A setting where a grid-forming meter DOES leave the scale (found by sweeping every
    # setting; most leave none, and on those the check below is true of any window).
    win = LBUILD(; topology = :chain, event = :G4, n = 3, T = _LT)
    @test !isempty(win.plots.notes[:grid_forming][])
    # ...and the number it gives is the most extreme meter reading in the panel. The first
    # version seeded that search with 0.0 and printed "meter peak 0.000 Hz".
    m = match(r"meter peak ([0-9.]+) Hz", win.plots.notes[:grid_forming][])
    zs = [p[2] for o in win.plots.meter_pts[:grid_forming] for p in o[]]
    ext = zs[argmax(abs.(zs .- _LS.F0))]
    @test parse(Float64, m.captures[1]) ≈ ext atol = 5e-4
    # The scale is the CENTRE OF INERTIA's, both runs, with the stated margin — not an
    # autoscale, which the meters' spike at the trip would set (the file header). Without
    # this the check below passes on an autoscaled axis too: nothing off scale, no note.
    cz = [p[2] for k in (:grid_following, :grid_forming) for p in win.plots.coi_zoom[k][]]
    lo, hi = extrema(cz); pad = max(0.25 * (hi - lo), 0.1)
    l = win.axes.gfl.finallimits[]
    @test l.origin[2] ≈ lo - pad atol = 1e-4
    @test l.origin[2] + l.widths[2] ≈ hi + pad atol = 1e-4
    for (kind, ax) in ((:grid_following, win.axes.gfl), (:grid_forming, win.axes.gfm))
        lims = ax.finallimits[]
        ylo, yhi = lims.origin[2], lims.origin[2] + lims.widths[2]
        outside = any(o -> any(p -> !(ylo <= p[2] <= yhi), o[]), win.plots.meter_pts[kind])
        @test outside == !isempty(win.plots.notes[kind][])
        # The centre of inertia itself is always inside: the scale is set from it.
        @test all(p -> ylo <= p[2] <= yhi, win.plots.coi_zoom[kind][])
    end
end

@testset "low_inertia_render writes a PNG of the same window" begin
    path = joinpath(mktempdir(), "low-inertia.png")
    @test low_inertia_render(; path, T = _LT) == path
    @test isfile(path) && filesize(path) > 10_000
end
