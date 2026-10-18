# M10 — double-outage screening (docs/plans/m10-plan.md, m10-context.md).
#
# Step 1: the two-line DC factors. Losing branches `k` and `l` together is a rank-two
# change to `B`, and the rank-two update written in flows is
#
#     f′_e = f_e + [P_ek  P_el] · M⁻¹ · [f_k; f_l],
#     M    = [1 − P_kk   −P_kl;  −P_lk   1 − P_ll],
#
# where `P_ek` is the flow on `e` per unit transfer across `k` (M8's `PTDF_mk`). An
# IDENTITY of the DC power flow, exactly as M8's single-outage factor is (Hurdle 18.1),
# so the check is agreement with rebuilding the model without both and solving again.
#
# `M` IS NOT SYMMETRIC. `P_kl = b_k·a_kᵀB⁻¹a_l` and `P_lk = b_l·a_lᵀB⁻¹a_k`, so they are
# equal only when the two susceptances are. A transposed `M` is therefore invisible on
# a pair of equal reactances, and the checks include unequal ones.
#
# ADDING TWO SINGLE-OUTAGE FACTORS IS `M` REPLACED BY ITS DIAGONAL (Hurdle 18.2): it
# ignores that each loss moves where the other's flow goes, and is exact only when
# `P_kl = P_lk = 0`.
#
# WHAT IS HELD (`m10-context.md` D7). M8 D4 refuses to form the PTDF, branches × buses.
# The pair code keeps a branches × branches table instead — column `k` is every
# branch's flow per unit transfer across `k`, built from one solve against the single
# factorisation, the solve's bus angles dropped as in M8. Every pair reads two columns
# and four entries of it. It is the size of M8's own outage table (`DCLineOutages.flow`)
# and smaller than this one's.
#
# A PAIR THAT CUTS THE GRID IS FOUND FROM THE GRAPH, NEVER FROM `det M` (Hurdle 18.3).
# At a cut `det M` is zero in exact arithmetic and round-off of either sign in floating
# point, M8 Hurdle 14 one dimension up — and a pair can cut the grid while neither line
# is a bridge (case9's ring: 15 of its 36 pairs). Nothing is thresholded, so a
# nearly-cut pair still gets an answer; it costs accuracy, about `eps/|det M|` relative.

"""
    DCLinePairOutages

Every simultaneous outage of two branches of a model, screened with the linear power
flow.

  - `base` — the intact model's [`DCPowerFlow`](@ref); `base.branches` names the
    branches, and the indices in `pairs` and every flow vector are in that order
  - `pairs` — `(k, l)` with `k < l`, every unordered pair of branches, in
    lexicographic order
  - `splits` — `true` where losing both branches splits the grid (a **cut**, found from
    the graph). No flows are computed for a cut here: who serves each piece is
    decided per piece, not by this table.
  - `det` — `det M` for every pair, **cuts included**: at a cut it is round-off of
    either sign, kept visible as what it is rather than as an exact zero. Small but
    not round-off on a nearly-cut pair, where it sets the accuracy (`eps/|det M|`).
  - `flow` — for each pair, the post-outage active power on **every** branch, pu on
    `S_base`, in the model's own orientation; entries `k` and `l` are exactly `0.0`.
    Empty for a cut.
"""
struct DCLinePairOutages
    base::DCPowerFlow
    pairs::Vector{Tuple{Int,Int}}
    splits::Vector{Bool}
    det::Vector{Float64}
    flow::Vector{Vector{Float64}}
end

# Column `k`: every branch's flow per unit transfer across branch `k` (+1 at its `from`
# end, −1 at its `to` end), from one solve against ONE sparse Cholesky factorisation —
# the operations of `dc_line_outages`'s loop in the same order, so `1 − P[k, k]` is
# its `margin[k]` bit for bit (a test holds the two copies together). The solve's bus
# angles are dropped after each column; only branches × branches is kept (D7).
function _dc_transfer_factors(net::NetworkModel, b::Vector{Float64})
    topo = branch_topology(net)
    n, m = length(net.buses), length(topo.src)
    P = zeros(Float64, m, m)
    m == 0 && return P
    Br, keep = _dc_reduced_susceptance(net, b)
    F = LinearAlgebra.cholesky(LinearAlgebra.Symmetric(Br))
    slot = zeros(Int, n)                   # vertex → row of `Br`; 0 for the reference
    slot[keep] = 1:length(keep)
    rhs = zeros(Float64, length(keep))
    φ = zeros(Float64, n)                  # the reference bus's entry stays 0.0
    for k in 1:m
        fill!(rhs, 0.0)
        i, j = topo.src[k], topo.dst[k]
        slot[i] > 0 && (rhs[slot[i]] += 1.0)
        slot[j] > 0 && (rhs[slot[j]] -= 1.0)
        φ[keep] = F \ rhs
        for e in 1:m
            P[e, k] = b[e] * (φ[topo.src[e]] - φ[topo.dst[e]])
        end
    end
    return P
end

# `true` per pair where the graph with both branches removed is disconnected — the
# same graph and the same test `NetworkModel` applies when it refuses a model, so the
# cut set IS the set of pairs whose rebuild is refused. (Parallel branches are refused
# by `NetworkModel`, so the simple graph loses nothing.)
function _pair_cut_mask(net::NetworkModel, pairs::Vector{Tuple{Int,Int}})
    topo = branch_topology(net)
    n = length(net.buses)
    return map(pairs) do (k, l)
        g = Graphs.SimpleGraph(n)
        for e in eachindex(topo.src)
            (e == k || e == l) && continue
            Graphs.add_edge!(g, topo.src[e], topo.dst[e])
        end
        !Graphs.is_connected(g)
    end
end

"""
    dc_line_pair_outages(net::NetworkModel) -> DCLinePairOutages

Screen every simultaneous outage of two branches of `net` with the linear (DC) power
flow, through the two-line factors: one sparse factorisation, one solve per branch,
then a 2 × 2 solve per pair.

The result is **the same numbers as rebuilding the model without both branches and
calling [`dc_powerflow`](@ref)** on it, to round-off, without building a model per
pair. A pair whose loss would split the grid is reported in `splits` and gets no flows;
rebuilding refuses those same pairs, because `NetworkModel` refuses a disconnected
model. A pair can split the grid while neither of its branches does alone.

It is **not** the sum of the two single outages of [`dc_line_outages`](@ref): that
shortcut ignores that each loss changes where the other's flow goes, and is exact only
when a transfer across either branch puts no flow on the other.

The approximation is `dc_powerflow`'s: `R` ignored, every `|V| = 1`, no reactive power.
"""
function dc_line_pair_outages(net::NetworkModel)
    base = dc_powerflow(net)
    topo = branch_topology(net)
    m = length(topo.src)
    f = base.flow
    # ONE susceptance vector, read by the matrix AND by the flow weights (M8 step 2's
    # rule: two reads could disagree, and a ring cannot see that).
    P = _dc_transfer_factors(net, inv.(topo.X))
    pairs = [(k, l) for k in 1:m for l in (k + 1):m]
    splits = _pair_cut_mask(net, pairs)
    det = Vector{Float64}(undef, length(pairs))
    flow = Vector{Vector{Float64}}(undef, length(pairs))
    for (p, (k, l)) in enumerate(pairs)
        # M = [a c; d e], NOT symmetric: c is the flow on k per transfer across l.
        a, c = 1.0 - P[k, k], -P[k, l]
        d, e = -P[l, k], 1.0 - P[l, l]
        det[p] = a * e - c * d
        if splits[p]
            flow[p] = Float64[]            # never divided by `det[p]`
            continue
        end
        xk = (e * f[k] - c * f[l]) / det[p]
        xl = (a * f[l] - d * f[k]) / det[p]
        post = Vector{Float64}(undef, m)
        for j in 1:m
            post[j] = f[j] + P[j, k] * xk + P[j, l] * xl
        end
        # Exactly zero, not round-off: both branches are gone.
        post[k] = 0.0
        post[l] = 0.0
        flow[p] = post
    end
    return DCLinePairOutages(base, pairs, splits, det, flow)
end
