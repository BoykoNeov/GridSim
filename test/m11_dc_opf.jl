# M11 step 1 — the DC network OPF (Hurdle 22; m11-plan.md step 1, m11-context.md D3, D9, D10).
#
# Every band below was written in `docs/evidence/gridsim-m11/step1_predictions.md` before
# the comparison it bounds first ran. The fixtures are case9 WITH ITS COSTS
# (`case9(; costed = true)`, the report script's grid — D10) and its variants, plus a
# hand-built three-bus triangle. On case9 as published no line binds (step 0), so the
# degeneration test there is a gate; the checks are the fixtures where a line binds.
#
# Uses from earlier files: `_C9`, `_ed_case9`, `_ed_band_pu`, `_ed_band_cost`,
# `_c9_closed_form` (test/m6_economic_dispatch.jl); `OutageScreenScript.case9`
# (scripts/outage_screen.jl, included by runtests.jl).

using LinearAlgebra: opnorm

const _OPF_TAU = 1.0e-9

# INVENTED ratings, labelled wherever they are used: case9's published ratings bind
# nothing (step 0), so every binding fixture is one of these.
const _OPF_L82_MVA = 100.0    # below G2's unconstrained 134.38 MW — G2's own line (22.2)
const _OPF_L89_MVA = 50.0     # below L89's unconstrained +72.17 MW — a ring line (22.3)

_opf_c9() = OutageScreenScript.case9(; costed = true)

# `net` with some branch ratings replaced (MVA), everything else as built.
function _opf_rated(net::NetworkModel, ratings::Pair{Symbol,Float64}...)
    d = Dict(ratings)
    br = [Branch(b.id, b.from, b.to, b.X, get(d, b.id, b.rating); R = b.R) for b in net.branches]
    return NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads;
                        slack = net.slack, inverters = net.inverters)
end

# `net` with machine `id`'s maximum lowered to `pmax` MW. `Machine` refuses P0 > Pmax,
# so its schedule moves down to the new maximum and the slack bus's machine takes the
# difference (D10) — the dispatch never reads the schedule, but the model must exist.
function _opf_capped(net::NetworkModel, id::Symbol, pmax::Float64)
    k = findfirst(m -> m.id === id, net.machines)
    m = net.machines[k]
    cut = max(m.P0 - pmax, 0.0)
    ks = net.machines_at_bus[net.bus_index[net.slack]][1]
    ms = [j == k ? GridSim._machine_with(mm; Pmax = pmax, P0 = min(mm.P0, pmax)) :
          j == ks ? GridSim._machine_with(mm; P0 = mm.P0 + cut) : mm
          for (j, mm) in pairs(net.machines)]
    return NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                        slack = net.slack, inverters = net.inverters)
end

# THE BAND (step1_predictions.md): M6's, with the balance held per bus (`nτ` for `τ`)
# and a term for the regularization reaching the angles.
function _opf_band_pu(net::NetworkModel, τ, ε)
    ca = cost_arrays(net)
    n = length(net.buses)
    w = 1 / (2 * minimum(ca.a2))
    p̄ = maximum(abs, ca.pmax)
    ΣX = sum(b.X for b in net.branches)
    D = sum(l.P0 for l in net.loads) / net.S_base
    return 2 * (w * (2τ + 2ε * p̄) + n * τ + 2w * ε * (n - 1) * ΣX^2 * D)
end

_opf_flow(r, id) = r.flow[findfirst(==(id), r.branches)]
_opf_MW(r) = r.P .* r.S_base

# The dispatch handed to `dc_powerflow` gives the OPF's own flows, to `2(n + m)τ`.
function _opf_identity(net::NetworkModel, r)
    f = dc_powerflow(dispatch_schedule(net, r))
    return maximum(abs.(f.flow .- r.flow)) ≤ 2 * (length(net.buses) + length(net.machines)) * r.tol
end

# The three-bus triangle of 22.4: the cheap unit (case9's G2 row) at A, the dear one
# (G1's row) at B, 200 MW of constant-power load at C. Reactances pu on 100 MVA.
function _opf_triangle(; rating_AC = 120.0)
    rA, rB = _C9[2], _C9[1]
    buses = [Bus(:A, 345.0), Bus(:B, 345.0), Bus(:C, 345.0)]
    br = [Branch(:AB, :A, :B, 0.1, 250.0), Branch(:AC, :A, :C, 0.1, rating_AC),
          Branch(:BC, :B, :C, 0.2, 250.0)]
    ms = [Machine(:GA, :A, 100.0, 5.0, 0.0, 0.2, 1.0, 100.0, Inf, rA.Pmax;
                  cost_c2 = rA.c2, cost_c1 = rA.c1, cost_c0 = rA.c0, Pmin = rA.Pmin),
          Machine(:GB, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 100.0, Inf, rB.Pmax;
                  cost_c2 = rB.c2, cost_c1 = rB.c1, cost_c0 = rB.c0, Pmin = rB.Pmin)]
    return NetworkModel(100.0, 50.0, buses, br, ms, [Load(:DC, :C, 200.0, 0.0, 0.0, 0.0, 1.0)];
                        slack = :A)
end

# The KKT system with one line binding at its UPPER limit, every unit free, in MW and
# $/MWh from the literal rows: `2c2ₖpₖ + c1ₖ = λ − μ·PTDFₖ`, `Σp = D`, `Σ PTDFₖpₖ = rhs`.
# Returns the solution and the system, whose inverse sizes the band.
function _opf_kkt(rows, ptdf, D, rhs)
    nu = length(rows)
    K = zeros(nu + 2, nu + 2)
    y = zeros(nu + 2)
    for k in 1:nu
        K[k, k] = 2rows[k].c2
        K[k, nu + 1] = -1.0
        K[k, nu + 2] = ptdf[k]
        y[k] = -rows[k].c1
    end
    K[nu + 1, 1:nu] .= 1.0
    y[nu + 1] = D
    K[nu + 2, 1:nu] .= ptdf
    y[nu + 2] = rhs
    x = K \ y
    return (; p = x[1:nu], λ = x[nu + 1], μ = x[nu + 2], K)
end

# The band on the closed form's dispatch, MW: the residuals the solver may leave (the
# balance and flow rows to `(n+1)τ` pu, i.e. `(n+1)τ·S_base` MW) through the inverse's
# dispatch rows, with M6's factor 2.
_opf_kkt_band(K, nu, n, τ, S) = 2 * opnorm(inv(K)[1:nu, :], Inf) * (n + 1) * τ * S

@testset "M11 step 1 — the DC network OPF" begin

@testset "case9(; costed = true) — the report grid with MATPOWER's costs (D10)" begin
    plain, costed = OutageScreenScript.case9(), _opf_c9()
    # The default path builds the identical object: no existing caller moves.
    @test repr(OutageScreenScript.case9(; costed = false)) == repr(plain)
    @test all(m -> isnan(m.cost_c2) && isnan(m.Pmin), plain.machines)
    # Row for row against the M6 rows (typed from MATPOWER's file) and `_ed_case9`.
    ed9 = _ed_case9()
    for (k, m) in pairs(costed.machines)
        @test (m.cost_c2, m.cost_c1, m.cost_c0, m.Pmin, m.Pmax) ===
              (_C9[k].c2, _C9[k].c1, _C9[k].c0, _C9[k].Pmin, _C9[k].Pmax)
        e = ed9.machines[k]
        @test (m.id, m.bus, m.cost_c2, m.cost_c1, m.cost_c0, m.Pmin, m.Pmax) ===
              (e.id, e.bus, e.cost_c2, e.cost_c1, e.cost_c0, e.Pmin, e.Pmax)
    end
    @test cost_arrays(costed) == cost_arrays(ed9)
    # `S_rated`, `H`, `D` and droop differ between the two copies (the script's are its
    # invented dynamics); no dispatch reads them. Only the costs were added here:
    for (a, b) in zip(plain.machines, costed.machines)
        @test GridSim._machine_with(b; cost_c2 = NaN, cost_c1 = NaN, cost_c0 = NaN,
                                    Pmin = NaN) |> repr == repr(a)
    end
end

@testset "22.1 degeneration: case9 as published binds nothing" begin
    net = _opf_c9()
    ca = cost_arrays(net)
    for ε in (0.0, 1.0e-7)
        r = dc_opf(net; tol = _OPF_TAU, regularization = ε)
        ed = economic_dispatch(net; tol = _OPF_TAU, regularization = ε)
        @test r.outcome === :optimal
        @test isempty(r.at_limit)
        band = _opf_band_pu(net, _OPF_TAU, ε) + _ed_band_pu(ca, _OPF_TAU, ε)
        @test maximum(abs.(r.P .- ed.P)) ≤ band
        @test abs(r.cost - ed.cost) ≤ _ed_band_cost(ca, band)
        @test _opf_identity(net, r)
        @test r.θ[findfirst(==(net.slack), r.buses)] == 0.0
    end
end

@testset "22.2 G2's own line binding IS G2's cap (an identity)" begin
    δ = 1.0e-6
    net = _opf_rated(_opf_c9(), :L82 => _OPF_L82_MVA)
    capped = _opf_capped(_opf_c9(), :G2, _OPF_L82_MVA * (1 - δ))
    ca = cost_arrays(capped)
    for ε in (0.0, 1.0e-7)
        r = dc_opf(net; tol = _OPF_TAU, regularization = ε, margin = δ)
        ed = economic_dispatch(capped; tol = _OPF_TAU, regularization = ε)
        @test r.outcome === :optimal
        @test r.at_limit == [:L82]
        n = length(net.buses)
        # L82 runs 8 → 2, so G2's power is NEGATIVE on it: the lower limit binds.
        @test abs(_opf_flow(r, :L82) + _OPF_L82_MVA * (1 - δ) / 100) ≤ 2 * (n + 1) * _OPF_TAU
        band = _opf_band_pu(net, _OPF_TAU, ε) + _ed_band_pu(ca, _OPF_TAU, ε)
        @test maximum(abs.(r.P .- ed.P)) ≤ band
        @test abs(r.cost - ed.cost) ≤ _ed_band_cost(ca, band)
        @test _opf_identity(net, r)
    end
end

@testset "22.3 a ring line binding reroutes power (L89 at an INVENTED 50 MVA)" begin
    δ = 1.0e-6
    base = _opf_c9()
    net = _opf_rated(base, :L89 => _OPF_L89_MVA)
    ed = economic_dispatch(base; tol = _OPF_TAU, regularization = 0.0)
    r = dc_opf(net; tol = _OPF_TAU, regularization = 0.0, margin = δ)
    n = length(net.buses)
    @test r.outcome === :optimal
    @test r.at_limit == [:L89]
    # L89 runs 8 → 9 and carries +72.17 MW unconstrained: the UPPER limit binds.
    @test abs(_opf_flow(r, :L89) - _OPF_L89_MVA * (1 - δ) / 100) ≤ 2 * (n + 1) * _OPF_TAU
    # Every unit moves, in the directions the ring's geometry predicts, and it costs.
    ΔP = _opf_MW(r) .- _ed_MW(ed)
    @test ΔP[1] > 1.0 && ΔP[2] < -1.0 && ΔP[3] < -1.0
    @test r.cost > ed.cost + 1.0
    @test _opf_identity(net, r)

    # Against a second formulation: the closed form with L89's PTDFs (slack B1) measured
    # by `dc_powerflow` on a 10 MW shift from G1 to each unit, from case9's own schedule
    # (no solver output enters).
    f0 = dc_powerflow(net)
    e89 = findfirst(==(:L89), r.branches)
    ptdf = zeros(3)
    for k in 2:3
        ms = [j == k ? GridSim._machine_with(m; P0 = m.P0 + 10.0) :
              j == 1 ? GridSim._machine_with(m; P0 = m.P0 - 10.0) : m
              for (j, m) in pairs(net.machines)]
        shifted = NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                               slack = net.slack)
        ptdf[k] = (dc_powerflow(shifted).flow[e89] - f0.flow[e89]) / 0.1
    end
    P0 = [m.P0 for m in net.machines]
    rhs = _OPF_L89_MVA * (1 - δ) - 100 * f0.flow[e89] + sum(ptdf .* P0)
    cf = _opf_kkt(_C9, ptdf, 315.0, rhs)
    @test cf.μ > 0                                            # an upper limit's sign
    @test all(k -> _C9[k].Pmin < cf.p[k] < _C9[k].Pmax, 1:3)  # every unit free
    @test maximum(abs.(_opf_MW(r) .- cf.p)) ≤ _opf_kkt_band(cf.K, 3, n, _OPF_TAU, 100.0)
    # At the default regularization, within the same band plus its ε terms.
    rε = dc_opf(net; tol = _OPF_TAU, margin = δ)
    @test maximum(abs.(_opf_MW(rε) .- cf.p)) ≤
          _opf_kkt_band(cf.K, 3, n, _OPF_TAU, 100.0) + 100 * _opf_band_pu(net, _OPF_TAU, rε.regularization)
end

@testset "22.4 the three-bus closed form, PTDFs by hand" begin
    δ = 1.0e-6
    rows = (_C9[2], _C9[1])                    # (cheap at A, dear at B), the literal rows
    # By hand, C the reference: an injection at A splits 0.75 / 0.25 over A–C and A–B–C;
    # one at B splits 0.5 / 0.5 over B–C and B–A–C. So on A→C: 0.75 and 0.5.
    ptdf_AC = [0.75, 0.5]
    # The control: A–C at 250 binds nothing — the closed form is M6's equal incremental
    # cost, and A→C carries 130.64 MW under it.
    ctl = dc_opf(_opf_triangle(; rating_AC = 250.0); tol = _OPF_TAU, regularization = 0.0)
    pc, _ = _c9_closed_form(collect(rows), 200.0)
    @test ctl.outcome === :optimal && isempty(ctl.at_limit)
    @test sum(ptdf_AC .* pc) ≈ 130.64 atol = 0.01
    @test maximum(abs.(_opf_MW(ctl) .- pc)) ≤ 100 * _opf_band_pu(_opf_triangle(), _OPF_TAU, 0.0)
    # Binding: A–C at 120 MVA, its upper limit (A→C is the positive orientation).
    net = _opf_triangle()
    r = dc_opf(net; tol = _OPF_TAU, regularization = 0.0, margin = δ)
    cf = _opf_kkt(rows, ptdf_AC, 200.0, 120.0 * (1 - δ))
    @test r.outcome === :optimal && r.at_limit == [:AC]
    @test cf.μ > 0
    @test all(k -> rows[k].Pmin < cf.p[k] < rows[k].Pmax, 1:2)
    @test cf.p ≈ [80.0, 120.0] atol = 1e-3                   # the predictions file, at δ = 0
    @test isapprox(cf.λ, 64.6; atol = 1e-2) && isapprox(cf.μ, 66.4; atol = 1e-2)
    @test maximum(abs.(_opf_MW(r) .- cf.p)) ≤ _opf_kkt_band(cf.K, 2, 3, _OPF_TAU, 100.0)
    @test _opf_identity(net, r)
    # The other two lines, by hand: A→B −40, B→C +80 MW — nowhere near 250.
    @test _opf_flow(r, :AB) * 100 ≈ 0.25 * cf.p[1] - 0.5 * cf.p[2] atol = 1e-5
    @test _opf_flow(r, :BC) * 100 ≈ 0.25 * cf.p[1] + 0.5 * cf.p[2] atol = 1e-5
end

@testset "infeasible limits are an outcome: B5 fed by two 40 MVA lines" begin
    net = _opf_rated(_opf_c9(), :L45 => 40.0, :L56 => 40.0)   # 80 < B5's 90 MW, by hand
    r = dc_opf(net; tol = _OPF_TAU)
    @test r.outcome === :infeasible
    @test occursin("INFEASIBILITY_CERTIFICATE", r.status)
    @test all(isnan, r.P) && isnan(r.cost) && isempty(r.at_limit)
    @test_throws ArgumentError dispatch_schedule(net, r)
    # The positive control: 92 MVA of feed reaches 90 MW.
    ok = dc_opf(_opf_rated(_opf_c9(), :L45 => 46.0, :L56 => 46.0); tol = _OPF_TAU)
    @test ok.outcome === :optimal
end

@testset "an infinite rating is no limit" begin
    r = dc_opf(_opf_rated(_opf_c9(), :L89 => Inf); tol = _OPF_TAU)
    @test r.outcome === :optimal && isempty(r.at_limit) && r.limit[findfirst(==(:L89), r.branches)] == Inf
end

@testset "the refusals, by name" begin
    msg(f) = try f(); "" catch e; sprint(showerror, e) end
    unc = OutageScreenScript.case9()
    @test occursin("dc_opf", msg(() -> dc_opf(unc))) && occursin("no cost", msg(() -> dc_opf(unc)))
    # economic_dispatch's messages did not move with the shared check.
    @test startswith(msg(() -> economic_dispatch(unc)), "ArgumentError: economic_dispatch: machine G1")
    @test occursin("minimum", msg(() -> dc_opf(_ed_case9(; load = 29.0))))
    @test occursin("using JuMP, HiGHS", msg(() -> GridSim._dc_opf_solve(nothing, nothing, 1e-9, 0.0)))
    @test_throws ArgumentError dc_opf(_opf_c9(); tol = 0.0)
    @test_throws ArgumentError dc_opf(_opf_c9(); regularization = -1.0)
    @test_throws ArgumentError dc_opf(_opf_c9(); margin = -1e-6)
    @test_throws ArgumentError dc_opf(_opf_c9(); margin = 1.0)
    # The plan's two network refusals are the CONSTRUCTORS': no model reaching `dc_opf`
    # can carry them (m11-context.md, "What step 1 measured").
    @test_throws ArgumentError Branch(:L, :A, :B, 0.1, 0.0)
    @test_throws ArgumentError NetworkModel(100.0, 50.0, [Bus(:A, 1.0), Bus(:B, 1.0)], Branch[],
                                            [Machine(:G, :A, 100.0, 5.0, 0.0, 0.2, 1.0, 0.0)])
end

end
