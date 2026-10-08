using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))

radial() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)

net = radial()
ours = ac_powerflow(net)
theirs = oracle_powerflow(net)
@printf("ours   Vm = %s\n", ours.Vm)
@printf("theirs Vm = %s\n", theirs.Vm)
@printf("ours   θ  = %s\n", ours.θ)
@printf("theirs θ  = %s\n", theirs.θ)
@printf("ours   flow = %s\n", ours.flow)
@printf("theirs flow = %s\n", theirs.flow)
@printf("ours   Pgen = %s\n", ours.Pgen)
@printf("theirs Pgen = %s\n", theirs.P_gen)
@printf("ours   Qgen = %s\n", ours.Qgen)
@printf("theirs Qgen = %s\n", theirs.Q_gen)
for ch in (:Vm, :θ)
    a = getfield(ours, ch); b = getfield(theirs, ch)
    @printf("gap %s = %.3e\n", ch, maximum(abs, a .- b))
end
@printf("gap flow = %.3e\n", maximum(abs, ours.flow .- theirs.flow))
