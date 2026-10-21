# M11 step 2 — OUR side only, before any comparison (D8): dc_opf's own convergence on each
# fixture, margin 0, regularization 0. Prints nothing of theirs. Also: does the script's
# `using Printf` load in this environment?
#   julia --project=W:/temp/claude/gridsim-m11-step2/refenv ours_probe.jl
using GridSim, JuMP, HiGHS
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
function rated(net, ratings...)
    d = Dict(ratings)
    br = [Branch(b.id, b.from, b.to, b.X, get(d, b.id, b.rating); R = b.R) for b in net.branches]
    NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads; slack = net.slack)
end
c9() = OutageScreenScript.case9(; costed = true)
fx = [("published", c9()), ("L82 at 100", rated(c9(), :L82 => 100.0)),
      ("L89 at 50", rated(c9(), :L89 => 50.0)), ("L45 L56 at 46", rated(c9(), :L45 => 46.0, :L56 => 46.0))]
for (name, net) in fx, τ in (1e-9,)
    a = dc_opf(net; tol = τ, regularization = 0.0, margin = 0.0)
    b = dc_opf(net; tol = τ / 10, regularization = 0.0, margin = 0.0)
    println(rpad(name, 15), " ", a.outcome, "/", b.outcome, " at_limit ", a.at_limit,
            "  P ", maximum(abs, a.P .- b.P), "  flow ", maximum(abs, a.flow .- b.flow),
            "  cost ", abs(a.cost - b.cost), "  status(τ/1000) ", b.status)
end
r = dc_opf(rated(c9(), :L45 => 40.0, :L56 => 40.0); tol = 1e-9, regularization = 0.0, margin = 0.0)
println("L45 L56 at 40   ", r.outcome, " ", r.status)
