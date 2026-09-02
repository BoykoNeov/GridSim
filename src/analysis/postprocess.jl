# Post-processing reads over a recorded trajectory. Engine-agnostic: everything
# here takes the plain vectors (or the `state_series` NamedTuple) that any engine
# produces, so it works for real-time and playback tiers alike.

"""
    windowed_rocof(t, f; window = 0.5) -> Vector{Float64}
    windowed_rocof(series; window = 0.5) -> (; t, RoCoF)

Rate of change of frequency measured over a **sliding time window**, the way
system operators actually measure it:

    RoCoF(tᵢ) = (f(tᵢ) − f(tⱼ)) / (tᵢ − tⱼ),   tⱼ = last sample at or before tᵢ − window

The default 500 ms is ENTSO-E best practice, and **every RoCoF figure in the
ENTSO-E Iberian blackout report is a 500 ms window** (report p.116). This is a
*different quantity* from the instantaneous `f0·dΔω/dt` that `current_state`
returns: during a fast transient they differ substantially, so comparing the
instantaneous value against a reported "−1 Hz/s" is comparing two different
things. The instantaneous value stays the live readout and the closed-form
validation target (docs/SPEC.md §7.6); this is an **additional** read, not a
replacement (docs/plans/entsoe-iberia-reproduction.md §3.3).

Returns a vector the **same length** as `t`, `NaN` where the window is not yet
full (there is no earlier sample a whole `window` back). Same length so it
overlays directly on `f(t)` in a stacked panel, and `NaN` because Makie skips it
— beats silently reporting a short-window value as if it were a 500 ms one.

The divisor is the **actual** elapsed time `tᵢ − tⱼ`, not the nominal `window`:
samples need not be uniformly spaced just because `step!` currently makes them so.
"""
function windowed_rocof(t::AbstractVector{<:Real}, f::AbstractVector{<:Real};
                        window::Real = 0.5)
    length(t) == length(f) ||
        throw(ArgumentError("windowed_rocof: length(t)=$(length(t)) != length(f)=$(length(f))"))
    window > 0 || throw(ArgumentError("windowed_rocof: window must be > 0, got $window"))
    out = fill(NaN, length(t))
    for i in eachindex(t)
        # Last sample at or before tᵢ − window (t is non-decreasing by construction).
        j = searchsortedlast(t, t[i] - window)
        j >= firstindex(t) || continue      # window not full yet ⇒ leave NaN
        dt = t[i] - t[j]
        dt > 0 || continue                  # degenerate duplicate timestamps
        out[i] = (f[i] - f[j]) / dt
    end
    return out
end

windowed_rocof(series::NamedTuple; window::Real = 0.5) =
    (; t = series.t, RoCoF = windowed_rocof(series.t, series.f; window = window))

# ---------------------------------------------------------------------------
# M4 step 2 — the divergence read between two trajectories of one scenario.
#
# WHY THERE IS NO RESAMPLING HERE, AND WHY THAT IS THE RESULT OF THE STEP.
# `m4-plan.md` step 2 offered two ways to put two trajectories on one grid: "the
# solver's own interpolant, or a shared `saveat` grid fixed before the solve".
# Reading the engines settles which: BOTH constructors build their integrator with
# `dense = false` and `save_everystep = false` (they must — a live run that is
# never stopped would otherwise grow without bound), and `calck = true` keeps the
# interpolation coefficients of the CURRENT step only. Once a step has closed, its
# interpolant is gone. So after `solve!` returns there is no interpolant to resample
# with — the only samples that exist are the ones the caller's `saveat` grid asked
# for, taken by the framework inside `savevalues!` at the one instant they are
# valid (`engines/playback.jl`, D9).
#
# That leaves exactly one sound route, and this file makes it STRUCTURAL rather
# than a rule somebody has to remember: solve both runs onto one grid, hand both
# series here, and the read refuses anything else. There is no code path in this
# file that draws a straight line between two recorded samples, because the error
# of that line would land in precisely the quantity being measured and the recorder
# decimates, so late in a run the samples are far apart. `test/` measures how far
# above the agreement band that error sits on a real swing, so the refusal is a
# quantified choice and not a scruple.
#
# LIKE WITH LIKE. Across fidelity tiers the only comparable channel is the
# inertia-weighted (centre-of-inertia) system frequency: `f_coi` on the network
# tier, `f` on the aggregate tier. A per-machine speed against the aggregate is a
# comparison of two different quantities, and a per-machine ANGLE is gauge-arbitrary
# on top of that (the fixpoint solver picks the common offset). `system_frequency`
# is the one place that choice is written down; `divergence` on two series defaults
# to it and takes any other channel selector explicitly, so comparing an angle
# DIFFERENCE (gauge-free) is one keyword away and comparing a raw angle is a
# deliberate act.
#
# THE BAND IS STATED BEFORE THE READ, NOT CHOSEN AFTER IT. `t_depart` — the first
# instant the gap exceeds `band` — is the "where do they part company" answer, and
# it is only an answer if `band` came from somewhere other than looking at the gap.
# `band` is therefore a REQUIRED keyword, and `tolerance_band` derives the one
# this repo already uses (M4 step 1: three times the relative tolerance times the
# channel's own excursion). Below that band a gap is a statement about two solver
# paths, not about two fidelity tiers — `test/` shows the same physical 4.4 µHz
# swing residual read as "indistinguishable" at the default tolerance and as a
# located, sized peak once the tolerance is tightened past it.
# ---------------------------------------------------------------------------

"""
    system_frequency(series::NamedTuple) -> AbstractVector{Float64}

The one recorded channel that is comparable **across fidelity tiers**: the
inertia-weighted (centre-of-inertia) system frequency in Hz. That is `f_coi` on the
network tier (`SwingEngine`) and `f` on the aggregate tier
(`FrequencyResponseEngine`); if a series carries both, `f_coi` wins, because it is
the explicitly aggregated one. Never a per-machine channel — a machine's own speed
is one machine's deviation, and its angle is gauge-arbitrary besides.

Throws if the series has neither, naming the channels it does have.
"""
function system_frequency(series::NamedTuple)
    haskey(series, :f_coi) && return series.f_coi
    haskey(series, :f) && return series.f
    throw(ArgumentError("system_frequency: the series has neither :f_coi nor :f " *
                        "(channels: $(keys(series))). Only the centre-of-inertia " *
                        "frequency is comparable across tiers; pass a channel " *
                        "selector to `divergence` to compare anything else deliberately."))
end

"""
    tolerance_band(reference::AbstractVector; reltol, factor = 3) -> Float64

The agreement band below which a gap between two runs is **solver noise, not a
result**: `factor · reltol · (peak excursion of `reference` from its first sample)`.
This is the band M4 step 1 wrote down *before* comparing real-time and playback
runs, and the reasoning is the same here: a relative tolerance is relative to the
signal being resolved (hence the excursion, not the level — a 50 Hz level with a
0.1 Hz swing is a 0.1 Hz signal), and two independently error-controlled paths
contribute two errors (hence a factor above 2, rounded up to 3).

Hand it the series you trust more — the higher-fidelity run, or the playback one
in a real-time-vs-playback check. Non-finite samples (a windowed RoCoF's unfilled
head) are ignored. Throws on a series with no finite sample, or on a
non-positive `reltol`.

A band chosen *after* looking at the gap tests nothing; this function exists so
the band has a stated derivation instead.
"""
function tolerance_band(reference::AbstractVector{<:Real}; reltol::Real,
                        factor::Real = 3)
    (isfinite(reltol) && reltol > 0) || throw(ArgumentError(
        "tolerance_band: reltol must be positive and finite, got $reltol"))
    factor > 0 || throw(ArgumentError("tolerance_band: factor must be > 0, got $factor"))
    i0 = findfirst(isfinite, reference)
    i0 === nothing && throw(ArgumentError(
        "tolerance_band: the reference series has no finite sample"))
    v0 = Float64(reference[i0])
    exc = 0.0
    @inbounds for v in reference
        isfinite(v) || continue
        exc = max(exc, abs(Float64(v) - v0))
    end
    return Float64(factor) * Float64(reltol) * exc
end

# Two grids count as "the same" when every sample lands within this of its partner.
# Not `==`: M4 step 1 measured that the real-time loop accumulates `t` by repeated
# addition of `dt` while the playback grid is `t0 + k*dt`, so two runs of one
# scenario differ in the last bits of their time stamps (below 1e-12 s there). A
# nanosecond is nine orders below any output step this repo uses and eleven above
# that roundoff; anything past it is a genuinely different grid.
const _GRID_ATOL = 1.0e-9   # s

function _same_grid(ta::AbstractVector{<:Real}, tb::AbstractVector{<:Real}, who::String)
    length(ta) == length(tb) || throw(ArgumentError(
        "$who: the two series are on different grids ($(length(ta)) vs $(length(tb)) " *
        "samples). Solve both runs onto ONE `saveat` grid fixed before the solve; " *
        "nothing here resamples, on purpose (see analysis/postprocess.jl)."))
    @inbounds for i in eachindex(ta, tb)
        abs(ta[i] - tb[i]) <= _GRID_ATOL || throw(ArgumentError(
            "$who: the two series are on different grids — sample $i is at t = " *
            "$(ta[i]) in one and t = $(tb[i]) in the other (more than $(_GRID_ATOL) s " *
            "apart). Solve both runs onto ONE `saveat` grid fixed before the solve; " *
            "nothing here resamples, on purpose (see analysis/postprocess.jl)."))
    end
    return nothing
end

"""
    divergence(t, a, b; band) -> (; max, t_max, rms, t_depart, n)
    divergence(series_a, series_b; band, channel = system_frequency) -> same

How far, and from when, two trajectories of **one scenario on one output grid**
part company. `a` and `b` are the same physical channel from two runs — two
fidelity tiers, two execution modes, two tolerances — and `t` is the grid both
were recorded on. The two-series form checks that the grids agree (to `1e-9` s)
and **refuses otherwise rather than resampling**: see the note at the head of
this section for why there is no interpolant to resample with and why a straight
line between recorded samples is not acceptable.

  - `max`, `t_max` — the largest `|a − b|` and the instant it occurs.
  - `rms`          — time-weighted root-mean-square gap (trapezoidal rule on the
                     actual sample times, so a decimated tail is not over-counted).
  - `t_depart`     — the first instant at which `|a − b| > band`, or `NaN` if the
                     gap never leaves the band. **This is the "where do they part
                     company" read**, and it is only meaningful because `band` is
                     required to be stated up front — derive it with
                     [`tolerance_band`](@ref), not by looking at `max`.
  - `n`            — samples compared. Samples where either side is non-finite
                     (e.g. the unfilled head of a `windowed_rocof`) are skipped,
                     and the RMS is taken over the spans between compared samples.

Symmetric in `a` and `b`. `band` must be positive and finite. `channel` is any
function of a series returning one vector, so a gauge-free angle difference is
`channel = s -> s.δ_G1 .- s.δ_G2`; the default is the one cross-tier channel.
"""
function divergence(t::AbstractVector{<:Real}, a::AbstractVector{<:Real},
                    b::AbstractVector{<:Real}; band::Real)
    n = length(t)
    (length(a) == n && length(b) == n) || throw(ArgumentError(
        "divergence: length(t)=$n, length(a)=$(length(a)), length(b)=$(length(b)) " *
        "must all agree"))
    n >= 1 || throw(ArgumentError("divergence: empty series"))
    (isfinite(band) && band > 0) || throw(ArgumentError(
        "divergence: band must be positive and finite, got $band — derive it with " *
        "`tolerance_band` before looking at the gap"))
    issorted(t) || throw(ArgumentError("divergence: t must be non-decreasing"))

    gmax = 0.0
    imax = 0
    n_cmp = 0
    t_depart = NaN
    num = 0.0                # ∫ gap² dt over compared spans (trapezoid)
    den = 0.0                # ∫ dt over the same spans
    prev_ok = false
    prev_g2 = 0.0
    prev_t = 0.0
    @inbounds for i in 1:n
        g = abs(Float64(a[i]) - Float64(b[i]))
        ok = isfinite(g)
        if ok
            n_cmp += 1
            if imax == 0 || g > gmax
                gmax = g
                imax = i
            end
            if isnan(t_depart) && g > band
                t_depart = Float64(t[i])
            end
            if prev_ok
                h = Float64(t[i]) - prev_t
                num += 0.5 * (prev_g2 + g * g) * h
                den += h
            end
            prev_g2 = g * g
            prev_t = Float64(t[i])
        end
        prev_ok = ok
    end
    n_cmp >= 1 || throw(ArgumentError(
        "divergence: no sample at which both series are finite"))
    # One compared sample (or all at one instant) has no span to average over; the
    # gap itself is then the only honest RMS.
    rms = den > 0 ? sqrt(num / den) : gmax
    return (; max = gmax, t_max = Float64(t[imax]), rms = rms, t_depart = t_depart,
              n = n_cmp)
end

function divergence(sa::NamedTuple, sb::NamedTuple; band::Real,
                    channel = system_frequency)
    _same_grid(sa.t, sb.t, "divergence")
    return divergence(sa.t, channel(sa), channel(sb); band = band)
end
