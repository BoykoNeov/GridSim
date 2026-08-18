# Headless replay of the 28 April 2025 Iberian blackout event sequence.
#
#   julia --project=. scripts/iberia_2025_04_28.jl
#
# Data + page citations: docs/scenarios/iberia-2025-04-28.md
# Plan + fidelity boundary: docs/plans/entsoe-iberia-reproduction.md
#
# This is the headless proof of docs/SPEC.md §7.8 criterion 1 — core runs from a
# script and produces a frequency trajectory with NO Makie dependency — using the
# real scenario instead of the synthetic `example_system`.
#
# READ THE FIDELITY BOUNDARY BEFORE TREATING ANY OF THIS AS VALIDATION. The
# centre-of-inertia model is faithful only from 12:32:00 to ~12:33:19.6. After
# that the collapse is driven by loss of synchronism between Iberia and
# Continental Europe — power sloshing across the ES–FR border as the angle
# difference runs past 90° — which a two-state swing + governor model has no
# mechanism for. See the plan doc §2.

using GridSim
using Printf

# ---------------------------------------------------------------------------
# System parameters. Every choice here is a modelling decision, not a fact from
# the report — recorded explicitly so the printed tables are reconstructible.
# ---------------------------------------------------------------------------

const KE     = 119_474.0   # MWs — Iberian kinetic energy at 12:30 (Table 2-4, p.36) [FACT]
const H_MID  = 2.46        # s   — midpoint of the report's 2.21–2.71 range [CHOICE]
const H_LO   = 2.21        # s   — low end of the published range [FACT]
const H_HI   = 2.71        # s   — high end of the published range [FACT]
const F0     = 50.0        # Hz  [FACT]
const D      = 1.5         # pu/pu — load damping; SPEC §7.2 says "typical 1–2" [CHOICE]
const TG     = 8.0         # s   — aggregate governor/turbine lag [CHOICE]

# LOAD INERTIA — decided consciously, per plan doc §3.4. The report's H_tot is
# H_eq + H_loads: it INCLUDES the rotating inertia of motor load, and the 2.21–2.71
# uncertainty band exists precisely because H_loads is not directly measurable.
# GridSim has no load-inertia term, so putting H_tot on the synchronous fleet
# CONFLATES the two. That is a documented approximation, not an oversight:
#   - For the frequency trajectory it is exactly right — the swing equation only
#     ever sees the total, `RoCoF = f0·ΔP/(2·H_sys)`, and H_sys is the total here.
#   - It is wrong the moment load inertia must behave differently from generator
#     inertia — i.e. when load sheds (its inertia leaves with it) or when per-unit
#     rotor angles appear. Neither exists at M1.
# The inertia-sensitivity section below runs the published range end to end, which
# is what that band is actually good for.

# `S_base = KE/H_tot` makes the base an artefact of the inertia choice (plan §3.4);
# keying off KE keeps the physics right whichever H_tot is used.
s_base(H_tot) = KE / H_tot   # MVA — 48,567 at H_tot = 2.46

# One aggregate synchronous fleet carries ALL the inertia and droop; the blocks
# that trip are inverter-based (H = 0, R = Inf, zero headroom), which the existing
# `GeneratingUnit` already expresses without any data-model change.
const S_SYNC    = 20_000.0   # MVA rated [CHOICE]
const P0_SYNC   = 10_000.0   # MW output [CHOICE]
const PMAX_SYNC = 12_000.0   # MW ⇒ 2 GW of up-reserve [CHOICE]
const R_SYNC    = 0.05       # pu droop [CHOICE]

"""
    iberia_system(H_tot = H_MID) -> SystemModel

The Iberian Peninsula as a single centre-of-inertia system, with the four
generation-loss clusters broken out as separately trippable inverter-based units.
`H_tot` (s) is the system inertia constant; the system base follows from the
measured kinetic energy, `S_base = KE/H_tot`.
"""
function iberia_system(H_tot::Float64 = H_MID)
    S = s_base(H_tot)
    units = [
        # H chosen so the COI aggregate H_sys comes out exactly at H_tot.
        GeneratingUnit(:SYNC, S_SYNC, H_tot * S / S_SYNC, P0_SYNC, R_SYNC, PMAX_SYNC),
        # Report Table 3-1 clusters (pp.103–105), grouped as in the narrative (p.116).
        GeneratingUnit(:E3,    355.0, 0.0,  355.0, Inf,  355.0),  # Granada transformer
        GeneratingUnit(:E4,    725.0, 0.0,  725.0, Inf,  725.0),  # Badajoz, 4a + 4b
        GeneratingUnit(:E5,    930.0, 0.0,  930.0, Inf,  930.0),  # Segovia/Huelva/Sevilla/Cáceres
        GeneratingUnit(:E6,   2600.0, 0.0, 2600.0, Inf, 2600.0),  # cascade to 12:33:20 (a FLOOR)
    ]
    return SystemModel(S, F0, D, TG, units)
end

# t = 0 is 12:32:00 CEST. Times are the report's own timestamps.
event_script(S) = [
    ( 0.00, StepLoad(317.3 / S)),  # cluster 1: net load rise over 12:32:00–12:32:57
    (57.22, TripGenerator(:E3)),
    (76.46, TripGenerator(:E4)),
    (77.37, TripGenerator(:E5)),
    (78.10, TripGenerator(:E6)),
]

# The defence plan as it actually fired, annotated on report Figure 3-67 (p.178):
# ES + PT aggregated per threshold. The first four stages are automatic
# pump-storage disconnection (Table 3-14, p.177), the rest low-frequency demand
# disconnection (Table 3-7, p.170). Both remove LOAD, so both are one mechanism
# here. 15,532 MW in total — a third of the system base.
const SHED_MW = [
    (49.8,  381.0, :PT_pump_49_8),
    (49.7,  450.0, :PT_pump_49_7),
    (49.6,  438.0, :PT_pump_49_6),
    (49.5, 2638.0, :ESPT_pump_49_5),   # 2,168 ES + 470 PT
    (49.3,  947.0, :ESPT_pump_49_3),   #   588 ES + 359 PT
    (49.2,  218.0, :PT_industrial_49_2),
    (49.0, 1491.0, :ESPT_lfdd_49_0),   # 1,176 ES + 315 PT
    (48.8, 1962.0, :ESPT_lfdd_48_8),   # 1,669 ES + 293 PT
    (48.6, 1890.0, :ESPT_lfdd_48_6),   # 1,575 ES + 315 PT
    (48.4, 1847.0, :ESPT_lfdd_48_4),   # 1,524 ES + 323 PT
    (48.2, 1576.0, :ESPT_lfdd_48_2),   # 1,294 ES + 282 PT
    (48.0, 1694.0, :ESPT_lfdd_48_0),   # 1,267 ES + 427 PT
]

shed_ladder(S) = [LoadShedStage(hz, mw / S; label = lab) for (hz, mw, lab) in SHED_MW]

# Reported frequency waypoints (p.116), as (t_rel, f_Hz, label).
const WAYPOINTS = [
    (55.0, 49.98, "12:32:55  after net load rise"),
    (60.0, 49.94, "12:33:00  after event 3  (355 MW)"),
    (76.9, 49.90, "12:33:16  after event 4  (725 MW)"),
    (77.9, 49.80, "12:33:17  after event 5  (930 MW)"),
    (80.0, 48.50, "12:33:20  after >=2,600 MW more"),
]

# The model is faithful only up to loss of synchronism at 12:33:19.62 (plan §2).
const T_BOUNDARY = 79.62

"""
    replay(; H_tot=H_MID, dt=0.01, tend=80.0, shed=true) -> FrequencyResponseEngine

Step the engine to `tend` seconds, draining the scripted events at step boundaries
exactly as the orchestration loop would. `shed=false` disarms the defence plan, to
isolate what the load shedding was worth.
"""
function replay(; H_tot::Float64 = H_MID, dt::Float64 = 0.01, tend::Float64 = 80.0,
                shed::Bool = true)
    model = iberia_system(H_tot)
    S = model.S_base
    stages = shed ? shed_ladder(S) : LoadShedStage[]
    eng = init!(FrequencyResponseEngine, model; dt = dt, shed = stages)
    script = event_script(S)
    i = 1
    for _ in 1:round(Int, tend / dt)
        t = current_state(eng).t
        while i <= length(script) && script[i][1] <= t
            inject!(eng, script[i][2])
            i += 1
        end
        step!(eng)
    end
    return eng
end

# 12:32:00 CEST + t, to the millisecond — the format the report annotates with.
function cest(t::Real)
    total = 12 * 3600 + 32 * 60 + t
    h, rem = divrem(total, 3600)
    m, sec = divrem(rem, 60)
    return @sprintf("%02d:%02d:%06.3f", h, m, sec)
end

# Nearest recorded sample to time `tq` (the trajectory is sampled every dt).
sample_at(s, tq) = argmin(abs.(s.t .- tq))

# Print an indented note under a table. (A triple-quoted string would have its
# uniform leading whitespace stripped, flattening the note against the margin.)
function note(lines...)
    for l in lines
        println("  ", l)
    end
end

function report_waypoints(s)
    println("Frequency waypoints (report p.116)\n")
    println(rpad("waypoint", 38), rpad("report", 9), rpad("model", 9), "delta")
    for (tq, fref, label) in WAYPOINTS
        fm = s.f[sample_at(s, tq)]
        println(rpad(label, 38), rpad(fref, 9), rpad(round(fm, digits = 3), 9),
                (fm >= fref ? "+" : ""), round(fm - fref, digits = 3))
    end
end

function report_shedding(eng)
    lg = shed_log(eng.ladder)
    S = eng.model.S_base
    println("\nDefence plan — stages that fired (report Fig 3-67, p.178)\n")
    if isempty(lg.t)
        println("  (none — frequency never fell to 49.8 Hz)")
        return
    end
    println("  ", rpad("threshold", 11), rpad("fired at (CEST)", 17), rpad("shed", 11), "label")
    for k in eachindex(lg.t)
        println("  ", rpad(string(lg.threshold_hz[k], " Hz"), 11), rpad(cest(lg.t[k]), 17),
                rpad(string(round(Int, lg.ΔP_pu[k] * S), " MW"), 11), lg.label[k])
    end
    println("  ", rpad("", 11), rpad("", 17),
            rpad(string(round(Int, shed_total(eng.ladder) * S), " MW"), 11), "TOTAL")
    note("",
         "Firing instants are ROOT-FOUND by a per-stage ContinuousCallback, not",
         "quantised to the $(eng.dt) s step — which is why they can be printed to the",
         "millisecond and set against the report's own annotations:",
         "",
         "  49.5 Hz / ES:  report 12:33:20.133–12:33:20.800 (p.174)",
         "  49.3 Hz / ES:  report 12:33:20.500 (p.174)",
         "",
         "The model fires its 49.5 Hz stage ~1.7 s EARLY, and that is the same",
         "'too deep before the boundary' error the waypoint table shows — not a",
         "separate defect. Reality did not reach 49.5 Hz until AFTER loss of",
         "synchronism at 12:33:19.62, i.e. past the point this model can speak to.")
end

function report_tripped(eng, s)
    println("\nCumulative tripped generation (second axis of report Figs 1-3 / 3-7 / 3-9)\n")
    for tq in (57.5, 76.9, 77.9, 78.5, 80.0)
        i = sample_at(s, tq)
        @printf("  %s   %6.0f MW   f = %.3f Hz\n", cest(s.t[i]), s.tripped_mw[i], s.f[i])
    end
    note("Report: >2.5 GW by 12:33:18.020 (p.11); ~5,750 MW in Spain by 12:33:20.560 (p.119).",
         "The 4,610 MW here is the scripted sequence only — the >=2,600 MW cluster is a",
         "FLOOR the report states as such, so this tally is a lower bound by construction.")
end

function report_rocof(s)
    w = windowed_rocof(s)                      # 500 ms sliding window
    inwin = findall(t -> t <= T_BOUNDARY, s.t)  # only inside the faithful window
    wv = [w.RoCoF[i] for i in inwin if !isnan(w.RoCoF[i])]
    iv = [s.RoCoF[i] for i in inwin]
    println("\nRoCoF — 500 ms window vs instantaneous (report p.116 uses the window)\n")
    @printf("  peak |RoCoF| inside the faithful window (to %s):\n", cest(T_BOUNDARY))
    @printf("    500 ms windowed  %6.3f Hz/s\n", minimum(wv))
    @printf("    instantaneous    %6.3f Hz/s\n", minimum(iv))
    note("",
         "The report states |RoCoF| stayed within 1 Hz/s until 12:33:20.560 — i.e.",
         "throughout this window, which the model satisfies. That is a check the",
         "windowed read can take and the instantaneous one cannot: they are different",
         "quantities, and the instantaneous value is the steeper of the two by",
         "construction. Beyond 12:33:19.62 neither number is claimable — the report's",
         "-1 Hz/s at 12:33:20.560 and -2 Hz/s at 12:33:23.360 are past the boundary",
         "and are NOT targets this model may be tuned against.")
end

"""
    rocof0(H_tot, id) -> Float64

Initial RoCoF (Hz/s) the model gives for tripping unit `id` at the origin, read
un-stepped so it is the exact closed form `−f0·(P/S_base)/(2·H_sys)`. Derived from
the model rather than restated as a formula, so it cannot drift from the engine.
"""
function rocof0(H_tot::Float64, id::Symbol)
    eng = init!(FrequencyResponseEngine, iberia_system(H_tot))
    inject!(eng, TripGenerator(id))
    return current_state(eng).RoCoF
end

function report_sensitivity()
    println("\nInertia sensitivity — the report's published H_tot range as an experiment\n")
    println("  ", rpad("H_tot", 8), rpad("S_base", 11), rpad("RoCoF0 (2.6 GW)", 17),
            rpad("stiffness", 11), rpad("nadir (armed)", 15), "nadir (no shed)")
    for H in (H_LO, H_MID, H_HI)
        eng = replay(; H_tot = H)
        bare = replay(; H_tot = H, shed = false)
        S = eng.model.S_base
        stiff = D + 1 / GridSim.aggregates(eng.model, Set([:SYNC])).R_eq   # D + 1/R_eq, pu
        println("  ", rpad(string(H, " s"), 8),
                rpad(string(round(Int, S), " MVA"), 11),
                rpad(string(round(rocof0(H, :E6), digits = 4), " Hz/s"), 17),
                rpad(string(round(stiff, digits = 2)), 11),
                rpad(string(round(eng.nadir, digits = 3), " Hz"), 15),
                round(bare.nadir, digits = 3), " Hz")
    end
    note("",
         "Three things in this table each look like a result and are not. Read them",
         "together.",
         "",
         "1. RoCoF0 does not move across the band AT ALL, and that is by construction,",
         "   not a finding. The base is keyed off the measured kinetic energy, so",
         "   f0·ΔP/(2·H_sys) collapses to f0·ΔP_MW/(2·KE) and the H_tot choice cancels",
         "   out exactly. KE is what the report actually measured; the 2.21–2.71 band",
         "   is uncertainty about how to SPLIT it between machines and motor load.",
         "   For a single-frequency model that split changes nothing.",
         "",
         "2. The ARMED nadir is identical across the band — again not insensitivity to",
         "   inertia. The 2,638 MW stage at 49.5 Hz arrests the fall exactly there, so",
         "   the nadir is pinned by a protection setting rather than by the physics.",
         "",
         "3. The DISARMED nadir does move, ~0.08 Hz, and it moves the 'wrong' way:",
         "   deeper at HIGHER H_tot. That is the giveaway that it is not an inertia",
         "   effect either. Raising H_tot shrinks S_base, which re-scales the fleet's",
         "   per-unit droop and damping (stiffness column, 8.9 → 10.6), and that",
         "   re-scaling is what moves the nadir. The genuine inertia-only comparison —",
         "   everything else held fixed — is asserted in test/runtests.jl, not here.",
         "",
         "So the ~1.2 Hz the model is off by at 12:33:20 cannot be laid at the door of",
         "H_tot uncertainty: no choice inside the report's own published range moves",
         "the answer materially, in either direction. The gap is the missing",
         "loss-of-synchronism export swing.",
         "",
         "H_tot is the report's H_eq + H_loads. GridSim has no load-inertia term, so",
         "all of it sits on the synchronous fleet. That is exact for the frequency",
         "trajectory (the swing equation only ever sees the total) and becomes an",
         "approximation the moment load inertia would have to leave with shed load —",
         "which is a real limitation now that the ladder above sheds 3.9 GW of it.",
         "Documented, not hidden; see the note at the top of this file.")
end

function main()
    eng = replay()
    s = state_series(eng)
    bare = replay(; shed = false)      # same scenario, defence plan disarmed

    println("Iberian blackout, 28 Apr 2025 — headless COI replay")
    @printf("S_base = %.0f MVA   H_tot = %.2f s   D = %.1f   Tg = %.1f s\n\n",
            eng.model.S_base, H_MID, D, TG)

    report_waypoints(s)
    report_shedding(eng)
    report_tripped(eng, s)
    report_rocof(s)
    report_sensitivity()

    @printf("\nnadir  %.3f Hz with the defence plan armed, %.3f Hz without it.\n",
            eng.nadir, bare.nadir)
    println("""
    Interpreting the deltas — the two windows fail differently, and a single
    "close enough" reading of the waypoint table is wrong:

      Before 12:33:16 the model runs TOO DEEP. Iberia was still synchronously
      inside Continental Europe behind a finite tie (~3 GW of AC; the 2 GW HVDC
      was in constant-power mode and gave no frequency support), so the real
      system was stiffer than an isolated Iberia. Re-running with a CE-scale base
      overshoots the other way, so the observation is bracketed — that bracket is
      the argument for a two-area/tie-line model.

      After 12:33:16 the model runs TOO SHALLOW, and now that the real defence
      plan is armed it runs shallower still: the ladder arrests the fall and the
      model RECOVERS. Reality did not. That divergence is the honest headline of
      this script, not a defect in it — the report's own numbers say ~15.5 GW of
      pump-storage and demand disconnection fired and the system collapsed
      anyway, because of ~5,000 MW of export swing from loss of synchronism plus
      generation loss beyond the >=2,600 MW floor injected here. A two-state
      swing + governor model has no mechanism for either. Do not close the gap by
      tuning parameters; close it with the two-area model (plan doc §7).""")
    return eng
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
