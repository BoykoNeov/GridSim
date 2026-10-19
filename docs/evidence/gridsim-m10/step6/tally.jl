# Kept as step 6's evidence (m10-context.md D12, "What step 6 measured"); re-run on the committed
# code, output in tally.out.txt.
#   julia --project=W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/testenv <this file>
using GridSim, Printf
module R
include(raw"W:\Claude_projects\GridSim\scripts\double_outage_screen.jl")
end
judged(v) = v in (:pass, :fail, :pass_load_lost)
for (key, name, f) in R.GRIDS
    G = R.grid_screens(f)
    both = R.simultaneous_rows(G)
    seq = R.sequential_rows(G; both)
    bi = Dict(Set((r.first, r.second)) => r for r in both)
    println("== $key")
    for k in R.SIDES
        os = [getfield(r.order, k) for r in seq]
        println("  $k order: ", join(["$o=$(count(==(o), os))" for o in sort!(unique(os))], " "))
        # verdict flips: sequential verdict vs both at once, where both judged
        flips = String[]
        for r in seq
            a, b = getfield(r, k).verdict, getfield(bi[Set((r.first, r.second))], k).verdict
            (judged(a) && judged(b) && a !== b) && push!(flips, "$(r.first)→$(r.second) $(a) (both $(b)) " *
                @sprintf("%+.4f vs %+.4f", getfield(r, k).worst, getfield(bi[Set((r.first, r.second))], k).worst))
        end
        println("    flips vs both ($(length(flips))): ", join(flips, "; "))
        # orders disagreeing in verdict
        sd = Dict((r.first, r.second) => r for r in seq)
        dis = String[]
        for r in seq
            r.first < r.second || continue
            o = sd[(r.second, r.first)]
            a, b = getfield(r, k).verdict, getfield(o, k).verdict
            (judged(a) && judged(b) && a !== b) && push!(dis, "$(r.first)/$(r.second): $a vs $b")
        end
        println("    orders disagree ($(length(dis))): ", join(dis, "; "))
        # largest |worst seq - worst both| among screened
        d = [(abs(getfield(r, k).worst - getfield(bi[Set((r.first, r.second))], k).worst), "$(r.first)→$(r.second)")
             for r in seq if !isnan(getfield(r, k).worst) && !isnan(getfield(bi[Set((r.first, r.second))], k).worst)]
        isempty(d) || (m = maximum(d); @printf("    max |worst seq − worst both| %.4f Hz at %s\n", m...))
        milder = [r for r in seq if getfield(r.order, k) === :milder]
        println("    milder: ", join(["$(r.first)→$(r.second)" for r in milder], " "))
    end
    # DC vs AC verdict disagreements, both at once
    for k in (:cp, :def)
        dis = ["$(r.first)+$(r.second) DC $(r.dc.verdict) AC $(getfield(r, k).verdict) " *
               @sprintf("%+.4f/%+.4f", r.dc.worst, getfield(r, k).worst)
               for r in both if judged(r.dc.verdict) && judged(getfield(r, k).verdict) && r.dc.verdict !== getfield(r, k).verdict]
        println("  both-at-once DC vs $k verdict differ ($(length(dis))): ", join(dis, "; "))
    end
    # pairs with load lost; extremes
    for r in both
        any(p -> p.kind === :load_lost, r.dc.pieces) && println("  load lost: $(r.first)+$(r.second) ", r.dc.verdict, " ", r.cp.verdict, " ", r.def.verdict, @sprintf(" %.4f %.4f %.4f", r.dc.worst, r.cp.worst, r.def.worst))
    end
    for k in R.SIDES
        w = [(abs(getfield(r, k).worst), getfield(r, k).worst, "$(r.first)+$(r.second)") for r in both if !isnan(getfield(r, k).worst)]
        p = [x for x in w if x[1] <= 0.2]
        @printf("  %s worst both: %s %+.4f; passes: %s\n", k, maximum(w)[3], maximum(w)[2], join([x[3] for x in sort(p; by = x -> x[3])], " "))
    end
    # unjudged pieces reasons
    for k in (:cp, :def)
        reasons = [(r.first, r.second, p.outcome) for r in both for p in getfield(r, k).pieces if p.verdict === :no_value]
        println("  $k no-value pieces: ", length(reasons), " ", unique(x[3] for x in reasons))
    end
    # split pairs with two live pieces: one up one down?
    two = [r for r in both if count(p -> p.kind === :live, r.dc.pieces) == 2]
    println("  two live pieces: ", length(two), " ", join(["$(r.first)+$(r.second)" for r in two], " "))
end
