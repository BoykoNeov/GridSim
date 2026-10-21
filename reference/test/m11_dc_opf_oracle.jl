# M11 step 2 — PowerModels' DC OPF against `dc_opf` (Hurdle 23; m11-plan.md step 2,
# m11-context.md D2.5, D7, D9).
#
# Every band below was written in `docs/evidence/gridsim-m11/step2_predictions.md` before
# the two sides were first compared. Our side is the report script's costed case9 (D10)
# and its invented-rating variants; their side is the TEXT below, typed from MATPOWER's
# file and read by PowerModels' own reader. The two share no data path (Hurdle 23.2):
# nothing on their side is built from a `NetworkModel` or from the script's constants.
#
# OUR SIDE RUNS AT `margin = 0` (step2_predictions.md, "How D9's margin is read here"):
# the margin exists for the strict tools an answer is handed to, and an oracle comparison
# hands it to none — the same problem on both sides, compared strictly.
#
# Included by runtests.jl at top level (it defines a module), and runnable alone.

module OutageScreenScriptM11
include(joinpath(@__DIR__, "..", "..", "scripts", "outage_screen.jl"))
end

# MATPOWER `data/case9.m`, its four data blocks TYPED FROM THE FILE (comments dropped):
# https://github.com/MATPOWER/matpower/blob/31e3308e80f831e7310c2d45835501038665b5a3/data/case9.m
# (the last commit to change it, 2017-10-31; byte-identical at master 80b6e16f on
# 2026-10-21, sha256 ee50fc7b…8623). `parse_matpower` of this text was checked `==` to
# `parse_file` of that file (docs/evidence/gridsim-m11/step2/reader.jl). The file itself
# is not committed: MATPOWER's licence does not cover its case files (D7).
const C9_MATPOWER = """
function mpc = case9
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
	1	3	0	0	0	0	1	1	0	345	1	1.1	0.9;
	2	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	3	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	4	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	5	1	90	30	0	0	1	1	0	345	1	1.1	0.9;
	6	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	7	1	100	35	0	0	1	1	0	345	1	1.1	0.9;
	8	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	9	1	125	50	0	0	1	1	0	345	1	1.1	0.9;
];
mpc.gen = [
	1	72.3	27.03	300	-300	1.04	100	1	250	10	0	0	0	0	0	0	0	0	0	0	0;
	2	163	6.54	300	-300	1.025	100	1	300	10	0	0	0	0	0	0	0	0	0	0	0;
	3	85	-10.95	300	-300	1.025	100	1	270	10	0	0	0	0	0	0	0	0	0	0	0;
];
mpc.branch = [
	1	4	0	0.0576	0	250	250	250	0	0	1	-360	360;
	4	5	0.017	0.092	0.158	250	250	250	0	0	1	-360	360;
	5	6	0.039	0.17	0.358	150	150	150	0	0	1	-360	360;
	3	6	0	0.0586	0	300	300	300	0	0	1	-360	360;
	6	7	0.0119	0.1008	0.209	150	150	150	0	0	1	-360	360;
	7	8	0.0085	0.072	0.149	250	250	250	0	0	1	-360	360;
	8	2	0	0.0625	0	250	250	250	0	0	1	-360	360;
	8	9	0.032	0.161	0.306	250	250	250	0	0	1	-360	360;
	9	4	0.01	0.085	0.176	250	250	250	0	0	1	-360	360;
];
mpc.gencost = [
	2	1500	0	3	0.11	5	150;
	2	2000	0	3	0.085	1.2	600;
	2	3000	0	3	0.1225	1	335;
];
"""

# The tolerances of step2_predictions.md: each side's working run and its tight run.
const M11_OURS_TOL = (1.0e-9, 1.0e-10)     # HiGHS refuses below 1e-10
const M11_THEIRS_TOL = (1.0e-8, 1.0e-11)   # Ipopt: SLOW_PROGRESS at 1e-13 on binding fixtures
const M11_RHO = 1.0e-11                    # the stated round-off allowance, pu (× |cost| on cost)
const M11_ANGLE_BOUND = 1.0472             # their reader's ±60°, rad, measured in 0.21.7

m11_c9() = OutageScreenScriptM11.case9(; costed = true)

# Our model with some ratings replaced (MVA), and their text with the same ones, by the
# branch's (fbus, tbus) as MATPOWER writes it. The two edits are written side by side
# here and share nothing but the numbers typed in this file.
function m11_rated(net::NetworkModel, ratings::Pair{Symbol,Float64}...)
    d = Dict(ratings)
    br = [Branch(b.id, b.from, b.to, b.X, get(d, b.id, b.rating); R = b.R) for b in net.branches]
    return NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads;
                        slack = net.slack)
end

m11_busno(id::Symbol) = parse(Int, String(id)[2:end])     # :B7 -> 7

# One fixture: both sides at both tolerances, mapped by bus number, gaps and bands per
# channel. `ours_rate` names our branches, `their_rate` the file's rows.
function m11_compare(ours_rate::Vector{Pair{Symbol,Float64}},
                     their_rate::Dict{Tuple{Int,Int},Float64}; r0::Bool = true)
    net = m11_rated(m11_c9(), ours_rate...)
    o = [dc_opf(net; tol = τ, regularization = 0.0, margin = 0.0) for τ in M11_OURS_TOL]
    text = matpower_edit(C9_MATPOWER; r0, rate = their_rate)
    t = [oracle_dc_opf(text; tol = τ) for τ in M11_THEIRS_TOL]
    # Their channels in OUR order, by bus number.
    gk = [findfirst(==(m11_busno(m.bus)), t[1].gen_bus) for m in net.machines]
    ek = [findfirst(j -> (t[1].f_bus[j], t[1].t_bus[j]) ==
                         (m11_busno(b.from), m11_busno(b.to)), eachindex(t[1].f_bus))
          for b in net.branches]
    vk = [m11_busno(b.id) for b in net.buses]
    ch(x) = (P = x.P, flow = x.flow, θ = x.θ, cost = [x.cost])
    th(x) = (P = x.pg[gk], flow = x.pf[ek], θ = x.va[vk], cost = [x.cost])
    gap = Dict{Symbol,Float64}()
    band = Dict{Symbol,Float64}()
    for c in (:P, :flow, :θ, :cost)
        O = maximum(abs, getproperty(ch(o[1]), c) .- getproperty(ch(o[2]), c))
        T = maximum(abs, getproperty(th(t[1]), c) .- getproperty(th(t[2]), c))
        ρ = c === :cost ? M11_RHO * abs(o[1].cost) : M11_RHO
        band[c] = 2 * (O + T) + ρ
        gap[c] = maximum(abs, getproperty(ch(o[1]), c) .- getproperty(th(t[1]), c))
    end
    return (; net, ours = o[1], theirs = t[1], tight = t[2], gk, ek, gap, band,
              flowgap = abs.(o[1].flow .- t[1].pf[ek]))
end

const M11_FIXTURES = [
    ("F1 published", Pair{Symbol,Float64}[], Dict{Tuple{Int,Int},Float64}(), Symbol[]),
    ("F2 L82 at an INVENTED 100 MVA", [:L82 => 100.0], Dict((8, 2) => 100.0), [:L82]),
    ("F3 L89 at an INVENTED 50 MVA", [:L89 => 50.0], Dict((8, 9) => 50.0), [:L89]),
    ("F4 L45, L56 at an INVENTED 46 MVA", [:L45 => 46.0, :L56 => 46.0],
     Dict((4, 5) => 46.0, (5, 6) => 46.0), [:L56]),
]

@testset "M11 step 2 — PowerModels' DC OPF as the outside check on dc_opf" begin

@testset "the input: typed rows, their reader, their units" begin
    d = oracle_dc_opf(C9_MATPOWER).data
    @test d["baseMVA"] == 100.0
    # Their reader's per-unit conversion — theirs, not ours: ratings and costs on 100 MVA.
    @test [d["branch"][string(i)]["rate_a"] for i in 1:9] == [2.5, 2.5, 1.5, 3.0, 1.5, 2.5, 2.5, 2.5, 2.5]
    @test d["gen"]["2"]["cost"] ≈ [0.085 * 100^2, 1.2 * 100, 600.0]
    # The ±60° bound their reader adds (D7), on every branch.
    @test all(b -> b["angmin"] == -M11_ANGLE_BOUND && b["angmax"] == M11_ANGLE_BOUND,
              values(d["branch"]))
    # Their branches are ours, by bus number, in our orientation.
    net = m11_c9()
    t = oracle_dc_opf(C9_MATPOWER)
    @test [(t.f_bus[j], t.t_bus[j]) for j in 1:9] ==
          [(m11_busno(b.from), m11_busno(b.to)) for b in net.branches]
    @test t.gen_bus == [m11_busno(m.bus) for m in net.machines]
    # The edits land where they say, in MVA, and a row that does not exist is refused.
    e = GridSimReference.PM.parse_matpower(IOBuffer(
        matpower_edit(C9_MATPOWER; r0 = true, rate = Dict((8, 9) => 50.0))))
    @test all(b -> b["br_r"] == 0.0, values(e["branch"]))
    @test e["branch"]["8"]["rate_a"] == 0.5 && e["branch"]["5"]["rate_a"] == 1.5
    @test_throws ArgumentError matpower_edit(C9_MATPOWER; rate = Dict((2, 8) => 50.0))
end

for (name, ours_rate, their_rate, binding) in M11_FIXTURES
    @testset "$name — strict, R = 0 on their side" begin
        c = m11_compare(ours_rate, their_rate)
        @test c.ours.outcome === :optimal
        @test c.theirs.solved && c.tight.solved
        @test c.ours.at_limit == binding
        for ch in (:P, :flow, :θ, :cost)
            @test c.gap[ch] ≤ c.band[ch]
        end
        # The same line binds on their side: its flow on the rating, within the band.
        for id in binding
            e = findfirst(==(id), c.ours.branches)
            r = c.net.branches[e].rating / 100
            @test abs(abs(c.theirs.pf[c.ek[e]]) - r) ≤ c.band[:flow]
        end
        # Their ±60° bound never binds: every branch's angle difference far inside it.
        va = c.theirs.va
        @test maximum(abs(va[f] - va[t]) for (f, t) in zip(c.theirs.f_bus, c.theirs.t_bus)) <
              M11_ANGLE_BOUND - 0.5
        @info "M11 step 2 $name" gap = c.gap band = c.band
    end
end

@testset "23.2 the cost conversion, free: 5216.0266 on both" begin
    c = m11_compare(Pair{Symbol,Float64}[], Dict{Tuple{Int,Int},Float64}())
    @test round(c.theirs.cost; digits = 4) == 5216.0266
    @test round(c.ours.cost; digits = 4) == 5216.0266
end

@testset "F5 infeasible limits: HiGHS's certificate beside Ipopt's local word" begin
    net = m11_rated(m11_c9(), :L45 => 40.0, :L56 => 40.0)
    o = dc_opf(net; tol = M11_OURS_TOL[1], regularization = 0.0, margin = 0.0)
    t = oracle_dc_opf(matpower_edit(C9_MATPOWER; r0 = true,
                                    rate = Dict((4, 5) => 40.0, (5, 6) => 40.0)))
    @test o.outcome === :infeasible && occursin("INFEASIBILITY_CERTIFICATE", o.status)
    # Reported side by side, never called agreement: Ipopt proves nothing global.
    @test !t.solved
    @test t.status == "LOCALLY_INFEASIBLE"
    @info "M11 step 2 F5" ours = o.status theirs = (t.status, t.primal)
end

@testset "23.1 the formula difference with R left in: measured, never a band" begin
    ring = (:L45, :L56, :L67, :L78, :L89, :L94)
    strict = m11_compare(Pair{Symbol,Float64}[], Dict{Tuple{Int,Int},Float64}())
    c = m11_compare(Pair{Symbol,Float64}[], Dict{Tuple{Int,Int},Float64}(); r0 = false)
    ids = c.ours.branches
    isring = [id in ring for id in ids]
    # F1: nothing binds, so the dispatch never sees the network — outputs agree strictly...
    @test c.gap[:P] ≤ strict.band[:P]
    # ...the generator lines carry the outputs and agree too, and every ring line differs,
    # by more than the strict band (the comparison can see the formula at all).
    @test maximum(c.flowgap[.!isring]) ≤ strict.band[:flow]
    @test minimum(c.flowgap[isring]) > strict.band[:flow]
    @info "M11 step 2, 23.1 F1 ring-line flow gaps with R in (MW)" Dict(zip(ids[isring], 100 .* c.flowgap[isring]))
    # F3: with L89 binding, R moves the outputs as well.
    s3 = m11_compare([:L89 => 50.0], Dict((8, 9) => 50.0))
    c3 = m11_compare([:L89 => 50.0], Dict((8, 9) => 50.0); r0 = false)
    @test c3.theirs.solved
    @test c3.gap[:P] > s3.band[:P]
    @info "M11 step 2, 23.1 F3 output gaps with R in (MW)" 100 .* abs.(c3.ours.P .- c3.theirs.pg[c3.gk])
end

end # M11 step 2
