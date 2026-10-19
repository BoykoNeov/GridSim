# Name every entry that differs between two `snapshot.jl` outputs: walk both values
# field by field and print the path of each leaf where they are not `isequal`.
#   julia --project=<root>/docs/evidence/gridsim-m9/harness/testenv snapshot_diff.jl <before> <after> <file>...
using GridSim, Serialization

function walk(a, b, path, out)
    if isequal(a, b)
        return
    elseif a isa AbstractVector && b isa AbstractVector && length(a) == length(b)
        for i in eachindex(a)
            walk(a[i], b[i], "$path[$i]", out)
        end
    elseif typeof(a) === typeof(b) && isstructtype(typeof(a)) && fieldcount(typeof(a)) > 0 &&
           !(a isa AbstractArray) && !(a isa AbstractString)
        for f in fieldnames(typeof(a))
            walk(getfield(a, f), getfield(b, f), "$path.$f", out)
        end
    else
        push!(out, "$path: $(repr(a)) → $(repr(b))")
    end
end

before, after = ARGS[1], ARGS[2]
for file in ARGS[3:end]
    a = deserialize(joinpath(before, file))
    b = deserialize(joinpath(after, file))
    out = String[]
    walk(a, b, "", out)
    println("== $file: $(length(out)) entries differ")
    # Name each moved entry by its ordered pair or element, not only by index.
    for line in out
        m = match(r"^\.(capped|pickup)\[(\d+)\]", line)
        m2 = match(r"^\.restore\[(\d+)\]", line)
        tag = m !== nothing ? "pair $(a.id[a.pairs[parse(Int, m[2])][1]])→$(a.id[a.pairs[parse(Int, m[2])][2]])" :
              m2 !== nothing ? "restore of $(a.restore[parse(Int, m2[1])].element)" : ""
        println("  ", line, isempty(tag) ? "" : "   ($tag)")
    end
end
