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

# ---------------------------------------------------------------------------
# System parameters. Every choice here is a modelling decision, not a fact from
# the report — recorded explicitly so the printed table is reconstructible.
# ---------------------------------------------------------------------------

const KE      = 119_474.0   # MWs   — Iberian kinetic energy at 12:30 (report Table 2-4, p.36) [FACT]
const H_TOT   = 2.46        # s     — midpoint of the report's 2.21–2.71 range [CHOICE]
const S_BASE  = KE / H_TOT  # MVA   — 48,567; see plan doc §3.4 on keying off KE instead
const F0      = 50.0        # Hz    [FACT]
const D       = 1.5         # pu/pu — load damping; SPEC §7.2 says "typical 1–2" [CHOICE]
const TG      = 8.0         # s     — aggregate governor/turbine lag [CHOICE]

# One aggregate synchronous fleet carries ALL the inertia and droop; the blocks
# that trip are inverter-based (H = 0, R = Inf, zero headroom), which the existing
# `GeneratingUnit` already expresses without any data-model change.
const S_SYNC    = 20_000.0                       # MVA rated [CHOICE]
const P0_SYNC   = 10_000.0                       # MW output [CHOICE]
const PMAX_SYNC = 12_000.0                       # MW ⇒ 2 GW of up-reserve [CHOICE]
const R_SYNC    = 0.05                           # pu droop [CHOICE]
const H_SYNC    = H_TOT * S_BASE / S_SYNC        # so H_sys == H_TOT

"""
    iberia_system() -> SystemModel

The Iberian Peninsula as a single centre-of-inertia system, with the four
generation-loss clusters broken out as separately trippable inverter-based units.
"""
function iberia_system()
    units = [
        GeneratingUnit(:SYNC, S_SYNC, H_SYNC, P0_SYNC, R_SYNC, PMAX_SYNC),
        # Report Table 3-1 clusters (pp.103–105), grouped as in the narrative (p.116).
        GeneratingUnit(:E3,    355.0, 0.0,  355.0, Inf,  355.0),  # Granada transformer
        GeneratingUnit(:E4,    725.0, 0.0,  725.0, Inf,  725.0),  # Badajoz, 4a + 4b
        GeneratingUnit(:E5,    930.0, 0.0,  930.0, Inf,  930.0),  # Segovia/Huelva/Sevilla/Cáceres
        GeneratingUnit(:E6,   2600.0, 0.0, 2600.0, Inf, 2600.0),  # cascade to 12:33:20 (a FLOOR)
    ]
    return SystemModel(S_BASE, F0, D, TG, units)
end

# t = 0 is 12:32:00 CEST. Times are the report's own timestamps.
const SCRIPT = [
    ( 0.00, StepLoad(317.3 / S_BASE)),  # cluster 1: net load rise over 12:32:00–12:32:57
    (57.22, TripGenerator(:E3)),
    (76.46, TripGenerator(:E4)),
    (77.37, TripGenerator(:E5)),
    (78.10, TripGenerator(:E6)),
]

# Reported frequency waypoints (p.116), as (t_rel, f_Hz, label).
const WAYPOINTS = [
    (55.0, 49.98, "12:32:55  after net load rise"),
    (60.0, 49.94, "12:33:00  after event 3  (355 MW)"),
    (76.9, 49.90, "12:33:16  after event 4  (725 MW)"),
    (77.9, 49.80, "12:33:17  after event 5  (930 MW)"),
    (80.0, 48.50, "12:33:20  after >=2,600 MW more"),
]

"""
    replay(; dt=0.01, tend=80.0) -> FrequencyResponseEngine

Step the engine to `tend` seconds, draining the scripted events at step
boundaries exactly as the orchestration loop would.
"""
function replay(; dt::Float64 = 0.01, tend::Float64 = 80.0)
    eng = init!(FrequencyResponseEngine, iberia_system(); dt = dt)
    i = 1
    for _ in 1:round(Int, tend / dt)
        t = current_state(eng).t
        while i <= length(SCRIPT) && SCRIPT[i][1] <= t
            inject!(eng, SCRIPT[i][2])
            i += 1
        end
        step!(eng)
    end
    return eng
end

function main()
    eng = replay()
    s = state_series(eng)
    at(tq) = s.f[argmin(abs.(s.t .- tq))]

    println("Iberian blackout, 28 Apr 2025 — headless COI replay")
    println("S_base = ", round(S_BASE, digits = 0), " MVA   H_tot = ", H_TOT,
            " s   D = ", D, "   Tg = ", TG, " s\n")
    println(rpad("waypoint", 38), rpad("report", 9), rpad("model", 9), "delta")
    for (tq, fref, label) in WAYPOINTS
        fm = at(tq)
        println(rpad(label, 38), rpad(fref, 9), rpad(round(fm, digits = 3), 9),
                (fm >= fref ? "+" : ""), round(fm - fref, digits = 3))
    end
    println("\nnadir = ", round(eng.nadir, digits = 3), " Hz",
            "   (report: 48.5 Hz just before 12:33:20, then collapse)")
    println("""

    Interpreting the deltas — the two windows fail differently, and a single
    "close enough" reading of this table is wrong:

      Before 12:33:16 the model runs TOO DEEP. Iberia was still synchronously
      inside Continental Europe behind a finite tie (~3 GW of AC; the 2 GW HVDC
      was in constant-power mode and gave no frequency support), so the real
      system was stiffer than an isolated Iberia. Re-running with a CE-scale base
      overshoots the other way, so the observation is bracketed — that bracket is
      the argument for a two-area/tie-line model.

      After 12:33:16 the model runs TOO SHALLOW, and the apparent agreement at
      12:33:20 is COINCIDENTAL CANCELLATION, not calibration. This script omits
      the ~4,854 MW of pump-storage shedding that actually fired from 49.8 Hz
      down (report Table 3-14), which would push frequency UP. Reality still fell
      further than the model, so the true late-window imbalance was well above
      the 2,600 MW injected here — consistent with the report's own hedges (the
      930 MW event "or even more than 1,100 MW"; >=2,600 MW is a floor;
      unobservable rooftop PV) and with the loss-of-synchronism export swing.
      Do not tune parameters against this waypoint.
    """)
    return eng
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
