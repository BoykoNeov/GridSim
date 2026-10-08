using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
import PowerFlows
const PNM = PowerFlows.PNM
import PowerSystems as PSY
net = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)
sys = to_powersystems(net)
Yt = PNM.Ybus(sys)
println("their Ybus =")
display(Matrix(Yt.data)); println()
Y = zeros(ComplexF64, 3, 3)
for br in net.branches
    f = net.bus_index[br.from]; t = net.bus_index[br.to]
    y = 1 / complex(br.R, br.X)
    Y[f,f] += y; Y[t,t] += y; Y[f,t] -= y; Y[t,f] -= y
end
println("ours =")
display(Y); println()
println("max |diff| = ", maximum(abs, Matrix(Yt.data) .- Y))
# and what the Line reports back
for l in PSY.get_components(PSY.Line, sys)
    println(PSY.get_name(l), "  r=", PSY.get_r(l), " x=", PSY.get_x(l), " b=", PSY.get_b(l))
end
