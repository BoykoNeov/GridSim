using GridSim
module OutageScreenScript
include(joinpath("W:/Claude_projects/GridSim", "scripts", "outage_screen.jl"))
end
const OS = OutageScreenScript
lossless(n) = NetworkModel(n.S_base, n.f0, n.buses, [Branch(b.id, b.from, b.to, b.X, b.rating) for b in n.branches], n.machines, n.loads; slack = n.slack)
for (name, build) in (("case9", OS.case9), ("mesh", OS.mesh)), loads in (:constant_power, :default)
    n = build(; loads)
    a, b = ac_generator_outages(lossless(n)), ac_generator_outages(n)
    println(rpad("$name $loads", 22), " lossless: ", a.outcome, "   lossy: ", b.outcome)
end
