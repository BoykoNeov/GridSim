# Serialize both pair screens on every fixture steps 2-3 use, so a refactor of their
# loop bodies can be gated byte for byte.  julia --project=<root>/docs/evidence/gridsim-m9/harness/testenv snapshot.jl <root> <out>
using GridSim, Serialization
root, out = ARGS[1], ARGS[2]
module OutageScreenScript
include(joinpath(ARGS[1], "scripts", "outage_screen.jl"))
end

function swing_case9()
    c9 = OutageScreenScript.case9()
    br = [Branch(b.id, b.from, b.to, b.X, b.rating) for b in c9.branches]
    ms = [c9.machines;
          [Machine(l.id, l.bus, 100.0, 1.0, 1.0, 0.25, 1.0, -l.P0) for l in c9.loads];
          [Machine(Symbol(:F, i), Symbol(:B, i), 100.0, 1.0, 0.5, 0.25, 1.0, 0.0) for i in (4, 6, 8)]]
    NetworkModel(c9.S_base, c9.f0, c9.buses, br, ms; slack = c9.slack)
end
function genmesh()
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.05, 150.0, 0.05, 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0, 0.04, 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5, 0.25, 1.00, -120.0),
          Machine(:G3, :E, 120.0, 3.5, 1.5, 0.25, 1.02, 40.0, 0.06, 45.0, 0.6)]
    br = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
          Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
          Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0),
          Branch(:BE, :B, :E, 0.20, 500.0)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms; slack = :A)
end
function corner(mode)
    iv = mode === :grid_forming ? Inverter(:I3, :C, :grid_forming, 100.0, 20.0; K_p = 0.1) :
                                  Inverter(:I3, :C, :grid_following, 100.0, 20.0)
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C)],
        [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:BC, :B, :C, 0.15, 500.0),
         Branch(:CA, :C, :A, 0.20, 500.0)],
        [Machine(:G1, :A, 200.0, 5.0, 1.0, 0.25, 1.0, 60.0, 0.05, 200.0)],
        [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0)]; slack = :A, inverters = [iv])
end

nets = [("case9 cp", OutageScreenScript.case9(; loads = :constant_power)),
        ("case9 def", OutageScreenScript.case9(; loads = :default)),
        ("mesh cp", OutageScreenScript.mesh(; loads = :constant_power)),
        ("mesh def", OutageScreenScript.mesh(; loads = :default)),
        ("swing case9", swing_case9()), ("genmesh", genmesh()),
        ("corner gfm", corner(:grid_forming)), ("corner gfl", corner(:grid_following))]
mkpath(out)
for (name, net) in nets
    for (what, f) in (("dc", dc_pair_outages), ("ac", ac_pair_outages))
        s = try
            f(net)
        catch e
            sprint(showerror, e)
        end
        open(joinpath(out, replace("$name $what", " " => "_") * ".bin"), "w") do io
            serialize(io, s)
        end
        println(rpad("$name $what", 18), s isa String ? s : "ok")
    end
end
