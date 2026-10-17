# M9 step 6 — predictions, written before any new code ran (2026-10-17)

Step 6 adds the rate of fall: the windowed rate of change of frequency after each
generator outage, read from the dip step's own runs (no new simulation), judged against
a caller-supplied limit and its window. Entered at `65e21b1`.

## Decisions fixed BEFORE any run (recorded in `m9-context.md` D10)

1. **What is judged: every surviving machine's own frequency — the user's choice
   (2026-10-17)**, asked before any rate was measured. The worst machine's windowed rate
   is judged; the centre-of-inertia (COI) rate is reported beside it, never in its place.
   Same rule as the dip (D9 rule 1). The verdict carries a field naming the read
   (`:worst_machine`) and the window is the limit's own.
2. **The runs keep their traces; the window is applied at judgement.** `generator_dips`
   stores, per measured outage and per tolerance, the output-grid samples of the COI
   frequency and every machine's frequency (Hz). The window comes from
   `FrequencyLimits.rate_window` at verdict time, so runs and limit cannot disagree on
   it and one set of runs serves any window. Nothing new is integrated.
3. **Differenced by `windowed_rocof`, never a second differencer.** On the 0.01 s output
   grid, the window must be a whole number of samples (refused otherwise, by name — a
   0.005 s window would silently become 0.01 s), and it is handed to `windowed_rocof`
   half a sample short, so the sample one window back is found whatever the grid's
   rounding (otherwise `t[i] − w` can round below the grid point and the read reaches
   one sample further, a bias that grows as the window shrinks). The divisor stays the
   actual span. The test checks each judged span equals the window.
4. **Which windows count:** every window ending after the trip, including those that
   straddle it (what a relay sees). The rate is the largest `|windowed rate|`, kept
   signed. Per machine, only the survivors.
5. **A decimated trace is never differenced.** The recorder halves its samples when it
   fills, which would widen every window silently. `generator_dips` refuses up front a
   horizon whose run could fill it, and the trace read refuses a decimated recorder.
6. **Same agreement rule as the dip:** `:pass` only where both tolerances' worst machine
   is within the limit, `:fail` only where both exceed it, `:tolerance_dependent`
   otherwise; a run that measured nothing passes its own outcome through.
7. **"A limit without a window is refused"** was built at step 4 (`FrequencyLimits`);
   step 6 relies on it and adds nothing there.

## Predicted

- **Gate:** the engine is not touched, so step 5's capture set stands; the five
  captures are still re-run before and after.
- **Closed form at t⁺ (COI, constant-power loads, lossy):** the instantaneous COI rate
  is `−(P_lost + ΔL)·f0/(2ΣHS)`, step 1's identity (ΣHS from the raw `Machine` fields,
  `H·S_rated/S_base`, survivors only; ΔL the change in losses across the trip).
  **Gap direction: the windowed COI rate is SMALLER in magnitude than the closed form
  at every window,** because damping (first order in t) and the governors (second
  order: the governor's output starts with zero slope) both oppose the fall from the
  first instant. **Size:** at 500 ms, 5–25 % below the closed form; the gap shrinks
  roughly in proportion to the window (first order, halving the window roughly halves
  it, ratio 1.7–2.3 between 0.04 and 0.02 s), and at 10 ms it is within 0.5 %.
  **Stated risk:** the losses swing with the inter-machine oscillation, so the COI rate
  is not monotone after the trip; a window starting later could read larger than the
  first one. If that happens it is a finding, not a tolerance to widen.
- **Step 0's lossless RoCoF₀** (over a 0.1 s read): case9 cp G3 0.935, mesh cp G1 3.60,
  G2 0.771, G3 0.468 Hz/s. The lossy closed-form values land within 5 % of these.
- **Per machine:** in every window lying wholly after the trip the COI rate is the
  inertia-weighted average of the machines' rates (an identity, the COI weights being
  fixed after the trip), so `|worst| ≥ |COI|` on every measured row. At 500 ms the
  worst machine reads 0–30 % above the COI (the inter-machine swing, ~1 s period, is
  partly averaged by the window).
- **Verdicts on the report grids, at 1 Hz/s over 500 ms (an illustration, not a
  sourced limit):** the mesh's G1 fails on both load models; every other measured row
  passes; case9's three refusals carry their refusal. At 2.5 Hz/s over 1 s (NC HVDC's
  numbers, for HVDC systems only): the mesh's G1 still fails at constant power
  (closed form ≈ 3.6 Hz/s), and may pass on default loads (load relief).

## Sabotages — predicted before any ran (`mutate.py`; focused run = steps 4–6 testsets)

| | Sabotage | Predicted red (testsets) |
|---|---|---|
| R1 | the verdict reads 500 ms whatever the limit says | the window control in "the verdict" (1 s passes → fails) — 1 |
| R2 | `H` left on the machine base (`machine_arrays`) | "t⁺" (engine against the raw-field formula, 4 rows) and the inertia-weighted-mean identity; step 5's pinned table moves too — many |
| R3 | the lost machine's inertia kept in the COI weights | "t⁺" (COI rate scaled by ΣH_left/ΣH_all) and the identity; step 5's COI dips — many |
| R4 | `abs` dropped in the pair verdict | every `:fail` expected on a falling rate or dip — several |
| R5 | the half-sample guard dropped | "the windows" by-index `===` read, **at some windows only** (depends on the grid's rounding) — uncertain, may be green |
| R6 | the COI rate judged in place of the machines | "every machine judged" (worst ≠ its machine's rate; the between-limit verdict passes) — 2–3 |
| R7 | only the fine run judged | the `:tolerance_dependent` assertion, rate and dip — 2 |
| R8 | a run that measured nothing passes | the refused rows' `:refused_at_trip`, rate and dip — 2+ |
| R9 | a window off the grid accepted | the 0.015 s refusal — 1 (0.005 still refused: it rounds to zero samples) |
| R10 | the horizon check dropped | the `horizon = 1e5` refusal — 1 (the run then just settles) |
| R11 | the decimation guard dropped | the capacity-16 refusal — 1 |

## Outcomes (appended after the runs, 2026-10-17; table in `rates_table.jl`)

- **Gap direction: held.** The windowed COI rate is below the closed form in magnitude
  on all four constant-power rows at every window from 1 s to 10 ms. The stated risk
  (a later window reading larger, from the losses swinging) did not happen.
- **Size at 500 ms: held** — 9.4 % (case9 G3), 19.9 / 15.0 / 18.4 % (mesh G1/G2/G3),
  inside 5–25 %. At 1 s, 28–47 %.
- **First order: held at the bottom of the sweep** — gap(20 ms)/gap(10 ms) = 2.12–2.19.
  Higher up the ratio is larger than 2 (2.2–2.3 from 40 to 20 ms, 2.7–2.8 from 200 to
  100 ms): the gap grows faster than the window there, the governors' second-order term.
- **At 10 ms: held** — 0.053–0.128 % below, inside 0.5 %.
- **Lossy closed form against step 0's lossless RoCoF₀: WRONG on one row.** case9 G3
  0.951 against 0.935 (+1.7 %), mesh G1 3.746 against 3.60 (+4.1 %), G2 0.790 against
  0.771 (+2.5 %), **G3 0.497 against 0.468 (+6.1 %)** — past the predicted 5 %. Two
  things move the same way here: the losses (the change in losses adds to the lost
  power) and step 0's read (over 0.1 s, so already ~1–2 % shallower than t⁺).
- **Per machine: held, at the low end** — the worst machine reads 0.1–4.0 % above the
  COI at 500 ms. **Not predicted:** at short windows it reads up to 52 % above it
  (mesh G2/G3 at 10 ms, both load models), the inter-machine swing undamped by any
  averaging — so the choice of the per-machine read matters most where the window is
  short.
- **Verdicts: held.** 1 Hz/s over 500 ms: the mesh's G1 fails on both load models
  (3.09 and 2.65 Hz/s), every other measured row passes, case9's refusals carry
  `:refused_at_trip`. 2.5 Hz/s over 1 s: the mesh's G1 fails at constant power
  (2.63) and passes on default loads (2.17).
- **The two tolerances** agree to ~5e-6 Hz/s at worst; no verdict above splits.
