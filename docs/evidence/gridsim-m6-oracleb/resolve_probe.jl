import Pkg
Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
Pkg.instantiate()
m0 = Pkg.Operations.Context().env.manifest
base = Dict(e.name => e.version for (_, e) in m0)
println("BEFORE count = ", length(m0))
for n in ("SciMLBase","OrdinaryDiffEq","NetworkDynamics","PowerDynamics","GridSim","Graphs")
    println("BEFORE ", n, " = ", get(base, n, nothing))
end
println("--- adding PowerSystems + PowerFlows ---")
try
    Pkg.add(["PowerSystems", "PowerFlows"])
catch err
    println("RESOLVE_FAILED")
    showerror(stdout, err); println()
    exit(0)
end
m1 = Pkg.Operations.Context().env.manifest
after = Dict(e.name => e.version for (_, e) in m1)
println("AFTER count = ", length(m1))
for n in ("SciMLBase","OrdinaryDiffEq","NetworkDynamics","PowerDynamics","PowerSystems","PowerFlows")
    println("AFTER ", n, " = ", get(after, n, nothing))
end
println("--- MOVED ---")
moved = 0
for (n, v) in sort(collect(base), by = first)
    v2 = get(after, n, nothing)
    if v2 !== v
        println("MOVED ", n, ": ", v, " -> ", v2); moved += 1
    end
end
println("moved_total = ", moved)
