using GridSim, Printf
const ODE = GridSim.OrdinaryDiffEq
module S; include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl"); end
for extra in (10.0, 2.0)
    net0 = S.case9(; loads = :default)
    ms = [k == 1 ? GridSim._machine_with(m; Pmax = m.P0 + extra) : m for (k, m) in pairs(net0.machines)]
    net = NetworkModel(net0.S_base, net0.f0, net0.buses, net0.branches, ms, net0.loads; slack = net0.slack)
    base = ac_powerflow(net)
    eng = init!(DetailedEngine, net; powerflow = base, solver = (extra == 10.0 ? ODE.Rodas5P() : ODE.FBDF()), dtmax = (extra == 10.0 ? Inf : 0.01))
    hr = eng.params[eng.hr_pidx[1]]; Pm = eng.params[eng.Pm_pidx[1]]
    @printf("extra %.0f MW: hr %.6f  Pm0 %.6f  Pm0+hr %.6f  Pmax/S %.6f\n", extra, hr, Pm, Pm + hr, ms[1].Pmax / 100)
    solve!(eng, (0.0, 1.0)); inject!(eng, TripGenerator(:G2))
    for t in (2.0, 5.0, 10.0, 20.0, 30.0, 60.0)
        solve!(eng, (eng.integrator.t, t)); st = current_state(eng)
        @printf("  t %5.1f  ΔPm1 %.6f  (hr − ΔPm %+.2e)  ω1 %+.3e\n", t, st.ΔPm[1], hr - st.ΔPm[1], st.ω[1])
    end
end
