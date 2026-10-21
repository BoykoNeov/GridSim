# M11 step 3 — the solver half of `ac_opf` (m11-context.md D4, D6).
#
# A package extension on JuMP + Ipopt, apart from the dispatch's HiGHS one: a session that
# never optimises in AC does not load an interior-point solver (M6 D16 §4). The problem
# and every refusal are core's (`src/steadystate/ac_opf.jl`); this file writes the
# optimiser's constraints and hands back the decisions.
#
# THE AC EQUATIONS HERE ARE A SECOND, HAND-WRITTEN COPY, and that is why the answer is
# handed back to `ac_powerflow` (Hurdle 24.1). They are written in BRANCH form — each
# branch's power at each end from its series admittance `y = g + jb`, summed per bus —
# where the power flow writes bus-admittance form; and each load's draw is the
# polynomial `a_z|V|² + a_i|V| + a_p` where core uses `_zip_scale`. For a branch `f → t`
# with `θ_ft = θ_f − θ_t`, `S_f = V_f·conj(y·(V_f − V_t))`:
#
#     P_f =  g·V_f² − V_f·V_t·(g·cos θ_ft + b·sin θ_ft)
#     Q_f = −b·V_f² − V_f·V_t·(g·sin θ_ft − b·cos θ_ft)
#
# and the `t` end with `f` and `t` swapped.
module GridSimOPFExt

using GridSim
using JuMP: JuMP, MOI
using Ipopt: Ipopt

function GridSim._ac_opf_solve(::GridSim._IpoptOPF, prob, tol::Float64, x0, max_iter::Int)
    nm, n, m = length(prob.a2), prob.n, length(prob.g)
    model = JuMP.Model(Ipopt.Optimizer)
    JuMP.set_silent(model)
    # Option names read from Ipopt's own options reference. Every convergence measure gets
    # `tol`, so the band derived from it has one input; bound relaxation is off, so a
    # bounded variable is inside its (margined) bound by the interior point's own
    # construction rather than to a relaxed `1e-8`.
    JuMP.set_attribute(model, "tol", tol)
    JuMP.set_attribute(model, "constr_viol_tol", tol)
    JuMP.set_attribute(model, "dual_inf_tol", tol)
    JuMP.set_attribute(model, "compl_inf_tol", tol)
    JuMP.set_attribute(model, "bound_relax_factor", 0.0)
    JuMP.set_attribute(model, "max_iter", max_iter)
    p = JuMP.@variable(model, prob.pmin[k] <= p[k = 1:nm] <= prob.pmax[k],
                       start = x0.p[k])
    θ = JuMP.@variable(model, θ[v = 1:n], start = x0.θ[v])
    JuMP.fix(θ[prob.slack], 0.0; force = true)
    held = [!isnan(prob.V_set[v]) for v in 1:n]
    # A held bus's magnitude is a constant, not a fixed variable: nothing for the solver
    # to move, and nothing for a bound to be relaxed on.
    Vfree = Dict(v => JuMP.@variable(model, lower_bound = prob.vlo, upper_bound = prob.vhi,
                                     start = x0.Vm[v], base_name = "V[$v]")
                 for v in 1:n if !held[v])
    V(v) = held[v] ? prob.V_set[v] : Vfree[v]
    qg = Dict{Int,JuMP.VariableRef}()
    for v in 1:n
        held[v] || continue
        q = JuMP.@variable(model, start = 0.0, base_name = "qg[$v]")
        isfinite(prob.Q_min[v]) && JuMP.set_lower_bound(q, prob.Q_min[v])
        isfinite(prob.Q_max[v]) && JuMP.set_upper_bound(q, prob.Q_max[v])
        qg[v] = q
    end
    # The branch powers at both ends.
    Pf = Vector{Any}(undef, m); Qf = Vector{Any}(undef, m)
    Pt = Vector{Any}(undef, m); Qt = Vector{Any}(undef, m)
    for e in 1:m
        f, t, g, b = prob.src[e], prob.dst[e], prob.g[e], prob.b[e]
        Vf, Vt = V(f), V(t)
        Pf[e] = JuMP.@expression(model,  g * Vf^2 - Vf * Vt * (g * cos(θ[f] - θ[t]) + b * sin(θ[f] - θ[t])))
        Qf[e] = JuMP.@expression(model, -b * Vf^2 - Vf * Vt * (g * sin(θ[f] - θ[t]) - b * cos(θ[f] - θ[t])))
        Pt[e] = JuMP.@expression(model,  g * Vt^2 - Vt * Vf * (g * cos(θ[t] - θ[f]) + b * sin(θ[t] - θ[f])))
        Qt[e] = JuMP.@expression(model, -b * Vt^2 - Vt * Vf * (g * sin(θ[t] - θ[f]) - b * cos(θ[t] - θ[f])))
        # The rating at BOTH ends; an infinite one writes no row.
        if isfinite(prob.limit[e])
            JuMP.@constraint(model, Pf[e]^2 + Qf[e]^2 <= prob.limit[e]^2)
            JuMP.@constraint(model, Pt[e]^2 + Qt[e]^2 <= prob.limit[e]^2)
        end
    end
    # Balance at every bus: generation − the loads' draw = what leaves into the branches.
    for v in 1:n
        Pout = sum((Pf[e] for e in 1:m if prob.src[e] == v); init = 0.0) +
               sum((Pt[e] for e in 1:m if prob.dst[e] == v); init = 0.0)
        Qout = sum((Qf[e] for e in 1:m if prob.src[e] == v); init = 0.0) +
               sum((Qt[e] for e in 1:m if prob.dst[e] == v); init = 0.0)
        Pgen = sum((p[k] for k in 1:nm if prob.gen_bus[k] == v); init = 0.0)
        Qgen = held[v] ? qg[v] : 0.0
        Vv = V(v)
        Pl = sum((prob.load_P[k] * (prob.load_az[k] * Vv^2 + prob.load_ai[k] * Vv + prob.load_ap[k])
                  for k in eachindex(prob.load_bus) if prob.load_bus[k] == v); init = 0.0)
        Ql = sum((prob.load_Q[k] * (prob.load_az[k] * Vv^2 + prob.load_ai[k] * Vv + prob.load_ap[k])
                  for k in eachindex(prob.load_bus) if prob.load_bus[k] == v); init = 0.0)
        JuMP.@constraint(model, Pgen - Pl - Pout == 0)
        JuMP.@constraint(model, Qgen - Ql - Qout == 0)
    end
    JuMP.@objective(model, Min, sum(prob.a2[k] * p[k]^2 + prob.a1[k] * p[k] for k in 1:nm))
    JuMP.optimize!(model)
    st, ps, ds = JuMP.termination_status(model), JuMP.primal_status(model),
                 JuMP.dual_status(model)
    status = "$st / $ps / $ds"
    if st == MOI.LOCALLY_SOLVED && ps == MOI.FEASIBLE_POINT
        return (; outcome = :locally_optimal, status,
                  p = Float64[JuMP.value(p[k]) for k in 1:nm],
                  θ = Float64[JuMP.value(θ[v]) for v in 1:n],
                  Vm = Float64[held[v] ? prob.V_set[v] : JuMP.value(Vfree[v]) for v in 1:n])
    elseif st == MOI.LOCALLY_INFEASIBLE
        return (; outcome = :locally_infeasible, status, p = Float64[], θ = Float64[],
                  Vm = Float64[])
    end
    throw(ErrorException(
        "ac_opf: Ipopt stopped with $status — neither a local optimum with a feasible " *
        "point nor its word that no feasible point was found nearby. The problem passed " *
        "every check in core, so this is the solver's refusal, reported as is."))
end

end
