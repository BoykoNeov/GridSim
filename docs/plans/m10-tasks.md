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
      red where registered. The inverter testset, added after them, got its own (S5,
      2026-10-19, prediction first): red there alone — through its explicit assertions, not
      the identity, which skips a piece that stopped solving.

## Step 4 — one event, one re-solve (Hurdle 20) — done 2026-10-19

- [x] Simultaneous event in the detailed tier (and the swing tier): `TripElements`, one
      re-solve of the final network; the swing tier's is the single trips back to back plus the
      graph's answer, bit for bit step 2's hand lists (`m10-context.md` D10).
- [x] Dead buses de-energised by the graph, both load models — grounded through their own
      load slot (`V = 0` exactly; a deviation from "out of the solve", recorded in D10). Found on
      the way: the exciter's `hypot` at zero aborted the run (`_exciter_vmag`).
- [x] Refused event changes nothing — decided by measurement: on the direct `inject!` the run
      on is its never-asked twin bit for bit (`_refusable!`; `TripLine` and `TripGenerator`
      through it too); on the out-of-step relay's path the engine and the relay's record are
      put back but the run STOPS (`halted`), because continued it silently loses the protection
      (`step4_relay_probe.jl`).
- [x] A generator cut off alone tripped in the same event — case9 L36 alone IS G3's outage,
      every survivor within 1e-9.
- [x] Positive control: case9 default L45+L67 runs (and its single first trip is refused,
      leaving nothing behind).
- [x] Per-piece settled frequency against step 3, through M9's losses identity per piece,
      carrying the loads' draw: constant power L56+L78 and L45+L56's rest; default L45+L67,
      L56+L78, L67+L89, L45+L56's rest — rtol 1e-6, whole-grid Σw and losses fail it. Constant
      power L45+L67 and L67+L89 are refused at the trip instant in this tier (D10). Run on
      Rodas5P: FBDF collapses, isolated, where a bus is grounded (`step4_settle_probe.jl`).
- [x] Sabotages run, predictions first (`step4_predictions.md`, two dated notes before any
      ran): all six red where registered; S2 and S3 also red on every L45+L56 testset, the
      intermediate/stranded network step 0 measured (D10).
- [x] Gate: M9's seven captures byte-identical (digests in D10). Suites 16525 core / 1439 ref
      / 745 UI, done 2026-10-19.
- [x] (On review, after the commit) the inverter half: a tripped grid-forming inverter is
      no source, a grid-following one goes with its piece; sabotage S7 red there alone.

## Step 5 — fail, restore, fail again (Hurdle 21) — done 2026-10-19

- [x] Decisions recorded before the code (`m10-context.md` D11): one restored model per live
      piece; the restore is the bend walk with damping zeroed, mirrored downward to `Pmin`; a
      grid-forming inverter capped at its rating (a refinement of D3); exact endpoints; the
      restored model's slack; what an ordered pair reports.
- [x] Refactor: the pair loops' bodies take any set of one or two elements
      (`_dc_outage_set`/`_ac_outage_set`), both screens byte-identical on eight fixtures.
- [x] Restored schedule per piece, exact (`dc_restore`/`ac_restore`); its refusal
      (`:restore_refused`, the mesh's G1); `Pmin` honoured; units below zero flagged, after the
      restore and after the settle. AC: the restored model's slack carries the balancing
      schedule (found by the first trial, D11.5); losses identity and `ac_powerflow`'s give-back
      on every restored piece.
- [x] Second loss = the pair screens' one-element case on the restored model — stated, by
      construction (`dc_sequential_outages`/`ac_sequential_outages`).
- [x] A-then-B, B-then-A, both-at-once tabulated (`step5_pairs.out.txt`); claim written after:
      the orders differ by what the first loss alone would settle to — exact in DC, exact to the
      solver in AC on case9 (equal D·R), to 5e-4 on the mesh.
- [x] Detailed-tier check from the restored model — nine pieces, ≤ 1.4e-9 relative through the
      per-piece identity; constant-power L78→G2 / L89→G2 refused at the trip in this tier.
- [x] Sabotages run, predictions first: all five red where registered; four unpredicted reds or
      greens explained (`m10-context.md`, "What step 5 measured").
- [x] Suites 19151 core / 1439 ref / 745 UI. M9's captures not re-run: step 5 touches no
      code they call (`screening.jl` untouched; the refactor gated byte for byte).

## Step 6 — the report — done 2026-10-19

- [x] Decisions recorded before the code (`m10-context.md` D12): a refused piece keeps no
      flags; the verdict per piece and its five names; one colour per pair (amended the same
      day on a note the user forwarded: customers cut off is never green — amber); DC printed
      once; no per-pair traces.
- [x] The screens' one fix (D12.1, `_ac_outage_set`): gated by 32 serialized screens, the 64
      moved entries all named (`step6/snapshot.out.txt`); sabotage F1 red where predicted.
- [x] Script `scripts/double_outage_screen.jl`: both grids, DC once and AC on both load models,
      both timings, per piece, the settled verdict with the preset's caveat.
- [x] Claims k–q written after the tables, asserted at printed precision (`test/m10_report.jl`).
      A no-state sequential pair judged at its restored 0.0 was found by looking at the window
      and fixed (claim q's counts 58/60 → 28/25) before any sabotage ran.
- [x] Window (the user's choice): `ui/src/double_outage_window.jl`, the eighth; figure
      `docs/images/fig-m10-double-outages.png`.
- [x] Sabotages, predictions first: F1, R1–R5, W1–W4 all red exactly where registered.
- [x] Suites 24360 core / 1439 ref / 3413 UI (19151 + 469 + 4740 core; 745 + 2668 UI); after
      the review's additions 24361 core / 3418 UI by count (focused runners green). M9's
      captures not re-run: step 6 touches no code they call (`screening.jl` untouched; the
      one change is in M10's `_ac_outage_set`, gated by `step6/snapshot.out.txt`).

## Step 7 — close

- [ ] Manifests re-resolved, counts re-measured, captures before and after.
- [ ] Ledger, README row and hurdles, `SPEC.md`, memory.
