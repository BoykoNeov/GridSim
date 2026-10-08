# M8 step 4 spike — the pickup rule against closed form, the rebuild, and the swing tier.
using GridSim, Printf
const G = GridSim

const MESH_BR = ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15),
                 (:BD, :B, :D, 0.25), (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10),
                 (:BE, :B, :E, 0.20))
# Machine(id,bus,S_rated,H,D,Xd′,E′,P0,R,Pmax,Tg)
function genmesh(; damp = 1.0, gov = true, gfm = false, slack = :A, S_base = 100.0)
    R(r) = gov ? r : Inf
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0damp, 0.25, 1.05, 150.0, R(0.05), 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0damp, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0damp, 0.25, 1.04, 60.0, R(0.04), 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5damp, 0.25, 1.00, -120.0)]
    invs = Inverter[]
    if gfm
        push!(invs, Inverter(:I3, :E, :grid_forming, 300.0, 40.0; K_p = 0.125, V_set = 1.02))
    else
        push!(ms, Machine(:G3, :E, 120.0, 3.5, 1.5damp, 0.25, 1.02, 40.0, R(0.06), 45.0, 0.6))
    end
    NetworkModel(S_base, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)],
                 [Branch(id, f, t, x * S_base / 100, 500.0) for (id, f, t, x) in MESH_BR],
                 ms; slack, inverters = invs)
end

net = genmesh()
for lost in (:G3, :G2, :G1, :LB)
    s = pickup_shares(net, lost)
    @printf("%-3s Δω = %+.9e  pickups %s capped %s\n", lost, s.Δω,
            join([@sprintf("%.6f", p) for p in s.pickup], " "), s.capped)
end
println("P1 pred Δω ", -0.4/107, "  P2 pred ", -(2.5e-3 + (0.6 - 88.3*2.5e-3)/68.3), "  P6 pred ", 1.3/126.8)
println("zero-D G3: ", pickup_shares(genmesh(damp = 0.0), :G3).Δω, " pred ", -0.4/97.5)
for (lbl, nt) in (("zeroD", genmesh(damp = 0.0)), ("nogov,noD", genmesh(damp = 0.0, gov = false)))
    sc = dc_generator_outages(nt)
    println(lbl, " outcomes ", sc.machines .=> sc.outcome)
end
println("gfm G2: ", pickup_shares(genmesh(gfm = true), :G2).Δω, " pred ", -0.6/90.5)

# rebuild identity
function rebuilt(net, k, pk, resp)
    ms = Machine[]
    for (i, m) in pairs(net.machines)
        i == k && continue
        j = findfirst(==(m.id), resp)
        P = m.P0 + pk[j] * net.S_base
        push!(ms, Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, P, m.R, max(m.Pmax, P), m.Tg))
    end
    invs = [begin j = findfirst(==(iv.id), resp)
                Inverter(iv.id, iv.bus, iv.mode, iv.S_rated, iv.P0 + pk[j] * net.S_base; K_p = iv.K_p, V_set = iv.V_set)
            end for iv in net.inverters]
    NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads; slack = net.slack, inverters = invs)
end
for nt in (genmesh(), genmesh(gfm = true))
    sc = dc_generator_outages(nt)
    for k in eachindex(sc.machines)
        sc.outcome[k] === :shared || continue
        bf = dc_powerflow(rebuilt(nt, k, sc.pickup[k], sc.responders)).flow
        @printf("rebuild %-3s max|Δ| = %.2e\n", sc.machines[k], maximum(abs.(bf .- sc.flow[k])))
    end
end
a = dc_generator_outages(genmesh(slack = :A)); c = dc_generator_outages(genmesh(slack = :D))
println("slack moved: ", maximum(maximum(abs.(a.flow[k] .- c.flow[k])) for k in eachindex(a.flow)))

# swing oracle
function swing_settle(net, lost; T = 300.0, reltol = 1e-10, abstol = 1e-12)
    eng = SwingEngine(net; reltol, abstol, dt = 0.05)
    ids = [m.id for m in net.machines]
    export0 = Dict(b.id => 0.0 for b in net.buses)
    exp_at(eng) = Dict(bus.id => sum((br.from === bus.id ? G.branch_power(eng, br.from, br.to) :
                                      br.to === bus.id ? G.branch_power(eng, br.to, br.from) : 0.0)
                                     for br in net.branches) for bus in net.buses)
    e0 = exp_at(eng)
    G.inject!(eng, TripGenerator(lost))
    out = Dict{Float64,Any}()
    t = 0.0
    for Tm in (T, 1.5T)
        while eng.integrator.t < Tm - 1e-9
            G.step!(eng, 0.05)
        end
        e1 = exp_at(eng)
        st = G.current_state(eng)
        out[Tm] = (; e1, ω = st.ω, ΔPm = st.ΔPm)
    end
    return e0, out
end
for (lbl, nt, lost) in (("uncapped G3", genmesh(), :G3), ("capped G2", genmesh(), :G2),
                        ("gfm G2", genmesh(gfm = true), :G2), ("zeroD G3", genmesh(damp = 0.0), :G3))
    s = pickup_shares(nt, lost)
    t0 = time()
    e0, out = swing_settle(nt, lost)
    for (Tm, o) in sort(collect(out); by = first)
        bus_of = Dict(m.id => m.bus for m in nt.machines); for iv in nt.inverters; bus_of[iv.id] = iv.bus; end
        dp = [o.e1[bus_of[r]] - e0[bus_of[r]] for r in s.responders]
        alive = s.responders .!== lost
        gap_p = maximum(abs.(dp[alive] .- s.pickup[alive]))
        busids = [b.id for b in nt.buses]
        lostbus = bus_of[lost]
        ωs = [o.ω[v] for v in eachindex(busids) if busids[v] !== lostbus]
        gap_w = maximum(abs.(ωs .- s.Δω))
        @printf("%-12s T=%5.0f  pickup gap %.2e  Δω gap %.2e  ω spread %.2e  (%.1fs)\n", lbl, Tm, gap_p, gap_w,
                maximum(ωs) - minimum(ωs), time() - t0)
        if lbl == "capped G2"
            v3 = findfirst(==(:E), busids)
            @printf("   G3 ΔPm - h = %.3e\n", o.ΔPm[v3] - 0.05)
        end
    end
end
