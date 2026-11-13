using GridSim
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
function capped()
    net = OutageScreenScript.case9(; loads = :default)
    ms = [k == 1 ? GridSim._machine_with(m; Pmax = m.P0 + 10.0) : m for (k, m) in pairs(net.machines)]
    NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads; slack = net.slack)
end
net = capped(); base = ac_powerflow(net)
s = ac_generator_outages(net); k2 = findfirst(m -> m.id === :G2, net.machines)
println("screen Δω = ", repr(s.Δω[k2]), " capped ", s.capped[k2])
for (nm, kw) in (("Rodas5P", (;)), ("FBDF", (; solver = OrdinaryDiffEq.FBDF())),
                 ("FBDF dtmax.01", (; solver = OrdinaryDiffEq.FBDF(), dtmax = 0.01)),
                 ("Rodas5P 1e-10", (; reltol = 1e-10, abstol = 1e-12)))
    eng = init!(DetailedEngine, net; powerflow = base, kw...)
    hr1 = eng.params[eng.hr_pidx[1]]
    solve!(eng, (0.0, 1.0)); inject!(eng, TripGenerator(:G2))
    mx = -Inf
    t = @elapsed for T in 1.5:0.5:60.0
        solve!(eng, (T - 0.5, T)); global st = current_state(eng); mx = max(mx, st.ΔPm[1] - hr1)
    end
    println(rpad(nm, 16), " max(ΔPm-hr)=", mx, " end ΔPm-hr=", st.ΔPm[1] - hr1, " ω1=", repr(st.ω[1]), "  ", round(t; digits = 2), " s")
end
