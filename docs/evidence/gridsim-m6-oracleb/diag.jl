using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))

include(joinpath(@__DIR__, "fixtures.jl"))

chans = [(:Vm, s -> s.Vm), (:θ, s -> s.θ), (:flow, s -> s.flow),
         (:flow_rev, s -> s.flow_rev), (:qflow, s -> s.qflow),
         (:Pgen, s -> s.Pgen), (:Qgen, s -> s.Qgen)]

# A first-order bound on the effect of single-precision admittances: perturb ONE
# branch's admittance by one Float32 ulp and sum the resulting answer changes over
# branches. The triangle inequality over branches bounds every rounding pattern at
# once, where the single twin realises only one of them.
function perbranch_bound(net, channel; abstol = 1e-12)
    base = ac_powerflow(net; abstol = abstol)
    tot = 0.0
    for e in eachindex(net.branches)
        brs = collect(net.branches)
        br = brs[e]
        y = 1 / complex(br.R, br.X)
        y2 = y + complex(eps(Float32(abs(real(y)))), eps(Float32(abs(imag(y)))))
        z = 1 / y2
        R = max(real(z), 0.0)
        brs[e] = Branch(br.id, br.from, br.to, imag(z), br.rating; R = R)
        pert = NetworkModel(net.S_base, net.f0, net.buses, brs, net.machines, net.loads;
                            slack = net.slack)
        tot += maximum(abs, channel(ac_powerflow(pert; abstol = abstol)) .- channel(base))
    end
    return tot
end

for (name, net, kw) in (("radial", pf_radial(), (;)), ("meshed", pf_meshed(), (;)),
                        ("lossy", pf_lossy(), (;)), ("offbase", pf_offbase(), (;)))
    println("\n===== ", name, " =====")
    ours = ac_powerflow(net); theirs = oracle_powerflow(net)
    @printf("%-9s %12s %12s %12s %12s %12s %8s %8s\n",
            "channel", "gap", "band", "ours", "quant", "theirs", "g/band", "g/perbr")
    for (cn, ch) in chans
        b = powerflow_band(net; channel = ch)
        g = maximum(abs, ch(ours) .- ch(theirs))
        pb = perbranch_bound(net, ch)
        @printf("%-9s %12.3e %12.3e %12.3e %12.3e %12.3e %8.2f %8.2f\n",
                cn, g, b.band, b.ours, b.quantization, b.theirs, g / b.band, g / pb)
    end
end
