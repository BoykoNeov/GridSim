# M10 step 5 — what M7's exported-surface walk will do with the two sequential screens, run
# directly (the focused runner does not load test/m7_inverters.jl). `_m7_pair` copied from
# there; both inverter kinds.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
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

for mode in (:grid_following, :grid_forming), (what, f) in (("DC", dc_sequential_outages),
                                                             ("AC", ac_sequential_outages))
    s = f(_m7_pair(; mode))
    println(mode, " ", what, ": returned, ", length(s.pairs), " ordered pair(s)")
    for rs in s.restore
        println("  restore after ", rs.element, ": ",
                join(["$(pc.buses) $(pc.kind) $(pc.outcome)" for pc in rs.pieces], "; "),
                "  pickup(MW) ", round.(rs.pickup .* 100; digits = 6), "  capped ", rs.capped)
        for (c, R) in pairs(rs.models)
            R === nothing && continue
            println("    restored model: ", [m.id => m.P0 for m in R.machines],
                    " ", [i.id => (i.mode, i.P0) for i in R.inverters])
        end
    end
    for (p, (a, b)) in pairs(s.pairs)
        println("  ", s.id[a], "→", s.id[b], "  ", s.outcome[p], "  ",
                join(["$(pc.buses) $(pc.outcome)" for pc in s.pieces[p]], "; "))
    end
end
