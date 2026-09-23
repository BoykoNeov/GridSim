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

end
