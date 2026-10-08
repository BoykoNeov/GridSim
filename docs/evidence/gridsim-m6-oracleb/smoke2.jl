using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
radial() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)
net = radial()
ours = ac_powerflow(net; abstol = 1e-14)
println("ours   Vm3 = ", repr(ours.Vm[3]), "  θ3 = ", repr(ours.θ[3]))
for lim in (false, true), tol in (1e-8, 1e-9, 1e-10, 1e-12, 1e-14)
    t = oracle_powerflow(net; tol = tol, check_limits = lim)
    @printf("lim=%-5s tol=%.0e  Vm3=%.17g  θ3=%.17g  gapV=%.3e gapθ=%.3e\n",
            lim, tol, t.Vm[3], t.θ[3], abs(t.Vm[3] - ours.Vm[3]), abs(t.θ[3] - ours.θ[3]))
end
