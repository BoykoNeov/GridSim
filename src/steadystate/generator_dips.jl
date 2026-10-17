# ─────────────────────────────────────────────────────────────────────────────
# M9 step 5: the dip (m9-context.md D0 Hurdles 16.2–16.6, D9).
#
# A STATIC SCREEN HAS NO INERTIA, so the lowest frequency an outage reaches needs a
# dynamic run (16.2): one per generator outage, in the detailed tier (the one dynamic
# tier that takes `Load`), on the screened grid itself — lossy, with its loads — and
# from the AC screen's OWN base solution, so the run and the screen start from one
# operating point. Every outage is run, whatever the AC screen said of it: the refusal
# mismatch (16.6) needs both columns on every row, and step 0 went wrong exactly by
# skipping one on the refused rows.
#
# FOUR RULES (D9):
#
#   1. Whose frequency (16.3). Every surviving machine's own speed is judged; the
#      centre-of-inertia dip is reported beside it and never in its place — the mean
#      can sit between two machines that are separating. The extremes are tracked in
#      the engine over every output sample (`speed_extremes`), never read back from
#      the recorder, which decimates.
#   2. When to stop (16.4) — on the run's OWN settling, never on the screen's value
#      (default loads settle 12–23 % away from it, D1). The slowest approach is a
#      governor-capped grid sliding on damping alone, `f∞ + A·e^(−t/τ)` with
#      `τ = 2ΣH/ΣD` over the survivors, and there the dip IS the settled value, so
#      stopping early reports a dip too shallow: a false pass. Its remaining shortfall
#      is `τ·|ḟ|`, so the run stops once that is below `_DIP_SHORTFALL` at every
#      settling read for one more `τ` (a trough, where `ḟ` passes through zero, cannot
#      stop it). A horizon reached first is `:not_reached`, never the last sample.
#      Every run waits for settling — the plan's "a minimum followed by a recovery
#      fixes the dip" is not used: a governor that caps later can slide below the
#      first trough. THE FINE RUN ALONE DECIDES WHEN, and the coarse run is integrated
#      over exactly the same span: at 1e-6 the detailed tier keeps a numerical wobble
#      of ~3e-7 Hz that never decays (mesh-default G3: `τ·|ḟ|` stays near 2e-5 Hz for
#      400 s while the 1e-8 run is below 1e-7 by 40 s, D9), so a coarse run asked to
#      settle on its own never does — and the coarse run exists to show whether the
#      verdict moves with the tolerance, not to judge settling.
#   3. Two tolerances, frozen (16.5): FBDF at reltol 1e-6 and 1e-8, abstol reltol/100.
#      A failure at either is `:solver_failure`, never retried at a third. Where both
#      finish, BOTH runs' numbers are kept and the verdict is taken at each: it
#      counts only where the two agree (`frequency_verdicts`; the user's choice,
#      D9). There is no agreement band — the one first stated (`tolerance_band` at
#      the coarse reltol) does not bound a 1e-6 run's global error over a 100 s slide
#      and left the 10.94 Hz outage unjudged (D9).
#   4. The trip's re-initialisation is CLASSIFIED, through the code that throws for
#      every other caller (`_trip_generator!`): the voltage band or a branch rating is
#      `:refused_at_trip`; a stalled static solve or a residual over threshold is
#      `:solver_failure` (D7 finding 2). A failed integration is read off the
#      integrator's own retcode. Nothing here matches an error's text.
#
# M9 STEP 6 — THE RATE OF FALL (16.7, D10) is read from these same runs; nothing new is
# integrated. Each measured run keeps its output-grid samples (`FrequencyTrace`) and
# the window is applied when the rate is read (`generator_rates`), so runs and a limit
# can never disagree on it. Every surviving machine's rate is judged, the COI's reported
# beside it (the user's choice, D10 — rule 1 again). Differenced by `windowed_rocof`
# and nothing else, handed the window HALF A SAMPLE SHORT, so the sample exactly one
# window back is found whatever the grid's rounding: handed the window itself,
# `t[i] − w` can round to just below a grid point and the read reaches one sample
# further, a bias that grows as the window shrinks. A window off the 0.01 s grid is
# refused (5 ms would become 10 ms), and so is a trace the recorder decimated (every
# window would silently widen).
# ─────────────────────────────────────────────────────────────────────────────

# The frozen pair, coarse first: (reltol, abstol). Changing it after a run has been
# seen is choosing an answer (16.5).
const _DIP_TOLERANCES = ((1.0e-6, 1.0e-8), (1.0e-8, 1.0e-10))
const _DIP_DT = 0.01            # s — the output grid the running extremes see
const _DIP_CHUNK = 0.5          # s — between settling reads
const _DIP_SHORTFALL = 1.0e-5   # Hz — the most dip the stopping rule may leave unseen
const _DIP_HORIZON = 40         # time constants after the trip (the default)

"""
    FrequencyTrace

One dip run's output-grid samples (M9 step 6), what [`generator_rates`](@ref)
differences: `t`, s, from the run's start every `0.01` s; `f_coi`, Hz, the
centre-of-inertia frequency; `f`, Hz, one column per machine in model order (the
machine lost included — its column is never read after the trip). Empty for an outage
that measured nothing. Never decimated: [`generator_dips`](@ref) refuses a run that
could fill the recorder.
"""
struct FrequencyTrace
    t::Vector{Float64}
    f_coi::Vector{Float64}
    f::Matrix{Float64}
end
FrequencyTrace() = FrequencyTrace(Float64[], Float64[], zeros(0, 0))

"""
    GeneratorDips

The dynamic run of every generator outage ([`generator_dips`](@ref)), in model order,
each at the two frozen tolerances (FBDF, reltol 1e-6 and 1e-8).

  - `machines`, `branches` — the model's ids, so a verdict can refuse another model's
    runs; `f0`, Hz; `t_trip`, s.
  - `outcome` — `:measured` (both runs settled); `:refused_at_trip` (the tier's
    re-initialisation refused the post-trip network at both); `:solver_failure` (a run
    failed to integrate, or its static solve stalled or missed its residual);
    `:tolerance_dependent` (one run refused at the trip and the other did not, or for
    a different reason); `:not_reached` (the fine run met its horizon before
    settling — it alone decides when a run stops, and the coarse one covers its span).
  - `reason` — `:none` when measured; `:voltage` or `:rating` for a refusal; `:stalled`,
    `:residual` or `:integration` for a solver failure; `:refusal` when tolerance
    dependent; `:horizon` when not reached.
  - `Δf_coi`, `Δf_coi_coarse` — the centre-of-inertia dip, Hz below nominal, at each
    tolerance. Reported beside the machines', never judged in their place.
  - `Δf_machine`, `Δf_machine_coarse` — per machine, its largest deviation either way
    while online, signed, Hz; `NaN` for the machine lost.
  - `worst`, `Δf_worst`, `Δf_worst_coarse` — the surviving machine with the largest
    `|Δf_machine|` at the fine tolerance, and each run's own largest (which may be
    another machine's).
  - `Δf_end` — the fine run's COI deviation where it stopped; `t_stop` — when, s.
  - `trace`, `trace_coarse` — each run's samples ([`FrequencyTrace`](@ref)), what the
    rate of fall is read from ([`generator_rates`](@ref), M9 step 6). The coarse run
    covers the fine run's span.

Every number is `NaN` (and `worst` is `:none`, each trace empty) unless the outcome is
`:measured`. No value is ever a verdict.
"""
struct GeneratorDips
    machines::Vector{Symbol}
    branches::Vector{Symbol}
    f0::Float64
    t_trip::Float64
    outcome::Vector{Symbol}
    reason::Vector{Symbol}
    Δf_coi::Vector{Float64}
    Δf_coi_coarse::Vector{Float64}
    Δf_machine::Vector{Vector{Float64}}
    Δf_machine_coarse::Vector{Vector{Float64}}
    worst::Vector{Symbol}
    Δf_worst::Vector{Float64}
    Δf_worst_coarse::Vector{Float64}
    Δf_end::Vector{Float64}
    t_stop::Vector{Float64}
    trace::Vector{FrequencyTrace}
    trace_coarse::Vector{FrequencyTrace}
end

# A run's samples, for the rate of fall. A decimated recorder has thinned its samples,
# so a window measured over them is wider than it says; `generator_dips` refuses a
# horizon that could fill the recorder, so reaching this is a bug, not an outcome.
function _frequency_trace(eng::DetailedEngine)
    eng.traj.keep_every == 1 || error(
        "generator_dips: the run's recorder decimated (every $(eng.traj.keep_every) " *
        "samples kept), so a windowed rate over it would be over a wider window than " *
        "stated. The horizon check should have refused this run.")
    s = state_series(eng)
    f = Matrix{Float64}(undef, length(s.t), length(eng.ids))
    for (k, id) in enumerate(eng.ids)
        f[:, k] .= eng.f0 .* (1 .+ getproperty(s, Symbol(:ω_, id)))
    end
    return FrequencyTrace(copy(s.t), copy(s.f_coi), f)
end

# A run's integration over `(t0, t1)`, a failure read off the integrator's own retcode
# rather than the error's text: `false` on a failed integration. Anything raised while
# the retcode does not name a failure is rethrown — a step-count collapse, for one, is
# `_playback!`'s "a bug, not a horizon", and a bad `tspan` is the caller's mistake.
# `Default` is NOT a failure: it is what an integrator that has not finished reads, and
# `successful_retcode` calls it unsuccessful — testing that alone classified a refused
# `tspan` before the first step as a failed integration (found by the test).
_integration_failed(rc) =
    rc != SciMLBase.ReturnCode.Default && !SciMLBase.successful_retcode(rc)

function _dip_solve!(eng::DetailedEngine, t0::Float64, t1::Float64)
    try
        solve!(eng, (t0, t1); saveat = _DIP_DT)
    catch
        _integration_failed(eng.integrator.sol.retcode) || rethrow()
        return false
    end
    return true
end

# One outage at one tolerance: `(status, reason, eng, t_stop)`, `status` one of
# `:settled` (the stopping rule met), `:ran` (integrated to `until`, no settling
# read), `:refused`, `:failed`, `:not_reached`. `until = t_trip` stops right after
# the trip. `init_kw` goes to `init!` and is here only so a test can make an
# integration fail on purpose (its `maxiters`).
function _dip_run(net::NetworkModel, base::ACPowerFlow, id::Symbol, t_trip::Float64,
                  τ::Float64, reltol::Float64, abstol::Float64;
                  horizon::Real = _DIP_HORIZON,
                  until::Union{Nothing,Float64} = nothing, init_kw...)
    eng = init!(DetailedEngine, net; powerflow = base, reltol, abstol,
                solver = OrdinaryDiffEq.FBDF(), init_kw...)
    _dip_solve!(eng, 0.0, t_trip) || return (:failed, :integration, eng, NaN)
    reason, _ = _trip_generator!(eng, TripGenerator(id))
    reason in (:voltage, :rating) && return (:refused, reason, eng, NaN)
    reason === :ok || return (:failed, reason, eng, NaN)
    t, t_end, quiet = t_trip, until === nothing ? t_trip + horizon * τ : until, NaN
    while t < t_end
        _dip_solve!(eng, t, min(t + _DIP_CHUNK, t_end)) ||
            return (:failed, :integration, eng, NaN)
        t = eng.integrator.t
        until === nothing || continue
        if τ * abs(coi_rocof(eng)) <= _DIP_SHORTFALL
            isnan(quiet) && (quiet = t)
            t - quiet >= τ && return (:settled, :none, eng, t)
        else
            quiet = NaN
        end
    end
    return until === nothing ? (:not_reached, :horizon, eng, NaN) : (:ran, :none, eng, t)
end

# A signed extreme: whichever of a run's lowest and highest deviation is larger.
_extreme(lo::Float64, hi::Float64) = abs(lo) >= abs(hi) ? lo : hi

"""
    generator_dips(net, base::ACPowerFlow; t_trip = 1.0, horizon = 40) -> GeneratorDips
    generator_dips(net, ac::ACGeneratorOutages; kw...)
    generator_dips(net, s::OutageScreen; kw...)

Run every generator outage of `net` in the detailed tier from the AC screen's own base
solution (`ac.base`, `s.ac_generators.base`), each tripped at `t_trip` and run to its
own settling, at both frozen tolerances. See [`GeneratorDips`](@ref) for what comes
back and this file's header for the four rules (`m9-context.md` D9). Hand the result
to [`frequency_verdicts`](@ref) as `dips =` to judge the dip.

Two stiff runs per machine, each until it settles — up to `horizon` time constants
after the trip, `τ = 2ΣH/ΣD` over the survivors (system base); an outage that has not
settled by then is `:not_reached`, never its last sample.

Refused by name: a model with inverters (the stopping rule's `τ` has no inverter terms),
and an outage that leaves no machine, or whose survivors have no damping (no `τ`).
"""
function generator_dips(net::NetworkModel, base::ACPowerFlow; t_trip::Real = 1.0,
                        horizon::Real = _DIP_HORIZON)
    isempty(net.inverters) || throw(ArgumentError(
        "generator_dips: the model has inverters " *
        "($(join((i.id for i in net.inverters), ", "))). The stopping rule's time constant " *
        "2ΣH/ΣD is the machines' alone — an inverter's droop and virtual inertia are " *
        "not in it (m9-context.md D9) — so a run could be stopped early. Refused."))
    tt = Float64(t_trip)
    (isfinite(tt) && tt > 0) || throw(ArgumentError(
        "generator_dips: t_trip must be positive and finite, got $t_trip."))
    (isfinite(horizon) && horizon > 0) || throw(ArgumentError(
        "generator_dips: horizon (time constants after the trip) must be positive and " *
        "finite, got $horizon."))
    ma = machine_arrays(net)
    ids = Symbol[m.id for m in net.machines]
    nm = length(ids)
    outcome, reason, worst = fill(:none, nm), fill(:none, nm), fill(:none, nm)
    Δf_coi, Δf_coi_c, Δf_worst, Δf_worst_c, Δf_end, t_stop =
        (fill(NaN, nm) for _ in 1:6)
    Δf_mach, Δf_mach_c = [fill(NaN, nm) for _ in 1:nm], [fill(NaN, nm) for _ in 1:nm]
    trace, trace_c = [FrequencyTrace() for _ in 1:nm], [FrequencyTrace() for _ in 1:nm]
    (rc, ac), (rf, af) = _DIP_TOLERANCES
    for k in 1:nm
        others = [j for j in 1:nm if j != k]
        isempty(others) && throw(ArgumentError(
            "generator_dips: losing $(ids[k]) leaves no machine online — no frequency " *
            "left to measure."))
        ΣD = sum(ma.D[others])
        ΣD > 0 || throw(ArgumentError(
            "generator_dips: the machines left after losing $(ids[k]) have no damping, " *
            "so a governor-capped slide never settles and the stopping rule has no time " *
            "constant (m9-context.md D9)."))
        τ = 2 * sum(ma.H[others]) / ΣD
        # The rate of fall is read off every sample (step 6), so a run must not be able
        # to fill the recorder: the seed, then one sample per `_DIP_DT` to the horizon.
        n = 1 + ceil(Int, (tt + horizon * τ) / _DIP_DT)
        n <= _TRAJ_CAPACITY || throw(ArgumentError(
            "generator_dips: losing $(ids[k]) could run for " *
            "$(round(tt + horizon * τ; sigdigits = 4)) s ($horizon time constants of " *
            "$(round(τ; sigdigits = 4)) s) — " *
            "$n samples, past the recorder's $(_TRAJ_CAPACITY). The recorder would " *
            "decimate and the rate of fall would be read over wider windows than stated. " *
            "Use a shorter horizon."))
        # The fine run decides when to stop; the coarse one covers the same span
        # (through the trip only, where the fine run did not get past it).
        sf, why_f, ef, ts = _dip_run(net, base, ids[k], tt, τ, rf, af; horizon)
        span = sf === :settled ? ts : sf === :not_reached ? tt + horizon * τ : tt
        sc, why_c, ec, _  = _dip_run(net, base, ids[k], tt, τ, rc, ac; until = span)
        if sc === :failed || sf === :failed
            outcome[k], reason[k] = :solver_failure, sf === :failed ? why_f : why_c
        elseif sc === :refused && sf === :refused && why_c === why_f
            outcome[k], reason[k] = :refused_at_trip, why_f
        elseif sc === :refused || sf === :refused
            outcome[k], reason[k] = :tolerance_dependent, :refusal
        elseif sc === :not_reached || sf === :not_reached
            outcome[k], reason[k] = :not_reached, :horizon
        else
            outcome[k] = :measured
            xc, xf = speed_extremes(ec), speed_extremes(ef)
            for j in others
                Δf_mach[k][j]   = _extreme(xf.Δf_min[j], xf.Δf_max[j])
                Δf_mach_c[k][j] = _extreme(xc.Δf_min[j], xc.Δf_max[j])
            end
            jw = others[argmax(abs.(Δf_mach[k][others]))]
            worst[k], Δf_worst[k] = ids[jw], Δf_mach[k][jw]
            Δf_worst_c[k] = Δf_mach_c[k][others[argmax(abs.(Δf_mach_c[k][others]))]]
            Δf_coi[k], Δf_coi_c[k] = ef.nadir - net.f0, ec.nadir - net.f0
            Δf_end[k], t_stop[k] = current_state(ef).f_coi - net.f0, ts
            trace[k], trace_c[k] = _frequency_trace(ef), _frequency_trace(ec)
        end
    end
    return GeneratorDips(ids, Symbol[b.id for b in net.branches], net.f0, tt, outcome,
                         reason, Δf_coi, Δf_coi_c, Δf_mach, Δf_mach_c, worst, Δf_worst,
                         Δf_worst_c, Δf_end, t_stop, trace, trace_c)
end

generator_dips(net::NetworkModel, ac::ACGeneratorOutages; kw...) =
    generator_dips(net, ac.base; kw...)
generator_dips(net::NetworkModel, s::OutageScreen; kw...) =
    generator_dips(net, s.ac_generators; kw...)

"""
    GeneratorRates

The rate of fall of every generator outage over one window ([`generator_rates`](@ref),
M9 step 6), read from a [`GeneratorDips`](@ref)'s runs, in model order.

  - `machines`, `f0`, Hz; `t_trip`, s; `window`, s — the window every rate here is
    measured over; `outcome` — the runs' own (see `GeneratorDips`).
  - `rate_coi`, `rate_coi_coarse` — the centre-of-inertia rate, Hz/s, at each
    tolerance: the largest `|windowed rate|` over every window ending after the trip
    (those straddling it included — what a relay sees), kept signed (negative when
    frequency falls). Reported beside the machines', never judged in their place.
  - `rate_machine`, `rate_machine_coarse` — the same read per machine; `NaN` for the
    machine lost.
  - `worst`, `rate_worst`, `rate_worst_coarse` — the surviving machine with the largest
    `|rate|` at the fine tolerance, and each run's own largest (which may be another
    machine's).

Every number is `NaN` (and `worst` is `:none`) unless the outcome is `:measured`.
"""
struct GeneratorRates
    machines::Vector{Symbol}
    f0::Float64
    t_trip::Float64
    window::Float64
    outcome::Vector{Symbol}
    rate_coi::Vector{Float64}
    rate_coi_coarse::Vector{Float64}
    rate_machine::Vector{Vector{Float64}}
    rate_machine_coarse::Vector{Vector{Float64}}
    worst::Vector{Symbol}
    rate_worst::Vector{Float64}
    rate_worst_coarse::Vector{Float64}
end

# The largest |windowed rate| over windows ending after the trip, signed. The window is
# handed over half a sample short (this file's header); `windowed_rocof` divides by the
# actual span.
function _largest_rate(t::Vector{Float64}, f::AbstractVector{Float64}, window::Float64,
                       t_trip::Float64)
    r = windowed_rocof(t, f; window = window - _DIP_DT / 2)
    best = NaN
    for i in eachindex(t)
        (t[i] > t_trip && !isnan(r[i])) || continue
        (isnan(best) || abs(r[i]) > abs(best)) && (best = r[i])
    end
    isnan(best) && error("generator_rates: no window of $window s ends after the trip " *
                         "inside the run ($(t[end]) s).")
    return best
end

"""
    generator_rates(dips::GeneratorDips; window) -> GeneratorRates

The rate of fall of every outage in `dips`, over `window` seconds, at both tolerances,
from the runs' own samples — nothing is integrated again. See
[`GeneratorRates`](@ref). [`frequency_verdicts`](@ref) calls this with the limit's own
`rate_window`.

`window` must be a whole number of the runs' 0.01 s output samples, at least one:
anything else is refused, since a read on that grid could only round it.
"""
function generator_rates(d::GeneratorDips; window::Real)
    w = Float64(window)
    m = w / _DIP_DT
    (isfinite(w) && round(m) >= 1 && abs(m - round(m)) <= 1e-9 * m) || throw(ArgumentError(
        "generator_rates: the window ($window s) must be a whole number of the runs' " *
        "$(_DIP_DT) s output samples, at least one — a read on that grid would round it."))
    nm = length(d.machines)
    rc, rcc, rw, rwc = (fill(NaN, nm) for _ in 1:4)
    rm, rmc = [fill(NaN, nm) for _ in 1:nm], [fill(NaN, nm) for _ in 1:nm]
    worst = fill(:none, nm)
    for k in 1:nm
        d.outcome[k] === :measured || continue
        tr, tc = d.trace[k], d.trace_coarse[k]
        rc[k] = _largest_rate(tr.t, tr.f_coi, w, d.t_trip)
        rcc[k] = _largest_rate(tc.t, tc.f_coi, w, d.t_trip)
        others = [j for j in 1:nm if j != k]
        for j in others
            rm[k][j] = _largest_rate(tr.t, view(tr.f, :, j), w, d.t_trip)
            rmc[k][j] = _largest_rate(tc.t, view(tc.f, :, j), w, d.t_trip)
        end
        jw = others[argmax(abs.(rm[k][others]))]
        worst[k], rw[k] = d.machines[jw], rm[k][jw]
        rwc[k] = rmc[k][others[argmax(abs.(rmc[k][others]))]]
    end
    return GeneratorRates(copy(d.machines), d.f0, d.t_trip, w, copy(d.outcome), rc, rcc,
                          rm, rmc, worst, rw, rwc)
end
