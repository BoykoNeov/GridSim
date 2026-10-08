using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
include(joinpath(@__DIR__, "fixtures.jl"))

println("== qflow: is the naive scale the wrong one? ==")
for (name, net) in (("meshed", pf_meshed()), ("lossy", pf_lossy()), ("offbase", pf_offbase()))
    ours = ac_powerflow(net); theirs = oracle_powerflow(net)
    gap = maximum(abs, ours.qflow .- theirs.qflow)
    naive = eps(Float32) * maximum(abs, ours.qflow)
    ymax = maximum(abs(1 / complex(b.R, b.X)) for b in net.branches)
    terms = eps(Float32) * ymax * maximum(ours.Vm)^2
    @printf("%-8s gap=%.3e  naive=%.3e (x%.2f)  |y|V^2=%.3e (x%.2f)   max|qflow|=%.3f ymax=%.2f\n",
            name, gap, naive, gap / naive, terms, gap / terms,
            maximum(abs, ours.qflow), ymax)
    for (cn, ch) in ((:Vm, s -> s.Vm), (:θ, s -> s.θ), (:flow, s -> s.flow))
        g = maximum(abs, ch(ours) .- ch(theirs))
        n = eps(Float32) * maximum(abs, ch(ours))
        @printf("     %-5s gap=%.3e naive=%.3e (x%.2f)\n", cn, g, n, g / n)
    end
end

println("\n== the Q-limit fixture, both halves ==")
for qm in (0.10, 50.0)
    net = pf_qlimit(Q_max = qm)
    try
        s = ac_powerflow(net)
        @printf("Q_max=%5.1f -> limited=%s Vm=%s Qgen2=%.6f\n", qm, s.limited,
                round.(s.Vm, digits = 5), s.Qgen[2])
        t = oracle_powerflow(net; check_limits = true)
        @printf("            theirs Vm=%s Qgen2=%.6f\n", round.(t.Vm, digits = 5), t.Qgen[2])
        u = oracle_powerflow(net; check_limits = false)
        @printf("            unlimited Vm=%s Qgen2=%.6f\n", round.(u.Vm, digits = 5), u.Qgen[2])
    catch err
        @printf("Q_max=%5.1f -> REFUSED: %s\n", qm, first(split(sprint(showerror, err), '.')))
    end
end
