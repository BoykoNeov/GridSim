# M10 step 3 — are case9's constant-power "no solution" pieces a voltage collapse, or a
# solve started in the wrong place? Probed on G1+G2 (G3 alone left), with the whole case
# (loads and schedule together) scaled from 315 MW down, through the same per-piece solve
# the screen runs. A flat start every time, as the screen does.
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m10/step3_collapse_probe.jl > step3_collapse_probe.out.txt
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const S = OutageScreenScript

for loads in (:constant_power, :default)
    println("== G1+G2 lost, $loads loads")
    for mw in (315.0, 300.0, 290.0, 280.0, 270.0, 260.0, 250.0, 240.0, 220.0, 200.0, 150.0, 100.0)
        net = S.case9(; loads, mw)
        base = ac_powerflow(net)
        st = GridSim._ac_piece_setup(net, base, [1, 2], collect(1:9), Int[], 1)
        o = GridSim._ac_piece_solve(net, st)
        Vmin = o.solution !== nothing ? minimum(o.solution.Vm) :
               o.outcome === :voltage ? minimum(l.Vm for l in o.detail) : NaN
        @printf("  %5.0f MW  %-12s Δω %12.5e   min |V| %.4f   G3 capped %s\n", mw, o.outcome,
                o.Δω, Vmin, o.capped[3])
    end
end
