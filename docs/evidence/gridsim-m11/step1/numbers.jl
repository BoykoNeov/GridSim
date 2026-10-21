# Prints the step-1 numbers next to the predictions (read by eye, not asserted).
using GridSim, Test, Printf
import JuMP, HiGHS
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
let src = read(raw"W:\Claude_projects\GridSim\test\m6_economic_dispatch.jl", String)
    include_string(Main, src[1:findfirst("@testset \"M6 step 7", src).start - 1])
end
let src = read(raw"W:\Claude_projects\GridSim\test\m11_dc_opf.jl", String)
    include_string(Main, src[1:findfirst("@testset \"M11 step 1", src).start - 1])
end
show(r) = (@printf("  %s  cost %.4f  at_limit %s\n  P MW %s\n  flow MW %s\n", r.outcome, r.cost,
           r.at_limit, round.(r.P .* 100; digits = 4), join(["$(b)=$(round(f*100;digits=4))" for (b,f) in zip(r.branches, r.flow)], " ")))
c9 = _opf_c9()
println("22.1"); r = dc_opf(c9); show(r); ed = economic_dispatch(c9); println("  ED P ", round.(ed.P .* 100; digits=4), " cost ", ed.cost, "  |ΔP| pu ", maximum(abs.(r.P .- ed.P)), " band ", _opf_band_pu(c9, 1e-9, 1e-7) + _ed_band_pu(cost_arrays(c9), 1e-9, 1e-7))
println("22.2"); show(dc_opf(_opf_rated(c9, :L82 => 100.0)))
println("22.3"); r3 = dc_opf(_opf_rated(c9, :L89 => 50.0); regularization=0.0); show(r3); println("  ΔP MW ", round.((r3.P .- ed.P) .* 100; digits=4), "  Δcost ", r3.cost - ed.cost)
println("22.4 ctl"); show(dc_opf(_opf_triangle(; rating_AC=250.0)))
println("22.4 bind"); show(dc_opf(_opf_triangle()))
println("infeasible"); show(dc_opf(_opf_rated(c9, :L45 => 40.0, :L56 => 40.0)))
println("control 46"); show(dc_opf(_opf_rated(c9, :L45 => 46.0, :L56 => 46.0)))
println("bands: kkt22.4 ", _opf_kkt_band(_opf_kkt((_C9[2],_C9[1]), [0.75,0.5], 200.0, 120.0).K, 2, 3, 1e-9, 100.0), " MW")
