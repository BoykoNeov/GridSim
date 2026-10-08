import Pkg
Pkg.activate("W:/temp/claude/gridsim-m6-resolve/b")
# Our stack first, at the versions M5 closed on.
Pkg.add([Pkg.PackageSpec(name="NetworkDynamics", version="1.3.0"),
         Pkg.PackageSpec(name="OrdinaryDiffEq"),
         Pkg.PackageSpec(name="SciMLBase"),
         Pkg.PackageSpec(name="Graphs"),
         Pkg.PackageSpec(name="Observables"),
         Pkg.PackageSpec(name="CommonSolve")])
m0 = Pkg.Operations.Context().env.manifest
base = Dict(e.name => e.version for (_, e) in m0)
println("BEFORE count = ", length(m0))
for n in ("SciMLBase","OrdinaryDiffEq","NetworkDynamics")
    println("BEFORE ", n, " = ", get(base, n, nothing))
end
println("--- now adding PowerSystems + PowerFlows ---")
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
for n in ("SciMLBase","OrdinaryDiffEq","NetworkDynamics","PowerSystems","PowerFlows")
    println("AFTER ", n, " = ", get(after, n, nothing))
end
println("--- packages whose version MOVED ---")
for (n, v) in sort(collect(base), by = first)
    v2 = get(after, n, nothing)
    if v2 !== v
        println("MOVED ", n, ": ", v, " -> ", v2)
    end
end
