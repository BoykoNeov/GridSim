# M9 step 1 gate, capture 4: step 0's lossless dip table (docs/evidence/gridsim-m9/
# step0_dips.jl) at shortest-round-trip precision. Same runs, same reads; `repr`
# instead of %8.4f so the comparison is bit-for-bit.
using GridSim
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end

function run_one(net, lost; T = 150.0, ttrip = 1.0, dt = 0.01)
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = 1e-8,
                abstol = 1e-10, solver = GridSim.OrdinaryDiffEq.FBDF())
    s = solve!(eng, (0.0, T); perturbations = [ttrip => TripGenerator(lost)], saveat = dt)
    t, f = s.t, s.f_coi
    i0 = findfirst(>=(ttrip), t)
    imin = argmin(f)
    i1 = findfirst(>=(ttrip + 0.1), t)
    rocof = (f[i1] - f[i0]) / (t[i1] - t[i0])
    ids = machine_ids(eng)
    mins = Dict(id => minimum(getproperty(s, Symbol(:ω_, id))[i0:end]) for id in ids if id != lost)
    worst_id = argmin(id -> mins[id], sort(collect(keys(mins))))
    return (; nadir = eng.nadir - net.f0, fnadir_ser = f[imin] - net.f0,
            tnadir = t[imin] - ttrip, settled = f[end] - net.f0, rocof,
            worst_id, worst = mins[worst_id] * net.f0, fpre = f[i0 - 1] - net.f0,
            nsamp = length(t), fsum = sum(f))
end

for (name, build) in (("case9", OS.case9), ("mesh", OS.mesh)), loads in (:constant_power, :default)
    net0 = build(; loads)
    net = NetworkModel(net0.S_base, net0.f0, net0.buses,
                       [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net0.branches],
                       net0.machines, net0.loads; slack = net0.slack)
    acg = ac_generator_outages(net)
    for (k, m) in enumerate(net.machines)
        tag = "$name $loads $(m.id)"
        r = try
            run_one(net, m.id)
        catch e
            println(tag, " FAILED ", typeof(e), ": ", sprint(showerror, e)[1:min(end, 300)])
            continue
        end
        println(tag, " AC.Δω = ", repr(acg.Δω[k]))
        for (key, v) in pairs(r)
            println(tag, " ", key, " = ", repr(v))
        end
    end
end
