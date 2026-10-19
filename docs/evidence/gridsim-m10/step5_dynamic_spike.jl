# M10 step 5 — spike for the dynamic check (Hurdle 21's only independent one), run BEFORE
# its test was written: the detailed tier initialised on the AC restored model, the second
# element tripped, run to 300 s and 400 s; per live piece, the settled frequency against the
# AC sequential screen's, through M9's losses identity taken per piece (step 4's form):
#     ω_dyn − Δω_AC = −[(L_dyn + D_dyn) − (L_AC + D_AC)] / Σw_piece.
# Candidates read from step5_offset_probe.out.txt: final pieces :secure, nothing capped.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Printf
const OrdinaryDiffEq = GridSim.OrdinaryDiffEq
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end

function piece_identity(eng, net, pc)
    inp(bus) = bus in pc.buses
    ma, st = machine_arrays(net), current_state(eng)
    ks = [k for (k, m) in pairs(net.machines) if inp(m.bus) && is_online(eng, m.id)]
    ωs = st.ω[ks]
    ω = sum(ωs) / length(ωs)
    Σw = sum(ma.invR[k] + ma.D[k] for k in ks)
    both(b) = branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
    L = sum(both(b) for b in net.branches if inp(b.from) && inp(b.to) &&
                                             is_online(eng, b.from, b.to); init = 0.0)
    D = sum(l.P0 / net.S_base * (l.a_z * st.V[net.bus_index[l.bus]]^2 +
                                 l.a_i * st.V[net.bus_index[l.bus]] + l.a_p)
            for l in net.loads if inp(l.bus); init = 0.0)
    ac = sum(pc.solution.loss) + sum(pc.solution.Pload)
    capped = any(st.ΔPm[k] >= ma.headroom[k] - 1e-6 for k in ks)
    return (; lhs = ω - pc.Δω, rhs = -(L + D - ac) / Σw, ω, spread = maximum(ωs) - minimum(ωs),
            capped)
end

cases = [(:default, :L78, :G2), (:default, :L89, :G2), (:default, :L56, :G3),
         (:default, :L67, :G3), (:default, :L56, :L78), (:default, :L45, :L67),
         (:constant_power, :L56, :G3), (:constant_power, :L78, :G2),
         (:constant_power, :L89, :G2), (:constant_power, :L67, :G3),
         (:constant_power, :L56, :L78)]
for (loads, a, b) in cases
    net = OutageScreenScript.case9(; loads)
    s = ac_sequential_outages(net)
    ia, ib = findfirst(==(a), s.id), findfirst(==(b), s.id)
    p = findfirst(==((ia, ib)), s.pairs)
    rs = s.restore[ia]
    c = only(i for (i, pc) in pairs(rs.pieces) if pc.kind === :live)
    R, base = rs.models[c], rs.bases[c]
    live = [pc for pc in s.pieces[p] if pc.kind === :live]
    @printf("\n%s %s→%s: %s; final %s\n", loads, a, b, s.outcome[p],
            join(["$(pc.outcome) Δω=$(pc.Δω)" for pc in live], " | "))
    try
        eng = init!(DetailedEngine, R; powerflow = base, reltol = 1e-10, abstol = 1e-12,
                    solver = OrdinaryDiffEq.Rodas5P())
        solve!(eng, (0.0, 1.0); saveat = 0.5)
        @printf("  flat 1 s: max|ω| %.2e\n", maximum(abs, current_state(eng).ω))
        ev = s.kind[ib] === :machine ? TripGenerator(b) :
             TripElements(lines = [(br.from, br.to) for br in R.branches if br.id === b])
        inject!(eng, ev)
        solve!(eng, (1.0, 300.0); saveat = 0.5)
        r300 = [piece_identity(eng, R, pc) for pc in live]
        solve!(eng, (300.0, 400.0); saveat = 0.5)
        for (i, pc) in pairs(live)
            r = piece_identity(eng, R, pc)
            @printf("  piece %-28s ω %+.9e  Δω_AC %+.9e  lhs %+.3e rhs %+.3e  rel %.2e  settle %.1e  spread %.1e  capped %s\n",
                    join(String.(pc.buses), ","), r.ω,
                    pc.Δω, r.lhs, r.rhs, abs(r.lhs - r.rhs) / abs(r.lhs),
                    abs(r.ω - r300[i].ω), r.spread, r.capped)
        end
    catch e
        println("  REFUSED/FAILED: ", first(sprint(showerror, e), 300))
    end
end
