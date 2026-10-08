# M9 step 1 spike: the numbers the new tests will assert, measured before the tests
# are written. Run against the WORKTREE (the edited tier):
#   julia --project=W:/temp/claude/gridsim-m9/wt W:/temp/claude/gridsim-m9/step1/spike.jl
using GridSim, Printf
module OS
include(joinpath(dirname(dirname(pathof(Main.GridSim))), "scripts", "outage_screen.jl"))
end
const FBDF = GridSim.OrdinaryDiffEq.FBDF

losses(eng) = sum(branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
                  for b in eng.model.branches)

println("== end-power identity at the seed: bp(a,b)+bp(b,a) vs ac.loss")
for (nm, f) in (("case9", OS.case9), ("mesh", OS.mesh)), ld in (:constant_power, :default)
    net = f(; loads = ld); sol = ac_powerflow(net)
    eng = init!(DetailedEngine, net; powerflow = sol)
    gap = maximum(abs(branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from) - sol.loss[e])
                  for (e, b) in pairs(net.branches))
    @printf("%-6s %-15s max|end-sum − loss| = %.3e   Σloss = %.6f   gap fwd = %.3e\n", nm, ld, gap,
            sum(sol.loss), maximum(abs(branch_power(eng, b.from, b.to) - sol.flow[e]) for (e, b) in pairs(net.branches)))
end

println("\n== flat runs (seeded, 50 s) and the fixpoint path")
for (nm, f) in (("case9", OS.case9), ("mesh", OS.mesh)), ld in (:constant_power, :default)
    net = f(; loads = ld); sol = ac_powerflow(net)
    for (rt, at) in ((1e-3, 1e-6), (1e-8, 1e-11))
        eng = init!(DetailedEngine, net; powerflow = sol, reltol = rt, abstol = at)
        ser = solve!(eng, (0.0, 50.0); saveat = 0.05)
        w = 0.0; ch = :none
        for c in keys(ser); c === :t && continue; v = getproperty(ser, c)
            d = maximum(abs, v .- v[1]); d > w && ((w, ch) = (d, c)); end
        @printf("%-6s %-15s rtol %.0e  worst drift %.3e on %s\n", nm, ld, rt, w, ch)
    end
    fx = try
        e2 = init!(DetailedEngine, net)
        s2 = solve!(e2, (0.0, 20.0); saveat = 0.05)
        @sprintf("fixpoint ok, f drift %.2e, losses %.6f", maximum(abs, s2.f_coi .- s2.f_coi[1]), losses(e2))
    catch e
        "fixpoint REFUSED: " * first(sprint(showerror, e), 160)
    end
    println("        ", fx)
end

println("\n== t⁺ identity: Σ2H·ω̇ = −(P_lost + ΔL)  (constant power; trip at t0)")
for (nm, f) in (("case9", OS.case9), ("mesh", OS.mesh)), ld in (:constant_power, :default)
    net = f(; loads = ld); sol = ac_powerflow(net)
    ma = machine_arrays(net)
    for (k, m) in pairs(net.machines)
        eng = init!(DetailedEngine, net; powerflow = sol, reltol = 1e-8, abstol = 1e-10, solver = FBDF())
        P_lost = eng.params[eng.Pm_pidx[k]]
        L⁻ = losses(eng)
        try
            inject!(eng, TripGenerator(m.id))
        catch e
            @printf("%-6s %-15s %s  refused at t⁺\n", nm, ld, m.id); continue
        end
        L⁺ = losses(eng)
        H = sum(ma.H[j] for j in eachindex(net.machines) if j != k)
        imb = coi_rocof(eng) * 2H / net.f0
        r = imb + P_lost + (L⁺ - L⁻)
        @printf("%-6s %-15s %s  imb %+.10f  −P_lost %+.10f  ΔL %+.3e  residual %.2e  (w/o ΔL %.2e)\n",
                nm, ld, m.id, imb, -P_lost, L⁺ - L⁻, abs(r), abs(imb + P_lost))
    end
end

println("\n== settled identity: Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw  (constant power)")
for (nm, f) in (("case9", OS.case9), ("mesh", OS.mesh))
    net = f(; loads = :constant_power); sol = ac_powerflow(net)
    acg = ac_generator_outages(net); ma = machine_arrays(net)
    for (k, m) in pairs(net.machines)
        acg.outcome[k] === :secure || (println("$nm $(m.id): AC ", acg.outcome[k]); continue)
        any(acg.capped[k]) && (println("$nm $(m.id): capped"); continue)
        for T in (100.0, 200.0, 400.0)
            eng = init!(DetailedEngine, net; powerflow = sol, reltol = 1e-10, abstol = 1e-12, solver = FBDF())
            r = try
                solve!(eng, (0.0, T); perturbations = [1.0 => TripGenerator(m.id)], saveat = 0.5)
            catch e
                println("$nm $(m.id) T=$T: ", first(sprint(showerror, e), 120)); break
            end
            cs = current_state(eng)
            Δω_dyn = r.f_coi[end] / net.f0 - 1
            tail = abs(r.f_coi[end] - r.f_coi[end-20]) / net.f0
            L_dyn = losses(eng); L_ac = sum(acg.solution[k].loss)
            Σw = sum(ma.invR[j] + ma.D[j] for j in eachindex(net.machines) if j != k)
            lhs = Δω_dyn - acg.Δω[k]; rhs = -(L_dyn - L_ac) / Σw
            @printf("%-6s %s T=%3.0f Δω_dyn %+.12f Δω_AC %+.12f  lhs %+.3e rhs %+.3e  resid %.2e  tail(10s) %.1e\n",
                    nm, m.id, T, Δω_dyn, acg.Δω[k], lhs, rhs, abs(lhs - rhs), tail)
        end
    end
end
