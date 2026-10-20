# run with --project=W:/temp/claude/gridsim-m11-resolve/core_test
using PowerModels, Ipopt, JuMP
PowerModels.silence()
f = raw"W:\temp\claude\gridsim-m11-resolve\data\case9.m"
opt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
function show(label, data, form)
    r = solve_opf(data, form, opt)
    gens = sort(collect(r["solution"]["gen"]), by = g -> parse(Int, first(g)))
    println(rpad(label, 34), r["termination_status"], "  cost = ", round(r["objective"], digits = 4),
            "  Pg (MW) = ", [round(100g["pg"], digits = 3) for (_, g) in gens])
end
d = PowerModels.parse_file(f)
show("AC, MATPOWER case9 as published", d, ACPPowerModel)
show("DC, MATPOWER case9 as published", d, DCPPowerModel)
d0 = deepcopy(d); for (_, b) in d0["branch"]; b["b_fr"] = 0.0; b["b_to"] = 0.0; end
show("AC, no line charging (our case9)", d0, ACPPowerModel)
