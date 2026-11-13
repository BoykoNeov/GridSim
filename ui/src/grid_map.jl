# The geometry every grid sketch needs, in one place.
#
# Three windows draw a grid as dots and lines (the editor, the double-outage window, the
# network-dispatch window), and each had placed its line names by its own rule: centred ON
# the line in two of them, so a name was struck through by the line it named, and by a
# ring-or-spur special case in the third, which only knows case9. The shipped figures showed
# all three (`L67`, `L82`, `L94` in the double-outage figure; "L89 100% AT LIMIT" in the
# dispatch figure; "L31 53.5 MW" in the editor's). What follows is render state only
# (docs/SPEC.md §3): it reads positions and names, never a model's numbers.
#
# Two rules, both derived rather than tuned per grid:
#
#   A LINE'S NAME SITS BESIDE THE LINE, ON THE SIDE AWAY FROM THE GRID'S CENTRE, AND ITS BOX
#   IS PUSHED OUT UNTIL NO CORNER TOUCHES THE LINE. The push is computed from the text's own
#   size, so a long label ("L89 100% AT LIMIT") clears the line as surely as a short one.
#
#   WHAT HANGS OFF A BUS (a generator, a load) GOES WHERE NO LINE LEAVES IT. Eight compass
#   directions are scored by their angle to every line at that bus and to what was already
#   placed there; the freest wins, ties broken outward.

_gm_unit(p) = (n = sqrt(p[1]^2 + p[2]^2); n > 0 ? Point2f(p[1] / n, p[2] / n) : Point2f(0, 1))
_gm_dot(a, b) = a[1] * b[1] + a[2] * b[2]

"""
    grid_centre(points) -> Point2f

The mean of the drawn bus positions: the "inside" a line label is kept away from.
"""
function grid_centre(points)
    n = 0; sx = 0.0; sy = 0.0
    for p in points
        sx += p[1]; sy += p[2]; n += 1
    end
    return n == 0 ? Point2f(0, 0) : Point2f(sx / n, sy / n)
end

"""
    line_label_placement(p, q, centre, text; fontsize = 10, gap = 5, scale = (1, 1))
        -> (; at, align, offset, normal)

Where to write `text` beside the line from `p` to `q` so that it never lies on the line:
anchored at the midpoint (`at`, data coordinates), shifted by `offset` PIXELS along the
line's normal on the side away from `centre`, with the `align` that keeps the text box on
that side. Pass the three to `text!(ax, at; text, align, offset)`. With `centred = true`
the alignment is `(:center, :center)` whatever the line's direction.

`scale` is pixels per data unit in x and y. It matters only on an axis without
`DataAspect`, where a normal in data coordinates is not a normal on the screen.

A line that points straight at the centre (a spur) has no outward side; its label goes to
the right, or above a horizontal one — a fixed rule, so a redraw never moves it.
"""
function line_label_placement(p, q, centre, text::AbstractString;
                              fontsize::Real = 10, gap::Real = 5, scale = (1, 1),
                              centred::Bool = false)
    mid = Point2f((p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
    t = _gm_unit(((q[1] - p[1]) * scale[1], (q[2] - p[2]) * scale[2]))
    n = Point2f(-t[2], t[1])
    out = Point2f((mid[1] - centre[1]) * scale[1], (mid[2] - centre[2]) * scale[2])
    s = _gm_dot(n, out)
    if abs(s) <= 0.05 * sqrt(_gm_dot(out, out))
        (n[1] < -1e-6 || (abs(n[1]) <= 1e-6 && n[2] < 0)) && (n = -n)
    elseif s < 0
        n = -n
    end
    # `centred`: one alignment for every label, for a plot that draws all its labels with a
    # single `align` (the editor's); the push below still clears the line.
    ha = centred ? :center : n[1] > 0.38 ? :left : n[1] < -0.38 ? :right : :center
    va = centred ? :center : n[2] > 0.38 ? :bottom : n[2] < -0.38 ? :top : :center
    fx = ha === :left ? 0.0 : ha === :center ? 0.5 : 1.0
    fy = va === :bottom ? 0.0 : va === :center ? 0.5 : 1.0
    # The text box's extent, estimated: 0.6 em per character is the monospace advance and
    # an over-estimate for the proportional face, which is the safe side.
    w = 0.6 * fontsize * length(text); h = 1.15 * fontsize
    # The corner nearest the line, measured along the normal from the anchor (≤ 0); the
    # shift that puts that corner `gap` pixels clear of the line.
    nearest = min(-fx * w * n[1], (1 - fx) * w * n[1]) + min(-fy * h * n[2], (1 - fy) * h * n[2])
    d = gap - nearest
    return (; at = mid, align = (ha, va), offset = (d * n[1], d * n[2]), normal = n)
end

const _GM_COMPASS = [Point2f(cos(a), sin(a)) for a in (0:7) .* (π / 4)]

"""
    free_directions(pos, edges, bus, n = 1; centre = grid_centre(values(pos))) -> Vector{Point2f}

`n` unit directions at `bus` in which nothing is drawn yet: each is the compass direction
(of eight) furthest in angle from every line leaving the bus and from the directions
already handed out, ties broken away from `centre`, then upward. `pos` maps a bus id to its
position, `edges` is the `(from, to)` pairs of the drawn lines.
"""
function free_directions(pos, edges, bus::Symbol, n::Integer = 1;
                         centre = grid_centre(values(pos)))
    here = Point2f(pos[bus]...)
    taken = Point2f[]
    for (a, b) in edges
        a === bus && b !== bus && push!(taken, _gm_unit(Point2f(pos[b]...) - here))
        b === bus && a !== bus && push!(taken, _gm_unit(Point2f(pos[a]...) - here))
    end
    outward = here - Point2f(centre[1], centre[2])
    outward = sqrt(_gm_dot(outward, outward)) > 1e-6 ? _gm_unit(outward) : Point2f(0, 1)
    chosen = Point2f[]
    for _ in 1:n
        best = _GM_COMPASS[1]; best_score = -Inf
        for c in _GM_COMPASS
            # Crowding: the largest cosine to anything already there (1 = on top of it).
            crowd = isempty(taken) ? -1.0 : maximum(_gm_dot(c, d) for d in taken)
            score = -crowd + 0.05 * _gm_dot(c, outward) + 0.005 * c[2]
            score > best_score && ((best, best_score) = (c, score))
        end
        push!(chosen, best); push!(taken, best)
    end
    return chosen
end

"""
    direction_align(d) -> (halign, valign)

The text alignment that keeps a label on the far side of a marker placed in direction `d`.
"""
direction_align(d) = (d[1] > 0.38 ? :left : d[1] < -0.38 ? :right : :center,
                      d[2] > 0.38 ? :bottom : d[2] < -0.38 ? :top : :center)
