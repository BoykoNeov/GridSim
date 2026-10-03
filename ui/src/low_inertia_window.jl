# The low-inertia window (M7 step 8) — step 7's study, drawn, and re-run when a control
# changes: the same generator trip with no inverters, with units displaced by
# GRID-FOLLOWING inverters, and with the same units displaced by GRID-FORMING ones.
#
# THE STUDY IS NOT COPIED HERE. Its fixture, its matched dispatch and every number it
# prints live in `scripts/low_inertia.jl`, which this package `include`s into a
# submodule exactly as the core's test suite does (`test/runtests.jl`). So the UI
# package now DEPENDS ON A FILE OUTSIDE `ui/src` — said here because nothing else
# would say it: moving or renaming that script breaks this package's load. The
# alternative, a second copy of the fixture beside the window, is the parallel model
# SPEC §3.2 forbids, and a window whose numbers could drift from the table it claims
# to draw would be worse than no window. The window's read-out is the study's own row
# (`study_cell(…; keep = true)` adds the samples and changes nothing else), and a test
# asserts `isequal` between the two.
#
# "LIVE" MEANS RE-RUN, NOT ANIMATED (m7-context.md D17). The detailed tier, the only
# one that holds a grid-following inverter, has no real-time loop (`step!` is not
# implemented for it, m5-context.md D2). So every control change runs the three
# simulations to completion and redraws; results are cached by (layout, event, kind,
# share), so going back to a setting is instant.
#
# THE WINDOW'S TOLERANCE IS NOT THE STUDY'S, AND THE READ-OUT SAYS WHICH IT IS. Measured
# warm (D17): at the study's reltol 1e-6 one run takes 1.5–8 s and one cell 36 s, so a
# click would wait 5–50 s for its three runs; at 1e-4 a run takes 0.2–2 s. Against the
# study's numbers, 1e-4 moves RoCoF₀ and min |V| by nothing at six decimals, the 500 ms
# COI reading by ≤ 1e-6 Hz/s, the PLL reading by ≤ 2.5e-4 Hz/s and the nadir by ≤ 1e-5 Hz
# — except the one cell whose frequency sinks to the end of the run, where it moves
# 2.3 mHz, and where 1e-5 moves it 4.5 mHz: the third decimal of that number is noise at
# every tolerance tried. So the window runs at 1e-4 by default, and `reltol = 1e-6`
# reproduces the study exactly (same function, same samples; a test asserts `isequal`).
#
# WHAT THE THREE PANELS ARE FOR (the user's layout, D17).
#
#   - TOP: the centre-of-inertia frequency of all three runs on one axis — the
#     inertia-weighted average every relay-free statement about "the frequency" means.
#     No inverters in grey, grid-following orange, grid-forming purple.
#   - BOTTOM, one per kind: the frequency the per-bus PLL METERS read (thin, one per
#     bus) behind that run's centre-of-inertia trace (bold). This is Hurdle 10 drawn: a
#     meter reads the bus voltage's phase, and at the trip the phase JUMPS, so a meter
#     reports a frequency excursion no rotor made (measured in step 6). How much of a
#     given meter's departure here is that, and how much a machine's own swing at its
#     bus, the study did not separate (D16) — so the window draws it and does not
#     label it. The bottom panels zoom on the first 1.5 s after the trip, where it lives.
#
# THE SPIKE IS CLIPPED, AND SAYS SO. Left to autoscale, the meters' spike at the trip
# sets the axis and flattens the centre-of-inertia trace into a line — the lesson
# hidden by its own illustration. The two meter panels share one y-range, set by the
# centre-of-inertia traces with a margin, and anything outside it is reported in the
# panel as a number ("meter peak … Hz (off scale)") rather than drawn — the number
# only, not a cause: the study could not say which mechanism sets it on the chain.
#
# EACH RUN ON ITS OWN TIME AXIS. The three runs are separate integrations whose sample
# times differ; they are overlaid, never subtracted. No difference between two runs is
# computed anywhere in this file (M4's rule against resampling, `analysis/postprocess.jl`).
#
# A REFUSED RUN IS THE COMMON CASE. On the large trip most grid-following rows leave the
# tier's 0.9 pu voltage band at t⁺ or have no post-trip solution. A refused run draws
# whatever it recorded before the refusal (often the flat pre-trip second) and its reason
# in place of the rest, and nothing from a previous setting survives a change.

module LowInertiaStudy
# The study script, verbatim — see the file header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "..", "..", "scripts", "low_inertia.jl"))
end

const _LIS = LowInertiaStudy

# The window's default solver tolerances (file header, D17) — the study's are
# `_LIS.RELTOL`/`_LIS.ABSTOL`, one keyword away.
const LI_RELTOL = 1.0e-4
const LI_ABSTOL = 1.0e-6

const LI_KINDS = (:machine, :grid_following, :grid_forming)
const LI_COLOURS = Dict(:machine => C_MUTED, :grid_following => C_AGGREGATE,
                        :grid_forming => RGBf(0.55, 0.30, 0.75))
const LI_NAMES = Dict(:machine => "no inverters", :grid_following => "grid-following",
                      :grid_forming => "grid-forming")
# How long after the trip the meter panels show. The meters' spike at the trip and the PLL's
# ringing are over within it; the frequency's slow fall is the top panel's business.
# 1.5 s and not the first render's 4: over 4 s the grid-following run's 2 Hz fall set
# the shared scale and the meters' departure from it — the thing the panels are for —
# was a sliver at the left edge (the meters rejoin the centre of inertia by ~1.5 s).
const LI_ZOOM = 1.5

# The units displaced at share `n`, in the study's own order (the OTHER units smallest
# first, then the tripped one), so the control can say which machines became inverters.
_li_displaced(event::Symbol, n::Integer) = _LIS.displacement_order(event)[1:n]

_li_mw(event::Symbol) = Dict(u[1] => u[5] for u in _LIS.UNITS)[event]

# The meter channels of one run, in Hz. `ωmeter_<bus>` is a per-unit deviation.
function _li_meters(series, f0)
    names = [c for c in keys(series) if startswith(String(c), "ωmeter_")]
    return [(Symbol(String(c)[length("ωmeter_")+1:end]), f0 .* (1 .+ getfield(series, c)))
            for c in names]
end

function _build_low_inertia_window(; kwargs...)
    themed(() -> _build_low_inertia_window_impl(; kwargs...))
end

function _build_low_inertia_window_impl(; topology::Symbol = :ring, event::Symbol = :G4,
                                        n::Integer = 2, T::Real = _LIS.T_END,
                                        reltol::Real = LI_RELTOL,
                                        abstol::Real = LI_ABSTOL)
    topology in (:ring, :chain) || throw(ArgumentError(
        "low-inertia window: layout must be :ring or :chain, got :$topology."))
    event in (:G1, :G4) || throw(ArgumentError(
        "low-inertia window: the study trips :G1 or :G4 (m7-context.md D16), got :$event."))
    0 <= n <= length(_LIS.UNITS) || throw(ArgumentError(
        "low-inertia window: units displaced must be 0–$(length(_LIS.UNITS)), got $n."))
    f0 = _LIS.F0
    t_trip = _LIS.T_TRIP

    fig = Figure(size = (1500, 950))
    ax_f = Axis(fig[1, 1:2]; xlabel = "time (s)", ylabel = "frequency (Hz)")
    ax_m = Dict(:grid_following => Axis(fig[2, 1]; xlabel = "time (s)",
                                        ylabel = "frequency (Hz)"),
                :grid_forming => Axis(fig[2, 2]; xlabel = "time (s)"))
    linkyaxes!(ax_m[:grid_following], ax_m[:grid_forming])
    rowsize!(fig.layout, 1, Relative(0.5))

    # ---- the top panel: one centre-of-inertia trace per run --------------------------
    coi = Dict(k => Observable(Point2f[]) for k in LI_KINDS)
    for k in LI_KINDS
        lines!(ax_f, coi[k]; color = LI_COLOURS[k], linewidth = k === :machine ? 2.5 : 2.2,
               label = LI_NAMES[k])
    end
    vlines!(ax_f, [t_trip]; color = (C_EVENT, 0.5), linestyle = :dash)
    axislegend(ax_f; position = :rb)

    # ---- the bottom panels: the meters behind each run's own centre of inertia -------
    # One `lines!` per meter, built once: every run of this study arms a meter on each of
    # the same seven buses, so the count never changes and nothing is rebuilt per run.
    nbus = length(_LIS.study_network(:ring).buses)
    meter_pts = Dict(k => [Observable(Point2f[]) for _ in 1:nbus]
                     for k in (:grid_following, :grid_forming))
    coi_zoom = Dict(k => Observable(Point2f[]) for k in (:grid_following, :grid_forming))
    notes = Dict(k => Observable("") for k in (:grid_following, :grid_forming))
    refusal = Dict(k => Observable("") for k in LI_KINDS)
    for k in (:grid_following, :grid_forming)
        ax = ax_m[k]
        for o in meter_pts[k]
            lines!(ax, o; color = (LI_COLOURS[k], 0.45), linewidth = 1.0)
        end
        lines!(ax, coi_zoom[k]; color = LI_COLOURS[k], linewidth = 2.6)
        vlines!(ax, [t_trip]; color = (C_EVENT, 0.5), linestyle = :dash)
        text!(ax, 0.02, 0.04; text = notes[k], space = :relative, align = (:left, :bottom),
              fontsize = 12, color = C_EVENT)
        text!(ax, 0.5, 0.55; text = refusal[k], space = :relative, align = (:center, :center),
              fontsize = 14, color = C_WARN, word_wrap_width = 520)
    end
    text!(ax_f, 0.02, 0.06; text = refusal[:machine], space = :relative,
          align = (:left, :bottom), fontsize = 13, color = C_WARN)

    # ---- the controls and the read-out ----------------------------------------------
    gc = fig[1:2, 3] = GridLayout(tellheight = false, valign = :top)
    colsize!(fig.layout, 3, Fixed(400))

    choice = (; topology = Observable(topology), event = Observable(event),
                n = Observable(Int(n)))
    status = Observable("")

    section_label!(gc[1, 1], "generator tripped")
    ge = gc[2, 1] = GridLayout()
    event_buttons = Dict(e => Button(ge[1, i]; label = "") for (i, e) in enumerate((:G1, :G4)))
    section_label!(gc[3, 1], "units displaced by inverters")
    gn = gc[4, 1] = GridLayout()
    share_buttons = Dict(k => Button(gn[1, k + 1]; label = "") for k in 0:length(_LIS.UNITS))
    displaced_text = Observable("")
    Label(gc[5, 1], displaced_text; halign = :left, tellwidth = false, fontsize = 12,
          color = C_MUTED, word_wrap = true, justification = :left)
    section_label!(gc[6, 1], "network layout")
    gt = gc[7, 1] = GridLayout()
    layout_buttons = Dict(t => Button(gt[1, i]; label = "") for (i, t) in enumerate((:ring, :chain)))

    section_label!(gc[8, 1], @sprintf("read-out (Hz, Hz/s, pu) — reltol %.0e", reltol))
    readout = Observable("")
    Label(gc[9, 1], readout; halign = :left, tellwidth = false, font = MONO_FONT,
          fontsize = 12, justification = :left)
    Label(gc[10, 1], status; halign = :left, tellwidth = false, fontsize = 12,
          color = C_SWING, word_wrap = true, justification = :left)
    # How to read it — the three things the picture cannot say by itself (D17).
    Label(gc[11, 1], "All three runs start from the same operating point: a displaced " *
          "machine becomes an inverter at its bus with the same output. Thin lines are " *
          "what a PLL meter at each bus reads — what a relay sees. At the trip the bus " *
          "voltage angles jump, and a meter reads that as a frequency swing no rotor " *
          "made. The grid-forming inverters have no current limit: GFM S/S_rated above " *
          "1 means the model ran them past their rating.";
          halign = :left, tellwidth = false, fontsize = 11, color = C_MUTED,
          word_wrap = true, justification = :left)

    # ---- running and drawing ------------------------------------------------------
    cache = Dict{Tuple{Symbol,Symbol,Symbol,Int},Any}()
    matches = Dict{Tuple{Symbol,Symbol},Any}()
    function cell(topo, ev, kind, k)
        key = (topo, ev, kind, k)
        haskey(cache, key) && return cache[key]
        m = get!(() -> _LIS.matched_dispatch(topo; slack = _LIS._slack(ev)), matches, (topo, ev))
        cache[key] = _LIS.study_cell(topo, ev, kind, k; T, reltol, abstol, match = m,
                                     keep = true)
        return cache[key]
    end

    rows = Dict{Symbol,Any}()
    function redraw!()
        topo, ev, k = choice.topology[], choice.event[], choice.n[]
        for (e, b) in event_buttons
            b.label[] = (e === ev ? "▸ " : "") * @sprintf("%s (%d MW)", e, _li_mw(e))
        end
        for (j, b) in share_buttons
            b.label[] = (j == k ? "▸ " : "") * string(j)
        end
        for (t, b) in layout_buttons
            b.label[] = (t === topo ? "▸ " : "") * String(t)
        end
        dis = _li_displaced(ev, k)
        share = 100 * sum((u[5] for u in _LIS.UNITS if u[1] in dis); init = 0.0) / _LIS.GEN_MW
        displaced_text[] = k == 0 ? "every unit is a machine" :
            @sprintf("%s replaced (%.0f %% of the generation)", join(dis, ", "), share)

        # The no-inverter run uses n = 0 of its own key; the two inverter runs at n = 0
        # are the SAME model built twice, and the test asserts their traces `==`.
        for kind in LI_KINDS
            rows[kind] = cell(topo, ev, kind, kind === :machine ? 0 : k)
        end

        # Clear everything first: nothing from the last setting may survive this one.
        for kind in LI_KINDS
            coi[kind][] = Point2f[]
            refusal[kind][] = ""
        end
        for kind in (:grid_following, :grid_forming)
            foreach(o -> o[] = Point2f[], meter_pts[kind])
            coi_zoom[kind][] = Point2f[]
            notes[kind][] = ""
        end

        zoom = (t_trip - 0.25, t_trip + LI_ZOOM)
        lo, hi = Inf, -Inf
        for kind in LI_KINDS
            r = rows[kind]
            s = r.series
            if s !== nothing
                coi[kind][] = Point2f.(s.t, s.f_coi)
            end
            r.status === :ok || (refusal[kind][] = LI_NAMES[kind] * " — refused: " * r.reason)
            kind === :machine && continue
            s === nothing && continue
            inz = findall(t -> zoom[1] <= t <= zoom[2], s.t)
            coi_zoom[kind][] = Point2f.(s.t[inz], s.f_coi[inz])
            if !isempty(inz)
                lo = min(lo, minimum(s.f_coi[inz])); hi = max(hi, maximum(s.f_coi[inz]))
            end
            for (j, (_, f)) in enumerate(_li_meters(s, f0))
                meter_pts[kind][j][] = Point2f.(s.t[inz], f[inz])
            end
        end
        # The shared meter range: the centre-of-inertia traces with a margin, never less
        # than 0.2 Hz tall. Whatever a meter reads outside it is a NUMBER in the panel.
        if isfinite(lo)
            pad = max(0.25 * (hi - lo), 0.1)
            ylo, yhi = lo - pad, hi + pad
            for kind in (:grid_following, :grid_forming)
                limits!(ax_m[kind], zoom..., ylo, yhi)
                s = rows[kind].series
                s === nothing && continue
                inz = findall(t -> zoom[1] <= t <= zoom[2], s.t)
                peak = 0.0; tpk = NaN
                for (_, f) in _li_meters(s, f0), i in inz
                    d = f[i] < ylo ? ylo - f[i] : f[i] > yhi ? f[i] - yhi : 0.0
                    d > peak && (peak = d; tpk = s.t[i])
                end
                if peak > 0
                    # The reading furthest from nominal. Seeded with `f0`, not 0.0: seeded
                    # with zero nothing a meter reads is further from 50 Hz than zero is,
                    # and the first render that went off scale said "meter peak 0.000 Hz".
                    fext = f0
                    for (_, f) in _li_meters(s, f0), i in inz
                        abs(f[i] - f0) > abs(fext - f0) && (fext = f[i])
                    end
                    # The reading and nothing more. WHY a meter leaves the scale is not
                    # attributed here: on the chain the study could not separate the
                    # trip's phase jump from a machine's own swing at its bus, and its
                    # first draft's "the phase jump, which no rotor felt" was withdrawn as
                    # a story (m7-context.md D16). The caption states the general effect.
                    notes[kind][] = @sprintf("meter peak %.3f Hz at t = %.2f s (off scale)",
                                             fext, tpk)
                end
            end
        else
            for kind in (:grid_following, :grid_forming)
                limits!(ax_m[kind], zoom..., f0 - 1, f0 + 0.2)
            end
        end
        reset_limits!(ax_f)

        ax_f.title[] = @sprintf("centre-of-inertia frequency — %s, trip %s (%d MW)",
                                topo, ev, _li_mw(ev))
        for kind in (:grid_following, :grid_forming)
            ax_m[kind].title[] = LI_NAMES[kind] * ": PLL meters (thin) and its centre of inertia"
        end
        readout[] = _li_readout(rows)
        refused = [LI_NAMES[k] * ": " * rows[k].reason for k in LI_KINDS
                   if rows[k].status !== :ok]
        status[] = isempty(refused) ? "all three runs completed" :
                   "refused — " * join(refused, "; ") *
                   ". A refused run draws what it recorded before the refusal."
        return nothing
    end

    # A control sets its choice; the choice re-runs. Kept apart so a test can set the
    # observables directly or click the buttons, and both take the one path.
    for (e, b) in event_buttons
        on(_ -> (choice.event[] = e), b.clicks)
    end
    for (j, b) in share_buttons
        on(_ -> (choice.n[] = j), b.clicks)
    end
    for (t, b) in layout_buttons
        on(_ -> (choice.topology[] = t), b.clicks)
    end
    for o in choice
        on(_ -> redraw!(), o)
    end
    redraw!()

    widgets = (; event_buttons, share_buttons, layout_buttons)
    plots = (; coi, meter_pts, coi_zoom, notes, refusal, displaced_text)
    return (; fig, axes = (; f = ax_f, gfl = ax_m[:grid_following], gfm = ax_m[:grid_forming]),
              choice, rows, cache, widgets, plots, readout, status, redraw!)
end

# The read-out: one column per run, the study's own numbers. A refused run shows dashes.
function _li_readout(rows)
    f = _LIS._f                # the study's own "—" for a number a refused run lacks
    hdr = @sprintf("%-15s %8s %8s %8s", "", "none", "GFL", "GFM")
    line(name, fld, fmt) = @sprintf("%-15s %8s %8s %8s", name,
                                    (f(getfield(rows[k], fld), fmt) for k in LI_KINDS)...)
    return join([hdr,
                 line("H after (s)", :H_post, "%.2f"),
                 line("RoCoF₀ formula", :rocof_cf, "%.3f"),
                 line("RoCoF₀ network", :rocof_inst, "%.3f"),
                 line("COI 500 ms", :rocof_coi, "%.3f"),
                 line("PLL 500 ms", :rocof_pll, "%.2f"),
                 line("nadir", :nadir, "%.3f"),
                 line("f at end", :f_end, "%.3f"),
                 line("min |V|", :V_min, "%.3f"),
                 line("GFM S/S_rated", :gfm_peak, "%.2f")], '\n')
end

"""
    low_inertia_playback(; topology = :ring, event = :G4, n = 2) -> window

Open the low-inertia window (M7 step 8): step 7's study (`scripts/low_inertia.jl`)
drawn, re-run whenever a control changes. One generator trip, three runs from the SAME
operating point — no inverters, `n` units displaced by grid-following inverters, the same
`n` by grid-forming ones — with the centre-of-inertia frequency of all three on top, and
per-bus PLL meters behind each inverter run's own centre of inertia below. Controls: which
generator trips (G1, 150 MW, or G4, 60 MW), how many units are displaced (0–4, the study's
order), and the layout (meshed ring or long chain). The read-out is the study's own row.

Each change runs three detailed-tier simulations to 30 s, at `reltol = 1e-4` by default
(0.2–2 s each, measured; the read-out names the tolerance) — pass `reltol = 1e-6,
abstol = 1e-8` for the study's own numbers exactly, at 1.5–36 s a run. Results are
cached, so returning to a setting is instant.

    julia --project=ui -e "using GridSimUI; wait_for_close(low_inertia_playback())"
"""
function low_inertia_playback(; kwargs...)
    GLMakie.activate!(; visible = true, title = "GridSim — low inertia")
    win = _build_low_inertia_window(; kwargs...)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    low_inertia_render(; path, topology = :ring, event = :G4, n = 2, T, reltol, abstol) -> path

Build the low-inertia window offscreen and save a PNG — how it is checked without a screen.
"""
function low_inertia_render(; path::AbstractString, kwargs...)
    GLMakie.activate!(; visible = false)
    win = _build_low_inertia_window(; kwargs...)
    mkpath(dirname(path))
    Makie.colorbuffer(win.fig)          # one throwaway frame (the text atlas, as elsewhere)
    save(path, win.fig)
    return path
end
