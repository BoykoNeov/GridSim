# Low inertia, measured rather than assumed: M1's four units on a network, displaced
# step by step by inverters of each kind, with a unit tripped at every step.
#
#   julia --project=. scripts/low_inertia.jl
#
# Plan + decisions: docs/plans/m7-plan.md step 7, docs/plans/m7-context.md D15–D16.
#
# WHAT IS HELD FIXED, AND WHY THAT IS THE WHOLE DESIGN. Every row of every table starts
# from the SAME operating point. A displaced machine becomes an inverter at the same bus
# with the same rating and the same dispatch, where "the same dispatch" is read off the
# all-machine power flow rather than written down: a grid-forming inverter holds the
# bus voltage the machine left there, a grid-following one injects the P and Q the
# machine was injecting (`matched_dispatch`). So before the trip every bus voltage and
# every branch flow is identical across a sweep (`test/` asserts it), and whatever
# differs after the trip is the displacement and nothing else.
#
# WHAT IS NOT HELD FIXED, AND IS NOT INERTIA. Displacing a machine removes more than its
# rotor. It removes its governor reserve (a grid-following inverter here has no
# frequency response at all, `m7-context.md` D2), its voltage support (a grid-following
# inverter holds a current, not a voltage), and — for a grid-forming inverter — it ADDS
# a droop response with no current limit and no reserve ceiling (D8 names current
# limiting as the omission that matters most). So the columns that are not RoCoF₀ are
# reported beside the quantities that move them, and the claims at the bottom are
# written only after the tables, not before (M3 step 6's lesson).
#
# THE TWO EVENTS (D16, the user's choice): G1, the largest unit — 150 of 390 MW, 38 %
# of the generation in one step — and G4, the smallest, 60 MW, the unit M1 itself
# tripped for its "less inertia" lesson because there the governors have the reserve
# to cover it. Each sweep displaces the OTHER units smallest first, then the tripped
# unit itself, so the event is the same 150 (or 60) MW on every row until the last.
#
# THE LOADS ARE THE REPO'S DEFAULT (constant impedance, D16): they draw less as the
# voltage sags, which is what lets the grid-following sweep run at all, and M6 taught
# that a claim made only on a convenient load model is a claim about the load model.
# The price is that RoCoF₀ is no longer the closed form exactly — the voltage dip at
# t⁺ sheds some load — so both are printed. The EXACT check is section 1, on
# constant-power loads, against M1's own recorded number.

using GridSim
using Printf

# ---------------------------------------------------------------------------
# The fixture
# ---------------------------------------------------------------------------

const F0 = 50.0
const S_BASE = 100.0       # MVA. M1's example used 550 = the fleet's rating; RoCoF₀ is
                           # base-independent, and 100 keeps the reactances ordinary.
# M1's `example_system()` units, field for field (`src/model/system_model.jl`):
#           id    bus   S_rated  H    P0     Pmax
const UNITS = [(:G1, :B1, 200.0, 4.0, 150.0, 200.0),
               (:G2, :B2, 150.0, 3.5, 110.0, 150.0),
               (:G3, :B3, 100.0, 3.0,  70.0, 100.0),
               (:G4, :B4, 100.0, 2.5,  60.0, 100.0)]
const R_DROOP = 0.05       # M1's
const TG      = 8.0        # s, M1's
const D_MACH  = 1.5        # pu on the machine's own base: Σ D·S/S_base = 1.5 on M1's 550
                           # MVA base, i.e. M1's system damping, carried by the machines
const XD′     = 0.3        # pu, own base [CHOICE]
const E′      = 1.10       # pu [CHOICE] — scanned: at 1.05 the G1 trip leaves its own bus
                           # at 0.874 pu, below the tier's 0.9 band (D16)
const X_LINE  = 0.05       # pu on S_BASE [CHOICE]
const GEN_MW  = sum(u[5] for u in UNITS)          # 390 MW
const LOADS   = [(:D1, :L1, 150.0, 30.0), (:D2, :L2, 140.0, 28.0), (:D3, :L3, 100.0, 20.0)]

# Two layouts of the same seven buses. `:ring` is meshed — every unit has two paths to
# the load and B1–B4 are tied directly. `:chain` is the same buses strung in a line,
# B1 at one end, so the units are electrically far apart and the trip at an end has to
# be made up from the other end. The study is run on both because a result that holds
# on only one of them is a result about that layout (m7-plan.md step 7).
function _branches(topology::Symbol)
    X = X_LINE
    chain = [Branch(:a, :B1, :L1, X, 2000.0), Branch(:b, :L1, :B2, X, 2000.0),
             Branch(:c, :B2, :L2, X, 2000.0), Branch(:d, :L2, :B3, X, 2000.0),
             Branch(:e, :B3, :L3, X, 2000.0), Branch(:f, :L3, :B4, X, 2000.0)]
    topology === :chain && return chain
    topology === :ring && return vcat(chain, [Branch(:g, :B4, :B1, 1.6X, 2000.0),
                                              Branch(:h, :L1, :L3, 2X, 2000.0)])
    throw(ArgumentError("topology must be :ring or :chain, got :$topology"))
end

"""
    study_network(topology; kinds, match, loads = :default, τ_p = 0.1, slack) -> NetworkModel

The fixture with each unit in `kinds` (`id => :grid_forming | :grid_following`)
displaced by an inverter at the matched dispatch `match` (see `matched_dispatch`); every
other unit is M1's machine. `loads = :constant_power` is section 1's exact case.
"""
function study_network(topology::Symbol; kinds = Dict{Symbol,Symbol}(), match = nothing,
                       loads::Symbol = :default, τ_p::Real = 0.1, slack::Symbol = :B1)
    ms = Machine[]; is = Inverter[]
    for (id, bus, S, H, P, Pmax) in UNITS
        kind = get(kinds, id, :machine)
        if kind === :machine
            push!(ms, Machine(id, bus, S, H, D_MACH, XD′, E′, P, R_DROOP, Pmax, TG))
        elseif kind === :grid_forming
            push!(is, Inverter(id, bus, :grid_forming, S, P; V_set = match.V[bus], τ_p = τ_p))
        elseif kind === :grid_following
            push!(is, Inverter(id, bus, :grid_following, S, P; Q0 = match.Q[id]))
        else
            throw(ArgumentError("unit kind must be :machine, :grid_forming or :grid_following"))
        end
    end
    a_p = loads === :constant_power ? 1.0 : loads === :default ? 0.0 :
          throw(ArgumentError("loads must be :default or :constant_power"))
    ld = [Load(id, bus, P, Q, 1.0 - a_p, 0.0, a_p) for (id, bus, P, Q) in LOADS]
    buses = [Bus(b, 230.0) for b in (:B1, :B2, :B3, :B4, :L1, :L2, :L3)]
    return NetworkModel(S_BASE, F0, buses, _branches(topology), ms, ld;
                        inverters = is, slack = slack)
end

# The active and reactive power a bus exports into the network, read from the NETWORK
# side — the branch currents leaving it. Every unit bus here carries no load, so this is
# the unit's own output, measured without asking the unit.
function bus_export(eng, b::Int)
    u = eng.integrator.u
    bt = GridSim.branch_topology(eng.model)
    V(v) = complex(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]])
    I = 0.0im
    for e in eachindex(bt.src)
        st = eng.params[eng.status_pidx[e]]
        bt.src[e] == b && (I += st * (V(b) - V(bt.dst[e])) / (im * bt.X[e]))
        bt.dst[e] == b && (I += st * (V(b) - V(bt.src[e])) / (im * bt.X[e]))
    end
    return V(b) * conj(I)
end

"""
    matched_dispatch(topology; loads = :default) -> (; V, Q)

The all-machine operating point: each unit bus's voltage magnitude and each unit's
reactive output (MVAr). A grid-forming inverter holds that voltage, a grid-following one
injects that Q, both at the unit's P0 — so the displaced network solves to the same
point (asserted in `test/`, not assumed).
"""
function matched_dispatch(topology::Symbol; loads::Symbol = :default, slack::Symbol = :B1)
    net = study_network(topology; loads, slack)
    eng = init!(DetailedEngine, net)
    V = Dict(b.id => abs(complex(eng.integrator.u[eng.Vre_idx[i]], eng.integrator.u[eng.Vim_idx[i]]))
             for (i, b) in pairs(net.buses))
    Q = Dict(id => imag(bus_export(eng, net.bus_index[bus])) * S_BASE for (id, bus, _...) in UNITS)
    return (; V, Q)
end

# ---------------------------------------------------------------------------
# One cell: build, trip, run, read
# ---------------------------------------------------------------------------

const T_TRIP = 1.0
const T_END  = 30.0
const WINDOW = 0.5         # s — the report's RoCoF window, as everywhere in the repo
# The solver tolerance the TABLES run at. The engines default to 1e-3 (a real-time
# setting); a study prints three decimals of Hz, so it runs three orders tighter, and
# the one place two runs are compared after t⁺ (`test/`, rows 3 and 4) is shown to
# close as this tightens rather than banded.
const RELTOL = 1e-6
const ABSTOL = 1e-8

# The units other than the one tripped, smallest first, then the tripped unit last.
displacement_order(event::Symbol) =
    [[u[1] for u in sort(UNITS; by = u -> u[5]) if u[1] !== event]; event]

# The online inertia on S_BASE after the trip, BY FORMULA from the model data — the
# aggregate tier's view, never the engine's weights.
function _H_post(net::NetworkModel, event::Symbol)
    H = 0.0
    for m in net.machines
        m.id === event || (H += m.H * m.S_rated / net.S_base)
    end
    for i in net.inverters
        (i.id !== event && i.mode === :grid_forming) && (H += i.τ_p / (2i.K_p) * i.S_rated / net.S_base)
    end
    return H
end

# Why a cell did not run, in the fewest words that still say which wall it hit.
function _reason(err)
    msg = sprint(showerror, err)
    m = match(r"bus (\w+) solved to \|V\| = ([0-9.]+)", msg)
    m === nothing || return @sprintf("|V| %s = %.3f pu at t⁺, below the 0.9 band", m[1], parse(Float64, m[2]))
    occursin("no machine and no grid-forming", msg) && return "no voltage source would be left (D5)"
    occursin("no machines and no grid-forming", msg) && return "nothing to follow (D5)"
    occursin("fixpoint", msg) && return "the post-trip network has no solution"
    return first(replace(msg, '\n' => ' '), 70)
end

"""
    study_cell(topology, event, kind, n; loads, τ_p, T, keep = false) -> NamedTuple

Displace the first `n` units of `displacement_order(event)` by `kind`, trip `event` at
`T_TRIP`, run to `T`. `status` is `:ok` or `:refused` (with `reason`); a refused cell
carries `NaN` in every number rather than a value from a run that did not happen.

`keep = true` (M7 step 8, for the window that draws this study) adds one field,
`series` — the run's `state_series`, or `nothing` when there was no run — and changes
nothing else: the numbers are computed by the same lines from the same samples, so the
window's read-out and this table are one computation, not two.
"""
function study_cell(topology::Symbol, event::Symbol, kind::Symbol, n::Integer;
                    loads::Symbol = :default, τ_p::Real = 0.1, T::Real = T_END,
                    reltol::Real = RELTOL, abstol::Real = ABSTOL,
                    match = matched_dispatch(topology; loads, slack = _slack(event)),
                    keep::Bool = false)
    r = _study_cell(topology, event, kind, n; loads, τ_p, T, reltol, abstol, match)
    keep || return r.row
    return merge(r.row, (; series = r.eng === nothing ? nothing : state_series(r.eng)))
end

# The cell itself, returning the engine beside the row so `keep` can read the samples
# the row was computed from. A cell refused at construction or initialisation has no
# engine; one refused during the run keeps its engine, and `keep` draws what it recorded.
function _study_cell(topology::Symbol, event::Symbol, kind::Symbol, n::Integer;
                     loads, τ_p, T, reltol, abstol, match)
    order = displacement_order(event)
    kinds = Dict(id => kind for id in order[1:n])
    share = sum((u[5] for u in UNITS if u[1] in keys(kinds)); init = 0.0) / GEN_MW
    nan = (; topology, event, kind, n, share, status = :refused, reason = "",
           H_post = NaN, P_lost = NaN, rocof_cf = NaN, rocof_inst = NaN, rocof_coi = NaN,
           rocof_pll = NaN, nadir = NaN, f_end = NaN, V_min = NaN, reserve = NaN,
           binds = false, gfm_peak = NaN, synchronous = false, falling = false,
           relief = NaN, ΔP_gfl = NaN, imbalance = NaN, V_pre = Float64[])
    net = try
        study_network(topology; kinds, match, loads, τ_p, slack = _slack(event))
    catch err
        return (; row = merge(nan, (; reason = _reason(err))), eng = nothing)
    end
    eng = try
        init!(DetailedEngine, net; reltol, abstol, meters = [PLLMeter(b.id) for b in net.buses])
    catch err
        return (; row = merge(nan, (; reason = _reason(err))), eng = nothing)
    end
    V_pre = copy(current_state(eng).V)
    try
        solve!(eng, (0.0, T_TRIP))
        b = net.bus_index[Dict(u[1] => u[2] for u in UNITS)[event]]
        P_lost = real(bus_export(eng, b))
        H_post = _H_post(net, event)
        gfl = [net.bus_index[i.bus] for i in net.inverters
               if i.mode === :grid_following && i.id !== event]
        load⁻, gfl⁻ = load_power(eng, net), sum((real(bus_export(eng, v)) for v in gfl); init = 0.0)
        inject!(eng, TripGenerator(event))
        rocof_inst = coi_rocof(eng)
        load⁺, gfl⁺ = load_power(eng, net), sum((real(bus_export(eng, v)) for v in gfl); init = 0.0)
        acct = (; relief = load⁻ - load⁺, ΔP_gfl = gfl⁺ - gfl⁻,
                imbalance = rocof_inst * 2 * H_post / F0)
        solve!(eng, (T_TRIP, Float64(T)))
        return (; row = merge(nan, _read(eng, net, event, P_lost, H_post, rocof_inst), acct,
                              (; V_pre)), eng)
    catch err
        return (; row = merge(nan, (; reason = _reason(err), V_pre)), eng)
    end
end

"""
    load_power(eng, net) -> Float64

The active power every load draws right now, pu, from its bus voltage and its own ZIP
law (`P₀·|V|²·k(|V|)`, the law `_load_current` integrates). With the default
constant-impedance loads this is `Σ P₀·|V|²`, so a voltage dip at t⁺ SHEDS load — the
term that separates the network's RoCoF₀ from the closed form on default loads.
"""
function load_power(eng, net)
    la = load_arrays(net)
    u = eng.integrator.u
    P = 0.0
    for k in eachindex(la.bus)
        v = la.bus[k]
        Vm = hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]])
        kz = (la.a_i[k] == 0.0 && la.a_p[k] == 0.0) ? 1.0 : GridSim._zip_k(Vm, la.a_i[k], la.a_p[k])
        P += la.P[k] * Vm^2 * kz
    end
    return P
end

# The reference bus is the TRIPPED unit's: it stays a machine or a grid-forming
# inverter on every row but the last (where it is displaced itself), and a reference
# bus must hold a voltage.
_slack(event::Symbol) = Dict(u[1] => u[2] for u in UNITS)[event]

function _read(eng, net, event, P_lost, H_post, rocof_inst)
    s = state_series(eng)
    post = findall(>=(T_TRIP), s.t)
    r = rocof_readouts(eng; window = WINDOW)
    coi = filter(!isnan, r.coi[post])
    pll = [maximum(abs, filter(!isnan, getfield(r.pll, c)[post]))
           for c in keys(r.pll) if startswith(String(c), "ωmeter_")]
    Vmin = minimum(minimum(getfield(s, Symbol("V_", b.id))[post]) for b in net.buses)
    # Governor reserve still online after the trip, and whether any of it is used up
    # at the end of the run (`ΔPm` at its ceiling). Grid-forming droop has NO ceiling
    # in this model (D8), so it is not reserve and is not counted here.
    ma = machine_arrays(net)
    cs = current_state(eng)
    online = [k for (k, m) in pairs(net.machines) if m.id !== event]
    reserve = sum((ma.headroom[k] for k in online); init = 0.0) * net.S_base
    binds = any(cs.ΔPm[k] >= ma.headroom[k] - 1e-6 for k in online)
    # The grid-forming inverters' peak apparent power against their rating, off every
    # saved state: the number that says how far the missing current limit is from
    # mattering (D8).
    g = eng.gfm
    ia = GridSim._inverter_arrays(net)       # same (bus) order as `eng.gfm`, system base
    gfm_peak = any(!=(event), g.ids) ? 0.0 : NaN
    for u in eng.integrator.sol.u, j in eachindex(g.ids)
        g.ids[j] === event && continue
        vb = g.bus[j]
        _, _, P, Q = GridSim._gfm_current(u[eng.Vre_idx[vb]], u[eng.Vim_idx[vb]], u[g.δ_idx[j]],
                                          GridSim._gfm_E(eng, u, j), ia.X_c[j])
        gfm_peak = max(gfm_peak, hypot(P, Q) / ia.S[j])
    end
    # Synchronous: every online source's frequency back on the centre of inertia at the
    # end, and no online angle more than π from the centre of inertia at any sample.
    spread_end = 0.0; δmax = 0.0
    for id in [[m.id for m in net.machines]; [i.id for i in net.inverters if i.mode === :grid_forming]]
        id === event && continue
        spread_end = max(spread_end, abs(getfield(s, Symbol("ω_", id))[end] -
                                         (s.f_coi[end] / F0 - 1)))
        δmax = max(δmax, maximum(abs, getfield(s, Symbol("δ_", id))[post] .- s.δ_coi[post]))
    end
    # A frequency still FALLING when the run ends has no nadir yet — flagged, and printed
    # as "≤", rather than presented as the bottom of a dip. Judged by the slope over the
    # last second, NOT by "the minimum is the last sample": a monotone approach to a
    # settled value also ends on its minimum, and the first version of this flag called
    # that "still falling" (the big-trip grid-following cell, which in fact sits within
    # 3 mHz of its 240 s value at 30 s — m7-context.md D16).
    f = s.f_coi[post]
    k_end = findfirst(>=(s.t[end] - 1.0), s.t[post])
    falling = (f[end] - f[k_end]) < -1e-3
    return (; status = :ok, H_post, P_lost, rocof_cf = -F0 * P_lost / (2 * H_post), rocof_inst,
            rocof_coi = maximum(abs, coi; init = 0.0), rocof_pll = maximum(pll; init = 0.0),
            nadir = minimum(f), f_end = s.f_coi[end], V_min = Vmin, falling,
            reserve, binds, gfm_peak, synchronous = spread_end < 1e-4 && δmax < π)
end

"""
    sweep(topology, event; kinds = (:grid_following, :grid_forming), τ_p = 0.1, loads, T)

Every row of one table: the all-machine row once, then `n = 1…4` for each kind.
"""
function sweep(topology::Symbol, event::Symbol;
               kinds = (:grid_following, :grid_forming), τ_p::Real = 0.1,
               loads::Symbol = :default, T::Real = T_END)
    match = matched_dispatch(topology; loads, slack = _slack(event))
    rows = [study_cell(topology, event, :machine, 0; loads, T, match)]
    for kind in kinds, n in 1:length(UNITS)
        push!(rows, study_cell(topology, event, kind, n; loads, τ_p, T, match))
    end
    return rows
end

# ---------------------------------------------------------------------------
# Printing
# ---------------------------------------------------------------------------

_f(x, fmt) = isnan(x) ? "—" : Printf.format(Printf.Format(fmt), x)

function print_table(rows)
    r0 = rows[1]
    println("\n### $(r0.topology), trip $(r0.event) ($(Int(Dict(u[1] => u[5] for u in UNITS)[r0.event])) MW)")
    @printf("%-15s %2s %5s | %6s | %7s %7s | %6s %6s | %6s %6s | %8s %7s | %5s | %5s %5s | %5s | %s\n",
            "displaced by", "n", "share", "H_post", "RoCoF₀", "RoCoF₀", "COI", "PLL",
            "relief", "ΔP_gfl", "nadir", "f(30s)", "min V", "resv", "binds", "GFM", "sync")
    @printf("%-15s %2s %5s | %6s | %7s %7s | %6s %6s | %6s %6s | %8s %7s | %5s | %5s %5s | %5s |\n",
            "", "", "%", "s", "formula", "network", "500ms", "500ms", "MW", "MW", "Hz", "Hz",
            "pu", "MW", "", "S/Sr")
    for r in rows
        if r.status !== :ok
            @printf("%-15s %2d %5.1f | refused: %s\n", r.kind, r.n, 100r.share, r.reason)
            continue
        end
        nadir = r.falling ? @sprintf("≤%.3f", r.nadir) : @sprintf("%.3f", r.nadir)
        @printf("%-15s %2d %5.1f | %6.2f | %7.3f %7.3f | %6.3f %6s | %6.1f %6.1f | %8s %7.3f | %5.3f | %5s %5s | %5s | %s\n",
                r.kind, r.n, 100r.share, r.H_post, r.rocof_cf, r.rocof_inst, r.rocof_coi,
                _f(r.rocof_pll, "%.2f"), r.relief * S_BASE, r.ΔP_gfl * S_BASE, nadir, r.f_end,
                r.V_min, _f(r.reserve, "%.0f"), r.binds ? "yes" : "no", _f(r.gfm_peak, "%.2f"),
                r.synchronous ? "yes" : "NO")
    end
    any(r -> r.status === :ok && r.falling, rows) &&
        println("  ≤ : still falling when the run ends at 30 s — the bottom is lower, not shown")
end

"""
    m1_control() -> Vector{NamedTuple}

Section 1, the positive control: at zero share, on CONSTANT-POWER loads (where the
closed form is exact), the network's instantaneous centre-of-inertia RoCoF at t⁺ against
the number M1's own engine reports for the same trip of `example_system()`.
"""
function m1_control(; topologies = (:ring, :chain))
    out = NamedTuple[]
    for topology in topologies, event in (:G1, :G4)
        fr = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        inject!(fr, TripGenerator(event))
        m1 = current_state(fr).RoCoF
        r = study_cell(topology, event, :machine, 0; loads = :constant_power, T = T_TRIP + 0.1)
        push!(out, (; topology, event, m1, network = r.rocof_inst, gap = r.rocof_inst - m1))
    end
    return out
end

function main()
    println("Low inertia (M7 step 7): M1's four units on a network, displaced by inverters")
    println("\n== 1. Positive control: zero share, constant-power loads, against M1 ==")
    for c in m1_control()
        @printf("  %-6s trip %s:  M1 %.12f Hz/s   network t⁺ %.12f   gap %.1e\n",
                c.topology, c.event, c.m1, c.network, c.gap)
    end
    println("\n== 2. The sweeps (default loads; RoCoF in Hz/s; the PLL column includes the trip's")
    println("   own phase-jump spike, Hurdle 10 — a relay reads it, no rotor moved) ==")
    for topology in (:ring, :chain), event in (:G1, :G4)
        print_table(sweep(topology, event))
    end
    println("\n== 3. Anti-vacuity: grid-forming with τ_p → 0.001 s (virtual inertia ≈ 0) ==")
    for topology in (:ring, :chain), event in (:G1, :G4)
        print_table(sweep(topology, event; kinds = (:grid_forming,), τ_p = 0.001))
    end
    print_claims()
end

# Written AFTER both layouts' tables were read, and each one asserted in
# `test/m7_low_inertia.jl`. Three drafted before the accounting columns existed did not
# survive them (m7-context.md D16, "What the study measured").
function print_claims()
    println("""

== 4. What the tables say — on BOTH layouts, both events (each asserted in test/) ==

 a. The formula RoCoF₀ steepens with every displacement, by exactly the inertia that
    left — but on the default loads the NETWORK RoCoF₀ ranks the two kinds the other
    way round. Grid-following gives no voltage support, the dip at t⁺ is deeper, and
    more constant-impedance load sheds itself (relief column), so its instantaneous
    RoCoF₀ comes out SHALLOWER than grid-forming's at the same share, and on the
    chain one grid-following swap reads shallower than no inverters at all. The
    accounting is exact: Σ2Hω̇ = −P_lost + relief + ΔP_gfl at t⁺, every term read
    from bus voltages.
 b. The nadir moves the opposite way to RoCoF₀ under grid-forming displacement: it
    is SHALLOWER at every share, while RoCoF₀ steepens. That benefit is the droop,
    not the virtual inertia — with τ_p → 0 the nadir moves by < 0.05 Hz while RoCoF₀
    explodes. It is measured with NO CURRENT LIMIT (D8): most grid-forming rows run
    above their rating (1.26–1.63× on the big trip), and the clean evidence is the
    ring's small-trip row that stays within it (0.97×).
 c. The 500 ms windowed RoCoF a relay reads barely follows RoCoF₀ under grid-forming
    displacement: from no inverter to no machine left, RoCoF₀ steepens 3.8–4.7×
    while the windowed reading changes by −19 % to +3 % (and not monotonically).
    Removing the virtual inertia raises it by 5–15 % where machines remain, and by
    about 1 % once none do.
 d. Grid-following displacement deepens the nadir in every cell that ran, and on the
    big trip it stops being a frequency question at a third of the generation: the
    voltage at t⁺ leaves the band on both layouts. At one swap the reserve is gone and
    the frequency sinks with NO recovery to 44.30 Hz (ring) / 44.66 Hz (chain) —
    measured at 240 s, and already within 3 mHz of it at 30 s.
 e. The layout matters most to VOLTAGE: at 46 % grid-following share on the small
    trip the ring holds 0.963 pu and the chain falls below 0.9 (0.899 at t⁺ — a
    refusal that sits on the band edge, so the robust statement is the gap, not the
    refusal). On the chain the PLL meters read up to twice the centre-of-inertia
    RoCoF over the same window. Where that excess comes from — the trip's own phase
    jump, or a machine's own swing at its bus (step 6 measured both) — is not
    separated here.
""")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
