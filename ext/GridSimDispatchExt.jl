# M6 step 7 — the solver half of `economic_dispatch` (m6-context.md D16 §4).
#
# A package extension: it loads only when BOTH JuMP and HiGHS are loaded, so core's
# dependency list does not grow by fifteen packages for every session that never
# dispatches. The formulation and every refusal live in core
# (`src/steadystate/economic_dispatch.jl`); this file only hands the per-unit
# problem to HiGHS and hands the numbers back.
module GridSimDispatchExt

using GridSim
using JuMP: JuMP, MOI
using HiGHS: HiGHS

function GridSim._dispatch_solve(::GridSim._HiGHSDispatch, prob, tol::Float64,
                                 regularization::Float64)
    n = length(prob.a2)
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    # Option names read from HiGHS's own `HighsOptions.h`, not from memory. All three
    # KKT measures get the same value, so the band derived from `tol` has one input.
    JuMP.set_attribute(model, "primal_feasibility_tolerance", tol)
    JuMP.set_attribute(model, "dual_feasibility_tolerance", tol)
    JuMP.set_attribute(model, "optimality_tolerance", tol)
    JuMP.set_attribute(model, "qp_regularization_value", regularization)
    p = JuMP.@variable(model, prob.pmin[k] <= p[k = 1:n] <= prob.pmax[k])
    JuMP.@constraint(model, sum(p) == prob.demand)
    JuMP.@objective(model, Min,
                    sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] for k in 1:n))
    JuMP.optimize!(model)
    st = JuMP.termination_status(model)
    st == MOI.OPTIMAL || throw(ErrorException(
        "economic_dispatch: HiGHS stopped with status $st, not OPTIMAL. The problem " *
        "passed every check in core (costs given, load reachable), so this is the " *
        "solver's refusal, reported as is."))
    JuMP.primal_status(model) == MOI.FEASIBLE_POINT || throw(ErrorException(
        "economic_dispatch: HiGHS reports OPTIMAL without a feasible primal point."))
    return Float64[JuMP.value(p[k]) for k in 1:n]
end

# M11 step 1 — the solver half of `dc_opf` (m11-context.md D3). The same settings as
# the dispatch above, and the same split: the problem and its refusals are core's.
function GridSim._dc_opf_solve(::GridSim._HiGHSDispatch, prob, tol::Float64,
                               regularization::Float64)
    nm, n, m = length(prob.a2), prob.n, length(prob.b)
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    JuMP.set_attribute(model, "primal_feasibility_tolerance", tol)
    JuMP.set_attribute(model, "dual_feasibility_tolerance", tol)
    JuMP.set_attribute(model, "optimality_tolerance", tol)
    JuMP.set_attribute(model, "qp_regularization_value", regularization)
    p = JuMP.@variable(model, prob.pmin[k] <= p[k = 1:nm] <= prob.pmax[k])
    θ = JuMP.@variable(model, θ[1:n])
    JuMP.fix(θ[prob.slack], 0.0; force = true)
    flow = [prob.b[e] * (θ[prob.src[e]] - θ[prob.dst[e]]) for e in 1:m]
    # Both directions. An infinite rating writes no row (JuMP would carry ±Inf bounds).
    for e in 1:m
        isfinite(prob.limit[e]) || continue
        JuMP.@constraint(model, -prob.limit[e] <= flow[e] <= prob.limit[e])
    end
    # Balance at EVERY bus: generation − load = what leaves through the branches.
    out = [JuMP.AffExpr(0.0) for _ in 1:n]
    for e in 1:m
        JuMP.add_to_expression!(out[prob.src[e]], flow[e])
        JuMP.add_to_expression!(out[prob.dst[e]], -1.0, flow[e])
    end
    gen = [JuMP.AffExpr(0.0) for _ in 1:n]
    for k in 1:nm
        JuMP.add_to_expression!(gen[prob.gen_bus[k]], p[k])
    end
    JuMP.@constraint(model, [v = 1:n], gen[v] - out[v] == prob.load[v])
    JuMP.@objective(model, Min,
                    sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] for k in 1:nm))
    JuMP.optimize!(model)
    st, ps, ds = JuMP.termination_status(model), JuMP.primal_status(model),
                 JuMP.dual_status(model)
    status = "$st / $ps / $ds"
    if st == MOI.OPTIMAL && ps == MOI.FEASIBLE_POINT
        return (; outcome = :optimal, status,
                  p = Float64[JuMP.value(p[k]) for k in 1:nm],
                  θ = Float64[JuMP.value(θ[v]) for v in 1:n])
    elseif st == MOI.INFEASIBLE && ds == MOI.INFEASIBILITY_CERTIFICATE
        return (; outcome = :infeasible, status, p = Float64[], θ = Float64[])
    end
    throw(ErrorException(
        "dc_opf: HiGHS stopped with $status — neither an optimum nor a certificate " *
        "that no dispatch meets the limits. The problem passed every check in core, so " *
        "this is the solver's refusal, reported as is."))
end

end
