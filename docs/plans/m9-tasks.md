# M9 — Tasks

The checklist. Companion to `m9-plan.md` (the how) and `m9-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **steps 0–3 done (2026-10-08/09); step 4 next.** Entered at `7a32ae1` with M8's
close counts, **5316 core / 1262 reference / 568 UI** on re-resolved manifests,
re-measured at `40b9acf` before step 1's first edit (same three numbers); after step 1
**5453 core / 1262 reference / 568 UI**; after step 2 **5605 core / 1262 reference / 568 UI** (+151 step-2 checks, +1 from the reworked M6 refusal test, −2 + 3 there; reference unchanged and not re-run for the review follow-up, which touched no reference code). Reference re-measured at `037c935` before step 3's first edit: 1262. After step 3 **5605 core / 1439 reference** (+177 step-3 checks; core count unchanged — the M6 refusal test now reaches the guard through `coi_model`, one `@test` for one); UI not re-run (no `ui/` change, core changed in docstrings only).

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed*, not when the code
runs.

---

## Step 0 — hurdle taken, the dip measured, limits read, plan written (2026-10-08)

- [x] **Topic chosen by the user:** Hurdle 16 as M9 (`m9-context.md` D0).
- [x] **The dip measured before the plan named it** (D1; spike
      `docs/evidence/gridsim-m9/step0_dips.jl`, predictions first in
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

## Step 1 — line resistance in the detailed tier (Hurdles 17.1–17.4, 17.7) — done 2026-10-08

- [x] Entry counts re-measured at HEAD (`40b9acf`) before the first edit: 5316 / 1262 /
      568, M8's close counts (the commits since were docs only).
- [x] Captures at HEAD, `docs/evidence/gridsim-m9/step1/*-HEAD.txt`: M5's criterion
      values and the 83-case AC digest (both byte-identical to M8's close captures as
      well), every field of `outage_screen` on both report grids and both load models
      (`screen_snapshot.jl`, new), step 0's lossless dip table at full precision
      (`dips_snapshot.jl`, new — same runs, `repr` instead of four decimals).
- [x] Edge current `(Vf − Vt)/(R + jX)` in both compiled networks (`R` appended to the
      edge parameters, written into both); `AntiSymmetric` kept — a series branch
      with no shunt carries one current; `branch_power`/`branch_power_series` read
      the receiving end as `Re(V_to·conj(−I))`; `branch_topology` carries `R`; the
      refusal lifted for this tier only (`_assert_lossless_branches` now names the
      classical tier and `build_oracle` as what is left).
- [x] **Gate: all four captures byte-identical** after the change. **Anti-vacuity
      (S6):** with the edge equation's `R = 0` path removed, 86 of the 169 criterion
      values move in their last digits. The current read-out's identical path moved
      none (S6b) — dividing by `complex(0, X)` IS dividing by `im·X` — so it was
      deleted at review; the receiving-end read's path is needed and is gated by no
      capture (D5).
- [x] Flat run from a lossy `ac_powerflow`: both report grids, both load models, two
      tolerances, worst drift 4.2e-13 per state (gate 1e-10).
- [x] Settled lossy trip against the AC screen: the identity holds to 4e-14 on case9
      G3 (gap 3.0e-5 pu) and 5e-14 on mesh G3 (2.8e-5 pu) at 400 s. **Only two
      outages qualify:** case9 G1/G2 are refused at the trip and the mesh's G2 caps
      G3's 5 MW of headroom (not foreseen by the plan).
- [x] `t⁺` identity with the losses term: four outages (case9 G3, mesh G1–G3),
      residual ≤ 6.7e-14 against a losses change of 1.9e-3 to 1.7e-2 pu.
- [x] Antisymmetry audit, list recorded (`m9-context.md` D5).
- [x] Sabotages, predictions first (`docs/evidence/gridsim-m9/step1/predictions.md`),
      each red where predicted, with one prediction wrong in the safe direction and
      one check found too lenient and tightened (D5). Nothing is shared with the
      power flow's admittance code — but **corrected at review**: a resistance misread
      the same way in both is green in every step-1 check, so that consistent
      two-site sabotage is step 3's mutation (D5).

## Step 2 — line resistance in the swing tier (Hurdle 17.6) — done 2026-10-08

- [x] Entry counts: 5453 / 1262 / 568, step 1's close (core measured on the `c81cf79`
      tree, `docs/evidence/gridsim-m9/step1/core-STEP1b.log`; reference and UI on
      `666b857`, whose follow-up `c81cf79` changed no test).
- [x] Captures at HEAD (`c81cf79`) before the first edit,
      `docs/evidence/gridsim-m9/step2/*-HEAD.txt`: step 1's four (each byte-identical
      to step 1's own) plus a new full-precision swing-tier capture
      (`swing_snapshot.jl`: seven fixtures including M8 step 4's mesh, every generator
      and line trip, both ends of every branch, `coi_rocof`, one playback series).
- [x] **Found at orientation, not planned — the slack.** A lossy grid has no steady
      state at this tier (fixed `Pm`, a schedule summing to zero). The model's
      reference bus picks up the losses, the detailed tier's rule, through a static
      solve before the dynamic fixpoint; headroom stays `Pmax − P0`; a grid-forming
      inverter as a lossy model's reference is refused by name (D6).
- [x] Conductance in the classical coupling, built edge by edge (no matrix); every
      branch of a lossy model takes the two-ended edge, self terms by the GRAPH edge's
      ends; a lossless model compiles exactly as before; refusal lifted
      (`_assert_lossless_branches` left with `build_oracle` alone). The reach guard
      takes its lossy, asymmetric form.
- [x] **Gate: all five captures byte-identical** but for one line — found, not planned:
      `branch_power_series` ignored the caller's order on a lossless model; fixed, and
      that line differs by an exact negation. **Anti-vacuity (S6):** with the lossless
      path removed, 225 of 312 swing-capture lines and 3 of 182 criterion lines move.
      M8 step 4's swing-against-DC agreement is inside the swing capture (the mesh,
      every outage) and in the suite unchanged.
- [x] Frozen-flux detailed tier matches on a lossy network: dispatch to 1e-12 first,
      then four channels inside `convergence_band` at two tolerances, each end of the
      pair as reference. `terminal_bus_reduced` had been dropping `R` and the
      reference — fixed and asserted.
- [x] Swing ≠ DC on a lossy grid by the losses alone, pinned as an identity:
      `(L_pre − L_post − [reference lost]·L_pre)/Σw`, three outages including the
      reference's, rtol 1e-6, gap > 10³ × residual.
- [x] Each end against a formula sharing no code (1e-13); dispatch (`==` off the
      reference, losses to 1e-12); flat start (residual < 1e-13, drift falling with
      tolerance — first written at 1e-10 and wrong: the lossless twin drifts as much);
      both ends of a dead branch exactly zero.
- [x] Sabotages S1–S6, predictions first, every one red somewhere; S3's refusal was
      the solver library's and is now the tier's own (D6).
- [x] **Found at review:** `coi_model` accepted a lossy model in silence — now refused
      by name; the antisymmetry audit for this tier recorded (D6, findings 5–6).

## Step 3 — the outside check on both tiers (Hurdle 17.5) — done 2026-10-09

- [x] Entry count at HEAD (`037c935`): 1262 reference. Six captures at HEAD before the
      first edit — step 2's five plus `oracle_snapshot.jl` (eight lossless oracle runs,
      every channel; copy in `docs/evidence/gridsim-m9/step3/oracle-HEAD.txt`) — all
      **byte-identical after**.
- [x] `PiLine` handed `Branch.R` at `:swing` and `:sauer_pai`; `:classical` and
      `:sauer_pai_avr` refuse it by name; transformer ratios passed explicitly.
      **Found at orientation:** the swing-tier seed handed PowerDynamics the schedule,
      not our loss-carrying dispatch — fixed, with control C2 (0.10 Hz off if undone).
- [x] Swing tier on the lossy ring: flat to 4e-16; a line trip and a generator trip
      inside `convergence_band` (gap 0.25–0.30 of it) on the COI, an angle difference
      and every surviving speed; the lossless run lands 6e6–1e8 bands away. C1 (their
      `R` zeroed) moves the angle 1e-2.
- [x] Detailed tier on the lossy ring: flat to 9.5e-15 per state at two tolerances;
      C1 moves `V_B1` 2.7e-3. **Not "inside the band" as planned** — its transient is
      outside one by design (the stator-ω residual, M5 step 3); judged instead by that
      residual's signature, which holds (coefficient 1.014–1.015).
- [x] Sabotages T1–T5, predictions first (`docs/evidence/gridsim-m9/step3/`): every
      `src/`-only misreading of `R` is red in-house somewhere (cross-tier, the test's
      own end formula, the losses' positivity, or by refusal); **T5 — the same ×1.1
      misreading in every reader, the test formula included — is seen by no in-house
      identity, comparison or formula, and is red here on both tiers.** Its one
      in-house red is case9 G1's re-initialisation stalling instead of being refused by
      name (an outage refused at HEAD anyway) — a convergence failure, not detection.
      Two predictions wrong (T1's step-1 identities red by refusal; T4 caught by the
      positivity checks), recorded in D7.
- [x] **Carried to step 5:** a detailed-tier re-initialisation that stalls surfaces as
      the library's `NetworkInitError`, not the tier's refusal (D7 finding 2).

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
- [ ] **Carried from step 3 (D7 finding 2):** a detailed-tier re-initialisation that
      STALLS after a trip comes out as a solver-failure outcome, distinct from the named
      voltage-band refusal — today it surfaces as the library's `NetworkInitError`.
      Reproducer: case9 G1 on constant-power loads with `R` ×1.1 (`step3/mutate.py`
      T1b; `step3/probe_trip_refusals.jl`).

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
