import Pkg
for (label, proj) in [("root now", raw"W:\Claude_projects\GridSim"), ("core+PM", raw"W:\temp\claude\gridsim-m11-resolve\core"),
                      ("core_test+PM", raw"W:\temp\claude\gridsim-m11-resolve\core_test"),
                      ("reference now", raw"W:\Claude_projects\GridSim\reference"), ("reference+PM", raw"W:\temp\claude\gridsim-m11-resolve\reference")]
    Pkg.activate(proj; io = devnull)
    d = Dict(x.name => x.version for x in values(Pkg.dependencies()))
    println(rpad(label, 15), length(d), " pkgs | ", join(["$k $(get(d, k, "-"))" for k in
        ("NonlinearSolve", "NonlinearSolveBase", "SciMLBase", "OrdinaryDiffEq", "NetworkDynamics", "JuMP", "HiGHS", "MathOptInterface", "PowerDynamics", "PowerSystems", "PowerFlows", "ForwardDiff", "TimerOutputs")], ", "))
end
Pkg.activate(raw"W:\temp\claude\gridsim-m11-resolve\alone"; io = devnull)
pm = pkgdir(Base.require(Base.PkgId(Base.UUID("c36e90e8-916a-50a6-bd94-075b64ef4655"), "PowerModels")))
println("PowerModels dir: ", pm)
println(filter(l -> occursin("julia", l), readlines(joinpath(pm, "Project.toml"))))
println(readdir(joinpath(pm, "test", "data", "matpower"))[1:min(end, 60)])
