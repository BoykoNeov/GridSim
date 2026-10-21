# M11 step 4 — PowerModels' AC OPF ALONE (nothing of ours), on the typed case9 text with
# the step-4 edits: R kept, line charging 0, generator voltages held by Vmin = Vmax = Vg.
#   julia --project=W:/Claude_projects/GridSim/reference theirs_probe.jl
using GridSimReference, Printf
const PM = GridSimReference.PM
src = read(joinpath(pkgdir(GridSimReference), "test", "m11_dc_opf_oracle.jl"), String)
const TXT = match(r"const C9_MATPOWER = \"\"\"\n(.*?)\"\"\""s, src).captures[1]

# The edits land where they say.
e = PM.parse_matpower(IOBuffer(matpower_edit(TXT; b0 = true, held = true, load = 1.5)))
println("b_fr/b_to all 0: ", all(b -> all(b["b_fr"] .== 0) && all(b["b_to"] .== 0), values(e["branch"])))
for i in 1:9
    b = e["bus"][string(i)]
    @printf("bus %d  vmin %.4f vmax %.4f  pd %.4f qd %.4f\n", i, b["vmin"], b["vmax"],
            sum((l["pd"] for l in values(e["load"]) if l["load_bus"] == i); init = 0.0),
            sum((l["qd"] for l in values(e["load"]) if l["load_bus"] == i); init = 0.0))
end
println("unedited parse == edited-with-defaults parse: ",
        PM.parse_matpower(IOBuffer(TXT)) == PM.parse_matpower(IOBuffer(matpower_edit(TXT))))

fixtures = [("published", Dict{Tuple{Int,Int},Float64}(), 1.0),
            ("1.5x", Dict{Tuple{Int,Int},Float64}(), 1.5),
            ("1.75x", Dict{Tuple{Int,Int},Float64}(), 1.75),
            ("L94@60", Dict((9, 4) => 60.0), 1.0)]
for (name, rate, s) in fixtures
    text = matpower_edit(TXT; b0 = true, held = true, load = s, rate)
    runs = Dict{Float64,Any}()
    println("\n== ", name)
    for τ in (1e-8, 1e-10, 1e-11, 1e-12)
        t = @elapsed r = oracle_ac_opf(text; tol = τ)
        runs[τ] = r
        @printf("  tol %.0e: %s / %s  (%.1f s)\n", τ, r.status, r.primal, t)
    end
    r = runs[1e-8]
    r.solved || continue
    @printf("  cost %.6f\n  pg  %s MW\n  qg  %s MVAr\n", r.cost, string(round.(100 .* r.pg; digits = 4)),
            string(round.(100 .* r.qg; digits = 4)))
    @printf("  vm  %s\n", string(round.(r.vm; digits = 6)))
    for j in eachindex(r.pf)
        Sf, St = hypot(r.pf[j], r.qf[j]), hypot(r.pt[j], r.qt[j])
        @printf("  br %d-%d  pf %+.4f pt %+.4f qf %+.4f qt %+.4f  |S|f %.4f |S|t %.4f  rate %.2f\n",
                r.f_bus[j], r.t_bus[j], 100r.pf[j], 100r.pt[j], 100r.qf[j], 100r.qt[j],
                100Sf, 100St, 100 * r.data["branch"][string(j)]["rate_a"])
    end
    va = r.va
    @printf("  max |angle diff| %.4f rad (bound %.4f)\n",
            maximum(abs(va[f] - va[t]) for (f, t) in zip(r.f_bus, r.t_bus)), r.angmax[1])
    for τ in (1e-10, 1e-11, 1e-12)
        q = runs[τ]
        q.solved || continue
        @printf("  |run(1e-8) - run(%.0e)|: pg %.2e qg %.2e vm %.2e va %.2e pf %.2e qf %.2e pt %.2e cost %.2e\n",
                τ, maximum(abs, r.pg .- q.pg), maximum(abs, r.qg .- q.qg), maximum(abs, r.vm .- q.vm),
                maximum(abs, r.va .- q.va), maximum(abs, r.pf .- q.pf), maximum(abs, r.qf .- q.qf),
                maximum(abs, r.pt .- q.pt), abs(r.cost - q.cost))
    end
end
