# M10 step 2: is the swing case9 gap the solver tolerance or unfinished settling? Same pairs at
# two tolerances, read at four times. julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Test
const Graphs = GridSim.Graphs
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const _M10_MESH = OutageScreenScript.mesh
const _M10_CASE9 = OutageScreenScript.case9
src = read(raw"W:\Claude_projects\GridSim\test\m10_double_outages.jl", String)
i = findfirst("# case9 shaped for the swing tier", src).start
j = findfirst("@testset \"M10 step 2", src).start
include_string(Main, src[i:j-1])
net = _m10_swing_case9(); s = dc_pair_outages(net)
for (a, b) in ((:L67, :G1), (:L45, :L94))
    p = _m10_pair(s, a, b); surv = _m10_survivors(net, s, p); evs = _m10_events(net, s, p)
    for rt in (1e-10, 1e-12)
        eng = SwingEngine(net; reltol = rt, abstol = rt / 100, dt = 0.05)
        foreach(ev -> inject!(eng, ev), evs)
        for T in (150.0, 300.0, 450.0, 900.0)
            while eng.integrator.t < T - 1e-9; step!(eng, 0.05); end
            st = current_state(eng)
            g = maximum(abs(st.ω[v] - pc.Δω) for (v, _, pc) in surv)
            println(a, "+", b, " reltol ", rt, " t ", T, " max ω gap ", g)
        end
    end
end
