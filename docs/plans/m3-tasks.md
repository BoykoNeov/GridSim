# M3 — Task checklist

Checklist for the Milestone 3 batches. See `m3-plan.md` for the approach and
`m3-context.md` for the decisions and the measurement behind them.

## Pre-plan (DONE)

- [x] **Direction chosen with the alternatives on the table**: governors +
      protection on the network tier, ahead of the roadmap's cross-fidelity
      playback rung, because it closes work the repo already labels unsound and
      needs no new dependency (`m3-context.md` §Why this milestone).
- [x] **The bit-identity question settled by measurement, not argument** — a
      zero-derivative third state changes `Tsit5`'s accepted steps from step 2
      onward, because the error norm is averaged over the state vector
      (`m3-context.md` D1). The plan's step 1 is written against the measured
      answer instead of assuming the convenient one.
- [x] **A wrong premise caught before it reached code.** "Governors give the
      system an equilibrium after a trip" is false — droop leaves a permanent
      speed offset, so the angles still drift and `find_fixpoint` still cannot be
      called post-trip. V3 now exists to pin that as a tested property.

## Step 1 — the governor state, alone on its own commit (DONE)

- [x] `Machine` grows `R`, `Pmax`, `Tg`; constructor guards each (`R > 0`,
      `Tg > 0`, `Pmax ≥ P0`) with **the message asserted per guard**, since an
      invalid machine usually violates more than one rule and "it threw" would not
      prove the intended guard fired (the M2 discipline). The three are **defaulted
      positional** arguments (`Inf`, `P0`, `1.0`), which is what keeps all eleven
      existing call sites building the machine they always built.
- [x] `Pmax` documented as **net-injection ceiling** on an aggregated area machine,
      not a fleet nameplate (`m3-context.md` D4). The negative-`P0`,
      negative-`Pmax` importing-area case is asserted as legal, since that is the
      shape the Iberian machine takes.
- [x] Third vertex state `ΔPm`; `machine_arrays` gains the droop-gain and headroom
      conversions to system base, and remains the **only** place conversion happens.
      Asserted the way it has to be to mean anything: `sum(invR)` reproduces M1's
      `1/R_eq` through `aggregates`, and the two plausible wrong conversions
      (weighting the droop instead of the gain; no weight at all) are named.
- [x] Headroom saturation **in the derivative**; `inject!`'s re-seating of `ΔPm`
      at an event boundary re-justified per machine — and given a test, because the
      hazard it closes had no planned counterpart. Verified non-vacuous: with the
      re-seat removed the same run aborts `Unstable` at the second trip.
- [x] `isoutofdomain` predicate touching **only** the `ΔPm` indices, and the
      `swing.jl` header's "there is deliberately no guard here" note **amended in
      the same commit**. The predicate is asserted directly against a state with a
      1e6 rad drifted angle, because a `δ` term creeping in would present as "the
      solver got slow", not as a failure.
- [x] Governor-free (`R = Inf`) machines expressible, so every M2 model still
      describes a real system — asserted as `ΔPm` staying at solver precision
      through a 20 s frequency collapse, not merely as "it builds".
- [x] **No new scenario in this commit.** The existing suite is the only oracle
      that can find a bug in a state-layout change. The governed fixtures the new
      tests need are local to those testsets, not shipped.
- [x] M2's solver-dependent constants **re-measured and re-pinned once**, with the
      old value recorded beside the new one — including the tight `1.205e-4` /
      `2.0e-4` gap, whose margin must be reported, not silently widened.
      **Reported: `1.205465e-4`, a 1.659× margin against M2's 1.66×.**

      **And the finding: the re-pin the plan announced did not happen.** Every
      gauge-free quantity is bit-identical to M2 — `f_coi`, the angle differences,
      even `naccept`/`nreject`. D1's probe was right about the error norm and wrong
      about this engine, because `step!(integrator, dt, true)` forces a stop at
      every `dt` and the controller was already taking exactly one step per `dt`.
      The only number that moved was the fixpoint's arbitrary **gauge** (a common
      2.14455e-3 rad shift on the two-machine pair), which is the one quantity the
      code says must never be asserted on. Table in `m3-context.md` D1.
- [x] Suite green before and after, and the "before" number written down so the
      "after" number means something. **Before: 1237 core / 78 UI. After: 1320 core
      / 78 UI.** Both measured, not inherited — the figures carried in memory
      (1234 / 74) were stale.
- [x] **`coi_model`'s meaning decided here rather than deferred to step 2**: it
      compiles the real droop. See the settled open question in `m3-context.md`,
      including why the aggregate `Tg` ships as an explicitly unvalidated choice.
- [x] **The `isoutofdomain` cost question measured here too** (271 ns against a
      1974 ns step, ~14 %, kept). `m3-context.md`, open questions.

## Step 2 — validation of primary response

- [ ] **V1** governor-free network still satisfies M2's **closed-form** predictions
      (`K = 4.284 pu`, `δ₀ = 0.140518 rad`, `f_osc = 1.5911075 Hz`, the V3 gap
      inside its bound) — **not** M2's re-pinned measured values, which step 1
      itself moves and against which the check would pass by construction.
- [ ] **V2** droop settling `Δω = −ΔP/(1/R_eq + D)` measured on the **running
      engine**, and mechanical power up by `−Δω/R_eq`.
- [ ] **V3** angle *differences* converge while the common mode keeps drifting at
      `ω₀·Δω_settle` — the tested form of the corrected premise.
- [ ] **V4** headroom: stops exactly at the ceiling, releases unaided on recovery,
      predicate never fires during continuous integration, and the predicate is
      asserted to ignore a large drifted `δ`.

## Step 3 — the shedding ladder, unbound from the M1 engine (refactor)

- [ ] A ladder binds to **one named machine**; firing steps that machine's `Pm`.
- [ ] M1's existing shed tests unchanged and still green — they are the oracle for
      this refactor.
- [ ] **V5** the right area sheds: the falling machine's `Pm` moves, the other's
      does not, and a ladder bound to the other machine does not fire.

## Step 4 — out-of-step protection (new mechanism, separate commit)

- [ ] `ContinuousCallback` on `|δ_from − δ_to|` for a named branch, latching,
      firing through the existing `inject!(::TripLine)` path.
- [ ] Threshold lives on the protection object, **not** on `Branch` (open question
      in `m3-context.md`; settle it here).
- [ ] **V6** the trip instant is a root, not a step: halving `dt` moves it by less
      than solver tolerance; the tie's power reverses sign before the trip; the
      trip leaves two islands each holding their own frequency.

## Step 5 — ramped generation loss

- [ ] `Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)` in the vertex RHS, with
      the staircase alternative rejected in a comment and why (`D7`).
- [ ] A zero-rate ramp is exactly the old behaviour — asserted, so the parameter
      addition cannot have perturbed existing scenarios.
- [ ] Ramp end is a `C¹` corner, not a jump: assert no protection callback fires
      spuriously at `t_start` or `t_start + duration`.
- [ ] **The ramp is inert at the fixpoint solve.** It puts explicit `t`-dependence
      into a RHS that `find_fixpoint` evaluates before `t_start`; M2's flat-start
      criterion must survive, and a mis-signed `t_start` must be caught by a test
      rather than showing up as an initialization artefact that looks like physics.

## Step 6 — the Iberian two-area case, in-repo, with its sweep

- [ ] **Re-derive the cascade magnitude from Table 3-1 before writing the ramp**
      — do **not** inherit it. The doc being replaced quotes 5,750 MW and 2,773 MW
      for the same cascade (`D7`), differing by more than 2×, and the sweep's own
      finding is that the slip boundary tracks magnitude almost one-for-one. Record
      which quantity `rate·duration` represents (generation lost, **not** apparent
      imbalance — §2 of the plan doc shows ≈5,000 MW of the 6,150 MW imbalance was
      export swing), and reconcile the staged pre-ramp losses against the
      cumulative 5,750 MW at 12:33:20.560.
- [ ] Two-machine `NetworkModel` on `S_base = 10,000 MVA`, both machines rated away
      from the base (`D8`), `Σ P0 = 0`.
- [ ] Tie strength expressed as the reactance it is: `X = E′₁E′₂/(P_max/S_base)`
      (`D9`), and the construction guard checked **at the weakest swept cell**.
- [ ] Sweep over tie strength × remote inertia × cascade profile, **in the repo and
      regenerable**, mutating `K` in the live parameter vector rather than
      rebuilding a model per cell.
- [ ] Every surviving single-point number labelled as one cell of the grid, or
      deleted. **This is the acceptance criterion** (`D10`) — a port that prints
      three tuned numbers has recreated the problem the milestone was chosen to
      close.
- [ ] `entsoe-iberia-reproduction.md` §7.3 updated to point at the in-repo run, and
      the throwaway probe's provenance warning kept, not quietly dropped.
- [ ] **V7** the sweep's *shape* asserted (stiffer tie ⇒ later slip; above a
      boundary, never), not a cell value that a solver version could move.

## Step 7 — Figure 3-67, or an explicit drop

- [ ] Shed-annotated frequency panel with threshold lines, markers at the
      **root-found** shed instants from the log.
- [ ] Rendered offscreen and the render checked in — render before claiming.
- [ ] New exports checked against `GLMakie` **before** any UI code is written.
- [ ] `ui/`'s own gitignored manifest re-resolved and its tests run, so a core
      change the UI needs cannot hide for six steps.
- [ ] If dropped: say so here and in `m3-plan.md`, rather than carrying it into a
      fourth milestone.

## Known hazards to check off explicitly

- [x] **Post-hoc state clamping stays banned.** Derivative saturation plus a
      step-rejecting predicate; the event-boundary re-seat is a discontinuity, not
      a clamp. *(Step 1. The re-seat goes to zero rather than to the new ceiling,
      because a tripped machine produces nothing at all, not merely nothing extra —
      its scheduled `Pm` goes to zero in the same breath.)*
- [x] **`coi_model`'s meaning is decided, not defaulted** — governor-free view or
      real aggregate droop, and what the cross-fidelity comparison then compares.
      *(Step 1: real droop. The aggregate `Tg` ships as a stated, unvalidated
      choice rather than as a formula presented as settled.)*
- [x] **No aggregate `ΔPm` read-out** that invites the per-machine / aggregate
      conflation M2 spent four distinct names avoiding. *(Step 1: `current_state`
      returns the per-machine vector and nothing sums it. It is deliberately not a
      recorder channel either — see the V5 tripwire's own note.)*
- [x] **Every long-running test self-terminates** on a fixed step count, never on a
      condition. *(Holds for step 1's four new testsets; re-check per step.)*
- [ ] **Both dependency resolutions tested**, not just the developer machine's —
      the gitignored manifest makes the dev machine systematically the stale one.

## Housekeeping folded into the first docs commit of this batch

- [x] `m1-tasks.md` still records unbounded trajectory growth as open; M2 step 3
      closed it (`src/engines/recorder.jl`). Fix the stale line. — **Already done**
      before this batch: `m1-tasks.md` line 111 reads "CLOSED at the head of M2
      step 3" and keeps the original entry beneath it for the record. Checked, not
      assumed, at the head of step 1.
- [x] Figure 3-67 is carried open in both `m1-tasks.md` and `m2-tasks.md` while
      ticking no acceptance criterion. Point both at M3 step 7, which has one. —
      **Already done**: both files carry the pointer and the criterion. Checked.
