# ─────────────────────────────────────────────────────────────────────────────
# M9 step 4: the frequency verdict and its limits, on the settled value
# (m9-context.md D0 Hurdle 16.1, D2, D3).
#
# A SEPARATE VERDICT, BESIDE THE SCREENS' OUTCOMES (D2.5, the user's choice). Nothing
# M8 built is touched: the screens, their comparisons and `OutageScreen` keep every
# field, and `:secure` keeps meaning "lines and voltages". The verdict is computed FROM
# a finished screen, so a caller who never asks for one sees M8 exactly.
#
# LIMITS ARE REQUIRED (D2.4): there is no default and no keyword that falls back to
# one. The preset carries only what its source publishes (D3).
#
# ONE PART PER CRITERION. The settled value is judged here, per screen, on that
# screen's own Δω (D0 16.1: neither screen is the reference). The dip and the rate need
# a dynamic run (steps 5–6); until it exists a limit given for them is reported
# `:not_run`, never `:pass`, and the settled value is never read in their place — not
# even where a capped grid's dip happens to equal it.
# ─────────────────────────────────────────────────────────────────────────────

# Optional limits are `Union{Nothing,Float64}`, not a sentinel: a NaN sentinel would
# compare false both ways and pass or fail silently, and `Inf` would make "no limit"
# indistinguishable from "a limit nothing reaches". The small union is the same
# shape as the screens' `Union{ACPowerFlow,Nothing}` and stays inferable.
const _OptHz = Union{Nothing,Float64}

"""
    FrequencyLimits(; settled = nothing, dip = nothing, rate = nothing,
                    rate_window = nothing)

The frequency limits an outage is judged against, each optional and each a
**deviation from nominal** — so the same limits serve a 50 Hz and a 60 Hz grid, and
the verdict converts with the model's own `f0`.

  - `settled` — Hz, the largest allowed settled deviation, either direction.
  - `dip` — Hz, the largest allowed instantaneous deviation (judged from step 5's
    dynamic run; until then reported `:not_run`).
  - `rate` — Hz/s, the largest allowed rate of change, **with** `rate_window`, s, the
    time over which it is measured. A rate without a window is refused: the sources
    disagree on the window and a RoCoF without one is not a number (`m9-context.md`
    D0 16.7, D3). So is a window with no rate.

Each limit given must be finite and positive. A set with no limit at all is refused:
every verdict would read "no limit", which looks like a check that ran.

Reaching a limit exactly passes: the sources state each as a **maximum** deviation.

See [`continental_europe_limits`](@ref) for the one preset.
"""
struct FrequencyLimits
    settled::_OptHz
    dip::_OptHz
    rate::_OptHz
    rate_window::_OptHz
    function FrequencyLimits(; settled = nothing, dip = nothing, rate = nothing,
                             rate_window = nothing)
        check(name, x) = x === nothing ? nothing :
            (x isa Real && isfinite(x) && x > 0) ? Float64(x) :
            throw(ArgumentError("FrequencyLimits: `$name` ($x) must be a finite, positive " *
                                "number, or left out."))
        s, d, r, w = check(:settled, settled), check(:dip, dip), check(:rate, rate),
                     check(:rate_window, rate_window)
        (r === nothing) == (w === nothing) || throw(ArgumentError(
            r === nothing ?
            "FrequencyLimits: a `rate_window` ($w s) was given with no `rate` to judge over it." :
            "FrequencyLimits: a `rate` limit ($r Hz/s) needs its `rate_window` in seconds. " *
            "The sources disagree on the window — NC DCC Art. 28(2)(k) says 500 ms, NC HVDC " *
            "Art. 12 the previous 1 s — and a rate of change without its window is not one " *
            "number (m9-context.md D3)."))
        s === nothing && d === nothing && r === nothing && throw(ArgumentError(
            "FrequencyLimits: no limit given. Every verdict would read `:no_limit`, which " *
            "looks like a check that ran."))
        return new(s, d, r, w)
    end
end

"""
    continental_europe_limits() -> FrequencyLimits

The Continental Europe synchronous area's frequency quality parameters: **settled
0.2 Hz, dip 0.8 Hz, no rate.** From Commission Regulation (EU) 2017/1485 (SO GL),
Annex III Table 1, OJ L 220/116: "maximum steady-state frequency deviation 200 mHz",
"maximum instantaneous frequency deviation 800 mHz" (copy under
`docs/evidence/gridsim-m9/sogl/`).

**These are design values, not a pass/fail rule.** SO GL defines them as the largest
deviation expected after an imbalance up to the reference incident — 3 000 MW for
Continental Europe (Art. 153(2)(b)(i)) — on a whole synchronous area (Art. 3, defs. 47
and 144). Applied to an outage on a small grid with invented droop they say something
about that droop, not about the grid's survival.

**No rate limit:** no area-wide value is published. NC RfG Art. 13(1)(b) and NC DCC
Art. 28(2)(k) leave it to the TSO; NC HVDC Art. 12's ±2.5 Hz/s is for HVDC systems;
ENTSO-E's 2 Hz/s is a study hypothesis with no window (`m9-context.md` D3). A caller who
judges the rate supplies the limit and its window.
"""
continental_europe_limits() = FrequencyLimits(; settled = 0.2, dip = 0.8)

"""
    FrequencyVerdicts

The frequency verdict of every outage in one screen, beside — never inside — the
screen's own outcomes ([`frequency_verdicts`](@ref)). Every vector is in the screen's
order.

  - `kind`, `id` — `:machine` rows only when built from a
    [`GeneratorScreenComparison`](@ref); every row of an [`OutageScreen`](@ref) when
    built from one (`:branch` then `:machine`).
  - `limits` — the [`FrequencyLimits`](@ref) judged against; `f0` — the model's
    nominal frequency, Hz, that converted each deviation.
  - `Δf_dc`, `Δf_ac` — each screen's own settled deviation, Hz (`Δω·f0`): negative
    when frequency falls. `NaN` where that screen produced none, and on line rows.
  - `settled_dc`, `settled_ac` — `:pass` (`|Δf| ≤ settled`), `:fail`, `:no_limit` (no
    settled limit given: every machine row then), `:no_value` (the screen produced no settled value it stands
    behind: a refusal, or AC's `:no_solution`), or `:not_applicable` (a line outage
    loses no generation, `m9-context.md` D4).
  - `settled` — the two side by side: `:both_pass`, `:both_fail`, `:dc_only_fails`,
    `:ac_only_fails`, `:one_unjudged` (one screen has no value), `:unjudged` (neither
    has), `:no_limit`, `:not_applicable`. A disagreement is reported, never resolved:
    neither screen is the reference (D0 16.1).
  - `dip`, `rate` — `:not_run` where a limit is given (the dynamic run that judges
    them is not built yet), `:no_limit` where none is, `:not_applicable` on line rows.

A line row that [`lone_source_bridges`](@ref) maps to a machine carries that
machine's verdict, as `OutageScreen` carries its outcome.
"""
struct FrequencyVerdicts
    kind::Vector{Symbol}
    id::Vector{Symbol}
    limits::FrequencyLimits
    f0::Float64
    Δf_dc::Vector{Float64}
    Δf_ac::Vector{Float64}
    settled_dc::Vector{Symbol}
    settled_ac::Vector{Symbol}
    settled::Vector{Symbol}
    dip::Vector{Symbol}
    rate::Vector{Symbol}
end

# The outcomes under which each screen stands behind its settled Δω. DC solves the
# shares exactly whenever it shares; AC's `:voltage` and `:overload` are solved operating
# points judged against other limits, while `:no_solution` — even where a solve got as
# far as a Δω (a switching backoff, a residual over threshold) — is not one.
const _DC_SETTLED = (:secure, :overload)
const _AC_SETTLED = (:secure, :overload, :voltage)

function _settled_verdict(Δf::Float64, has_value::Bool, lim::_OptHz, who)
    # A screen that says it solved and hands back no number broke its own contract;
    # judging NaN would pass or fail silently, so it is not judged at all.
    has_value && !isfinite(Δf) && error("frequency_verdicts: the $who screen reports a " *
                                        "solved outcome with a settled deviation of $Δf Hz.")
    lim === nothing && return :no_limit
    has_value || return :no_value
    return abs(Δf) <= lim ? :pass : :fail
end

function _settled_pair(dc::Symbol, ac::Symbol)
    (dc === :no_limit || ac === :no_limit) && return :no_limit
    nd, na = dc === :no_value, ac === :no_value
    nd && na && return :unjudged
    (nd || na) && return :one_unjudged
    dc === ac && return dc === :pass ? :both_pass : :both_fail
    return dc === :fail ? :dc_only_fails : :ac_only_fails
end

_pending(lim::_OptHz) = lim === nothing ? :no_limit : :not_run

"""
    frequency_verdicts(net, gens::GeneratorScreenComparison, limits::FrequencyLimits)
        -> FrequencyVerdicts
    frequency_verdicts(net, s::OutageScreen, limits::FrequencyLimits) -> FrequencyVerdicts

Judge every generator outage's frequency against `limits`, per screen, on that
screen's **own** settled deviation (`m9-context.md` D0 16.1), converted to Hz with
`net.f0`. Built from a finished screen, which it does not change: with no call to this
function, every M8 output is what it was (D2.5).

The `OutageScreen` form gives one row per row of the screen: line outages are
`:not_applicable`, and a line that IS a lone generator's outage carries that
generator's verdict. Both forms take the model, for `f0` and to refuse a screen of
another model — the `OutageScreen` by its branch and machine ids, the comparison by
what it carries (machine ids, and one entry per branch in each solved outage's miss).

The limits are required; [`continental_europe_limits`](@ref) is the one preset. Only
the settled value is judged so far — see [`FrequencyVerdicts`](@ref) for the dip and
the rate.
"""
function frequency_verdicts(net::NetworkModel, gens::GeneratorScreenComparison,
                            limits::FrequencyLimits)
    ids = Symbol[m.id for m in net.machines]
    # The comparison carries machine ids and, per solved outage, one miss per branch:
    # that is all there is to check it against (two fixtures can share machine ids).
    nb = length(net.branches)
    (gens.machines == ids && all(v -> isempty(v) || length(v) == nb, gens.reactive)) ||
        throw(ArgumentError(
            "frequency_verdicts: the screen is not of this model — machines " *
            "$(gens.machines) against $ids, or branch counts other than $nb."))
    nm = length(ids)
    has_dc = [o in _DC_SETTLED for o in gens.dc_outcome]
    has_ac = [o in _AC_SETTLED for o in gens.ac_outcome]
    # Where a screen stands behind no value, its number is not reported either.
    Δf_dc = [has_dc[k] ? gens.Δω_dc[k] * net.f0 : NaN for k in 1:nm]
    Δf_ac = [has_ac[k] ? gens.Δω_ac[k] * net.f0 : NaN for k in 1:nm]
    settled_dc = [_settled_verdict(Δf_dc[k], has_dc[k], limits.settled, "DC") for k in 1:nm]
    settled_ac = [_settled_verdict(Δf_ac[k], has_ac[k], limits.settled, "AC") for k in 1:nm]
    return FrequencyVerdicts(fill(:machine, nm), ids, limits, net.f0, Δf_dc, Δf_ac,
                             settled_dc, settled_ac, _settled_pair.(settled_dc, settled_ac),
                             fill(_pending(limits.dip), nm), fill(_pending(limits.rate), nm))
end

function frequency_verdicts(net::NetworkModel, s::OutageScreen, limits::FrequencyLimits)
    bids = Symbol[b.id for b in net.branches]
    nb = length(bids)
    (length(s.id) == nb + length(net.machines) && s.id[1:nb] == bids) || throw(ArgumentError(
        "frequency_verdicts: the screen is not of this model — rows $(s.id) against " *
        "branches $bids then the machines."))
    g = frequency_verdicts(net, s.generators, limits)
    N = length(s.id)
    # Row `r` → the machine whose verdict it carries, or 0 for a line that loses none.
    src = [r <= nb ? (s.via[r] === :none ? 0 : findfirst(==(s.via[r]), g.id)) : r - nb
           for r in 1:N]
    pick(v::Vector{Float64}) = [k == 0 ? NaN : v[k] for k in src]
    pick(v::Vector{Symbol}) = [k == 0 ? :not_applicable : v[k] for k in src]
    return FrequencyVerdicts(copy(s.kind), copy(s.id), limits, net.f0, pick(g.Δf_dc),
                             pick(g.Δf_ac), pick(g.settled_dc), pick(g.settled_ac),
                             pick(g.settled), pick(g.dip), pick(g.rate))
end
