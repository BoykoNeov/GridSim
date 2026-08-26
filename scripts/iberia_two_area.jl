# The 28 April 2025 Iberian separation as a TWO-AREA classical model, with the
# parameter sweep that is this script's actual result.
#
#   julia --project=. scripts/iberia_two_area.jl
#
# Data + page citations: docs/scenarios/iberia-2025-04-28.md
# Plan + fidelity boundary: docs/plans/entsoe-iberia-reproduction.md §7
# Decisions behind the numbers: docs/plans/m3-context.md D7–D10, D12
#
# WHAT THIS IS FOR. `iberia_2025_04_28.jl` runs the same event on the aggregate
# centre-of-inertia tier, where Iberia is the whole world. That model is faithful
# only to ~12:33:19.6 and then RECOVERS where reality collapsed, because it has no
# state for the loss of synchronism with Continental Europe. This script adds the
# one missing mechanism: a second area, a rotor angle, and a NONLINEAR tie whose
# transfer `K·sin(δ_IB − δ_CE)` peaks at 90°, falls while the angle keeps growing,
# and reverses past 180°. That reversal is the report's export swing.
#
# WHAT COUNTS AS THE RESULT — READ THIS BEFORE QUOTING ANY NUMBER BELOW. Section 3
# prints a single cell of a grid, and single cells are exactly how the throwaway
# probe this replaces went wrong: its tie strength was tuned until the peninsula
# slipped, and three of its printed numbers were artefacts of that tuning
# (`entsoe-iberia-reproduction.md` §7.3, `m3-context.md` D10). The result is
# section 4 — what survives the whole sweep — and every section-3 number is
# labelled as one cell of it. A number that does not survive section 4 is not a
# finding here, however well it agrees with the report.

using GridSim
using Printf

# ---------------------------------------------------------------------------
# 1. Provenance. [FACT] is stated in the report; [DERIVED] is arithmetic on
#    report figures and is done in code below so it can be checked; [CHOICE] is
#    a modelling decision; [GUESS] is plausible and unsupported.
# ---------------------------------------------------------------------------

const S_BASE = 10_000.0   # MVA — ONE system base, fixed (m3-context.md D8) [CHOICE]
const F0     = 50.0       # Hz [FACT]

# --- Iberia ---
const KE_IB = 119_474.0   # MWs — Iberian kinetic energy at 12:30 (Table 2-4, p.36) [FACT]
const H_IB  = 2.46        # s   — midpoint of the report's 2.21–2.71 band [CHOICE]
# --- Continental Europe ---
const KE_CE = 800_000.0   # MWs — the rest of the synchronous area [GUESS]
const H_CE  = 3.0         # s   [GUESS]

const D_MACH = 1.5        # pu/pu on the machine's own base [CHOICE] — SPEC §7.2 "typical 1–2"
const R_DROOP = 0.05      # pu on the machine's own base [CHOICE] — standard 5 % droop
const TG      = 8.0       # s   — aggregate governor/turbine lag [CHOICE]

# UP-RESERVE, and it is load-bearing rather than decorative. `Pmax` on an area
# machine is a NET-INJECTION ceiling, not a fleet nameplate (D4): with 5 % droop on
# a 48,567 MVA base the governor would command ~19 GW at −1 Hz, so what the area
# actually delivers is set by this number and not by `R`. Continental Europe's
# frequency containment reserve is 3,000 MW for the whole synchronous area; Iberia's
# share is roughly its share of demand (~25 GW of ~300 GW), i.e. a few hundred MW.
# Both figures are [CHOICE], and section 3 reports whether the run saturates them —
# it does, within the first second, which is the physically interesting part.
const RESERVE_IB = 500.0    # MW [CHOICE]
const RESERVE_CE = 2_500.0  # MW [CHOICE]

# PRE-EVENT AC TIE FLOW, and this is the one parameter two prior sources disagree
# about. `m3-context.md` D8 says −1,000 MW, "net import over the tie". The probe in
# `entsoe-iberia-reproduction.md` §7.3(d) computes its export swing as
# `P_max − 1,000 = 2,500`, i.e. it had Iberia EXPORTING 1,000 MW. The report as
# extracted states neither: §1.2 gives only the CHANGE (ES–FR active power fell by
# ≈1,500 MW between 12:32:00 and 12:33:00, p.120) and the HVDC's constant
# 2 × 500 MW Spain→France. Since the HVDC was in constant-power mode its share did
# not move, so the whole ≈1,500 MW fall landed on the AC corridor — which is what
# makes an importing peninsula at cascade onset the defensible reading. It is a
# [CHOICE], it is swept in section 4, and section 5 shows the headline conclusion
# TURNS ON IT.
const P_TIE0 = -1_000.0   # MW, Iberia's net injection into the AC tie (negative = importing)

# Nominal tie strength. NOT a fact: `P_max` is a fitted parameter with a plausible
# range (§7.5), and this value is the sweep's centre, not a result.
const P_MAX_NOMINAL = 3_500.0   # MW [CHOICE]

# t = 0 is 12:33:16.460 CEST — cluster 4a, the first event of the fast cascade.
const T0_CEST = 16.460          # seconds past 12:33:00
cest(t::Real) = @sprintf("12:33:%06.3f", T0_CEST + t)

# ---------------------------------------------------------------------------
# 2. The cascade magnitude, RE-DERIVED from Table 3-1. This is a checklist item
#    in its own right (m3-tasks.md step 6) because the document this script
#    replaces quotes two figures for the same quantity that differ by 1.9×.
#    The arithmetic runs here rather than being quoted, so it can be checked.
# ---------------------------------------------------------------------------

# Generation loss by cluster, from Table 3-1 (pp.103–105) as extracted in
# docs/scenarios/iberia-2025-04-28.md §2. Cluster 1 (+317.3 MW) is a net LOAD
# RISE, not generation loss, and is deliberately absent — see PRE_EVENT below.
const CLUSTERS_PRE = [            # complete by 12:32:57.220, ~19 s before the cascade
    (:c2, 208.0),                 # 2a/2b, many small wind/PV trips
    (:c3, 355.0),                 # Granada 400/220 kV transformer
]
const CLUSTERS_CASCADE = [        # 12:33:16.460 onward — what the ramp carries
    (:c4a, 582.0), (:c4b, 145.0),
    (:c5,  930.0),                # report notes frequency implies up to 1,100 MW
    (:c6,  650.0),
    (:c7_13, 2_600.0),            # stated as a FLOOR (≥) in the report, p.116
]

const REPORT_CUMULATIVE_2056 = 5_750.0   # MW in SPAIN by 12:33:20.560 (p.119) [FACT]
const REPORT_CUMULATIVE_1802 = 2_500.0   # MW, ">2.5 GW" by 12:33:18.020 (p.11) [FACT], a floor

gen_pre()     = sum(v for (_, v) in CLUSTERS_PRE)
gen_cascade_floor() = sum(v for (_, v) in CLUSTERS_CASCADE)

# THE NUMBER THE RAMP CARRIES. Two independent routes, and the difference between
# them is the honest uncertainty:
#
#   top-down  — the report's own cumulative for Spain at 12:33:20.560, MINUS the
#               generation already lost before the cascade began. Using the 5,750
#               unreduced (which is what §7.3 of the doc being replaced did) counts
#               the 563 MW of clusters 2 and 3 twice: they are 19 s in the past at
#               t = 0 and are in the initial condition, not in the ramp.
#   bottom-up — Table 3-1's own cascade clusters, summed. A FLOOR, because the
#               7–13 row is stated as ≥2,600 MW.
#
# `rate·duration` uses the top-down figure. The floor is what corroborates it, and
# the gap between them is quoted rather than hidden.
cascade_magnitude() = REPORT_CUMULATIVE_2056 - gen_pre()   # 5,187 MW [DERIVED]

# THE DURATION. 12:33:16.460 (cluster 4a) → 12:33:20.560 (the report's own
# cumulative checkpoint, and the instant |RoCoF| first reached 1 Hz/s, p.116).
const CASCADE_END_CEST = 20.560
cascade_duration() = CASCADE_END_CEST - T0_CEST            # 4.100 s [DERIVED]

# The two figures this replaces, kept so the sweep CONTAINS them as labelled cells
# rather than merely contradicting them in prose.
const MAG_OLD_UNSOURCED = 2_773.0   # §7.4's sweep centre, labelled "(report)"
const MAG_OLD_CUMULATIVE = 5_750.0  # §7.3's probe parameter, the un-reduced cumulative

"""
    print_derivation()

The Table 3-1 arithmetic, printed. This is section 2 of the output and is the
answer to "where does the ramp magnitude come from", which the document being
replaced could not answer for either of the two figures it carried.
"""
function print_derivation()
    println("2. Cascade magnitude, re-derived from Table 3-1 (NOT inherited)\n")
    pre, floor_ = gen_pre(), gen_cascade_floor()
    @printf("  generation lost BEFORE the cascade (clusters 2, 3)      %8.0f MW\n", pre)
    @printf("  Table 3-1 cascade clusters 4a…13, summed (a FLOOR)      %8.0f MW\n", floor_)
    @printf("  report cumulative for Spain at 12:33:20.560 (p.119)     %8.0f MW\n",
            REPORT_CUMULATIVE_2056)
    println()
    @printf("  bottom-up cumulative at 12:33:18.020  %6.0f MW   report says >%.0f (p.11)\n",
            pre + 582 + 145 + 930, REPORT_CUMULATIVE_1802)
    @printf("  bottom-up cumulative at ~12:33:20     %6.0f MW   report says ~%.0f (p.119)\n",
            pre + floor_, REPORT_CUMULATIVE_2056)
    println()
    @printf("  => ramp magnitude, top-down (%.0f - %.0f)        %8.0f MW  [DERIVED, used]\n",
            REPORT_CUMULATIVE_2056, pre, cascade_magnitude())
    @printf("     ramp magnitude, bottom-up floor            %8.0f MW  [DERIVED, corroborates]\n",
            floor_)
    @printf("     ramp duration (12:33:%06.3f -> %06.3f)      %8.3f s   [DERIVED]\n",
            T0_CEST, CASCADE_END_CEST, cascade_duration())
    note("",
         "Both routes are consistent: the bottom-up sum is $(round(Int, cascade_magnitude()-floor_)) MW short of the",
         "top-down figure, and the 7–13 row it rests on is stated as a floor (>=2,600 MW),",
         "so the shortfall sits inside the report's own >=. Table 3-1 also undercounts the",
         "report's cumulative at the EARLIER checkpoint, which the report explains itself:",
         "generation below 1 MW has no real-time reporting obligation, so the itemisation",
         "is a lower bound by construction (report §5, and p.102 fn.24).",
         "",
         "WHAT THE NUMBER IS. Generation LOST, not apparent imbalance. Those are different",
         "quantities in this event and differ by more than the correction above: at the",
         "moment -1 Hz/s was reached the Iberian imbalance was >=6,150 MW, of which ~5,000 MW",
         "was the export swing from loss of synchronism (p.116-119). Feeding 6,150 MW into",
         "the ramp would double-count the swing, because THIS MODEL PRODUCES THE SWING",
         "ITSELF - it is the whole reason the second area exists.",
         "",
         "SCOPE BOUNDARY, stated rather than repeated. The 5,750 MW is 'in Spain' (p.119)",
         "and every Table 3-1 cluster above is a Spanish site, but the machine below is",
         "IBERIA, keyed off the Iberian kinetic energy. Portuguese generation loss in the",
         "same window is not in the table and is therefore not in the ramp.",
         "",
         "THE TWO FIGURES THIS REPLACES, and neither is used:",
         "  5,750 MW - the report's cumulative used unreduced, which double-counts the",
         "             $(round(Int,pre)) MW of clusters 2 and 3 that were already gone at t = 0.",
         "  2,773 MW - reconstructs from NOTHING in Table 3-1 by any grouping. The old",
         "             sweep's +/-30 % cells (1,941 / 3,605) are simply +/-30 % of it, so the",
         "             whole magnitude axis of that sweep was centred on an unsourced",
         "             number 1.87x too small. Both appear as labelled cells in section 4.")
end

# ---------------------------------------------------------------------------
# 3. The model. Two machines, one tie.
# ---------------------------------------------------------------------------

"""
    two_area_model(; P_max_mw, KE_ce, P_tie0_mw, …) -> NetworkModel

Iberia and Continental Europe as two machines on one nonlinear tie.

`P_max_mw` is the tie's maximum transfer, and it enters as **the reactance it
is** (D9): with `E′ = 1.0` at both ends and `K` in pu on the system base,
`K = E′₁E′₂/X`, so `X = S_base/P_max`. Saying this out loud is not pedantry —
sweeping `P_max` while thinking of it as a rating quietly becomes a sweep over
something else.

Both machines are rated **away** from `S_base` (48.6 GVA and 266.7 GVA against a
10 GVA base) on purpose: M2 established that a rating equal to the base hides a
missing or inverted per-unit conversion behind a weight of 1. The check that this
conversion is right is that `machine_arrays(net).H` comes out as `KE/S_base`
exactly, which section 3 prints.

**What is folded into `P0` rather than modelled.** `P0` here is the pre-event AC
exchange with Continental Europe and nothing else. The 2 × 500 MW HVDC was in
constant-power mode, so it is a fixed, **angle-independent** injection: −1,000 MW
inside Iberia's net injection and +1,000 MW inside CE's. That is not an
approximation of the HVDC, it *is* the HVDC in constant-power mode, and it is why
this model demonstrates rather than asserts that the link gave no frequency
support. The ES–MA export (≈2,100 MW) and the internal ES–PT flow (≈750 MW) are
likewise inside the machines' net injections; Morocco is a third area this tier
does not carry, and its 12:33:20.473 underfrequency trip is out of scope.
"""
function two_area_model(; P_max_mw::Real = P_MAX_NOMINAL,
                          KE_ce::Real = KE_CE,
                          P_tie0_mw::Real = P_TIE0,
                          reserve_ib::Real = RESERVE_IB,
                          reserve_ce::Real = RESERVE_CE,
                          R::Real = R_DROOP, Tg::Real = TG, D::Real = D_MACH,
                          h_ib::Real = H_IB, h_ce::Real = H_CE)
    S_ib = KE_IB / h_ib          # MVA — the machine's own base follows from its KE
    S_ce = KE_ce / h_ce
    X    = S_BASE / P_max_mw     # pu on S_base, with E′ = 1.0 at both ends (D9)
    buses = [Bus(:ES, 400.0), Bus(:FR, 400.0)]
    machines = [
        # `Xd′` is carried and unused by this tier (see network_model.jl); 0.30 pu
        # is a plausible machine value and changes nothing here.
        Machine(:IB, :ES, S_ib, h_ib, D, 0.30, 1.0,  P_tie0_mw,
                R,  P_tie0_mw + reserve_ib, Tg),
        Machine(:CE, :FR, S_ce, h_ce, D, 0.30, 1.0, -P_tie0_mw,
                R, -P_tie0_mw + reserve_ce, Tg),
    ]
    branches = [Branch(:TIE, :ES, :FR, X, P_max_mw)]
    return NetworkModel(S_BASE, F0, buses, branches, machines)
end

# The defence plan as it actually fired, from report Fig 3-67 (p.178), ES + PT
# aggregated per threshold — the same table `iberia_2025_04_28.jl` uses, and for the
# same reason (pump-storage disconnection and low-frequency demand disconnection
# both remove LOAD, so both are one mechanism on this tier). Bound to :IB, because
# a defence plan fires on ITS OWN area's frequency and not on an inertia-weighted
# average of Iberia and Continental Europe (D5) — a distinction that is the whole
# point once the two are separating.
const SHED_MW = [
    (49.8,  381.0, :PT_pump_49_8),   (49.7,  450.0, :PT_pump_49_7),
    (49.6,  438.0, :PT_pump_49_6),   (49.5, 2638.0, :ESPT_pump_49_5),
    (49.3,  947.0, :ESPT_pump_49_3), (49.2,  218.0, :PT_industrial_49_2),
    (49.0, 1491.0, :ESPT_lfdd_49_0), (48.8, 1962.0, :ESPT_lfdd_48_8),
    (48.6, 1890.0, :ESPT_lfdd_48_6), (48.4, 1847.0, :ESPT_lfdd_48_4),
    (48.2, 1576.0, :ESPT_lfdd_48_2), (48.0, 1694.0, :ESPT_lfdd_48_0),
]
defence_plan() = [LoadShedStage(hz, mw / S_BASE; label = lab) for (hz, mw, lab) in SHED_MW]

# ---------------------------------------------------------------------------
# 4. Running one cell.
# ---------------------------------------------------------------------------

# The run window, fixed. Every long run in this repo self-terminates on a step
# count and never on a condition (m3-tasks.md, known hazards). 20 s past cascade
# onset is 12:33:36 — nine seconds past the blackout, so a cell that has not lost
# synchronism by then did not lose it in this event.
const TEND = 20.0
const DT   = 0.01

"""
    run_cell(; …) -> NamedTuple

One cell of the sweep: build the model, arm the cascade ramp, step it to `TEND`,
and return the gauge-free measurements.

  - `slipped`  — did `|δ_IB − δ_CE|` pass **π**? Not π/2: passing 90° is a
                 first-swing excursion a system can recover from (M3 step 4 measured
                 exactly that on a healthy tie), whereas past 180° the synchronising
                 power has reversed and a system still in deficit cannot come back.
                 `n_pole_slips` is the corroboration that it really ran away.
  - `t90`      — the instant `|δ|` first reaches π/2, linearly interpolated between
                 samples. This is the quantity comparable to the report's
                 "12:33:19.62 — Iberian Peninsula loses synchronism".
  - `swing`    — peak tie export minus the pre-event flow (MW), the quantity
                 §7.3(d) reasons about.

Everything returned is **gauge-free** (angle differences, speeds, powers, times).
Each cell rebuilds the model and therefore draws its own arbitrary angle gauge
from `find_fixpoint`, so an absolute `δ` is not comparable across cells and none
is returned.
"""
function run_cell(; P_max_mw::Real = P_MAX_NOMINAL, KE_ce::Real = KE_CE,
                    P_tie0_mw::Real = P_TIE0,
                    magnitude_mw::Real = cascade_magnitude(),
                    duration_s::Real = cascade_duration(),
                    shed::Bool = false, tend::Real = TEND, dt::Real = DT,
                    kwargs...)
    net = two_area_model(; P_max_mw = P_max_mw, KE_ce = KE_ce,
                           P_tie0_mw = P_tie0_mw, kwargs...)
    K   = branch_arrays(net).K[1]
    ramp = GenerationRamp(-magnitude_mw / S_BASE / duration_s, 0.0, Float64(duration_s))
    stages = shed ? [:IB => defence_plan()] : Pair{Symbol,Vector{LoadShedStage}}[]
    eng = SwingEngine(net; dt = dt, ramp = [:IB => ramp], shed = stages)

    n = round(Int, tend / dt)
    t90 = NaN; slipped = false; prev = abs(_gap(eng)); dmax = prev
    f_ib_min = F0; f_ce_min = F0; peak_export = -Inf; ΔPm_max = 0.0
    for _ in 1:n
        s = step!(eng)
        d = abs(s.δ[1] - s.δ[2])
        dmax = max(dmax, d)
        # Linear interpolation between the two bracketing samples. The dt-grid alone
        # would quantise this to 10 ms, which is the same order as the difference
        # between cells the sweep is trying to resolve.
        if isnan(t90) && d >= π/2 && d > prev
            t90 = s.t - dt * (d - π/2) / (d - prev)
        end
        d >= π && (slipped = true)
        prev = d
        f_ib_min = min(f_ib_min, eng.f0 * (1 + s.ω[1]))
        f_ce_min = min(f_ce_min, eng.f0 * (1 + s.ω[2]))
        peak_export = max(peak_export, K * sin(s.δ[1] - s.δ[2]) * S_BASE)
        ΔPm_max = max(ΔPm_max, s.ΔPm[1])
    end
    hr = machine_arrays(net).headroom[1]
    return (; eng, net, slipped, t90, dmax,
            n_pole_slips = floor(Int, dmax / 2π),
            f_ib_min, f_ce_min, peak_export,
            swing = peak_export - P_tie0_mw,
            ΔPm_max, headroom = hr, saturated = ΔPm_max >= hr - 1e-9,
            ramp_delivered = isnan(t90) ? 1.0 : min(t90 / duration_s, 1.0))
end

_gap(eng) = (s = current_state(eng); s.δ[1] - s.δ[2])

# ---------------------------------------------------------------------------
# 5. The reference check every engine ships (SPEC §6), on this model.
# ---------------------------------------------------------------------------

"""
    small_signal_mode(net) -> Float64

The inter-area mode frequency (Hz) in closed form, `§7.5(2)`:

    ω_n² = 2π·f₀·K_s·(1/2H₁ + 1/2H₂),   K_s = K·cos δ₀

Derived **through `machine_arrays`/`branch_arrays`**, never from a hand-written
coupling — the same discipline `two_machine_system`'s 1.59 Hz test uses, and for
the same reason: a check written against its own restatement of the formula
cannot catch a per-unit error in the code path it is supposed to validate. `δ₀` is
read off a built engine rather than computed as `asin(P/K)` for the same reason
again — it makes `find_fixpoint`'s answer part of what is being checked, and it is
the branch of the `asin` the solver actually landed on rather than the one the
formula assumes.

Valid for the **governor-free, undamped** machine. With droop armed the mode is
*faster*: a first-order governor whose `Tg` is far longer than the mode period
contributes `invR/(ω₀·Tg)` of extra synchronising stiffness, worth ~4.7 % on the
nominal cell. That is why the reference check builds its own `R = Inf, D = 0`
model instead of asserting against the scenario's.
"""
function small_signal_mode(net::NetworkModel)
    ma, ba = machine_arrays(net), branch_arrays(net)
    eng = SwingEngine(net)
    δ₀ = _gap(eng)                          # gauge-free: the difference, off the fixpoint
    Ks = ba.K[1] * cos(δ₀)
    return sqrt(2π * net.f0 * Ks * (1/(2*ma.H[1]) + 1/(2*ma.H[2]))) / 2π
end

"""
    measure_mode(net; kick_mw=5.0, dt=0.001, n=40_000) -> (; f, amplitude)

The same mode, measured on the running engine by timing zero crossings of the
angle **difference** about its own mean. Gauge-free by construction.

The excitation is a 5 MW / 50 ms `GenerationRamp` — i.e. the shipped API — and
**not** a hand-written perturbation of `integrator.u`. That was the first thing
tried and it silently does nothing: the next `step!` integrates from `uprev`, so
the mutated `u` is overwritten and the run stays exactly on its equilibrium. A
measurement built that way returns a number computed from a flat trace, which is
the failure mode that looks most like success.
"""
function measure_mode(net::NetworkModel; kick_mw::Real = 5.0, dt::Real = 0.001,
                      n::Integer = 40_000)
    kick = GenerationRamp(-kick_mw / S_BASE / 0.05, 0.0, 0.05)
    eng = SwingEngine(net; dt = dt, ramp = [:IB => kick])
    t = Vector{Float64}(undef, n); d = Vector{Float64}(undef, n)
    for k in 1:n
        s = step!(eng); t[k] = s.t; d[k] = s.δ[1] - s.δ[2]
    end
    i0 = findfirst(>(0.5), t)               # discard the kick itself
    tt, dd = @view(t[i0:end]), @view(d[i0:end])
    mid = (maximum(dd) + minimum(dd)) / 2
    zc = [tt[i] + (tt[i+1]-tt[i])*(mid-dd[i])/(dd[i+1]-dd[i])
          for i in 1:length(tt)-1 if dd[i] < mid <= dd[i+1]]
    return (f = (length(zc) - 1) / (zc[end] - zc[1]),
            amplitude = maximum(dd) - minimum(dd))
end

# ---------------------------------------------------------------------------
# 6. The sweep. THIS IS THE RESULT (m3-context.md D10).
# ---------------------------------------------------------------------------

# Tie strengths scanned when locating the slip boundary. The lower edge is the
# weakest tie the sweep visits and is checked against the `NetworkModel`
# construction guard in `test/` — `|P0| ≤ ΣK` — so widening the sweep carelessly
# produces a construction error rather than a wrong number, which is the good
# failure mode (D9).
const P_MAX_SCAN = 2_500.0:100.0:12_000.0

"""
    slip_boundary(; …) -> (; boundary, monotone, scan)

The largest tie strength at which the peninsula still loses synchronism, found by
scanning `P_MAX_SCAN` rather than by bisecting it. Bisection assumes the
slip/no-slip predicate is monotone in `P_max`; scanning **measures** that it is
and returns the answer, so a cell where it were not would be visible instead of
silently halving into the wrong half.

`boundary` is the last scanned tie that slips, so the true boundary lies within
one scan step above it. Two edge cases are reported rather than swallowed, because
either one silently returns a scan edge that reads exactly like an answer:

  - no scanned cell slips → `boundary` is `NaN`;
  - **every** scanned cell slips → `boundary` is the top of the scan and
    `saturated` is `true`, meaning the real boundary is somewhere above the range
    and this number is a lower bound on it, not the boundary.
"""
function slip_boundary(; scan = P_MAX_SCAN, kwargs...)
    sl = [run_cell(; P_max_mw = P, kwargs...).slipped for P in scan]
    first_no = findfirst(!, sl)
    monotone = first_no === nothing ? true : !any(@view sl[first_no:end])
    boundary = first_no === nothing ? last(scan) :
               first_no == 1 ? NaN : scan[first_no - 1]
    return (; boundary, monotone, saturated = first_no === nothing, scan, slipped = sl)
end

# How a boundary prints, with both edge cases visible. A sweep that quietly
# reported its own scan edge as a result would be the same class of error as the
# figures this script exists to replace.
show_boundary(b) = isnan(b.boundary) ? "none" :
                   b.saturated ? @sprintf(">=%.0f", b.boundary) :
                   @sprintf("%.0f", b.boundary)

# The cascade profiles the sweep visits. Magnitudes are DERIVED (section 2) except
# the two labelled `[old]`, which are the figures this script replaces — carried so
# the grid contains them as cells rather than only contradicting them in prose.
cascade_profiles() = [
    ("Table 3-1 floor",    gen_cascade_floor(),      cascade_duration()),
    ("derived (used)",     cascade_magnitude(),      cascade_duration()),
    ("cumulative [old]",   MAG_OLD_CUMULATIVE,       cascade_duration()),
    ("unsourced [old]",    MAG_OLD_UNSOURCED,        cascade_duration()),
]

# Ramp durations. The onset is held at cluster 4a and the SHAPE is varied, because
# the report states the ordering INSIDE the cascade is uncertain (§5) while the
# cumulative total is comparatively solid. The three middle values are the three
# Table 3-1 windows that end at 12:33:20.560 (cluster 4a / 5a / 6a onset); 1.5 and
# 6.0 bracket them. 2.458 s is also the "2.46 s (report)" of the old sweep — whose
# label is doubly unfortunate, since it is numerically the inertia midpoint H_tot
# and no timestamp pair in Table 3-1 was ever cited for it.
const DURATIONS = [1.5, 2.458, 3.192, 4.100, 6.0]

const KE_CE_CELLS  = [600_000.0, 800_000.0, 1_000_000.0, 1_200_000.0]
const P_TIE0_CELLS = [-2_000.0, -1_500.0, -1_000.0, -500.0, 0.0, 500.0, 1_000.0]

# ---------------------------------------------------------------------------
# 7. Output.
# ---------------------------------------------------------------------------

function note(lines...)
    for l in lines
        println("  ", l)
    end
end

function report_reference_check()
    println("\n1. Reference check — the inter-area mode against its closed form\n")
    println("  ", rpad("P_max (MW)", 12), rpad("closed form", 14), rpad("measured", 14),
            rpad("relative", 11), "amplitude")
    for P in (2_500.0, 3_500.0, 5_000.0, 8_000.0)
        net = two_area_model(; P_max_mw = P, R = Inf, D = 0.0,
                               reserve_ib = 0.0, reserve_ce = 0.0)
        cf, ms = small_signal_mode(net), measure_mode(net)
        println("  ", rpad(round(Int, P), 12), rpad(@sprintf("%.6f Hz", cf), 14),
                rpad(@sprintf("%.6f Hz", ms.f), 14),
                rpad(@sprintf("%.1e", abs(ms.f-cf)/cf), 11),
                @sprintf("%.2e rad", ms.amplitude))
    end
    note("",
         "Governor-free and undamped, which is what the closed form describes.",
         "",
         "The residual is finite-amplitude nonlinearity and not a model error, and the",
         "table says so rather than asserting it: the measured mode is BELOW the closed",
         "form in every row (a pendulum's period lengthens with amplitude), and the gap",
         "shrinks monotonically with the amplitude, an order of magnitude across the four",
         "rows. A per-unit or coupling error would not track amplitude.",
         "",
         "Derived through machine_arrays/branch_arrays, and delta_0 read off a built",
         "engine rather than from asin(P/K) — so find_fixpoint's answer is inside what",
         "is being checked. A check written against a hand-copied formula could say",
         "neither thing.")
end

function report_nominal_cell()
    println("\n3. ONE CELL of the grid — not a result. (m3-context.md D10)\n")
    r = run_cell()
    ma = machine_arrays(r.net); ba = branch_arrays(r.net)
    @printf("  S_base %.0f MVA   f0 %.0f Hz   tie P_max %.0f MW  =>  X = %.4f pu, K = %.4f pu\n",
            S_BASE, F0, P_MAX_NOMINAL, ba.X[1], ba.K[1])
    @printf("  H on the system base:  IB %.4f s   CE %.4f s   (= KE/S_base: %.4f / %.4f)\n",
            ma.H[1], ma.H[2], KE_IB/S_BASE, KE_CE/S_BASE)
    @printf("  pre-event tie flow %+.0f MW  =>  delta_0 = %.4f rad = %.2f deg\n",
            P_TIE0, asin(ma.Pm[1]/ba.K[1]), rad2deg(asin(ma.Pm[1]/ba.K[1])))
    @printf("  cascade  %.0f MW over %.3f s  =>  rate %.6f pu/s\n\n",
            cascade_magnitude(), cascade_duration(),
            -cascade_magnitude()/S_BASE/cascade_duration())
    @printf("  |δ_IB − δ_CE| reaches  90 deg at %s   report: 12:33:19.620   delta %+.3f s\n",
            cest(r.t90), T0_CEST + r.t90 - 19.620)
    @printf("  pole slips inside the %.0f s window: %d   peak |δ| %.1f rad\n",
            TEND, r.n_pole_slips, r.dmax)
    @printf("  f_IB minimum %.3f Hz    f_CE minimum %.3f Hz\n", r.f_ib_min, r.f_ce_min)
    @printf("  peak tie export %+.0f MW; swing against the pre-event flow %.0f MW\n",
            r.peak_export, r.swing)
    @printf("  Iberian governor: peak ΔPm %.5f pu against %.5f pu of reserve — saturated: %s\n",
            r.ΔPm_max, r.headroom, r.saturated)
    @printf("  cascade delivered at the 90 deg crossing: %.1f%% (%.0f of %.0f MW)\n",
            100*r.ramp_delivered, cascade_magnitude()*r.ramp_delivered, cascade_magnitude())
    note("",
         "THE 31 ms IS A PROPERTY OF THIS CELL AND NOT OF THE MODEL. Nothing here was",
         "fitted to it — the tie strength is D8's nominal, the cascade is section 2's",
         "derivation and the rest is the report — but section 4d walks the same quantity",
         "across the slipping band and it spans about three seconds. The claim that",
         "survives is the band, not this row of it. Quoting the 31 ms on its own would",
         "be the exact thing that went wrong in the probe this replaces.")

    a = run_cell(; shed = true)
    lg = shed_log(shed_ladder(a.eng, :IB))
    println("\n  With the defence plan armed (report Fig 3-67, bound to :IB, root-found):\n")
    for k in eachindex(lg.t)
        @printf("    %.1f Hz  %s  %5.0f MW  %s\n", lg.threshold_hz[k], cest(lg.t[k]),
                lg.ΔP_pu[k]*S_BASE, lg.label[k])
    end
    @printf("    %d stages, %.0f MW shed; f_IB minimum %.3f Hz (was %.3f); 90 deg at %s\n",
            length(lg.t), shed_total(shed_ladder(a.eng,:IB))*S_BASE, a.f_ib_min,
            r.f_ib_min, cest(a.t90))
    note("",
         "THE DEFENCE PLAN CANNOT PREVENT THIS SEPARATION, in this cell, and the reason is",
         "a timing one rather than a magnitude one: the first stage arms at 49.8 Hz and",
         "Iberian frequency does not reach 49.8 Hz until AFTER the angle has passed 90 deg.",
         "The 90 deg crossing is therefore identical to the millisecond with the plan armed",
         "and disarmed, while the frequency nadir moves by nearly 3 Hz. Arresting the",
         "frequency and holding synchronism are different things, and only the first is",
         "something the ladder can do here.",
         "",
         "The Iberian governor saturates. That is not a modelling artefact to be tuned",
         "away: with 5 % droop on a 48.6 GVA base the droop LAW would command ~19 GW at",
         "-1 Hz, so what the area delivers is set by its reserve (a stated [CHOICE] of",
         "500 MW, sized on Iberia's share of the 3,000 MW area-wide containment reserve)",
         "and the run exhausts it. A larger reserve would help; it is on no sweep axis",
         "below, so no claim in section 4 rests on the exact figure.")
end

function report_sweep()
    println("\n4. THE SWEEP — this is the result\n")
    nom_mag, nom_dur = cascade_magnitude(), cascade_duration()

    println("  4a. Largest tie that still slips, by cascade profile (KE_CE = 800k, P_tie,0 = -1,000)\n")
    print("  ", rpad("cascade profile", 22), rpad("MW", 8))
    for d in DURATIONS; print(rpad(@sprintf("%.3f s", d), 10)); end
    println(rpad("spread", 9), "monotone")
    nonmono = 0
    for (lab, mag, _) in cascade_profiles()
        print("  ", rpad(lab, 22), rpad(round(Int, mag), 8))
        bs = Float64[]
        for d in DURATIONS
            b = slip_boundary(; magnitude_mw = mag, duration_s = d)
            b.monotone || (nonmono += 1)
            push!(bs, b.boundary)
            print(rpad(show_boundary(b), 10))
        end
        println(rpad(@sprintf("%.0f", maximum(bs)-minimum(bs)), 9),
                nonmono == 0 ? "yes" : "NO")
    end
    note("",
         "MONOTONE means what the boundary number depends on: that no tie STIFFER than a",
         "non-slipping one slips. It is scanned and measured rather than assumed, because",
         "the obvious way to find this boundary is to bisect, and bisection on a",
         "predicate that is not monotone silently halves into the wrong half.",
         "",
         "ROWS — the magnitude axis of section 2, with the two [old] rows carried as",
         "cells so the grid contains the figures it replaces rather than only",
         "contradicting them. The correction moves the boundary from the old sweep's",
         "4,250 MW to about 5,500 MW: the boundary tracks cascade magnitude hard, exactly",
         "as the old sweep said it would, which is why re-deriving the magnitude from the",
         "report's own table was made a checklist item rather than left to judgement.",
         "",
         "COLUMNS — and this one came out the opposite way to the reasoning that",
         "prompted it. At the derived magnitude the cascade is STILL ARRIVING when",
         "synchronism is lost (~76 % delivered at the 90 deg crossing in section 3), which",
         "says magnitude and duration should not be separable. Measured, they are: the",
         "boundary moves by at most one or two scan steps across a 4x change in ramp",
         "duration, against ~2,700 MW across the magnitude axis. So the old sweep's",
         "second reading SURVIVES the correction — how fast the deficit arrives barely",
         "matters, only how much of it there is. That is the useful half, because the",
         "report states the ordering INSIDE the cascade is uncertain (§5) while the",
         "cumulative total is comparatively solid.")

    println("\n  4b. Boundary vs remote inertia KE_CE (derived cascade)\n")
    print("  ", rpad("KE_CE (MWs)", 14)); println("boundary (MW)")
    for ke in KE_CE_CELLS
        b = slip_boundary(; KE_ce = ke, magnitude_mw = nom_mag, duration_s = nom_dur)
        @printf("  %-14s %s\n", round(Int, ke), show_boundary(b))
    end
    note("", "Continental Europe's inertia barely matters, which the old sweep also found.",
         "An area 6.7x the peninsula's kinetic energy is already close enough to an",
         "infinite bus that doubling it changes little.")

    println("\n  4c. Boundary vs the PRE-EVENT TIE FLOW — the parameter two sources disagree about\n")
    print("  ", rpad("P_tie,0 (MW)", 15), rpad("boundary (MW)", 16), "P_max needed for a 5,000 MW swing")
    println()
    for p0 in P_TIE0_CELLS
        b = slip_boundary(; P_tie0_mw = p0, magnitude_mw = nom_mag, duration_s = nom_dur)
        need = 5_000.0 + p0                     # swing = peak export (=P_max) − P_tie,0
        @printf("  %-15s %-16s %.0f  %s\n", @sprintf("%+.0f", p0),
                show_boundary(b), need,
                (!isnan(b.boundary) && need <= b.boundary) ? "<= boundary: BOTH reproducible" :
                                                             "> boundary: not both")
    end

    println("\n  4d. 90 deg crossing across the slipping band (derived cascade, KE_CE = 800k)\n")
    println("  ", rpad("P_max (MW)", 12), rpad("90 deg at", 16), rpad("vs report", 12), "swing (MW)")
    for P in 2_500.0:500.0:5_500.0
        r = run_cell(; P_max_mw = P)
        r.slipped || continue
        println("  ", rpad(round(Int, P), 12), rpad(cest(r.t90), 16),
                rpad(@sprintf("%+.2f s", T0_CEST + r.t90 - 19.620), 12),
                @sprintf("%.0f", r.swing))
    end

    println("\n  4e. Does the defence plan change the boundary?\n")
    for sh in (false, true)
        b = slip_boundary(; shed = sh, magnitude_mw = nom_mag, duration_s = nom_dur)
        @printf("  defence plan %-9s boundary %s MW\n", sh ? "ARMED" : "disarmed",
                show_boundary(b))
    end
    note("",
         "It moves the boundary a little and decides nothing in the middle of the band,",
         "and the two facts have one explanation. The ladder's first stage arms at",
         "49.8 Hz; whether it can help depends entirely on whether the area reaches",
         "49.8 Hz BEFORE the angle runs away. At the nominal cell it does not — the",
         "90 deg crossing is identical to the millisecond armed and disarmed (section 3).",
         "Near the boundary the angle runs away slowly enough for the frequency to get",
         "there first, so the ladder tips a narrow band of tie strengths from slipping to",
         "holding. That band is the whole of the effect.")
end

"""
    timing_band(; tol_s = 1.0) -> (; lo, hi)

The range of tie strengths whose 90° crossing lands within `tol_s` of the report's
12:33:19.62, at the derived cascade. Computed rather than asserted, so section 5's
"within about a second" is a read of the grid and not a recollection of it.
"""
function timing_band(; tol_s::Real = 1.0, scan = P_MAX_SCAN, kwargs...)
    ok = Float64[]
    for P in scan
        r = run_cell(; P_max_mw = P, kwargs...)
        r.slipped && abs(T0_CEST + r.t90 - 19.620) <= tol_s && push!(ok, P)
    end
    return (; lo = isempty(ok) ? NaN : first(ok), hi = isempty(ok) ? NaN : last(ok))
end

function report_conclusions()
    b    = slip_boundary()
    band = timing_band()
    println("\n5. What survives the grid, and what does not\n")
    note("SURVIVES — the separation is reproduced across the whole plausible corridor.",
         "  Every tie strength from the weakest cell scanned ($(round(Int,first(P_MAX_SCAN))) MW) up to about",
         "  $(round(Int,b.boundary)) MW loses synchronism, at the derived cascade, at every remote inertia",
         "  scanned; and the 90 deg crossing lands within one second of the report's",
         "  12:33:19.62 for every tie from $(round(Int,band.lo)) to $(round(Int,band.hi)) MW. The defensible statement is",
         "  the one §7.4 of the plan doc worked out in advance: at the report's cascade",
         "  profile a two-area classical model reproduces the separation, to within about",
         "  a second, at any tie strength in the lower part of the plausible corridor.",
         "  It is NOT 'the model predicted 12:33:19.589'.",
         "",
         "SURVIVES — the defence plan does not decide the separation, and section 4e",
         "  says why rather than only that. Arming the full Fig 3-67 ladder moves the",
         "  boundary by one or two scan steps and changes the nominal cell's 90 deg",
         "  crossing not at all, because the ladder's first stage arms at 49.8 Hz and",
         "  Iberian frequency does not reach 49.8 Hz until after the angle has passed",
         "  90 deg. Only in a narrow band of tie strengths near the boundary does the",
         "  angle run away slowly enough for the frequency to get there first. This",
         "  REPLACES §7.3(c)'s retracted knife-edge inference with a mechanism.",
         "",
         "SURVIVES — 'the boundary is near-insensitive to ramp duration', and it survives",
         "  AGAINST the reasoning that predicted it would not: at the derived magnitude",
         "  the cascade is still arriving when synchronism is lost, which says duration",
         "  ought to matter. Measured, it does not (section 4a). Useful, because the",
         "  report's within-cascade ordering is explicitly uncertain and its cumulative",
         "  total is not.",
         "",
         "DOES NOT SURVIVE — the old 4,250 MW boundary, and it was never a property of",
         "  the corridor. It was a property of an unsourced 2,773 MW cascade (section 2).",
         "",
         "TURNS ON A PARAMETER THE REPORT DOES NOT STATE — §7.3(d)'s ceiling, that a",
         "  constant-voltage two-area reduction can reproduce the separation OR the",
         "  ~5,000 MW export swing but not both. Section 4c: with the pre-event AC flow",
         "  read as IMPORT (D8's -1,000 MW) the swing needs P_max = 4,000 MW, which is",
         "  well inside the slipping band, so BOTH are reproducible. Read as EXPORT",
         "  (+1,000 MW, which is what §7.3(d)'s own arithmetic assumes) it needs 6,000 MW",
         "  against a boundary of ~3,500, and the ceiling holds. The conclusion flips on",
         "  the sign of a quantity the report as extracted gives only the CHANGE in.",
         "  That is a weaker claim than the old doc made and a better one, because it",
         "  names the single observation that would settle it.",
         "",
         "STILL OUT OF SCOPE, unchanged (§7.6). Voltage magnitude is constant behind a",
         "  reactance, so angle instability is in and voltage instability is not: the",
         "  final phase, 12:33:21.5 to the 12:33:27 blackout, is a voltage collapse this",
         "  tier cannot represent at any point of the grid above.",
         "",
         "BIAS, stated in the direction it points. This run starts at cascade onset with",
         "  the peninsula at exactly 50.000 Hz and zero governor deployment, where reality",
         "  was near 49.94 Hz with ~880 MW of loss and load rise already standing (the",
         "  clusters folded into the initial condition — see section 2). Both give the",
         "  machine MORE margin than it had, so every boundary above is a CONSERVATIVE",
         "  bound on tie stiffness: the real system would slip at a stiffer tie than the",
         "  numbers here say, not a weaker one.",
         "",
         "NOT RE-DERIVED HERE. §7.3(a)'s bracket-closure result — that adding a second",
         "  area fixes the pre-separation frequency window regardless of how the tie is",
         "  parameterised — needs the 12:32:00-12:33:16 run, which needs five discrete",
         "  injections on one machine and this tier has one scheduled ramp per machine.",
         "  It remains a THROWAWAY-PROBE result and is labelled as one in §7.3.")
end

function main()
    println("Iberian separation, 28 Apr 2025 — two-area classical model with its sweep")
    println("t = 0 is 12:33:16.460 CEST (Table 3-1 cluster 4a, cascade onset)\n")
    report_reference_check()
    println()
    print_derivation()
    report_nominal_cell()
    report_sweep()
    report_conclusions()
    return nothing
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
