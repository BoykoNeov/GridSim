# M10 — Tasks

The checklist. Companion to `m10-plan.md` (the how) and `m10-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **steps 0–3 done (step 3 2026-10-19); step 4 next.** Entered at M9's close counts,
**6718 core / 1439 reference / 745 UI**, re-measured at HEAD (`a9ec5bd`) before step 1's
first edit — unchanged. Step 1 leaves **6905 core / 1439 reference / 745 UI**; step 2
(entered at those, re-measured at `8889b86`) leaves **14479 core / 1439 / 745** — the
14479 predicted from the focused run before the suite ran. Step 3 (entered at those,
re-measured at `65d349f`) leaves **16351 / 1439 / 745**, also predicted first.

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
- [x] **Plan reviewed after its first commit (`c053b8b`)** and corrected the same
      day (D6): two checks that hold by construction moved to dynamic runs, per-piece
      read-outs, the swing tier's blindness to a lost load, the relay path, `Pmin`.
- [x] Plan written against the hurdles (`m10-plan.md`); `docs/plans/README.md` row
      and hurdle list updated; `SPEC.md` §9 item 8 annotated.

## Step 1 — two-line DC factors, cut pairs from the graph (Hurdles 18.1–18.3) — done 2026-10-18

- [x] Entry counts re-measured at HEAD before the first edit: 6718 / 1439 / 745, as M9
      closed. (One capture, `criterion`, first died on a full paging file at HEAD and was
      re-run before any edit.)
- [x] M8 captures at HEAD: M9's harness, all six (`swing criterion ac screen dips
      verdict`), which include every M8 screen output on both report grids and both
      load models.
- [x] Rank-two update on M8's factorisation; cut pairs from the graph
      (`dc_line_pair_outages`, `src/steadystate/double_outages.jl`). What is held is a
      branches × branches table, never the bus-indexed PTDF (`m10-context.md` D7).
- [x] Gate: all six captures byte-identical after. `dc_line_outages` is not edited, so
      this holds by construction (D7); a test ties the pair code's copy of the
      per-branch solve to M8's numbers with `===`.
- [x] Exact against rebuild-and-re-solve on the mesh's 19 connected pairs: 0.005–0.119
      of the band.
- [x] The additive shortcut's error measured: outside the band on all 19 mesh pairs
      (9.8e11–2.5e13 × it); within it on the control's 9 cross pairs (two triangles
      sharing a bus).
- [x] Cut set = the rebuild's refusals (case9 36, mesh 2); `det M` at every cut ≤ 2.6e-16,
      of both signs and zero.
- [x] Near-cut band stated in `step1_predictions.md` before the run; error ∝ 1/|det M|,
      0.005 of the band at Xw = 1e3, 1e5, 1e7. **Found:** the rebuild is not the oracle
      there when the reference sits on the nearly cut-off bus (it drifts 4× more than
      the factors); the closed form is, and the test asserts the attribution.
- [x] Sabotages run (transposed `M`, diagonal `M`, wrong column, plus a bridge-only cut
      test), predictions first: all red where registered; the diagonal one also reddens
      the cut check (unpredicted, in our favour).

## Step 2 — pieces, and generators, in DC (Hurdles 18.4, 19.1–19.4) — done 2026-10-18

- [x] Entry counts re-measured at HEAD (`8889b86`) before the first edit: 6905 / 1439 /
      745, as step 1 left them.
- [x] Every pair kind; per-piece sharing; load lost; sources cut off; D4's collapse
      (`dc_pair_outages`, `m10-context.md` D8). Kinds on case9 as predicted. **Found:**
      a whole grid can be dead (genmesh LB+LD), and the mesh's AB+AC is G1's outage in
      frequency but not in flows (a loop flow through A) — both asserted.
- [x] Brute force per piece: every live piece on six fixtures (75, 45, 162, 65, 5, 1,
      measured after and held exactly). Collapsed pairs and the four "G1 and G2 gone"
      paths equal to round-off.
- [x] Swing tier per piece, band 1e-7 stated first: ≤ 5.5e-10 on speed, ≤ 2.0e-8 on
      export change (governor gain × the speed gap); the gap shrinks with the solver
      tolerance, so it is the solver's. One piece up, one down (L45+L67); a lone cut-off
      generator tripped in the same instant; a stranded `P0 < 0` machine left running and
      excluded by name.
- [x] Order in the swing tier: ≤ 4.2e-8 against 1e-7, every pair kind (two lines, two
      machines, a line and a machine, a load-machine); the cap binds to 9.1e-11.
- [x] Sabotages run, predictions first (with a dated correction written before they
      ran): all four red where registered; S4 by design only on the classification and
      the count.

## Step 3 — pairs and pieces in AC (Hurdle 19.5) — done 2026-10-19

- [x] Entry counts re-measured at HEAD (`65d349f`) before the first edit, in a detached
      worktree so the edits could not leak in; the six M9 captures taken at HEAD first.
      14479 / 1439 / 745, as step 2 left them. **Predicted before the suite ran: 16351 core** (14479 +
      1871 from the focused run + 1 more function walked by M7's surface check), reference
      and UI unchanged. **Measured: 16351 / 1439 / 745.**
- [x] Own reference, frequency and reactive limits per piece, one Newton solve per live
      piece; outcomes per piece; DC-vs-AC per pair by id (`ac_pair_outages`,
      `compare_pair_screens`; `m10-context.md` D9). M8's shared solve generalised in place,
      not copied.
- [x] Gate: the six captures byte-identical after.
- [x] Degenerations: a connected line pair IS `ac_powerflow` on the rebuilt model (by
      construction, stated); the three collapsed pairs are M8's single AC outage within
      1e-10, both load models. Four paths to "G1 and G2 gone" agree within 1e-10 —
      **found:** none of them solves (no convergence on constant power, `:voltage` on default).
- [x] Per-piece losses identity on every live piece that solved, both grids, both load models.
- [x] Lossless rung: Δω and pickups = step 2's within 1e-10; A0 (every bus at 1 pu): tree
      pieces' flows = DC's, meshed ones carry a loop flow.
- [x] Both load models throughout. **Found:** the mesh's AB+AC differs from G1's outage in
      AC frequency with the sign set by the load model (the prediction had reason and sign
      wrong).
- [x] Inverter pieces (step 2's two triangles): kinds agree with DC, identity on every piece
      that solved, a grid-forming inverter as a piece's only responder off the reference.
- [x] Sabotages run, predictions first (with a dated correction before they ran): all four
      red where registered. (Run before the inverter testset was added; the sabotages
      have not been run against that testset.)

## Step 4 — one event, one re-solve (Hurdle 20)

- [ ] Simultaneous event in the detailed tier (and the swing tier).
- [ ] Dead buses de-energised by the graph, both load models.
- [ ] Refused event changes nothing (or the engine refuses to run on) — decided by
      measurement; `TripLine`'s half-applied refusal fixed; tested on the direct
      call AND the out-of-step relay's path.
- [ ] A generator cut off alone tripped in the same event.
- [ ] Positive control: case9 default L45+L67 runs.
- [ ] Per-piece settled frequency against step 3, through M9's losses identity
      taken per piece (`Σw`, losses, settling).
- [ ] Gate: M9's captures bit-identical.

## Step 5 — fail, restore, fail again (Hurdle 21)

- [ ] Restored schedule per piece, exact; its refusal; `Pmin` honoured when given;
      units below zero output flagged.
- [ ] Second loss = M8's screens on the restored model — stated, by construction.
- [ ] A-then-B, B-then-A, both-at-once tabulated; claim written after.
- [ ] Detailed-tier check from the restored model — Hurdle 21's only independent
      check, not cuttable.
- [ ] Sabotages run, predictions first.

## Step 6 — the report

- [ ] Script, both grids, both load models, both timings, per piece, both fidelities,
      settled verdict with the preset's caveat.
- [ ] Claims asserted at printed precision; prose after the table.
- [ ] Window: the user's call.

## Step 7 — close

- [ ] Manifests re-resolved, counts re-measured, captures before and after.
- [ ] Ledger, README row and hurdles, `SPEC.md`, memory.
