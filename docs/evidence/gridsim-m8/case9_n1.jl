using GridSim, Printf
br(id, f, t, r, x, rate) = Branch(id, Symbol(:B, f), Symbol(:B, t), x, rate; R = r)
const ALL = [br(:L14, 1, 4, 0.0, 0.0576, 250.0), br(:L45, 4, 5, 0.017, 0.092, 250.0),
       br(:L56, 5, 6, 0.039, 0.17, 150.0), br(:L36, 3, 6, 0.0, 0.0586, 300.0),
       br(:L67, 6, 7, 0.0119, 0.1008, 150.0), br(:L78, 7, 8, 0.0085, 0.072, 250.0),
       br(:L82, 8, 2, 0.0, 0.0625, 250.0), br(:L89, 8, 9, 0.032, 0.161, 250.0),
       br(:L94, 9, 4, 0.01, 0.085, 250.0)]
Pmax = (250.0, 300.0, 270.0); Vg = (1.04, 1.025, 1.025)
function net(branches, load)
    s = load / 315
    ms = [Machine(Symbol(:G, i), Symbol(:B, i), 100.0, 5.0, 0.0, 0.2, 1.0, load * Pmax[i] / sum(Pmax), Inf, Pmax[i];
                  V_set = Vg[i], Q_min = -3.0, Q_max = 3.0) for i in 1:3]
    ls = [Load(:D5, :B5, 90s, 30s, 0, 0, 1), Load(:D7, :B7, 100s, 35s, 0, 0, 1), Load(:D9, :B9, 125s, 50s, 0, 0, 1)]
    NetworkModel(100.0, 50.0, [Bus(Symbol(:B, i), 345.0) for i in 1:9], branches, ms, ls; slack = :B1)
end
for load in (315.0, 400.0)
    println("== load $load MW")
    for k in ALL
        rest = filter(b -> b !== k, ALL)
        n = try net(rest, load) catch e; println(rpad(k.id, 4), " refused (islands)"); continue end
        dc = dc_powerflow(n)
        dcload = [abs(f) * 100 / b.rating for (b, f) in zip(rest, dc.flow)]
        j = argmax(dcload)
        ac = try
            ac_powerflow(n); "AC ok"
        catch e
            m = sprint(showerror, e); "AC refuses: " * m[1:min(end, 110)]
        end
        @printf("%-4s DC worst %-4s at %5.1f%% of rating | %s\n", k.id, rest[j].id, 100dcload[j], ac)
    end
end
