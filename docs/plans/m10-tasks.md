# M10 — Tasks

The checklist. Companion to `m10-plan.md` (the how) and `m10-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **step 0 done (2026-10-18); step 1 next.** Enters at M9's close counts,
**6718 core / 1439 reference / 745 UI** on re-resolved manifests — to be re-measured
at HEAD before step 1's first edit.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed*, not when the code
runs.

---

## Step 0 — topic chosen, pairs measured, hurdles named, plan written (2026-10-18)

- [x] **Topic chosen by the user:** double outages (`m10-context.md` D0).
- [x] **Every line pair classified before the plan named anything** (D1;
      `docs/evidence/gridsim-m10/step0_census.jl`). case9: all 36 split — 9 into two
      live pieces, 3 strand a load, 24 cut off a lone generator. Mesh: 19 connected,
      2 cut off a lone generator. A reviewer's prediction from topology matched all
      six counts.
- [x] **The detailed tier run on two simultaneous case9 line trips** (D1;
      `step0_islands_spike.jl`). Found, not planned: the intermediate one-line
      network is refused where the final one passes (Hurdle 20.1); a refused
      `TripLine` is half-applied (20.2, predates M10); a stranded load bus is
      solved to 1.8e9 pu or 0.0 pu depending on the load model (20.3).
- [x] **Read before writing:** M8's pickup solve already shares a surplus, with no
      down-floor, as the swing tier (Hurdle 19.1); the swing tier's `TripLine`
      re-solves nothing, so two at one instant are one event there (19.2).
- [x] **The user's choices** (D2): both timings; lines and generators; solve each
      piece; restore 50 Hz between failures. The restore proportion (governor gain)
      named in D3.
- [x] Plan written against the hurdles (`m10-plan.md`); `docs/plans/README.md` row
      and hurdle list updated; `SPEC.md` §9 item 8 annotated.

## Step 1 — two-line DC factors, cut pairs from the graph (Hurdles 18.1–18.3)

- [ ] Entry counts re-measured at HEAD before the first edit.
- [ ] M8 captures at HEAD (screen outputs on both report grids, both load models).
- [ ] Rank-two update on M8's factorisation; cut pairs from the graph.
- [ ] Gate: M8 captures bit-identical.
- [ ] Exact against rebuild-and-re-solve on the mesh's 19 connected pairs.
- [ ] The additive shortcut's error measured; zero on a non-crossing control.
- [ ] Cut set = the rebuild's refusals (case9 36, mesh 2); `det M` shown as round-off.
- [ ] Near-cut band stated in `step1_predictions.md` before the run; scaling seen.
- [ ] Sabotages run (transposed `M`, diagonal `M`, wrong column), predictions first.

## Step 2 — pieces, and generators, in DC (Hurdles 18.4, 19.1–19.4)

- [ ] Every pair kind; per-piece sharing; load lost; sources cut off; D4's collapse.
- [ ] Brute force per piece.
- [ ] Swing tier per piece, band stated first; one piece up, one down; a stranded load.
- [ ] Order-independence on every pair, with a capping fixture as the control.
- [ ] Sabotages run, predictions first.

## Step 3 — pairs and pieces in AC (Hurdle 19.5)

- [ ] Shared reference per piece; outcomes per piece; DC-vs-AC per pair by ID.
- [ ] Degenerations: connected pair = `ac_powerflow`; whole-grid piece = M8's solve.
- [ ] Lossless 1-pu rung against step 2.
- [ ] Both load models.
- [ ] Sabotages run, predictions first.

## Step 4 — one event, one re-solve (Hurdle 20)

- [ ] Simultaneous event in the detailed tier (and the swing tier).
- [ ] Dead buses de-energised by the graph, both load models.
- [ ] Refused event changes nothing (or the engine refuses to run on) — decided by
      measurement; `TripLine`'s half-applied refusal fixed.
- [ ] Positive control: case9 default L45+L67 runs.
- [ ] Per-piece settled frequency against step 3, through M9's losses identity.
- [ ] Gate: M9's captures bit-identical.

## Step 5 — fail, restore, fail again (Hurdle 21)

- [ ] Restored schedule per piece, exact; its refusal.
- [ ] Second loss = M8's screens on the restored model.
- [ ] A-then-B, B-then-A, both-at-once tabulated; claim written after.
- [ ] Detailed-tier check from the restored model.
- [ ] Sabotages run, predictions first.

## Step 6 — the report

- [ ] Script, both grids, both load models, both timings, per piece, both fidelities,
      settled verdict with the preset's caveat.
- [ ] Claims asserted at printed precision; prose after the table.
- [ ] Window: the user's call.

## Step 7 — close

- [ ] Manifests re-resolved, counts re-measured, captures before and after.
- [ ] Ledger, README row and hurdles, `SPEC.md`, memory.
