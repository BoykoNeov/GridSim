# M6 step 7 — cheapest dispatch, network-free (m6-context.md D16).
#
# Minimise the generators' summed running cost subject to ONE balance (total output
# equals total scheduled load) and each unit's own minimum and maximum. No lines, no
# losses, no voltages: those are the owed network OPF (D16 §7). The answer is handed
# to the power flow as a schedule (`dispatch_schedule`), and the flow's slack then
# picks up the losses — `dispatch_loss_gap` reports what that costs, rather than
# quoting a network-free optimum as though the network agreed with it.
#
# THE SPLIT IS D2's, APPLIED A SECOND TIME: the formulation below is ours, the solver
# is HiGHS through JuMP. And JuMP/HiGHS are a PACKAGE EXTENSION
# (`ext/GridSimDispatchExt.jl`), not a dependency: fifteen packages is a real
# load-time cost for every session that never dispatches, so core keeps loading only
# what it needs (D16 §4). Everything that REFUSES lives here, in core, so a model
# with an uncosted machine is refused by name whether or not the solver is loaded.
#
# THE UNITS. `Machine` stores its cost as the source prints it — $/h against MW —
# because `Machine` stores `P0` and `Pmax` in MW too and does not know `S_base`
# (only `NetworkModel` does). So the per-unit conversion happens where every other
# one in this repo happens: in a compiled view, `cost_arrays`. D16 §3 said "at the
# constructor boundary"; that boundary does not have the base, and this is recorded
# as the step's departure from its plan (m6-tasks.md step 7). The conversion is
#
#     C($/h) = c2·P² + c1·P + c0,  P = p·S_base   ⇒   a2 = c2·S_base², a1 = c1·S_base, a0 = c0
#
# and it is the one place a wrong factor of `S_base` survives every check that reads
# the converted numbers back (D16 §6) — which is why the tests check it from literal
# MW numbers that never pass through it, and at two different bases.

"""
    cost_arrays(net::NetworkModel) -> (; ids, a2, a1, a0, pmin, pmax)

The dispatch's compiled view of the machines' costs and limits, **per-unit on
`net.S_base`**, in `net.machines` order (bus-sorted):

  - `a2`, `a1`, `a0` — the running cost `a2·p² + a1·p + a0` in **\$/h** with `p` in pu,
    i.e. `Machine.cost_c2·S_base²`, `cost_c1·S_base`, `cost_c0`
  - `pmin`, `pmax` — `Machine.Pmin/S_base`, `Machine.Pmax/S_base`

A machine whose cost or minimum was never given carries `NaN` here; the refusal is
[`economic_dispatch`](@ref)'s, which names the machine, not this view's.
"""
function cost_arrays(net::NetworkModel)
    S = net.S_base
    ms = net.machines
    return (; ids  = Symbol[m.id for m in ms],
              a2   = Float64[m.cost_c2 * S^2 for m in ms],
              a1   = Float64[m.cost_c1 * S for m in ms],
              a0   = Float64[m.cost_c0 for m in ms],
              pmin = Float64[m.Pmin / S for m in ms],
              pmax = Float64[m.Pmax / S for m in ms])
end

"""
    EconomicDispatch

The answer of [`economic_dispatch`](@ref).

  - `machines` — machine ids, in `net.machines` order
  - `P` — each machine's output, **pu on `S_base`** (multiply by `S_base` for MW)
  - `cost` — the total running cost, **\$/h**, RECOMPUTED from `P` and the model's
    own cost data rather than read off the solver's objective, so the number
    reported is a function of the answer returned
  - `demand` — the total scheduled load the dispatch met, pu
  - `S_base` — MVA, the base `P` is on
  - `tol`, `regularization` — the solver settings it was produced at, so a band
    derived from them travels with the answer it bounds
"""
struct EconomicDispatch
    machines::Vector{Symbol}
    P::Vector{Float64}
    cost::Float64
    demand::Float64
    S_base::Float64
    tol::Float64
    regularization::Float64
end

# The solver lives in the extension. This fallback is what runs when it is not
# loaded, and it says how to load it rather than failing with a MethodError.
struct _HiGHSDispatch end
function _dispatch_solve(::Any, prob, tol, regularization)
    throw(ArgumentError(
        "economic_dispatch needs its solver, which is an optional extension: " *
        "`using JuMP, HiGHS` (both must be installed in the active environment) " *
        "loads it. The model itself was checked and is dispatchable."))
end

# Everything the dispatch refuses, in one place and in core. Returns the problem in
# pu, ready for the solver. `tol` is the solver's primal tolerance: a load outside
# the reachable range by less than that is one the solver can meet, and refusing it
# would refuse the exact edge — measured: three 10 MW minimums sum to
# 30.000000000000004 MW once divided by `S_base` and added, so "load = Σ Pmin" was
# refused as below it (m6-tasks.md step 7).
function _dispatch_problem(net::NetworkModel, tol::Float64 = 1.0e-9)
    isempty(net.machines) && throw(ArgumentError(
        "economic_dispatch: the model has no machines, so there is nothing to dispatch."))
    ca = cost_arrays(net)
    for m in net.machines
        isnan(m.cost_c2) && throw(ArgumentError(
            "economic_dispatch: machine $(m.id) has no cost (cost_c2, cost_c1, " *
            "cost_c0 not given). It is refused rather than costed at zero: a zero is " *
            "an invented number, and it would make $(m.id) the first unit loaded."))
        isnan(m.Pmin) && throw(ArgumentError(
            "economic_dispatch: machine $(m.id) has no minimum output (Pmin not " *
            "given). It is refused rather than given a minimum of zero: a unit that " *
            "may run at zero is a modelling claim the data never made."))
    end
    S = net.S_base
    demand = sum(l.P0 for l in net.loads; init = 0.0) / S
    lo, hi = sum(ca.pmin), sum(ca.pmax)
    # UNREACHABLE THROUGH `NetworkModel` TODAY, and kept: `Machine` requires
    # `P0 ≤ Pmax` and `NetworkModel` requires `Σ P0 = Σ loads`, so `Σ loads ≤ Σ Pmax`
    # on every model that exists (tested). The dispatch does not lean on an invariant
    # enforced in two other files; a reachable refusal below it (the minimum) is the
    # same check, and it IS reached.
    demand > hi + tol && throw(ArgumentError(
        "economic_dispatch: the load ($(demand * S) MW) is above every machine at its " *
        "maximum together ($(hi * S) MW). No dispatch meets it."))
    demand < lo - tol && throw(ArgumentError(
        "economic_dispatch: the load ($(demand * S) MW) is below every machine at its " *
        "minimum together ($(lo * S) MW). No dispatch meets it without switching a " *
        "unit off, and on/off decisions are out of scope (m6-context.md D16 §7)."))
    return (; ca..., demand)
end

"""
    economic_dispatch(net::NetworkModel; tol = 1e-9, regularization = 1e-7) -> EconomicDispatch

The cheapest split of the model's total scheduled load (`Σ loads.P0`) across its
machines, each within `[Pmin, Pmax]`, with quadratic running costs — **network-free**:
no line limits, no losses, no voltages (`m6-context.md` D16). Hand the answer to the
power flow with [`dispatch_schedule`](@ref), and read what the losses cost with
[`dispatch_loss_gap`](@ref).

Needs `using JuMP, HiGHS` (a package extension). Refused by name, with or without
the solver loaded: a model with no machines, a machine with no cost or no minimum
(never costed or bounded at zero), and a load no dispatch can meet.

`tol` is handed to HiGHS as its primal feasibility, dual feasibility and optimality
tolerances; `regularization` as `qp_regularization_value` — the value HiGHS adds to
the Hessian in its active-set QP solver, whose default is `1e-7`. Both are
**explicit** rather than inherited because the band an answer is checked against is
derived from them (see the tests), and a default that changed underneath would move
the answer without moving the band.

The solution is projected onto each unit's `[pmin, pmax]` before it is returned — a
QP solver's bounds hold only to its feasibility tolerance, and `Machine` refuses
`P0 > Pmax` outright — and the projection is **refused if it moves any unit by more
than `tol`**, so it can never hide a wrong answer.
"""
function economic_dispatch(net::NetworkModel; tol::Real = 1.0e-9,
                           regularization::Real = 1.0e-7)
    tol > 0 || throw(ArgumentError("economic_dispatch: tol ($tol) must be > 0."))
    regularization ≥ 0 || throw(ArgumentError(
        "economic_dispatch: regularization ($regularization) must be ≥ 0."))
    prob = _dispatch_problem(net, Float64(tol))
    p = _dispatch_solve(_HiGHSDispatch(), prob, Float64(tol), Float64(regularization))
    for k in eachindex(p)
        q = clamp(p[k], prob.pmin[k], prob.pmax[k])
        abs(q - p[k]) ≤ tol || throw(ErrorException(
            "economic_dispatch: the solver put machine $(prob.ids[k]) at $(p[k]) pu, " *
            "outside [$(prob.pmin[k]), $(prob.pmax[k])] by more than tol = $tol."))
        p[k] = q
    end
    cost = sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] + prob.a0[k] for k in eachindex(p))
    return EconomicDispatch(prob.ids, p, cost, prob.demand, net.S_base,
                            Float64(tol), Float64(regularization))
end

# `ed` must have been computed from THIS model: same machines, same order, same base.
function _assert_dispatch_of(net::NetworkModel, ed::EconomicDispatch)
    ids = Symbol[m.id for m in net.machines]
    ids == ed.machines || throw(ArgumentError(
        "dispatch: the dispatch is for machines $(ed.machines), the model has $ids."))
    ed.S_base == net.S_base || throw(ArgumentError(
        "dispatch: the dispatch is on S_base = $(ed.S_base) MVA, the model on $(net.S_base)."))
    return nothing
end

"""
    dispatch_schedule(net, ed::EconomicDispatch) -> NetworkModel

`net` with each machine's `P0` replaced by its dispatched output (in MW), rebuilt
through the constructors — the schedule the power flow reads. Nothing else moves.
"""
function dispatch_schedule(net::NetworkModel, ed::EconomicDispatch)
    _assert_dispatch_of(net, ed)
    ms = Machine[_machine_with(m; P0 = ed.P[k] * net.S_base) for (k, m) in pairs(net.machines)]
    return NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                        slack = net.slack)
end

"""
    dispatch_loss_gap(net, ed::EconomicDispatch; kwargs...) -> NamedTuple

Run the AC power flow ([`ac_powerflow`](@ref), `kwargs` passed through) on the
dispatched schedule and report what the network does to the optimum. The dispatch
met the load with no losses; the flow puts the losses on the slack machine, so the
*flowed* state costs more than the optimum by the slack's cost of that extra output.

  - `flow` — the `ACPowerFlow`; `schedule` — the `NetworkModel` it solved
  - `slack_machine` — the one machine at the slack bus (refused if there are several:
    the pickup would need a sharing rule the model does not have)
  - `pickup` — pu, the slack's solved output minus its dispatch
  - `cost_optimal`, `cost_flowed` — \$/h; `gap = cost_flowed − cost_optimal`
  - `slack_within_limits` — whether the slack's solved output is still inside its
    `[Pmin, Pmax]`. Reported, not enforced: the network-free dispatch never saw the
    losses, so nothing kept room for them.

`gap = pickup·(2·a2·p + a1 + a2·pickup)` for the slack's own coefficients — so it
has the sign of the pickup whenever the slack's marginal cost `2·a2·p + a1` is
positive at its dispatch, which is the case the tests assert on.
"""
function dispatch_loss_gap(net::NetworkModel, ed::EconomicDispatch; kwargs...)
    _assert_dispatch_of(net, ed)
    sched = dispatch_schedule(net, ed)
    v = sched.bus_index[sched.slack]
    at = sched.machines_at_bus[v]
    length(at) == 1 || throw(ArgumentError(
        "dispatch_loss_gap: the slack bus :$(sched.slack) carries $(length(at)) " *
        "machines. The losses land on the slack BUS, and pricing them needs to know " *
        "which machine produces them — a sharing rule this model does not have."))
    k = at[1]
    flow = ac_powerflow(sched; kwargs...)
    ca = cost_arrays(sched)
    pickup = flow.Pgen[v] - ed.P[k]
    p_new = ed.P[k] + pickup
    cost_flowed = ed.cost - (ca.a2[k] * ed.P[k]^2 + ca.a1[k] * ed.P[k]) +
                  (ca.a2[k] * p_new^2 + ca.a1[k] * p_new)
    return (; flow, schedule = sched, slack_machine = ca.ids[k], pickup,
              cost_optimal = ed.cost, cost_flowed, gap = cost_flowed - ed.cost,
              slack_within_limits = ca.pmin[k] ≤ p_new ≤ ca.pmax[k])
end
