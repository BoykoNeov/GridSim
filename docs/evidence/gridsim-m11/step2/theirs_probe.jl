# M11 step 2 — THEIR side only, before any comparison (D8): Ipopt's statuses and its own
# convergence on each fixture, the solution's keys, the ±60° bound. Prints nothing of ours.
#   julia --project=W:/temp/claude/gridsim-m11-step2/refenv theirs_probe.jl
using PowerModels, Ipopt, JuMP
PowerModels.silence()
const TEXT = read(raw"W:\temp\claude\gridsim-m11-step2\data\typed.m", String)

# Branch rows in file order: (f, t) => line index in the branch block.
function edit(text; r0 = true, rate = Dict{Tuple{Int,Int},Float64}())
    out = String[]
    inbr = false
    for ln in split(text, '\n')
        if startswith(ln, "mpc.branch")
            inbr = true
        elseif inbr && startswith(ln, "];")
            inbr = false
        elseif inbr
            c = split(strip(ln, ['\t', ' ', ';']), '\t')
            ft = (parse(Int, c[1]), parse(Int, c[2]))
            r0 && (c[3] = "0")
            haskey(rate, ft) && (c[6] = c[7] = c[8] = string(rate[ft]))
            ln = "\t" * join(c, '\t') * ";"
        end
        push!(out, ln)
    end
    return join(out, '\n')
end

function theirs(text, tol)
    d = PowerModels.parse_matpower(IOBuffer(text))
    opt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0, "tol" => tol,
                                    "constr_viol_tol" => tol, "dual_inf_tol" => tol,
                                    "compl_inf_tol" => tol, "bound_relax_factor" => 0.0,
                                    "max_wall_time" => 120.0)
    r = solve_opf(d, DCPPowerModel, opt)
    return d, r
end

fixtures = [("published", Dict{Tuple{Int,Int},Float64}()),
            ("L82 at 100", Dict((8, 2) => 100.0)),
            ("L89 at 50", Dict((8, 9) => 50.0)),
            ("L45 L56 at 46", Dict((4, 5) => 46.0, (5, 6) => 46.0)),
            ("L45 L56 at 40", Dict((4, 5) => 40.0, (5, 6) => 40.0))]

pg(r) = [r["solution"]["gen"][string(i)]["pg"] for i in 1:3]
pf(r) = [r["solution"]["branch"][string(i)]["pf"] for i in 1:9]
va(r) = [r["solution"]["bus"][string(i)]["va"] for i in 1:9]

let (d, r) = theirs(TEXT, 1e-10)
    println("solution keys: gen ", keys(r["solution"]["gen"]["1"]), " branch ", keys(r["solution"]["branch"]["1"]),
            " bus ", keys(r["solution"]["bus"]["1"]))
    println("angmin/angmax after the reader: ", unique((b["angmin"], b["angmax"]) for (_, b) in d["branch"]))
    println("rate_a (pu): ", [d["branch"][string(i)]["rate_a"] for i in 1:9])
    println("f_bus/t_bus: ", [(d["branch"][string(i)]["f_bus"], d["branch"][string(i)]["t_bus"]) for i in 1:9])
end
for (name, rate) in fixtures, tol in (1e-8, 1e-10, 1e-11, 1e-13)
    _, r = theirs(edit(TEXT; rate), tol)
    st = string(r["termination_status"], "/", r["primal_status"])
    if r["termination_status"] in (JuMP.LOCALLY_SOLVED, JuMP.OPTIMAL)
        println(rpad(name, 15), " tol ", tol, "  ", st, "  pg ", pg(r))
    else
        println(rpad(name, 15), " tol ", tol, "  ", st)
    end
end
println("\nself-convergence |run(τ) − run(τ/1000)| (pu), their side alone:")
for (name, rate) in fixtures[1:4], τ in (1e-8, 1e-10)
    _, a = theirs(edit(TEXT; rate), τ)
    _, b = theirs(edit(TEXT; rate), τ / 1000)
    ok = all(x -> x["termination_status"] == JuMP.LOCALLY_SOLVED, (a, b))
    println(rpad(name, 15), " τ ", τ, " both solved: ", ok, "  pg ", maximum(abs, pg(a) .- pg(b)),
            "  pf ", maximum(abs, pf(a) .- pf(b)), "  cost ", abs(a["objective"] - b["objective"]),
            "  max branch |θf−θt| ", maximum(abs(va(a)[f] - va(a)[t]) for (f, t) in
                ((1,4),(4,5),(5,6),(3,6),(6,7),(7,8),(8,2),(8,9),(9,4))))
end
