# M10 step 2: the measured gaps behind each band (m10-context.md, "What step 2 measured").
# julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Test
const Graphs = GridSim.Graphs
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const _M10_MESH = OutageScreenScript.mesh
const _M10_CASE9 = OutageScreenScript.case9
src = read(raw"W:\Claude_projects\GridSim\test\m10_double_outages.jl", String)
i = findfirst("# case9 shaped for the swing tier", src).start
j = findfirst("@testset \"M10 step 2", src).start
include_string(Main, src[i:j-1])
function _m7_pair(; mode::Symbol = :grid_following, P_inv::Real = 50.0)
    NetworkModel(100.0, 50.0, [Bus(:B1, 230.0), Bus(:B2, 230.0)], [Branch(:L12, :B1, :B2, 0.2, 500.0)],
                 [Machine(:G1, :B1, 200.0, 5.0, 2.0, 0.3, 1.0, 100.0 - P_inv)], [Load(:D2, :B2, 100.0, 0.0)];
                 inverters = [Inverter(:I2, :B2, mode, 100.0, P_inv)])
end
for mode in (:grid_following, :grid_forming)
    s = dc_pair_outages(_m7_pair(mode = mode))
    println("m7 pair ", mode, ": returned, kinds ", [[pc.kind for pc in ps] for ps in s.pieces])
end
# swing
sw_ω = sw_x = 0.0
for (net, list) in [(_m10_swing_case9(), [(:L45, :L67), (:L45, :L56), (:L45, :L94), (:L14, :L82), (:L67, :G1), (:G1, :G2), (:L36, :G3)]),
                    (_m10_genmesh(), [(:AB, :AC), (:G2, :BC), (:G2, :LD), (:AB, :CD)])]
    s = dc_pair_outages(net)
    for (a, b) in list
        p = _m10_pair(s, a, b); surv = _m10_survivors(net, s, p)
        pw = px = 0.0
        for o in _m10_swing(net, _m10_events(net, s, p), (300.0, 450.0)), (v, mid, pc) in surv
            q = findfirst(==(mid), s.responders)
            pw = max(pw, abs(o.ω[v] - pc.Δω)); px = max(px, abs(o.Δexport[net.machines[q].bus] - s.pickup[p][q]))
        end
        println("swing ", a, "+", b, ": ω ", pw, "  export ", px, "  Δω ", [pc.Δω for pc in _m10_live(s, p)])
        global sw_ω = max(sw_ω, pw); global sw_x = max(sw_x, px)
    end
end
println("SWING max ω gap ", sw_ω, " max export gap ", sw_x)
or_m = 0.0
for (net, list, gm) in [(_m10_genmesh(), [(:G2, :LD), (:G2, :BC), (:AB, :CD), (:G2, :G3)], true), (_m10_swing_case9(), [(:L45, :L67), (:L67, :G1)], false)]
    s = dc_pair_outages(net)
    for (a, b) in list
        p = _m10_pair(s, a, b); evs = _m10_events(net, s, p)
        ia = findfirst(==(a), s.id) == s.pairs[p][1] ? 1 : 2
        both = _m10_swing(net, evs, (300.0, 450.0))
        seq = _m10_swing(net, [evs[ia]], (300.0, 600.0, 750.0); second = [evs[3-ia]], t2 = 300.0)
        gone = Set(s.id[e] for e in s.pairs[p]); g = 0.0
        for (o1, o2) in zip(both, seq[2:3]), (v, mc) in pairs(net.machines)
            mc.id in gone && continue
            g = max(g, abs(o1.ω[v] - o2.ω[v]), abs(o1.Δexport[mc.bus] - o2.Δexport[mc.bus]))
        end
        cap = gm && a === :G2 ? abs(seq[1].ΔPm[5] - 0.05) : NaN
        println("order ", a, " then ", b, ": gap ", g, "  |ΔPm_G3 - 0.05| after A ", cap)
        global or_m = max(or_m, g)
    end
end
println("ORDER max gap ", or_m)
c9 = _M10_CASE9(); s = dc_pair_outages(c9); g = dc_generator_outages(c9)
for p in findall(!=(:none), s.same_as)
    k = findfirst(==(s.same_as[p]), g.machines); pc = only(_m10_live(s, p))
    println("collapsed ", s.id[s.pairs[p][1]], "+", s.same_as[p], ": Δω rel ", abs(pc.Δω - g.Δω[k]) / abs(g.Δω[k]),
            " pickup ", maximum(abs.(s.pickup[p] .- g.pickup[k])), " flow ", maximum(abs.(s.flow[p] .- g.flow[k])),
            " band ", 100eps() * maximum(abs, g.flow[k]))
end
ps = [_m10_pair(s, a, b) for (a, b) in ((:L14, :L82), (:L14, :G2), (:L82, :G1), (:G1, :G2))]
for p in ps[1:3]
    println("path ", s.id[collect(s.pairs[p])], ": Δω ", abs(only(_m10_live(s, p)).Δω - only(_m10_live(s, ps[4])).Δω), " flow ", maximum(abs.(s.flow[p] .- s.flow[ps[4]])))
end
p = _m10_pair(s, :L45, :L67); println("L45+L67 Δω ", [(pc.buses, pc.imbalance * 100, pc.Δω) for pc in s.pieces[p]])
