# M6 step 7 — cheapest dispatch, network-free (m6-context.md D16, m6-tasks.md step 7).
#
# THE COST DATA. MATPOWER `case9`, `data/case9.m`, fetched 2026-09-23 from
# https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case9.m
# (last commit touching the file: 31e3308e80f831e7310c2d45835501038665b5a3,
# 2017-10-31). Its header cites Chow (1982) p. 70 and an EPRI report for the
# NETWORK. **The `gencost` rows cite nothing: PUBLISHED BUT UNSOURCED**
# (docs/validation-ledger.md). The user chose this fallback over the Wood &
# Wollenberg example on 2026-09-23, knowing it has no printed answer — so D16 §5's
# part (b) is ABSENT for this step, and what stands in for it is named below.
#
# The rows are TYPED HERE, from the file, and the MW oracle reads them from this
# table — never from `Machine`, and never through `cost_arrays`. That is the whole
# point of the table: a check that reads the per-unit conversion cannot check the
# per-unit conversion (M4's lesson, met here a third time and planned for).
#
#   gencost: 2 startup shutdown 3 c2 c1 c0     gen: Pmax Pmin
#            2 1500 0 3 0.11   5   150              250   10
#            2 2000 0 3 0.085  1.2 600              300   10
#            2 3000 0 3 0.1225 1   335              270   10
#
# The startup column (1500 / 2000 / 3000) is NOT carried: it prices switching a
# unit on, and on/off decisions are out of scope (D16 §7).
const _C9 = ((c2 = 0.11,   c1 = 5.0, c0 = 150.0, Pmin = 10.0, Pmax = 250.0),
             (c2 = 0.085,  c1 = 1.2, c0 = 600.0, Pmin = 10.0, Pmax = 300.0),
             (c2 = 0.1225, c1 = 1.0, c0 = 335.0, Pmin = 10.0, Pmax = 270.0))

# Cost in $/h of an MW split, from the literal rows. Independent of every line of
# `src/`.
_c9_cost(rows, P) = sum(r.c2 * p^2 + r.c1 * p + r.c0 for (r, p) in zip(rows, P))

# The equal-incremental-cost closed form, in MW, from the literal rows (D16 §5 a).
# Valid only when no limit binds — the caller checks that it doesn't.
function _c9_closed_form(rows, D)
    λ = (D + sum(r.c1 / (2r.c2) for r in rows)) / sum(1 / (2r.c2) for r in rows)
    return [(λ - r.c1) / (2r.c2) for r in rows], λ
end

# The same condition with the limits in it: every free unit at one marginal cost λ,
# every other one clamped, λ found by bisection on the (monotone) total. Not a
# closed form, but pure arithmetic on the literal rows and nothing to do with the
# solver; it agrees with the closed form where both apply (tested).
function _c9_lambda(rows, D)
    P(λ) = [clamp((λ - r.c1) / (2r.c2), r.Pmin, r.Pmax) for r in rows]
    lo, hi = -1.0e6, 1.0e6
    for _ in 1:300
        mid = (lo + hi) / 2
        (sum(P(mid)) < D ? (lo = mid) : (hi = mid))
    end
    return P((lo + hi) / 2)
end

# D16 §5 c — exhaustive search in MW over the literal rows, every feasible split on
# an `h`-MW grid for all units but the last, the last taking what balances. Returns
# the cheapest cost found.
function _c9_search(rows, D, h)
    n = length(rows)
    best = Inf
    if n == 2
        for p1 in rows[1].Pmin:h:rows[1].Pmax
            p2 = D - p1
            rows[2].Pmin ≤ p2 ≤ rows[2].Pmax || continue
            best = min(best, _c9_cost(rows, (p1, p2)))
        end
    elseif n == 3
        for p1 in rows[1].Pmin:h:rows[1].Pmax, p2 in rows[2].Pmin:h:rows[2].Pmax
            p3 = D - p1 - p2
            rows[3].Pmin ≤ p3 ≤ rows[3].Pmax || continue
            best = min(best, _c9_cost(rows, (p1, p2, p3)))
        end
    else
        error("the search is for the two- and three-unit cases only")
    end
    return best
end

# THE BANDS — WRITTEN BEFORE ANY GAP WAS READ (D16 §5), from the settings the answer
# was produced at, which `EconomicDispatch` carries. Derivation, per unit, for a
# unit strictly inside its limits: HiGHS returns `p` satisfying stationarity
# `(2a2ᵢ + ε)pᵢ + a1ᵢ − λ = rᵢ` with `|rᵢ| ≤ τ` (dual feasibility), where `ε` is the
# regularization it adds to the Hessian, and the balance `Σp = D + s` with `|s| ≤ τ`
# (primal feasibility). Subtracting the exact optimum and writing `wᵢ = 1/2a2ᵢ`,
# `W = Σ wⱼ` over the free units:
#
#     δpᵢ = wᵢ(rᵢ − ε pᵢ + δλ),   δλ = (s − Σⱼ wⱼ(rⱼ − ε pⱼ)) / W
#     ⇒ |δpᵢ| ≤ wᵢ(2τ + 2ε·p̄) + τ·wᵢ/W ≤ w_max(2τ + 2ε·p̄) + τ
#
# with `p̄ = max|pmax|`. A unit AT a limit is off by at most `τ` (primal bound
# feasibility), which the same expression covers. The factor 2 on the whole is
# stated headroom for HiGHS measuring its tolerances on its own scaled problem, and
# it is the only number here that is not derived — if a gap needs more than it,
# that is a finding, not a reason to raise it.
function _ed_band_pu(ca, τ, ε)
    w = 1 / (2 * minimum(ca.a2))
    p̄ = maximum(abs, ca.pmax)
    return 2 * (w * (2τ + 2ε * p̄) + τ)
end
# The cost that position band can buy, first order plus second, in $/h:
# `Σ |marginalᵢ|·|δpᵢ| + a2ᵢ δpᵢ²` with each marginal bounded by its value at pmax.
function _ed_band_cost(ca, bp)
    return sum(abs(2ca.a2[k] * ca.pmax[k]) + abs(ca.a1[k]) for k in eachindex(ca.a2)) * bp +
           sum(ca.a2) * bp^2
end

# The case9 network WITHOUT line charging — `Branch` carries no `B` (m6-context.md
# D4), so this is NOT case9 and is never called that. `R`, `X` and ratings are the
# file's `branch` rows; bus 1 is the reference, as in the file. Loads are constant
# power (`a_p = 1`) by default, scaled together by `load/315`; `zip_default = true`
# gives them `Load`'s own default instead — constant IMPEDANCE — which is what
# most models in this repo carry and what the loss report has to survive (F7).
# The machines' dynamic data (`H`, `D`, `Xd′`, `E′`) is placeholder — no code this step runs reads it — and
# `S_rated` is the file's `mBase`. The starting `P0` is an arbitrary balanced
# schedule (each unit's share of `ΣPmax`), NOT the file's `Pg`: those sum to 320.3
# MW against 315 of load, the flow's losses already in them, and `NetworkModel`'s
# schedule balance refuses that by design.
function _ed_case9(; S_base = 100.0, load = 315.0, lossy = true, costed = true,
                     rows = _C9, zip_default = false)
    s = load / 315.0
    buses = [Bus(Symbol(:B, i), 345.0) for i in 1:9]
    br(id, f, t, r, x, rate) = Branch(id, Symbol(:B, f), Symbol(:B, t), x, rate;
                                      R = lossy ? r : 0.0)
    branches = [br(:L14, 1, 4, 0.0, 0.0576, 250.0), br(:L45, 4, 5, 0.017, 0.092, 250.0),
                br(:L56, 5, 6, 0.039, 0.17, 150.0), br(:L36, 3, 6, 0.0, 0.0586, 300.0),
                br(:L67, 6, 7, 0.0119, 0.1008, 150.0), br(:L78, 7, 8, 0.0085, 0.072, 250.0),
                br(:L82, 8, 2, 0.0, 0.0625, 250.0), br(:L89, 8, 9, 0.032, 0.161, 250.0),
                br(:L94, 9, 4, 0.01, 0.085, 250.0)]
    # The file's reactances are pu on ITS base, 100 MVA. On any other `S_base` they
    # are rescaled, so the network stays the same network.
    if S_base != 100.0
        branches = [Branch(b.id, b.from, b.to, b.X * S_base / 100.0, b.rating;
                           R = b.R * S_base / 100.0) for b in branches]
    end
    Vg = (1.04, 1.025, 1.025)
    ΣPmax = sum(r.Pmax for r in rows)
    machines = [Machine(Symbol(:G, i), Symbol(:B, i), 100.0, 5.0, 0.0, 0.2, 1.0,
                        load * rows[i].Pmax / ΣPmax, Inf, rows[i].Pmax;
                        V_set = Vg[i], Q_min = -300.0 / S_base, Q_max = 300.0 / S_base,
                        (costed ? (cost_c2 = rows[i].c2, cost_c1 = rows[i].c1,
                                   cost_c0 = rows[i].c0, Pmin = rows[i].Pmin) :
                                  NamedTuple())...)
                for i in 1:3]
    L(id, bus, P, Q) = zip_default ? Load(id, bus, P, Q) : Load(id, bus, P, Q, 0.0, 0.0, 1.0)
    loads = [L(:D5, :B5, 90.0s, 30.0s), L(:D7, :B7, 100.0s, 35.0s),
             L(:D9, :B9, 125.0s, 50.0s)]
    return NetworkModel(S_base, 50.0, buses, branches, machines, loads; slack = :B1)
end

# Two of the case9 units on two buses — the two-unit case the search covers.
function _ed_two_unit(; load = 200.0, S_base = 100.0)
    rows = _C9[1:2]
    buses = [Bus(:B1, 345.0), Bus(:B2, 345.0)]
    branches = [Branch(:L12, :B1, :B2, 0.1, 500.0)]
    machines = [Machine(Symbol(:G, i), Symbol(:B, i), 100.0, 5.0, 0.0, 0.2, 1.0,
                        load / 2, Inf, rows[i].Pmax;
                        cost_c2 = rows[i].c2, cost_c1 = rows[i].c1,
                        cost_c0 = rows[i].c0, Pmin = rows[i].Pmin) for i in 1:2]
    loads = [Load(:D2, :B2, load, 0.0, 0.0, 0.0, 1.0)]
    return NetworkModel(S_base, 50.0, buses, branches, machines, loads; slack = :B1)
end

_ed_MW(ed) = ed.P .* ed.S_base

# The three loads: case9's own (no limit binds — computed, not assumed: see the
# first assertion), and two of OURS chosen so a limit MUST bind, labelled as ours.
const _ED_LOADS = (published = 315.0,   # case9's load
                   at_max = 780.0,      # ours: G2 is driven to its 300 MW maximum
                   at_min = 60.0)       # ours: G1 is held at its 10 MW minimum

@testset "M6 step 7 — cheapest dispatch, network-free" begin

@testset "Machine gains a cost and a minimum, defaulted to NOT GIVEN" begin
    m = Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0)
    @test isnan(m.cost_c2) && isnan(m.cost_c1) && isnan(m.cost_c0) && isnan(m.Pmin)
    # Every fixture in the repo is uncosted: the fields exist, and nothing old moved.
    for net in (three_machine_ring(), two_machine_system(), governed_ring())
        @test all(mm -> isnan(mm.cost_c2) && isnan(mm.Pmin), net.machines)
    end
    c = Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0, Inf, 250.0;
                cost_c2 = 0.11, cost_c1 = 5.0, cost_c0 = 150.0, Pmin = 10.0)
    @test (c.cost_c2, c.cost_c1, c.cost_c0, c.Pmin) === (0.11, 5.0, 150.0, 10.0)
    # A cost is all three coefficients or none — a missing one would be a zero.
    @test_throws ArgumentError Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0;
                                       cost_c2 = 0.11, cost_c1 = 5.0)
    # Concave cost: the problem stops being convex and the solver's answer a minimum.
    err = try
        Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0;
                cost_c2 = -0.1, cost_c1 = 5.0, cost_c0 = 0.0)
    catch e
        e
    end
    @test err isa ArgumentError && occursin("cost_c2", err.msg)
    @test_throws ArgumentError Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0, Inf, 50.0;
                                       Pmin = 60.0)                       # Pmin > Pmax
    @test_throws ArgumentError Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0;
                                       cost_c2 = Inf, cost_c1 = 5.0, cost_c0 = 0.0)
    # NO `P0 ≥ Pmin` guard, on purpose: a pre-dispatch schedule may sit anywhere, and
    # M2a's negative-P0 machines exist. The minimum is the DISPATCH's constraint.
    @test Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 5.0, Inf, 250.0; Pmin = 10.0).P0 == 5.0
    # A linear cost (c2 = 0) is legal: convex, and the MATPOWER form allows it.
    @test Machine(:G, :B, 100.0, 5.0, 0.0, 0.2, 1.0, 50.0;
                  cost_c2 = 0.0, cost_c1 = 5.0, cost_c0 = 0.0).cost_c2 === 0.0
end

@testset "_machine_with rebuilds through the constructor and carries every field" begin
    net = _ed_case9()
    for m in net.machines
        @test GridSim._machine_with(m) === m
        m2 = GridSim._machine_with(m; P0 = 42.0)
        @test m2.P0 === 42.0
        for f in fieldnames(Machine)
            f === :P0 && continue
            @test getfield(m2, f) === getfield(m, f)
        end
    end
    @test_throws ArgumentError GridSim._machine_with(net.machines[1]; nonsense = 1.0)
    @test_throws ArgumentError GridSim._machine_with(net.machines[1]; Pmin = 1.0e6)
end

@testset "cost_arrays: the per-unit conversion, written out" begin
    for S in (100.0, 250.0)
        ca = cost_arrays(_ed_case9(; S_base = S))
        @test ca.ids == [:G1, :G2, :G3]
        for (k, r) in pairs(_C9)
            @test ca.a2[k] == r.c2 * S^2
            @test ca.a1[k] == r.c1 * S
            @test ca.a0[k] == r.c0
            @test ca.pmin[k] == r.Pmin / S
            @test ca.pmax[k] == r.Pmax / S
        end
    end
end

@testset "the scenario file carries the cost, and an older file reads as NOT GIVEN" begin
    # D16 deferred this fold-in; `test/scenario_file.jl`'s field-list guard forced it,
    # because a writer that silently drops a field is the failure it exists to catch.
    dir = mktempdir()
    path = joinpath(dir, "costed.toml")
    net = _ed_case9()
    write_scenario(path, net)
    back = read_scenario(path).net
    @test back.machines == net.machines
    @test [(m.cost_c2, m.cost_c1, m.cost_c0, m.Pmin) for m in back.machines] ==
          [(r.c2, r.c1, r.c0, r.Pmin) for r in _C9]
    # the dispatch of the read-back model is the dispatch of the original, exactly
    @test economic_dispatch(back).P == economic_dispatch(net).P
    # an uncosted model writes `nan` and reads NaN back — not zero
    write_scenario(path, three_machine_ring())
    @test occursin("cost_c2 = nan", read(path, String))
    @test all(m -> isnan(m.cost_c2) && isnan(m.Pmin), read_scenario(path).net.machines)
    # a file written before step 7 has no such keys at all, and reads the same way
    old = replace(read(path, String), r"(?m)^ *(cost_c[012]|Pmin) = .*\n" => "")
    @test !occursin("cost_c", old)
    write(path, old)
    @test all(m -> isnan(m.cost_c0) && isnan(m.Pmin), read_scenario(path).net.machines)
end

@testset "the refusals, each by name — with or without the solver" begin
    msg(f) = try f(); "" catch e; sprint(showerror, e) end
    # the problem check is core's, so it answers without the extension involved
    unc = _ed_case9(; costed = false)
    @test occursin("G1", msg(() -> GridSim._dispatch_problem(unc)))
    @test occursin("no cost", msg(() -> economic_dispatch(unc)))
    # a cost but no minimum
    m = _ed_case9().machines
    nomin = NetworkModel(100.0, 50.0, _ed_case9().buses, _ed_case9().branches,
                         [m[1], m[2], Machine(:G3, :B3, 100.0, 5.0, 0.0, 0.2, 1.0,
                                              m[3].P0, Inf, 270.0; cost_c2 = 0.1225,
                                              cost_c1 = 1.0, cost_c0 = 335.0)],
                         _ed_case9().loads; slack = :B1)
    @test occursin("G3", msg(() -> economic_dispatch(nomin)))
    @test occursin("minimum", msg(() -> economic_dispatch(nomin)))
    # the load no dispatch meets, both ways — and the POSITIVE CONTROLS, at exactly
    # the edges, which must dispatch every unit to that edge.
    # Above every maximum is UNREACHABLE: `P0 ≤ Pmax` per machine and the schedule
    # balance mean no such model can be built at all. Measured, not assumed — the
    # first draft of this test asserted the dispatch's refusal and got the
    # constructor's instead. The dispatch keeps its own check anyway (see source).
    @test occursin("Pmax", msg(() -> _ed_case9(; load = 821.0)))
    @test occursin("minimum", msg(() -> economic_dispatch(_ed_case9(; load = 29.0))))
    top = economic_dispatch(_ed_case9(; load = 820.0))
    @test _ed_MW(top) ≈ [250.0, 300.0, 270.0] atol = 1e-6
    bot = economic_dispatch(_ed_case9(; load = 30.0))
    @test _ed_MW(bot) ≈ [10.0, 10.0, 10.0] atol = 1e-6
    # the fallback, reached with a backend the extension does not implement
    @test occursin("using JuMP, HiGHS",
                   msg(() -> GridSim._dispatch_solve(nothing, nothing, 1e-9, 0.0)))
    @test_throws ArgumentError economic_dispatch(_ed_case9(); tol = 0.0)
    @test_throws ArgumentError economic_dispatch(_ed_case9(); regularization = -1.0)
end

@testset "the solver is an EXTENSION: core's dependency list did not grow" begin
    proj = GridSim.TOML.parsefile(joinpath(pkgdir(GridSim), "Project.toml"))
    @test !haskey(proj["deps"], "JuMP") && !haskey(proj["deps"], "HiGHS")
    @test haskey(proj["weakdeps"], "JuMP") && haskey(proj["weakdeps"], "HiGHS")
    @test Base.get_extension(GridSim, :GridSimDispatchExt) !== nothing   # and it loaded
end

# ── the oracle ────────────────────────────────────────────────────────────────────

@testset "oracle (a): the closed form, in MW, from the literal rows" begin
    P, λ = _c9_closed_form(_C9, _ED_LOADS.published)
    @test all(r.Pmin < p < r.Pmax for (r, p) in zip(_C9, P))    # interior: (a) applies
    @test _c9_lambda(_C9, _ED_LOADS.published) ≈ P rtol = 1e-12  # the two oracles agree
    ed = economic_dispatch(_ed_case9())
    bp = _ed_band_pu(cost_arrays(_ed_case9()), ed.tol, ed.regularization)
    @test maximum(abs, _ed_MW(ed) .- P) ≤ bp * ed.S_base
    @test abs(ed.cost - _c9_cost(_C9, P)) ≤ _ed_band_cost(cost_arrays(_ed_case9()), bp)
    @test sum(ed.P) ≈ ed.demand atol = 2ed.tol
end

@testset "oracle (a′): a limit that MUST bind, both ends — our loads, not published" begin
    for (D, k, edge) in ((_ED_LOADS.at_max, 2, :Pmax), (_ED_LOADS.at_min, 1, :Pmin))
        P0, _ = _c9_closed_form(_C9, D)
        # the unclamped closed form puts unit k past its limit — so the limit binds
        @test edge === :Pmax ? P0[k] > _C9[k].Pmax : P0[k] < _C9[k].Pmin
        P = _c9_lambda(_C9, D)
        @test P[k] == getfield(_C9[k], edge)
        net = _ed_case9(; load = D)
        ed = economic_dispatch(net)
        bp = _ed_band_pu(cost_arrays(net), ed.tol, ed.regularization)
        @test maximum(abs, _ed_MW(ed) .- P) ≤ bp * ed.S_base
    end
end

@testset "part (b) is ABSENT, and what stands in for it: S_base invariance" begin
    # There is no printed answer for case9's costs, so nothing in MW from the source
    # checks the per-unit conversion. Two things do instead: the literal-MW oracle
    # above (it never reads `cost_arrays`), and THIS — the same machines and load at
    # two bases must give the same MW. A conversion wrong by a factor of `S_base`
    # makes the answer a function of `S_base`. Neither base is 1, where every such
    # factor vanishes.
    for D in values(_ED_LOADS)
        a = economic_dispatch(_ed_case9(; S_base = 100.0, load = D))
        b = economic_dispatch(_ed_case9(; S_base = 250.0, load = D))
        ba = _ed_band_pu(cost_arrays(_ed_case9(; S_base = 100.0)), a.tol, a.regularization)
        bb = _ed_band_pu(cost_arrays(_ed_case9(; S_base = 250.0)), b.tol, b.regularization)
        @test maximum(abs, _ed_MW(a) .- _ed_MW(b)) ≤ ba * 100.0 + bb * 250.0
        @test abs(a.cost - b.cost) ≤
              _ed_band_cost(cost_arrays(_ed_case9(; S_base = 100.0)), ba) +
              _ed_band_cost(cost_arrays(_ed_case9(; S_base = 250.0)), bb)
    end
end

@testset "oracle (c): exhaustive search — nothing cheaper, and the search can see" begin
    h = 0.1        # MW
    for (rows, net) in ((_C9[1:2], _ed_two_unit()),
                        (_C9, _ed_case9()),
                        (_C9, _ed_case9(; load = _ED_LOADS.at_max)),
                        (_C9, _ed_case9(; load = _ED_LOADS.at_min)))
        ed = economic_dispatch(net)
        ca = cost_arrays(net)
        bc = _ed_band_cost(ca, _ed_band_pu(ca, ed.tol, ed.regularization))
        best = _c9_search(rows, ed.demand * ed.S_base, h)
        # ONE-SIDED, on COST, not position: near the optimum the surface is flat, so
        # the cheapest grid point can sit well away from it. Nothing is cheaper...
        @test best ≥ ed.cost - bc
        # ...and the search is not vacuous: its best is within what its own grid can
        # miss by. The free unit that balances moves at most h/2 and so does each
        # gridded one (or it sits exactly on the limit, which the grid includes), so
        # the excess is at most Σ c2·(h/2)² per unit — bounded here by n·c2max·h².
        @test best - ed.cost ≤ length(rows) * maximum(r.c2 for r in rows) * h^2 + bc
    end
end

@testset "the band survives the tolerances changing" begin
    # M2's rule: a gap below the solver's own tolerance is not a result until it
    # survives the tolerance changing. Tighter AND looser, and the regularization off.
    net = _ed_case9()
    P, _ = _c9_closed_form(_C9, _ED_LOADS.published)
    ca = cost_arrays(net)
    for τ in (1e-7, 1e-9, 1e-10), ε in (1e-7, 0.0)
        ed = economic_dispatch(net; tol = τ, regularization = ε)
        @test maximum(abs, _ed_MW(ed) .- P) ≤ _ed_band_pu(ca, τ, ε) * ed.S_base
    end
end

# ── the hand-off to the power flow ────────────────────────────────────────────────

@testset "dispatch_schedule: P0 is the dispatch, and NOTHING else moves" begin
    net = _ed_case9()
    ed = economic_dispatch(net)
    s = dispatch_schedule(net, ed)
    @test [m.P0 for m in s.machines] == _ed_MW(ed)
    for (a, b) in zip(net.machines, s.machines), f in fieldnames(Machine)
        f === :P0 || @test getfield(a, f) === getfield(b, f)
    end
    @test s.branches === net.branches && s.loads == net.loads && s.slack === net.slack
    # a dispatch of a DIFFERENT model is refused, not applied
    @test_throws ArgumentError dispatch_schedule(_ed_case9(; S_base = 250.0), ed)
    @test_throws ArgumentError dispatch_schedule(_ed_two_unit(), ed)
end

@testset "the losses' cost: positive on a lossy network, and why" begin
    net = _ed_case9()
    ed = economic_dispatch(net)
    g = dispatch_loss_gap(net, ed)
    losses = sum(g.flow.loss)
    @test g.losses === losses
    @test losses > 0                                         # the case really is lossy
    # constant-power loads draw their nominal P at any |V|: no shift to add
    @test abs(g.load_shift) ≤ length(net.buses) * eps()
    # the slack's pickup IS the losses, to the flow's own residual (step 3's identity)
    @test abs(g.pickup - losses) ≤ length(net.buses) * max(g.flow.residual, eps())
    # THE SIGN, DERIVED: gap = L·(2·a2·p + a1 + a2·L). The slack's marginal cost is
    # positive at its dispatch, so the gap has the sign of the pickup — asserted, not
    # bounded. And the pickup is the LOSSES only because these loads are constant
    # power; see the next testset but one for a model where it is not.
    ca = cost_arrays(net)
    k = findfirst(==(g.slack_machine), ca.ids)
    @test 2ca.a2[k] * ed.P[k] + ca.a1[k] > 0
    @test g.gap > 0
    @test g.gap ≈ g.pickup * (2ca.a2[k] * ed.P[k] + ca.a1[k] + ca.a2[k] * g.pickup) rtol = 1e-12
    @test g.cost_flowed > g.cost_optimal
end

@testset "the losses' cost on a LOSSLESS network" begin
    net = _ed_case9(; lossy = false)
    ed = economic_dispatch(net)
    g = dispatch_loss_gap(net, ed)
    # MEASURED FIRST, then asserted (m6-tasks.md step 7, F-list). D16 planned to
    # assert the gap "exactly zero" here, and a review predicted the summed branch
    # loss at least would be. NEITHER IS: measured, the pickup is 3.3e-16 pu and
    # Σ loss is −2.2e-16 pu, because `loss` is `flow + flow_rev` — two solved powers
    # that cancel only to rounding. What IS exactly zero is the loss recomputed from
    # the data, `|I|²·R` with `R = 0`:
    losses_from_R = sum(abs2((g.flow.Vm[g.schedule.bus_index[b.from]] *
                              cis(g.flow.θ[g.schedule.bus_index[b.from]]) -
                              g.flow.Vm[g.schedule.bus_index[b.to]] *
                              cis(g.flow.θ[g.schedule.bus_index[b.to]])) /
                             complex(b.R, b.X)) * b.R for b in net.branches)
    @test losses_from_R === 0.0
    # and the solved quantities are within the flow's own residual of it — the
    # bound step 3's losses identity already uses, not a new one. (The pickup is
    # this small only because the loads are constant power: with `Load`'s default
    # a lossless network still moves the slack, by the loads' shift — F7.)
    bound = length(net.buses) * max(g.flow.residual, eps())
    @test abs(sum(g.flow.loss)) ≤ bound
    @test abs(g.pickup) ≤ bound
    ca = cost_arrays(net)
    k = findfirst(==(g.slack_machine), ca.ids)
    @test abs(g.gap) ≤ bound * (2ca.a2[k] * ed.P[k] + ca.a1[k] + ca.a2[k] * bound)
end

@testset "on DEFAULT loads the pickup is NOT the losses — both parts, and the sum" begin
    # F7, found by review after the step was first committed: the slack picks up the
    # losses PLUS the change in what voltage-dependent loads draw. With `Load`'s
    # default (constant impedance) the second term dominates and has the other sign,
    # so a report of "the losses' cost" would have been negative on a default model.
    net = _ed_case9(; zip_default = true)
    @test all(l -> l.a_i == 0.0 && l.a_p == 0.0, net.loads)      # really the default
    ed = economic_dispatch(net)
    g = dispatch_loss_gap(net, ed)
    # THE DRAW IS WRITTEN OUT AS THE TEXTBOOK POLYNOMIAL, not read from `Pload` or
    # `_zip_scale` — step 3's lesson (sabotage S4): a check that computes the draw
    # through the function it checks restates it.
    drawn = 0.0
    for l in net.loads
        V = g.flow.Vm[net.bus_index[l.bus]]
        drawn += l.P0 / net.S_base * (l.a_z * V^2 + l.a_i * V + l.a_p)
    end
    shift = drawn - sum(l.P0 for l in net.loads) / net.S_base
    bound = length(net.buses) * max(g.flow.residual, eps())
    @test abs(g.load_shift - shift) ≤ bound
    @test abs(g.pickup - (g.losses + g.load_shift)) ≤ bound
    # measured, and the reason this testset exists: the shift is the larger term,
    # of the opposite sign, so the slack produces LESS than dispatched...
    @test g.losses > 0
    @test g.load_shift < -g.losses
    @test g.pickup < 0
    # ...and the flowed state is CHEAPER than the "optimum", which is not a paradox:
    # the optimum was computed for a nominal load the network never draws.
    @test g.gap < 0
    ca = cost_arrays(net)
    k = findfirst(==(g.slack_machine), ca.ids)
    @test g.gap ≈ g.pickup * (2ca.a2[k] * ed.P[k] + ca.a1[k] + ca.a2[k] * g.pickup) rtol = 1e-12
end

@testset "a slack bus with two machines is refused, not guessed" begin
    base = _ed_case9()
    m = base.machines
    extra = Machine(:G1b, :B1, 100.0, 5.0, 0.0, 0.2, 1.0, 0.0, Inf, 50.0;
                    V_set = 1.04, cost_c2 = 0.2, cost_c1 = 10.0, cost_c0 = 0.0, Pmin = 0.0)
    net = NetworkModel(100.0, 50.0, base.buses, base.branches, [m..., extra], base.loads;
                       slack = :B1)
    @test_throws ArgumentError dispatch_loss_gap(net, economic_dispatch(net))
end

end   # M6 step 7
