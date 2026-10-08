using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
include(joinpath(@__DIR__, "fixtures.jl"))

chans = [(:Vm, s -> s.Vm), (:θ, s -> s.θ), (:flow, s -> s.flow),
         (:flow_rev, s -> s.flow_rev), (:qflow, s -> s.qflow)]

# RELATIVE ulp of the admittance MAGNITUDE, applied to both components — the fix.
function perbranch(net, channel; abstol = 1e-12)
    base = ac_powerflow(net; abstol = abstol)
    tot = 0.0
    for e in eachindex(net.branches)
        brs = collect(net.branches)
        br = brs[e]
        y = 1 / complex(br.R, br.X)
        u = eps(Float32) * abs(y)                 # one relative ulp of |y|
        z = 1 / (y + complex(u, u))
        R = max(real(z), 0.0)
        brs[e] = Branch(br.id, br.from, br.to, imag(z), br.rating; R = R)
        pert = NetworkModel(net.S_base, net.f0, net.buses, brs, net.machines, net.loads;
                            slack = net.slack)
        tot += maximum(abs, channel(ac_powerflow(pert; abstol = abstol)) .- channel(base))
    end
    return tot
end

for (name, net) in (("radial", pf_radial()), ("meshed", pf_meshed()),
                    ("lossy", pf_lossy()), ("offbase", pf_offbase()))
    println("\n===== ", name, " =====")
    ours = ac_powerflow(net); theirs = oracle_powerflow(net)
    @printf("%-9s %12s %12s %12s %8s\n", "channel", "gap", "perbranch", "twin", "g/perbr")
    for (cn, ch) in chans
        b = powerflow_band(net; channel = ch)
        g = maximum(abs, ch(ours) .- ch(theirs))
        pb = perbranch(net, ch)
        @printf("%-9s %12.3e %12.3e %12.3e %8.2f\n", cn, g, pb, b.quantization, g / pb)
    end
end

println("\n===== Q-limit fixture tuning (our side only) =====")
for (P, Q, Qmax) in ((120.0, 40.0, 0.30), (120.0, 40.0, 0.20), (100.0, 30.0, 0.15),
                     (100.0, 30.0, 0.10), (90.0, 25.0, 0.10))
    net = NetworkModel(100.0, 50.0,
        [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
        [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.10, 400.0)],
        [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, P - 70.0; V_set = 1.00),
         Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 70.0; V_set = 1.05,
                 Q_min = -Qmax, Q_max = Qmax)],
        [Load(:D3, :B3, P, Q, 0.0, 0.0, 1.0)]; slack = :B1)
    try
        s = ac_powerflow(net)
        @printf("P=%5.1f Q=%4.1f Qmax=%.2f -> limited=%s Vm=%s Qgen2=%.4f\n",
                P, Q, Qmax, s.limited, round.(s.Vm, digits = 4), s.Qgen[2])
    catch err
        @printf("P=%5.1f Q=%4.1f Qmax=%.2f -> REFUSED: %s\n", P, Q, Qmax,
                first(split(sprint(showerror, err), '.')))
    end
end
