# The voltage-visible playback window (M5 step 8) — the classical tier against the
# detailed one, with the quantity only one of them has drawn beside the quantity
# both of them report.
#
# THE PROMISE THIS DISCHARGES, IN FULL AND IN ONE PLACE. `docs/plans/m4-plan.md`
# step 3 wrote a commitment on M5's behalf, quoted verbatim so the commitment and
# the delivery sit in the same file:
#
#     "Voltage coupling and inverter behaviour need a tier that has voltage in it,
#      and that is M5."
#
# M4's own overlay (`playback_window.jl`) says in its caption that it can only ever
# show ONE of the three lessons SPEC §7.6 names — inter-machine swings — because
# neither of its tiers carries voltage as an unknown. This window keeps the VOLTAGE
# half of the promise: the detailed tier's bus voltage magnitudes are algebraic
# states it actually solves for, and they are drawn here.
#
# THE OTHER HALF IS NOT KEPT AND DOES NOT BECOME KEPT BY STANDING NEXT TO THIS ONE
# (decision D12). Inverter (IBR) behaviour has no tier in M5. It is a third
# fidelity, unnamed and unscheduled, and `docs/SPEC.md` §7.6's third lesson says so
# out loud rather than letting a voltage window imply it.
#
# WHY A FOURTH WINDOW AND NOT A MODE ON THE THIRD. `playback_window.jl`'s header is
# eighty lines arguing why THAT pair can show one lesson of three. This pair shows a
# second one, so that argument is false here — and a caption cannot be swapped out
# from under the prose that justifies it. The two builders share `theme.jl`, the
# core's `divergence`, and nothing else; the ~40 lines of cursor wiring duplicated
# below buys both files a header that is true.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE PAIR, AND THE ONE THING A READER MUST NOT TAKE FROM THE VOLTAGE PANEL
#
# TWO MODELS FROM ONE DEFINITION. `governed_ring()` and `governed_ring(; detailed
# = …)` agree bit for bit in every quantity `SwingEngine` reads and differ in
# exactly the set it refuses by name (`_assert_frozen_flux`). The plan asked for one
# model handed to both engines; that is not available, and deliberately so — a
# classical engine handed a real `Xd` would silently run a machine its own data does
# not describe. M5 step 7 settled this and the same structure is used here.
#
# THE TWO RUNS DO NOT START AT THE SAME BUS VOLTAGE, AND THAT IS NOT A RESULT. This
# is the trap this window was nearly built around, so it is stated before anything
# else. `Machine.E′` denominates a DIFFERENT PHYSICAL QUANTITY at the two tiers
# (`Machine`'s docstring): the constant internal voltage AT THE BUS classically, and
# the magnitude of the q-axis source BEHIND `(Ra + jXq)` in detail. Holding the
# number at 1.05 while moving what it sits behind from `X′d = 0.30` to `Xq = 1.7`
# puts the source 5.7× further back, and the detailed power flow then solves that
# bus to 0.915 pu. Measured on the shipped scenario:
#
#     pre-event offset |E′ − |V|(0)|      0.135 / 0.107 / 0.120 pu
#     largest movement max| |V| − |V|(0)| 0.090 / 0.096 / 0.094 pu
#
# So the biggest number on the panel is an artefact of one model number serving two
# denominations, and it is there at `t = 0` before anything has happened. It is
# drawn — hiding it would be worse — but it is labelled as a pre-event offset in the
# read-out, named in the caption, and the read-out's voltage rows carry `Δ from t0`
# beside every absolute value so the movement is a number rather than a squint.
#
# This is the M4 window's "0.857 Hz that is not the lesson" in its voltage form, and
# it is the second time this repo has met it: the largest quantity on a cross-tier
# picture is usually a bookkeeping or denomination difference, not the physics the
# picture exists for.
#
# AT THE CLASSICAL DEGENERATION THE OFFSET COLLAPSES, which is what says the above
# is denomination and not a broken comparison. Build the same window on
# `governed_ring()` on BOTH sides — the frozen-flux model, where `E′` sits behind
# `X′d` on both — and the three offsets fall to 0.013 / 0.0003 / 0.010 pu, i.e. the
# `X′d` the classical tier folds away and nothing else. That is a factor of ten on
# every bus, and it is what says the 0.13 is denomination rather than a broken
# comparison. That run is the anti-vacuity control for the whole panel — without it
# "the panel draws a real offset" cannot be told from "the panel always draws one" —
# and it is asserted in `ui/test/runtests.jl`.
#
# THE BUS WHOSE VOLTAGE MATTERS MOST IS THE ONE THIS WINDOW CANNOT SHOW. The
# classical tier refuses a machine-free bus by name (`_assert_one_machine_per_bus`:
# "a passive bus is an algebraic node, which is the detailed (DAE) tier"), so any
# model BOTH tiers accept has exactly one machine on every bus. `state_series`'s own
# docstring says a machine-free bus "is often the one whose voltage matters" — and
# it is structurally absent from every pair this window can draw. Stated in the
# caption, because a boundary a picture cannot show is one a reader will not notice.
#
# NO BAND ON THE VOLTAGE PANEL, AND NO DEPARTURE READ EITHER. `tolerance_band` is a
# SOLVER-NOISE band: below it a gap between two runs is integration error rather
# than a result. The classical/detailed voltage difference is not solver noise at
# all — it is a modelling difference, plus the denomination above — so a band would
# be answering a question nobody asked, and `t_depart` ("when does noise stop
# explaining this") has no voltage analogue here. The frequency panel keeps both,
# because there the question is exactly the right one. A voltage panel that borrowed
# the gap panel's furniture would be read as though the band applied to it, and M4's
# own finding was that a per-machine channel needs its own band and never the
# aggregate's.
#
# THE CLASSICAL TIER'S LINE IS AN ASSUMPTION, NOT AN OUTPUT, and it is drawn dashed
# and flat for that reason. `_assert_frozen_flux`'s own wording is the authority:
# the classical tier "represents a machine as a constant-magnitude `E′` at the bus".
# That is its entire model of a bus voltage — a constant of the data, with no
# equation behind it and nothing that could ever move it.
#
# THE SHIPPED SCENARIO IS A RAMP THAT ADDS LOAD, AND EVERY PART OF THAT WAS FORCED
# OR MEASURED.
#
# A ramp rather than an event, forced: `DetailedEngine` refuses `TripGenerator` by
# name (a tripped machine makes its bus passive, which a compiled vertex model
# cannot become at run time), so of the *events* both tiers accept only `TripLine`
# is left — and on this ring a line trip moves the frequency by 1.5 mHz and the
# voltage by 0.004 pu, which is a picture of nothing. A `GenerationRamp` is armed at
# construction, so both tiers get it identically, and it is the disturbance M3 and
# M5 step 7 already use.
#
# ADDING LOAD RATHER THAN LOSING GENERATION, measured. The ramp is on `G3`, the
# ring's load (`P0 = −110 MW`), so a negative ramp draws 60 MW MORE. The first
# render of this window put it on `G1` instead, which loses 60 MW of generation —
# and there the voltage RISES (0.915 → 1.011), because unloading a machine takes
# current out of its own `Xq` and the terminal comes up. That is perfectly real and
# it is the wrong picture: the traces climb toward the classical tier's constants,
# which reads as the two tiers converging when nothing of the sort is happening.
# Adding load makes the voltage SAG instead — 0.920 → 0.826 — which is the direction
# SPEC §7.6's "voltage coupling" lesson is about and the direction the Iberian case
# fell in.
#
# NOT FURTHER, deliberately. Doubling the ramp to 120 MW drives an outright voltage
# COLLAPSE (|V| to 0.002 pu, and a 2.5 Hz frequency gap). It is the most vivid
# demonstration of the tier boundary this window could draw, and it is not the
# default, because the detailed tier's load model has a NAMED singularity at zero
# voltage (M5 step 6: named, not softened) and a picture whose headline sits past
# where the model is trustworthy is worth nothing.
#
# SIXTY SECONDS, not twenty. `T′do = 8 s`, so at a 20 s horizon the flux is still
# moving at the right-hand edge and the "largest movement" is just the last sample.
# The run settles well inside 60.
#
# THE FIELD IS HELD, NOT REGULATED, IN THE DEFAULT — and that is the M4 line-trip
# decision made again. With the AVR armed the regulator does its job: the terminal
# voltage barely moves (0.0005 pu, and it ends where it started) while the FIELD
# voltage moves instead, `Efd` 1.051 → 1.115. That is a true and interesting result
# — step 7's finding in miniature, that what acts on the voltage is the regulator
# working through the flux — and it is the wrong DEFAULT, because a voltage panel
# whose voltage is flat teaches "voltage does not do anything". With the flux live
# and the field held at its dispatch the voltage moves 0.096 pu, 190× more.
#
# The held-field configuration is not a convenience either: it is exactly what
# `build_oracle(tier = :sauer_pai)` runs, so the shipped default is a machine the
# repo already checks against an external oracle. Arm the exciter by passing a
# detailed model built with one — see `voltage_playback`'s docstring.

# What the pair can and cannot support. In the figure rather than in a docstring,
# because the reader who over-reads the picture is the one looking at the picture.
const _VOLTAGE_CAPTION =
    "M4 promised this window: \"voltage coupling and inverter behaviour need a tier that " *
    "has voltage in it, and that is M5\". The VOLTAGE half is kept here — the lower panel " *
    "is an algebraic state the detailed tier solves for. The INVERTER (IBR) half is NOT, " *
    "and does not become kept by standing next to it: that is a third fidelity, unnamed " *
    "and unscheduled.  ·  THE PRE-EVENT OFFSET IS NOT A RESULT. The two runs start at " *
    "different bus voltages because Machine.E′ denominates a different quantity at each " *
    "tier — the voltage AT the bus classically, the source BEHIND (Ra + jXq) in detail — " *
    "so one number sits 5.7× further back in one model than the other. It is there at " *
    "t = 0 before anything happens; read the MOVEMENT (Δ from t0 in the read-out), not " *
    "the gap.  ·  The dashed lines are the classical tier's ASSUMPTION, not its output: " *
    "that tier has no bus-voltage equation at all, only a constant.  ·  Every bus here " *
    "carries a machine, because the classical tier refuses a machine-free one — so the " *
    "passive bus, which is often the one whose voltage matters, is the bus this " *
    "comparison structurally cannot show."

# Floor for the log-scaled frequency-gap panel, as a fraction of the band.
const _VGAP_FLOOR_FRACTION = 0.1

# One colour per bus, so a bus's solved |V| and the classical constant it is being
# compared against are visibly the same bus. Solid is solved, dashed is assumed.
const _BUS_COLOURS = (RGBf(0.12, 0.47, 0.85), RGBf(0.93, 0.45, 0.08),
                      RGBf(0.18, 0.55, 0.34), RGBf(0.55, 0.25, 0.60),
                      RGBf(0.72, 0.13, 0.13), RGBf(0.25, 0.25, 0.25))
_bus_colour(k::Integer) = _BUS_COLOURS[mod1(k, length(_BUS_COLOURS))]

"""
    _build_voltage_window(classical, detailed; band, reltol, buses, E_assumed, …)

Assemble the voltage-visible figure over two **already-solved** series on one grid,
returning `(; fig, t, classical, detailed, gap, band, read, cursor, widgets, axes,
caption, caption_text, readout, buses, V, E_assumed, offsets, …)`.

`classical` is the classical (`SwingEngine`) tier's series and `detailed` the
detailed (`DetailedEngine`) tier's. They are compared on `system_frequency` — the
one channel that means the same thing at both tiers — with the agreement band the
solve's own tolerance derives. Nothing here solves, steps or resamples; a pair on
two grids is a build-time error raised by `divergence` in the core.

`buses` names the bus channels drawn on the voltage panel and `E_assumed` gives, in
the same order, the constant the classical tier holds at each of those buses. They
are passed as a matched pair rather than looked up here, because the mapping from a
bus to *the machine standing on it* is the one thing on this panel that can be
silently transposed: three buses whose constants are 1.05, 1.03 and 1.04 draw very
nearly the same picture under any permutation. `_voltage_window` builds the pair
through `machine_at`, and `ui/test/runtests.jl` asserts each plotted constant
against the machine at that bus rather than against a position.

There is no band and no departure read on the voltage panel — see the file header.

The look is `GRIDSIM_THEME` (`theme.jl`), applied through `themed` so it is scoped
to the build.
"""
_build_voltage_window(classical::NamedTuple, detailed::NamedTuple; kwargs...) =
    themed(() -> _build_voltage_window_impl(classical, detailed; kwargs...))

function _build_voltage_window_impl(classical::NamedTuple, detailed::NamedTuple;
                                    band::Real,
                                    reltol::Real,
                                    buses::Vector{Symbol},
                                    E_assumed::Vector{Float64},
                                    events::Vector{Tuple{Float64,String}} =
                                        Tuple{Float64,String}[],
                                    scenario::AbstractString = "",
                                    title::AbstractString =
                                        "GridSim — voltage-visible playback: classical tier vs detailed tier",
                                    ylims_f = nothing,
                                    ylims_gap = nothing,
                                    ylims_v = nothing)
    length(buses) == length(E_assumed) || throw(ArgumentError(
        "voltage window: $(length(buses)) buses against $(length(E_assumed)) assumed " *
        "constants. The two are a matched pair — a bus and the constant the classical " *
        "tier holds AT that bus — and a mismatch is exactly the transposition this " *
        "argument shape exists to make impossible."))
    isempty(buses) && throw(ArgumentError(
        "voltage window: no buses to draw. This window's whole content is the bus " *
        "voltage the detailed tier solves for; without one there is nothing here that " *
        "`playback` does not already do better."))

    # The grid check and the frequency summary in one call: `divergence` throws if
    # the two series are not on one grid, which is the only way this window can be
    # handed something it must not draw.
    read = divergence(classical, detailed; band = band)

    t = classical.t
    fc = system_frequency(classical)      # classical tier: f_coi
    fd = system_frequency(detailed)       # detailed tier:  f_coi
    # Same arithmetic as `divergence`'s, so `maximum(gap)` equals `read.max` to the
    # bit — asserted in `ui/test/runtests.jl` rather than assumed here.
    gap = abs.(fc .- fd)

    # The voltage channels, read out of the detailed series by name. A bus the
    # detailed tier did not record is a caller error worth naming, since the whole
    # panel is these vectors.
    V = Vector{Vector{Float64}}(undef, length(buses))
    for (k, b) in pairs(buses)
        ch = Symbol("V_", b)
        haskey(detailed, ch) || throw(ArgumentError(
            "voltage window: the detailed series has no channel $ch for bus $b " *
            "(channels: $(keys(detailed))). Bus voltage magnitudes are recorded one " *
            "per BUS by `DetailedEngine`; a name that is not among them is a typo or " *
            "a bus from a different model."))
        V[k] = Float64.(detailed[ch])
    end
    # The pre-event offset, per bus: how far apart the two runs START, before
    # anything at all has happened. Computed once and carried out of the builder so
    # the read-out, the caption and a test all quote one number.
    offsets = [abs(E_assumed[k] - V[k][1]) for k in eachindex(buses)]
    excursions = [maximum(abs.(V[k] .- V[k][1])) for k in eachindex(buses)]

    fig = Figure(size = (1320, 1020))

    ax_f = Axis(fig[1, 1]; title = title, ylabel = "f (Hz)",
                xticklabelsvisible = false)
    floor_v = Float64(band) * _VGAP_FLOOR_FRACTION
    ax_g = Axis(fig[2, 1];
                ylabel = @sprintf("|f gap| (Hz), floored at band/%.0f",
                                  1 / _VGAP_FLOOR_FRACTION),
                yscale = log10, xticklabelsvisible = false)
    ax_v = Axis(fig[3, 1]; xlabel = "t (s)", ylabel = "|V| (pu)")
    linkxaxes!(ax_f, ax_g, ax_v)

    # ---- the two tiers, on the channel they share --------------------------
    # No legend inside an axis: M4's shipped render had one lying across the data.
    lines!(ax_f, t, fc; color = C_SWING, linewidth = 2,
           label = "classical tier — f_COI (SwingEngine)")
    lines!(ax_f, t, fd; color = C_AGGREGATE, linewidth = 2, linestyle = :dash,
           label = "detailed tier — f_COI (DetailedEngine)")

    # ---- the frequency gap, its band, and where they part company ----------
    lines!(ax_g, t, max.(gap, floor_v); color = RGBf(0.15, 0.15, 0.17), linewidth = 1.5,
           label = "|f gap|")
    hlines!(ax_g, [Float64(band)]; color = (C_WARN, 0.9), linestyle = :dash,
            label = "agreement band")
    if !isnan(read.t_depart)
        vlines!(ax_f, [read.t_depart]; color = (C_WARN, 0.5), linewidth = 1.5)
        vlines!(ax_g, [read.t_depart]; color = (C_WARN, 0.5), linewidth = 1.5,
                label = "departs")
    end
    if !isempty(events)
        vlines!(ax_f, [e[1] for e in events]; color = (C_EVENT, 0.6), linestyle = :dot,
                label = "event (detailed tier's log)")
    end

    # ---- THE PANEL THIS WINDOW EXISTS FOR ----------------------------------
    # Solid: an algebraic state the detailed tier solves for at every step.
    # Dashed: the classical tier's constant, which is not an output — see header.
    # Both plots are held by reference and returned, so a check reads the drawn
    # argument rather than the vector it was built from (M3 step 7, in its UI form).
    v_lines = Any[]
    e_lines = Any[]
    for (k, b) in pairs(buses)
        c = _bus_colour(k)
        push!(v_lines, lines!(ax_v, t, V[k]; color = c, linewidth = 2,
                              label = "$b — solved |V| (detailed)"))
        push!(e_lines, hlines!(ax_v, [E_assumed[k]]; color = (c, 0.55),
                               linestyle = :dash, linewidth = 1.5,
                               label = "$b — assumed E′ (classical)"))
    end
    if !isempty(events)
        vlines!(ax_v, [e[1] for e in events]; color = (C_EVENT, 0.6), linestyle = :dot)
    end

    # ---- the cursor --------------------------------------------------------
    # Index, not time: every number the read-out shows is then a recorded sample
    # verbatim. `1:length(t)` rather than `eachindex`, so the slider's own value is
    # an `Int` a test can set exactly. Same rule as `playback_window.jl`, and for
    # the same reason — there is no interpolant left on either side to resample with.
    sl = Slider(fig[4, 1]; range = 1:length(t), startvalue = 1, tellwidth = false)
    cursor = lift(sl.value) do i
        k = Int(i)
        (; i = k, t = t[k], f_classical = fc[k], f_detailed = fd[k], gap = gap[k],
           V = [v[k] for v in V], ΔV = [v[k] - v[1] for v in V])
    end
    cx = lift(c -> [c.t], cursor)
    vline_f = vlines!(ax_f, cx; color = (C_CURSOR, 0.9), linewidth = 1.5)
    vline_g = vlines!(ax_g, cx; color = (C_CURSOR, 0.9), linewidth = 1.5)
    vline_v = vlines!(ax_v, cx; color = (C_CURSOR, 0.9), linewidth = 1.5,
                      label = "cursor")
    # The dots the read-out's numbers come from, made visible. `Point2f` — Float32 —
    # so they are a picture and never an assertion target; `cursor` above carries
    # the Float64 the read-out formats.
    scatter!(ax_f, lift(c -> [Point2f(c.t, c.f_classical)], cursor);
             color = C_SWING, markersize = 11)
    scatter!(ax_f, lift(c -> [Point2f(c.t, c.f_detailed)], cursor);
             color = C_AGGREGATE, markersize = 11)
    scatter!(ax_g, lift(c -> [Point2f(c.t, max(c.gap, floor_v))], cursor);
             color = C_CURSOR, markersize = 11)
    for k in eachindex(buses)
        scatter!(ax_v, lift(c -> [Point2f(c.t, c.V[k])], cursor);
                 color = _bus_colour(k), markersize = 10)
    end

    # ---- the read-out column ----------------------------------------------
    gc = fig[1:4, 2] = GridLayout(tellheight = false, valign = :top)

    Legend(gc[1, 1], ax_f; tellwidth = false, tellheight = true, halign = :left)
    Legend(gc[2, 1], ax_v; tellwidth = false, tellheight = true, halign = :left,
           nbanks = 1)

    # The frequency cursor read-out: names once, values a `lift` (theme.jl).
    section_label!(gc[3, 1], "cursor — the channel both tiers report")
    ro_keys = "sample\nt\nclassical\ndetailed\n|f gap|"
    ro_values = lift(cursor) do c
        @sprintf("%d of %d\n%9.3f s\n%9.4f Hz\n%9.4f Hz\n%9.3e Hz",
                 c.i, length(t), c.t, c.f_classical, c.f_detailed, c.gap)
    end
    gro = gc[4, 1] = GridLayout()
    ro = readout_block!(gro, ro_keys; values = ro_values)
    readout = lift(v -> readout_text(ro_keys, v), ro_values)
    readout_label = ro.values_label

    # THE VOLTAGE READ-OUT, AND WHY IT HAS THREE COLUMNS RATHER THAN ONE. `|V|` is
    # the state; `Δ from t0` is the MOVEMENT, which is the thing this panel is
    # actually about; and `pre-event` is the offset the two runs started with, named
    # as such so it cannot be read as something the disturbance caused. Without the
    # middle column a reader compares a 0.13 offset against a 0.08 movement by eye,
    # on a panel where the offset is the larger.
    section_label!(gc[5, 1], "cursor — bus voltage, which only one tier has")
    v_keys = join(["$b" for b in buses], "\n")
    v_values = lift(cursor) do c
        join([@sprintf("%7.4f  Δ %+.4f", c.V[k], c.ΔV[k])
              for k in eachindex(buses)], "\n")
    end
    gvr = gc[6, 1] = GridLayout()
    vro = readout_block!(gvr, v_keys; values = v_values)
    voltage_readout = lift(v -> readout_text(v_keys, v), v_values)
    voltage_readout_label = vro.values_label

    # The band and its derivation together, FREQUENCY ONLY and labelled so. A band
    # whose provenance is not on the screen is a magic number, and `t_depart` is
    # only meaningful relative to it.
    depart = isnan(read.t_depart) ?
             "never — indistinguishable at this band" :
             @sprintf("%.3f s", read.t_depart)
    divergence_head = section_label!(gc[7, 1],
                                     "divergence on f_COI — the frequency channel only")
    # THE CHANNEL IS NAMED IN THE BLOCK ITSELF, not only in the heading above it. A
    # heading is a `Label` this builder did not hold, so "the read-out says which
    # channel this is" was a claim about a thing no check could reach — M3 step 7's
    # lesson, met again at the one place in this window where a reader could take a
    # frequency band as applying to the voltage panel.
    summary = @sprintf("channel   f_COI ONLY (frequency)\nband      %9.3e Hz\n          = 3 · reltol · excursion,\n            reltol %.0e\nmax       %9.3e Hz  at %.2f s\nrms       %9.3e Hz\ndeparts   %s\nsamples   %d",
                       band, reltol, read.max, read.t_max, read.rms, depart, read.n)
    summary_label = Label(gc[8, 1], summary; halign = :left, justification = :left,
                          tellwidth = false, font = MONO_FONT, fontsize = 13)

    # THE OFFSET, WRITTEN OUT AS A NUMBER AND CALLED AN ARTEFACT. The largest
    # quantity on the voltage panel is this one, so leaving it to be inferred from
    # the picture is exactly how it gets read as physics. Per bus, beside the
    # largest movement, so the two are comparable at a glance.
    section_label!(gc[9, 1], "voltage: what is an artefact and what is not")
    offset_rows = [@sprintf("%-4s pre-event %.4f   moved %.4f", buses[k],
                            offsets[k], excursions[k]) for k in eachindex(buses)]
    offset_text = "NO band here: a cross-tier voltage gap is a\nmodelling difference, not solver noise.\n\n" *
                  join(offset_rows, "\n") *
                  "\n\npre-event = Machine.E′ in two denominations,\nthere at t = 0. moved = what the run did."
    offset_label = Label(gc[10, 1], offset_text; halign = :left, justification = :left,
                         tellwidth = false, word_wrap = true, fontsize = 13,
                         font = MONO_FONT, color = C_MUTED)

    # The scenario, and the event log if the run had one. `SwingEngine` and
    # `DetailedEngine` both keep a log; the detailed tier's is used because it is the
    # side with the events, and both tiers are armed identically here (unlike M4's
    # pair, where the asymmetry was the point).
    event_text = isempty(events) ? "(no injected events: a ramp is armed at\nconstruction, so neither engine logs one)" :
                 join([@sprintf("%6.2f s  %s", e[1], e[2]) for e in events], "\n")
    section_label!(gc[11, 1], "scenario — armed identically on both tiers")
    scenario_label = Label(gc[12, 1], (isempty(scenario) ? "" : scenario * "\n\n") * event_text;
                           halign = :left, justification = :left, tellwidth = false,
                           word_wrap = true, fontsize = 13, color = C_MUTED)

    # Held by reference and returned, so a test can assert it is IN the figure's
    # layout rather than assert against an observable the picture might not contain
    # (M3 step 7: a Label with the right text that was never added to the figure
    # passes every text assertion anyone can write about it).
    caption = Label(fig[5, 1:2], _VOLTAGE_CAPTION; halign = :left,
                    justification = :left, tellwidth = false, word_wrap = true,
                    fontsize = 12, color = C_MUTED)

    rowsize!(fig.layout, 2, Relative(0.18))
    rowsize!(fig.layout, 3, Relative(0.30))
    rowsize!(fig.layout, 4, Fixed(40))
    colsize!(fig.layout, 2, Fixed(370))
    rowgap!(gc, 8)

    # Pinned limits, for the reason the other three windows pin theirs: two renders
    # meant to be compared must share a scale, or a gap three times larger draws the
    # same shape as a small one.
    xlims!(ax_f, t[1], t[end])
    ylims_f === nothing || ylims!(ax_f, ylims_f[1], ylims_f[2])
    if ylims_gap === nothing
        ylims!(ax_g, floor_v / 2, max(maximum(gap), Float64(band)) * 4)
    else
        ylims!(ax_g, ylims_gap[1], ylims_gap[2])
    end
    if ylims_v === nothing
        lo = min(minimum(minimum, V), minimum(E_assumed))
        hi = max(maximum(maximum, V), maximum(E_assumed))
        pad = max(0.02 * (hi - lo), 0.005)
        ylims!(ax_v, lo - pad, hi + pad)
    else
        ylims!(ax_v, ylims_v[1], ylims_v[2])
    end

    widgets = (; time = sl)
    axes = (; frequency = ax_f, gap = ax_g, voltage = ax_v)
    return (; fig, t, classical, detailed, gap, band = Float64(band), read, cursor,
              widgets, axes, caption, caption_text = _VOLTAGE_CAPTION,
              readout, voltage_readout, buses, V, E_assumed, offsets, excursions,
              events, readout_label, voltage_readout_label, summary_label,
              offset_label, scenario_label, divergence_head,
              voltage_lines = v_lines, assumed_lines = e_lines,
              cursor_lines = (; frequency = vline_f, gap = vline_g, voltage = vline_v))
end

# The machine data that turns `governed_ring()` into the detailed tier's model. The
# textbook large-machine values `scripts/iberia_two_area.jl` already sweeps around,
# reused rather than re-picked so the two places that need "a realistic synchronous
# machine" cannot drift apart.
#
# THE FIELD IS HELD HERE, NOT REGULATED — see the file header for the measurement
# that decided it (0.096 pu of movement against 0.0005 with the exciter armed).
const DETAILED_MACHINE = (; Xd = 1.8, Xq = 1.7, Xq′ = 0.55, Td0′ = 8.0, Tq0′ = 0.4)

# A static exciter, for a caller who wants to see the regulator hold the voltage
# instead. Named here so "arm the AVR" is one keyword rather than four numbers a
# caller has to know.
const DETAILED_AVR = (; K_A = 200.0, T_E = 0.05, Efd_max = 5.0)

# The tolerances, and they are NOT the engine defaults. `reltol = 1e-3` is too loose
# to resolve this tier (M5 step 7 measured it), and on the detailed tier it is
# `abstol` rather than `reltol` that decides whether a run COMPLETES — at isolated
# points, because a hard saturation makes the right-hand side discontinuous and the
# governor headroom is one even with no regulator. These are step 7's pair, on the
# completing side, with the integrator's own step cap raised past its 1e5 default.
const V_RELTOL, V_ABSTOL = 1.0e-5, 1.0e-8
const V_MAXITERS = 20_000_000

# The shipped disturbance: 60 MW of LOAD added over two seconds from t = 1 s, on
# `G3` — the ring's load, a machine with `P0 = −110 MW`, so a negative ramp draws
# more. `GenerationRamp` takes pu/s on `S_base`, so −0.30 pu/s × 2 s = −0.60 pu =
# 60 MW on this model's 100 MVA base. See the file header for why load added rather
# than generation lost, and why not twice as much.
const _DEFAULT_RAMP = GenerationRamp(-0.30, 1.0, 2.0)
const _DEFAULT_RAMP_MACHINE = :G3
const _DEFAULT_HORIZON = 60.0
const _DEFAULT_RAMP_TEXT =
    "ramp on G3, the ring's load:\n  −0.30 pu/s for 2.0 s from t = 1.0 s\n  = 60 MW MORE drawn, on top of 110 MW.\n\n" *
    "Load ADDED, not generation lost — see the\nfile header for the measurement that\nchose the direction."

# Solve the pair. Both engines are FRESH and both are armed with the SAME ramp:
# unlike M4's overlay, where the two tiers deliberately could not receive the same
# event, here they can and do, so any difference on the screen is the tier and not
# the scenario.
function _solve_voltage_pair(classical_net::NetworkModel, detailed_net::NetworkModel;
                             horizon::Real, ramp, perturbations, saveat::Real,
                             reltol::Real, abstol::Real, maxiters::Integer)
    sw = SwingEngine(classical_net; reltol = reltol, abstol = abstol, ramp = ramp)
    de = init!(DetailedEngine, detailed_net; reltol = reltol, abstol = abstol,
               maxiters = maxiters, ramp = ramp)
    solve!(sw, (0.0, horizon); perturbations = perturbations, saveat = saveat)
    solve!(de, (0.0, horizon); perturbations = perturbations, saveat = saveat)
    return sw, de
end

"""
    _assumed_constants(net) -> Vector{Float64}

The constant the classical tier holds at each bus, **in bus order**, looked up
through `machine_at` and never by position.

`V_<bus>` is indexed by bus and `net.machines` by machine, so pairing a solved
voltage with the wrong machine's constant is the one silent error this panel can
make — and on the shipped ring the three constants are 1.05, 1.03 and 1.04, close
enough that a transposed picture would look right.

**AND THAT ERROR IS ALREADY UNREACHABLE, which was measured rather than assumed and
is worth writing down because it changes what the check below is for.** `NetworkModel`
stores its machines SORTED BY BUS (`network_model.jl`, the field comment), and the
classical tier refuses a bus that does not carry exactly one machine
(`_assert_one_machine_per_bus`). Between them, machine index *equals* vertex index on
every model this window can be handed, so the positional version
`[m.E′ for m in net.machines]` returns the identical vector. A mutation to the
positional form was run against the whole UI suite and changed no answer anywhere.

So this is not a guard against a live bug. It is written through `machine_at` because
the equivalence is a property of two *other* invariants rather than of this code, and
`machine_at`'s own comment records that indexing `net.machines[v]` with a vertex "was
right only while the two indices coincided" — i.e. the general-case version of this
mistake has been made in this repo before. The lookup costs nothing and stays correct
if a tier ever accepts two machines on a bus.
"""
_assumed_constants(net::NetworkModel) =
    Float64[machine_at(net, b.id).E′ for b in net.buses]

# The fields the CLASSICAL tier reads. Every one of them must agree between the two
# models, or the comparison is of two cases rather than of two tiers.
const _CLASSICAL_FIELDS = (:id, :bus, :S_rated, :H, :D, :Xd′, :E′, :P0, :R, :Pmax, :Tg)

"""
    _assert_tier_pair(classical, detailed)

The comparison's own precondition, checked at build time rather than documented:
the two models must agree **exactly** in every field `SwingEngine` reads, so that
the difference between the two runs is the tier and nothing else.

This is M5 step 7's invariant, made structural at the one seam that can violate it.
The plan asked for one model handed to both engines; that is not available, because
`SwingEngine` refuses detailed machine data and a regulator by name — a classical
engine handed a real `Xd` would silently run a machine its own data does not
describe. What replaces it is this: two models from one definition
(`governed_ring(; detailed = …)`), agreeing bit for bit in what the classical tier
reads and differing in exactly the set it refuses.

`==` and not `≈`: these are the same numbers out of the same constructor, so any
difference at all is a different case being drawn as a tier boundary.

**It does not check that the two models start at the same operating point, and they
do not** — see the file header. That is a consequence of this invariant rather than
a violation of it: `Machine.E′` passes the check by being equal, and denominates a
different physical quantity on each side, which is exactly why the window has to
draw the pre-event offset as a labelled number instead of letting it read as
physics.
"""
function _assert_tier_pair(classical::NetworkModel, detailed::NetworkModel)
    length(classical.machines) == length(detailed.machines) || throw(ArgumentError(
        "voltage window: the classical model has $(length(classical.machines)) " *
        "machines and the detailed one $(length(detailed.machines)). The pair must be " *
        "one model definition built twice — see `governed_ring(; detailed = …)`."))
    for (mc, md) in zip(classical.machines, detailed.machines)
        for f in _CLASSICAL_FIELDS
            getfield(mc, f) == getfield(md, f) || throw(ArgumentError(
                "voltage window: machine $(mc.id) differs between the two models in " *
                "`$f` ($(getfield(mc, f)) against $(getfield(md, f))), and that is a " *
                "field the CLASSICAL tier reads. The two runs would then differ for " *
                "two reasons — the tier and the data — and the picture could not " *
                "attribute either. Build both from one definition " *
                "(`governed_ring(; detailed = …)`); the detailed keyword sets only " *
                "the fields `SwingEngine` refuses."))
        end
    end
    classical.branches == detailed.branches || throw(ArgumentError(
        "voltage window: the two models' branches differ. The network is not part of " *
        "the tier boundary — both tiers read it identically — so a difference here is " *
        "two cases, not two tiers."))
    (classical.S_base == detailed.S_base && classical.f0 == detailed.f0) ||
        throw(ArgumentError(
            "voltage window: the two models disagree on S_base or f0. Every per-unit " *
            "number on the screen is on that base."))
    return nothing
end

# Solve and build. Shared by `voltage_playback` and `voltage_playback_render` for
# the standing reason: the PNG a headless session looks at has to be a picture of
# the window a user opens.
#
# THE PAIR IS PASSED, NEVER DERIVED HERE. An earlier draft took the classical model
# and a NamedTuple of detailed fields and rebuilt the twin. That is a second copy of
# the model's construction living in the UI package — the forked-data hazard SPEC
# §3.2 forbids, in the one package that must never own model data. The core builds
# both (`governed_ring(; detailed = …)` is one definition producing two models) and
# this function checks the pair rather than making it.
function _voltage_window(classical_net::NetworkModel = governed_ring(),
                         detailed_net::NetworkModel =
                             governed_ring(; detailed = DETAILED_MACHINE);
                         horizon::Real = _DEFAULT_HORIZON,
                         ramp = nothing,
                         perturbations = Pair{Float64,PerturbationEvent}[],
                         saveat::Real = 0.02,
                         reltol::Real = V_RELTOL,
                         abstol::Real = V_ABSTOL,
                         maxiters::Integer = V_MAXITERS,
                         scenario::AbstractString = "",
                         kwargs...)
    _assert_tier_pair(classical_net, detailed_net)
    rr = ramp === nothing ? [_DEFAULT_RAMP_MACHINE => _DEFAULT_RAMP] : ramp
    txt = isempty(scenario) && ramp === nothing ? _DEFAULT_RAMP_TEXT : scenario

    sw, de = _solve_voltage_pair(classical_net, detailed_net; horizon = horizon,
                                 ramp = rr, perturbations = perturbations,
                                 saveat = saveat, reltol = reltol, abstol = abstol,
                                 maxiters = maxiters)
    cs, ds = state_series(sw), state_series(de)
    # Derived from the side we trust more (the detailed tier resolves what the
    # classical one holds constant) and from the tolerance the solve actually ran
    # at — never from looking at the gap.
    band = tolerance_band(system_frequency(ds); reltol = reltol)
    events = Tuple{Float64,String}[(e.t, describe_event(e)) for e in event_log(de)]

    buses = Symbol[b.id for b in classical_net.buses]
    E_assumed = _assumed_constants(classical_net)

    return _build_voltage_window(cs, ds; band = band, reltol = reltol,
                                 buses = buses, E_assumed = E_assumed,
                                 events = events, scenario = txt, kwargs...)
end

"""
    voltage_playback(classical_net = governed_ring(),
                     detailed_net = governed_ring(; detailed = DETAILED_MACHINE);
                     horizon = 60.0, ramp = nothing, perturbations = [],
                     saveat = 0.02, reltol = 1e-5, abstol = 1e-8, cursor_at = nothing,
                     title = …, ylims_f = nothing, ylims_gap = nothing, ylims_v = nothing)

Solve one scenario on the **classical** and **detailed** tiers and open the
voltage-visible playback window over the pair, returning `(; fig, t, classical,
detailed, gap, band, read, cursor, widgets, axes, caption, readout, buses, V,
E_assumed, offsets, screen)`.

**This window is the delivery of a promise `docs/plans/m4-plan.md` step 3 made on
M5's behalf, in writing:** *"Voltage coupling and inverter behaviour need a tier
that has voltage in it, and that is M5."* The voltage half is kept — the lower panel
draws bus voltage magnitudes the detailed tier carries as algebraic unknowns and
solves at every step, which is the quantity `playback`'s own caption says its pair
can never show. The **inverter half is not kept and does not become kept by
proximity** (`m5-context.md` D12): IBR behaviour is a third fidelity, unnamed and
unscheduled, and `docs/SPEC.md` §7.6 says so rather than letting this window imply
otherwise.

Playback, not real time, and that is decision D2 rather than a shortcut: `step!` is
not implemented at the detailed tier at all.

**The pair is two models from one definition, and it is PASSED rather than derived
here.** `governed_ring()` is the classical tier's and `governed_ring(; detailed = …)`
the detailed tier's; they agree bit for bit in every quantity `SwingEngine` reads
and differ in exactly the set it refuses by name. That agreement is not left as a
claim — `_assert_tier_pair` checks all eleven classical fields plus the branches and
the bases at build time, and refuses a pair that would make the two runs differ for
two reasons at once. Deriving the twin inside this package instead would put a
second copy of the model's construction in the one package that must never own model
data (SPEC §3.2). Both are solved to `horizon` on one `saveat` grid, which is what
makes them comparable at all — nothing here resamples, and the core refuses a pair
on two grids.

**Read the movement, not the offset.** The two runs do not start at the same bus
voltage, because `Machine.E′` denominates a different physical quantity at each tier
(the voltage *at* the bus classically, the source *behind* `(Ra + jXq)` in detail).
On the shipped fixture that puts the source 5.7× further back and the detailed power
flow solves the buses to ≈0.92 pu against the classical tier's 1.05/1.03/1.04 — a
0.135/0.107/0.120 pu offset present at `t = 0`, larger than the 0.090/0.096/0.094 pu
the disturbance then moves the voltage by. It is drawn, named in the caption, and
given as a number in the read-out beside `Δ from t0`. Hand `governed_ring()` to both
sides instead and the offsets collapse by a factor of ten, to 0.013/0.0003/0.010 pu
— which is what says the 0.13 is denomination and not a broken comparison.

**The default disturbance adds 60 MW of load, and every part of that was forced or
measured.** `DetailedEngine` refuses `TripGenerator` by name (a tripped machine
makes its bus passive, and a compiled vertex model cannot change shape at run time),
so `TripLine` is the only *event* both tiers take — and on this ring a line trip
moves the frequency 1.5 mHz and the voltage 0.004 pu, which is a picture of nothing.
A `GenerationRamp` is armed at construction instead, so both tiers get it
identically. It is on `G3`, the ring's load, so the voltage **sags** (0.920 → 0.826)
rather than rising: putting the same ramp on a generator unloads that machine and
its terminal voltage climbs *toward* the classical tier's constants, which reads as
the two tiers converging when nothing of the sort is happening. Twice the ramp
drives an outright voltage collapse (0.002 pu) and is deliberately not the default —
the detailed tier's load model has a named singularity there.

**The field is held, not regulated, by default.** Arm the exciter by passing the
detailed model built with one —

    voltage_playback(governed_ring(),
                     governed_ring(; detailed = merge(GridSimUI.DETAILED_MACHINE,
                                                      GridSimUI.DETAILED_AVR)))

— and the regulator does its job: the terminal voltage barely moves
(0.0005 pu against the held field's 0.096, and it ends where it started) while the
*field* voltage moves instead, `Efd` 1.051 → 1.115. That is a real result — step 7's
finding in miniature, that what acts on the voltage is the regulator working through
the flux — and it is the wrong default, because a voltage panel whose voltage is
flat teaches that voltage does nothing.

Drag the slider to move the cursor through the run; the read-out shows both tiers'
frequency, their gap, and every bus's solved `|V|` with its movement from `t = 0`.
`cursor_at` places the cursor at the recorded sample nearest a given time — no
interpolation, since the slider indexes samples.

**Point it at a single synchronous area.** Across an area split the inertia-weighted
mean is not a system frequency (D5) and the upper two panels mean nothing.

From a shell this must be followed by something that blocks:

    julia --project=ui -e "using GridSimUI; wait_for_close(voltage_playback())"
"""
function voltage_playback(classical_net::NetworkModel = governed_ring(),
                          detailed_net::NetworkModel =
                              governed_ring(; detailed = DETAILED_MACHINE);
                          horizon::Real = _DEFAULT_HORIZON,
                          ramp = nothing,
                          perturbations = Pair{Float64,PerturbationEvent}[],
                          saveat::Real = 0.02,
                          reltol::Real = V_RELTOL,
                          abstol::Real = V_ABSTOL,
                          maxiters::Integer = V_MAXITERS,
                          cursor_at::Union{Nothing,Real} = nothing,
                          title::AbstractString =
                              "GridSim — voltage-visible playback: classical tier vs detailed tier",
                          ylims_f = nothing, ylims_gap = nothing, ylims_v = nothing)
    GLMakie.activate!(; visible = true, title = "GridSim — voltage playback")
    win = _voltage_window(classical_net, detailed_net; horizon = horizon, ramp = ramp,
                          perturbations = perturbations, saveat = saveat,
                          reltol = reltol, abstol = abstol, maxiters = maxiters,
                          title = title, ylims_f = ylims_f, ylims_gap = ylims_gap,
                          ylims_v = ylims_v)
    cursor_at === nothing || _voltage_cursor_to_time!(win, cursor_at)
    screen = display(win.fig)
    return (; win..., screen)
end

"""
    voltage_playback_render(classical_net = governed_ring(),
                            detailed_net = governed_ring(; detailed = DETAILED_MACHINE);
                            path, …) -> path

Build the *same* voltage-visible window offscreen and save a PNG to `path`.

This is how the window is checked from a session with no screen — the standing
"render before claiming" rule (M2/M3), and it is run **before** the live window
rather than after. Everything `voltage_playback` accepts is accepted here, with one
difference in the default: the cursor is placed at the instant the bus voltages are
furthest from where they started, because a saved frame has no reader to drag the
slider and a cursor at the flat start shows nothing. Note that this is the largest
*movement*, not the largest gap between the tiers — the largest gap on the voltage
panel is the pre-event offset, and putting the saved cursor there would frame the
one number on the panel that is an artefact.

It is moved through `set_close_to!` on the very slider a user drags, not by writing
the cursor directly.
"""
function voltage_playback_render(classical_net::NetworkModel = governed_ring(),
                                 detailed_net::NetworkModel =
                                     governed_ring(; detailed = DETAILED_MACHINE);
                                 path::AbstractString,
                                 horizon::Real = _DEFAULT_HORIZON,
                                 ramp = nothing,
                                 perturbations = Pair{Float64,PerturbationEvent}[],
                                 saveat::Real = 0.02,
                                 reltol::Real = V_RELTOL,
                                 abstol::Real = V_ABSTOL,
                                 maxiters::Integer = V_MAXITERS,
                                 cursor_at::Union{Nothing,Real} = nothing,
                                 title::AbstractString =
                                     "GridSim — voltage-visible playback: classical tier vs detailed tier",
                                 ylims_f = nothing, ylims_gap = nothing, ylims_v = nothing)
    GLMakie.activate!(; visible = false)
    win = _voltage_window(classical_net, detailed_net; horizon = horizon, ramp = ramp,
                          perturbations = perturbations, saveat = saveat,
                          reltol = reltol, abstol = abstol, maxiters = maxiters,
                          title = title, ylims_f = ylims_f, ylims_gap = ylims_gap,
                          ylims_v = ylims_v)
    if cursor_at === nothing
        set_close_to!(win.widgets.time, _peak_movement_index(win))
    else
        _voltage_cursor_to_time!(win, cursor_at)
    end
    mkpath(dirname(path))
    save(path, win.fig)
    return path
end

# The sample at which some bus voltage is furthest from its own starting value —
# the largest MOVEMENT, deliberately not the largest cross-tier difference. See
# `voltage_playback_render`'s docstring.
function _peak_movement_index(win)
    best, bi = -1.0, firstindex(win.t)
    for v in win.V, i in eachindex(v)
        d = abs(v[i] - v[1])
        d > best && (best = d; bi = i)
    end
    return bi
end

# Put the cursor on the recorded sample NEAREST `τ`. Nearest, and never between:
# the slider indexes samples precisely so that no displayed number is a value nobody
# computed (file header).
function _voltage_cursor_to_time!(win, τ::Real)
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
