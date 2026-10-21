# Name every entry the D12 fix moved in M10's serialized screens: per file, per pair, the
# field, and the largest |change|.
using GridSim, Serialization
A, B = ARGS[1], ARGS[2]
function walk(a, b, path, out)
    if a isa AbstractFloat && b isa AbstractFloat
        (isequal(a, b)) || push!(out, (path, abs(a - b), a, b))
    elseif a isa AbstractDict && b isa AbstractDict
        isequal(a, b) || push!(out, (path * " [dict]", NaN, "", ""))
    elseif a isa AbstractArray && b isa AbstractArray
        length(a) == length(b) || (push!(out, (path * " [len]", NaN, length(a), length(b))); return)
        for i in eachindex(a)
            isassigned(a, i) && isassigned(b, i) || continue
            walk(a[i], b[i], "$path[$i]", out)
        end
    elseif a isa Union{Symbol,AbstractString,Integer,Bool,Nothing}
        isequal(a, b) || push!(out, (path, NaN, a, b))
    else
        T = typeof(a)
        T === typeof(b) || (push!(out, (path * " [type]", NaN, T, typeof(b))); return)
        for f in fieldnames(T); walk(getfield(a, f), getfield(b, f), "$path.$f", out); end
    end
end
for f in sort(readdir(A))
    a = deserialize(joinpath(A, f)); b = deserialize(joinpath(B, f))
    out = Any[]; walk(a, b, "", out)
    isempty(out) && continue
    big = filter(x -> !(x[2] isa Float64 && x[2] < 1e-12), out)
    println("== $f: $(length(out)) entries moved, $(length(big)) by ≥ 1e-12 (or not numeric); largest ",
            maximum(x -> x[2] isa Float64 && !isnan(x[2]) ? x[2] : 0.0, out))
    for x in big[1:min(end, 12)]; println("   ", x); end
end
