# M8 — single-outage screening (docs/plans/m8-plan.md, m8-context.md).
#
# Step 2: the DC line-outage factors. Losing branch `k` in the linear power flow
# moves every other branch `m` by
#
#     Δf_m = PTDF_mk / (1 − PTDF_kk) · f_k,
#
# where `PTDF_mk` is how much of a unit transfer injected at `k`'s `from` end and
# withdrawn at its `to` end crosses `m`. That is an IDENTITY of the DC power flow,
# not an approximation of it: removing a branch is a rank-one change to `B`, and this
# is the rank-one update written in flows (m8-context.md D0, Hurdle 13.1). So the
# screen's check is exact agreement with rebuilding the model without `k` and
# solving again.
#
# NO PTDF IS EVER FORMED (D4). A full PTDF is branches × buses and dense, the shape
# `CLAUDE.md` refuses for an admittance matrix. The reduced susceptance matrix is
# factorised ONCE, sparsely, and each outage costs one solve against that
# factorisation for its own column, `B_r φ = e_from − e_to`, used and dropped.
#
# A BRIDGE IS FOUND FROM THE GRAPH, NEVER FROM `1 − PTDF_kk` (Hurdle 14). At a bridge
# that number is zero in exact arithmetic and the formula divides by it. In floating
# point it comes out at round-off, and with EITHER sign: measured on case9 at step 2,
# its three bridges give −2.2e-16, 0.0 and 0.0, while a connected grid whose second
# path has reactance 1e7 pu gives 1.0e-8. No cut-off separates those reliably, and
# the outside checker's (1e-6) misfires on that connected grid. `Graphs.bridges`
# answers the question that is actually being asked. Nothing is thresholded, so a
# nearly-split grid still gets an answer; it costs accuracy (about
# `eps/(1 − PTDF_kk)` relative), not correctness.

"""
    DCLineOutages

Every single-branch outage of a model, screened with the linear power flow.

  - `base` — the intact model's [`DCPowerFlow`](@ref); `base.branches` names the
    branches, and every vector below is in that order
  - `splits` — `true` where losing that branch splits the grid (a **bridge**, found
    from the graph). No flows are computed for a split: the linear power flow of a
    split grid is not defined until something decides who serves the cut-off part.
  - `margin` — `1 − PTDF_kk` for every branch, **bridges included**: the share of a
    transfer across `k` that has another way round. Kept so that a bridge's value is
    visible as what it is (round-off, either sign) rather than as an exact zero.
  - `flow` — for each outage `k`, the post-outage active power on **every** branch,
    pu on `S_base`, in the model's own orientation; entry `k` is exactly `0.0`.
    Empty for a split.

`flow` is branches × branches, because that is the size of the question "every
outage, every branch". It is not a factor matrix: the matrix that would be dense
(the PTDF, branches × buses) is never formed (`m8-context.md` D4).
"""
struct DCLineOutages
    base::DCPowerFlow
    splits::Vector{Bool}
    margin::Vector{Float64}
    flow::Vector{Vector{Float64}}
end

# `true` per branch, in model order, where removing that branch disconnects the
# graph. `Graphs.bridges` returns edges with `src < dst`, so the match is on the
# unordered bus pair: a branch declared `to → from` is still found.
function _bridge_mask(net::NetworkModel)
    topo = branch_topology(net)
    g = Graphs.SimpleGraph(length(net.buses))
    for e in eachindex(topo.src)
        Graphs.add_edge!(g, topo.src[e], topo.dst[e])
    end
    cut = Set{Tuple{Int,Int}}(minmax(Graphs.src(e), Graphs.dst(e)) for e in Graphs.bridges(g))
    return Bool[minmax(topo.src[e], topo.dst[e]) in cut for e in eachindex(topo.src)]
end

# The susceptance matrix with the reference bus's row and column deleted, from the
# susceptances `b` the caller holds, and the vertices it keeps (in order). Stored
# entries: `n + 2m` for the full matrix (`_dc_susceptance`), less the reference
# bus's diagonal and its `2·degree` off-diagonals.
function _dc_reduced_susceptance(net::NetworkModel, b::Vector{Float64})
    topo = branch_topology(net)
    n = length(net.buses)
    v_ref = net.bus_index[net.slack]
    keep = [v for v in 1:n if v != v_ref]
    return _dc_susceptance(n, topo.src, topo.dst, b)[keep, keep], keep
end

"""
    dc_line_outages(net::NetworkModel) -> DCLineOutages

Screen every single-branch outage of `net` with the linear (DC) power flow, through
the line-outage factors: one sparse factorisation, then one solve per branch.

The result is **the same numbers as rebuilding the model without each branch and
calling [`dc_powerflow`](@ref)** on it, to round-off, without building a model per
outage. A branch whose loss would split the grid is reported in `splits` and gets no
flows; rebuilding refuses those same branches, because `NetworkModel` refuses a
disconnected model.

The reference bus plays no part in the answer: it only fixes where angles are
measured from, and every quantity here is an angle **difference**. Moving the slack
moves no flow.

The approximation is `dc_powerflow`'s: `R` ignored, every `|V| = 1`, no reactive
power. So this screen cannot see a voltage problem at all, by construction
(`m8-context.md` D0, Hurdle 13.4). It reports flows; judging them against ratings is
the next step's.
"""
function dc_line_outages(net::NetworkModel)
    base = dc_powerflow(net)
    topo = branch_topology(net)
    n, m = length(net.buses), length(topo.src)
    f = base.flow
    # ONE susceptance vector, read by the matrix AND by each branch's flow weight
    # below. Two separate reads would let them disagree, and a ring cannot see that
    # disagreement (Hurdle 13.2), so it is not left possible.
    b = inv.(topo.X)
    splits = _bridge_mask(net)
    margin = Vector{Float64}(undef, m)
    flow = Vector{Vector{Float64}}(undef, m)
    m == 0 && return DCLineOutages(base, splits, margin, flow)

    Br, keep = _dc_reduced_susceptance(net, b)
    # Symmetric positive definite on a connected grid, which `NetworkModel`
    # guarantees: one Cholesky factorisation serves every outage.
    F = LinearAlgebra.cholesky(LinearAlgebra.Symmetric(Br))
    slot = zeros(Int, n)                   # vertex → row of `Br`; 0 for the reference
    slot[keep] = 1:length(keep)
    rhs = zeros(Float64, length(keep))
    φ = zeros(Float64, n)                  # the reference bus's entry stays 0.0

    for k in 1:m
        # The transfer across `k`: +1 at its `from` end, −1 at its `to` end, with the
        # reference bus's entry deleted along with its row.
        fill!(rhs, 0.0)
        i, j = topo.src[k], topo.dst[k]
        slot[i] > 0 && (rhs[slot[i]] += 1.0)
        slot[j] > 0 && (rhs[slot[j]] -= 1.0)
        φ[keep] = F \ rhs
        margin[k] = 1.0 - b[k] * (φ[i] - φ[j])
        if splits[k]
            flow[k] = Float64[]            # never divided by `margin[k]`
            continue
        end
        post = Vector{Float64}(undef, m)
        for e in 1:m
            ptdf_ek = b[e] * (φ[topo.src[e]] - φ[topo.dst[e]])
            post[e] = f[e] + ptdf_ek / margin[k] * f[k]
        end
        # Exactly zero, not `f_k − f_k` to round-off: the branch is gone.
        post[k] = 0.0
        flow[k] = post
    end
    return DCLineOutages(base, splits, margin, flow)
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: the same outages through the nonlinear solve, and what the shortcut missed.
#
# THE AC SCREEN IS NOT A SHORTCUT. It rebuilds the model without each branch and runs
# `ac_powerflow`'s own solve on it, classified rather than thrown (D3): there is no
# rank-one update of a nonlinear flow. What it buys is the answer the DC screen
# approximates, so the gap between the two is a measurement of the shortcut and not
# of a second, different model.
#
# EACH OUTAGE'S SOLUTION IS ONE BRANCH SHORTER than the model, because the branch is
# gone. Every branch after the outaged one sits one index lower in it, so the two
# screens are matched BY BRANCH ID, never by position.
# ─────────────────────────────────────────────────────────────────────────────

# `net` without branch `k`, every other collection carried. A bridge leaves a
# disconnected model, which `NetworkModel` refuses; callers decide bridges from the
# graph first and never reach that refusal.
_without_branch(net::NetworkModel, k::Int) =
    NetworkModel(net.S_base, net.f0, net.buses,
                 Branch[b for (e, b) in pairs(net.branches) if e != k],
                 net.machines, net.loads; slack = net.slack, inverters = net.inverters)

# What `_ac_powerflow_outcome` reports, as concrete types: a struct field typed `Any`
# is the performance cliff `CLAUDE.md` names.
const _OverEntry = @NamedTuple{kind::Symbol, id::Symbol, mva::Float64, rating::Float64}
const _LowEntry = @NamedTuple{bus::Symbol, Vm::Float64}

"""
    ACLineOutages

Every single-branch outage of a model, screened with the nonlinear power flow — the
same solve [`ac_powerflow`](@ref) runs, switching included, with its refusals
**classified** instead of thrown (`m8-context.md` D3).

  - `base` — the intact model's `ACPowerFlow`. The screen exists only for a base case
    `ac_powerflow` accepts; any other refuses the whole screen, with
    `ac_powerflow`'s own message.
  - `branches` — branch ids, in model order; every vector below is in that order.
  - `splits` — `true` where losing that branch splits the grid, decided from the
    graph (Hurdle 14). Never solved.
  - `outcome` — `:splits`, `:secure`, `:overload`, `:voltage` or `:no_solution`.
  - `solution` — the post-outage `ACPowerFlow` for `:secure` and `:overload` (unless
    an overload's residual also failed), else `nothing`. **It has one branch fewer
    than the model**, so read it by branch id.
  - `over` — for `:overload`, every element over its rating, `(kind, id, mva,
    rating)` in MVA. `kind` is `:branch`, or `:inverter_slack` for a grid-forming
    slack over its rating.
  - `low` — for `:voltage`, every bus outside the band, `(bus, Vm)`.
  - `reason` — for `:no_solution`, why (`:newton`, `:switching`, `:backoff`,
    `:residual`); `:none` otherwise.
"""
struct ACLineOutages
    base::ACPowerFlow
    branches::Vector{Symbol}
    splits::Vector{Bool}
    outcome::Vector{Symbol}
    solution::Vector{Union{ACPowerFlow,Nothing}}
    over::Vector{Vector{_OverEntry}}
    low::Vector{Vector{_LowEntry}}
    reason::Vector{Symbol}
end

"""
    ac_line_outages(net::NetworkModel) -> ACLineOutages

Screen every single-branch outage of `net` with the nonlinear (AC) power flow: for
each branch that is not a bridge, rebuild the model without it and run the solve
`ac_powerflow` runs, classifying the result (`m8-context.md` D3).

The base case must be one `ac_powerflow` accepts. If it is not, this throws exactly
what `ac_powerflow(net)` throws: a screen of outages from an operating point the
network cannot hold says nothing about the outages.

Bridges are found from the graph, as in [`dc_line_outages`](@ref), and never solved.
Losing one leaves two grids, and who serves the cut-off part is a decision the screen
does not take (Hurdle 14).

Unlike the DC screen this can see voltage: a `:voltage` outcome is exactly the case
the linear flow has no way to express (Hurdle 13.4). Compare the two with
[`compare_line_screens`](@ref).
"""
function ac_line_outages(net::NetworkModel)
    base = ac_powerflow(net)
    splits = _bridge_mask(net)
    m = length(net.branches)
    outcome = Vector{Symbol}(undef, m)
    solution = Vector{Union{ACPowerFlow,Nothing}}(nothing, m)
    over = [_OverEntry[] for _ in 1:m]
    low = [_LowEntry[] for _ in 1:m]
    reason = fill(:none, m)
    for k in 1:m
        if splits[k]
            outcome[k] = :splits
            continue
        end
        r = _ac_powerflow_outcome(_without_branch(net, k))
        outcome[k] = r.outcome
        solution[k] = r.solution
        r.outcome === :overload && append!(over[k], r.detail)
        r.outcome === :voltage && append!(low[k], r.detail)
        r.outcome === :no_solution && (reason[k] = r.detail.reason)
    end
    return ACLineOutages(base, Symbol[b.id for b in net.branches], splits, outcome,
                         solution, over, low, reason)
end

"""
    LineScreenComparison

The DC and AC line screens of one model, side by side, and what the DC shortcut
missed (`m8-context.md` D0, Hurdle 13).

  - `branches`, `splits` — as in both screens; every vector is in this order.
  - `dc_base_over` — branches the **DC** base case puts over their rating. The AC base
    is secure by construction ([`ac_line_outages`](@ref) refuses otherwise), so a
    non-empty list here is already a disagreement. It is reported rather than
    refused, because refusing would hide it.
  - `dc_outcome` — `:secure`, `:overload` or `:splits`: the DC flows judged against
    the same ratings the AC solve is held to.
  - `ac_outcome` — the AC screen's outcome.
  - `dc_over`, `ac_over` — the branches each screen puts over its rating. A
    grid-forming slack over its rating is not a branch and is not listed here.
  - `class` — per outage:
      - `:splits` — a bridge; neither screen solves it;
      - `:dc_blind` — the AC outcome is `:voltage` or `:no_solution`, or a
        grid-forming slack is over its rating: things a flow of `P` alone cannot
        express;
      - `:agree` — both put exactly the same branches over (often none);
      - `:dc_missed` — AC overloads a branch DC passes, and DC flags nothing AC
        does not;
      - `:dc_false_alarm` — DC overloads a branch AC passes, and misses nothing;
      - `:mixed` — both of the last two at once.
  - `reactive`, `real` — the miss on each branch, split in two (Hurdle 13.3), pu on
    `S_base`, in model branch order. With `S = max(|S_from|, |S_to|)` (the end the
    rating binds), `P_ac = max(|P_from|, |P_to|)` and `P_dc = |f_dc|`:
    `reactive = S − P_ac` and `real = P_ac − P_dc`, so `S − P_dc = reactive + real`.
    `reactive ≥ 0` by algebra, end by end, and that is a statement, not a check.
    `real` has no predicted sign: it carries the angle linearisation, the losses
    and the voltage magnitudes, all of which the DC flow drops. The outaged branch
    reads `0.0` in both. **Empty where AC has no flows**: a split, `:voltage`,
    `:no_solution`, or an overload whose residual failed.
  - `base_reactive`, `base_real` — the same split on the intact model.
"""
struct LineScreenComparison
    branches::Vector{Symbol}
    splits::Vector{Bool}
    dc_base_over::Vector{Symbol}
    dc_outcome::Vector{Symbol}
    ac_outcome::Vector{Symbol}
    dc_over::Vector{Vector{Symbol}}
    ac_over::Vector{Vector{Symbol}}
    class::Vector{Symbol}
    reactive::Vector{Vector{Float64}}
    real::Vector{Vector{Float64}}
    base_reactive::Vector{Float64}
    base_real::Vector{Float64}
end

# The two parts of the miss on every branch of `net`: `dc` in model order, `sol` read
# BY BRANCH ID. A branch absent from `sol` (the outaged one) reads 0.0 in both.
function _screen_miss(net::NetworkModel, dc::Vector{Float64}, sol::ACPowerFlow)
    m = length(net.branches)
    reactive = zeros(Float64, m)
    real = zeros(Float64, m)
    for (e, b) in pairs(net.branches)
        j = findfirst(==(b.id), sol.branches)
        j === nothing && continue
        S = max(hypot(sol.flow[j], sol.qflow[j]), hypot(sol.flow_rev[j], sol.qflow_rev[j]))
        P = max(abs(sol.flow[j]), abs(sol.flow_rev[j]))
        reactive[e] = S - P
        real[e] = P - abs(dc[e])
    end
    return reactive, real
end

"""
    compare_line_screens(net, dc::DCLineOutages, ac::ACLineOutages) -> LineScreenComparison

Put the DC and AC line screens of `net` side by side: per outage, both outcomes,
every disagreement classified, and what the DC flow missed on each branch, split
into a reactive part and a real-power part (see [`LineScreenComparison`](@ref)).

**It takes the model** because the DC screen carries flows and no ratings, and an
overload is a flow judged against a rating. The DC flows are judged by the same
comparison the AC solve uses (`_rating_violations`), on their magnitude: a DC flow
may run either way along a branch, and a rating does not care which. Both screens
must be of `net`; their branch lists are checked against it, and a mismatch is
refused.
"""
function compare_line_screens(net::NetworkModel, dc::DCLineOutages, ac::ACLineOutages)
    ids = Symbol[b.id for b in net.branches]
    (dc.base.branches == ids && ac.branches == ids) || throw(ArgumentError(
        "compare_line_screens: the screens are not of this model — branches " *
        "$(dc.base.branches) (DC) and $(ac.branches) (AC) against $ids."))
    dc.splits == ac.splits || throw(ArgumentError(
        "compare_line_screens: the two screens disagree on which branches are " *
        "bridges, so they are not of the same model."))
    m = length(ids)
    judged(flow) = Symbol[ids[e] for e in _rating_violations(net, abs.(flow))]
    dc_outcome = Vector{Symbol}(undef, m)
    dc_over = [Symbol[] for _ in 1:m]
    ac_over = [Symbol[] for _ in 1:m]
    class = Vector{Symbol}(undef, m)
    reactive = [Float64[] for _ in 1:m]
    real = [Float64[] for _ in 1:m]
    for k in 1:m
        if dc.splits[k]
            dc_outcome[k] = class[k] = :splits
            continue
        end
        dc_over[k] = judged(dc.flow[k])
        dc_outcome[k] = isempty(dc_over[k]) ? :secure : :overload
        append!(ac_over[k], (d.id for d in ac.over[k] if d.kind === :branch))
        sol = ac.solution[k]
        sol === nothing || ((reactive[k], real[k]) = _screen_miss(net, dc.flow[k], sol))
        o = ac.outcome[k]
        if o === :voltage || o === :no_solution || any(d -> d.kind !== :branch, ac.over[k])
            class[k] = :dc_blind
            continue
        end
        missed = setdiff(ac_over[k], dc_over[k])
        false_alarm = setdiff(dc_over[k], ac_over[k])
        class[k] = isempty(missed) ? (isempty(false_alarm) ? :agree : :dc_false_alarm) :
                   (isempty(false_alarm) ? :dc_missed : :mixed)
    end
    base_reactive, base_real = _screen_miss(net, dc.base.flow, ac.base)
    return LineScreenComparison(ids, copy(dc.splits), judged(dc.base.flow), dc_outcome,
                                copy(ac.outcome), dc_over, ac_over, class, reactive,
                                real, base_reactive, base_real)
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: generator outages in the DC screen, the lost power shared by droop and
# damping (m8-context.md D2, D7).
#
# WHO PICKS UP A LOST GENERATOR is read off `swing_vertex!`, not chosen. At a settled
# frequency deviation `Δω` every remaining machine `i` produces, on top of its
# schedule,
#
#     pickupᵢ = min(−Δω·(1/R)ᵢ, headroomᵢ) − Δω·Dᵢ,
#
# because the rotor line carries `−D·ω` and the governor state carries `−ω/R`, and
# the saturation acts on the GOVERNOR state only. So the cap is on the droop term and
# never on the damping term: a damped machine whose governor is at its headroom
# settles ABOVE its `Pmax`, by `−Δω·D`, because that is what the dynamic tier does.
# A grid-forming inverter's droop law settles the same way with gain `1/K_p` and no
# cap (the swing tier gives it no power limit); a grid-following one holds its `P`.
#
# THE SOLVE IS EXACT. With `x = −Δω` the total pickup `T(x) = Σ min(x·gᵢ, hᵢ) + x·Σd`
# is piecewise linear and never decreasing, bending where a governor reaches its
# headroom (`x = hᵢ/gᵢ`). Walking those bends finds `T(x) = P_lost` with no
# root-finder and no tolerance, and it decides the two refusals the same way: nothing
# left responds to frequency, or no damping is left once every governor is capped
# short of the loss. With any damping present a steady state always exists, however
# large the loss, and the screen reports the large `Δω` rather than refusing.
# ─────────────────────────────────────────────────────────────────────────────

# Every element that can answer a frequency deviation, on the SYSTEM base, in the
# order: machines (model order), then grid-forming inverters (model order). The
# machine weights come from `machine_arrays` and the inverter gain from
# `_inverter_arrays`, the one place each per-unit conversion lives (D2): never
# rebuilt from `Machine.R` or `Inverter.K_p` beside them.
function _responders(net::NetworkModel)
    ma = machine_arrays(net)
    ia = _inverter_arrays(net)
    ids = vcat(Symbol[m.id for m in net.machines], ia.id)
    bus = vcat(ma.bus, ia.bus)
    g = vcat(ma.invR, inv.(ia.K_p))
    d = vcat(ma.D, zeros(length(ia.id)))
    h = vcat(ma.headroom, fill(Inf, length(ia.id)))
    P = vcat(ma.Pm, ia.P)
    return (; ids, bus, g, d, h, P, n_machines = length(net.machines))
end

# The settled pickup of every element marked `alive`, for a loss of `P_lost` pu.
# Returns `(status, Δω, pickup, capped)`; `status` is `:shared`, `:no_response` or
# `:reserve_exhausted`, and the last two carry `Δω = NaN` and zero pickups.
function _pickup_solve(g::Vector{Float64}, d::Vector{Float64}, h::Vector{Float64},
                       alive::AbstractVector{Bool}, P_lost::Float64)
    n = length(g)
    pickup = zeros(Float64, n)
    capped = falses(n)
    P_lost == 0.0 && return (:shared, 0.0, pickup, capped)
    Σd = sum(d[i] for i in 1:n if alive[i]; init = 0.0)
    Σg = sum(g[i] for i in 1:n if alive[i]; init = 0.0)
    Σg + Σd > 0.0 || return (:no_response, NaN, pickup, capped)
    if P_lost < 0.0
        # Frequency RISES and every governor commands less. There is no down-floor
        # in the swing tier (its header says so), so nothing caps on the way up.
        Δω = -P_lost / (Σg + Σd)
        for i in 1:n
            alive[i] && (pickup[i] = -Δω * (g[i] + d[i]))
        end
        return (:shared, Δω, pickup, capped)
    end
    # The bends, in order. A governor with zero headroom bends at x = 0: capped from
    # the start. Governor-free elements (g = 0) never bend.
    T(x) = sum(min(x * g[i], h[i]) + x * d[i] for i in 1:n if alive[i]; init = 0.0)
    bends = sort!([h[i] / g[i] for i in 1:n if alive[i] && g[i] > 0.0 && isfinite(h[i])])
    x_lo = 0.0
    for xb in bends
        T(xb) >= P_lost && break    # the answer lies on the segment ending here
        x_lo = xb
    end
    # On the segment starting at x_lo the slope is the damping plus every governor
    # not yet at its headroom there. Recomputed from the definition, never
    # accumulated across bends.
    slope = Σd + sum(g[i] for i in 1:n if alive[i] && g[i] > 0.0 && x_lo < h[i] / g[i];
                     init = 0.0)
    slope > 0.0 || return (:reserve_exhausted, NaN, pickup, capped)
    x = x_lo + (P_lost - T(x_lo)) / slope
    for i in 1:n
        alive[i] || continue
        droop = x * g[i]
        capped[i] = g[i] > 0.0 && droop >= h[i]
        pickup[i] = min(droop, h[i]) + x * d[i]
    end
    return (:shared, -x, pickup, capped)
end

"""
    pickup_shares(net::NetworkModel, lost::Symbol) -> NamedTuple

Who makes up the power of machine `lost` once frequency has settled, and at what
frequency (`m8-context.md` D2): each remaining machine picks up
`min(−Δω/Rᵢ, headroomᵢ) − Δω·Dᵢ` and each grid-forming inverter `−Δω/K_pᵢ`, all on
the system base, with `Δω` the one deviation at which the pickups cover the loss.

Returns `(; Δω, responders, pickup, capped)`:

  - `Δω` — the settled speed deviation, pu (times `f0` for Hz). Negative after losing
    a generator; positive after losing a negative-`P0` machine (a load).
  - `responders` — machine ids in model order, then grid-forming inverter ids.
  - `pickup` — pu on `S_base`, the change in each one's output, in that order. The
    lost machine's entry is `0.0`, and the entries sum to its `P0/S_base`.
  - `capped` — `true` where the governor sits at its headroom. A capped machine with
    damping still settles above its `Pmax`, by `−Δω·D`, as the swing tier does.

**Two refusals, by name, and only two.** Nothing left responds to frequency (every
remaining `1/R`, `D` and `1/K_p` is zero); or no damping is left and every governor
is capped before the loss is covered. With any damping present a steady state always
exists, and a huge loss gives a huge `Δω`, reported rather than refused.

When no damping is left and the headroom left exactly equals the loss, every `Δω`
past the last governor's cap balances; the smallest `|Δω|` is returned.

Losing a negative-`P0` machine raises frequency, and every governor commands less
with no floor, as in the swing tier.
"""
function pickup_shares(net::NetworkModel, lost::Symbol)
    r = _responders(net)
    k = findfirst(==(lost), view(r.ids, 1:r.n_machines))
    k === nothing && throw(ArgumentError(
        "pickup_shares: :$lost is not a machine of this model (machines: " *
        "$(join(r.ids[1:r.n_machines], ", ")))."))
    alive = trues(length(r.ids))
    alive[k] = false
    status, Δω, pickup, capped = _pickup_solve(r.g, r.d, r.h, alive, r.P[k])
    status === :no_response && throw(ArgumentError(
        "pickup_shares: nothing left responds to frequency after losing :$lost — every " *
        "remaining droop gain 1/R, damping D and inverter gain 1/K_p is zero, so no " *
        "frequency settles the $(r.P[k] * net.S_base) MW it leaves (m8-context.md D2)."))
    status === :reserve_exhausted && throw(ArgumentError(
        "pickup_shares: after losing :$lost every remaining governor is at its headroom " *
        "before the $(r.P[k] * net.S_base) MW is covered, and no damping is left to " *
        "carry the rest, so frequency never settles (m8-context.md D2)."))
    return (; Δω, responders = r.ids, pickup, capped = collect(capped))
end

"""
    DCGeneratorOutages

Every single-machine outage of a model, screened with the linear power flow, the
lost power shared by droop and damping ([`pickup_shares`](@ref)'s rule).

  - `base` — the intact model's [`DCPowerFlow`](@ref)
  - `machines` — the machine ids screened, in model order; every outage vector below
    is in this order
  - `responders` — machine ids then grid-forming inverter ids: the order of each
    `pickup` and `capped` vector
  - `outcome` — `:shared`, or one of the two refusals by name: `:no_response`
    (nothing left responds to frequency) and `:reserve_exhausted` (no damping left,
    every governor capped short of the loss). A screen reports a refusal; it does
    not throw (`m8-context.md` D3).
  - `Δω` — the settled speed deviation, pu; `NaN` for a refusal
  - `pickup`, `capped` — per outage, as `pickup_shares` returns them; all zero and
    `false` for a refusal
  - `flow` — per outage, the post-outage active power on every branch, pu, in the
    model's orientation; empty for a refusal

The machine's bus stays in the network: losing a generator does not remove a
substation, so every branch still carries what passes through it.
"""
struct DCGeneratorOutages
    base::DCPowerFlow
    machines::Vector{Symbol}
    responders::Vector{Symbol}
    outcome::Vector{Symbol}
    Δω::Vector{Float64}
    pickup::Vector{Vector{Float64}}
    capped::Vector{Vector{Bool}}
    flow::Vector{Vector{Float64}}
end

"""
    dc_generator_outages(net::NetworkModel) -> DCGeneratorOutages

Screen every single-machine outage of `net` with the linear (DC) power flow. The
lost power is shared by the remaining machines' droop and damping and the
grid-forming inverters' droop ([`pickup_shares`](@ref)), and the flows follow from
the new injections with one solve against the same sparse factorisation
[`dc_line_outages`](@ref) uses: `B` does not change, because the bus stays.

The result is **the same numbers as rebuilding the model without the machine, adding
each pickup to its responder's schedule and calling [`dc_powerflow`](@ref)**, to
round-off. The reference bus is a gauge here as in the line screen, so losing the
slack bus's own machine is screened like any other: the pickups rebalance every
injection and nothing is left for the reference to absorb.

Every machine is screened, a negative-`P0` one too (losing it raises frequency).
Inverter outages are not screened. An outage with no steady state is reported as a
refusal in `outcome`, never thrown.
"""
function dc_generator_outages(net::NetworkModel)
    base = dc_powerflow(net)
    topo = branch_topology(net)
    n, m = length(net.buses), length(topo.src)
    r = _responders(net)
    nm = r.n_machines
    outcome = Vector{Symbol}(undef, nm)
    Δω = fill(NaN, nm)
    pickup = Vector{Vector{Float64}}(undef, nm)
    capped = Vector{Vector{Bool}}(undef, nm)
    flow = Vector{Vector{Float64}}(undef, nm)
    # The same susceptances and the same reduced matrix as the line screen (D4).
    b = inv.(topo.X)
    Br, keep = _dc_reduced_susceptance(net, b)
    F = n > 1 ? LinearAlgebra.cholesky(LinearAlgebra.Symmetric(Br)) : nothing
    θ = zeros(Float64, n)
    alive = trues(length(r.ids))
    for k in 1:nm
        alive[k] = false
        status, dω, pk, cp = _pickup_solve(r.g, r.d, r.h, alive, r.P[k])
        alive[k] = true
        outcome[k] = status
        pickup[k] = pk
        capped[k] = collect(cp)
        if status !== :shared
            flow[k] = Float64[]
            continue
        end
        Δω[k] = dω
        # The machine leaves its bus; every responder adds its pickup at its own.
        P = copy(base.P)
        P[r.bus[k]] -= r.P[k]
        for i in eachindex(pk)
            P[r.bus[i]] += pk[i]
        end
        F === nothing || (θ[keep] = F \ P[keep])
        flow[k] = Float64[b[e] * (θ[topo.src[e]] - θ[topo.dst[e]]) for e in 1:m]
    end
    return DCGeneratorOutages(base, Symbol[mc.id for mc in net.machines], r.ids,
                              outcome, Δω, pickup, capped, flow)
end
