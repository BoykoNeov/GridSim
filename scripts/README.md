# scripts/

REPL-driven experiments against the headless core — the payoff of the no-UI-in-core
design (`docs/SPEC.md` §3.1). A script here should `using GridSim`, build a system,
run an engine, and print/assert results, with **no** Makie import.

Run one with the project environment active:

```julia
julia --project=. scripts/<name>.jl
```

## `iberia_2025_04_28.jl`

Replays the 28 April 2025 Iberian blackout event sequence through
`FrequencyResponseEngine`. This is Milestone 1's headless proof (`docs/SPEC.md`
§7.8 criterion 1), using a real scenario instead of the synthetic
`example_system`. Five sections:

1. **Frequency waypoints** against the ones ENTSO-E reported.
2. **Defence plan** — which load-shedding stages fired, at instants *root-found*
   by a per-stage `ContinuousCallback` (so they print to the millisecond and can
   be set against the report's own annotations), and how much each shed.
3. **Cumulative tripped generation** at the report's checkpoints — a lower bound
   by construction, since the last cluster is a floor the report states as such.
4. **RoCoF**, 500 ms windowed vs instantaneous. These are different quantities;
   only the windowed one is comparable to the report.
5. **Inertia sensitivity** over the report's published 2.21–2.71 s band.

Read `docs/plans/entsoe-iberia-reproduction.md` §2 before treating any of this as
validation — the centre-of-inertia model is faithful only up to ~12:33:19.6, and
**the model recovers where reality collapsed**. That gap is the missing
loss-of-synchronism export swing, and it is not to be closed by tuning.

Three of the printed sections look like results and are not; each says so in its
own output. The script's claims are asserted in `test/runtests.jl`, which
includes this file as a module so the scenario data lives in exactly one place.

## `iberia_two_area.jl`

The same event on the **two-area** tier (`SwingEngine`), which is what adds the one
mechanism the script above has no state for: a rotor angle and a nonlinear tie whose
transfer peaks at 90°, falls while the angle keeps growing, and reverses past 180°.
That reversal is the report's export swing, and it is why the aggregate model
recovers where reality collapsed.

**The result is the sweep, not the trace.** This is Milestone 3 step 6, and it exists
to replace a throwaway probe whose tie strength had been tuned until the peninsula
lost synchronism, so that three of its quoted numbers were artefacts of the tuning
(`docs/plans/entsoe-iberia-reproduction.md` §7.3, `docs/plans/m3-context.md` D10).
Five sections:

1. **Reference check** — the inter-area mode against its closed form, derived through
   `machine_arrays`/`branch_arrays` and with the residual *identified* (it tracks
   swing amplitude) rather than merely bounded.
2. **The cascade magnitude, re-derived from Table 3-1** and printed as arithmetic, not
   quoted. 5,187 MW over 4.100 s. The two figures previously in circulation for this
   one quantity differ by 1.87× and both appear below as labelled cells.
3. **One cell** of the grid, labelled as one cell in its own output.
4. **The sweep** — tie strength × cascade magnitude × ramp duration × remote inertia ×
   pre-event tie flow × defence plan, regenerable in under a minute.
5. **What survives the grid and what does not**, including one conclusion of §7.3 that
   is overturned, one that survives against the reasoning that predicted it would not,
   and one that turns out to depend on a quantity the report never states.

Read `docs/plans/entsoe-iberia-reproduction.md` §7.6 before treating any of it as
validation: voltage magnitude is constant behind a reactance here, so angle
instability is in scope and the final voltage collapse to blackout is not.

**The picture of one cell** is `ui/scripts/figure_3_67.jl` (M3 step 7), which
`include`s this file so the model and the twelve shed stages live in exactly one
place, and renders `docs/images/fig-3-67-two-area.png`. It lives under `ui/`
rather than here for this directory's own reason: it imports Makie, and nothing
in `scripts/` may.

## `low_inertia.jl`

M7 step 7's study: **what changes when the generation has no rotor.** M1's four units
(`example_system()`, field for field) on a seven-bus network in two layouts (a meshed
`:ring` and a `:chain`), displaced step by step by grid-following and by grid-forming
inverters at **matched dispatch** — every row of a sweep starts from the same operating
point — with a unit tripped at every step on the detailed tier. Two events (the user's
choice, `docs/plans/m7-context.md` D16): G1, the largest unit (38 % of the generation),
and G4, the smallest. Default (constant-impedance) loads. Four sections:

1. **Positive control** — zero share, constant-power loads: the network's
   instantaneous centre-of-inertia RoCoF at t⁺ against M1's own engine on the same trip,
   to ~1e-12 on both layouts.
2. **The sweeps** — per share: inertia online, RoCoF₀ by formula and by network, the
   500 ms windowed RoCoF from the centre of inertia and from PLL meters at every bus, the
   load relief and grid-following power change at t⁺ that account for the gap between
   the two RoCoF₀ columns exactly, nadir (`≤` when the frequency is still falling at the
   end — never reported as a nadir), voltage, governor reserve, grid-forming loading
   against rating, and synchronism; or the wall a refused cell hit.
3. **Anti-vacuity** — the grid-forming sweeps with τ_p → 0.001 s (virtual inertia ≈ 0).
4. **What the tables say** — five claims, written after both layouts' tables and each
   asserted in `test/m7_low_inertia.jl`. Three drafted before the tables did not survive
   them.

Read D16's "What the study measured" before quoting a number. The grid-forming rows run
with **no current limit** (D8) and most of them above their rating; the PLL column
includes the trip's own phase-jump spike, which no rotor felt.

## `outage_screen.jl`

M8 step 6's report: **every single outage, at both fidelities, side by side.** Each
line and each generator of two grids is taken out one at a time and screened with
the linear (DC) power flow — the shortcut real screening tools start from — and with
the full nonlinear (AC) one, and every place the two disagree gets a reason printed
beside it. The grids are case9 **without line charging** (the model has no shunts),
with **invented** droop and damping because published case9 has none, and M8 step 5's
invented five-bus mesh. Both run on constant-power and on the default
constant-impedance loads. Three sections:

1. **The one decision step 6 took** (`docs/plans/m8-context.md` D9, the user's
   choice): a line whose loss cuts off a generator sitting alone is screened as that
   generator's outage. Checked on the numbers — the line carries nothing in the
   generator's outage, and the bus it cuts off sits at its neighbour's voltage.
2. **The tables** — per outage: both verdicts, the class of disagreement, the most
   loaded branch against its rating at each fidelity, the settled frequency after a
   generator is lost, and why.
3. **What the tables say** — five claims, written after the tables and each asserted
   in `test/m8_outage_screen.jl`.

Read claim (d) before quoting a "secure": the screen judges line loading and voltage
only. It has no frequency criterion, and one "secure" row settles 10.9 Hz low.
