import Pkg
env = ARGS[1]; out = ARGS[2]
Pkg.activate(env)
Pkg.resolve()
m = Pkg.Operations.Context().env.manifest
open(out, "w") do io
    for (_, e) in sort(collect(m), by = kv -> kv[2].name)
        println(io, e.name, "\t", e.version)
    end
end
println("wrote ", out, " with ", length(m), " entries")
