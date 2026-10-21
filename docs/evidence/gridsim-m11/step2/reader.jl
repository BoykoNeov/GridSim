# M11 step 2 — the extension loads beside PowerModels, `parse_matpower(IOBuffer)` exists,
# and the typed rows read the same as the downloaded file (evidence only; the file is not
# committed).
#   julia --project=W:/temp/claude/gridsim-m11-step2/refenv reader.jl TYPED.m
using GridSim, JuMP, HiGHS, PowerModels, Ipopt
PowerModels.silence()
println("GridSimDispatchExt loaded: ", Base.get_extension(GridSim, :GridSimDispatchExt) !== nothing)
println("PowerModels ", pkgversion(PowerModels), "  Ipopt ", pkgversion(Ipopt))
file = PowerModels.parse_file(raw"W:\temp\claude\gridsim-m11-step2\data\case9-pinned.m")
typed = PowerModels.parse_matpower(IOBuffer(read(ARGS[1], String)))
println("parse_matpower(IOBuffer(typed)) == parse_file(case9.m): ", typed == file)
if typed != file
    for k in union(keys(typed), keys(file))
        get(typed, k, nothing) == get(file, k, nothing) || println("  differs: ", k)
    end
end
for (i, b) in sort(collect(file["branch"]), by = x -> parse(Int, x[1]))
    println("branch ", i, " ", b["f_bus"], "->", b["t_bus"], " angmin ", b["angmin"], " angmax ", b["angmax"],
            " rate_a ", b["rate_a"])
end
