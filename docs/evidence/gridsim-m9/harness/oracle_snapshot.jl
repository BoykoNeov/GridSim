# M9 step 3 gate, capture 6: the PowerDynamics oracle on LOSSLESS models at full
# precision (`repr`), so "nothing lossless moved in the builder" is a text comparison.
# One run per tier the builder maps — swing (line trip and generator trip), classical,
# sauer_pai (line trip; a load bus), sauer_pai_avr (a setpoint step) and the
# grid-forming inverter case (its coupling lines are PiLines too) — every channel
# `oracle_solve` returns, every sample.
#
#   julia --project=W:/Claude_projects/GridSim/reference W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/oracle_snapshot.jl > <out>.txt
using GridSim, GridSimReference

function dump(name, s)
    println("== ", name)
    for k in keys(s)
        println(k, " ", repr(collect(getproperty(s, k))))
    end
end

grid = collect(0.0:0.05:3.0)

dump("swing ring TripLine", oracle_solve(build_oracle(three_machine_ring();
     perturbations = [1.0 => TripLine(:B3, :B1)]), (0.0, 3.0); saveat = grid))
dump("swing ring TripGenerator", oracle_solve(build_oracle(three_machine_ring();
     perturbations = [1.0 => TripGenerator(:G2)]), (0.0, 3.0); saveat = grid))

let c = build_oracle(two_machine_system(); tier = :classical)
    set_mechanical_power!(c, :G1, machine_arrays(two_machine_system()).Pm[1] + 0.05)
    dump("classical pair step", oracle_solve(c, (0.0, 3.0); saveat = grid))
end

dump("sauer_pai ring TripLine", oracle_solve(build_oracle(three_machine_ring();
     tier = :sauer_pai, perturbations = [1.0 => TripLine(:B3, :B1)]), (0.0, 3.0);
     saveat = grid))
dump("sauer_pai load bus flat", oracle_solve(build_oracle(load_bus_system();
     tier = :sauer_pai), (0.0, 3.0); saveat = grid))

let c = build_oracle(infinite_bus_system(; K_A = 20.0, T_E = 0.5); tier = :sauer_pai_avr)
    dump("sauer_pai_avr flat", oracle_solve(c, (0.0, 3.0); saveat = grid))
end

gfm = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0), Bus(:C, 1.0)],
    [Branch(:AC, :A, :C, 0.2, 500.0), Branch(:BC, :B, :C, 0.25, 500.0),
     Branch(:AB, :A, :B, 0.3, 500.0)], Machine[], [Load(:D, :C, 90.0, 20.0)];
    inverters = [Inverter(:iA, :A, :grid_forming, 150.0, 50.0; V_set = 1.02,
                          K_q = 0.05, X_c = 0.1),
                 Inverter(:iB, :B, :grid_forming, 120.0, 40.0; K_q = 0.05,
                          τ_q = 0.2, X_c = 0.1)])
dump("gfm flat", oracle_solve(build_oracle(gfm; tier = :sauer_pai), (0.0, 3.0);
     saveat = grid))
dump("gfm line trip", oracle_solve(build_oracle(gfm; tier = :sauer_pai,
     perturbations = [1.0 => TripLine(:A, :B)]), (0.0, 3.0); saveat = grid))
