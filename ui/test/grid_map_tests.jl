# The grid sketches' shared geometry (`../src/grid_map.jl`, 2026-11-13).
#
# What is asserted is the property the file exists for, not the numbers it happens to
# produce: a line's label never touches the line it names, whatever the line's direction
# and however long the text; and what hangs off a bus goes where no line leaves it.

const _GM = GridSimUI

# The label's box (estimated exactly as `line_label_placement` estimates it), in pixels
# relative to the line's midpoint; its smallest distance from the line along the normal.
function _gm_clearance(p, q, centre, text; fontsize = 10, gap = 5, centred = false)
    pl = _GM.line_label_placement(p, q, centre, text; fontsize, gap, centred)
    w = 0.6 * fontsize * length(text); h = 1.15 * fontsize
    fx = pl.align[1] === :left ? 0.0 : pl.align[1] === :center ? 0.5 : 1.0
    fy = pl.align[2] === :bottom ? 0.0 : pl.align[2] === :center ? 0.5 : 1.0
    corners = [(pl.offset[1] + x, pl.offset[2] + y)
               for x in (-fx * w, (1 - fx) * w), y in (-fy * h, (1 - fy) * h)]
    n = pl.normal
    return (; clear = minimum(c[1] * n[1] + c[2] * n[2] for c in corners), pl)
end

@testset "grid map: a line's label never touches its line" begin
    centre = Point2f(0, 0)
    for θ in 0:7:359, text in ("L1", "L89 100% AT LIMIT"), centred in (false, true)
        # A chord of the unit circle around the centre, in every direction.
        a = deg2rad(θ)
        mid = Point2f(cos(a), sin(a))
        t = Point2f(-sin(a), cos(a))
        r = _gm_clearance(mid - 0.4f0 * t, mid + 0.4f0 * t, centre, text; centred)
        @test r.clear ≥ 5 - 1e-3                    # every corner at least `gap` px clear
        # …and on the side away from the centre.
        @test r.pl.normal[1] * mid[1] + r.pl.normal[2] * mid[2] > 0.99
        centred && @test r.pl.align == (:center, :center)
    end
    # A spur pointing straight at the centre has no outward side: the rule is fixed
    # (right of a vertical line, above a horizontal one), so a redraw never moves it.
    v = _GM.line_label_placement(Point2f(0, -1), Point2f(0, -2), centre, "L14")
    @test v.normal[1] > 0.99 && v.align[1] === :left
    h = _GM.line_label_placement(Point2f(1, 0), Point2f(2, 0), centre, "L")
    @test h.normal[2] > 0.99 && h.align[2] === :bottom
    # Reversing the line's direction does not move its label.
    for (p, q) in ((Point2f(-0.87, 0.5), Point2f(0, 1)), (Point2f(0, -1), Point2f(0, -1.8)))
        a = _GM.line_label_placement(p, q, centre, "L67")
        b = _GM.line_label_placement(q, p, centre, "L67")
        @test a.align == b.align && all(isapprox.(a.offset, b.offset; atol = 1e-4))
    end
    # A longer label is pushed further out, never left to overlap.
    short = _GM.line_label_placement(Point2f(-1, 1), Point2f(1, 1.4), centre, "L1")
    long = _GM.line_label_placement(Point2f(-1, 1), Point2f(1, 1.4), centre, "L1 100% AT LIMIT")
    @test hypot(long.offset...) > hypot(short.offset...)
end

@testset "grid map: what hangs off a bus goes where no line leaves it" begin
    pos = GridSimUI.DO_POSITIONS[:case9]
    edges = [(:B1, :B4), (:B4, :B5), (:B5, :B6), (:B3, :B6), (:B6, :B7), (:B7, :B8),
             (:B8, :B2), (:B8, :B9), (:B9, :B4)]
    P(b) = Point2f(pos[b]...)
    for bus in keys(pos)
        dirs = _GM.free_directions(pos, edges, bus, 2)
        @test length(dirs) == 2 && dirs[1] != dirs[2]
        nb = [e[1] === bus ? e[2] : e[1] for e in edges if bus in e]
        for d in dirs, o in nb
            u = P(o) - P(bus); u = u / hypot(u...)
            @test d[1] * u[1] + d[2] * u[2] < cosd(40)   # at least 40° from every line
        end
    end
    # B1 hangs below B4 on a vertical spur: its generator goes straight down, away from
    # the line — in the old drawing G1's marker sat ON the line L14.
    @test _GM.free_directions(pos, edges, :B1, 1)[1] ≈ Point2f(0, -1)
    @test _GM.direction_align(Point2f(0, -1)) == (:center, :top)
    @test _GM.direction_align(Point2f(1, 0)) == (:left, :center)
    @test _GM.grid_centre([Point2f(0, 0), Point2f(2, 4)]) == Point2f(1, 2)
    @test _GM.counted(1, "line") == "1 line" && _GM.counted(3, "line") == "3 lines"
end

@testset "grid map: the windows use it" begin
    # The editor's branch labels: one offset per label, none of them zero (a zero offset
    # is a label centred on its line, which is what this replaced).
    win = GridSimUI._build_editor_window(GridSimUI.ScenarioEditor(three_machine_ring()))
    labs = win.plots.branch_labels[]
    offs = win.plots.branch_label_offsets[]
    @test length(labs) == 3 == length(offs)
    @test all(o -> hypot(o...) ≥ 5, offs)
    # The network window's status line counts in the singular.
    nw = GridSimUI._build_network_window(two_machine_system())
    @test occursin("1 line in service", nw.status[])
end
