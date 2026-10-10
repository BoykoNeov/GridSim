# M9 step 5: `generator_dips` on every generator outage of the two report fixtures,
# both load models, lossless copies (step 0's table, the regression) and the lossy
# report grids themselves, beside the AC screen's outcome on the same grid.
#   julia --project=W:/Claude_projects/GridSim dips_table.jl
using GridSim, Printf
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
lossless(n) = NetworkModel(n.S_base, n.f0, n.buses,
                           [Branch(b.id, b.from, b.to, b.X, b.rating) for b in n.branches],
                           n.machines, n.loads; slack = n.slack)
for grid in (:lossless, :lossy), (name, build) in (("case9", OS.case9), ("mesh", OS.mesh)),
    loads in (:constant_power, :default)
    net0 = build(; loads)
    net = grid === :lossless ? lossless(net0) : net0
    ac = ac_generator_outages(net)
    t0 = time()
    d = generator_dips(net, ac)
    el = time() - t0
    for k in eachindex(d.machines)
        @printf("%-8s %-5s %-14s %-3s AC %-11s | %-19s %-11s coi %9.5f / %9.5f | worst %-3s %9.5f / %9.5f | end %9.5f at %7.2f s\n",
                grid, name, loads, d.machines[k], ac.outcome[k], d.outcome[k], d.reason[k],
                d.Δf_coi[k], d.Δf_coi_coarse[k], d.worst[k], d.Δf_worst[k],
                d.Δf_worst_coarse[k], d.Δf_end[k], d.t_stop[k])
        println("    full: coi ", repr(d.Δf_coi[k]), " ", repr(d.Δf_coi_coarse[k]),
                " worst ", repr(d.Δf_worst[k]), " ", repr(d.Δf_worst_coarse[k]),
                " end ", repr(d.Δf_end[k]), " t_stop ", repr(d.t_stop[k]))
    end
    @printf("    [%s %s %s: %.1f s]\n", grid, name, loads, el)
end
