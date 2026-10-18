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
    # ONE susceptance vector, read by the matrix AND by the flow weights (M8 step 2's
    # rule: two reads could disagree, and a ring cannot see that).
    P = _dc_transfer_factors(net, inv.(topo.X))
    return _dc_line_pairs(net, base, P)
end

# The pair loop itself, on a base solve and a factor table already made, so step 2's
# screen reads the same numbers rather than a second copy of them.
function _dc_line_pairs(net::NetworkModel, base::DCPowerFlow, P::Matrix{Float64})
    m = length(base.flow)
    f = base.flow
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

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: every pair of elements in DC — two lines, two machines, one of each — and a
# grid split by the pair answered piece by piece (Hurdles 18.4, 19.1–19.4).
#
# THE ELEMENTS ARE M8's ROWS: every branch in model order, then every machine. A pair
# is unordered (`m10-context.md` D4); an ordered pair needs a rule between the two
# losses, and that is step 5's.
#
# A SPLIT GRID KEEPS RUNNING AS SEVERAL GRIDS (Hurdle 19). The pieces come from the
# graph with the pair's branches removed, and each is one of four things (D4):
#   - LIVE: it holds a source — a machine with `P0 ≥ 0` that the pair did not take, or
#     a grid-forming inverter — and a load. Its imbalance is shared by ITS OWN units
#     alone, by M8's rule (`_pickup_solve` with the piece as the `alive` mask), so each
#     live piece settles at its own frequency, and one with a surplus rises.
#   - SOURCES LOST: a source and no load. What it produced is lost to the rest
#     (M8 D9, generalised). Its machines are not shared into.
#   - LOAD LOST: no source. Its load is lost, and any grid-following inverter with it:
#     one has nothing to follow there (D4).
#   - EMPTY: nothing at all.
# A machine with `P0 < 0` is a LOAD here, never a source (D6.3): that is how the swing
# tier's fixtures write loads, and as a source a stranded load-machine would make its
# piece live.
#
# A LIVE PIECE'S IMBALANCE IS READ FROM THE BASE CASE: the schedule of the machines the
# pair took out of it, plus the power it imported across the pair's branches (base DC
# flows; an export counts negative). Read that way a pair that leaves the grid whole
# has an imbalance of EXACTLY the lost schedule — `0.0` for two lines, the two
# machines' sum for two machines — and a split charges each piece with what crossed
# the cut, which is what each side loses. Summing a piece's injections would give the
# same number to the base solve's round-off, and would also share out whatever the
# reference absorbed from a schedule that balances only to the model's guard.
#
# THE FLOWS. A pair that leaves the grid whole reuses M8's one factorisation: two lines
# are step 1's rank-two update; two machines are new injections on the unchanged `B`;
# a line and a machine are the machine's injections first and then the line's
# single-outage factor applied to those flows (a factor is a property of the network,
# not of the injections). A split pair gets one fresh sparse factorisation of the
# network without its branches, with one reference per piece. A dead piece carries
# nothing; a live piece with no settled state carries `NaN`.
# ─────────────────────────────────────────────────────────────────────────────

"""
    DCPiece

One piece of the grid a pair outage leaves behind ([`DCPairOutages`](@ref)).

  - `buses` — its bus ids, in vertex order
  - `kind` — `:live` (a source and a load), `:sources_lost` (a source and no load: what
    it produced is lost), `:load_lost` (no source: its load is lost, and any
    grid-following inverter in it), `:empty` (nothing in it). A source is a machine
    with `P0 ≥ 0` that the pair did not take, or a grid-forming inverter; a load is a
    `Load` or a machine with `P0 < 0`.
  - `outcome` — for a live piece, M8's rule run inside it: `:shared`, `:no_response`
    or `:reserve_exhausted`; for any other piece, its `kind`
  - `imbalance` — live: what its own units must make up, pu on `S_base` (negative: a
    surplus, and frequency rises); `0.0` otherwise
  - `Δω` — the settled speed deviation of a live piece that shared, pu; `NaN` otherwise
  - `sources_lost`, `load_lost` — what a dead piece takes with it, pu, both `≥ 0`: the
    schedule of its machines and inverters, and its load (a `P0 < 0` machine's
    `|P0|` included). `0.0` for a live piece.
"""
struct DCPiece
    buses::Vector{Symbol}
    kind::Symbol
    outcome::Symbol
    imbalance::Float64
    Δω::Float64
    sources_lost::Float64
    load_lost::Float64
end

"""
    DCPairOutages

Every simultaneous outage of two elements of a model — two branches, two machines or
one of each — screened with the linear power flow, a split grid answered per piece.

  - `base` — the intact model's [`DCPowerFlow`](@ref)
  - `kind`, `id` — the elements: `:branch` then `:machine`, in model order (M8's rows)
  - `pairs` — `(i, j)` with `i < j`, indices into `kind`/`id`, lexicographic
  - `same_as` — the machine whose single outage the pair IS, or `:none`: a bridge that
    cuts off exactly that lone machine, paired with the machine itself
    (`m10-context.md` D4; [`lone_source_bridges`](@ref))
  - `splits` — `true` where the pair's branches split the grid
  - `responders` — machine ids then grid-forming inverter ids: the order of `pickup`
    and `capped`
  - `pieces` — per pair, every piece left, ordered by first bus ([`DCPiece`](@ref));
    one piece when the grid stays whole
  - `pickup`, `capped` — per pair, each responder's change in output, pu, and whether
    its governor sits at its headroom; zero and `false` for a lost machine and for
    anything outside a live piece that shared
  - `flow` — per pair, the post-outage active power on every branch, pu, model
    orientation: `0.0` on the pair's branches and inside a dead piece, `NaN` inside a
    live piece with no settled state
"""
struct DCPairOutages
    base::DCPowerFlow
    kind::Vector{Symbol}
    id::Vector{Symbol}
    pairs::Vector{Tuple{Int,Int}}
    same_as::Vector{Symbol}
    splits::Vector{Bool}
    responders::Vector{Symbol}
    pieces::Vector{Vector{DCPiece}}
    pickup::Vector{Vector{Float64}}
    capped::Vector{Vector{Bool}}
    flow::Vector{Vector{Float64}}
end

# The pieces left once the branches `out` are removed: a piece index per vertex, the
# pieces numbered by their first vertex.
function _pair_pieces(n::Int, topo, out::Vector{Int})
    g = Graphs.SimpleGraph(n)
    for e in eachindex(topo.src)
        e in out && continue
        Graphs.add_edge!(g, topo.src[e], topo.dst[e])
    end
    comps = sort!(Graphs.connected_components(g); by = minimum)
    piece = zeros(Int, n)
    for (c, vs) in pairs(comps)
        piece[vs] .= c
    end
    return piece, length(comps)
end

"""
    dc_pair_outages(net::NetworkModel) -> DCPairOutages

Screen every simultaneous outage of two elements of `net` — every pair of branches,
of machines, and of one of each — with the linear (DC) power flow
([`DCPairOutages`](@ref)).

A pair that leaves the grid whole is M8's screens on a pair: lost power shared by
droop and damping ([`pickup_shares`](@ref)'s rule), two lines by the two-line factors
of [`dc_line_pair_outages`](@ref). A pair that splits it is answered **piece by
piece**: each piece with a source and a load shares its own imbalance among its own
units and settles at its own frequency; a piece with no load loses its sources, one
with no source its load ([`DCPiece`](@ref)). Grid-forming inverters share; grid-
following ones hold their power, and are lost with a piece that has no source.

The result is **the same numbers as rebuilding each live piece as its own model, with
every unit at its schedule plus its pickup, and calling [`dc_powerflow`](@ref)** on
it, to round-off. Every outcome is reported, never thrown (`m8-context.md` D3).

The approximation is `dc_powerflow`'s: `R` ignored, every `|V| = 1`, no reactive power.
"""
function dc_pair_outages(net::NetworkModel)
    base = dc_powerflow(net)
    topo = branch_topology(net)
    n, m = length(net.buses), length(topo.src)
    f = base.flow
    b = inv.(topo.X)
    P = _dc_transfer_factors(net, b)
    lines = _dc_line_pairs(net, base, P)
    line_pair = Dict(kl => p for (p, kl) in pairs(lines.pairs))
    r = _responders(net)
    nm = r.n_machines
    la, fa = load_arrays(net), _gfl_arrays(net)
    is_gfm = [i > nm for i in eachindex(r.ids)]
    N = m + nm
    kind = [fill(:branch, m); fill(:machine, nm)]
    id = [base.branches; Symbol[mc.id for mc in net.machines]]
    elems = [(i, j) for i in 1:N for j in (i + 1):N]
    src = lone_source_bridges(net)
    # Branches come first, so a mixed pair is always (branch, machine).
    same_as = Symbol[(i <= m && j > m && src.machine[i] === id[j]) ? id[j] : :none
                     for (i, j) in elems]
    Br, keep = _dc_reduced_susceptance(net, b)
    F = n > 1 ? LinearAlgebra.cholesky(LinearAlgebra.Symmetric(Br)) : nothing
    v_ref = net.bus_index[net.slack]
    busid = Symbol[bs.id for bs in net.buses]
    np = length(elems)
    splits = Vector{Bool}(undef, np)
    pieces = Vector{Vector{DCPiece}}(undef, np)
    pickup = Vector{Vector{Float64}}(undef, np)
    capped = Vector{Vector{Bool}}(undef, np)
    flow = Vector{Vector{Float64}}(undef, np)
    for (p, (i, j)) in pairs(elems)
        out = Int[e for e in (i, j) if e <= m]
        lost = falses(nm)
        for e in (i, j)
            e > m && (lost[e - m] = true)
        end
        piece, npieces = _pair_pieces(n, topo, out)
        splits[p] = npieces > 1
        # Each piece's imbalance: the lost schedule inside it, plus what it imported
        # across the pair's branches in the base case.
        imb = zeros(Float64, npieces)
        for k in 1:nm
            lost[k] && (imb[piece[r.bus[k]]] += r.P[k])
        end
        for e in out
            ps, pd = piece[topo.src[e]], piece[topo.dst[e]]
            ps == pd && continue
            imb[pd] += f[e]
            imb[ps] -= f[e]
        end
        pk = zeros(Float64, length(r.ids))
        cp = falses(length(r.ids))
        ps_out = Vector{DCPiece}(undef, npieces)
        settled = falses(npieces)
        alive = falses(length(r.ids))
        for c in 1:npieces
            has_src = has_load = false
            sources = load = 0.0
            for k in 1:nm
                (piece[r.bus[k]] == c && !lost[k]) || continue
                if r.P[k] >= 0.0
                    has_src = true
                    sources += r.P[k]
                else
                    has_load = true
                    load -= r.P[k]
                end
            end
            for q in (nm + 1):length(r.ids)
                piece[r.bus[q]] == c || continue
                has_src = true
                sources += r.P[q]
            end
            for q in eachindex(la.bus)
                piece[la.bus[q]] == c || continue
                has_load = true
                load += la.P[q]
            end
            gfl = 0.0
            for q in eachindex(fa.bus)
                piece[fa.bus[q]] == c && (gfl += fa.P[q])
            end
            bs = busid[piece .== c]
            if has_src && has_load
                for q in eachindex(r.ids)
                    alive[q] = piece[r.bus[q]] == c && !(q <= nm && lost[q])
                end
                status, dω, pq, cq = _pickup_solve(r.g, r.d, r.h, alive, imb[c])
                if status === :shared
                    settled[c] = true
                    for q in eachindex(r.ids)
                        alive[q] || continue
                        pk[q] = pq[q]
                        cp[q] = cq[q]
                    end
                end
                ps_out[c] = DCPiece(bs, :live, status, imb[c], status === :shared ? dω : NaN,
                                    0.0, 0.0)
            elseif has_src
                ps_out[c] = DCPiece(bs, :sources_lost, :sources_lost, 0.0, NaN,
                                    sources + gfl, 0.0)
            elseif has_load || gfl != 0.0
                ps_out[c] = DCPiece(bs, :load_lost, :load_lost, 0.0, NaN, gfl, load)
            else
                ps_out[c] = DCPiece(bs, :empty, :empty, 0.0, NaN, 0.0, 0.0)
            end
        end
        pieces[p], pickup[p], capped[p] = ps_out, pk, collect(cp)
        live = Bool[ps_out[c].kind === :live for c in 1:npieces]
        if !splits[p] && settled[1] && length(out) == 2
            flow[p] = copy(lines.flow[line_pair[(out[1], out[2])]])
            continue
        end
        # The post-outage injections: the base, less every lost machine, plus every
        # pickup; nothing in a dead piece or in one that did not settle.
        Pinj = copy(base.P)
        for k in 1:nm
            lost[k] && (Pinj[r.bus[k]] -= r.P[k])
        end
        for q in eachindex(r.ids)
            Pinj[r.bus[q]] += pk[q]
        end
        for v in 1:n
            settled[piece[v]] || (Pinj[v] = 0.0)
        end
        post = zeros(Float64, m)
        if !splits[p]
            if settled[1]
                θ = zeros(Float64, n)
                F === nothing || (θ[keep] = F \ Pinj[keep])
                for e in 1:m
                    post[e] = b[e] * (θ[topo.src[e]] - θ[topo.dst[e]])
                end
                if length(out) == 1
                    # The line's single-outage factor, applied to these flows.
                    k = out[1]
                    x = post[k] / (1.0 - P[k, k])
                    for e in 1:m
                        post[e] += P[e, k] * x
                    end
                    post[k] = 0.0
                end
            elseif live[1]
                fill!(post, NaN)
            end
            # (A whole grid with no load or no source is dead: it carries nothing.)
            flow[p] = post
            continue
        end
        # A split: one reference per piece — the model's own where it lies in the
        # piece, else the piece's first bus.
        refs = [any(==(v_ref), findall(==(c), piece)) ? v_ref : findfirst(==(c), piece)
                for c in 1:npieces]
        kv = [v for v in 1:n if !(v in refs)]
        keepb = [e for e in 1:m if !(e in out)]
        θ = zeros(Float64, n)
        if !isempty(kv)
            Bs = _dc_susceptance(n, topo.src[keepb], topo.dst[keepb], b[keepb])[kv, kv]
            θ[kv] = LinearAlgebra.cholesky(LinearAlgebra.Symmetric(Bs)) \ Pinj[kv]
        end
        for e in keepb
            c = piece[topo.src[e]]
            post[e] = settled[c] ? b[e] * (θ[topo.src[e]] - θ[topo.dst[e]]) :
                      live[c] ? NaN : 0.0
        end
        flow[p] = post
    end
    return DCPairOutages(base, kind, id, elems, same_as, splits, r.ids, pieces, pickup,
                         capped, flow)
end
