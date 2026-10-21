# run with --project=W:/temp/claude/gridsim-m11-resolve/core_test
# Where do line limits bind on MATPOWER case9 (DC and AC-held-V, no line charging)?
using PowerModels, Ipopt, JuMP
PowerModels.silence()
opt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0, "tol" => 1e-10)
base = PowerModels.parse_file(raw"W:\temp\claude\gridsim-m11-resolve\data\case9.m")
for (_, b) in base["branch"]; b["b_fr"] = 0.0; b["b_to"] = 0.0; end
for (i, v) in ((1, 1.04), (2, 1.025), (3, 1.025)); b = base["bus"][string(i)]; b["vmin"] = v; b["vmax"] = v; end
names = Dict("1"=>"L14","2"=>"L45","3"=>"L56","4"=>"L36","5"=>"L67","6"=>"L78","7"=>"L82","8"=>"L89","9"=>"L94")
function run(d, form)
    r = solve_opf(d, form, opt)
    st = string(r["termination_status"])
    st in ("LOCALLY_SOLVED", "OPTIMAL") || return (st, NaN, String[], NaN[])
    bind = String[]; load = Float64[]
    for (k, br) in r["solution"]["branch"]
        q(x) = (x isa Number && isfinite(x)) ? x : 0.0; s = max(hypot(br["pf"], q(get(br, "qf", 0.0))), hypot(br["pt"], q(get(br, "qt", 0.0))))
        rate = d["branch"][k]["rate_a"]
        s / rate > 0.999 && push!(bind, names[k])
    end
    pg = [round(100r["solution"]["gen"][string(i)]["pg"], digits = 2) for i in 1:3]
    (st, r["objective"], sort(bind), pg)
end
function scaled(s; nonet = false)
    d = deepcopy(base)
    for (_, l) in d["load"]; l["pd"] *= s; l["qd"] *= s; end
    nonet && for (_, b) in d["branch"]; b["rate_a"] = 1e3; end
    d
end
println("scale | DC: cost, binding, Pg | DC no limits cost | AC held-V: status, cost, binding, Pg")
for s in (1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.4)
    dc = run(scaled(s), DCPPowerModel); dcn = run(scaled(s; nonet = true), DCPPowerModel)
    ac = run(scaled(s), ACPPowerModel)
    println(rpad(s, 5), " | ", round(dc[2], digits = 2), " ", dc[3], " ", dc[4], " | ", round(dcn[2], digits = 2),
            " | ", ac[1], " ", round(ac[2], digits = 2), " ", ac[3], " ", ac[4])
end
println("\nrating sweep at published load, one line at a time down to 60% of its DC-unconstrained flow:")
r0 = solve_opf(scaled(1.0; nonet = true), DCPPowerModel, opt)
for k in sort(collect(keys(names)), by = x -> parse(Int, x))
    f = abs(r0["solution"]["branch"][k]["pf"]) * 100
    d = scaled(1.0); d["branch"][k]["rate_a"] = 0.6f / 100
    dc = run(d, DCPPowerModel)
    println(rpad(names[k], 4), " unconstrained ", round(f, digits = 1), " MW (rated ", base["branch"][k]["rate_a"] * 100, ") -> at 60%: cost ", round(dc[2], digits = 2), " binding ", dc[3], " Pg ", dc[4])
end
