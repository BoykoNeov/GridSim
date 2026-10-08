# M9 step 1 gate, capture 3: every field of `outage_screen` on both report fixtures and
# both load models, at shortest-round-trip precision (`repr`), so "bit-identical" is a
# text comparison. Then the script's own printed report.
#
#   julia --project=W:/Claude_projects/GridSim W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/screen_snapshot.jl > <out>.txt
using GridSim
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end

function dump(prefix, x)
    T = typeof(x)
    if isstructtype(T) && !(x isa AbstractArray) && !(x isa Number) && !(x isa Symbol) &&
       !(x isa AbstractString) && fieldcount(T) > 0
        for f in fieldnames(T)
            dump("$prefix.$f", getfield(x, f))
        end
    else
        println(prefix, " = ", repr(x))
    end
end

for (name, loads, net) in OS.screens()
    println("== ", name, " — ", loads)
    dump("s", outage_screen(net))
end
println("\n== the script's own report ==")
OS.main()
