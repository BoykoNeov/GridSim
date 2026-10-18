# M10 step 2: is a swing gap the solver tolerance or unfinished settling (or, for the order run,
# path dependence)? Same pairs at two tolerances. julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
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
net = _m10_swing_case9(); s = dc_pair_outages(net)
for (a, b) in ((:L67, :G1), (:L45, :L94))
    p = _m10_pair(s, a, b); surv = _m10_survivors(net, s, p); evs = _m10_events(net, s, p)
    for rt in (1e-10, 1e-12)
        eng = SwingEngine(net; reltol = rt, abstol = rt / 100, dt = 0.05)
        foreach(ev -> inject!(eng, ev), evs)
        for T in (150.0, 300.0, 450.0, 900.0)
            while eng.integrator.t < T - 1e-9; step!(eng, 0.05); end
            st = current_state(eng)
            g = maximum(abs(st.ω[v] - pc.Δω) for (v, _, pc) in surv)
            println(a, "+", b, " reltol ", rt, " t ", T, " max ω gap ", g)
        end
    end
end
# The order run with the tightest margin (L67 then G1, 4.2e-8 against 1e-7): sequential
# against both at once, at two tolerances. Shrinking ~100x = the solver's; staying = path.
function _probe_run(net, first, Ts, rt; second = (), t2 = Inf)
    eng = SwingEngine(net; reltol = rt, abstol = rt / 100, dt = 0.05)
    export_of(bus) = sum((br.from === bus ? branch_power(eng, br.from, br.to) :
                          br.to === bus ? branch_power(eng, br.to, br.from) : 0.0) for br in net.branches)
    e0 = Dict(b.id => export_of(b.id) for b in net.buses)
    foreach(ev -> inject!(eng, ev), first); pending = !isempty(second); out = []
    for T in Ts
        if pending && T > t2
            while eng.integrator.t < t2 - 1e-9; step!(eng, 0.05); end
            foreach(ev -> inject!(eng, ev), second); pending = false
        end
        while eng.integrator.t < T - 1e-9; step!(eng, 0.05); end
        st = current_state(eng)
        push!(out, (; ω = copy(st.ω), Δx = Dict(b.id => export_of(b.id) - e0[b.id] for b in net.buses)))
    end
    out
end
p = _m10_pair(s, :L67, :G1); evs = _m10_events(net, s, p)
ia = findfirst(==(:L67), s.id) == s.pairs[p][1] ? 1 : 2
for rt in (1e-10, 1e-12)
    both = _probe_run(net, evs, (300.0, 450.0), rt)
    seq = _probe_run(net, [evs[ia]], (300.0, 600.0, 750.0), rt; second = [evs[3 - ia]], t2 = 300.0)
    gω = gx = 0.0
    for (o1, o2) in zip(both, seq[2:3]), (v, mc) in pairs(net.machines)
        mc.id === :G1 && continue
        gω = max(gω, abs(o1.ω[v] - o2.ω[v])); gx = max(gx, abs(o1.Δx[mc.bus] - o2.Δx[mc.bus]))
    end
    println("order L67 then G1 reltol ", rt, " max ω gap ", gω, " max export gap ", gx)
end
