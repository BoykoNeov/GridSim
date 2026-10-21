# M11 step 3 — does Ipopt resolve in the ROOT environment's own copy (Project.toml +
# Manifest.toml), and what moves? Two adds, in order: Ipopt alone (the new weak
# dependency), then JuMP + HiGHS beside it (the test target's set).
#   julia --project=W:/temp/claude/gridsim-m11-step3/rootenv resolve.jl
import Pkg
vers() = Dict(i.name => i.version for (_, i) in Pkg.dependencies())
function report(before, after, label)
    println("\n== ", label, ": packages ", length(before), " -> ", length(after))
    for n in sort(collect(keys(before)))
        haskey(after, n) || (println("REMOVED  ", n, " ", before[n]); continue)
        before[n] == after[n] || println("MOVED    ", n, " ", before[n], " -> ", after[n])
    end
end
v0 = vers()
Pkg.add("Ipopt")
v1 = vers()
report(v0, v1, "Ipopt alone")
Pkg.add(["JuMP", "HiGHS"])
v2 = vers()
report(v1, v2, "+ JuMP + HiGHS")
for n in ("Ipopt", "Ipopt_jll", "JuMP", "HiGHS", "MathOptInterface")
    println("added    ", n, " ", get(v2, n, "absent"))
end
for n in ("NetworkDynamics", "OrdinaryDiffEq", "NonlinearSolve", "NonlinearSolveBase", "SciMLBase",
          "Graphs", "Observables", "CommonSolve")
    println("ours     ", n, " ", get(v0, n, "absent"), " -> ", get(v2, n, "absent"))
end
using JuMP, Ipopt
m = Model(Ipopt.Optimizer); set_silent(m)
@variable(m, x >= 0.5); @objective(m, Min, (x - 2)^2 + sin(x)); optimize!(m)
println("Ipopt smoke: ", termination_status(m), " x = ", value(x))
