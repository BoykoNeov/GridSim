# M11 step 2 — does PowerModels + Ipopt + JuMP + HiGHS resolve in reference/'s OWN
# environment (a scratch copy of its Project.toml + Manifest.toml), and what moves?
#   julia --project=W:/temp/claude/gridsim-m11-step2/refenv resolve.jl
import Pkg
vers() = Dict(i.name => i.version for (_, i) in Pkg.dependencies())
before = vers()
Pkg.add(["PowerModels", "Ipopt", "JuMP", "HiGHS"])
after = vers()
println("\npackages: ", length(before), " -> ", length(after))
for n in sort(collect(keys(before)))
    haskey(after, n) || (println("REMOVED  ", n, " ", before[n]); continue)
    before[n] == after[n] || println("MOVED    ", n, " ", before[n], " -> ", after[n])
end
for n in ("PowerModels", "Ipopt", "JuMP", "HiGHS", "Ipopt_jll", "HiGHS_jll", "NLsolve", "MathOptInterface")
    println("added    ", n, " ", get(after, n, "absent"))
end
for n in ("GridSim", "NetworkDynamics", "OrdinaryDiffEq", "PowerDynamics", "PowerFlows", "PowerSystems",
          "NonlinearSolve", "NonlinearSolveBase", "SciMLBase", "TimerOutputs")
    println("ours     ", n, " ", get(before, n, "absent"), " -> ", get(after, n, "absent"))
end
