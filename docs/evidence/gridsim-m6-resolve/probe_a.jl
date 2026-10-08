import Pkg
Pkg.activate("W:/temp/claude/gridsim-m6-resolve/a")
Pkg.add(["PowerSystems", "PowerFlows"])
Pkg.status()
m = Pkg.Operations.Context().env.manifest
println("PACKAGE_COUNT_A = ", length(m))
for (_, e) in m
    if e.name in ("PowerSystems","PowerFlows","SciMLBase","OrdinaryDiffEq","NetworkDynamics","InfrastructureSystems")
        println("VER ", e.name, " = ", e.version)
    end
end
