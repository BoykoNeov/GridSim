# M10 step 5 — the order table (Hurdle 21.4): every unordered pair {A, B} of both report
# grids, both load models, both fidelities — A then B, B then A (frequency restored in
# between), and both at once. Printed BEFORE any claim about order was written.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Printf
module OutageScreenScript
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end

# Live pieces by bus set: Δω (NaN where none) and outcome.
livemap(pieces) = Dict(Set(pc.buses) => (pc.Δω, pc.outcome) for pc in pieces if pc.kind === :live)
fmt(x) = isnan(x) ? "     NaN    " : @sprintf("%+.6e", x)
pieces_str(pm) = join(["{" * join(sort!(String.(collect(k))), ",") * "} " * fmt(v[1]) * " " *
                       String(v[2]) for (k, v) in sort!(collect(pm); by = p -> minimum(String.(collect(p[1]))))], "; ")

# The worst |Δω| over the live pieces that answered; NaN if none (an AC whole piece that
# lost lines has no Δω by design).
function worst(pm)
    xs = [abs(v[1]) for v in values(pm) if !isnan(v[1])]
    return isempty(xs) ? NaN : maximum(xs)
end
same(x, y) = abs(x - y) <= 1e-9 * max(abs(x), abs(y)) + 1e-15

function table(name, net, fid)
    S = net.S_base
    seq = fid === :dc ? dc_sequential_outages(net) : ac_sequential_outages(net)
    sim = fid === :dc ? dc_pair_outages(net) : ac_pair_outages(net)
    seqi = Dict(ab => p for (p, ab) in pairs(seq.pairs))
    println("\n=== $name — $(uppercase(String(fid))) — $(length(sim.pairs)) unordered pairs")
    tally = Dict{Symbol,Int}()
    who = Dict{Symbol,Vector{String}}()
    pair_name = ""
    function bump(k)
        tally[k] = get(tally, k, 0) + 1
        push!(get!(who, k, String[]), pair_name)
    end
    for (q, (a, b)) in pairs(sim.pairs)
        pab, pba = seqi[(a, b)], seqi[(b, a)]
        mb = livemap(sim.pieces[q])
        mab, mba = livemap(seq.pieces[pab]), livemap(seq.pieces[pba])
        @printf("%-4s+%-4s both: %s\n", seq.id[a], seq.id[b], pieces_str(mb))
        @printf("   %-4s→%-4s %-13s %s\n", seq.id[a], seq.id[b], seq.outcome[pab], pieces_str(mab))
        @printf("   %-4s→%-4s %-13s %s\n", seq.id[b], seq.id[a], seq.outcome[pba], pieces_str(mba))
        dpk = maximum(abs, seq.pickup[pab] .- seq.pickup[pba]) * S
        line = @sprintf("   dispatch A→B vs B→A: max |Δ| %.3e MW", dpk)
        if fid === :dc
            df = maximum(abs, filter(!isnan, seq.flow[pab] .- seq.flow[pba]); init = 0.0) * S
            line *= @sprintf("; flows max |Δ| %.3e MW", df)
        end
        println(line)
        # Tally: the worse order against both at once, by the worst live piece.
        if seq.outcome[pab] === :screened && seq.outcome[pba] === :screened
            wa, wb, ws = worst(mab), worst(mba), worst(mb)
            pair_name = @sprintf("%s+%s(%s/%s/%s)", seq.id[a], seq.id[b], fmt(wa), fmt(wb),
                                 fmt(ws))
            if isnan(wa) || isnan(wb) || isnan(ws)
                bump(:no_number)
            else
                bump(same(wa, wb) ? :orders_same_worst : :orders_differ)
                w = max(wa, wb)
                bump(same(w, ws) ? :worse_order_same_as_both :
                     w > ws ? :worse_order_worse_than_both : :worse_order_milder_than_both)
                m = min(wa, wb)
                bump(same(m, ws) ? :milder_order_same_as_both :
                     m < ws ? :milder_order_milder_than_both : :milder_order_worse_than_both)
            end
            bump(dpk <= 1e-9 ? :same_dispatch : :dispatch_differs)
        else
            bump(:not_both_screened)
        end
    end
    println("TALLY $name $(uppercase(String(fid))): ",
            join(["$k=$(tally[k])" for k in sort!(collect(keys(tally)))], ", "))
    # Who is in the categories a claim would rest on: |Δω| of A→B / B→A / both at once.
    for k in (:worse_order_worse_than_both, :milder_order_worse_than_both,
              :worse_order_milder_than_both, :orders_differ)
        haskey(who, k) && println("  $k: ", join(who[k], "  "))
    end
end

for (gname, f) in (("case9", OutageScreenScript.case9), ("mesh", OutageScreenScript.mesh)),
    loads in (:constant_power, :default), fid in (:dc, :ac)
    fid === :dc && loads === :default && continue        # DC reads no load model
    table("$gname $(fid === :dc ? "" : String(loads))", f(; loads), fid)
end
