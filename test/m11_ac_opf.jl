# M11 step 3 — the AC network OPF, generator voltages held (Hurdle 24; m11-plan.md step 3,
# m11-context.md D4, D9, D11).
#
# Every band below was written in `docs/evidence/gridsim-m11/step3_predictions.md` before
# the comparison it bounds first ran. The fixtures are the costed case9 of step 1 at
# published load, at 1.5× (the voltage fixture) and at 1.75× (locally infeasible), on
# constant-power AND default loads, plus L94 at an INVENTED 60 MVA — the one AC fixture
# where a rating binds, and at the line's RECEIVING end.
#
# The centre is 24.1: the optimiser writes the AC equations a second time, by hand, and the
# answer handed back to `ac_powerflow` (our Newton, no optimiser) is the check that sees
# the two copies disagree. The optimiser and step 4's PowerModels share Ipopt, so 24.1,
# 24.2 and 24.5 are the solver-independent checks.
#
# Uses from earlier files: `_opf_c9`, `_opf_rated` (test/m11_dc_opf.jl);
# `OutageScreenScript.case9` (scripts/outage_screen.jl, included by runtests.jl).

using LinearAlgebra: opnorm

const _AC_TAU = 1.0e-9        # ac_opf's default
const _AC_TIGHT = 1.0e-10     # the tight run: Ipopt stalls at 1e-11 on three fixtures
const _AC_RHO = 1.0e-11       # 24.5's round-off allowance, pu (step 2's)
const _AC_L94_MVA = 60.0      # INVENTED: below L94's unconstrained 71.73 MVA (receiving end)

_ac_c9(; loads::Symbol = :constant_power, mw::Real = 315.0) =
    OutageScreenScript.case9(; costed = true, loads, mw)
_ac_l94(loads::Symbol) = _opf_rated(_ac_c9(; loads), :L94 => _AC_L94_MVA)

# κ = ‖J⁻¹‖∞ of the power flow's own equations at its own solution — central differences
# on core's residual, at the round the solve ended on (no switch: asserted by the caller).
function _ac_kappa(net::NetworkModel, f::ACPowerFlow)
    c, _ = GridSim._ac_first_round(net)
    x = vcat([f.θ[v] for v in c.nonslack], [f.Vm[v] for v in c.pq])
    N = length(x)
    J = zeros(N, N); F1 = zeros(N); F2 = zeros(N); h = 1.0e-7
    for j in 1:N
        xp = copy(x); xp[j] += h
        xm = copy(x); xm[j] -= h
        GridSim._ac_residual!(F1, xp, c)
        GridSim._ac_residual!(F2, xm, c)
        J[:, j] = (F1 .- F2) ./ (2h)
    end
    return opnorm(inv(J), Inf)
end

# The answer handed back to `ac_powerflow`, and the predictions file's bands for it:
# `band_x = 2κ(2τ + ρ_pf)` on |V| and θ, `band_S = 6.82·|y|max·band_x` on every branch
# quantity, `band_S + 2τ + ρ_pf` on the slack's output. Refused BY NAME where a reactive
# output sits on its limit (D4: the optimiser's "held" and the flow's switch may part).
function _ac_handback(net::NetworkModel, r::ACOPF)
    r.outcome === :locally_optimal || error("24.1: the OPF's outcome is :$(r.outcome)")
    isempty(r.q_at_limit) || error(
        "24.1 refused for this fixture: the reactive output at $(r.q_at_limit) sits on a " *
        "limit, where the OPF's held voltage and the power flow's switch may part (D4).")
    sched = dispatch_schedule(net, r)
    f = ac_powerflow(sched)
    isempty(f.limited) || error("24.1: the handed-back flow switched $(f.limited) to a limit")
    κ = _ac_kappa(sched, f)
    ρ = GridSim._PF_RESIDUAL
    bx = 2κ * (2r.tol + ρ)
    ymax = maximum(abs(inv(complex(b.R, b.X))) for b in net.branches)
    bS = (4 * 1.1 + 2 * 1.1^2) * ymax * bx
    return (; f, κ, bx, bS, bP = bS + 2r.tol + ρ)
end

_ac_mva(f) = [max(hypot(f.flow[e], f.qflow[e]), hypot(f.flow_rev[e], f.qflow_rev[e]))
              for e in eachindex(f.flow)]

# 24.5's band, step 2's form: each start's own convergence |run(τ) − run(tight)|, summed
# and doubled, plus ρ.
_ac_gap(a, b, fld) = maximum(abs, getfield(a, fld) .- getfield(b, fld))

const _AC_FIELDS = (:P, :Vm, :θ, :flow, :flow_rev, :qflow, :qflow_rev)

@testset "M11 step 3 — the AC network OPF, voltages held" begin

@testset "24.1 handed back to ac_powerflow: $label" for (label, mk) in (
        ("published, constant power", () -> _ac_c9()),
        ("published, default loads", () -> _ac_c9(; loads = :default)),
        ("1.5×, constant power", () -> _ac_c9(; mw = 1.5 * 315)),
        ("L94 at an INVENTED 60 MVA, constant power", () -> _ac_l94(:constant_power)),
        ("L94 at an INVENTED 60 MVA, default loads", () -> _ac_l94(:default)))
    net = mk()
    r = ac_opf(net)
    @test r.outcome === :locally_optimal
    @test isempty(r.q_at_limit)
    h = _ac_handback(net, r)
    f = h.f
    @test f.buses == r.buses && f.branches == r.branches
    @test maximum(abs, f.Vm .- r.Vm) ≤ h.bx
    @test maximum(abs, f.θ .- r.θ) ≤ h.bx
    for fld in (:flow, :flow_rev, :qflow, :qflow_rev)
        @test maximum(abs, getfield(f, fld) .- getfield(r, fld)) ≤ h.bS
    end
    @test maximum(abs, _ac_mva(f) .- r.mva) ≤ h.bS
    vs = net.bus_index[net.slack]
    ks = only(net.machines_at_bus[vs])
    @test abs(f.Pgen[vs] - r.P[ks]) ≤ h.bP
    # Every other machine holds its OPF output (the schedule), to round-off.
    for (k, m) in pairs(net.machines)
        k == ks && continue
        @test abs(f.Pgen[net.bus_index[m.bus]] - r.P[k]) ≤ h.bP
    end
    for v in eachindex(net.buses)
        isempty(net.machines_at_bus[v]) && continue
        deg = count(b -> b.from === net.buses[v].id || b.to === net.buses[v].id, net.branches)
        @test abs(f.Qgen[v] - r.Qgen[v]) ≤ deg * h.bS
    end
    # D9: the margins are larger than what the re-solve can move — on this fixture's κ.
    @test r.margin_V > h.bx
    for e in eachindex(r.branches)
        r.branches[e] in r.at_limit || continue
        @test r.margin_S * net.branches[e].rating / net.S_base > h.bS
    end
end

@testset "D11: the losses and the load-draw shift, reported apart" begin
    for loads in (:constant_power, :default), mw in (315.0, 1.5 * 315)
        net = _ac_c9(; loads, mw)
        r = ac_opf(net)
        n = length(net.buses)
        @test abs(sum(r.P) - r.demand - (r.losses + r.load_shift)) ≤ n * r.residual + 2r.tol * 3
        @test r.losses > 0
        if loads === :constant_power
            @test abs(r.load_shift) ≤ n * 1e-12
        else
            @test r.load_shift < 0    # sagging voltages serve less load (M6's −318 $/h lesson)
        end
    end
end

@testset "24.2 never dearer than M6's dispatch handed to the flow, $loads" for loads in
        (:constant_power, :default)
    net = _ac_c9(; loads)
    r = ac_opf(net)
    ed = economic_dispatch(net; tol = _AC_TAU, regularization = 0.0)
    g = dispatch_loss_gap(net, ed)
    f = g.flow
    # FEASIBILITY FIRST, for the OPF's own MARGINED problem — or the bound means nothing.
    for m in net.machines
        v = net.bus_index[m.bus]
        @test m.Q_min ≤ f.Qgen[v] ≤ m.Q_max          # the slack's included
    end
    @test g.slack_within_limits
    @test all(r.vmin .≤ f.Vm .≤ r.vmax)
    @test all(_ac_mva(f) .≤ r.limit)
    # The bound, recomputed here — never taken from rounded figures (0.02 $/h on cp).
    @test r.cost ≤ g.cost_flowed
end

@testset "24.3 the voltage fixture: 1.5×, constant power" begin
    net = _ac_c9(; mw = 1.5 * 315)
    # Positive control: the DC optimum (M6's — nothing binds in DC) is refused by the flow.
    d = dc_opf(net; regularization = 0.0)
    @test isempty(d.at_limit)
    out = GridSim._ac_powerflow_outcome(dispatch_schedule(net, d))
    @test out.outcome === :voltage
    @test [l.bus for l in out.detail] == [:B9]
    @test only(out.detail).Vm < 0.9
    # The OPF moves the dispatch to hold B9 on the margined floor.
    r = ac_opf(net)
    @test r.outcome === :locally_optimal
    @test r.at_band == [:B9] && isempty(r.at_limit)
    v9 = net.bus_index[:B9]
    @test abs(r.Vm[v9] - r.vmin) ≤ r.near
    @test r.vmin == 0.9 + r.margin_V
    h = _ac_handback(net, r)
    @test 0.9 < h.f.Vm[v9] ≤ r.vmin + h.bx
    @test r.cost > d.cost                      # the network costs something here
end

@testset "24.4 1.75×, constant power: Ipopt's word, and the cause pinned" begin
    net = _ac_c9(; mw = 1.75 * 315)
    r = ac_opf(net)
    @test r.outcome === :locally_infeasible
    @test startswith(r.status, "LOCALLY_INFEASIBLE")
    @test all(isnan, r.P) && isnan(r.cost) && isempty(r.at_band)
    @test_throws ArgumentError dispatch_schedule(net, r)
    # The floor lowered: solved — the floor is what bound it.
    low = ac_opf(net; vmin = 0.8)
    @test low.outcome === :locally_optimal
    @test minimum(low.Vm) < 0.9
    # The reactive limits removed: still no point — they were not the cause.
    ms = [GridSim._machine_with(m; Q_min = -Inf, Q_max = Inf) for m in net.machines]
    free = NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                        slack = net.slack)
    @test ac_opf(free).outcome === :locally_infeasible
end

@testset "L94 at an INVENTED 60 MVA: a rating binds at the RECEIVING end, $loads" for loads in
        (:constant_power, :default)
    net = _ac_l94(loads)
    r = ac_opf(net)
    base = ac_opf(_ac_c9(; loads))
    e = findfirst(==(:L94), r.branches)
    @test r.at_limit == [:L94]
    Sf = hypot(r.flow[e], r.qflow[e])
    St = hypot(r.flow_rev[e], r.qflow_rev[e])
    @test St > Sf                                      # the larger end is the far one
    @test abs(St - r.limit[e]) ≤ r.near
    @test r.limit[e] == _AC_L94_MVA * (1 - r.margin_S) / net.S_base
    @test r.cost > base.cost
    @test all(abs.(r.P .- base.P) .> 1e-3)             # every unit moves (> 0.1 MW)
end

@testset "24.5 two starts, one local answer: $label" for (label, mk) in (
        ("published, constant power", () -> _ac_c9()),
        ("published, default loads", () -> _ac_c9(; loads = :default)),
        ("1.5×, constant power", () -> _ac_c9(; mw = 1.5 * 315)),
        ("L94 60 MVA, constant power", () -> _ac_l94(:constant_power)),
        ("L94 60 MVA, default loads", () -> _ac_l94(:default)))
    net = mk()
    d = dc_opf(net; regularization = 0.0)
    flat, flat_t = ac_opf(net), ac_opf(net; tol = _AC_TIGHT)
    dc, dc_t = ac_opf(net; start = d), ac_opf(net; tol = _AC_TIGHT, start = d)
    @test flat.outcome === dc.outcome === :locally_optimal
    for fld in _AC_FIELDS
        band = 2 * (_ac_gap(flat, flat_t, fld) + _ac_gap(dc, dc_t, fld)) + _AC_RHO
        @test _ac_gap(flat, dc, fld) ≤ band
    end
    cband = 2 * (abs(flat.cost - flat_t.cost) + abs(dc.cost - dc_t.cost)) + _AC_RHO * abs(flat.cost)
    @test abs(flat.cost - dc.cost) ≤ cband
end

@testset "the answer's own bookkeeping" begin
    net = _ac_c9()
    r = ac_opf(net)
    @test r.θ[findfirst(==(net.slack), r.buses)] == 0.0
    for m in net.machines
        @test r.Vm[net.bus_index[m.bus]] === m.V_set      # held, exactly
    end
    @test r.residual ≤ 2 * (length(net.buses) + 1) * r.tol
    @test r.cost == sum(cost_arrays(net).a2 .* r.P .^ 2 .+ cost_arrays(net).a1 .* r.P .+
                        cost_arrays(net).a0)
    @test r.near == 2 * (length(net.buses) + 1) * r.tol
    # The schedule: every machine but the slack's at its OPF output; the slack's at the
    # nominal balance, so the model constructs.
    s = dispatch_schedule(net, r)
    @test [m.P0 for m in s.machines][2:3] == r.P[2:3] .* net.S_base
    @test sum(m.P0 for m in s.machines) ≈ sum(l.P0 for l in s.loads)
end

@testset "the refusals, by name (ac_opf)" begin
    msg(f) = try f(); "" catch e; sprint(showerror, e) end
    unc = OutageScreenScript.case9()
    @test occursin("ac_opf", msg(() -> ac_opf(unc))) && occursin("no cost", msg(() -> ac_opf(unc)))
    @test occursin("using JuMP, Ipopt",
                   msg(() -> GridSim._ac_opf_solve(nothing, nothing, 1e-9, nothing, 1)))
    net = _ac_c9()
    @test_throws ArgumentError ac_opf(net; tol = 0.0)
    @test_throws ArgumentError ac_opf(net; margin_V = -1e-6)
    @test_throws ArgumentError ac_opf(net; margin_S = 1.0)
    @test_throws ArgumentError ac_opf(net; vmin = 1.1, vmax = 0.9)
    @test occursin("`start` must be", msg(() -> ac_opf(net; start = :warm)))
    # A start from another model, and a start with no point.
    other = dc_opf(_ac_c9(; mw = 1.5 * 315))
    @test ac_opf(net; start = other).outcome === :locally_optimal   # same ids: accepted
    tri = dc_opf(_opf_triangle())
    @test occursin("not this model's", msg(() -> ac_opf(net; start = tri)))
    # A held voltage outside the band has no feasible point.
    hi = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
                      [k == 2 ? GridSim._machine_with(m; V_set = 1.12) : m
                       for (k, m) in pairs(net.machines)], net.loads; slack = net.slack)
    @test occursin("outside the band", msg(() -> ac_opf(hi)))
    # A schedule from another model's answer.
    @test occursin("dispatch_schedule", msg(() -> dispatch_schedule(_opf_triangle(), ac_opf(net))))
end

end
