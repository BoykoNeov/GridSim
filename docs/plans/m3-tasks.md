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
- [x] **New exports checked against `GLMakie`: there are none.** `R`, `Pmax` and
      `Tg` are struct fields, `ΔPm` is a `NamedTuple` key, and
      `_swing_outofdomain` is internal. Written down rather than left silent,
      because on a hazard list that has cost a round twice, silence reads as
      skipped rather than as clear.
- [x] **Two counterfactuals committed, not left in a scratch script.** Neither
      mechanism was covered by a test that would fail if it were removed:
      - the **re-seat** in `inject!` — remove it and the same run aborts
        `Unstable` at the second trip;
      - the **guard itself** being attached to `init` — detach it and six
        assertions across two testsets go red. Four of those are in the
        saturation test, which was *expected* to pass without the guard on the
        grounds that the derivative saturation bounds `ΔPm` by itself. It does
        not: adaptive-step overshoot exceeds the 1e-9 bound without the guard to
        reject it. The guard is load-bearing, not belt-and-braces.
- [x] **A legal machine nothing had initialised**: finite `R` with `Pmax == P0`
      (zero reserve, blessed by D4) is the one configuration where the saturation
      branch is live *at* the equilibrium — `ΔPm >= headroom` is `0 >= 0`. It was
      only ever *constructed* in a guard test, never handed to `find_fixpoint`. Now
      initialised and run: the fixpoint converges flat and the machine holds at
      exactly zero while droop commands it upward. A sweep cell zeroing an area's
      reserve is an obvious thing to try in step 6, and it would have found this.

## Step 2 — validation of primary response (DONE)

Validation only: **no `src/` change, no new export, no new dependency**, so the
`GLMakie` collision hazard and the `ui/`-manifest hazard are *clear here*, not
skipped — `ui/`'s manifest was re-resolved and its 78 tests run anyway, because
"it cannot have changed" is what was believed the last two times it had.

**Suite: 1332 → 1388 core (+56), 78 UI unchanged.** Both measured either side —
and measuring the "before" caught a stale number in this very file. Step 1's line
above records "After: 1320", which was true at `e402f0a` and not at the end of the
step: `f7cfd95` added the counterfactual tests and took it to **1332**. The count
was re-run at `HEAD` rather than inherited from the doc, which is the same rule
step 1 wrote down after inheriting 1234/74 from memory.

- [x] **V1** governor-free network still satisfies M2's **closed-form** predictions
      (`K = 4.284 pu`, `δ₀ = 0.140518 rad`, `f_osc = 1.5911075 Hz`, the V3 gap
      inside its bound) — **not** M2's re-pinned measured values, against which the
      check would pass by construction. *(The reason survived step 1 but changed:
      step 1 measured that the re-pin never happened, so the risk is no longer "the
      baseline moved" but "the baseline could have, and the check must not depend
      on its not having".)* Those three are asserted by the M2 testsets that
      already run against this engine, so what V1 adds is **the non-redundant
      half — invariance to every governor parameter** now that `Tg` and `Pmax` are
      read by the fixpoint solve and the RHS. `Tg` over three decades × headroom
      zero / 500 MW, all with `R = Inf`:
      - Three of the four variants are **bit-identical** to the shipped fixture's
        trace; `Tg = 100` differs by **6.4e-16**, about 4 ulp on a 0.14 rad quantity.
      - **And that residual is not `Tg`.** What differs between the four models at
        `t = 0` is the fixpoint's **arbitrary gauge** — absolute angles up to
        0.11 rad apart, with `δ₁ − δ₂` bit-identical in all four. Shifting *only*
        the gauge, on one model with `Tg` fixed, reproduces it: 0.0018 rad → bit
        identical, 0.108 rad → 9.4e-16, 0.7 rad → 3.9e-15. **Step 1's D1 finding in
        a second place**, and it is asserted, not narrated.
      - The zero-headroom and 500 MW variants take **different branches** of the
        saturation (`ΔPm >= headroom` is `0 >= 0` at the equilibrium when
        `Pmax == P0`). They agree only because the command is identically zero —
        said in the test, or the agreement reads as an untested coincidence.
- [x] **V2** droop settling measured on the **running engine**, and mechanical
      power up by `−Δω/R` per machine (`0.2078` / `0.5195` pu, matching
      `−ω_ss·invR` to 3e-14; their ratio is the gain ratio, not a pooled figure).
      Settled `ω_coi = −0.0051948052` against the closed form to **8.7e-14
      relative** after 150 s.
      - **The finding, and it is a correction to this plan's own V2 line
        (`m3-context.md` D11): the denominator is SURVIVORS ONLY.** `−0.8/154`,
        not `−0.8/160`. The plan states V2 as M1's `Δω = −ΔP/(1/R_eq + D)` where
        `D` is one system-wide *load* damping a trip does not change; on this tier
        `D` is per machine and bolted to a rotor, so "which machines are in the
        sum" has two plausible answers **3.75 % apart** — far too big to hide in a
        tolerance, and the wrong one would have read as a physics bug.
      - Three named near misses (all-`D`, no-droop, no-damping) are each asserted
        **outside** the tolerance by more than 1e-4.
      - **Non-saturation asserted as a precondition over the whole run**, because
        the binding constraint is the *peak* command in the dip, not the settled
        one: peaks `0.284` / `0.712` pu against settled `0.208` / `0.519`. The
        shipped `governed_ring` defaults are unusable for this test for exactly
        that reason — step 1's own saturation testset records that 60 MW of reserve
        puts G3 on its ceiling. The fixture therefore carries 50 pu.
      - 15,000 steps, **0 rejections**, one accepted step per `dt`.
- [x] **V3** angle *differences* converge while the common mode keeps drifting at
      `ω₀·Δω_settle` — the tested form of the corrected premise. Drift measured as
      a finite difference of `δ_coi` over a whole 10 s window at t ≈ 140–150 s:
      **1.0e-13 relative** to `ω₀·ω_ss`, with `|δ_coi| > 100 rad` by then (the
      "never assert on an absolute angle" rule, shown rather than asserted).
      Synchronised pair `δ₂ − δ₃`: rate **1.5e-13 rad/s**, i.e. stopped.
      - **And the tripped machine is not in that set.** `inject!` zeroes the
        couplings of every branch incident to the dead bus, so nothing drives that
        rotor: from a flat start its speed stays **exactly** `0.0`, its angle
        freezes, and its difference against the survivors grows at the *full* drift
        rate. "Angle differences settle" is a statement about the connected, online
        machines — asserted both ways round.
- [x] **V4** headroom: stops exactly at the ceiling, **releases unaided on
      recovery** (trip the ring's net load, `ΔPm` off the ceiling inside 1 s and
      settling at `−0.2727` — negative, legal, no down-regulation floor on this
      tier), and the predicate is asserted to ignore a large drifted `δ` *(that
      half already lives in step 1's saturation testset)*.
      - **The claim about the predicate is worded to what is observable.** It is
        false on every one of the 30,016 **accepted** states, the run rejected 20
        steps total (error control, not a collapsing `dt`), and it advanced the
        full 300 s. That is *not* "the predicate never returned true" — which
        cannot be seen from outside `init!` — and the tasks line above has been
        rewritten to stop claiming it. This file has already paid once for a check
        claimed before it was run.
      - **Why it cannot fire, measured rather than argued**: the largest excursion
        above the ceiling anywhere in the run is **2.4e-11**, inside the
        predicate's own 1e-10 slack. The derivative saturation does the work; the
        guard only absorbs adaptive-step overshoot, and there was none worth
        absorbing.

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
      condition. *(Holds for step 1's four new testsets and for step 2's four,
      whose longest is a 30,000-step (300 s) run written as two fixed loops;
      re-check per step.)*
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
