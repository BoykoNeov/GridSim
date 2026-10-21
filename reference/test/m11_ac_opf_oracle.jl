# M11 step 4 — PowerModels' AC OPF against `ac_opf` (Hurdle 24, its outside check;
# m11-plan.md step 4, m11-context.md D4, D7, D9).
#
# BOTH SIDES USE IPOPT. There is no second open-source nonlinear solver on the stack, so
# agreement here checks the FORMULATION — the network equations, the held voltages, the
# band, the ratings at both ends, the costs and their units — not the solver. The checks
# that do not share it are step 3's (test/m11_ac_opf.jl in core): the answer handed back
# to `ac_powerflow` (24.1), the cost bound (24.2) and the two starts (24.5).
#
# CONSTANT-POWER LOADS ONLY. PowerModels has no voltage-dependent load, so the default
# (ZIP) loads have no outside check here; step 3's three checks run on them.
#
# Every band below was written in `docs/evidence/gridsim-m11/step4_predictions.md` before
# the two sides were first compared. Their side is step 2's typed `C9_MATPOWER` text with
# the AC edits — line charging zeroed (`b0`: our case9 has none), each generator bus's
# Vmin = Vmax = its gen row's `Vg` (`held`, read from THEIR text), loads scaled (`load`) —
# read by their own reader; `R` is kept on both sides (in AC the formula is the same).
#
# OUR SIDE RUNS AT `margin_V = margin_S = 0` (step4_predictions.md, "How D9's margin is
# read here"): step 2's reading — the same problem on both sides, compared strictly.
#
# Uses from m11_dc_opf_oracle.jl (included first): `OutageScreenScriptM11`, `C9_MATPOWER`,
# `m11_c9`, `m11_rated`, `m11_busno`, `M11_RHO`, `M11_ANGLE_BOUND`.

# The tolerances of step4_predictions.md: each side's working run and its tight run.
const M11_AC_OURS_TOL = (1.0e-9, 1.0e-10)     # ac_opf throws at 1e-11 (SLOW_PROGRESS)
const M11_AC_THEIRS_TOL = (1.0e-8, 1.0e-10)   # theirs: ALMOST_LOCALLY_SOLVED at 1e-11
const M11_AC_L94_MVA = 60.0                    # INVENTED, as in core's step-3 test

m11_ac_text(; load::Real = 1, rate = Dict{Tuple{Int,Int},Float64}(), b0::Bool = true) =
    matpower_edit(C9_MATPOWER; b0, held = true, load, rate)

# One fixture: both sides at both tolerances, mapped by bus number, gaps and bands per
# channel.
function m11_ac_compare(net::NetworkModel, text::AbstractString)
    o = [ac_opf(net; tol = τ, margin_V = 0.0, margin_S = 0.0) for τ in M11_AC_OURS_TOL]
    t = [oracle_ac_opf(text; tol = τ) for τ in M11_AC_THEIRS_TOL]
    gk = [findfirst(==(m11_busno(m.bus)), t[1].gen_bus) for m in net.machines]
    gv = [net.bus_index[m.bus] for m in net.machines]
    ek = [findfirst(j -> (t[1].f_bus[j], t[1].t_bus[j]) ==
                         (m11_busno(b.from), m11_busno(b.to)), eachindex(t[1].f_bus))
          for b in net.branches]
    vk = [m11_busno(b.id) for b in net.buses]
    ch(x) = (P = x.P, Q = x.Qgen[gv], Vm = x.Vm, θ = x.θ, flow = x.flow,
             flow_rev = x.flow_rev, qflow = x.qflow, qflow_rev = x.qflow_rev, cost = [x.cost])
    th(x) = (P = x.pg[gk], Q = x.qg[gk], Vm = x.vm[vk], θ = x.va[vk], flow = x.pf[ek],
             flow_rev = x.pt[ek], qflow = x.qf[ek], qflow_rev = x.qt[ek], cost = [x.cost])
    gap = Dict{Symbol,Float64}()
    band = Dict{Symbol,Float64}()
    if o[1].outcome === :locally_optimal && t[1].solved
        for c in keys(ch(o[1]))
            O = maximum(abs, getproperty(ch(o[1]), c) .- getproperty(ch(o[2]), c))
            T = maximum(abs, getproperty(th(t[1]), c) .- getproperty(th(t[2]), c))
            ρ = c === :cost ? M11_RHO * abs(o[1].cost) : M11_RHO
            band[c] = 2 * (O + T) + ρ
            gap[c] = maximum(abs, getproperty(ch(o[1]), c) .- getproperty(th(t[1]), c))
        end
    end
    return (; net, ours = o[1], theirs = t[1], tight = (o[2], t[2]), gk, vk, ek, gap, band)
end

const M11_AC_FIXTURES = [
    ("A1 published", () -> m11_c9(), () -> m11_ac_text()),
    ("A2 1.5×, the voltage fixture",
     () -> OutageScreenScriptM11.case9(; costed = true, mw = 1.5 * 315),
     () -> m11_ac_text(; load = 1.5)),
    ("A3 L94 at an INVENTED 60 MVA",
     () -> m11_rated(m11_c9(), :L94 => M11_AC_L94_MVA),
     () -> m11_ac_text(; rate = Dict((9, 4) => M11_AC_L94_MVA))),
]

@testset "M11 step 4 — PowerModels' AC OPF as the outside check on ac_opf (both on Ipopt)" begin

@testset "the input: the AC edits, read back through their reader" begin
    PM = GridSimReference.PM
    plain = PM.parse_matpower(IOBuffer(C9_MATPOWER))
    # Every edit off by default: the text step 2 compares on is unchanged in meaning.
    @test PM.parse_matpower(IOBuffer(matpower_edit(C9_MATPOWER))) == plain
    # The published file HAS line charging; ours has none, so their side must lose it.
    @test any(b -> b["b_fr"] != 0, values(plain["branch"]))
    d = PM.parse_matpower(IOBuffer(m11_ac_text(; load = 1.5, rate = Dict((9, 4) => 60.0))))
    @test all(b -> b["b_fr"] == 0 && b["b_to"] == 0, values(d["branch"]))
    @test all(b["br_r"] == plain["branch"][k]["br_r"] for (k, b) in d["branch"])     # R kept
    # Held: Vmin = Vmax = their own Vg at the three generator buses — which are our V_set.
    net = m11_c9()
    for m in net.machines
        b = d["bus"][string(m11_busno(m.bus))]
        g = only(x for x in values(plain["gen"]) if x["gen_bus"] == m11_busno(m.bus))
        @test b["vmin"] == b["vmax"] == g["vg"] == m.V_set
    end
    @test all(d["bus"][string(i)]["vmin"] == 0.9 && d["bus"][string(i)]["vmax"] == 1.1
              for i in 4:9)
    # Loads ×1.5, P and Q, in their per unit; the rating on L94 in MVA, read as 0.6 pu.
    pq(x, i) = only((l["pd"], l["qd"]) for l in values(x["load"]) if l["load_bus"] == i)
    for i in (5, 7, 9)
        @test all(isapprox.(pq(d, i), 1.5 .* pq(plain, i); rtol = 1e-14))
    end
    @test d["branch"]["9"]["rate_a"] == 0.6 && d["branch"]["8"]["rate_a"] == 2.5
    # Two generators on one bus asking for different voltages are refused.
    two = replace(C9_MATPOWER, "\t3\t85\t-10.95\t300\t-300\t1.025" =>
                               "\t2\t85\t-10.95\t300\t-300\t1.03")
    @test two != C9_MATPOWER
    @test_throws ArgumentError matpower_edit(two; held = true)
end

for (name, mk_net, mk_text) in M11_AC_FIXTURES
    @testset "$name — strict, R kept on both" begin
        c = m11_ac_compare(mk_net(), mk_text())
        o, t = c.ours, c.theirs
        @test o.outcome === :locally_optimal
        @test t.solved && c.tight[2].solved && c.tight[1].outcome === :locally_optimal
        for ch in (:P, :Q, :Vm, :θ, :flow, :flow_rev, :qflow, :qflow_rev, :cost)
            @test c.gap[ch] ≤ c.band[ch]
        end
        # Held, exactly, on both sides.
        for (k, m) in pairs(c.net.machines)
            @test t.vm[m11_busno(m.bus)] == m.V_set
            @test o.Vm[c.net.bus_index[m.bus]] === m.V_set
        end
        # No reactive limit is reached (D4's switch is not tested by any fixture here).
        @test isempty(o.q_at_limit)
        @test all(abs.(t.qg) .< 3.0 - 0.5)
        # Their ±60° bound present and never binding.
        @test all(==(M11_ANGLE_BOUND), t.angmax) && all(==(-M11_ANGLE_BOUND), t.angmin)
        @test maximum(abs(t.va[f] - t.va[u]) for (f, u) in zip(t.f_bus, t.t_bus)) <
              M11_ANGLE_BOUND - 0.5
        @info "M11 step 4 $name (gap, band) per channel, pu (\$/h on cost)" sort(
            [ch => (c.gap[ch], c.band[ch]) for ch in keys(c.gap)])
    end
end

@testset "what binds, on both sides" begin
    a1 = m11_ac_compare(m11_c9(), m11_ac_text())
    @test isempty(a1.ours.at_limit) && isempty(a1.ours.at_band)
    @test minimum(a1.theirs.vm) > 0.9 + 0.01
    # A2: B9 on the floor on both.
    a2 = m11_ac_compare(OutageScreenScriptM11.case9(; costed = true, mw = 1.5 * 315),
                        m11_ac_text(; load = 1.5))
    @test a2.ours.at_band == [:B9] && isempty(a2.ours.at_limit)
    @test abs(a2.theirs.vm[9] - 0.9) ≤ a2.band[:Vm]
    @test all(a2.theirs.vm[v] > 0.9 + 0.01 for v in 4:8)
    # A3: L94 on its rating at the RECEIVING end (bus 4) on both.
    a3 = m11_ac_compare(m11_rated(m11_c9(), :L94 => M11_AC_L94_MVA),
                        m11_ac_text(; rate = Dict((9, 4) => M11_AC_L94_MVA)))
    @test a3.ours.at_limit == [:L94]
    e = findfirst(==(:L94), a3.ours.branches)
    j = a3.ek[e]
    St = hypot(a3.theirs.pt[j], a3.theirs.qt[j])
    Sf = hypot(a3.theirs.pf[j], a3.theirs.qf[j])
    @test St > Sf
    @test abs(St - M11_AC_L94_MVA / 100) ≤ a3.band[:flow] + a3.band[:qflow]
    @test a3.ours.cost > a1.ours.cost && a3.theirs.cost > a1.theirs.cost
    # 24.2's figure, outside: the published optimum costs 5325.2661 on both.
    @test round(a1.ours.cost; digits = 4) == round(a1.theirs.cost; digits = 4) == 5325.2661
end

@testset "A4 1.75×: two local words, side by side" begin
    net = OutageScreenScriptM11.case9(; costed = true, mw = 1.75 * 315)
    o = ac_opf(net; tol = M11_AC_OURS_TOL[1], margin_V = 0.0, margin_S = 0.0)
    t = oracle_ac_opf(m11_ac_text(; load = 1.75); tol = M11_AC_THEIRS_TOL[1])
    # Never called agreement: each is Ipopt's word that it found no feasible point nearby.
    @test o.outcome === :locally_infeasible
    @test !t.solved && t.status == "LOCALLY_INFEASIBLE"
    @info "M11 step 4 A4" ours = o.status theirs = (t.status, t.primal)
end

end # M11 step 4
