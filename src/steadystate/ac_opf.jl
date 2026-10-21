# M11 step 3 — the cheapest dispatch SUBJECT TO THE NETWORK, nonlinear ("AC") form, with
# every generator voltage HELD at its set-point (m11-context.md D2.2, D4, Hurdle 24).
#
# The unknowns are each machine's output `p`, each source bus's reactive output, each
# bus angle (the slack's held at 0) and the magnitude of every bus WITHOUT a source; a
# source bus holds its `V_set`. The constraints are real and reactive balance at every
# bus, with each load drawing what its ZIP law says at the bus's magnitude; each source
# bus's reactive output within its machines' summed `[Q_min, Q_max]`; every free bus
# inside the voltage band; every branch's `|S|` inside its rating at BOTH ends (the
# M10-cleanup reading the detailed tier uses: a conductor's rating has to hold where the
# flow is larger). The cost is M6's, through `cost_arrays`.
#
# "HELD" IS D4's. `ac_powerflow` holds a generator bus's voltage until its reactive output
# reaches a limit and then switches it; an optimiser cannot make that switch without a
# discrete choice. Here a point that would need the switch is infeasible, never switched.
# Where a source's reactive output ends ON its limit the two readings may part, and the
# result names the bus (`q_at_limit`) so a comparison with the power flow can refuse it.
#
# THE EQUATIONS ARE WRITTEN TWICE, ON PURPOSE. The extension (`ext/GridSimOPFExt.jl`)
# writes the AC power equations as the optimiser's constraints in BRANCH form — each
# branch's flow at each end from its series admittance, summed per bus — a second,
# hand-written copy of what `ac_powerflow` solves in bus-admittance form through
# `_ac_flows`. The loads' draw there is the polynomial `a_z|V|² + a_i|V| + a_p`, not core's
# `_zip_scale`. Two copies can disagree, and the check that sees it is the answer handed
# back to `ac_powerflow` (Hurdle 24.1, `test/m11_ac_opf.jl`), which uses no optimiser.
#
# WHAT IS READ BACK, AND HOW. Only the decisions come from the solver: the outputs, the
# angles and the free magnitudes. Everything else on the result — every branch flow at
# both ends, each bus's reactive generation, each load's draw, the losses, the cost — is
# RECOMPUTED here from those, through the power flow's own `_ac_branch_flows` and
# `_zip_scale`, so the numbers reported are the ones the power flow's arithmetic gives
# at the optimiser's point. A recomputed quantity past its MARGINED limit by more than
# the stated nearness is refused, as `dc_opf` refuses a projection past `tol`: the
# margin exists so that the answer is strictly inside every real limit, and an answer
# that is not is the solver's or the formulation's error, not a schedule.
#
# THE MARGINS (D9). The binding fixtures put the optimum ON a limit, and the tools the
# answer is handed to refuse a breach strictly. The voltage band is pulled in by an
# absolute `margin_V` and each rating by a relative `margin_S`, both carried on the
# result. Their size is set against what the power flow's own re-solve can move a
# voltage or a flow by — not against the optimiser's tolerance — and argued in
# `docs/evidence/gridsim-m11/step3_predictions.md`.
#
# THE BAND CAN BE MOVED (`vmin`, `vmax`), for one reason: Hurdle 24.4 pins the CAUSE of
# a locally infeasible answer by solving the same case with the floor lowered. An answer
# outside 0.9–1.1 is one `ac_powerflow` refuses, which is the point of that variant and
# not a schedule anyone should hand on.

"""
    ACOPF

The answer of [`ac_opf`](@ref).

  - `outcome` — `:locally_optimal` (Ipopt: `LOCALLY_SOLVED` with a feasible point) or
    `:locally_infeasible` (Ipopt: `LOCALLY_INFEASIBLE`). **Neither is a global claim**:
    Ipopt returns a local optimum, and "locally infeasible" means it found no feasible
    point from where it started — not a proof that none exists. Every other status is
    an error, not an outcome.
  - `status` — Ipopt's termination, primal and dual statuses, as it printed them
  - `machines`, `P` — machine ids in `net.machines` order and their outputs, **pu**
  - `cost` — \$/h, RECOMPUTED from `P` (M6's rule)
  - `demand` — `Σ loads.P0 / S_base`, the load at nominal voltage
  - `buses`, `Vm`, `θ` — per bus, vertex order; a source bus's `Vm` is its `V_set`
    exactly, the slack's `θ` exactly 0
  - `Qgen` — per bus, the sources' reactive output, pu, recomputed from the voltages
  - `Pload`, `Qload` — per bus, what the loads draw at the solved magnitude, pu
  - `losses` — `Σ loss`, pu; `load_shift` — `Σ Pload − demand`, pu (D11: on
    voltage-dependent loads the optimum can be cheaper because it serves less load,
    and the two are reported apart)
  - `branches`, `flow`, `flow_rev`, `qflow`, `qflow_rev`, `loss` — as
    [`ACPowerFlow`](@ref)'s, recomputed by the same function
  - `mva` — each branch's `|S|` at its larger end, pu; `limit` — its rating as the
    optimiser held it, `rating·(1 − margin_S)/S_base` (`Inf` for an unlimited branch)
  - `at_limit` — branches whose `mva` is within `near` of `limit`
  - `vmin`, `vmax` — the band as the optimiser held it, margins applied
  - `at_band` — free buses whose `Vm` is within `near` of `vmin` or `vmax`
  - `q_at_limit` — source buses whose `Qgen` is within `near` of a reactive limit (D4:
    there the optimiser's "held" and the power flow's switch may part)
  - `residual` — the largest bus mismatch of the recomputed balance, pu: real power at
    every bus, reactive at every bus without a source
  - `near` — `2(n + 1)·tol`, `n` the bus count — the summed balance tolerance, twice
  - `S_base`, `tol`, `margin_V`, `margin_S` — the settings it was produced at

On `:locally_infeasible` every solved field is `NaN` and every list is empty.
"""
struct ACOPF
    outcome::Symbol
    status::String
    machines::Vector{Symbol}
    P::Vector{Float64}
    cost::Float64
    demand::Float64
    buses::Vector{Symbol}
    Vm::Vector{Float64}
    θ::Vector{Float64}
    Qgen::Vector{Float64}
    Pload::Vector{Float64}
    Qload::Vector{Float64}
    losses::Float64
    load_shift::Float64
    branches::Vector{Symbol}
    flow::Vector{Float64}
    flow_rev::Vector{Float64}
    qflow::Vector{Float64}
    qflow_rev::Vector{Float64}
    loss::Vector{Float64}
    mva::Vector{Float64}
    limit::Vector{Float64}
    at_limit::Vector{Symbol}
    vmin::Float64
    vmax::Float64
    at_band::Vector{Symbol}
    q_at_limit::Vector{Symbol}
    residual::Float64
    near::Float64
    S_base::Float64
    tol::Float64
    margin_V::Float64
    margin_S::Float64
end

# The solver lives in the extension; this is what runs when it is not loaded.
struct _IpoptOPF end
function _ac_opf_solve(::Any, prob, tol, start, max_iter)
    throw(ArgumentError(
        "ac_opf needs its solver, which is an optional extension: `using JuMP, Ipopt` " *
        "(both must be installed in the active environment) loads it. The model itself " *
        "was checked and is dispatchable."))
end

# The per-unit problem: M6's costs and limits (and its refusals, under this name), the
# network as branch admittances, the held voltages, the reactive limits per source bus,
# the loads one by one with their ZIP shares, and the margined band and ratings.
function _ac_opf_problem(net::NetworkModel, tol::Float64, margin_V::Float64,
                         margin_S::Float64, vmin::Float64, vmax::Float64)
    prob = _dispatch_problem(net, tol; who = "ac_opf")
    n = length(net.buses)
    V_set = fill(NaN, n)
    Q_min = zeros(Float64, n)
    Q_max = zeros(Float64, n)
    for m in net.machines
        v = net.bus_index[m.bus]
        if isnan(V_set[v])
            V_set[v] = m.V_set
        else
            m.V_set == V_set[v] || throw(ArgumentError(
                "ac_opf: bus $(m.bus) carries machines with different V_set " *
                "($(V_set[v]) and $(m.V_set) pu, the latter on machine $(m.id)). A bus " *
                "has ONE terminal voltage."))
        end
        Q_min[v] += m.Q_min
        Q_max[v] += m.Q_max
    end
    for v in 1:n
        isnan(V_set[v]) && continue
        vmin ≤ V_set[v] ≤ vmax || throw(ArgumentError(
            "ac_opf: bus $(net.buses[v].id) holds V_set = $(V_set[v]) pu, outside the band " *
            "[$vmin, $vmax]. A held voltage outside the band has no feasible point."))
    end
    la = load_arrays(net)
    topo = branch_topology(net)
    y = [inv(complex(br.R, br.X)) for br in net.branches]   # X > 0 by `Branch`
    return (; prob..., n,
              gen_bus = Int[net.bus_index[m.bus] for m in net.machines],
              src = topo.src, dst = topo.dst, g = real.(y), b = imag.(y),
              limit = Float64[br.rating * (1 - margin_S) / net.S_base for br in net.branches],
              V_set, Q_min, Q_max,
              load_bus = la.bus, load_P = la.P, load_Q = la.Q,
              load_az = la.a_z, load_ai = la.a_i, load_ap = la.a_p,
              vlo = vmin + margin_V, vhi = vmax - margin_V,
              slack = net.bus_index[net.slack])
end

# Where the search starts: `(; p, θ, Vm)` per machine / per bus. Flat is `|V| = 1` at
# every free bus, every angle 0 and the load split in proportion to `Pmax` (the schedule
# rule of the report grids); a `DCOPF` start takes its outputs and angles.
function _ac_opf_start(net::NetworkModel, prob, start)
    n = prob.n
    Vm = [isnan(prob.V_set[v]) ? 1.0 : prob.V_set[v] for v in 1:n]
    if start === :flat
        p = clamp.(prob.demand .* prob.pmax ./ sum(prob.pmax), prob.pmin, prob.pmax)
        return (; p, θ = zeros(Float64, n), Vm)
    elseif start isa DCOPF
        start.outcome === :optimal || throw(ArgumentError(
            "ac_opf: the DC OPF given as `start` is :$(start.outcome), so it has no point " *
            "to start from."))
        start.machines == prob.ids && start.buses == Symbol[b.id for b in net.buses] ||
            throw(ArgumentError(
                "ac_opf: the DC OPF given as `start` was solved for machines " *
                "$(start.machines) over buses $(start.buses), not this model's."))
        return (; p = copy(start.P), θ = copy(start.θ), Vm)
    end
    throw(ArgumentError(
        "ac_opf: `start` must be :flat or a DCOPF (the answer of `dc_opf` on this model), " *
        "got $(repr(start))."))
end

"""
    ac_opf(net::NetworkModel; tol = 1e-9, margin_V = 1e-6, margin_S = 1e-5,
           vmin = 0.9, vmax = 1.1, start = :flat, max_iter = 3000) -> ACOPF

The cheapest dispatch of the model's machines **subject to the AC network**, with every
generator voltage **held** at its `V_set`: real and reactive balance at every bus with
the loads' own ZIP draw, the losses in the lines, each source bus's reactive output
within its machines' summed limits, every other bus inside `[vmin + margin_V,
vmax − margin_V]`, and every branch's `|S|` within `rating·(1 − margin_S)` at both ends.
The costs, units and refusals of [`economic_dispatch`](@ref) under this name. Hand the
answer on with [`dispatch_schedule`](@ref).

Needs `using JuMP, Ipopt` (a package extension, `GridSimOPFExt`). Ipopt returns a
**local** optimum: `outcome` is `:locally_optimal` or `:locally_infeasible`, never a
global claim, and every other Ipopt status throws.

`tol` goes to Ipopt as its overall, constraint-violation, dual-infeasibility and
complementarity tolerances, with its bound relaxation off, so every bounded quantity is
inside its margined bound by Ipopt's own construction. The margins are sized against the
power flow's re-solve of the answer (`step3_predictions.md`): at `tol = 1e-9` on case9 it
can move a voltage by at most ~7e-9 pu and a branch's `|S|` by ~9e-7 pu, so `margin_V =
1e-6` pu and `margin_S = 1e-5` (6e-6 pu on a 60 MVA line) keep the handed-back answer
strictly inside the real limits. `start` is `:flat` or a
[`DCOPF`](@ref) of the same model. `vmin`/`vmax` move the band itself: anything but the
defaults gives an answer [`ac_powerflow`](@ref) may refuse, which is what it is for (a
cause pinned by a variant, never a schedule).
"""
function ac_opf(net::NetworkModel; tol::Real = 1.0e-9, margin_V::Real = 1.0e-6,
                margin_S::Real = 1.0e-5, vmin::Real = _PF_VMIN, vmax::Real = _PF_VMAX,
                start = :flat, max_iter::Integer = 3000)
    tol > 0 || throw(ArgumentError("ac_opf: tol ($tol) must be > 0."))
    margin_V ≥ 0 || throw(ArgumentError("ac_opf: margin_V ($margin_V) must be ≥ 0."))
    0 ≤ margin_S < 1 || throw(ArgumentError(
        "ac_opf: margin_S ($margin_S) must be in [0, 1) — it is the fraction of each " *
        "rating held back."))
    0 < vmin + margin_V < vmax - margin_V || throw(ArgumentError(
        "ac_opf: the margined band [$(vmin + margin_V), $(vmax - margin_V)] is empty or " *
        "not above zero."))
    τ, δV, δS = Float64(tol), Float64(margin_V), Float64(margin_S)
    prob = _ac_opf_problem(net, τ, δV, δS, Float64(vmin), Float64(vmax))
    x0 = _ac_opf_start(net, prob, start)
    sol = _ac_opf_solve(_IpoptOPF(), prob, τ, x0, Int(max_iter))
    return _ac_opf_result(net, prob, sol, τ, δV, δS)
end

# The answer, read back (see the header): decisions from the solver, everything else
# recomputed through the power flow's own functions, then checked against the margined
# limits it was optimised against.
function _ac_opf_result(net::NetworkModel, prob, sol, τ, δV, δS)
    n, nb = prob.n, length(net.branches)
    buses = Symbol[b.id for b in net.buses]
    branches = Symbol[b.id for b in net.branches]
    near = 2 * (n + 1) * τ
    if sol.outcome === :locally_infeasible
        nan(k) = fill(NaN, k)
        return ACOPF(:locally_infeasible, sol.status, prob.ids, nan(length(prob.ids)), NaN,
                     prob.demand, buses, nan(n), nan(n), nan(n), nan(n), nan(n), NaN, NaN,
                     branches, nan(nb), nan(nb), nan(nb), nan(nb), nan(nb), nan(nb),
                     prob.limit, Symbol[], prob.vlo, prob.vhi, Symbol[], Symbol[], NaN, near,
                     net.S_base, τ, δV, δS)
    end
    p = sol.p
    for k in eachindex(p)
        q = clamp(p[k], prob.pmin[k], prob.pmax[k])
        abs(q - p[k]) ≤ τ || throw(ErrorException(
            "ac_opf: the solver put machine $(prob.ids[k]) at $(p[k]) pu, outside " *
            "[$(prob.pmin[k]), $(prob.pmax[k])] by more than tol = $τ."))
        p[k] = q
    end
    held = .!isnan.(prob.V_set)
    Vm = [held[v] ? prob.V_set[v] : sol.Vm[v] for v in 1:n]
    θ = copy(sol.θ)
    θ[prob.slack] = 0.0
    flow, flow_rev, qflow, qflow_rev, loss, mva = _ac_branch_flows(net, Vm, θ)
    Pnet = zeros(Float64, n)
    Qnet = zeros(Float64, n)
    for e in 1:nb
        f, t = prob.src[e], prob.dst[e]
        Pnet[f] += flow[e];     Qnet[f] += qflow[e]
        Pnet[t] += flow_rev[e]; Qnet[t] += qflow_rev[e]
    end
    Pload = zeros(Float64, n)
    Qload = zeros(Float64, n)
    for k in eachindex(prob.load_bus)
        v = prob.load_bus[k]
        z = _zip_scale(Vm[v], prob.load_ai[k], prob.load_ap[k])
        Pload[v] += prob.load_P[k] * z
        Qload[v] += prob.load_Q[k] * z
    end
    Pgen = zeros(Float64, n)
    for k in eachindex(p)
        Pgen[prob.gen_bus[k]] += p[k]
    end
    Qgen = Qnet .+ Qload
    residual = max(maximum(abs, Pnet .+ Pload .- Pgen),
                   maximum((abs(Qgen[v]) for v in 1:n if !held[v]); init = 0.0))
    # The margined limits, re-read on the recomputed numbers.
    for e in 1:nb
        mva[e] ≤ prob.limit[e] + near || throw(ErrorException(
            "ac_opf: branch $(branches[e]) carries $(mva[e] * net.S_base) MVA at its larger " *
            "end, over the margined limit $(prob.limit[e] * net.S_base) MVA by more than " *
            "$(near * net.S_base) — the optimiser's answer breaks a limit it was given."))
    end
    for v in 1:n
        held[v] && continue
        prob.vlo - near ≤ Vm[v] ≤ prob.vhi + near || throw(ErrorException(
            "ac_opf: bus $(buses[v]) solved to |V| = $(Vm[v]), outside the margined band " *
            "[$(prob.vlo), $(prob.vhi)] by more than $near."))
    end
    for v in 1:n
        held[v] || continue
        prob.Q_min[v] - near ≤ Qgen[v] ≤ prob.Q_max[v] + near || throw(ErrorException(
            "ac_opf: the sources at bus $(buses[v]) give Q = $(Qgen[v]) pu, outside " *
            "[$(prob.Q_min[v]), $(prob.Q_max[v])] by more than $near."))
    end
    at_limit = Symbol[branches[e] for e in 1:nb
                      if isfinite(prob.limit[e]) && mva[e] ≥ prob.limit[e] - near]
    at_band = Symbol[buses[v] for v in 1:n
                     if !held[v] && (Vm[v] ≤ prob.vlo + near || Vm[v] ≥ prob.vhi - near)]
    q_at_limit = Symbol[buses[v] for v in 1:n
                        if held[v] && (Qgen[v] ≤ prob.Q_min[v] + near ||
                                       Qgen[v] ≥ prob.Q_max[v] - near)]
    cost = sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] + prob.a0[k] for k in eachindex(p))
    return ACOPF(:locally_optimal, sol.status, prob.ids, p, cost, prob.demand, buses, Vm, θ,
                 Qgen, Pload, Qload, sum(loss), sum(Pload) - prob.demand,
                 branches, flow, flow_rev, qflow, qflow_rev, loss, mva, prob.limit, at_limit,
                 prob.vlo, prob.vhi, at_band, q_at_limit, residual, near,
                 net.S_base, τ, δV, δS)
end

"""
    dispatch_schedule(net, r::ACOPF) -> NetworkModel

`net` with each machine's `P0` set from the AC OPF — the schedule handed to
[`ac_powerflow`](@ref) and the simulators. **The slack bus's machine is the one
exception**: `NetworkModel` requires the schedule to balance at nominal voltage
(`Σ machines.P0 = Σ loads.P0`), and an AC dispatch does not — it carries the losses and,
on voltage-dependent loads, the load-draw shift. So every other machine gets its OPF
output and the slack's machine gets the nominal balance; a power flow never reads the
slack's `P0` (its output is whatever the network needs), and the handed-back flow's
slack output is what is compared with the OPF's.

Refused: an answer that is not `:locally_optimal`; a slack bus carrying more than one
machine (which of them takes the balance is a rule the model does not have, as in
[`dispatch_loss_gap`](@ref)); and a nominal balance above the slack machine's `Pmax`,
which `Machine` would refuse, named here (there is no lower bound to check: `Machine`
admits any `P0 ≤ Pmax`, negative included).
"""
function dispatch_schedule(net::NetworkModel, r::ACOPF)
    r.outcome === :locally_optimal || throw(ArgumentError(
        "dispatch_schedule: the AC OPF's outcome is :$(r.outcome) ($(r.status)), so it " *
        "has no schedule to hand on."))
    ids = Symbol[m.id for m in net.machines]
    ids == r.machines && r.S_base == net.S_base || throw(ArgumentError(
        "dispatch_schedule: the AC OPF is for machines $(r.machines) on S_base = " *
        "$(r.S_base) MVA; the model has $ids on $(net.S_base)."))
    at = net.machines_at_bus[net.bus_index[net.slack]]
    length(at) == 1 || throw(ArgumentError(
        "dispatch_schedule: the slack bus :$(net.slack) carries $(length(at)) machines. " *
        "The AC OPF's schedule leaves the slack's machine the nominal balance, and with " *
        "several there is no rule for which one takes it."))
    ks = at[1]
    S = net.S_base
    others = sum((r.P[k] * S for k in eachindex(r.P) if k != ks); init = 0.0)
    p_slack = sum(l.P0 for l in net.loads; init = 0.0) - others
    m = net.machines[ks]
    p_slack ≤ m.Pmax || throw(ArgumentError(
        "dispatch_schedule: the nominal balance left for the slack machine $(m.id) is " *
        "$p_slack MW, above its Pmax ($(m.Pmax) MW). The OPF's own slack output is " *
        "$(r.P[ks] * S) MW; it is the schedule's nominal balance that does not fit."))
    ms = Machine[_machine_with(mm; P0 = k == ks ? p_slack : r.P[k] * S)
                 for (k, mm) in pairs(net.machines)]
    return NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                        slack = net.slack, inverters = net.inverters)
end
