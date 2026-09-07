# M6 step 2 — the linear ("DC") power flow.
#
# THE FIRST MATRIX THIS REPO ASSEMBLES ITSELF. Every sparse structure to date has
# belonged to `NetworkDynamics`; this is the first place `CLAUDE.md`'s "sparse from
# day one, never a dense Y-bus" binds our own code, which is why the sparsity here
# is CHECKED (`nnz` against what the branch list predicts) rather than trusted.
#
# The classical approximation, in the four assumptions it is made of:
#
#   1. every bus voltage magnitude is exactly 1.0 pu;
#   2. angle differences are small, so `sin(θᵢ − θⱼ) ≈ θᵢ − θⱼ`;
#   3. branches are lossless — `R` is IGNORED, not required to be zero (see below);
#   4. reactive power is not modelled at all.
#
# What survives is one linear system, `B·θ = P`, with `B` the branch susceptance
# matrix. It is nearly free on the reactance-only branches the repo already has,
# and that is why it lands before the nonlinear solve: it is a second opinion for
# step 3 at almost no cost.
#
# WHY THIS DOES NOT CALL `_assert_lossless_branches`. Every engine in `src/` does,
# because a lossy model run at a lossless tier is a *different network* than its
# data describes. Here it is not: ignoring `R` is the stated approximation, named
# in the docstring, and the AC solve in step 3 reads `R` on the same model. A DC
# solve that refused a lossy case would refuse exactly the cases step 3 exists for.
#
# WHY THERE IS NO SLACK-PICKUP READ-OUT. `NetworkModel` rejects a model whose
# scheduled injections do not sum to zero, and a lossless DC solve conserves that
# sum exactly, so the slack's pickup here is identically zero — an assertion with
# no content. Losses have a home: step 3's `R ≠ 0` identity, where the slack picks
# up the summed branch losses and the check is an identity rather than a tolerance.

"""
    bus_injections(net::NetworkModel) -> Vector{Float64}

The **net scheduled active injection at every bus**, in vertex order, per unit on
`net.S_base` — machines minus load, positive into the network.

The two halves come from `machine_arrays` and `load_arrays` rather than from
`Machine.P0` / `Load.P0` directly, because those are the one place the per-unit
conversion happens and a second copy of it is the mistake that keeps recurring
(`machine_arrays`' machine-base weight in particular).

A load's `P` is what it draws **at `V = 1`**, and the DC approximation holds every
magnitude at exactly 1, so the ZIP shares do not appear here: at unit voltage the
constant-impedance, constant-current and constant-power shares all draw `P0`. That
is an exact statement about this approximation, not a simplification of it.

`NetworkModel`'s Σ-balance guard means this vector sums to zero on any model that
can be constructed.
"""
function bus_injections(net::NetworkModel)
    P = zeros(Float64, length(net.buses))
    ma = machine_arrays(net)
    for k in eachindex(ma.bus)
        P[ma.bus[k]] += ma.Pm[k]
    end
    la = load_arrays(net)
    for k in eachindex(la.bus)
        P[la.bus[k]] -= la.P[k]
    end
    return P
end

"""
    _dc_susceptance(net::NetworkModel) -> SparseMatrixCSC{Float64,Int}

The DC susceptance matrix `B`, `n × n` in vertex order: `B[i,i] = Σ 1/X` over the
branches at bus `i`, `B[i,j] = −1/X_ij` for a branch between `i` and `j`.

**Assembled through `sparse(I, J, V, n, n)`**, which sums duplicate `(i,j)` entries
— that is what lets each branch contribute its two diagonal terms independently
without the caller tracking bus degree, and it keeps the stored-entry count exactly
`n + 2m`:

  - `n` diagonal entries, all structurally present because a model with an
    unbranched bus is disconnected and `NetworkModel` rejects those;
  - `2m` off-diagonal entries with no cancellation, because `Branch` rejects a
    self-loop and `NetworkModel` rejects a second branch on a pair already joined,
    so every off-diagonal is a single `−1/X` and never a sum.

Singular by construction (`B · 1 = 0`, angles being relative), which is why the
solve deletes the slack row and column rather than factorising this.
"""
function _dc_susceptance(net::NetworkModel)
    topo = branch_topology(net)
    n = length(net.buses)
    m = length(topo.src)
    rows = Vector{Int}(undef, 4m)
    cols = Vector{Int}(undef, 4m)
    vals = Vector{Float64}(undef, 4m)
    for e in 1:m
        b = inv(topo.X[e])              # X > 0 is enforced by `Branch`
        f, t = topo.src[e], topo.dst[e]
        k = 4e - 3
        rows[k],   cols[k],   vals[k]   = f, f,  b
        rows[k+1], cols[k+1], vals[k+1] = t, t,  b
        rows[k+2], cols[k+2], vals[k+2] = f, t, -b
        rows[k+3], cols[k+3], vals[k+3] = t, f, -b
    end
    return SparseArrays.sparse(rows, cols, vals, n, n)
end

"""
    DCPowerFlow

A solved linear power flow: the answer, detached from the model it came from, so a
caller can hold it, compare two of them, or hand one to the UI.

  - `slack` — the reference bus, whose angle is exactly `0.0`
  - `buses`, `θ` — bus ids in vertex order and their angles in **radians**
  - `P` — the net injections that were solved for, pu on the model's `S_base`
  - `branches`, `from`, `to`, `flow` — branch ids in model order, their own
    orientation, and the active power `from → to` in pu

**Its vectors are handed out live, and the type is treated as immutable by
convention** — the same contract `state_series` has, which returns the recorder's
own channel vectors rather than copies. Field access here is field access. The one
place a copy is made is `branch_power(sol)`, and only so that it matches its
sibling `branch_power(eng::SwingEngine)`, which computes a fresh vector because it
has no stored one to return.

Read it with [`bus_angle`](@ref) and [`branch_power`](@ref). `branch_power` is the
same name the two dynamic tiers answer to, deliberately: `(θᵢ − θⱼ)/X` here,
`K·sin(δᵢ − δⱼ)` at the classical tier and `Re(V·conj(I))` at the detailed one are
the same physical quantity, and M5 step 7 established that writing one quantity out
under several names at several call sites is how its sign gets lost.
"""
struct DCPowerFlow
    slack::Symbol
    buses::Vector{Symbol}
    θ::Vector{Float64}
    P::Vector{Float64}
    branches::Vector{Symbol}
    from::Vector{Symbol}
    to::Vector{Symbol}
    flow::Vector{Float64}
end

"""
    dc_powerflow(net::NetworkModel) -> DCPowerFlow

Solve the linear power flow for `net` at its declared dispatch and declared slack.

**The dispatch is read from the model and nowhere else** — there is no injection
argument. A second way to supply injections would be a second source of truth about
the same fact, which is the shape `m6-context.md` D3 rejects for bus type and
rejects here for the same reason: an override can silently disagree with the
machines and loads actually attached.

The approximation ignores `R`, holds `|V| = 1` everywhere and drops reactive power
entirely; see the notes at the head of this file. A model with `R ≠ 0` is accepted
and gives the lossless answer, which is what a DC power flow *is*.

Bus roles play no part: at this approximation a generator bus and a load bus hold
the same thing (their `P`), and only the slack is distinguished — by having its
angle pinned to zero. `bus_roles` starts mattering in step 3.
"""
function dc_powerflow(net::NetworkModel)
    n = length(net.buses)
    P = bus_injections(net)
    B = _dc_susceptance(net)
    v_slack = net.bus_index[net.slack]          # the constructor guarantees this resolves

    # Delete the slack's row AND column, pinning θ_slack = 0. The remaining
    # (n−1)×(n−1) block is symmetric positive definite on a connected network —
    # which `NetworkModel` guarantees — so it has exactly one solution and the
    # sparse factorisation cannot fall over on a singularity.
    keep = [v for v in 1:n if v != v_slack]
    θ = zeros(Float64, n)
    if n > 1
        θ[keep] = B[keep, keep] \ P[keep]
    end

    topo = branch_topology(net)
    flow = Float64[(θ[topo.src[e]] - θ[topo.dst[e]]) / topo.X[e] for e in eachindex(topo.src)]

    return DCPowerFlow(net.slack,
                       Symbol[b.id for b in net.buses], θ, P,
                       Symbol[b.id for b in net.branches],
                       Symbol[b.from for b in net.branches],
                       Symbol[b.to for b in net.branches],
                       flow)
end

"""
    bus_angle(sol::DCPowerFlow, bus::Symbol) -> Float64

The solved voltage angle at `bus`, in radians, relative to the slack (which is
exactly `0.0`). Throws if the bus is not in the solution — a missing bus is a typo,
the way `load_at` and `bus_role` treat one.
"""
function bus_angle(sol::DCPowerFlow, bus::Symbol)
    v = findfirst(==(bus), sol.buses)
    v === nothing && throw(ArgumentError("DCPowerFlow: no bus :$bus (has $(join(sol.buses, ", ")))."))
    return sol.θ[v]
end

"""
    branch_power(sol::DCPowerFlow, from::Symbol, to::Symbol) -> Float64

Active power flowing **from** bus `from` into the branch joining it to `to`, pu on
the model's `S_base` — `(θ_from − θ_to)/X`.

Same contract as the engines' `branch_power`: the branch is found on the unordered
pair, and **the argument order decides the sign**, so
`branch_power(sol, :A, :B) == -branch_power(sol, :B, :A)`. The
DC branch is lossless, so the far end receives exactly this number.
"""
function branch_power(sol::DCPowerFlow, from::Symbol, to::Symbol)
    for e in eachindex(sol.branches)
        if sol.from[e] === from && sol.to[e] === to
            return sol.flow[e]
        elseif sol.from[e] === to && sol.to[e] === from
            return -sol.flow[e]
        end
    end
    throw(ArgumentError("DCPowerFlow: no branch between :$from and :$to."))
end

"""
    branch_power(sol::DCPowerFlow) -> Vector{Float64}

Every branch's active power in **model branch order**, `from → to`, pu.
"""
branch_power(sol::DCPowerFlow) = copy(sol.flow)
