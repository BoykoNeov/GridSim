# Single-outage screening, reported: every line and every generator of two grids taken
# out one at a time, at both fidelities, side by side, with the reason for every place
# the two disagree.
#
#   julia --project=. scripts/outage_screen.jl
#
# Plan + decisions: docs/plans/m8-plan.md step 6, docs/plans/m8-context.md D9.
#
# THE TWO FIDELITIES. The linear (DC) screen keeps only real power and line reactances:
# every voltage is 1 pu, nothing is lost in the lines, nothing reactive flows. The
# nonlinear (AC) screen solves the full power flow. The DC one is the shortcut every
# real screening tool starts from; the gap between them is what the shortcut costs.
#
# THE ONE DECISION THIS STEP TOOK (D9, the user's choice): a line whose loss cuts off a
# generator that sits alone — nothing else on that side, no load, no inverter — is
# screened as that generator's outage, because for the grid that is left the two are the
# same event. case9's three generators each hang off exactly one line, so a third of its
# line outages are decided by this rule. Section 1 checks that the equivalence holds on
# the numbers, not just in the argument.
#
# BOTH GRIDS ARE PARTLY INVENTED, and say so wherever it matters:
#   - case9 WITHOUT LINE CHARGING (the model has no shunts), so part of every case9
#     voltage sag is the missing charging and not the outage (D0, Hurdle 13.4). Its
#     generators carry INVENTED droop and damping — published case9 has none, and with
#     none no frequency settles after losing a generator (D7's refusal).
#   - the mesh is step 5's five-bus fixture, invented throughout, declared in m8-context
#     D8. It has no line whose loss splits it, so the D9 rule never fires there.
# Both run on constant-power AND on the repo's default constant-impedance loads: M6
# step 7's rule — a claim made on one load model is a claim about that load model.

using GridSim
using Printf

const F0 = 50.0

# ---------------------------------------------------------------------------
# The fixtures
# ---------------------------------------------------------------------------

# case9's published branch data (R, X pu on 100 MVA; rating MVA). The same numbers as
# `_ed_case9` in `test/m6_economic_dispatch.jl` — a second copy, kept here because a
# deliverable script must not reach into the test suite; `test/m8_outage_screen.jl`
# asserts the two copies agree branch for branch, so they cannot drift apart unseen.
const CASE9_BRANCHES = [(:L14, 1, 4, 0.0, 0.0576, 250.0), (:L45, 4, 5, 0.017, 0.092, 250.0),
                        (:L56, 5, 6, 0.039, 0.17, 150.0), (:L36, 3, 6, 0.0, 0.0586, 300.0),
                        (:L67, 6, 7, 0.0119, 0.1008, 150.0), (:L78, 7, 8, 0.0085, 0.072, 250.0),
                        (:L82, 8, 2, 0.0, 0.0625, 250.0), (:L89, 8, 9, 0.032, 0.161, 250.0),
                        (:L94, 9, 4, 0.01, 0.085, 250.0)]
const CASE9_PMAX = (250.0, 300.0, 270.0)        # MW, published
const CASE9_VSET = (1.04, 1.025, 1.025)         # pu, published
const CASE9_LOADS = [(:D5, :B5, 90.0, 30.0), (:D7, :B7, 100.0, 35.0), (:D9, :B9, 125.0, 50.0)]
const CASE9_MW = 315.0
# INVENTED (published case9 has no dynamics): each machine rated at its Pmax, droop 5 %
# and damping 1 on its own base, H 5 s. These decide how a lost generator's power is
# shared and nothing else; no line-outage row reads them.
const R_DROOP, D_DAMP, H_INV = 0.05, 1.0, 5.0

_zip(loads::Symbol, id, bus, P, Q) =
    loads === :constant_power ? Load(id, bus, P, Q, 0.0, 0.0, 1.0) :
    loads === :default ? Load(id, bus, P, Q) :
    throw(ArgumentError("loads must be :constant_power or :default, got :$loads"))

"""
    case9(; loads = :constant_power, mw = 315.0) -> NetworkModel

case9 without line charging: published branches, loads, set-points and the published
Pmax-share schedule at 315 MW, reactive limits ±300 MVAr; invented droop and damping.
`mw` scales every load and the schedule with it (the published case is 315).
"""
function case9(; loads::Symbol = :constant_power, mw::Real = CASE9_MW)
    s = mw / CASE9_MW
    buses = [Bus(Symbol(:B, i), 345.0) for i in 1:9]
    br = [Branch(id, Symbol(:B, f), Symbol(:B, t), x, rate; R = r)
          for (id, f, t, r, x, rate) in CASE9_BRANCHES]
    ms = [Machine(Symbol(:G, i), Symbol(:B, i), CASE9_PMAX[i], H_INV, D_DAMP, 0.2, 1.0,
                  mw * CASE9_PMAX[i] / sum(CASE9_PMAX), R_DROOP, CASE9_PMAX[i];
                  V_set = CASE9_VSET[i], Q_min = -3.0, Q_max = 3.0)
          for i in 1:3]
    ls = [_zip(loads, id, bus, s * P, s * Q) for (id, bus, P, Q) in CASE9_LOADS]
    return NetworkModel(100.0, F0, buses, br, ms, ls; slack = :B1)
end

"""
    mesh(; loads = :constant_power) -> NetworkModel

Step 5's invented five-bus mesh (m8-context.md D8), lossy (R = X/10): three machines
with droop, two loads, seven lines rated 500 MVA, none of them a bridge.
"""
function mesh(; loads::Symbol = :constant_power)
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.05, 150.0, 0.05, 220.0, 0.5; V_set = 1.05),
          Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0, 0.04, 100.0, 0.4; V_set = 1.04),
          Machine(:G3, :E, 120.0, 3.5, 1.5, 0.25, 1.02, 40.0, 0.06, 45.0, 0.6; V_set = 1.02)]
    br = [Branch(id, f, t, x, 500.0; R = 0.1x) for (id, f, t, x) in
          ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15),
           (:BD, :B, :D, 0.25), (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10),
           (:BE, :B, :E, 0.20))]
    ls = [_zip(loads, :LB, :B, 130.0, 30.0), _zip(loads, :LD, :D, 120.0, 25.0)]
    return NetworkModel(100.0, F0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms, ls;
                        slack = :A)
end

const CASES = [("case9 (no line charging, invented droop)", case9),
               ("mesh (invented, step 5's fixture)", mesh)]

# ---------------------------------------------------------------------------
# Section 1: the D9 rule, checked on the numbers
# ---------------------------------------------------------------------------

"""
    rule_check(net) -> Vector{NamedTuple}

For every line the D9 rule maps to a generator: that generator's outage solved WITH the
line still in, read on the line. If losing the line really is losing the generator, the
line carries nothing at either end at either fidelity, and the bus it cuts off sits at
the voltage of the near end. `P`, `Q` pu; `ΔV` pu.
"""
function rule_check(net::NetworkModel)
    src = lone_source_bridges(net)
    dcg, acg = dc_generator_outages(net), ac_generator_outages(net)
    out = NamedTuple[]
    for (e, mid) in pairs(src.machine)
        mid === :none && continue
        k = findfirst(m -> m.id === mid, net.machines)
        b = net.branches[e]
        dc = isempty(dcg.flow[k]) ? NaN : abs(dcg.flow[k][e])
        sol = acg.solution[k]
        far = only(src.cut_off[e])
        near = b.from === far ? b.to : b.from
        ac = ΔV = NaN
        if sol !== nothing
            j = findfirst(==(b.id), sol.branches)
            ac = maximum(abs, (sol.flow[j], sol.flow_rev[j], sol.qflow[j], sol.qflow_rev[j]))
            ΔV = abs(sol.Vm[net.bus_index[far]] - sol.Vm[net.bus_index[near]])
        else
            # A voltage refusal keeps no solution, but it lists every bus out of band
            # with its |V|: if both ends are there, their voltages can still be compared.
            V = Dict(l.bus => l.Vm for l in acg.low[k])
            (haskey(V, far) && haskey(V, near)) && (ΔV = abs(V[far] - V[near]))
        end
        push!(out, (; line = b.id, machine = mid, cut_off = src.cut_off[e],
                    ac_outcome = acg.outcome[k], dc_flow = dc, ac_flow = ac, ΔV))
    end
    return out
end

# ---------------------------------------------------------------------------
# Section 2: the tables
# ---------------------------------------------------------------------------

_mw(x) = @sprintf("%.1f", x)

# Why the two fidelities say what they say, in one line built from the row's own data.
function why(s::OutageScreen, net::NetworkModel, r::Int)
    S = net.S_base
    rating(id) = net.branches[findfirst(b -> b.id === id, net.branches)].rating
    pos(id) = findfirst(b -> b.id === id, net.branches)
    parts = String[]
    s.via[r] === :none ||
        push!(parts, "= losing $(s.via[r]); $(join(s.cut_off[r], ", ")) cut off, not judged")
    c = s.class[r]
    if c === :splits
        push!(parts, "splits the grid: the cut-off side is not a lone generator")
    elseif c === :dc_blind
        o = s.ac_outcome[r]
        if o === :voltage
            push!(parts, "AC " * join([@sprintf("%s %.3f pu", l.bus, l.Vm) for l in s.low[r]], ", ") *
                         " (band 0.9–1.1); DC has no voltage")
        elseif o === :no_solution
            push!(parts, "AC finds no operating point ($(s.reason[r]))")
        else
            push!(parts, "AC: " * join([@sprintf("%s %s %.1f/%.0f MVA", d.kind, d.id, d.mva, d.rating)
                                        for d in s.ac_over[r] if d.kind !== :branch], ", "))
        end
    elseif c in (:dc_missed, :dc_false_alarm, :mixed)
        acmva = Dict(d.id => d.mva for d in s.ac_over[r] if d.kind === :branch)
        for id in sort(union(s.dc_over[r], collect(keys(acmva))))
            e = pos(id)
            dcmw = abs(s.dc_flow[r][e]) * S
            side = id in s.dc_over[r] ? (haskey(acmva, id) ? "both" : "DC only") : "AC only"
            split = isempty(s.reactive[r]) ? "" :
                    @sprintf(" (reactive +%.1f, real %+.1f)", s.reactive[r][e] * S, s.real[r][e] * S)
            push!(parts, @sprintf("%s %s: DC %.1f MW, AC %s MVA, rating %.0f%s", id, side, dcmw,
                                  haskey(acmva, id) ? _mw(acmva[id]) : "≤ rating", rating(id), split))
        end
    elseif c === :agree && s.ac_outcome[r] === :overload
        push!(parts, "both: " * join(s.dc_over[r], ", "))
    elseif c in (:refused, :refusals_differ)
        push!(parts, "DC $(s.dc_outcome[r]), AC $(s.ac_outcome[r])")
    end
    return join(parts, "; ")
end

# The largest loading on any branch after the outage, as a share of its rating, at each
# fidelity: the margin a "secure" verdict carries. AC read by branch id (D6).
function worst_loading(s::OutageScreen, net::NetworkModel, r::Int)
    dc = isempty(s.dc_flow[r]) ? NaN :
         maximum(abs(s.dc_flow[r][e]) * net.S_base / b.rating for (e, b) in pairs(net.branches))
    sol = s.kind[r] === :branch ? (s.via[r] === :none ? s.ac_lines.solution[r] :
                                   s.ac_generators.solution[findfirst(m -> m.id === s.via[r], net.machines)]) :
          s.ac_generators.solution[r - length(net.branches)]
    ac = NaN
    if sol !== nothing
        ac = 0.0
        for (j, id) in pairs(sol.branches)
            b = net.branches[findfirst(x -> x.id === id, net.branches)]
            S = max(hypot(sol.flow[j], sol.qflow[j]), hypot(sol.flow_rev[j], sol.qflow_rev[j]))
            ac = max(ac, S * net.S_base / b.rating)
        end
    end
    return dc, ac
end

_f(x, fmt) = isnan(x) ? "—" : Printf.format(Printf.Format(fmt), x)

function print_table(name, net::NetworkModel, s::OutageScreen)
    println("\n### $name")
    @printf("%-8s %-4s | %-9s %-11s | %-15s | %5s %5s | %7s %7s | %s\n",
            "lost", "", "DC", "AC", "class", "DC", "AC", "Δf DC", "Δf AC", "why")
    @printf("%-8s %-4s | %-9s %-11s | %-15s | %5s %5s | %7s %7s |\n",
            "", "", "", "", "", "max %", "max %", "Hz", "Hz")
    for r in eachindex(s.id)
        dcl, acl = worst_loading(s, net, r)
        @printf("%-8s %-4s | %-9s %-11s | %-15s | %5s %5s | %7s %7s | %s\n",
                s.id[r], s.kind[r] === :branch ? "line" : "gen", s.dc_outcome[r],
                s.ac_outcome[r], s.class[r], _f(100dcl, "%.0f"), _f(100acl, "%.0f"),
                _f(s.Δω_dc[r] * F0, "%.4f"), _f(s.Δω_ac[r] * F0, "%.4f"), why(s, net, r))
    end
end

screens() = [(name, loads, f(; loads)) for (name, f) in CASES
             for loads in (:constant_power, :default)]

function main()
    println("Single-outage screening (M8 step 6): every line and every generator, DC and AC")
    println("\n== 1. The D9 rule, checked: each mapped line, read in its generator's outage ==")
    for (name, f) in CASES, loads in (:constant_power, :default)
        rows = rule_check(f(; loads))
        if isempty(rows)
            println("  $name, $loads loads: no line cuts off a lone generator — the rule never fires")
            continue
        end
        for c in rows
            # A voltage refusal keeps no AC solution, so there is no AC line flow to
            # read; its |ΔV| comes from the refusal's own list of buses.
            @printf("  %s, %s loads: %s → %s (cuts off %s; AC %s)  |line flow| DC %.1e  AC %s pu   |ΔV| %.1e pu\n",
                    split(name)[1], loads, c.line, c.machine, join(c.cut_off, ","), c.ac_outcome,
                    c.dc_flow, isnan(c.ac_flow) ? "— (no solution kept)" : @sprintf("%.1e", c.ac_flow),
                    c.ΔV)
        end
    end
    println("\n== 2. The tables (max % = the most loaded branch against its rating; Δf = settled")
    println("   frequency deviation after a generator is lost; a voltage refusal has no AC flows) ==")
    for (name, loads, net) in screens()
        print_table("$name — $loads loads", net, outage_screen(net))
    end
    print_claims()
end

# Written AFTER the four tables were read, each asserted in `test/m8_outage_screen.jl`.
# The predictions made before the first run are in m8-context.md D9.
function print_claims()
    println("""

== 3. What the tables say (each asserted in test/m8_outage_screen.jl) ==

 a. The D9 rule decides three of case9's nine line outages — L14, L36 and L82, the
    lines its three generators hang on. Without it they would be "splits" with no
    answer. On the numbers the two outages are the same: each mapped line carries at
    most 1e-15 pu in its generator's outage, at both fidelities, and the bus it cuts
    off sits at its near end's voltage exactly. That includes losing G1, a voltage
    refusal, read through the refusal's own list of buses (and at 200 MW, where it
    solves). Leaving the dead bus out changes no verdict. The mesh has no such line.
 b. At the published ratings the DC screen passes every outage of both grids on both
    load models, and every disagreement is a voltage refusal it cannot express. On
    case9 that is G1 (and L14, the same event), L45 and L94 on constant-power loads; on
    the default loads L45 comes back inside the band and the other two stay out. Part
    of every case9 sag is the missing line charging.
 c. Where both screens say secure, DC still understates the most-loaded branch: by up
    to 8.2 points of its rating on case9 with constant-power loads (L78 out: 66.7 %
    against 74.9 %), and it never overstates there. On the default loads it errs both
    ways, −3.0 to +3.3 points, because the sagging voltage sheds load. On the mesh,
    under 2.1 points either way.
 d. "Secure" says nothing about frequency. Losing the mesh's G1 (150 MW) puts both
    remaining governors at their limit (45 MW of headroom between them); the other
    105 MW is carried by damping alone, and the frequency settles 10.94 Hz low in DC
    (11.22 / 11.06 Hz in AC). Both screens call it secure, because they judge line
    loading and voltage only. A real grid would have shed load long before.
 e. DC's settled frequency is not a bound in either direction. On constant-power loads
    AC's deviation is deeper in all six generator outages, by 0.6–16 % (losses rise and
    must be covered too; case9's G1: 0.401 against 0.463 Hz). On the default loads it is
    shallower in five of six, down to half (case9's G1: 0.195 Hz), and deeper only for
    the mesh's G1.
""")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
