# M9 close, capture 6: M9's own lossy numbers at shortest-round-trip precision —
# every field of `generator_dips`, of `generator_rates` at the report's two windows,
# and of `frequency_verdicts` under the CE preset, on both report grids and both
# load models. The five step-1/2 captures never reach these, so a solver bump could
# move a lossy dip and none of them would show it. Traces are printed in full.
using GridSim
module OS
include(raw"W:/Claude_projects/GridSim/scripts/outage_screen.jl")
end

function dump(tag, x)
    for k in fieldnames(typeof(x))
        v = getfield(x, k)
        if v isa AbstractVector && !isempty(v) && first(v) isa FrequencyTrace
            for (i, tr) in enumerate(v), j in fieldnames(FrequencyTrace)
                println(tag, " ", k, "[", i, "].", j, " = ", repr(getfield(tr, j)))
            end
        else
            println(tag, " ", k, " = ", repr(v))
        end
    end
end

for (name, build) in (("case9", OS.case9), ("mesh", OS.mesh)), loads in (:constant_power, :default)
    net = build(; loads)
    s = outage_screen(net)
    dips = generator_dips(net, s)
    tag = "$name $loads"
    dump("$tag dips", dips)
    for w in OS.RATE_WINDOWS
        dump("$tag rates[$w]", generator_rates(dips; window = w))
    end
    dump("$tag verdicts", frequency_verdicts(net, s, continental_europe_limits(); dips))
end
