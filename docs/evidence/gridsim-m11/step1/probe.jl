# M11 step 1 — pre-prediction probes (NOT comparisons; D8):
#  (a) our dc_powerflow's branch flows at economic_dispatch's schedule on case9 (to pick 22.3's line)
#  (b) does HiGHS solve the θ formulation at qp_regularization_value = 0? status only
#  (c) what statuses HiGHS reports on a hand-provable infeasible fixture
using GridSim, JuMP, HiGHS
const MOI = JuMP.MOI
const _C9 = ((c2 = 0.11,   c1 = 5.0, c0 = 150.0, Pmin = 10.0, Pmax = 250.0),
             (c2 = 0.085,  c1 = 1.2, c0 = 600.0, Pmin = 10.0, Pmax = 300.0),
             (c2 = 0.1225, c1 = 1.0, c0 = 335.0, Pmin = 10.0, Pmax = 270.0))
function c9(; load = 315.0, ratings = Dict{Symbol,Float64}())
    s = load / 315.0
    buses = [Bus(Symbol(:B, i), 345.0) for i in 1:9]
    rows = [(:L14, 1, 4, 0.0, 0.0576, 250.0), (:L45, 4, 5, 0.017, 0.092, 250.0),
            (:L56, 5, 6, 0.039, 0.17, 150.0), (:L36, 3, 6, 0.0, 0.0586, 300.0),
            (:L67, 6, 7, 0.0119, 0.1008, 150.0), (:L78, 7, 8, 0.0085, 0.072, 250.0),
            (:L82, 8, 2, 0.0, 0.0625, 250.0), (:L89, 8, 9, 0.032, 0.161, 250.0),
            (:L94, 9, 4, 0.01, 0.085, 250.0)]
    br = [Branch(id, Symbol(:B, f), Symbol(:B, t), x, get(ratings, id, rate); R = r)
          for (id, f, t, r, x, rate) in rows]
    ΣPmax = sum(r.Pmax for r in _C9)
    ms = [Machine(Symbol(:G, i), Symbol(:B, i), 100.0, 5.0, 0.0, 0.2, 1.0,
                  load * _C9[i].Pmax / ΣPmax, Inf, _C9[i].Pmax;
                  cost_c2 = _C9[i].c2, cost_c1 = _C9[i].c1, cost_c0 = _C9[i].c0,
                  Pmin = _C9[i].Pmin) for i in 1:3]
    ls = [Load(:D5, :B5, 90.0s, 30.0s, 0.0, 0.0, 1.0), Load(:D7, :B7, 100.0s, 35.0s, 0.0, 0.0, 1.0),
          Load(:D9, :B9, 125.0s, 50.0s, 0.0, 0.0, 1.0)]
    NetworkModel(100.0, 50.0, buses, br, ms, ls; slack = :B1)
end

println("(a) dc_powerflow at economic_dispatch's schedule, case9 315 MW (MW, branch orientation):")
net = c9()
ed = economic_dispatch(net)
f = dc_powerflow(dispatch_schedule(net, ed))
for (e, b) in pairs(net.branches)
    println("  ", b.id, " ", b.from, "→", b.to, "  ", round(100f.flow[e], digits = 4), " MW  (rating ", b.rating, ")")
end

function θmodel(net, reg; tol = 1e-9)
    S = net.S_base; ca = cost_arrays(net); topo = branch_topology(net); la = load_arrays(net)
    n = length(net.buses); nm = length(ca.a2); m = length(topo.src)
    model = JuMP.Model(HiGHS.Optimizer); JuMP.set_silent(model)
    for a in ("primal_feasibility_tolerance", "dual_feasibility_tolerance", "optimality_tolerance")
        JuMP.set_attribute(model, a, tol)
    end
    JuMP.set_attribute(model, "qp_regularization_value", reg)
    @variable(model, ca.pmin[k] <= p[k = 1:nm] <= ca.pmax[k])
    @variable(model, θ[1:n])
    JuMP.fix(θ[net.bus_index[net.slack]], 0.0; force = true)
    b = inv.(topo.X)
    flow = [b[e] * (θ[topo.src[e]] - θ[topo.dst[e]]) for e in 1:m]
    rate = [br.rating / S for br in net.branches]
    @constraint(model, [e = 1:m], -rate[e] <= flow[e] <= rate[e])
    inj = [JuMP.AffExpr(0.0) for _ in 1:n]
    for (k, mm) in pairs(net.machines); JuMP.add_to_expression!(inj[net.bus_index[mm.bus]], p[k]); end
    for k in eachindex(la.bus); JuMP.add_to_expression!(inj[la.bus[k]], -la.P[k]); end
    for e in 1:m
        JuMP.add_to_expression!(inj[topo.src[e]], -flow[e]); JuMP.add_to_expression!(inj[topo.dst[e]], flow[e])
    end
    @constraint(model, [v = 1:n], inj[v] == 0)
    @objective(model, Min, sum(ca.a2[k] * p[k]^2 + ca.a1[k] * p[k] for k in 1:nm))
    JuMP.optimize!(model)
    (JuMP.termination_status(model), JuMP.primal_status(model), JuMP.dual_status(model))
end

println("\n(b) θ formulation, status only:")
for (name, nn) in (("case9 published", c9()), ("case9 L82 at 100 MVA", c9(; ratings = Dict(:L82 => 100.0))),
                   ("case9 L45 at 30 MVA", c9(; ratings = Dict(:L45 => 30.0))))
    for reg in (0.0, 1e-7)
        println("  ", name, " reg=", reg, ": ", θmodel(nn, reg))
    end
end

println("\n(c) B5 (90 MW) fed only by L45 + L56, both at 40 MVA (80 < 90): statuses")
println("  ", θmodel(c9(; ratings = Dict(:L45 => 40.0, :L56 => 40.0)), 1e-7))
println("  ", θmodel(c9(; ratings = Dict(:L45 => 40.0, :L56 => 40.0)), 0.0))
