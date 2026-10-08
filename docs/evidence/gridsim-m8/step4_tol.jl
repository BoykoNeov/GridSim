using GridSim, Printf
include(raw"W:\Claude_projects\GridSim\test\helpers.jl")
using Test
# pull the fixture + reader from the test file without running its testsets
src = read(raw"W:\Claude_projects\GridSim\test\m8_screening.jl", String)
i = findfirst("function _m8_genmesh", src).start - 1
j = findfirst("@testset \"M8 step 4", src).start - 1
include_string(Main, src[i:j])
function gaps(nt, lost, rt, at)
    s = pickup_shares(nt, lost)
    eng = SwingEngine(nt; reltol = rt, abstol = at, dt = 0.05)
    ex(bus) = sum((br.from === bus ? branch_power(eng, br.from, br.to) : br.to === bus ? branch_power(eng, br.to, br.from) : 0.0) for br in nt.branches)
    e0 = Dict(b.id => ex(b.id) for b in nt.buses)
    inject!(eng, TripGenerator(lost))
    while eng.integrator.t < 300 - 1e-9; step!(eng, 0.05); end
    bus_of = Dict(vcat([m.id => m.bus for m in nt.machines], [iv.id => iv.bus for iv in nt.inverters]))
    gp = maximum(abs(ex(bus_of[r]) - e0[bus_of[r]] - s.pickup[k]) for (k, r) in pairs(s.responders) if r !== lost)
    lv = nt.bus_index[bus_of[lost]]
    st = current_state(eng)
    gw = maximum(abs(st.ω[v] - s.Δω) for v in eachindex(nt.buses) if v != lv)
    gp, gw, st.ΔPm
end
for (lbl, nt, lost) in (("uncapped G3", _m8_genmesh(), :G3), ("capped G2", _m8_genmesh(), :G2), ("gfm G2", _m8_genmesh(gfm = true), :G2))
    for (rt, at) in ((1e-8, 1e-10), (1e-10, 1e-12), (1e-12, 1e-14))
        gp, gw, dpm = gaps(nt, lost, rt, at)
        @printf("%-12s reltol %.0e  pickup %.2e  Δω %.2e  %s\n", lbl, rt, gp, gw, lbl == "capped G2" ? @sprintf("ΔPm-h %.2e", dpm[5] - 0.05) : "")
    end
end
