# M11 step 0: does an outside network-OPF checker resolve, alone and against our stack?
import Pkg
const R = raw"W:\temp\claude\gridsim-m11-resolve"
const G = raw"W:\Claude_projects\GridSim"
function trial(name, setup)
    dir = joinpath(R, name); mkpath(dir)
    println("\n===== ", name); flush(stdout)
    Pkg.activate(dir; io = devnull)
    try
        setup()
        deps = Pkg.dependencies()
        for k in ("PowerModels", "Ipopt", "JuMP", "NLsolve", "NonlinearSolve", "GridSim",
                  "PowerDynamics", "PowerSystems", "OrdinaryDiffEq", "SciMLBase", "InfrastructureModels")
            v = [d for d in values(deps) if d.name == k]
            isempty(v) || println("  ", k, " ", v[1].version)
        end
        println("  RESOLVED, ", length(deps), " packages")
    catch e
        msg = sprint(showerror, e)
        println("  FAILED:\n", join(last(split(msg, '\n'), 40), '\n'))
    end
    flush(stdout)
end
which = isempty(ARGS) ? ["alone", "core", "reference", "core_test"] : ARGS
"alone" in which && trial("alone", () -> Pkg.add(["PowerModels", "Ipopt"]))
"core" in which && trial("core", () -> (Pkg.develop(path = G); Pkg.add(["PowerModels", "Ipopt"])))
"reference" in which && trial("reference", () -> (Pkg.develop(path = G);
    Pkg.develop(path = joinpath(G, "reference")); Pkg.add(["PowerModels", "Ipopt"])))
"core_test" in which && trial("core_test", () -> (Pkg.develop(path = G);
    Pkg.add(["JuMP", "HiGHS", "PowerModels", "Ipopt"])))
