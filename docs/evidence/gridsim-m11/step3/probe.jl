# M11 step 3 — runs made BEFORE the predictions, one side at a time (never the OPF
# handed to the power flow, never two starts compared):
#   A. the power flow alone: M6's network-free dispatch handed to `ac_powerflow` at
#      published load, both load models — the 24.2 feasibility facts; at 1.5x — the 24.3
#      control's B9 on the EXACT dispatch; and the Jacobian's inverse norm at each.
#   B. the optimiser alone: statuses, at_band/at_limit/q_at_limit, and its own
#      convergence |run(1e-8) - run(tight)| on every fixture; the rating-fixture search.
#   julia --project=W:/temp/claude/gridsim-m11-step3/probeenv probe.jl
using GridSim, JuMP, HiGHS, Ipopt, Printf, LinearAlgebra
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const c9 = OutageScreenScript.case9
const S = 100.0

# The power flow's Jacobian at a solved point, by central differences on core's own
# residual (no comparison: one side's conditioning).
function jac_inv_norm(net)
    c, _ = GridSim._ac_first_round(net)
    sol = ac_powerflow(net)
    x = vcat([sol.θ[v] for v in c.nonslack], [sol.Vm[v] for v in c.pq])
    N = length(x); J = zeros(N, N); F1 = zeros(N); F2 = zeros(N); h = 1e-7
    for j in 1:N
        xp = copy(x); xp[j] += h; xm = copy(x); xm[j] -= h
        GridSim._ac_residual!(F1, xp, c); GridSim._ac_residual!(F2, xm, c)
        J[:, j] = (F1 .- F2) ./ (2h)
    end
    return opnorm(inv(J), Inf), N
end

# The same at an unchecked solve (for a dispatch the band refuses: the 1.5x control).
function jac_inv_norm_raw(net)
    c, x0 = GridSim._ac_first_round(net)
    x, _ = GridSim._ac_newton(c, x0, 1e-12, 200)
    N = length(x); J = zeros(N, N); F1 = zeros(N); F2 = zeros(N); h = 1e-7
    for j in 1:N
        xp = copy(x); xp[j] += h; xm = copy(x); xm[j] -= h
        GridSim._ac_residual!(F1, xp, c); GridSim._ac_residual!(F2, xm, c)
        J[:, j] = (F1 .- F2) ./ (2h)
    end
    Vm, θ = GridSim._ac_expand(c, x)
    return opnorm(inv(J), Inf), Vm
end

println("== A. the power flow alone")
for loads in (:constant_power, :default)
    net = c9(; costed = true, loads)
    ed = economic_dispatch(net; regularization = 0.0)
    g = dispatch_loss_gap(net, ed)
    f = g.flow
    println("-- published, loads = $loads: M6 dispatch MW ", round.(ed.P .* S; digits = 6),
            " cost_flowed ", @sprintf("%.6f", g.cost_flowed))
    # 24.2 feasibility facts, on the flowed point
    ms = net.machines
    for (k, m) in pairs(ms)
        v = net.bus_index[m.bus]
        @printf("   %s  P %.6f MW in [%.1f, %.1f]   Q %.6f MVAr in [%.0f, %.0f]\n", m.id,
                f.Pgen[v] * S, m.Pmin, m.Pmax, f.Qgen[v] * S, m.Q_min * S, m.Q_max * S)
    end
    @printf("   min |V| %.9f at %s, max |V| %.9f\n", minimum(f.Vm), f.buses[argmin(f.Vm)], maximum(f.Vm))
    mva = [max(hypot(f.flow[e], f.qflow[e]), hypot(f.flow_rev[e], f.qflow_rev[e])) for e in eachindex(f.flow)]
    worst = argmax(mva .* S ./ [b.rating for b in net.branches])
    @printf("   worst loading %s %.4f / %.0f MVA;  losses %.6f MW, load_shift %.6f MW\n",
            f.branches[worst], mva[worst] * S, net.branches[worst].rating, g.losses * S, g.load_shift * S)
    κ, N = jac_inv_norm(dispatch_schedule(net, ed))
    @printf("   ‖J⁻¹‖∞ = %.4f  (N = %d)\n", κ, N)
end
for loads in (:constant_power, :default)
    net = c9(; costed = true, loads, mw = 1.5 * 315)
    d = dc_opf(net; regularization = 0.0)
    r = GridSim._ac_powerflow_outcome(dispatch_schedule(net, d))
    println("-- 1.5x, loads = $loads: DC OPF dispatch MW ", round.(d.P .* S; digits = 6),
            " at_limit ", d.at_limit, " -> ac_powerflow :", r.outcome)
    r.outcome === :voltage && for l in r.detail
        @printf("   %s |V| = %.9f\n", l.bus, l.Vm)
    end
    κ, Vm = jac_inv_norm_raw(dispatch_schedule(net, d))
    @printf("   unchecked solve: min |V| %.9f;  ‖J⁻¹‖∞ = %.4f\n", minimum(Vm), κ)
end

println("\n== B. the optimiser alone")
show_r(r) = r.outcome === :locally_optimal ?
    @printf("   %s  cost %.9f  P MW %s\n   at_band %s  at_limit %s  q_at_limit %s  min|V| %.10f  residual %.2e  losses %.6f MW  shift %.6f MW\n",
            r.status, r.cost, string(round.(r.P .* S; digits = 6)), r.at_band, r.at_limit,
            r.q_at_limit, minimum(r.Vm), r.residual, r.losses * S, r.load_shift * S) :
    println("   ", r.outcome, "  ", r.status)
conv(a, b) = a.outcome === b.outcome === :locally_optimal ?
    @printf("   own convergence |1e-8 − tight|: P %.2e  Vm %.2e  θ %.2e  flow %.2e  cost %.2e\n",
            maximum(abs, a.P .- b.P), maximum(abs, a.Vm .- b.Vm), maximum(abs, a.θ .- b.θ),
            maximum(abs, a.flow .- b.flow), abs(a.cost - b.cost)) : nothing

fixtures = [("published cp", () -> c9(; costed = true)),
            ("published default", () -> c9(; costed = true, loads = :default)),
            ("1.5x cp", () -> c9(; costed = true, mw = 1.5 * 315)),
            ("1.5x default", () -> c9(; costed = true, mw = 1.5 * 315, loads = :default)),
            ("1.75x cp", () -> c9(; costed = true, mw = 1.75 * 315)),
            ("1.75x default", () -> c9(; costed = true, mw = 1.75 * 315, loads = :default))]
for (label, mk) in fixtures
    net = mk()
    println("-- ", label)
    rs = Dict{Float64,Any}()
    for τ in (1e-8, 1e-10, 1e-11)
        rs[τ] = try
            ac_opf(net; tol = τ)
        catch err
            println("   tol $τ THREW: ", sprint(showerror, err)[1:min(end, 200)]); nothing
        end
    end
    rs[1e-10] === nothing || show_r(rs[1e-10])
    for τt in (1e-10, 1e-11)
        (rs[1e-8] !== nothing && rs[τt] !== nothing) && (print("   vs $τt:"); conv(rs[1e-8], rs[τt]))
    end
end
println("-- 1.75x cp, floor lowered to 0.8")
show_r(ac_opf(c9(; costed = true, mw = 1.75 * 315); tol = 1e-10, vmin = 0.8))
println("-- 1.75x cp, reactive limits removed")
let net = c9(; costed = true, mw = 1.75 * 315)
    ms = [GridSim._machine_with(m; Q_min = -Inf, Q_max = Inf) for m in net.machines]
    n2 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads; slack = net.slack)
    show_r(ac_opf(n2; tol = 1e-10))
end
println("-- the DC start, published cp and 1.5x cp (statuses only, no comparison)")
for mw in (315.0, 1.5 * 315)
    net = c9(; costed = true, mw)
    r = ac_opf(net; tol = 1e-10, start = dc_opf(net; regularization = 0.0))
    println("   ", r.outcome, " ", r.status)
end

println("\n== B2. the rating fixture: each ring line at the unconstrained AC optimum (published, cp)")
let net = c9(; costed = true)
    r = ac_opf(net; tol = 1e-10)
    for (e, id) in pairs(r.branches)
        @printf("   %s  |S_from| %.4f  |S_to| %.4f MVA  (rating %.0f)\n", id,
                hypot(r.flow[e], r.qflow[e]) * S, hypot(r.flow_rev[e], r.qflow_rev[e]) * S,
                net.branches[e].rating)
    end
end
