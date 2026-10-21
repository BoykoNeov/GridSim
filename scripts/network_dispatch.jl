# The cheapest dispatch subject to the network, reported: case9 and its binding fixtures,
# the network-free dispatch (M6) beside the linear (DC) and the nonlinear (AC) network
# optimum, and the AC optimum handed to the detailed tier as a schedule that runs.
#
#   julia --project=reference scripts/network_dispatch.jl
#
# The solvers are optional extensions of GridSim (HiGHS for the dispatch and the DC OPF,
# Ipopt for the AC OPF), so the root environment alone cannot run this file: it needs one
# that carries JuMP, HiGHS and Ipopt beside GridSim, as `reference/` does. The test suite
# includes this file into a module; its test target carries all three.
#
# Plan + decisions: docs/plans/m11-plan.md step 5, docs/plans/m11-context.md D2, D4, D9,
# D11, D12.
#
# THE GRID IS M8's REPORT case9, NOT A COPY: `scripts/outage_screen.jl` is included into a
# submodule (`Single`), with MATPOWER's costs (`costed = true`, D10). It has NO LINE
# CHARGING (the model has no shunts), so every load limit below — the voltage floor
# binding at 1.5×, no AC answer found at 1.75× on constant-power loads — is a fact about
# THIS case9. MATPOWER's published case9 carries line charging, and PowerModels solves it
# at 1.75× (m11-context.md, "What step 4 measured").
#
# THE BINDING FIXTURES ARE INVENTED RATINGS, labelled wherever they are printed: on case9
# as published no line limit binds, in DC or AC (D1.2), so a network optimum checked only
# there is checked on nothing the network does. Each is the rating its step chose:
#   - L82 at 100 MVA — G2's own line: in DC its flow IS G2's output (step 1, 22.2);
#   - L89 at 50 MVA  — a ring line: the power reroutes and every unit moves (22.3);
#   - L94 at 60 MVA  — the AC fixture where a rating binds, at the RECEIVING end (step 3).
# And two loadings: 1.5×, where the AC optimum is held by the 0.9 pu floor at B9 (24.3),
# and 1.75×, where Ipopt finds no feasible point on constant-power loads (24.4).
#
# THREE THINGS EVERY ROW KEEPS APART.
#   - Ipopt's answer is LOCAL. "locally optimal" and "locally infeasible" are its words,
#     and neither is a claim about every possible dispatch.
#   - On the default (constant-impedance) loads a sagging voltage serves less load, so
#     part of any AC cost difference is load not served, not generation saved (D11). The
#     load-draw shift is printed beside the losses, and no row calls the difference "the
#     cost of the network" there.
#   - The AC comparison is against M6's dispatch HANDED TO THE AC FLOW, the reference
#     machine taking up whatever the flow needs — the network-free dispatch's own cost
#     never paid for the losses.

using GridSim
using Printf
import JuMP, HiGHS, Ipopt      # load the two solver extensions

module Single
# The single-outage report, verbatim — see the header. Its `main()` is guarded by
# `PROGRAM_FILE`, so including it runs nothing.
include(joinpath(@__DIR__, "outage_screen.jl"))
end

# The INVENTED ratings (MVA), the ones steps 1 and 3 chose; `test/m11_report.jl` asserts
# they are the test suite's `_OPF_L82_MVA`, `_OPF_L89_MVA` and `_AC_L94_MVA`.
const L82_MVA = 100.0
const L89_MVA = 50.0
const L94_MVA = 60.0

# `net` with some branch ratings replaced (MVA), everything else as built.
function rated(net::NetworkModel, ratings::Pair{Symbol,Float64}...)
    d = Dict(ratings)
    br = [Branch(b.id, b.from, b.to, b.X, get(d, b.id, b.rating); R = b.R) for b in net.branches]
    return NetworkModel(net.S_base, net.f0, net.buses, br, net.machines, net.loads;
                        slack = net.slack, inverters = net.inverters)
end

"""
    FIXTURES

`(key, label, build)`: `build(loads)` gives the costed case9 for that load model.
"""
const FIXTURES = [
    (:published, "case9 as published (315 MW)",
     loads -> Single.case9(; costed = true, loads)),
    (:L82, "L82 at an INVENTED $(Int(L82_MVA)) MVA (G2's own line)",
     loads -> rated(Single.case9(; costed = true, loads), :L82 => L82_MVA)),
    (:L89, "L89 at an INVENTED $(Int(L89_MVA)) MVA (a ring line)",
     loads -> rated(Single.case9(; costed = true, loads), :L89 => L89_MVA)),
    (:L94, "L94 at an INVENTED $(Int(L94_MVA)) MVA (a ring line)",
     loads -> rated(Single.case9(; costed = true, loads), :L94 => L94_MVA)),
    (:x150, "every load 1.5× (472.5 MW)",
     loads -> Single.case9(; costed = true, loads, mw = 1.5 * Single.CASE9_MW)),
    (:x175, "every load 1.75× (551.25 MW)",
     loads -> Single.case9(; costed = true, loads, mw = 1.75 * Single.CASE9_MW)),
]

const LOADS = (:constant_power, :default)
const LOAD_NAMES = Dict(:constant_power => "constant-power loads", :default => "default loads")

# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

_mw(P, S) = P .* S

"""
    dispatch_row(net) -> NamedTuple

One fixture on one load model, every answer the report prints:

  - `ed` — M6's network-free dispatch (`economic_dispatch`), and `flowed` — that dispatch
    handed to the AC flow: `outcome` (`:secure`, or why the flow refuses it), and where it
    is secure the cost with the reference machine covering what the flow needs
    (`dispatch_loss_gap`'s `cost_flowed`), its losses and load-draw shift
  - `dc` — the DC network optimum (`dc_opf`)
  - `ac` — the AC network optimum (`ac_opf`), voltages held
"""
function dispatch_row(net::NetworkModel)
    ed = economic_dispatch(net)
    sched = dispatch_schedule(net, ed)
    out = GridSim._ac_powerflow_outcome(sched)
    flowed = if out.outcome === :secure
        g = dispatch_loss_gap(net, ed)
        (; outcome = :secure, cost = g.cost_flowed, losses = g.losses,
           load_shift = g.load_shift, within = g.slack_within_limits)
    else
        (; outcome = out.outcome, cost = NaN, losses = NaN, load_shift = NaN, within = false)
    end
    return (; net, ed, flowed, flow_detail = out, dc = dc_opf(net), ac = ac_opf(net))
end

"""
    report_rows() -> Vector{NamedTuple}

Every fixture × load model, in `FIXTURES` × `LOADS` order: `(; key, label, loads, row)`.
"""
report_rows() = [(; key, label, loads, row = dispatch_row(build(loads)))
                 for (key, label, build) in FIXTURES for loads in LOADS]

# What binds, in words: the DC OPF's lines at their limit; the AC OPF's lines, buses on
# the band, reactive outputs on a limit.
_binds(d::DCOPF) = d.outcome === :optimal ?
                   (isempty(d.at_limit) ? "nothing" : join(d.at_limit, ", ")) : String(d.outcome)
function _binds(a::ACOPF)
    a.outcome === :locally_optimal || return "—"
    parts = String[]
    append!(parts, String.(a.at_limit))
    append!(parts, ["$b on $(a.vmin < 1 ? "the floor" : "the ceiling")" for b in a.at_band])
    append!(parts, ["$b reactive limit" for b in a.q_at_limit])
    return isempty(parts) ? "nothing" : join(parts, ", ")
end

_cost(x) = isnan(x) ? "—" : @sprintf("%.2f", x)
# A difference below half a cent prints as +0.00, never as a signed zero.
_delta(x) = isnan(x) ? "" : @sprintf("%+.2f", abs(x) < 0.005 ? 0.0 : x)

# Why `ac_powerflow` refused a schedule, from its own outcome: the buses out of the band,
# or the branches over their rating with the MVA it found.
function _refusal(out)
    out.outcome === :voltage &&
        return "voltage, " * join([@sprintf("%s %.4f pu", l.bus, l.Vm) for l in out.detail], ", ")
    out.outcome === :overload &&
        return "overload, " * join([@sprintf("%s %.1f/%.0f MVA", d.id, d.mva, d.rating)
                                    for d in out.detail], ", ")
    return String(out.outcome)
end
_gens(P, S) = any(isnan, P) ? "—" : join((@sprintf("%.2f", p) for p in _mw(P, S)), " / ")

function print_table(io::IO, rows)
    println(io, "\n== 1. The dispatch, four ways (\$/h; G1 / G2 / G3 in MW) ==")
    println(io, "   network-free = M6's economic_dispatch, which never sees the network;")
    println(io, "   … to the AC flow = that dispatch run through ac_powerflow, the reference machine")
    println(io, "   (G1) covering what the flow needs; DC = dc_opf; AC = ac_opf, voltages held.")
    println(io, "   vs free = the cost minus the network-free one. On the default loads an AC row's")
    println(io, "   difference includes the load NOT served at the sagging voltages (the load shift),")
    println(io, "   so there it is not the cost of the network (D11). No line charging (the header).")
    for r in rows
        R, S = r.row, r.row.net.S_base
        println(io, "\n### $(r.label) — $(LOAD_NAMES[r.loads])")
        line(name, cost, d, gens, what) =
            @printf(io, "  %-22s %10s %9s   %-26s  %s\n", name, cost, d, gens, what)
        line("", "cost", "vs free", "G1 / G2 / G3", "binds / outcome")
        line("network-free", _cost(R.ed.cost), "", _gens(R.ed.P, S), "—")
        fl = R.flowed
        why = fl.outcome === :secure ?
              @sprintf("losses %.2f MW, load shift %+.2f MW%s", fl.losses * S, fl.load_shift * S,
                       fl.within ? "" : ", G1 OUTSIDE its limits") :
              "REFUSED by the flow: " * _refusal(R.flow_detail)
        line("  … to the AC flow", _cost(fl.cost), _delta(fl.cost - R.ed.cost), "", why)
        line("DC network optimum", _cost(R.dc.cost), _delta(R.dc.cost - R.ed.cost),
             _gens(R.dc.P, S), _binds(R.dc))
        a = R.ac
        acwhy = a.outcome === :locally_optimal ?
                @sprintf("%s; losses %.2f MW, load shift %+.2f MW", _binds(a), a.losses * S,
                         a.load_shift * S) :
                "no AC answer found — Ipopt's LOCAL word: $(a.status)"
        line("AC network optimum", _cost(a.cost), _delta(a.cost - R.ed.cost), _gens(a.P, S), acwhy)
    end
end
print_table(rows) = print_table(stdout, rows)

# ---------------------------------------------------------------------------
# Section 2: the AC optimum handed to the detailed tier
# ---------------------------------------------------------------------------

# EVERY AC optimum the report has is handed over — seven of them sit ON a limit (B9 on the
# floor, a line at its rating), the cases D9's margin exists for, handed to a tier that
# refuses a breach strictly.
const FLAT_HORIZON = 10.0      # s
const FLAT_SAVEAT = 0.05       # s

"""
    flat_row(net, a::ACOPF) -> NamedTuple

The AC optimum's schedule (`dispatch_schedule`) started on the detailed tier from its own
AC power flow, as M9's dips start (`powerflow = ac_powerflow(schedule)`), and run
`FLAT_HORIZON` s with no event:

  - `drift` — the largest change of any recorded channel over the run
  - `Pm`, `Pm_gap` — each machine's mechanical power in the engine (pu) and its largest
    gap to the optimum's output
  - `headroom` — each machine's governor up-reserve in the engine (pu); `headroom_schedule`
    — `(Pmax − P0)/S_base`, the schedule's, which the reference machine's used to be (D12)
"""
function flat_row(net::NetworkModel, a::ACOPF)
    sched = dispatch_schedule(net, a)
    eng = init!(DetailedEngine, sched; powerflow = ac_powerflow(sched))
    ser = solve!(eng, (0.0, FLAT_HORIZON); saveat = FLAT_SAVEAT)
    drift = maximum(maximum(abs, getproperty(ser, ch) .- getproperty(ser, ch)[1])
                    for ch in keys(ser) if ch !== :t)
    Pm = [eng.params[i] for i in eng.Pm_pidx]
    headroom = [eng.params[i] for i in eng.hr_pidx]
    return (; drift, Pm, Pm_gap = maximum(abs, Pm .- a.P), headroom,
            headroom_schedule = machine_arrays(sched).headroom, n_samples = length(ser.t),
            schedule = sched)
end

flat_rows(rows) = [(; r.key, r.label, r.loads, flat = flat_row(r.row.net, r.row.ac), ac = r.row.ac)
                   for r in rows if r.row.ac.outcome === :locally_optimal]

function print_flat(io::IO, frows)
    println(io, "\n== 2. The AC optimum handed to the detailed tier: a flat run, no event ==")
    println(io, "   The schedule (`dispatch_schedule`) started from its own AC power flow and run")
    println(io, @sprintf("   %.0f s. drift = the largest change of any recorded channel; Pm gap = the", FLAT_HORIZON))
    println(io, "   largest gap between a machine's mechanical power in the engine and the optimum's")
    println(io, "   output; G1's up-reserve as the engine holds it (from what G1 produces, D12)")
    println(io, "   against the schedule's Pmax − P0.")
    @printf(io, "  %-43s %-21s %-15s %8s %8s   %s\n", "fixture", "loads", "what binds", "drift",
            "Pm gap", "G1 up-reserve, MW: engine / schedule's")
    for r in frows
        f, S = r.flat, r.flat.schedule.S_base
        @printf(io, "  %-43s %-21s %-15s %8.1e %8.1e   %.4f / %.4f\n", r.label, LOAD_NAMES[r.loads],
                _binds(r.ac), f.drift, f.Pm_gap, f.headroom[1] * S, f.headroom_schedule[1] * S)
    end
end
print_flat(frows) = print_flat(stdout, frows)

function main()
    println("The cheapest dispatch subject to the network (M11 step 5): case9, DC and AC")
    rows = report_rows()
    print_table(rows)
    print_flat(flat_rows(rows))
    print_claims()
end

# Written AFTER the tables were read, each asserted in `test/m11_report.jl`.
function print_claims(io::IO = stdout)
    println(io, """

== 3. What the tables say (each asserted in test/m11_report.jl) ==

 Every load limit below is case9's WITHOUT line charging (see the header), and every AC
 answer is Ipopt's local one.

 s. Where no line limit binds, the DC network optimum IS the network-free dispatch, to the
    cent: case9 as published, at 1.5× and at 1.75× (5216.03, 9857.82, 12819.84 \$/h). The
    INVENTED L94 rating binds nothing in DC either — its DC flow stays under 60 MW — and
    binds in AC on both load models: in AC the reactive power crosses it too, which DC
    does not carry.
 t. A rating that binds costs, and moves every unit. In DC, L82 at an invented 100 MVA
    (G2's own line) holds G2 at exactly 100.00 MW, +168.95 \$/h; L89 at an invented 50 MVA
    (a ring line) moves G1 +35.32, G2 −33.80 and G3 −1.53 MW, +234.65 \$/h. In AC on
    constant-power loads the same ratings cost more (+409.61, +427.03): a rating in MVA is
    spent on reactive power too, so G2 behind its own 100 MVA line gets 88.97 MW, not 100.
 u. Wherever something binds, M6's dispatch is not an operating point. Handed to the AC
    flow it is refused on every invented rating (L82 at 143.0 of 100 MVA on constant-power
    loads, L89 at 74.0 of 50, L94 at 71.8 of 60) and at 1.5× (B9 at 0.8996 pu). Where the
    flow accepts it — the published case — the AC optimum is cheaper, by 0.02 \$/h on
    constant-power loads (5325.27 against 5325.29) and 14.22 \$/h on the default loads.
 v. On constant-power loads every AC optimum is dearer than the DC one: +109.24 \$/h on
    the published case, which carries 4.46 MW of losses, and +383.82 at 1.5×, where B9
    sits on the 0.9 pu floor and G1 takes 13.21 MW more. At 1.75× Ipopt finds no AC point
    at all, where DC dispatches without complaint.
 w. On the default loads every AC cost is below its constant-power twin and below the
    network-free cost too (−332.70 \$/h on the published case, −2673.54 at 1.75×), because
    the sagging voltages serve 17.15 to 81.17 MW less load. That is load NOT SERVED, not
    generation saved (D11). At 1.75×, with 81.17 MW less to serve, it finds an AC point.
 x. Every AC optimum here runs as it stands in the detailed tier: all eleven, seven of them
    ON a limit, start from their own power flow and drift at most 8.3e-13 over 10 s, every
    machine's mechanical power the optimum's output within 3.4e-14 pu. G1's up-reserve in
    the engine is measured from what G1 produces (D12), not from its schedule: 4.46 MW less
    than Pmax − P0 on the published case with constant-power loads, and on the default loads
    MORE — by 14.12 MW at published load, 70.61 MW at 1.75×. A flat run never moves a
    governor, so it shows the schedule is a steady state; that the reserve is right is
    test/m11_headroom.jl's to show.
""")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
