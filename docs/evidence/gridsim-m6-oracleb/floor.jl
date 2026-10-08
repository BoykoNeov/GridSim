using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
mk(X12, X23) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, X12, 400.0), Branch(:L23, :B2, :B3, X23, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 20.0; V_set = 1.00),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 70.0; V_set = 1.05,
             Q_min = -0.10, Q_max = 0.10)],
    [Load(:D3, :B3, 90.0, 25.0, 0.0, 0.0, 1.0)]; slack = :B1)
for (tag, X12, X23) in (("on-grid 0.10/0.10", 0.10, 0.10), ("off-grid 0.11/0.13", 0.11, 0.13))
    net = mk(X12, X23)
    for tol in (1e-12, 1e-15)
        try
            s = ac_powerflow(net; abstol = tol)
            @printf("%-20s abstol=%.0e -> ok, residual=%.4e\n", tag, tol, s.residual)
        catch err
            @printf("%-20s abstol=%.0e -> %s\n", tag, tol,
                    first(split(sprint(showerror, err), '.')))
        end
    end
    o = ac_powerflow(net); t = oracle_powerflow(net; check_limits = true)
    @printf("%-20s limited=%s gapV=%.4e\n\n", tag, o.limited, maximum(abs, o.Vm .- t.Vm))
end
