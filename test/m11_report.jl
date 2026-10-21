# ─────────────────────────────────────────────────────────────────────────────
# M11 step 5 — the report (`scripts/network_dispatch.jl`)
#
# case9 and its binding fixtures, the network-free dispatch beside the DC and the AC network
# optimum, and every AC optimum handed to the detailed tier. Asserted against the script's
# own row builders, so the numbers tested are the numbers printed. Every claim (s–x) was
# written AFTER the tables were read and is asserted here at the precision it prints.
# ─────────────────────────────────────────────────────────────────────────────

using Printf: @sprintf

const _ND = NetworkDispatchScript
const _ND_ROWS = _ND.report_rows()
const _ND_FLAT = _ND.flat_rows(_ND_ROWS)

_nd(key, loads) = only(r.row for r in _ND_ROWS if r.key === key && r.loads === loads)
_nd_flat(key, loads) = only(r.flat for r in _ND_FLAT if r.key === key && r.loads === loads)
_nd2(x) = @sprintf("%.2f", x)
_nd_mw(r, field, k) = getfield(r, field).P[k] * r.net.S_base
_nd_branch(r, id) = findfirst(==(id), r.ac.branches)

@testset "M11 step 5 — the report: the dispatch four ways, and handed to the detailed tier" begin

@testset "the script's invented ratings are the test suite's" begin
    @test _ND.L82_MVA == _OPF_L82_MVA
    @test _ND.L89_MVA == _OPF_L89_MVA
    @test _ND.L94_MVA == _AC_L94_MVA
    @test [r.key for r in _ND_ROWS] == repeat([k for (k, _, _) in _ND.FIXTURES]; inner = 2)
    @test [r.loads for r in _ND_ROWS] == repeat(collect(_ND.LOADS), length(_ND.FIXTURES))
end

@testset "each column reads what its header says" begin
    for r in _ND_ROWS
        R = r.row
        @test R.ed.cost == economic_dispatch(R.net).cost
        @test R.dc.outcome === :optimal
        if R.flowed.outcome === :secure
            g = dispatch_loss_gap(R.net, R.ed)
            @test R.flowed.cost == g.cost_flowed
        else
            @test GridSim._ac_powerflow_outcome(dispatch_schedule(R.net, R.ed)).outcome ===
                  R.flowed.outcome
        end
    end
    # The flat run's Pm and headroom are the engine's parameters, read by index.
    f = _nd_flat(:published, :constant_power)
    eng = init!(DetailedEngine, f.schedule; powerflow = ac_powerflow(f.schedule))
    @test f.Pm == [eng.params[i] for i in eng.Pm_pidx]
    @test f.headroom == [eng.params[i] for i in eng.hr_pidx]
end

@testset "claim s: where nothing binds, DC is the network-free dispatch; L94 binds in AC only" begin
    for (key, cost) in ((:published, "5216.03"), (:x150, "9857.82"), (:x175, "12819.84")),
        loads in _ND.LOADS
        R = _nd(key, loads)
        @test isempty(R.dc.at_limit)
        @test abs(R.dc.cost - R.ed.cost) < 0.005
        @test _nd2(R.dc.cost) == cost
    end
    for loads in _ND.LOADS
        R = _nd(:L94, loads)
        @test isempty(R.dc.at_limit)
        @test abs(R.dc.flow[findfirst(==(:L94), R.dc.branches)]) * R.net.S_base < _ND.L94_MVA
        @test R.ac.at_limit == [:L94]
    end
end

@testset "claim t: a binding rating costs and moves every unit; in AC MVA is shared with Q" begin
    R = _nd(:L82, :constant_power)
    @test R.dc.at_limit == [:L82]
    @test _nd2(_nd_mw(R, :dc, 2)) == "100.00"
    @test _ND._delta(R.dc.cost - R.ed.cost) == "+168.95"
    R = _nd(:L89, :constant_power)
    @test R.dc.at_limit == [:L89]
    @test [_ND._delta(_nd_mw(R, :dc, k) - _nd_mw(R, :ed, k)) for k in 1:3] ==
          ["+35.32", "-33.80", "-1.53"]
    @test _ND._delta(R.dc.cost - R.ed.cost) == "+234.65"
    @test _ND._delta(_nd(:L82, :constant_power).ac.cost - R.ed.cost) == "+409.61"
    @test _ND._delta(R.ac.cost - R.ed.cost) == "+427.03"
    @test _nd2(_nd_mw(_nd(:L82, :constant_power), :ac, 2)) == "88.97"
    # The DC rows are the same on both load models: DC reads no load model.
    for key in (:L82, :L89)
        @test _nd(key, :default).dc.P == _nd(key, :constant_power).dc.P
    end
end

@testset "claim u: where something binds, M6's dispatch is refused; where not, AC is cheaper" begin
    detail(R) = _ND._refusal(R.flow_detail)
    for (key, txt) in ((:L82, "overload, L82 143.0/100 MVA"), (:L89, "overload, L89 74.0/50 MVA"),
                       (:L94, "overload, L94 71.8/60 MVA"))
        @test detail(_nd(key, :constant_power)) == txt
        @test _nd(key, :default).flowed.outcome === :overload
    end
    @test detail(_nd(:x150, :constant_power)) == "voltage, B9 0.8996 pu"
    for (loads, gap) in ((:constant_power, "0.02"), (:default, "14.22"))
        R = _nd(:published, loads)
        @test R.flowed.outcome === :secure && R.flowed.within
        @test R.ac.cost < R.flowed.cost                      # recomputed, not rounded
        @test _nd2(R.flowed.cost - R.ac.cost) == gap
    end
    R = _nd(:published, :constant_power)
    @test (_nd2(R.ac.cost), _nd2(R.flowed.cost)) == ("5325.27", "5325.29")
end

@testset "claim v: on constant-power loads AC is dearer than DC; at 1.75× it finds nothing" begin
    for (key, _, _) in _ND.FIXTURES
        R = _nd(key, :constant_power)
        R.ac.outcome === :locally_optimal || continue
        @test R.ac.cost > R.dc.cost
    end
    R = _nd(:published, :constant_power)
    @test _ND._delta(R.ac.cost - R.dc.cost) == "+109.24"
    @test _nd2(R.ac.losses * R.net.S_base) == "4.46"
    R = _nd(:x150, :constant_power)
    @test _ND._delta(R.ac.cost - R.dc.cost) == "+383.82"
    @test R.ac.at_band == [:B9] && isempty(R.ac.at_limit)
    @test _ND._delta(_nd_mw(R, :ac, 1) - _nd_mw(R, :dc, 1)) == "+13.21"
    R = _nd(:x175, :constant_power)
    @test R.ac.outcome === :locally_infeasible && R.dc.outcome === :optimal
end

@testset "claim w: on the default loads AC serves less load, and costs less for it" begin
    shifts = Float64[]
    for (key, _, _) in _ND.FIXTURES
        R = _nd(key, :default)
        @test R.ac.outcome === :locally_optimal
        @test R.ac.cost < R.ed.cost
        cp = _nd(key, :constant_power).ac
        cp.outcome === :locally_optimal && @test R.ac.cost < cp.cost
        push!(shifts, -R.ac.load_shift * R.net.S_base)
    end
    @test all(>(0), shifts)
    @test (_nd2(minimum(shifts)), _nd2(maximum(shifts))) == ("17.15", "81.17")
    @test _ND._delta(_nd(:published, :default).ac.cost - _nd(:published, :default).ed.cost) == "-332.70"
    @test _ND._delta(_nd(:x175, :default).ac.cost - _nd(:x175, :default).ed.cost) == "-2673.54"
end

@testset "claim x: every AC optimum runs flat in the detailed tier; G1's reserve is its own" begin
    @test length(_ND_FLAT) == count(r -> r.row.ac.outcome === :locally_optimal, _ND_ROWS) == 11
    @test count(r -> !isempty(r.ac.at_limit) || !isempty(r.ac.at_band), _ND_FLAT) == 7
    @test @sprintf("%.1e", maximum(r.flat.drift for r in _ND_FLAT)) == "8.3e-13"
    @test @sprintf("%.1e", maximum(r.flat.Pm_gap for r in _ND_FLAT)) == "3.4e-14"
    @test all(r.flat.drift < 1e-10 for r in _ND_FLAT)      # M5's flat-run gate
    @test all(r.flat.n_samples > 100 for r in _ND_FLAT)
    # D12: G1's reserve in the engine is Pmax less what G1 produces at the optimum.
    for r in _ND_FLAT
        m = r.flat.schedule.machines[1]
        @test abs(r.flat.headroom[1] - (m.Pmax / r.flat.schedule.S_base - r.ac.P[1])) ≤ 1e-12
        @test r.flat.headroom[2:end] == r.flat.headroom_schedule[2:end]
    end
    # The controls. The start is a real check: a schedule outside a limit is refused there
    # (the DC optimum at 1.5×, B9 at 0.8996 pu). And the Pm gap sees a schedule that is not
    # the optimum's: G2 moved by 1 MW (G1 taking the difference) shows 0.01 pu. (A third,
    # tried first and BLIND: every one of the eleven AC optima solved at margin 0 starts too —
    # D9's margin is a guarantee against the re-solve's band, needed by none of them;
    # m11-context.md, "What step 5's report measured".)
    R = _nd(:x150, :constant_power)
    dcs = dispatch_schedule(R.net, R.dc)
    @test_throws Exception init!(DetailedEngine, dcs; powerflow = ac_powerflow(dcs))
    R = _nd(:published, :constant_power)
    s0 = dispatch_schedule(R.net, R.ac)
    ms = [k == 2 ? GridSim._machine_with(m; P0 = m.P0 + 1.0) :
          k == 1 ? GridSim._machine_with(m; P0 = m.P0 - 1.0) : m for (k, m) in pairs(s0.machines)]
    moved = NetworkModel(s0.S_base, s0.f0, s0.buses, s0.branches, ms, s0.loads; slack = s0.slack)
    e = init!(DetailedEngine, moved; powerflow = ac_powerflow(moved))
    @test maximum(abs, [e.params[i] for i in e.Pm_pidx] .- R.ac.P) > 0.009
    gap(key, loads) = (f = _nd_flat(key, loads); (f.headroom[1] - f.headroom_schedule[1]) * 100)
    @test _nd2(-gap(:published, :constant_power)) == "4.46"
    @test _nd2(gap(:published, :default)) == "14.12"
    @test _nd2(gap(:x175, :default)) == "70.61"
end

end
