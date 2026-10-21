# M11 step 4 — re-resolve reference/'s OWN environment (a scratch copy) so its manifest
# records GridSim's current extension list (GridSimOPFExt, added at step 3); what moves?
#   julia --project=W:/temp/claude/gridsim-m11-step4/refenv resolve.jl
import Pkg
vers() = Dict(i.name => i.version for (_, i) in Pkg.dependencies())
v0 = vers()
Pkg.resolve()
v1 = vers()
println("\npackages: ", length(v0), " -> ", length(v1))
for n in sort(collect(keys(v0)))
    haskey(v1, n) || (println("REMOVED  ", n, " ", v0[n]); continue)
    v0[n] == v1[n] || println("MOVED    ", n, " ", v0[n], " -> ", v1[n])
end
for n in sort(collect(keys(v1)))
    haskey(v0, n) || println("ADDED    ", n, " ", v1[n])
end
using GridSim, JuMP, Ipopt, HiGHS
println("GridSimOPFExt loaded: ", Base.get_extension(GridSim, :GridSimOPFExt) !== nothing)
println("GridSimDispatchExt loaded: ", Base.get_extension(GridSim, :GridSimDispatchExt) !== nothing)
