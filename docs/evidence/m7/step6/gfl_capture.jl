using GridSim, Serialization
net = NetworkModel(100.0, 50.0, [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.2, 900.0), Branch(:L23, :B2, :B3, 0.25, 900.0),
     Branch(:L13, :B1, :B3, 0.3, 900.0)],
    [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.3, 1.02, 80.0),
     Machine(:G3, :B3, 400.0, 3.0, 1.0, 0.3, 1.0, -140.0)];
    inverters = [Inverter(:S2, :B2, :grid_following, 150.0, 60.0; Q0 = 10.0)])
eng = init!(DetailedEngine, net; reltol = 1e-10, abstol = 1e-12)
solve!(eng, (0.0, 1.5); perturbations = [0.5 => TripLine(:B1, :B3)], saveat = 0.0:0.001:1.5)
s = state_series(eng)
out = ARGS[1]
serialize(out, s)
if length(ARGS) > 1
    ref = deserialize(ARGS[2])
    println("keys equal: ", keys(ref) == keys(s))
    println("bit-identical: ", all(getfield(ref, k) == getfield(s, k) for k in keys(ref)))
end
