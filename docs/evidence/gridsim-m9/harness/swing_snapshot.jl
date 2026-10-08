# M9 step 2 gate, capture 5: the classical (swing) tier at full precision (`repr`), so
# "bit-identical at R = 0" is a text comparison. Every fixture the swing tier's tests
# lean on, every generator trip and every line trip, the state and every branch's power
# (both ends) read before and after, plus one playback run through `branch_power_series`.
#
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/swing_snapshot.jl > <out>.txt
using GridSim, Test
import OrdinaryDiffEq, SciMLBase, NetworkDynamics, Graphs
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")

# M8 step 4's mesh, copied verbatim from test/m8_screening.jl (`_m8_genmesh`).
function genmesh(; damp = 1.0, gov = true, gfm = false, slack = :A)
    R(r) = gov ? r : Inf
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0damp, 0.25, 1.05, 150.0, R(0.05), 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0damp, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0damp, 0.25, 1.04, 60.0, R(0.04), 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5damp, 0.25, 1.00, -120.0)]
    invs = gfm ? [Inverter(:I3, :E, :grid_forming, 300.0, 40.0; K_p = 0.125, V_set = 1.02)] :
                 Inverter[]
    gfm || push!(ms, Machine(:G3, :E, 120.0, 3.5, 1.5damp, 0.25, 1.02, 40.0, R(0.06), 45.0, 0.6))
    br = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
          Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
          Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0),
          Branch(:BE, :B, :E, 0.20, 500.0)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms;
                 slack, inverters = invs)
end

both_ends(eng) = [(branch_power(eng, b.from, b.to), branch_power(eng, b.to, b.from))
                  for b in eng.model.branches]

function run_to(eng, T)
    while eng.integrator.t < T - 1e-9
        step!(eng, 0.05)
    end
end

fixtures = [("two_machine", two_machine_system()), ("three_ring", three_machine_ring()),
            ("ratio_ring", ratio_ring()), ("quiet_ring", quiet_ring()),
            ("genmesh", genmesh()), ("genmesh_nogov", genmesh(gov = false)),
            ("genmesh_gfm", genmesh(gfm = true))]

for (name, net) in fixtures
    println("== ", name)
    eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
    println("u0 = ", repr(eng.integrator.u))
    println("p0 = ", repr(eng.integrator.p))
    println("P0 = ", repr(both_ends(eng)))
    events = vcat([TripGenerator(id) for id in eng.ids if !(id in Set(i.id for i in net.inverters))],
                  [TripLine(b.from, b.to) for b in net.branches])
    for ev in events
        e = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
        run_to(e, 1.0)
        inject!(e, ev)
        run_to(e, 20.0)
        println("-- ", ev)
        println("u  = ", repr(e.integrator.u))
        println("P  = ", repr(both_ends(e)))
        println("st = ", repr(current_state(e)))
        println("coi_rocof = ", repr(coi_rocof(e)))
    end
end

println("== playback, two_machine, a Pm step")
let eng = SwingEngine(two_machine_system(); reltol = 1e-9, abstol = 1e-12)
    eng.params[eng.Pm_pidx[1]] += 0.05
    ser = solve!(eng, (0.0, 5.0); saveat = 0.1)
    println("f_coi = ", repr(ser.f_coi))
    bs = branch_power_series(eng, :B1, :B2)
    println("series = ", repr(bs.P))
    println("series_rev = ", repr(branch_power_series(eng, :B2, :B1).P))
end
