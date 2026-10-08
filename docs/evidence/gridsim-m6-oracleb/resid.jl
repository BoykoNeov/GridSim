using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
net = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)

# An INDEPENDENT mismatch: build Y by hand from the branch list, then S = V .* conj(Y*V).
n = 3
Y = zeros(ComplexF64, n, n)
for br in net.branches
    f = net.bus_index[br.from]; t = net.bus_index[br.to]
    y = 1 / complex(br.R, br.X)
    Y[f, f] += y; Y[t, t] += y; Y[f, t] -= y; Y[t, f] -= y
end
# Scheduled injection at each bus (pu): machines minus loads (constant power here).
Psch = [0.6, 1.0, -1.6]   # G1 unknown at slack; G2 = 1.0; D3 = -1.6
function mismatch(Vm, θ, tag)
    V = Vm .* cis.(θ)
    S = V .* conj.(Y * V)
    # bus 2: P equation; bus 3: P and Q equations (Q load = 0.40 pu)
    @printf("%-8s  P2 mismatch = %+.3e   P3 = %+.3e   Q3 = %+.3e\n", tag,
            real(S[2]) - 1.0, real(S[3]) + 1.6, imag(S[3]) + 0.4)
end
ours = ac_powerflow(net; abstol = 1e-14)
theirs = oracle_powerflow(net; tol = 1e-12)
mismatch(ours.Vm, ours.θ, "ours")
mismatch(theirs.Vm, theirs.θ, "theirs")
