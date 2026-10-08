# M8 step 1 gate (c): `ac_powerflow` itself, field by field at shortest-round-trip
# precision, and every refusal's exception type and FULL message. M5's criterion
# harness never calls `ac_powerflow` (scripts/iberia_two_area.jl reaches only the
# detailed tier's `_check_power_flow`), so it cannot see the step-1 restructure.
#
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/ac_snapshot.jl > <out>.txt
using GridSim

br(id, f, t, r, x, rate) = Branch(id, Symbol(:B, f), Symbol(:B, t), x, rate; R = r)
const ALL = [br(:L14, 1, 4, 0.0, 0.0576, 250.0), br(:L45, 4, 5, 0.017, 0.092, 250.0),
       br(:L56, 5, 6, 0.039, 0.17, 150.0), br(:L36, 3, 6, 0.0, 0.0586, 300.0),
       br(:L67, 6, 7, 0.0119, 0.1008, 150.0), br(:L78, 7, 8, 0.0085, 0.072, 250.0),
       br(:L82, 8, 2, 0.0, 0.0625, 250.0), br(:L89, 8, 9, 0.032, 0.161, 250.0),
       br(:L94, 9, 4, 0.01, 0.085, 250.0)]
const Pmax = (250.0, 300.0, 270.0); const Vg = (1.04, 1.025, 1.025)

function case9(branches, load; cp = true, Qlim = 3.0, rate = 1.0)
    s = load / 315
    branches = [Branch(b.id, b.from, b.to, b.X, rate * b.rating; R = b.R) for b in branches]
    ms = [Machine(Symbol(:G, i), Symbol(:B, i), 100.0, 5.0, 0.0, 0.2, 1.0,
                  load * Pmax[i] / sum(Pmax), Inf, Pmax[i];
                  V_set = Vg[i], Q_min = -Qlim, Q_max = Qlim) for i in 1:3]
    ld(id, b, p, q) = cp ? Load(id, b, p, q, 0, 0, 1) : Load(id, b, p, q)
    ls = [ld(:D5, :B5, 90s, 30s), ld(:D7, :B7, 100s, 35s), ld(:D9, :B9, 125s, 50s)]
    NetworkModel(100.0, 50.0, [Bus(Symbol(:B, i), 345.0) for i in 1:9], branches, ms, ls;
                 slack = :B1)
end

function dump(tag, mk)
    println("== ", tag)
    net = try mk() catch e
        println("MODEL ", typeof(e), ": ", sprint(showerror, e)); return
    end
    sol = try ac_powerflow(net) catch e
        println("THROW ", typeof(e), ": ", sprint(showerror, e)); return
    end
    for f in fieldnames(ACPowerFlow)
        println(rpad(string(f), 10), " = ", repr(getfield(sol, f)))
    end
end

for (lbl, kw) in (("cp", (cp = true,)), ("zip", (cp = false,)), ("cp-Qlim0.3", (cp = true, Qlim = 0.3)), ("cp-rate0.6", (cp = true, rate = 0.6)))
    for load in (315.0, 400.0)
        dump("case9 $lbl $load base", () -> case9(ALL, load; kw...))
        for k in ALL
            dump("case9 $lbl $load -$(k.id)", () -> case9(filter(b -> b !== k, ALL), load; kw...))
        end
    end
end

inv_slack(S) = NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)],
                            [Branch(:AB, :A, :B, 0.1, 500.0)], Machine[],
                            [Load(:D, :B, 40.0, 30.0, 0.0, 0.0, 1.0)];
                            inverters = [Inverter(:gf, :A, :grid_forming, S, 40.0)])
dump("inverter slack 60", () -> inv_slack(60.0))
dump("inverter slack 50", () -> inv_slack(50.0))
dump("slack without source", () -> NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)],
        [Branch(:AB, :A, :B, 0.1, 500.0)],
        [Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 40.0, Inf, 50.0)],
        [Load(:D, :B, 40.0, 30.0)]; slack = :A))
