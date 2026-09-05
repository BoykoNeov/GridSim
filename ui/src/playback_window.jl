# The playback window (M4 step 3): a run that has already happened, scrubbed
# rather than watched.
#
# THE THIRD WINDOW, AND WHY IT IS A THIRD RATHER THAN A MODE ON THE SECOND. The
# other two windows in this package are siblings because the two *engines* accept
# different events. This one is a sibling for a different reason: it is the other
# EXECUTION MODE (docs/SPEC.md §2, §3.3). `window.jl` and `network_window.jl` show
# a run as it happens — an `Observable` written by `run_realtime!`, a rolling
# buffer, a repaint throttled to ~30 fps. Nothing here streams. `solve!` has
# already finished, the whole trajectory exists as two plain vectors, and the only
# live thing in the figure is where the reader has put the cursor.
#
# So there is no `EventQueue`, no `RealtimeControl`, no `refresh!` throttle and no
# task: every one of those exists to manage a run in progress, and there is no run
# in progress. Adding them for symmetry would be four pieces of machinery whose
# only content is that they do nothing.
#
# WHY THE BUILDER TAKES SERIES AND NOT A MODEL. `_build_playback_window` receives
# two already-solved series and the agreement band. It cannot solve, cannot step,
# and cannot choose a grid — which is "render state is not simulation state"
# (SPEC §3) in its strongest available form: this window is incapable of
# influencing the numbers it draws. The pair-building is three lines in
# `_solve_overlay` below, on top of `coi_model` — the compiled aggregate view the
# core already derives (SPEC §3.2) — so nothing here is a parallel model.
#
# THE SHARED GRID IS ENFORCED BY THE CORE, NOT RE-ENFORCED HERE. `divergence`
# refuses two series on different grids rather than resampling between them
# (`analysis/postprocess.jl`, M4 step 2 — straight-line resampling was measured at
# 33.7× the agreement band). This window calls it at build time, so a mismatched
# pair fails loudly here instead of being quietly interpolated onto one axis.
#
# THE CURSOR IS AN INDEX, NOT A TIME. The slider runs over sample indices, so
# every number the read-out shows is a recorded sample verbatim. A slider over
# *time* would need a value between two samples, and the only ways to produce one
# are the two the milestone rejected: interpolate (there is no interpolant left —
# both engines run `dense = false`, so a closed step's coefficients are gone) or
# straight-line between recorded samples (measured above). Indexing makes the
# refusal structural in the UI as well as in the read.
#
# THE BAND IS DERIVED AND DISPLAYED, NEVER ADJUSTABLE. `t_depart` — the instant
# the two tiers part company — is only an answer because the band was stated
# before the gap was seen (M4 step 2). A window is exactly where that discipline
# would die: a band slider lets a reader scrub, look at the gap, and then choose
# the band that puts the departure where they expected it. There is no such
# control. The band comes from `tolerance_band` on the solve's own `reltol`, and
# it is shown with its derivation so the number is auditable rather than magic.
# Exploring the tolerance means solving again on fresh engines, which re-derives
# the band with it.

# What the pair can and cannot support. Drawn in the figure rather than left in a
# docstring, because the reader who over-reads the picture is the one looking at
# the picture. Three claims, every one of which cost something to learn, and all
# three deliberately scenario-independent — a caption that described the run it
# happened to be over would be wrong the first time somebody passed a different
# one.
#
#   ONE LESSON OF THE THREE. SPEC §7.6 says the divergence between tiers shows
#   "inter-machine swings, voltage coupling, IBR behavior". This pair can only
#   ever show the first: neither tier here carries voltage as an unknown and
#   neither has an inverter in it. Presenting it as the milestone's payoff would
#   promote a number it cannot support.
#
#   A BIG GAP IS NOT BY ITSELF EVIDENCE OF A SWING, and this is the one the first
#   render of this window taught. The shipped scenario was a generator trip on
#   `three_machine_ring()`, whose gap grows to 0.857 Hz — by far the largest
#   number the window has ever displayed, and *not the lesson*: V4c derived it as
#   the aggregate keeping the tripped machine's damping in its denominator, which
#   is bookkeeping. The two models differ in ways that have nothing to do with
#   swings, and those differences are usually the larger ones. Hence the default
#   scenario is now the line trip (see `playback`), where the gap IS the residual
#   swing content and nothing else on the screen competes with it.
#
#   THE AGGREGATE IS ONLY A FREQUENCY WHILE THE MACHINES STAY TOGETHER (decision
#   D5, M3). `f_COI` is an inertia-weighted mean over the online machines; across
#   an area split it is the average of two things that are no longer one system,
#   and then BOTH curves here are meaningless, not just one. The M3 window could
#   suppress its aggregate line and keep drawing; this window is the comparison,
#   so there is nothing left to draw and the caller must not point it at a
#   two-area model.
const _PLAYBACK_CAPTION =
    "The most this pair can ever show is ONE of the three lessons SPEC §7.6 names — " *
    "inter-machine swings. NOT voltage coupling and NOT inverter (IBR) behaviour: neither " *
    "tier here carries voltage as an unknown, and that is M5's detailed tier.  ·  A large " *
    "gap is not by itself evidence of a swing — the two models also differ in which " *
    "machines' damping the aggregate keeps, and that difference is usually the larger one.  " *
    "·  Valid only while the machines stay in synchronism: across an area split the " *
    "inertia-weighted mean is not a system frequency (D5), and then both curves are " *
    "meaningless, not just one."

const _GAP_FLOOR_FRACTION = 0.1

"""
    _build_playback_window(swing, agg; band, reltol, events, title, ylims_f, ylims_gap)

Assemble the playback figure over two **already-solved** series on one grid,
returning `(; fig, t, swing, agg, gap, band, read, cursor, widgets, axes, caption,
readout, caption_text)`.

`swing` is the network (per-machine swing) tier's series and `agg` the aggregate
tier's; both are compared on `system_frequency`, the one channel that means the
same thing in both (`f_coi` on one, `f` on the other). `band` is the agreement
band, already derived — see the file header for why it is not a control.

`events` is a vector of `(time, description)` taken from the *swing engine's own
event log*, so the marked instants are the ones the engine applied rather than the
ones a caller intended. `aggregate_times` is the list of instants at which
something was applied to the **aggregate** side. The two are separate arguments
because the two tiers need not receive the same events at all (see `playback`),
and when they differ the figure has to say so rather than let a reader assume a
single unlabelled event list reached both.

Nothing here solves, steps, or resamples. A pair on two different grids is a
build-time error, raised by `divergence` in the core.

The look is `GRIDSIM_THEME` (`theme.jl`), applied through `themed` so it is scoped
to the build.
"""
_build_playback_window(swing::NamedTuple, agg::NamedTuple; kwargs...) =
    themed(() -> _build_playback_window_impl(swing, agg; kwargs...))

function _build_playback_window_impl(swing::NamedTuple, agg::NamedTuple;
                                band::Real,
                                reltol::Real,
                                events::Vector{Tuple{Float64,String}} =
                                    Tuple{Float64,String}[],
                                aggregate_times::Vector{Float64} = Float64[],
                                title::AbstractString =
                                    "GridSim — playback overlay: swing tier vs aggregate tier",
                                ylims_f = nothing,
                                ylims_gap = nothing)
    # The grid check and the summary in one call: `divergence` throws if the two
    # series are not on one grid, which is the only way this window can be handed
    # something it must not draw.
    read = divergence(swing, agg; band = band)

    t = swing.t
    a = system_frequency(swing)          # network tier: f_coi
    b = system_frequency(agg)            # aggregate tier: f
    # The plotted gap and the summary above must be the same arithmetic, or the
    # picture and the read-out can disagree about where the maximum is. Same
    # expression as `divergence`'s, so `maximum(gap)` equals `read.max` to the bit
    # — asserted in `ui/test/runtests.jl` rather than assumed here.
    gap = abs.(a .- b)

    fig = Figure(size = (1240, 800))

    ax_f = Axis(fig[1, 1]; title = title, ylabel = "f (Hz)",
                xticklabelsvisible = false)
    floor_v = Float64(band) * _GAP_FLOOR_FRACTION
    ax_g = Axis(fig[2, 1]; xlabel = "t (s)",
                ylabel = @sprintf("|gap| (Hz), floored at band/%.0f", 1 / _GAP_FLOOR_FRACTION),
                yscale = log10)
    linkxaxes!(ax_f, ax_g)

    # ---- the two tiers -----------------------------------------------------
    # No legend inside the axis: the shipped generator-trip render had one lying
    # across both curves and the cursor dot in the bottom-right corner, which is
    # where a falling frequency ends up. It lives at the top of the read-out
    # column instead (below), where nothing is plotted.
    lines!(ax_f, t, a; color = C_SWING, linewidth = 2,
           label = "swing tier — f_COI over the machines")
    lines!(ax_f, t, b; color = C_AGGREGATE, linewidth = 2, linestyle = :dash,
           label = "aggregate tier — single-machine equivalent")

    # ---- the gap, the band, and where they part company --------------------
    lines!(ax_g, t, max.(gap, floor_v); color = RGBf(0.15, 0.15, 0.17), linewidth = 1.5,
           label = "|gap|")
    hlines!(ax_g, [Float64(band)]; color = (C_WARN, 0.9), linestyle = :dash,
            label = "agreement band")
    if !isnan(read.t_depart)
        vlines!(ax_f, [read.t_depart]; color = (C_WARN, 0.5), linewidth = 1.5)
        vlines!(ax_g, [read.t_depart]; color = (C_WARN, 0.5), linewidth = 1.5,
                label = "departs")
    end

    # The engine's own log, on the frequency panel. Same rule as M2's window: the
    # traces carry no record that anything happened, so this is the only place a
    # line trip or a relay firing appears at all.
    if !isempty(events)
        vlines!(ax_f, [e[1] for e in events]; color = (C_EVENT, 0.6), linestyle = :dot,
                label = "event (swing tier's log)")
    end

    # ---- the cursor --------------------------------------------------------
    # Index, not time (file header). `1:length(t)` rather than `eachindex`, so the
    # slider's own value is an `Int` a test can set exactly.
    sl = Slider(fig[3, 1]; range = 1:length(t), startvalue = 1, tellwidth = false)
    cursor = lift(sl.value) do i
        k = Int(i)
        (; i = k, t = t[k], f_swing = a[k], f_agg = b[k], gap = gap[k])
    end
    cx = lift(c -> [c.t], cursor)
    # Held by reference and returned: a test that reads `cursor` is reading the
    # read-out's source, which is one step short of the picture. These two plots
    # ARE the cursor as drawn, and their own argument is what a check should be
    # against (M3 step 7's lesson, in its UI form).
    vline_f = vlines!(ax_f, cx; color = (C_CURSOR, 0.9), linewidth = 1.5)
    vline_g = vlines!(ax_g, cx; color = (C_CURSOR, 0.9), linewidth = 1.5,
                      label = "cursor")
    # The two dots are where the read-out's numbers come from, made visible. They
    # are `Point2f` — Float32 — so they are a picture and never an assertion
    # target; `cursor` above carries the Float64 the read-out formats.
    scatter!(ax_f, lift(c -> [Point2f(c.t, c.f_swing)], cursor);
             color = C_SWING, markersize = 11)
    scatter!(ax_f, lift(c -> [Point2f(c.t, c.f_agg)], cursor);
             color = C_AGGREGATE, markersize = 11)
    scatter!(ax_g, lift(c -> [Point2f(c.t, max(c.gap, floor_v))], cursor);
             color = C_CURSOR, markersize = 11)

    # ---- the read-out column ----------------------------------------------
    gc = fig[1:3, 2] = GridLayout(tellheight = false, valign = :top)

    # Both panels' legends, at the top of the column where nothing is plotted.
    # `tellheight = true` so each legend's row is its own height; left to the
    # default the rows expand to share the column and the legends float apart.
    Legend(gc[1, 1], ax_f; tellwidth = false, tellheight = true, halign = :left)
    Legend(gc[2, 1], ax_g; tellwidth = false, tellheight = true, halign = :left)

    # The cursor read-out: names once, values a `lift` of the cursor (theme.jl).
    # `readout` is the composite a test reads — the rows the two labels draw, joined.
    section_label!(gc[3, 1], "cursor")
    ro_keys = "sample\nt\nswing tier\naggregate\ngap"
    ro_values = lift(cursor) do c
        @sprintf("%d of %d\n%9.3f s\n%9.4f Hz\n%9.4f Hz\n%9.3e Hz",
                 c.i, length(t), c.t, c.f_swing, c.f_agg, c.gap)
    end
    gro = gc[4, 1] = GridLayout()
    ro = readout_block!(gro, ro_keys; values = ro_values)
    readout = lift(v -> readout_text(ro_keys, v), ro_values)
    readout_label = ro.values_label

    # The band and its derivation together. A band whose provenance is not on the
    # screen is a magic number, and `t_depart` is only meaningful relative to it.
    depart = isnan(read.t_depart) ?
             "never — indistinguishable at this band" :
             @sprintf("%.3f s", read.t_depart)
    section_label!(gc[5, 1], "divergence over the whole run")
    summary = @sprintf("band      %9.3e Hz\n          = 3 · reltol · excursion,\n            reltol %.0e\nmax       %9.3e Hz  at %.2f s\nrms       %9.3e Hz\ndeparts   %s\nsamples   %d",
                       band, reltol, read.max, read.t_max, read.rms, depart, read.n)
    summary_label = Label(gc[6, 1], summary; halign = :left, justification = :left,
                          tellwidth = false, font = MONO_FONT, fontsize = 13)

    # THE ASYMMETRY IS DRAWN, NOT ASSUMED AWAY. The two tiers are allowed to receive
    # different events, and on the shipped scenario they do: the aggregate view has
    # no branches, so a line trip is not an event it can be given at all. An
    # unlabelled event list would let a reader take "1.00 s trip line B3-B1" as
    # something both curves responded to, and then read the whole gap as a
    # modelling difference when part of it is simply an event one side never saw.
    #
    # Marked on the INSTANT, which is what this window actually knows: the swing
    # side's list is the engine's own log, the aggregate side's is the list of
    # times something was applied to it. "Nothing was applied at this instant" is
    # a fact; "the aggregate has no representation of this event" would be an
    # interpretation, and on a tier that simply was not given an event it could
    # have taken, it would be the wrong one.
    only_swing = [e for e in events
                  if !any(tau -> abs(tau - e[1]) <= 1.0e-9, aggregate_times)]
    asymmetric = !isempty(only_swing) || length(aggregate_times) != length(events)
    event_rows = [@sprintf("%6.2f s  %s%s", e[1], e[2],
                           e in only_swing ? "   [swing tier only]" : "")
                  for e in events]
    event_head = isempty(events) ? "events (swing tier's log)" :
                 asymmetric ?
                 @sprintf("events — THE TIERS DID NOT GET THE SAME ONES\n(swing tier's log: %d;  applied to the aggregate: %d)",
                          length(events), length(aggregate_times)) :
                 "events (both tiers, from the swing tier's log)"
    event_text = isempty(events) ? "(no events)" : join(event_rows, "\n")
    # `word_wrap`: the asymmetric heading is long, and the first render of this
    # window had it running off the right edge of the figure.
    event_label = Label(gc[7, 1], event_head * "\n" * event_text;
                        halign = :left, justification = :left, tellwidth = false,
                        word_wrap = true, fontsize = 13,
                        color = asymmetric ? C_WARN : C_MUTED)

    # The caption is a `Label` held by reference and returned, so a test can assert
    # it is in the figure's layout rather than assert against an observable the
    # picture might not contain (M3 step 7: a check that reads the log where it
    # should read the picture passes against a caption that was never drawn).
    caption = Label(fig[4, 1:2], _PLAYBACK_CAPTION; halign = :left,
                    justification = :left, tellwidth = false, word_wrap = true,
                    fontsize = 12, color = C_MUTED)

    rowsize!(fig.layout, 2, Relative(0.30))
    rowsize!(fig.layout, 3, Fixed(40))
    colsize!(fig.layout, 2, Fixed(340))
    rowgap!(gc, 10)

    # Axis boxes. Pinned limits exist for the same reason they do in the other two
    # windows: two renders meant to be compared must share a scale, or a gap three
    # times larger draws the same shape as a small one.
    xlims!(ax_f, t[1], t[end])
    ylims_f === nothing || ylims!(ax_f, ylims_f[1], ylims_f[2])
    if ylims_gap === nothing
        top = max(maximum(gap), Float64(band)) * 4
        ylims!(ax_g, floor_v / 2, top)
    else
        ylims!(ax_g, ylims_gap[1], ylims_gap[2])
    end

    widgets = (; time = sl)
    axes = (; frequency = ax_f, gap = ax_g)
    return (; fig, t, swing, agg, gap, band = Float64(band), read, cursor,
              widgets, axes, caption, caption_text = _PLAYBACK_CAPTION, readout,
              events, aggregate_times, asymmetric, event_label, readout_label,
              summary_label, cursor_lines = (; frequency = vline_f, gap = vline_g))
end

# The pair itself: two engines, one scenario, one output grid. The aggregate side
# is `coi_model(net)`, the compiled view the core already derives, so this is not a
# second model of anything (SPEC §3.2).
#
# THE TWO TIERS DO NOT ALWAYS GET THE SAME EVENTS, AND WHICH ONES THEY GET IS
# STATED, NEVER INFERRED. The aggregate view has no branches, so `TripLine` has no
# `inject!` method on it at all — the shipped scenario is exactly that case, and
# the "event" the aggregate tier sees is nothing whatsoever. That asymmetry is the
# fidelity boundary made visible, so it must be visible: `aggregate_perturbations`
# is a separate argument the caller writes out.
#
# The rejected alternative was to filter the list automatically — keep only the
# events the aggregate has a method for, via `hasmethod`. It reads well and it is
# wrong: a method that is MISSING BY MISTAKE would then be silently reclassified as
# a fidelity boundary, which is the one error this comparison exists to detect. A
# missing method is better as a loud `MethodError` pointing at the real question.
#
# Both engines are FRESH. `solve!` refuses an engine that is not at `tspan[1]`, so
# a "solve it again at a tighter tolerance" path cannot reuse these; that is what
# keeps the band honest when the tolerance moves (file header).
function _solve_overlay(net::NetworkModel;
                        horizon::Real,
                        perturbations,
                        aggregate_perturbations,
                        saveat::Real,
                        reltol::Real,
                        abstol::Real)
    sw = SwingEngine(net; reltol = reltol, abstol = abstol)
    ag = FrequencyResponseEngine(coi_model(net); reltol = reltol, abstol = abstol)
    solve!(sw, (0.0, horizon); perturbations = perturbations, saveat = saveat)
    solve!(ag, (0.0, horizon); perturbations = aggregate_perturbations, saveat = saveat)
    return sw, ag
end

# The shipped scenario, as ONE object rather than two keyword defaults that could
# drift apart: a line trip the swing tier rings on and the aggregate tier is not
# given at all, because there is no event to give it.
#
# `nothing` for either list means "the caller did not say". Both unsaid gives this
# scenario. A `perturbations` list with no `aggregate_perturbations` gives BOTH
# tiers the same list — the symmetric reading, which is the safe one, and which
# fails loudly on an event the aggregate has no method for instead of quietly
# dropping it.
const _DEFAULT_SCENARIO = (perturbations = [1.0 => TripLine(:B3, :B1)],
                           aggregate_perturbations = Pair{Float64,PerturbationEvent}[])

function _resolve_scenario(perturbations, aggregate_perturbations)
    if perturbations === nothing
        aggregate_perturbations === nothing || throw(ArgumentError(
            "playback: `aggregate_perturbations` was given without `perturbations`. " *
            "Both tiers' event lists are stated together or neither is."))
        return _DEFAULT_SCENARIO.perturbations, _DEFAULT_SCENARIO.aggregate_perturbations
    end
    return perturbations,
           aggregate_perturbations === nothing ? perturbations : aggregate_perturbations
end

# Solve the pair and build the window over it. Shared by `playback` and
# `playback_render` for the standing reason: the PNG a headless session looks at
# has to be a picture of the window a user opens.
function _playback_window(net::NetworkModel;
                          horizon::Real,
                          perturbations,
                          aggregate_perturbations,
                          saveat::Real,
                          reltol::Real,
                          abstol::Real,
                          kwargs...)
    pert, agg_pert = _resolve_scenario(perturbations, aggregate_perturbations)
    sw, ag = _solve_overlay(net; horizon = horizon, perturbations = pert,
                            aggregate_perturbations = agg_pert, saveat = saveat,
                            reltol = reltol, abstol = abstol)
    swing, agg = state_series(sw), state_series(ag)
    # Derived from the side we trust more (the swing tier resolves the swings the
    # aggregate averages away) and from the tolerance the solve actually ran at —
    # never from looking at the gap.
    band = tolerance_band(system_frequency(swing); reltol = reltol)
    # The engine's own log, not the caller's schedule: a relay that fired on the
    # system's own state at an instant nobody scheduled belongs on the picture too.
    events = Tuple{Float64,String}[(e.t, describe_event(e)) for e in event_log(sw)]
    # The aggregate keeps no event log of its own (only `SwingEngine` does), so what
    # it received is the schedule it was handed. Times only — see the builder.
    aggregate_times = Float64[Float64(first(p)) for p in agg_pert]
    return _build_playback_window(swing, agg; band = band, reltol = reltol,
                                  events = events, aggregate_times = aggregate_times,
                                  kwargs...)
end

"""
    playback(net = three_machine_ring(); horizon = 20.0, perturbations = nothing,
             aggregate_perturbations = nothing, saveat = 0.02, reltol = 1e-3,
             abstol = 1e-6, cursor_at = nothing, title = …, ylims_f = nothing,
             ylims_gap = nothing)

Solve one scenario on **both** fidelity tiers and open the playback window over
the pair, returning `(; fig, t, swing, agg, gap, band, read, cursor, widgets,
axes, caption, readout, events, screen)`.

A different verb from `launch` on purpose. `launch` is the real-time mode and
picks its window by dispatching on the model type; both modes run on the same
`NetworkModel`, so the model cannot say which is wanted — the core makes the same
distinction by verb (`run_realtime!` against `solve!`) rather than by type.

The pair is the network swing tier against `coi_model(net)`, the aggregate view
compiled down from the same model. Both are solved to `horizon` onto one `saveat`
grid, which is what makes them comparable at all: nothing in this package
resamples, and the core refuses a pair on two grids.

**The default scenario is a line trip, and the two tiers do not both get it.**
`TripLine(:B3, :B1)` opens one side of the ring: the machines swing against each
other and the centre-of-inertia frequency rings by about 1 mHz, while the
aggregate tier — which has no branches, and therefore no `inject!` method for a
line trip — is handed nothing and stays at exactly 50 Hz. The whole gap is then
the residual inter-machine swing content, which is the one lesson this pair can
support (see the caption in the figure).

A generator trip is accepted by both tiers and is the other instructive run, but
it is deliberately not the default: its gap reaches 0.857 Hz and **is not the
lesson** — V4c derived it as the aggregate keeping the tripped machine's damping.
Pass it explicitly:

    playback(; perturbations = [1.0 => TripGenerator(:G1)], horizon = 60.0)

Stating `perturbations` without `aggregate_perturbations` gives both tiers the
same list; state both to make them differ.

Drag the slider to move the cursor through the run; the read-out shows both tiers
and their gap at that sample, and the whole-run divergence summary beside it.
`cursor_at` places the cursor at the recorded sample nearest a given time — no
interpolation, since the slider indexes samples.

**Point it at a single synchronous area.** Across an area split the
inertia-weighted mean is not a system frequency (D5) and neither curve means
anything.

From a shell this must be followed by something that blocks:

    julia --project=ui -e "using GridSimUI, GridSim; wait_for_close(playback())"
"""
function playback(net::NetworkModel = three_machine_ring();
                  horizon::Real = 20.0,
                  perturbations = nothing,
                  aggregate_perturbations = nothing,
                  saveat::Real = 0.02,
                  reltol::Real = 1.0e-3,
                  abstol::Real = 1.0e-6,
                  cursor_at::Union{Nothing,Real} = nothing,
                  title::AbstractString =
                      "GridSim — playback overlay: swing tier vs aggregate tier",
                  ylims_f = nothing,
                  ylims_gap = nothing)
    GLMakie.activate!(; visible = true, title = "GridSim — playback")
    win = _playback_window(net; horizon = horizon, perturbations = perturbations,
                           aggregate_perturbations = aggregate_perturbations,
                           saveat = saveat, reltol = reltol, abstol = abstol,
                           title = title, ylims_f = ylims_f, ylims_gap = ylims_gap)
    cursor_at === nothing || _cursor_to_time!(win, cursor_at)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    playback_render(net = three_machine_ring(); path, …) -> path

Build the *same* playback window offscreen and save a PNG to `path`.

This is how the window is checked from a session with no screen — the standing
"render before claiming" rule (M2/M3). Everything `playback` accepts is accepted
here, with one difference in the default: the cursor is placed at the instant of
**largest** disagreement rather than at `t = 0`, because a saved frame has no
reader to drag the slider and a cursor at the flat start shows nothing. It is
moved through `set_close_to!` on the very slider a user drags, not by writing the
cursor directly.
"""
function playback_render(net::NetworkModel = three_machine_ring();
                         path::AbstractString,
                         horizon::Real = 20.0,
                         perturbations = nothing,
                         aggregate_perturbations = nothing,
                         saveat::Real = 0.02,
                         reltol::Real = 1.0e-3,
                         abstol::Real = 1.0e-6,
                         cursor_at::Union{Nothing,Real} = nothing,
                         title::AbstractString =
                             "GridSim — playback overlay: swing tier vs aggregate tier",
                         ylims_f = nothing,
                         ylims_gap = nothing)
    GLMakie.activate!(; visible = false)
    win = _playback_window(net; horizon = horizon, perturbations = perturbations,
                           aggregate_perturbations = aggregate_perturbations,
                           saveat = saveat, reltol = reltol, abstol = abstol,
                           title = title, ylims_f = ylims_f, ylims_gap = ylims_gap)
    if cursor_at === nothing
        set_close_to!(win.widgets.time, argmax(win.gap))
    else
        _cursor_to_time!(win, cursor_at)
    end
    mkpath(dirname(path))
    save(path, win.fig)
    return path
end

# Put the cursor on the recorded sample NEAREST `τ`. Nearest, and never between:
# the slider indexes samples precisely so that no displayed number is a value
# nobody computed (file header).
function _cursor_to_time!(win, τ::Real)
    t = win.t
    j = searchsortedfirst(t, Float64(τ))
    i = if j <= firstindex(t)
        firstindex(t)
    elseif j > lastindex(t)
        lastindex(t)
    else
        abs(t[j] - τ) < abs(τ - t[j - 1]) ? j : j - 1
    end
    set_close_to!(win.widgets.time, i)
    return i
end
