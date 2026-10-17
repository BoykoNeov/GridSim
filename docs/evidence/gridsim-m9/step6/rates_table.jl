# M9 step 6: the rate table (D10). Every generator outage of the two lossy report
# grids, both load models: the closed form at t⁺ (constant power only), the windowed
# COI rate over a window sweep, the worst machine, and two illustrative verdicts.
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step6/rates_table.jl
using GridSim, Printf
module OutageScreenScript
include("W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end
const O = OutageScreenScript
losses(eng) = sum(branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
                  for b in eng.model.branches)
for (name, build) in (("case9", O.case9), ("mesh", O.mesh)), loads in (:constant_power, :default)
    net = build(; loads)
    ac = ac_generator_outages(net)
    d = generator_dips(net, ac)
    g = compare_generator_screens(net, dc_generator_outages(net), ac)
    W = (1.0, 0.5, 0.2, 0.1, 0.04, 0.02, 0.01)
    R = Dict(w => generator_rates(d; window = w) for w in W)
    v1 = frequency_verdicts(net, g, FrequencyLimits(; rate = 1.0, rate_window = 0.5); dips = d)
    v2 = frequency_verdicts(net, g, FrequencyLimits(; rate = 2.5, rate_window = 1.0); dips = d)
    println("== $name $loads")
    for (k, id) in enumerate(d.machines)
        if d.outcome[k] !== :measured
            println("  $id: $(d.outcome[k]) ($(d.reason[k]))  verdicts $(v1.rate[k]) / $(v2.rate[k])")
            continue
        end
        cf = NaN
        if loads === :constant_power
            eng = init!(DetailedEngine, net; powerflow = ac.base, reltol = 1e-8, abstol = 1e-10,
                        solver = GridSim.OrdinaryDiffEq.FBDF())
            P, L = eng.params[eng.Pm_pidx[k]], losses(eng)
            inject!(eng, TripGenerator(id))
            ΣHS = sum(m.H * m.S_rated / net.S_base for (j, m) in pairs(net.machines) if j != k)
            cf = -(P + losses(eng) - L) * net.f0 / (2ΣHS)
        end
        @printf("  %s: closed form %s Hz/s\n", id, isnan(cf) ? "—" : @sprintf("%.6f", cf))
        for w in W
            r = R[w]
            @printf("    w=%5.2f s  coi %+.6f (coarse %+.6f)  worst %s %+.6f (coarse %+.6f)  worst/coi %.4f%s\n",
                    w, r.rate_coi[k], r.rate_coi_coarse[k], r.worst[k], r.rate_worst[k],
                    r.rate_worst_coarse[k], r.rate_worst[k] / r.rate_coi[k],
                    isnan(cf) ? "" : @sprintf("  gap %.3e (%.3f %%)", abs(cf) - abs(r.rate_coi[k]),
                                              100 * (abs(cf) - abs(r.rate_coi[k])) / abs(cf)))
        end
        if !isnan(cf)
            gp = [abs(cf) - abs(R[w].rate_coi[k]) for w in W]
            @printf("    gap ratios (w / w/2-ish): %s\n", join((@sprintf("%.3f", gp[i] / gp[i+1]) for i in 1:length(W)-1), " "))
        end
        println("    verdict 1 Hz/s over 0.5 s: $(v1.rate[k]) ($(v1.rocof[k]));  2.5 Hz/s over 1 s: $(v2.rate[k]) ($(v2.rocof[k]))")
    end
end
