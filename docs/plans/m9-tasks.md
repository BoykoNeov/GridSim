# M9 — Tasks

The checklist. Companion to `m9-plan.md` (the how) and `m9-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **step 0 done (2026-10-08); step 1 next.** Entered at `7a32ae1` with M8's
close counts, **5316 core / 1262 reference / 568 UI** on re-resolved manifests; step
1 re-measures them before its first edit.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed*, not when the code
runs.

---

## Step 0 — hurdle taken, the dip measured, limits read, plan written (2026-10-08)

- [x] **Topic chosen by the user:** Hurdle 16 as M9 (`m9-context.md` D0).
- [x] **The dip measured before the plan named it** (D1; spike
      `W:\temp\claude\gridsim-m9\step0_dips.jl`, predictions first in
      `step0_predictions.md`). Dip 1.20–1.65× the settled value wherever governors
      stay uncapped; equal to it (monotone, ~100 s) where they cap; worst machine
      up to 7.7 % deeper than the COI dip; initial rate within 2–3 % of
      `ΔP/(2ΣHS)·f0`.
- [x] **Found, not planned — the dynamic tiers refuse line resistance**, so neither
      report fixture runs dynamically; the spike used lossless copies. Named as
      Hurdle 17.
- [x] **Found, not planned — a solver failure on one outage** (mesh-default G2:
      FBDF 1e-8 `Unstable`; three other settings agree to four digits). Named as
      Hurdle 16.5: never a verdict.
- [x] **Found at review, the same day — the refusal sets do NOT match.** The plan
      first claimed the detailed tier refused exactly the AC screen's `:voltage`
      outages; the spike had never printed the AC outcome for refused runs.
      Re-checked (`step0_refusals.jl`): case9-constant-power G2 is refused
      dynamically (B2 0.889 pu at the trip) and `:secure` in AC, lossless and lossy.
      D0 16.6 rewritten: a named "refused at the trip" outcome, reported not
      asserted empty. Two more review corrections in the same commit: the dip run
      stops on its own settling (default loads settle 12–23 % off the screen's
      value), the solver pair is frozen in the plan (FBDF 1e-6 / 1e-8, mesh-default
      G2 predicted to come back as a solver failure), and 17.4 became an identity in
      the losses rather than a band.
- [x] **The limits read from their sources** (D3): SO GL Annex III Table 1 (800 mHz
      dip, 200 mHz settled for Continental Europe, read from the page image);
      no area-wide sourced rate limit, so the preset carries none.
- [x] **The user's choices** (D2): settled + dip + rate; resistance taught to both
      dynamic tiers; limits required with a cited preset; a separate verdict.
- [x] Plan written against the hurdles (`m9-plan.md`); `docs/plans/README.md` row
      and hurdle list updated.

## Step 1 — line resistance in the detailed tier (Hurdles 17.1–17.4, 17.7)

- [ ] Entry counts re-measured at HEAD before the first edit.
- [ ] Captures at HEAD: M5 criterion values, 83-case AC digest, M8 screen outputs,
      step 0's lossless dip table.
- [ ] Edge current reads `R`; `branch_power` honest at both ends; refusal lifted
      for this tier only.
- [ ] Gate: all four captures bit-identical.
- [ ] Flat run from a lossy `ac_powerflow`.
- [ ] Settled lossy trip against the AC screen (constant power, uncapped): the
      losses identity of D0 17.4, not a band.
- [ ] `t⁺` identity with the losses term.
- [ ] Antisymmetry audit, list recorded.
- [ ] Sabotages, predictions first, each red where predicted; the shared-builder one
      recorded for step 3.

## Step 2 — line resistance in the swing tier (Hurdle 17.6)

- [ ] Conductance in the classical coupling, sparse; refusal lifted.
- [ ] Gate: captures and M8 step 4's swing-against-DC agreement bit-identical at `R = 0`.
- [ ] Frozen-flux detailed tier matches on a lossy network.
- [ ] Swing ≠ DC on a lossy grid by the losses alone, pinned.
- [ ] Sabotages.

## Step 3 — the outside check on both tiers (Hurdle 17.5)

- [ ] `PiLine` with `R`; band stated before the gap.
- [ ] Detailed tier and swing tier inside it on a lossy mesh.
- [ ] The sabotage only this check sees: red here, green in steps 1–2.

## Step 4 — the frequency verdict and its limits (Hurdle 16.1)

- [ ] Limits type; rate refused without a window; Continental Europe preset cited.
- [ ] Verdict beside each generator outcome, per screen; comparison class added.
- [ ] Gate: no limits → M8 bit-identical.
- [ ] Positive control, near-limit anti-vacuity, a DC/AC disagreement fixture.

## Step 5 — the dip (Hurdles 16.2–16.6)

- [ ] Per-machine running minimum in the engine.
- [ ] Stopping rule on the run's own settling, and "not reached".
- [ ] Frozen pair FBDF 1e-6 / 1e-8; mesh-default G2 (lossless) returns the
      solver-failure outcome as predicted.
- [ ] Step 0's table reproduced wherever the pair judges.
- [ ] "Refused at the trip" outcome; mismatch set reported (predicted lossless:
      case9-constant-power G2 only; lossy measured).
- [ ] Sabotages.

## Step 6 — the rate of fall (Hurdle 16.7)

- [ ] Windowed rate, COI and per machine; verdict names its read.
- [ ] Closed form at `t⁺`, gap direction predicted first.
- [ ] Sabotages.

## Step 7 — the report

- [ ] Both verdicts side by side on the lossy report grids; claim (d) revisited.
- [ ] Claims asserted at printed precision; prose after the table.
- [ ] Window: the user's call.

## Step 8 — close

- [ ] Re-resolve, counts, captures before/after, ledger, README, SPEC, memory.
