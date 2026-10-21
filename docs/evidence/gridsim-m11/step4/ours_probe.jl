# M11 step 4 — our ac_opf ALONE (nothing of theirs), constant-power loads, margins 0.
#   julia --project=W:/Claude_projects/GridSim/reference ours_probe.jl
using GridSim, JuMP, Ipopt, Printf
module S
include(raw"W:\Claude_projects\GridSim\scripts\outage_screen.jl")
end
function rated(net, ratings...)
    d = Dict(ratings)
    br = [Branch(b.id, b.from, b.to, b.X, get(d, b.id, b.rating); R = b.R) for b in net.branches]
    NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads; slack = net.slack)
end
c9(mw = 315.0) = S.case9(; costed = true, mw)
fixtures = [("published", c9()), ("1.5x", c9(1.5 * 315)), ("1.75x", c9(1.75 * 315)),
            ("L94@60", rated(c9(), :L94 => 60.0))]
F = (:P, :Vm, :θ, :Qgen, :flow, :flow_rev, :qflow, :qflow_rev)
for (name, net) in fixtures
    println("\n== ", name)
    runs = Dict{Float64,Any}()
    for τ in (1e-9, 1e-10, 1e-11)
        r = try
            ac_opf(net; tol = τ, margin_V = 0.0, margin_S = 0.0)
        catch e
            println("  tol $τ threw: ", sprint(showerror, e)[1:min(end, 160)]); nothing
        end
        r === nothing && continue
        runs[τ] = r
        @printf("  tol %.0e: %s  %s\n", τ, r.outcome, r.status)
    end
    r = runs[1e-9]
    r.outcome === :locally_optimal || continue
    @printf("  cost %.6f\n  P   %s MW\n  Qgen %s MVAr\n  Vm  %s\n", r.cost,
            string(round.(100 .* r.P; digits = 4)), string(round.(100 .* r.Qgen; digits = 4)),
            string(round.(r.Vm; digits = 6)))
    println("  at_limit ", r.at_limit, "  at_band ", r.at_band, "  q_at_limit ", r.q_at_limit,
            "  residual ", r.residual)
    for e in eachindex(r.branches)
        @printf("  %s  flow %+.4f rev %+.4f q %+.4f qrev %+.4f\n", r.branches[e],
                100r.flow[e], 100r.flow_rev[e], 100r.qflow[e], 100r.qflow_rev[e])
    end
    for τ in (1e-10, 1e-11)
        haskey(runs, τ) && runs[τ].outcome === :locally_optimal || continue
        q = runs[τ]
        @printf("  |run(1e-9) - run(%.0e)|: %s cost %.2e\n", τ,
                join(("$f " * @sprintf("%.2e", maximum(abs, getfield(r, f) .- getfield(q, f))) for f in F), " "),
                abs(r.cost - q.cost))
    end
end
