# M9 step 0: dips, RoCoF and settled frequency for every generator outage, detailed tier.
using GridSim, Printf
module OutageScreenScript
include(joinpath("W:/Claude_projects/GridSim", "scripts", "outage_screen.jl"))
end
const OS = OutageScreenScript

function run_one(net, lost; T = 150.0, ttrip = 1.0, dt = 0.01)
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = 1e-8,
                abstol = 1e-10, solver = GridSim.OrdinaryDiffEq.FBDF())
    s = solve!(eng, (0.0, T); perturbations = [ttrip => TripGenerator(lost)], saveat = dt)
    t, f = s.t, s.f_coi
    i0 = findfirst(>=(ttrip), t)
    fpre = f[i0 - 1]
    imin = argmin(f)
    # initial RoCoF over the first 0.1 s after the trip
    i1 = findfirst(>=(ttrip + 0.1), t)
    rocof = (f[i1] - f[i0]) / (t[i1] - t[i0])
    ids = machine_ids(eng)
    mins = Dict(id => minimum(getproperty(s, Symbol(:ω_, id))[i0:end]) for id in ids if id != lost)
    f0 = net.f0
    worst_id = argmin(id -> mins[id], collect(keys(mins)))
    return (; nadir = eng.nadir - f0, fnadir_ser = f[imin] - f0, tnadir = t[imin] - ttrip,
            settled = f[end] - f0, tail = f[end] - f[end - 1000], rocof,
            worst_id, worst = mins[worst_id] * f0, fpre = fpre - f0)
end

for (name, build) in (("case9", OS.case9), ("mesh", OS.mesh)), loads in (:constant_power, :default)
    net0 = build(; loads)
    net = NetworkModel(net0.S_base, net0.f0, net0.buses, [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net0.branches], net0.machines, net0.loads; slack = net0.slack)  # LOSSLESS copy: the dynamic tiers refuse R
    acg = ac_generator_outages(net)
    for (k, m) in enumerate(net.machines)
        r = try
            run_one(net, m.id)
        catch e
            println(rpad("$name $loads $(m.id)", 30), " FAILED: ", sprint(showerror, e)[1:min(end, 200)])
            continue
        end
        acdf = acg.Δω[k] * net.f0
        @printf("%-30s nadir %8.4f Hz (ser %8.4f) at %6.2f s | settled %8.4f (AC screen %8.4f, tail drift %.1e) | dip/settled %5.2f | RoCoF0 %7.3f Hz/s | worst machine %s %8.4f Hz | pre %.1e\n",
                "$name $loads $(m.id)", r.nadir, r.fnadir_ser, r.tnadir, r.settled, acdf, r.tail,
                r.nadir / r.settled, r.rocof, r.worst_id, r.worst, r.fpre)
    end
end
