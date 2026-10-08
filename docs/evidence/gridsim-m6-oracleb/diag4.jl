using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
include(joinpath(@__DIR__, "fixtures.jl"))
for qm in (0.10, 50.0), tol in (1e-12, 1e-13, 1e-14, 1e-15)
    net = pf_qlimit(Q_max = qm)
    try
        s = ac_powerflow(net; abstol = tol)
        @printf("Qmax=%5.1f abstol=%.0e -> ok, residual=%.3e\n", qm, tol, s.residual)
    catch err
        @printf("Qmax=%5.1f abstol=%.0e -> %s\n", qm, tol,
                first(split(sprint(showerror, err), '.')))
    end
end
net = pf_radial(); s = ac_powerflow(net)
@printf("\nradial: flow_scale=%.4f  max|qflow|=%.4f  max|flow|=%.4f  ymax=%.4f\n",
        flow_scale(net, s), maximum(abs, s.qflow), maximum(abs, s.flow),
        maximum(abs(1/complex(b.R,b.X)) for b in net.branches))
