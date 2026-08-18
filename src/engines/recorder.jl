# Shared, bounded trajectory recording for every engine (SPEC §3.3).
#
# WHY THIS EXISTS. M1's engine appended to five parallel `Vector{Float64}`s on
# every `step!`, forever: a live run that is never stopped is an unbounded
# allocation. M2 adds a second engine with exactly the same shape, so the choice
# was fix-the-pattern-once or duplicate-the-leak (docs/plans/m2-tasks.md,
# "Carried over from M1"). This is the once.
#
# WHY DECIMATION AND NOT A RING BUFFER. A ring buffer keeps the most recent
# `capacity` samples and discards the oldest. For this domain that discards
# precisely the interesting part: the initial RoCoF slope and the frequency nadir
# both happen in the first seconds after a disturbance, so a long run would
# quietly throw away the headline numbers and leave a flat settled tail. Instead,
# when the buffer fills we halve it — keep every other retained sample — and from
# then on record at half the rate. The whole run stays visible at progressively
# coarser resolution, with the start never lost.
#
# THE RETENTION INVARIANT. After any number of pushes, the retained samples are
# exactly those whose 1-based push index `n` satisfies `(n - 1) % keep_every == 0`
# — an arithmetic progression that always starts at the very first sample. Note
# the deliberate ordering in `record!`: the keeper test is re-applied *after* a
# decimation, because doubling `keep_every` can disqualify the sample that
# triggered it (this is what goes wrong for odd capacities if you push blindly).
# Amortised cost is O(1) per push.
#
# TIME IS A MANDATORY CHANNEL, NOT AN OPTIONAL ONE. Decimation changes the
# effective sample interval mid-run, so any consumer that assumes a fixed `dt` —
# by finite-differencing the series, or by plotting against an implied index —
# silently goes wrong after the first halving. The constructor therefore prepends
# `:t` itself and refuses to be handed one, so no recorder can exist without its
# own time base and no `state_series` can hand back data without it.
# (`analysis/postprocess.jl`'s `windowed_rocof` already divides by the *actual*
# elapsed time rather than the nominal window, so it is decimation-safe as
# written — that was luck plus a good habit, and it is now a requirement.)
#
# RUNNING SUMMARIES MUST NOT BE DERIVED FROM THE BUFFER. Because the buffer
# decimates, `minimum(series.f)` is the lowest *retained* sample, not the lowest
# sample. Anything that must be exact (the nadir, a cumulative total) is tracked
# incrementally on the engine as each sample arrives, outside the recorder. M1
# already did this for its nadir; it is now load-bearing rather than incidental.

# Default capacity: at the usual 0.02 s step this is ~4000 s of simulated time
# before the first halving, which no test or interactive session comes near — the
# bound is a guard against an unattended run, not a working constraint.
const _TRAJ_CAPACITY = 200_000

"""
    TrajectoryRecorder{names,N}

Fixed-capacity, self-decimating recorder for `N` parallel `Float64` channels
named `names` (whose first element is always `:t`). Built by the constructor
below, never by filling fields by hand.

Type parameters carry the channel names so `series` can build its `NamedTuple`
without a runtime lookup; the channel vectors are a homogeneous
`NTuple{N,Vector{Float64}}`, so the per-sample push path is type-stable and
allocation-free (SPEC §4).

  - `channels`   — the retained data, `channels[1]` being time.
  - `capacity`   — maximum retained samples per channel; halved-into, never exceeded.
  - `keep_every` — current decimation stride (1 until the first halving).
  - `n_seen`     — total samples offered, including those the stride skipped.
"""
mutable struct TrajectoryRecorder{names,N}
    const channels::NTuple{N,Vector{Float64}}
    const capacity::Int
    keep_every::Int
    n_seen::Int
end

"""
    TrajectoryRecorder(channel_names::Symbol...; capacity = 200_000)

Build an empty recorder with a `:t` channel followed by `channel_names`, in that
order — so `series(rec)` comes back as `(; t, channel_names...)`.

`:t` is prepended automatically and passing it explicitly is an error: time is
mandatory (see the file header), and accepting it as one name among many would
make "recorder without a time base" a representable state.
"""
function TrajectoryRecorder(channel_names::Symbol...;
                            capacity::Integer = _TRAJ_CAPACITY)
    :t in channel_names && throw(ArgumentError(
        "TrajectoryRecorder: :t is prepended automatically, do not pass it"))
    isempty(channel_names) && throw(ArgumentError(
        "TrajectoryRecorder: needs at least one channel besides :t"))
    allunique(channel_names) || throw(ArgumentError(
        "TrajectoryRecorder: duplicate channel names in $(channel_names)"))
    # capacity < 2 cannot satisfy the retention invariant: halving a 1-element
    # buffer frees nothing, so the next push would overrun the bound.
    capacity >= 2 || throw(ArgumentError(
        "TrajectoryRecorder: capacity must be >= 2, got $capacity"))
    names = (:t, channel_names...)
    N = length(names)
    return TrajectoryRecorder{names,N}(ntuple(_ -> Float64[], N), Int(capacity), 1, 0)
end

# Halve the retained samples in place: keep positions 1, 3, 5, ... (so the first
# sample always survives) and double the stride. Copy-down-then-`resize!` rather
# than allocating fresh vectors — the buffers keep their capacity and the next
# `capacity/2` pushes need no reallocation.
function _decimate!(rec::TrajectoryRecorder)
    for ch in rec.channels
        m = length(ch)
        w = 0
        @inbounds for r in 1:2:m
            w += 1
            ch[w] = ch[r]
        end
        resize!(ch, w)
    end
    rec.keep_every *= 2
    return rec
end

"""
    record!(rec::TrajectoryRecorder{names,N}, values::Vararg{Real,N}) -> rec

Offer one sample — `values` in channel order, so `values[1]` is the timestamp.
The sample is retained only if the current stride selects it; if the buffer is
full it is halved first (see the retention invariant in the file header). The
arity is pinned by the type parameter, so a call with the wrong number of
channels is a `MethodError` at the call site rather than a length mismatch
discovered later.
"""
function record!(rec::TrajectoryRecorder{names,N}, values::Vararg{Real,N}) where {names,N}
    rec.n_seen += 1
    n = rec.n_seen
    (n - 1) % rec.keep_every == 0 || return rec
    length(rec.channels[1]) < rec.capacity || _decimate!(rec)
    # Re-test: the halving just doubled the stride, which may have disqualified
    # this very sample. Pushing it anyway is how the invariant breaks (visibly so
    # at odd capacities, where the retained samples stop being evenly spaced).
    (n - 1) % rec.keep_every == 0 || return rec
    v = ntuple(k -> Float64(values[k]), Val(N))   # unrolled; keeps the push stable
    @inbounds for k in 1:N
        push!(rec.channels[k], v[k])
    end
    return rec
end


"""
    record!(rec::TrajectoryRecorder{names,N}, t::Real, values::AbstractVector{<:Real}) -> rec

Same as the varargs form, for an engine whose channel count is not a compile-time
constant — `SwingEngine` has one angle and one speed channel per machine, so it
fills a reusable buffer and passes it here rather than splatting. `values` holds
the non-time channels, in order; the length is checked against the recorder rather
than pinned by dispatch, so the error names both counts.
"""
function record!(rec::TrajectoryRecorder{names,N}, t::Real,
                 values::AbstractVector{<:Real}) where {names,N}
    length(values) == N - 1 || throw(ArgumentError(
        "record!: got $(length(values)) channel values, expected $(N - 1) " *
        "for channels $(Base.tail(names))"))
    rec.n_seen += 1
    n = rec.n_seen
    (n - 1) % rec.keep_every == 0 || return rec
    length(rec.channels[1]) < rec.capacity || _decimate!(rec)
    (n - 1) % rec.keep_every == 0 || return rec
    @inbounds push!(rec.channels[1], Float64(t))
    @inbounds for k in 2:N
        push!(rec.channels[k], Float64(values[k - 1]))
    end
    return rec
end

"""
    series(rec::TrajectoryRecorder) -> NamedTuple

The retained trajectory as `(; t, ...)` over the recorder's channel names. The
vectors are the live buffers, not copies: read them, do not mutate them, and do
not hold one across further `record!` calls (a decimation rewrites them in place).
"""
series(rec::TrajectoryRecorder{names}) where {names} = NamedTuple{names}(rec.channels)

"""
    n_kept(rec) -> Int

Samples currently retained (never more than the capacity). Distinct from
`rec.n_seen`, which counts every sample offered — their ratio is the decimation
that has happened so far.
"""
n_kept(rec::TrajectoryRecorder) = length(rec.channels[1])
