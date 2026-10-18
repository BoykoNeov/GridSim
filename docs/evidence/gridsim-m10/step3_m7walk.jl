# M10 step 3 — what M7's exported-surface walk will do with `ac_pair_outages`, run directly
# (the focused runner does not load test/m7_inverters.jl). `_m7_pair` copied from there.
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m10/step3_m7walk.jl > step3_m7walk.out.txt
using GridSim

function _m7_pair(; mode::Symbol = :grid_following, P_inv::Real = 50.0)
    buses = [Bus(:B1, 230.0), Bus(:B2, 230.0)]
    branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
    machines = [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 100.0 - P_inv)]
    loads = [Load(:D2, :B2, 100.0, 0.0)]
    inverters = [Inverter(:I2, :B2, mode, 100.0, P_inv)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads;
                        inverters = inverters)
end

for mode in (:grid_following, :grid_forming)
    s = ac_pair_outages(_m7_pair(; mode))
    println(mode, ": returned, ", length(s.pairs), " pair(s)")
    for (p, (i, j)) in pairs(s.pairs), pc in s.pieces[p]
        println("  ", s.id[i], "+", s.id[j], "  ", pc.buses, "  ", pc.kind, "  ", pc.outcome)
    end
end
