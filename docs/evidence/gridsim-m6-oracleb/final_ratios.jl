using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
include(joinpath(@__DIR__, "fixtures.jl"))

println("channel gaps against the SHIPPED band (gap / band), per fixture\n")
@printf("%-9s %-9s %12s %12s %8s\n", "fixture", "channel", "gap", "band", "ratio")
for (name, net, kw) in (("radial", pf_radial(), (;)), ("meshed", pf_meshed(), (;)),
                        ("lossy", pf_lossy(), (;)), ("offbase", pf_offbase(), (;)),
                        ("qlimit", pf_qlimit(), (; abstol_fine = 1e-14)))
    ours = ac_powerflow(net); theirs = oracle_powerflow(net)
    fs = flow_scale(net, ours)
    for (cn, ch, sc) in ((:Vm, s -> s.Vm, nothing), (:θ, s -> s.θ, nothing),
                         (:flow, s -> s.flow, fs), (:qflow, s -> s.qflow, fs))
        b = powerflow_band(net; channel = ch, scale = sc, kw...)
        g = maximum(abs, ch(ours) .- ch(theirs))
        @printf("%-9s %-9s %12.3e %12.3e %8.3f\n", name, cn, g, b.band, g / b.band)
    end
end

println("\nindependent mismatch, per fixture (ours vs theirs)")
for (name, net) in (("radial", pf_radial()), ("meshed", pf_meshed()),
                    ("lossy", pf_lossy()), ("offbase", pf_offbase()),
                    ("qlimit", pf_qlimit()))
    o = independent_mismatch(net, ac_powerflow(net))
    t = independent_mismatch(net, oracle_powerflow(net))
    @printf("%-9s ours=%.3e  theirs=%.3e  ratio=%.3e\n", name, o, t, t / o)
end

println("\nthe lossy channel (only this fixture has one)")
net = pf_lossy(); o = ac_powerflow(net); t = oracle_powerflow(net)
@printf("our losses  = %s\n", round.(o.flow .+ o.flow_rev, sigdigits = 6))
@printf("their losses= %s\n", round.(t.flow .+ t.flow_rev, sigdigits = 6))
@printf("slack pickup ours=%.9f theirs=%.9f\n", sum(o.Pgen), sum(t.Pgen))
