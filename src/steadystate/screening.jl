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
