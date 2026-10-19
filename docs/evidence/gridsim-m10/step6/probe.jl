# Kept as step 6's evidence (m10-context.md D12, "What step 6 measured"); re-run on the committed
# code, output in probe.out.txt.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
# Step 6 probe (first run BEFORE the D12.1 fix printed the mesh G1 AC restore capped [0,1,1];
# this re-run is after it): screen timings, refused-piece capped flags, and the piece shapes the
# per-piece verdict must map (D12).
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
const O = OutageScreenScript

for (g, f) in (("case9", O.case9), ("mesh", O.mesh)), loads in (:constant_power, :default)
    net = f(; loads)
    t = @elapsed begin
        dp = dc_pair_outages(net); ap = ac_pair_outages(net)
        ds = dc_sequential_outages(net); as = ac_sequential_outages(net)
    end
    t2 = @elapsed begin
        dp = dc_pair_outages(net); ap = ac_pair_outages(net)
        ds = dc_sequential_outages(net); as = ac_sequential_outages(net)
    end
    @printf("%s %s: first %.1f s, again %.2f s\n", g, loads, t, t2)
    # Refused live pieces whose capped flags are still set (pair screens).
    for (scr, nm) in ((dp, "DC pair"), (ap, "AC pair"))
        for (p, pcs) in pairs(scr.pieces)
            for pc in pcs
                pc.kind === :live || continue
                bad = isnan(pc.Δω) && pc.outcome ∉ (:secure, :overload, :voltage)
                if bad && any(scr.capped[p])
                    println("  $nm $(scr.id[scr.pairs[p][1]])+$(scr.id[scr.pairs[p][2]]): piece $(pc.outcome) Δω NaN, capped ", scr.responders[scr.capped[p]])
                end
            end
        end
    end
    for (rs_all, nm) in ((ds.restore, "DC restore"), (as.restore, "AC restore"))
        for rs in rs_all
            if any(pc -> pc.outcome === :restore_refused || pc.outcome === :no_response, rs.pieces)
                println("  $nm $(rs.element): ", [pc.outcome for pc in rs.pieces if pc.kind === :live],
                        " capped=", rs.capped, " pickup=", rs.pickup)
            end
        end
    end
    # Piece shapes: outcome × Δω finiteness, per screen.
    shapes(pcs_all) = sort!(collect(Set((pc.kind, pc.outcome, isnan(pc.Δω) ? :NaN : pc.Δω == 0.0 ? :zero : :value)
                                        for pcs in pcs_all for pc in pcs)))
    println("  DC pair shapes: ", shapes(dp.pieces))
    println("  AC pair shapes: ", shapes(ap.pieces))
    println("  DC seq shapes:  ", shapes(ds.pieces[ds.outcome .=== :screened]))
    println("  AC seq shapes:  ", shapes(as.pieces[as.outcome .=== :screened]))
    tally(v) = join(["$k=$(count(==(k), v))" for k in sort!(unique(v))], " ")
    println("  DC seq outcomes: ", tally(ds.outcome), " | AC seq outcomes: ", tally(as.outcome))
    println("  pairs: ", length(dp.pairs), " splits=", count(dp.splits), " same_as=", count(!=(:none), dp.same_as))
end
