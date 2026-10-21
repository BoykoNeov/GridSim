# M11 step 1 — the cheapest dispatch SUBJECT TO THE NETWORK, linear ("DC") form
# (m11-context.md D3, Hurdle 22).
#
# M6's dispatch with the network moved from after the optimisation to inside it. The
# unknowns are each machine's output `p` and each bus angle `θ` (the slack's held at
# 0); the constraints are power balance at EVERY bus — not one total, which is what
# would let the optimiser ignore the network — each branch's flow `(θ_f − θ_t)/X`
# within its rating in BOTH directions, and each machine within `[Pmin, Pmax]`. The
# cost is M6's, through `cost_arrays`, so the per-unit conversion stays in one place.
# The DC approximation is `dc_powerflow`'s, read from the same `1/X` weights: `|V| = 1`,
# `R` ignored, no reactive power, loads at their nominal `P0`.
#
# THE SPLIT IS M6's: every refusal is here, in core, and the extension
# (`ext/GridSimDispatchExt.jl`) only hands the per-unit problem to HiGHS. The checks
# `economic_dispatch` makes are the same function, called under this one's name.
#
# THE MARGIN (D9). The binding fixtures put the optimum ON a limit, and a solver holds
# a constraint only to its tolerance — while the tools the answer is handed to refuse a
# breach strictly. So the optimiser works against each rating pulled in by a stated
# relative `margin`, carried on the result: an answer on a margined limit is strictly
# inside the real one. An identity checked against this answer uses the margined
# rating, or it measures the margin.
#
# REFUSALS THAT CANNOT BE REACHED (m11-context.md, "What step 1 measured"). The plan
# named two refusals of its own: a grid in pieces and a zero rating. `NetworkModel`
# refuses the first and `Branch` the second, so no model this function can receive
# carries either. They are not re-checked here, and no path around the constructors
# was added to make them reachable. An INFINITE rating is reachable (`rating > 0`
# admits it) and means what it says: that branch gets no limit.

"""
    DCOPF

The answer of [`dc_opf`](@ref).

  - `outcome` — `:optimal`, or `:infeasible` when HiGHS returned a certificate that no
    dispatch meets the limits. Every other solver status is an error, not an outcome.
  - `status` — HiGHS's termination, primal and dual statuses, as it printed them
  - `machines`, `P` — machine ids in `net.machines` order and their outputs, **pu**
  - `cost` — \$/h, RECOMPUTED from `P` and the model's own costs (M6's rule)
  - `demand` — the total scheduled load met, pu
  - `buses`, `θ` — bus ids in vertex order and their angles, radians, slack at 0
  - `branches`, `flow` — branch ids in model order and their flows `from → to`, pu,
    recomputed from `θ` as `(θ_f − θ_t)/X`
  - `limit` — each branch's limit as the optimiser held it, pu: `rating·(1 − margin)/S_base`
    (`Inf` for an unlimited branch)
  - `at_limit` — the branches whose `|flow|` is within `2(n + 1)·tol` of `limit`, `n`
    the bus count (the balance rows' summed tolerance plus the flow row's, twice)
  - `S_base`, `tol`, `regularization`, `margin` — the settings it was produced at

On `:infeasible`, `P`, `θ`, `flow` and `cost` are `NaN` and `at_limit` is empty.
"""
struct DCOPF
    outcome::Symbol
    status::String
    machines::Vector{Symbol}
    P::Vector{Float64}
    cost::Float64
    demand::Float64
    buses::Vector{Symbol}
    θ::Vector{Float64}
    branches::Vector{Symbol}
    flow::Vector{Float64}
    limit::Vector{Float64}
    at_limit::Vector{Symbol}
    S_base::Float64
    tol::Float64
    regularization::Float64
    margin::Float64
end

# The solver lives in the extension; this is what runs when it is not loaded.
function _dc_opf_solve(::Any, prob, tol, regularization)
    throw(ArgumentError(
        "dc_opf needs its solver, which is an optional extension: `using JuMP, HiGHS` " *
        "(both must be installed in the active environment) loads it. The model itself " *
        "was checked and is dispatchable."))
end

# The per-unit problem: M6's (costs, limits, demand) plus the network. Loads are summed
# per bus from `load_arrays`, the one place their conversion happens — not from
# `bus_injections`, which already carries the machines' schedule `P0`, the very thing
# being chosen.
function _dc_opf_problem(net::NetworkModel, tol::Float64, margin::Float64)
    prob = _dispatch_problem(net, tol; who = "dc_opf")
    n = length(net.buses)
    load = zeros(Float64, n)
    la = load_arrays(net)
    for k in eachindex(la.bus)
        load[la.bus[k]] += la.P[k]
    end
    topo = branch_topology(net)
    return (; prob..., n, load,
              gen_bus = Int[net.bus_index[m.bus] for m in net.machines],
              src = topo.src, dst = topo.dst,
              b = inv.(topo.X),                  # `_dc_susceptance`'s weights, X > 0 by `Branch`
              limit = Float64[br.rating * (1 - margin) / net.S_base for br in net.branches],
              slack = net.bus_index[net.slack])
end

"""
    dc_opf(net::NetworkModel; tol = 1e-9, regularization = 1e-7, margin = 1e-6) -> DCOPF

The cheapest dispatch of the model's machines **subject to the network**, in the
linear (DC) approximation: each machine within `[Pmin, Pmax]`, power balanced at every
bus, and every branch's flow `(θ_f − θ_t)/X` within `±rating·(1 − margin)` — the costs,
units and refusals of [`economic_dispatch`](@ref), the network of
[`dc_powerflow`](@ref). Hand the answer on with [`dispatch_schedule`](@ref).

Needs `using JuMP, HiGHS` (the same extension as `economic_dispatch`). Refused by name,
with or without the solver: everything `economic_dispatch` refuses, under this name.
A set of ratings no dispatch meets is an OUTCOME (`:infeasible`, with HiGHS's
certificate), not an error.

`tol` and `regularization` go to HiGHS as `economic_dispatch` hands them. `margin` is
D9's: relative, `0 ≤ margin < 1`, and the default `1e-6` puts a 150 MVA line's limit
1.5e-4 MW inside its rating — three orders above `tol`, so a flow on its margined
limit is strictly inside the real one. `margin = 0` optimises against the ratings as
given.
"""
function dc_opf(net::NetworkModel; tol::Real = 1.0e-9, regularization::Real = 1.0e-7,
                margin::Real = 1.0e-6)
    tol > 0 || throw(ArgumentError("dc_opf: tol ($tol) must be > 0."))
    regularization ≥ 0 || throw(ArgumentError(
        "dc_opf: regularization ($regularization) must be ≥ 0."))
    0 ≤ margin < 1 || throw(ArgumentError(
        "dc_opf: margin ($margin) must be in [0, 1) — it is the fraction of each " *
        "rating held back."))
    τ = Float64(tol)
    prob = _dc_opf_problem(net, τ, Float64(margin))
    sol = _dc_opf_solve(_HiGHSDispatch(), prob, τ, Float64(regularization))
    buses = Symbol[b.id for b in net.buses]
    branches = Symbol[b.id for b in net.branches]
    if sol.outcome === :infeasible
        nan(k) = fill(NaN, k)
        return DCOPF(:infeasible, sol.status, prob.ids, nan(length(prob.ids)), NaN,
                     prob.demand, buses, nan(prob.n), branches, nan(length(branches)),
                     prob.limit, Symbol[], net.S_base, τ, Float64(regularization),
                     Float64(margin))
    end
    p = sol.p
    # Projected onto each unit's limits, refused if that moves a unit by more than
    # `tol` — `economic_dispatch`'s rule, for its reason (`Machine` refuses P0 > Pmax).
    for k in eachindex(p)
        q = clamp(p[k], prob.pmin[k], prob.pmax[k])
        abs(q - p[k]) ≤ τ || throw(ErrorException(
            "dc_opf: the solver put machine $(prob.ids[k]) at $(p[k]) pu, outside " *
            "[$(prob.pmin[k]), $(prob.pmax[k])] by more than tol = $τ."))
        p[k] = q
    end
    θ = sol.θ
    flow = Float64[prob.b[e] * (θ[prob.src[e]] - θ[prob.dst[e]]) for e in eachindex(prob.b)]
    near = 2 * (prob.n + 1) * τ
    at_limit = Symbol[branches[e] for e in eachindex(flow)
                      if isfinite(prob.limit[e]) && abs(flow[e]) ≥ prob.limit[e] - near]
    cost = sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] + prob.a0[k] for k in eachindex(p))
    return DCOPF(:optimal, sol.status, prob.ids, p, cost, prob.demand, buses, θ,
                 branches, flow, prob.limit, at_limit, net.S_base, τ,
                 Float64(regularization), Float64(margin))
end

"""
    dispatch_schedule(net, r::DCOPF) -> NetworkModel

`net` with each machine's `P0` set to the OPF's output — as for an `EconomicDispatch`.
Refused for an answer that is not `:optimal`: an infeasible OPF has no schedule.
"""
function dispatch_schedule(net::NetworkModel, r::DCOPF)
    r.outcome === :optimal || throw(ArgumentError(
        "dispatch_schedule: the OPF's outcome is :$(r.outcome) ($(r.status)), so it " *
        "has no schedule to hand on."))
    return dispatch_schedule(net, EconomicDispatch(r.machines, r.P, r.cost, r.demand,
                                                   r.S_base, r.tol, r.regularization))
end
