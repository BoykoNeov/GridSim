# M8 step 6 — predictions, written before the run they describe

Context: `W:\Claude_projects\GridSim\docs\plans\m8-context.md` (D9 to be written).
Everything above "Outcome" is written BEFORE the first run of the report. Outcomes
are appended underneath, never edited above.

## The decision (user's go-ahead 2026-10-07)

A bridge whose cut-off side holds exactly ONE machine and nothing else (no load, no
inverter of either kind) is screened as that machine's outage. Everything else stays
`:splits`. If both sides qualify (a grid of two lone machines), it stays `:splits`:
no one machine is "the" outage.

Why exact here: no shunt anywhere in `NetworkModel` (no line charging, no taps), so
once the machine is gone the cut-off side has zero injection, zero current, and every
bus on it sits at the voltage of the bridge's main end. Losing the bridge then changes
nothing the main grid sees. Checked, not assumed:
- C1: in the generator-outage AC solution, the mapped bridge carries |P|, |Q| at both
  ends ≤ 1e-10 pu (Newton abstol 1e-12; band 100× it for the flow formula's
  amplification by 1/X ≈ 17 on L14).
- C2: same in DC, ≤ 1e-12 (round-off of a solve against the Cholesky factor).
- C3: the far bus's |V| equals the near bus's within 1e-10.

## Mapping on case9 (by name)

L14 → G1, L36 → G3, L82 → G2. L82 is declared B8 → B2, so a rule assuming the source
sits at `from` gets exactly that one wrong (anti-vacuity mutation).

Declined fixtures: a pendant bus with a machine AND a load → `:splits`; a pendant
load bus (step 2's mesh, DE with load at E) → `:splits`; a pendant grid-following
inverter bus → `:splits`.

## Fixtures

- **case9 without line charging**, published R/X/ratings, published Pmax-share
  schedule at 315 MW, Q limits ±300 MVAr, V_set 1.04/1.025/1.025. INVENTED droop:
  S_rated = Pmax, R 0.05, D 1 (own base), H 5, Xd′ 0.2, E′ 1. Reference B1.
- **mesh**: step 5's `_m8_acmesh(r = 0.1)` (lossy), ratings 500 MVA.
- Both on constant power AND default (constant impedance) loads.

## Predicted table, case9, constant power

| outage | DC | AC | class |
|---|---|---|---|
| L14 (→G1) | secure | voltage (B4 low; B1 dead, dropped) | dc_blind |
| L45 | secure | voltage (B5 ~0.873) | dc_blind |
| L56 | secure | secure | agree |
| L36 (→G3) | secure | secure | agree |
| L67 | secure | secure | agree |
| L78 | secure | secure | agree |
| L82 (→G2) | secure | secure | agree |
| L89 | secure | secure | agree |
| L94 | secure | voltage (B9 ~0.757) | dc_blind |
| G1 | secure | voltage | dc_blind |
| G2 | secure | secure | agree |
| G3 | secure | secure | agree |

Bridge rows equal their machine rows field for field (except the dead-bus listing).
The dead-bus filter does NOT change any outcome (B1's |V| equals B4's).

DC Δω for G1 lost: P_lost 96.04 MW; Σg = (300+270)/100/0.05 = 114, Σd = 5.7 →
Δω = −0.9604/119.7 = −0.008023 pu (−0.401 Hz). AC Δω: same sign, magnitude
different by the loss change (a few %), not predicted closer.

## Predicted table, case9, default loads

Voltages sag less hard per MW (constant-impedance load draws less as |V| falls) but
still sag. Predict L94 still voltage; L45 UNCERTAIN (0.873 on constant power, may
pass the 0.9 band on default — not predicted either way); G1/L14 voltage (0.81 on
constant power). Everything else agree/secure.

## Predicted table, mesh (no bridges; the rule never fires)

All 7 line outages and 3 generator outages: secure at both fidelities, class agree,
on both load models. No bridge → nothing mapped (asserted, said in output).

## Outcome

(appended after the run)

## Sabotages — predictions (written before any ran)

Test file `test/m8_outage_screen.jl`. Testset names abbreviated.

- MU1 `near-side-only`: the rule looks only at the side of the branch's `from` bus.
  RED: "maps case9's three by name" (L82 lost), "declines…" (pendant CP: P is the
  `to` side; positive control and island=2 lose GP), "mapped row IS its generator's"
  (L82 loop), claim a (count 2, and L82 becomes :splits), claim b (:splits not in
  (:agree, :dc_blind)). Rule-check testset: L82 missing from rows → KeyError → red.
- MU2 `loads-ignored`: a load does not disqualify a side. RED: "declines…"
  (machine_and_load maps to GP), "mapped row…" (CP row of machine_and_load no longer
  :splits). case9 unaffected (its generator buses carry no load).
- MU3 `dead-bus-judged`: the cut-off buses are not filtered from `low`. RED: only
  "mapped row…" (B1 in L14's low; the equality line).
- MU4 `no-abs`: the generator comparison judges signed DC flows. RED: only the new L94
  line in "every class" (DC misses it → :dc_missed). Every other overload in the file
  runs along its declared direction — predicted GREEN elsewhere.
- MU5 `inverter-not-blind`: the generator comparison ignores a grid-forming inverter
  over its rating. RED: only the inverter line in "every class" (class → :agree).
- MU6 `bridge-row-from-lines`: outage_screen fills a mapped bridge from the line
  comparison (ignores `via`). RED: "mapped row…", claim a (`!any(:splits)`), claim b.

## Sabotage outcomes, first run

All six red. MU1, MU3, MU4, MU5, MU6 red exactly where predicted. **MU2 red, but not
where predicted**: the pendant fixture's main side held only G1, so with loads ignored
the main side was a lone source too, and the rule declined machine_and_load for the
wrong reason (both sides lone). It was caught by the positive control and the :load /
:inverter / :two_machines lines instead (the rule then mapped CP to G1).
Fix: a second, zero-output machine G0 on the main side. MU2 re-predicted: red ONLY at
the machine_and_load line of "declines…" and the split-row check of "mapped row…".
PREDICTED core 5268 / ref 1262 / ui 568
