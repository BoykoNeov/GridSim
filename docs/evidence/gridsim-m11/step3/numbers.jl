# M11 step 3 — prints every comparison's gap beside its band (the tests assert them).
#   julia --project=W:/temp/claude/gridsim-m11-step3/probeenv numbers.jl
using GridSim, Test, Printf
using LinearAlgebra: opnorm
import JuMP, HiGHS, Ipopt
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
cd(raw"W:\Claude_projects\GridSim")
src = read(raw"W:\Claude_projects\GridSim\test\m11_dc_opf.jl", String)
include_string(Main, src[findfirst("_opf_c9() =", src).start:findfirst("# The three-bus triangle", src).start-1])
src3 = read(raw"W:\Claude_projects\GridSim\test\m11_ac_opf.jl", String)
include_string(Main, src3[findfirst("const _AC_TAU", src3).start:findfirst("@testset \"M11 step 3", src3).start-1])
fx = (("published cp", () -> _ac_c9()), ("published default", () -> _ac_c9(; loads = :default)),
      ("1.5x cp", () -> _ac_c9(; mw = 1.5 * 315)), ("L94 cp", () -> _ac_l94(:constant_power)),
      ("L94 default", () -> _ac_l94(:default)))
println("== 24.1")
for (l, mk) in fx
    net = mk(); r = ac_opf(net); h = _ac_handback(net, r); f = h.f
    vs = net.bus_index[net.slack]
    @printf("%-18s κ %.4f  band_x %.2e band_S %.2e | Vm %.1e θ %.1e flows %.1e mva %.1e slackP %.1e (band %.2e) | cost %.6f\n",
            l, h.κ, h.bx, h.bS, maximum(abs, f.Vm .- r.Vm), maximum(abs, f.θ .- r.θ),
            maximum(maximum(abs, getfield(f, s) .- getfield(r, s)) for s in (:flow, :flow_rev, :qflow, :qflow_rev)),
            maximum(abs, _ac_mva(f) .- r.mva), abs(f.Pgen[vs] - r.P[1]), h.bP, r.cost)
    @printf("    P MW %s  at_limit %s at_band %s  losses %.4f MW shift %.4f MW  min|V| flow %.10f\n",
            string(round.(r.P .* 100; digits = 4)), r.at_limit, r.at_band, r.losses * 100, r.load_shift * 100, minimum(f.Vm))
end
println("== 24.2")
for loads in (:constant_power, :default)
    net = _ac_c9(; loads); r = ac_opf(net)
    g = dispatch_loss_gap(net, economic_dispatch(net; regularization = 0.0))
    @printf("%-15s OPF %.6f  M6 flowed %.6f  margin %.6f \$/h\n", loads, r.cost, g.cost_flowed, g.cost_flowed - r.cost)
end
println("== 24.5")
for (l, mk) in fx
    net = mk(); d = dc_opf(net; regularization = 0.0)
    a, at, b, bt = ac_opf(net), ac_opf(net; tol = 1e-10), ac_opf(net; start = d), ac_opf(net; tol = 1e-10, start = d)
    worst = maximum(_ac_gap(a, b, s) / (2 * (_ac_gap(a, at, s) + _ac_gap(b, bt, s)) + 1e-11) for s in _AC_FIELDS)
    @printf("%-18s max gap %.1e pu (P %.1e)  worst gap/band %.3f  cost gap %.1e\n", l,
            maximum(_ac_gap(a, b, s) for s in _AC_FIELDS), _ac_gap(a, b, :P), worst, abs(a.cost - b.cost))
end
