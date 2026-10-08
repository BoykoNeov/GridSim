using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
mk(X23, Qmax, P, Q) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.11, 400.0), Branch(:L23, :B2, :B3, X23, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, P - 70.0; V_set = 1.00),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 70.0; V_set = 1.05,
             Q_min = -Qmax, Q_max = Qmax)],
    [Load(:D3, :B3, P, Q, 0.0, 0.0, 1.0)]; slack = :B1)
for (X23, Qmax, P, Q) in ((0.13, 0.10, 90.0, 25.0), (0.13, 0.15, 90.0, 25.0),
                          (0.13, 0.12, 95.0, 30.0), (0.13, 0.20, 95.0, 30.0))
    net = mk(X23, Qmax, P, Q)
    try
        o = ac_powerflow(net); t = oracle_powerflow(net; check_limits = true)
        gapV = maximum(abs, o.Vm .- t.Vm)
        b = powerflow_band(net; channel = s -> s.Vm, check_limits = true, abstol_fine = 1e-14)
        @printf("X23=%.2f Qmax=%.2f P=%.0f -> limited=%s Vm=%s Qgen2=%.4f gapV=%.3e ratio=%.3f\n",
                X23, Qmax, P, o.limited, round.(o.Vm, digits=4), o.Qgen[2], gapV, gapV/b.band)
    catch err
        @printf("X23=%.2f Qmax=%.2f P=%.0f -> %s\n", X23, Qmax, P,
                first(split(sprint(showerror, err), '.')))
    end
end
