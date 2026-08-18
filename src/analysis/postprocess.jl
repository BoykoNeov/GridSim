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
