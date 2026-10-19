# M10 step 5 — what separates the two orders, probed AFTER the order table was read
# (step5_pairs.out.txt). On every pair where A→B and both-at-once are BOTH :secure in every
# live piece (AC) or answered (DC), the gap per piece, both − (A→B), against what the restore
# after A moved: Σ restore pickups of the piece's units over the piece's Σ(1/R + D) — the
# frequency A alone would have settled to, which the restore cancels before B.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end

ok(pc, fid) = fid === :dc ? pc.outcome === :shared : pc.outcome === :secure

function probe(name, net, fid)
    seq = fid === :dc ? dc_sequential_outages(net) : ac_sequential_outages(net)
    sim = fid === :dc ? dc_pair_outages(net) : ac_pair_outages(net)
    r = GridSim._responders(net)
    busof = [net.buses[v].id for v in r.bus]
    println("\n=== $name $(uppercase(String(fid)))")
    worst_rel, n = 0.0, 0
    for (p, (a, b)) in pairs(seq.pairs)
        seq.outcome[p] === :screened || continue
        q = findfirst(==((min(a, b), max(a, b))), sim.pairs)
        ls = Dict(Set(pc.buses) => pc for pc in seq.pieces[p] if pc.kind === :live)
        lb = Dict(Set(pc.buses) => pc for pc in sim.pieces[q] if pc.kind === :live)
        keys(ls) == keys(lb) || continue
        all(pc -> ok(pc, fid) && !isnan(pc.Δω), values(ls)) || continue
        all(pc -> ok(pc, fid) && !isnan(pc.Δω), values(lb)) || continue
        (any(seq.capped[p]) || any(sim.capped[q])) && continue      # caps break the sum
        rs = seq.restore[a]
        for (k, pc) in ls
            units = [i for i in eachindex(r.ids) if busof[i] in k && r.ids[i] !== seq.id[a] &&
                     r.ids[i] !== seq.id[b]]
            pred = -sum(rs.pickup[units]) / sum(r.g[units] .+ r.d[units])
            gap = lb[k].Δω - pc.Δω
            rel = abs(gap - pred) / max(abs(pred), 1e-300)
            abs(pred) > 0 && (worst_rel = max(worst_rel, rel); n += 1)
            @printf("%-4s→%-4s %-24s both %+.6e  A→B %+.6e  gap %+.6e  pred %+.6e  rel %.2e\n",
                    seq.id[a], seq.id[b], join(sort!(String.(collect(k))), ","), lb[k].Δω,
                    pc.Δω, gap, pred, abs(pred) > 0 ? rel : 0.0)
        end
    end
    @printf("WORST %s %s: %d pieces with a nonzero restore, worst relative miss %.3e\n",
            name, uppercase(String(fid)), n, worst_rel)
end

for (gname, f) in (("case9", OutageScreenScript.case9), ("mesh", OutageScreenScript.mesh))
    probe(gname, f(), :dc)
    for loads in (:constant_power, :default)
        probe("$gname $loads", f(; loads), :ac)
    end
end
