# M8 step 0 probe — the outside checker's line-outage factors against our brute force.
# Run in the reference environment. Not repo code.
using GridSim, GridSimReference
const PNM = GridSimReference.PF.PNM
println("PNM version: ", pkgversion(PNM))
const Graphs = GridSim.Graphs
using Printf

const B = Bus
mk(branches; loads = [Load(:LB, :B, 80.0, 20.0, 0.0, 0.0, 1.0),
                      Load(:LD, :D, 90.0, 25.0, 0.0, 0.0, 1.0),
                      Load(:LE, :E, 40.0, 10.0, 0.0, 0.0, 1.0)]) =
    NetworkModel(100.0, 50.0, [B(s, 230.0) for s in (:A, :B, :C, :D, :E)], branches,
                 [Machine(:G1, :A, 200.0, 4.0, 2.0, 0.25, 1.05, 150.0),
                  Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0)], loads; slack = :A)

base_branches() = [Branch(:AB, :A, :B, 0.10, 500.0), Branch(:AC, :A, :C, 0.20, 500.0),
                   Branch(:BC, :B, :C, 0.15, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
                   Branch(:CD, :C, :D, 0.30, 500.0), Branch(:DE, :D, :E, 0.10, 500.0)]

# Our brute force: rebuild without branch k, re-solve. `nothing` where the model refuses.
function brute(branches)
    out = Dict{Symbol,Any}()
    for k in eachindex(branches)
        rest = [b for (j, b) in pairs(branches) if j != k]
        out[branches[k].id] = try
            sol = dc_powerflow(mk(rest))
            Dict(b.id => f for (b, f) in zip(rest, sol.flow))
        catch e
            e isa ArgumentError ? sprint(showerror, e)[1:min(end, 60)] : rethrow()
        end
    end
    return out
end

function probe(label, branches)
    println("\n=== $label ===")
    net = mk(branches)
    pre = dc_powerflow(net)
    prev = Dict(b.id => f for (b, f) in zip(net.branches, pre.flow))
    # bridges by graph
    g = Graphs.SimpleGraph(length(net.buses))
    for b in net.branches
        Graphs.add_edge!(g, net.bus_index[b.from], net.bus_index[b.to])
    end
    br = Graphs.bridges(g)
    names = [b.id for b in net.branches
             if any(e -> Set((Graphs.src(e), Graphs.dst(e))) ==
                         Set((net.bus_index[b.from], net.bus_index[b.to])), br)]
    println("graph bridges: ", names)

    sys = to_powersystems(net)
    lodf = PNM.LODF(sys)
    arc(b) = (net.bus_index[b.from], net.bus_index[b.to])
    bf = brute(net.branches)
    worst = Dict("lodf[m,k]" => 0.0, "lodf[k,m]" => 0.0)
    for k in net.branches
        r = bf[k.id]
        if r isa AbstractString
            # what the checker predicts for a refused (islanding) outage
            preds = [(m.id, prev[m.id] + lodf[arc(m), arc(k)] * prev[k.id]) for m in net.branches if m !== k]
            @printf("outage %s: ours REFUSES (%s…)\n  checker predicts: %s\n", k.id, r[1:40],
                    join([@sprintf("%s=%.6f", a, b) for (a, b) in preds], " "))
            continue
        end
        gk = maximum(abs(prev[m.id] + lodf[arc(m), arc(k)] * prev[k.id] - r[m.id]) for m in net.branches if m !== k)
        @printf("  outage %-3s gap(lodf[m,k]) %.3e   pre-flow %.4f
", k.id, gk, prev[k.id])
        for m in net.branches
            m === k && continue
            for (lab, f) in (("lodf[m,k]", lodf[arc(m), arc(k)]), ("lodf[k,m]", lodf[arc(k), arc(m)]))
                worst[lab] = max(worst[lab], abs(prev[m.id] + f * prev[k.id] - r[m.id]))
            end
        end
    end
    @printf("max |checker - brute| over connected outages:  lodf[m,k] %.3e   lodf[k,m] %.3e\n",
            worst["lodf[m,k]"], worst["lodf[k,m]"])
    return net, lodf
end

probe("F1 meshed + radial spur DE", base_branches())

# Near-bridge: a weak second path to E. 1 - PTDF_DE,DE = X_DE/(X_DE + X_path) roughly.
for Xw in (1.0e3, 1.0e5, 1.0e6, 1.0e7)
    probe("near-bridge: CE weak path X=$Xw", vcat(base_branches(), [Branch(:CE, :C, :E, Xw, 500.0)]))
end

# Float32-grid control: reciprocals exactly representable in single precision.
probe("F1 on the Float32 grid (X = 1/8, 1/4, 1/2, 1/4, 1/2, 1/8)",
      [Branch(:AB, :A, :B, 0.125, 500.0), Branch(:AC, :A, :C, 0.25, 500.0),
       Branch(:BC, :B, :C, 0.5, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
       Branch(:CD, :C, :D, 0.5, 500.0), Branch(:DE, :D, :E, 0.125, 500.0)])
# and the same topology with X slightly OFF the grid
probe("F1 Float32 grid, AB nudged to 0.1251",
      [Branch(:AB, :A, :B, 0.1251, 500.0), Branch(:AC, :A, :C, 0.25, 500.0),
       Branch(:BC, :B, :C, 0.5, 500.0), Branch(:BD, :B, :D, 0.25, 500.0),
       Branch(:CD, :C, :D, 0.5, 500.0), Branch(:DE, :D, :E, 0.125, 500.0)])
