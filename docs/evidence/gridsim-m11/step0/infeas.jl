# run with --project=W:/temp/claude/gridsim-m11-resolve/core
using GridSim, PowerModels, Ipopt, JuMP
PowerModels.silence()
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
opt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0, "tol" => 1e-10)
base = PowerModels.parse_file(raw"W:\temp\claude\gridsim-m11-resolve\data\case9.m")
for (_, b) in base["branch"]; b["b_fr"] = 0.0; b["b_to"] = 0.0; end
for (i, v) in ((1, 1.04), (2, 1.025), (3, 1.025)); b = base["bus"][string(i)]; b["vmin"] = v; b["vmax"] = v; end
function variant(s; qfree = false, vlow = 0.9, vfree = false, rates = true)
    d = deepcopy(base)
    for (_, l) in d["load"]; l["pd"] *= s; l["qd"] *= s; end
    qfree && for (_, g) in d["gen"]; g["qmax"] = 1e3; g["qmin"] = -1e3; end
    for (k, b) in d["bus"]; parse(Int, k) > 3 && (b["vmin"] = vlow); end
    vfree && for i in 1:3; d["bus"][string(i)]["vmin"] = 0.9; d["bus"][string(i)]["vmax"] = 1.1; end
    rates || for (_, b) in d["branch"]; b["rate_a"] = 1e3; end
    r = solve_opf(d, ACPPowerModel, opt)
    st = string(r["termination_status"])
    st == "LOCALLY_SOLVED" || return st
    q = [round(100r["solution"]["gen"][string(i)]["qg"], digits = 1) for i in 1:3]
    vm = minimum(b["vm"] for b in values(r["solution"]["bus"]))
    "solved, cost $(round(r["objective"], digits = 2)), Qg $q, min Vm $(round(vm, digits = 4))"
end
for s in (1.5, 1.75)
    println("s=$s as before:           ", variant(s))
    println("s=$s Q limits removed:    ", variant(s; qfree = true))
    println("s=$s load-bus vmin 0.8:   ", variant(s; vlow = 0.8))
    println("s=$s gen V free 0.9–1.1:  ", variant(s; vfree = true))
    println("s=$s ratings removed:     ", variant(s; rates = false))
end
