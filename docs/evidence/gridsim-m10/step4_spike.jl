# M10 step 4, spike: before building the one-event trip, does ONE re-solve of the final
# network (both lines open at once, no intermediate network) pass on the pairs step 4 needs?
# And does grounding a dead bus through its own load slot (G = 1, B = 0, a_i = a_p = 0)
# give the static solve a unique answer (|V| = 0) where leaving it alone gives nonsense?
# Uses engine internals on purpose; nothing here is API. docs/plans/m10-context.md D10.
using GridSim
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
import OrdinaryDiffEq, NetworkDynamics
const SII = NetworkDynamics.SII

function trial(net, lines; dead = Symbol[], ground = false)
    base = ac_powerflow(net)
    eng = init!(DetailedEngine, net; powerflow = base, reltol = 1e-8, abstol = 1e-10,
                solver = OrdinaryDiffEq.FBDF())
    solve!(eng, (0.0, 1.0); saveat = 0.05)
    for (a, b) in lines
        e = GridSim._detailed_branch_index(eng, a, b)
        delete!(eng.lines_online, e)
        eng.params[eng.status_pidx[e]] = 0.0
        eng.p_static[eng.sstatus_pidx[e]] = 0.0
    end
    if ground
        for bus in dead, (nw, p) in ((eng.nw, eng.params), (eng.nw_static, eng.p_static))
            v = net.bus_index[bus]
            for (s, x) in ((:G, 1.0), (:B, 0.0), (:a_i, 0.0), (:a_p, 0.0))
                p[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, s))] = x
            end
        end
    end
    reason, err = GridSim._reinitialise_outcome!(eng)
    V = [hypot(eng.u_static[eng.sVre_idx[v]], eng.u_static[eng.sVim_idx[v]])
         for v in eachindex(net.buses)]
    live = [v for v in eachindex(net.buses) if !(net.buses[v].id in dead)]
    print("   reason=", rpad(reason, 9), " live |V| in [", round(minimum(V[live]); digits = 4),
          ", ", round(maximum(V[live]); digits = 4), "]")
    isempty(dead) || print("  dead |V| = ", [V[net.bus_index[b]] for b in dead])
    err === nothing || print("\n   ", first(sprint(showerror, err), 120))
    println()
end

for lm in (:default, :constant_power)
    net = case9(loads = lm)
    println("== $lm")
    for (name, ls) in (("L45+L67", [(:B4, :B5), (:B6, :B7)]),
                       ("L56+L78", [(:B5, :B6), (:B7, :B8)]),
                       ("L67+L89", [(:B6, :B7), (:B8, :B9)]))
        println(" ", name); trial(net, ls)
    end
    println(" L45+L56, B5 left alone"); trial(net, [(:B4, :B5), (:B5, :B6)]; dead = [:B5])
    println(" L45+L56, B5 grounded");   trial(net, [(:B4, :B5), (:B5, :B6)]; dead = [:B5], ground = true)
end
