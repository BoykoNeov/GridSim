using GridSim
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
let src = read(raw"W:\Claude_projects\GridSim\test\m8_screening.jl", String)
    i = findfirst("function _m8_genmesh", src).start
    include_string(Main, src[i:findnext("\nend\n", src, i).stop])
end
withR(net, f) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating; R = f * b.X) for b in net.branches],
    net.machines, net.loads; slack = net.slack, inverters = net.inverters)
function drift(ser)
    out = Pair{Symbol,Float64}[]
    for ch in keys(ser); ch === :t && continue
        v = getproperty(ser, ch); push!(out, ch => maximum(abs, v .- v[1])); end
    sort(out; by = last, rev = true)[1:3]
end
for (nm, base) in (("ring", ratio_ring(D1 = 1.0)), ("mesh", _m8_genmesh()), ("gfm", _m8_genmesh(gfm = true)))
    for f in (0.0, 0.3), (rt, at) in ((1e-6, 1e-9), (1e-10, 1e-12))
        eng = SwingEngine(withR(base, f); reltol = rt, abstol = at)
        u = eng.integrator.u; du = similar(u); eng.nw(du, u, eng.integrator.p, 0.0)
        ser = solve!(eng, (0.0, 50.0); saveat = 0.5)
        println(rpad("$nm R=$f rt=$rt", 26), " res0=", maximum(abs, du), "  ", drift(ser))
    end
end
