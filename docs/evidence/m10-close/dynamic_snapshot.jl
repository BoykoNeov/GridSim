# M10 close: a full-precision capture of M10's DYNAMIC numbers, which no other capture reaches
# (the snapshots and the report are the static DC/AC screens only). The detailed tier on
# Rodas5P at reltol 1e-10, the solver steps 4 and 5 use: step 4's `TripElements` cases (both at
# once, from the base AC solution) and step 5's (the second element tripped on the AC restored
# model). Every state, `repr`, at 1 s (before the trip), 5 s and 20 s; a refusal prints its type.
# Run before and after the manifests are re-resolved and compare with `cmp`.
#   julia --project=<tree> dynamic_snapshot.jl <tree>
using GridSim
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
const TREE = ARGS[1]
module OutageScreenScript
include(joinpath(Main.TREE, "scripts", "outage_screen.jl"))
end

function capture(label, net, pf, event)
    println("== ", label)
    try
        eng = init!(DetailedEngine, net; powerflow = pf, reltol = 1e-10, abstol = 1e-12,
                    solver = OrdinaryDiffEq.Rodas5P())
        solve!(eng, (0.0, 1.0); saveat = 0.5)
        println("u(1) = ", repr(eng.integrator.u))
        inject!(eng, event(net))
        for T in (5.0, 20.0)
            solve!(eng, (eng.integrator.t, T); saveat = 0.5)
            println("u($(Int(T))) = ", repr(eng.integrator.u))
        end
    catch e
        println("refused: ", typeof(e))
    end
end

lines(net, ids) = [(b.from, b.to) for id in ids for b in net.branches if b.id === id]

# Step 4: both at once (step4_settle_probe.jl's six, plus a refusal at the trip).
for (loads, ids) in [(:constant_power, (:L56, :L78)), (:constant_power, (:L45, :L56)),
                     (:constant_power, (:L45, :L67)),
                     (:default, (:L45, :L67)), (:default, (:L56, :L78)),
                     (:default, (:L67, :L89)), (:default, (:L45, :L56))]
    net = OutageScreenScript.case9(; loads)
    capture("step4 $loads $(join(ids, '+'))", net, ac_powerflow(net),
            n -> TripElements(lines = lines(n, ids)))
end

# Step 5: the second loss on the restored model (step5_dynamic_spike.jl's eleven).
for (loads, a, b) in [(:default, :L78, :G2), (:default, :L89, :G2), (:default, :L56, :G3),
                      (:default, :L67, :G3), (:default, :L56, :L78), (:default, :L45, :L67),
                      (:constant_power, :L56, :G3), (:constant_power, :L78, :G2),
                      (:constant_power, :L89, :G2), (:constant_power, :L67, :G3),
                      (:constant_power, :L56, :L78)]
    net = OutageScreenScript.case9(; loads)
    s = ac_sequential_outages(net)
    ia, ib = findfirst(==(a), s.id), findfirst(==(b), s.id)
    rs = s.restore[ia]
    c = only(i for (i, pc) in pairs(rs.pieces) if pc.kind === :live)
    capture("step5 $loads $a→$b", rs.models[c], rs.bases[c],
            n -> s.kind[ib] === :machine ? TripGenerator(b) : TripElements(lines = lines(n, (b,))))
end
