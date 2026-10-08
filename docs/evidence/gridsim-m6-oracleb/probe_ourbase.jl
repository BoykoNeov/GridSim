using GridSim, Printf
import Pkg
nsb = get(Dict(e.name => e.version for (_, e) in Pkg.Operations.Context().env.manifest),
          "NonlinearSolveBase", nothing)
println("NonlinearSolveBase = ", nsb)
net = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 500.0; R = 0.01),
     Branch(:L23, :B2, :B3, 0.15, 500.0; R = 0.02),
     Branch(:L13, :B1, :B3, 0.30, 500.0; R = 0.03)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 250.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.5, 0.3, 0.2)];
    slack = :B1)
for tol in (1e-12, 1e-15)
    sol = ac_powerflow(net; abstol = tol)
    @printf("tol=%.0e  Vm = ", tol)
    for v in sol.Vm; @printf("%.17g ", v); end
    print("  θ = ")
    for v in sol.θ; @printf("%.17g ", v); end
    @printf("  res=%.3e\n", sol.residual)
end
