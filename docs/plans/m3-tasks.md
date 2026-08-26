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

## Step 3 — the shedding ladder, unbound from the M1 engine (refactor) (DONE)

**Suite: 1388 → 1461 core (+73), 78 UI unchanged.** Both measured either side. This
step *does* change `src/`, so unlike step 2 the two standing hazards had to be
cleared rather than merely noted: `ui/`'s gitignored manifest was re-resolved (no
packages added or removed) and its 78 tests run, and the new exports were checked
against `GLMakie` before any of it — **one** new export, `shed_ladder`, and
`intersect(names(GridSim), names(GLMakie))` is empty. `AGGREGATE_MACHINE` and
`disarm!` are deliberately internal.

- [x] A ladder binds to **one named machine**; firing steps that machine's `Pm`.
      `protection/load_shedding.jl` now knows **no state layout at all**: the engine
      passes in a `speed(u)` and an `apply!(integrator, ΔP_pu)`, so the condition
      reads that machine's own `ω` and the affect steps that machine's own `Pm`
      parameter. On this tier `Pm` is a *net injection*, so removing load raises it
      by exactly the block — the same sign as M1's `ΔP_dist += ΔP_pu`, and said in
      the one comment that owns the convention.
- [x] The kwarg is `shed = [:ES => stages, :PT => stages]`, a **vector of pairs and
      not a `Dict`**, so the callback set is built in the caller's order; a `Dict`'s
      iteration order is not the caller's and two runs of one script must arm the
      same callbacks the same way. The engine **builds** its ladders rather than
      accepting pre-built ones, because a `ShedLadder` holds a live latch and log and
      handing one object to two engines would silently share both.
- [x] Three construction guards, each provoked alone and asserted **by its own
      wording** (the step-1 discipline): the `:system` sentinel reaching a network
      engine, an unresolvable machine id, and two ladders on one machine — that last
      one because double-arming sheds a block twice at one threshold, which reads as
      a working defence plan.
- [x] M1's existing shed tests unchanged and still green — they are the oracle for
      this refactor. **And the bar was raised from "green" to bit-identical**: the
      new arithmetic is `f0*(1+speed(u))` with `speed = u -> u[1]`, which is the old
      expression, so a recorded run at `HEAD` before the edit is the real check. Root
      -found instant, `Δω`, `f`, `ΔPm`, `ΔP_dist`, `naccept` and `nreject` all agree
      **to every digit** across two scenarios. Green alone could not have said that.
- [x] **V5 — and the planned V5 was vacuous.** As written in the plan ("the falling
      machine's `Pm` moves, the other's does not, and a ladder bound to the other
      does not fire") it is satisfied *in full* by a ladder that reads `f_coi` and
      applies to a named machine — which is exactly the bug D5 exists to prevent. The
      fixture therefore separates the two candidate signals **by construction**: a
      small area (`:A` with its local generation `:C`) on a deliberately weak tie to a
      machine carrying 30× its inertia. Trip `:C` and over the whole 60 s run
      - the bound machine goes **6.52 Hz below** the threshold (min 42.979 Hz),
      - the COI average stays **0.09 Hz above** it (min 49.595 Hz), as does `:B`,
      so a `f_coi`-driven ladder fires **zero** times where the correct one fires
      once. Not a near-coincidence a solver version could close. The firing instant
      is additionally pinned inside the one-`dt` bracket of the bound machine's own
      crossing, and asserted off the `dt` grid, i.e. root-found. `:B`'s identical
      ladder is shown not to fire **ever**, on its own 60 s run, not merely "not yet".
- [x] `Pm` moved by exactly the block on the bound machine and **to the bit**
      unchanged on the other; `shed_ladder` on a machine with no ladder is a
      `KeyError`, not a silent empty one.
- [x] **The trip × shed interaction settled here rather than left to step 6**, where
      trips and sheds first share a scenario. A generator trip **disarms** the ladder
      bound to that machine — latched, not fired, so the log stays a record of what
      actually shed. Generator trips only: a *line* trip can island a live machine,
      which is the situation its ladder exists for, and step 4 fires through that
      same path.
- [x] **And the finding: for a genuine under-frequency stage that disarm cannot
      change anything, and it is provable rather than hopeful.** After a trip the
      machine has `Pm = 0`, every incident `K = 0`, `invR = 0` and `ΔPm` re-seated,
      so its rotor obeys `dω/dt = −Dω/2H` and decays **monotonically back toward
      nominal**. A machine tripped below a threshold has therefore already fired
      (measured: 48.633 Hz at its own trip, having fired at t ≈ 1.91 s), and one
      tripped above it only moves away. Re-arming it by hand after the trip leaves
      the run **bit-identical** in every angle and speed.

      So the counterfactual was built on the construction that **does** reach it: a
      dead rotor decaying toward nominal *from above* crosses every threshold between
      where it was and 50 Hz, downward. `LoadShedStage` does not forbid a threshold
      above nominal — M1's own crossing-polarity test uses 50.5 — so with the disarm
      removed, a machine that has been **offline for seven seconds** sheds load and
      starts injecting `+0.05` pu. Kept, tested, and labelled as what it is: intent
      made structural, plus real cover for step 5, whose ramp puts `t`-dependence
      into the vertex RHS and could otherwise re-open the hazard silently.
- [x] **The network engine gets its own `dt`-refinement test.** M1's pins the
      *framework's* behaviour (`apply_callback!` sets `derivative_discontinuity`
      before the affect); this path is a different one — `p` is a flat `Vector` and
      the affect writes an index, not a field of a mutable struct. 10× refinement
      agrees to **4.9e-10** relative on the shed machine's speed and **1.3e-11** on
      the firing instant, against the **1.7e-4** bias a single stale-derivative step
      would cost. Asserted non-vacuous: the unarmed run sits 0.0055 pu lower.
- [x] **The bit-identity bar applied to the SWING engine too, not just M1.** The
      easy thing to miss: before this step `SwingEngine` passed **no** `callback`
      kwarg to `init`, and now every no-shed construction passes an empty
      `CallbackSet` — a new argument on the integrator underneath every existing M2
      and M3 network test, verified only by "the suite is green", which is precisely
      what step 1 established cannot see a moved digit. Checked against a worktree at
      `d7342ac`: the ring after a generator trip and the pair after a line trip agree
      **to every digit** on per-machine speeds, gauge-free angle differences, `ω_coi`,
      the nadir, and both `naccept` and `nreject`. The empty callback set costs
      nothing and moves nothing, so step 2's pinned tolerances stand as measured
      rather than merely as re-passed.
- [x] **Droop and a ladder on the SAME machine, which nothing had run.** Every other
      step-3 test uses governor-free machines, so the one configuration step 6
      actually needs — an area with primary response *and* a defence plan — was
      untested. It earns a test because it is where two independently-made decisions
      meet: a shed steps `Pm` and leaves `headroom` alone, which is correct **only**
      because D4 defines `Pmax` as a net-injection ceiling, so removing load raises
      the ceiling by exactly the block. Asserted as the ceiling `Pm + headroom` moving
      by exactly the block, so a later reinterpretation of `Pmax` as a generation
      nameplate cannot break it silently. On a machine that is genuinely **out of
      reserve when the stage fires**: `ΔPm` sits on the ceiling (max overshoot 7.5e-11,
      inside the guard's own 1e-10 slack), the shed's own block drives the recovery —
      step 2's release test used a load trip as the cause — and it settles on the
      droop closed form with step 2's *survivors-only* denominator, to 1e-8. The
      unarmed counterfactual stays pinned at the ceiling for the whole 120 s.
      The step-rejecting guard does fire here (59 rejections in 12,050 steps), which
      is step 1's measured behaviour at a live ceiling, and the run still advances its
      full span.
- [x] **Sheds stay out of the `EngineEvent` log**, and the header now says why rather
      than leaving a reader to wonder: the ladder's own log already carries the
      root-found instant, the threshold and the block, and the event log's stamp
      would be the `dt`-quantised one. Step 7 plots the two together; it does not
      merge them.

## Step 4 — out-of-step protection (new mechanism, separate commit) (DONE)

**Suite: 1461 → 1560 core (+99), 78 UI unchanged.** Both measured at `HEAD` either
side rather than inherited — the rule step 1 wrote down after inheriting 1234/74
from memory, and step 2 needed after this file's own "After: 1320" went stale. This
step changes `src/`, so the two standing hazards were cleared rather than noted:
`ui/`'s gitignored manifest was re-resolved (no packages added or removed) and its
78 tests run, and the four new exports were checked against `GLMakie`
**before** any of it — `OutOfStepTrip`, `OutOfStepRelay`, `out_of_step_log`,
`out_of_step_relay`, all clear, and `intersect(names(GridSim), names(GLMakie))` is
still empty. `disarm!` stays internal, for `ShedLadder`'s reason. No new dependency,
so the both-resolutions hazard is **clear here, not skipped**.

- [x] `ContinuousCallback` on `|δ_from − δ_to|` for a named branch, latching,
      firing through the existing `inject!(::TripLine)` path — and it is the **real**
      `inject!`, not a shared helper, so the no-op guard, `lines_online`, the event
      log and both integrator-boundary calls are the shipped ones by construction.
      The price is stated where it is paid: the affect reaches the engine through a
      `Base.RefValue{Any}` the constructor fills on its last line, because the
      callbacks are arguments to `init` and the integrator is one of the engine's own
      type parameters. A closure capture, **not** a struct field, so SPEC §4 is
      untouched; one dynamic dispatch per relay per run.
- [x] Threshold lives on the protection object, **not** on `Branch` — the open
      question in `m3-context.md` is closed with the reasoning, not left standing.
- [x] **V6** all three clauses, and the third one needed correcting before it could
      be asserted:
      - **the instant is a root, not a step** — 10× `dt` refinement moves it by
        **4.4e-15** (1.5e-15 relative), against the up-to-one-whole-`dt` bias a
        step-boundary detector would carry. It lands inside the one-`dt` bracket the
        bare run puts the crossing in, off the `dt` grid, and `|δ|` at the firing
        instant equals the threshold **to the bit**;
      - **the tie's power reverses before the trip** — the area exports 0.10 pu
        pre-fault, the flow reverses at **t = 0.91 s**, and the relay fires at
        **t = 2.9336 s**, 2.02 s later. The reversal passes through `abs`'s kink at
        zero harmlessly, which is a *maximum* of the condition and so carries no sign
        change for the rootfinder to mistake for a crossing;
      - **two islands, each holding its own frequency** — each converges on its own
        closed form with step 2's survivors-only denominator (`:ES` alone at −0.04 pu
        = 48.00 Hz, `:FR` at −0.005 = 49.75 Hz) to **3.0e-10** and **1.3e-9**, flat to
        7.6e-10 peak-to-peak, with the tie transferring **exactly 0.0**.
- [x] **And the finding: that third clause, asserted alone, would have passed with
      the relay deleted.** The unarmed run reaches the *same* two island frequencies
      to ~3e-5, because a fully slipping tie transfers almost no NET power — `K·sin`
      of a monotonically growing angle averages to zero. This is step 3's V5 trap in a
      new place. What actually discriminates is asserted instead, and by four orders
      of magnitude: 300 s in, the unarmed tie is still swinging the **whole** way from
      `+K` to `−K` and never decaying (0.5407 pu peak-to-peak = 2K), and the residual
      ripple in the two speeds is 3.1e-4 / 1.2e-4 against the armed run's 7.6e-10 /
      2.1e-9 — a factor of 4.1e5 and 5.7e4. The closed forms are asserted **as well**,
      labelled as the half that does not tell the two runs apart.
- [x] **The step-3 fixture was measured and rejected, not reused.** On
      `_split_speed_net` the two ends already sit at their own islanded closed forms
      **with the tie in service** (A at −0.14 pu, B at −0.004, which are exactly the
      unarmed minima step 3 recorded), so V6's third clause is true there before the
      relay does anything. `_pole_slip_net` is sized to the question instead: the
      tie's maximum transfer (`K = 0.2704 pu`) is **below the area's own load**
      (0.40 pu), so after the trip the surviving network has no equilibrium at all —
      not a marginal one a solver version could push either way.
- [x] **Two interactions the plan's three bullets did not mention, both provoked
      alone and both non-vacuous.**
      - **A generator trip at either end disarms the relay.** Step 2's V3 measured
        why: the dead rotor's `δ` freezes while the survivors' common mode drifts on
        at `ω₀·ω_ss`, so the angle across a branch with one dead end grows at the
        *full drift rate* and crosses any threshold whatever. Measured: after `:ESG`
        trips, `L12`'s coupling is exactly `0.0` and `|δ_B1 − δ_B2|` blows through
        120° at **t = 2.36 s**, reaching ~199 rad by 30 s — so without the disarm the
        relay opens a line that has carried nothing for over two seconds and calls it
        a pole slip. Latched, not fired, so the log still says it never operated. The
        disarm is **selective** (only branches incident to that bus) and asserted so:
        the tie's own relay survives the same trip and still works.
      - **Opening a branch disarms every relay on it, whoever opened it.**
        `inject!(::TripLine)` no-ops on an already-open branch, so a relay left armed
        would root-find a crossing, change nothing, and then log a protection
        operation that never happened — breaking the engine's rule that a log records
        what changed the system. One line, after the no-op guard, covering the user's
        trip, another relay's trip and the relay's own. Non-vacuous: after a hand trip
        of the tie the threshold *is* crossed, at t = 2.53 s.
- [x] **Polarity and branch orientation settled by one fixture.** The condition is
      `threshold − |δ|`, so exceeding the threshold is a **downward** crossing and the
      trip goes in the `affect_neg!` slot; wired to the other slot the relay would
      open the tie when the areas came back **into** step. The construction guard
      forces the condition to start positive, so the discriminating scenario is one
      where the angle overshoots and recovers — `three_machine_ring` after an `L23`
      trip peaks at 0.3989 rad at t = 0.435 s and settles at 0.2629, so a 0.35
      threshold is crossed once up and once down. The relay fires at **t = 0.3330**,
      on the way up. That same fixture settles the orientation: `L31` is declared
      `:B3 → :B1` while `Graphs` holds the edge as `(1, 3)`, so the two orientations
      differ by a sign — the log carries the **branch's**, `−0.35`, and `|δ|` alone
      could never have caught a swap.
- [x] **Bit-identity, not "still green", for everything that already worked.** The
      easy thing to miss: `init`'s `callback` argument is now a `CallbackSet` wrapping
      the shed set and the relay set, and both `inject!` methods grew a loop over
      `eng.relays`. Checked against a worktree at `871a20e` (whose gitignored manifest
      had to be instantiated first — the trap again): the ring after a generator trip,
      the pair after a splitting line trip, the ring with a shed ladder that fires,
      and the governed ring all agree **to every digit** on per-machine angles,
      speeds, `ΔPm`, `ω_coi`, the nadir, the shed log's root-found instant, and both
      `naccept` and `nreject`.
- [x] **A ladder and a relay in one engine, which nothing had run** — the pairing
      step 6 actually needs. Both fire in one run; the relay's *line* trip does **not**
      disarm the ladder, which is the asymmetry `inject!(::TripGenerator)` documents;
      and the two logs stay separate, with the line trip in the event log and the shed
      not.

      **And the order is the opposite of what the test first asserted.** The tie
      separates at **2.93 s** and the area only falls through 49.5 Hz at **5.51 s**, so
      the ladder operates on an area that is *already islanded* — the sequence the
      report describes (separation, then the island's own defence plan), not a defence
      plan that saves the tie. The assumed ordering went into the test first and the
      measurement corrected it; both instants are now pinned.
- [x] Four construction guards, each provoked alone and asserted **by its own
      wording**: a non-positive threshold, an unknown bus pair, two relays on one
      branch, and a threshold below the steady-state angle (the fourth needs the
      fixpoint, so it runs past `find_fixpoint`). The last is tested from both sides —
      0.38 rad legal, 0.30 rejected, against a steady-state angle of 0.3789.
- [x] **And checking the fourth guard's own justification overturned it.** It was
      written against "such a relay could never fire: the condition starts below zero
      and a downward crossing needs a positive side to fall from" — a claim about the
      rootfinder that nothing observes from outside `init`, i.e. the shape of wording
      step 2's V4 already had to rewrite. Measured instead of asserted, **and it is
      false**: `|δ|` is not monotone, because the export swing carries the angle down
      *through zero* first. A relay set at 0.30 rad starts at `g = −0.0789`, is carried
      inside its own threshold at **t = 0.41 s**, and fires on the way back out at
      **t = 1.25 s** — 1.7 s before the genuine slip at 2.9336 s, on an ordinary
      disturbance excursion. So the guard prevents a relay that trips a healthy tie
      early and **looks like it worked**, not an inert one. Both crossings pinned.
- [x] **`auto_dt_reset!` inside a callback affect was measured, not assumed.**
      `inject!` calls it, which is safe between `step!`s but is a different situation
      inside a `ContinuousCallback`, where the integrator has just been interpolated
      back to the root mid-acceptance. Patched out of the `TripLine` path — with a
      printed marker to prove the patch was live, because "bit-identical" is also what
      a stale precompile cache produces — the trip instant and every digit of the state
      are identical at three step sizes. Inert on this path and harmless, which is what
      made calling the real `inject!` the right design rather than a hopeful one
      (`m3-context.md` D6).
- [x] **Every long-running test self-terminates on a fixed step count**, never on a
      condition. The longest here is a 30,000-step (300 s) pair of runs.

## Step 5 — ramped generation loss (DONE)

- [x] `Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)` in the vertex RHS, with
      the staircase alternative rejected in a comment and why (`D7`). Three vertex
      parameters, armed at construction (`SwingEngine(net; ramp = [:G1 => …])`) as
      `shed` and `out_of_step` are — a ramp is *scheduled* scenario data, not a
      thing a user does to a running engine, so it is deliberately **not** a
      `PerturbationEvent`.
- [x] **`rate` is pu/s on `S_base`, not MW/s**, and the reason is the invariant:
      `machine_arrays`/`branch_arrays` are the single place *model* data converts
      to the system base. A ramp is an engine-armed *setting*, like
      `LoadShedStage`'s `ΔP_pu`, which is in pu for exactly this reason. MW/s here
      would have opened a second conversion site beside the one the rule names.
- [x] A zero-rate ramp is exactly the old behaviour — asserted to the **bit**,
      `naccept` included, between two engines built in the same process (which is
      what makes it a real check rather than the stale-precompile artefact a
      cross-process "bit-identical" can be).
- [x] **THE FINDING: `find_fixpoint` was being evaluated at `t = NaN`, and nothing
      had noticed.** NetworkDynamics defaults the steady-state solve's time to
      `NaN` (`NetworkFixedT`), which was harmless for four milestones because no
      vertex RHS read `t` at all. The moment one does, `clamp(NaN − t_start, 0, d)`
      is `NaN` and `0.0 · NaN` is `NaN` — so a **zero-rate** machine would have been
      enough to NaN out the steady-state solve of every model in the repo. The
      constructor now pins `t = t0`, which is also simply the right question to ask.
      Asserted directly (`swing_vertex!` at `t = NaN` really does return `NaN`), so
      the line cannot be removed as decoration.
- [x] **The ramp is inert at the fixpoint solve.** `_bind_ramps` refuses
      `t_start < t0`, so `clamp(t0 − t_start, 0, duration)` is exactly `0` at the
      solve: the steady state is the un-ramped one, **bit-identical** to the engine
      with no ramp armed, and the run stays bit-identical until `t_start`. A
      mis-signed `t_start` throws with its own message, and the guard is measured
      against the run's own `t0` rather than against zero (asserted both ways).
- [x] Ramp end is a `C¹` corner, not a jump: no protection callback fires
      spuriously at `t_start` or `t_start + duration`.

      > **The planned check was vacuous and was rewritten.** "Arm protection whose
      > threshold the run never reaches, assert nothing fires" passes with the ramp
      > term deleted from the RHS — nothing fires because nothing happened. Same
      > trap as step 3's V5 and step 4's V6 third clause. What is asserted instead
      > is a ladder whose threshold the ramp **does** cross, at 49.15 Hz — chosen so
      > the crossing lands **10 ms before** the far corner at `t = 4.0`, as close as
      > the trace allows without being it. It fires at `3.989737 s`, matches the
      > recorded frequency crossing to 100× better than its distance from the
      > corner, and moves by **< 6.2e-8 s** over a 4× change in `dt` (V6's own
      > discriminator, at four thresholds spanning before, straddling and after both
      > corners).
- [x] **No `tstops` at the corners, decided by that measurement rather than by
      argument.** The obvious defensive move is to pin `tstops = [t_start,
      t_start+duration]` so the solver lands exactly on both kinks. The measurement
      says there is nothing left for it to buy — and pinning them would change the
      step sequence and destroy the zero-rate bit-identity above, so it would have
      cost a real assertion to fix nothing.
- [x] **A generator trip takes its ramp with it** — not on the checklist, and the
      one thing in this step that would have been a live bug. `Pm_eff = Pm + ramp`,
      so `inject!(::TripGenerator)` zeroing `Pm` alone leaves the ramp standing: an
      offline, decoupled, undriven machine goes on being injected into.
      `m3-context.md` predicted this exact re-opening (the "a dead machine sheds and
      injects" case step 3 found unreachable, put back on the table by explicit
      `t`-dependence). Asserted from **outside** the parameter vector — the dead
      rotor's own undriven decay `ω(t) = ω_trip·e^{−t/(2H/D)}` to `rtol = 1e-6` —
      because reading `rate` back would pass even if the RHS ignored it. The
      survivors' settling frequency is asserted too and **labelled as the half that
      cannot tell the two runs apart** (a tripped machine's power reaches nobody
      either way).
- [x] The magnitude claim, which is the strongest one available: where the system
      settles depends only on `rate·duration` and not on the path. Three shapes
      (`−0.5×3`, `−1.5×1`, `−0.15×10`) all land on step 2's droop closed form
      `Δω = ΔP/(Σ1/Rᵢ + ΣDᵢ) = −0.009375` to `rtol = 1e-9`. The no-saturation
      precondition is sized against the **peak** governor command (≈1.19 pu), not
      the settled one (0.9375 pu) — step 2's lesson, 26 % apart.
- [x] Guards, one asserted message each: non-finite `rate`/`t_start`,
      `duration ≤ 0` (a zero-duration ramp is the instantaneous step this type
      exists to avoid), infinite `duration` (no total magnitude for step 6's sweep
      to vary), unknown machine, two ramps on one machine, `t_start < t0`.
- [x] The V5 tripwire moved by exactly `4n` and is accounted for rather than
      re-pinned: three vertex parameters add `3n`, one new index vector
      (`rate_pidx`) adds `n`. `24n + 2 → 28n + 2`. Only the *rate* gets a flat
      index, because it is the only ramp parameter anything writes after
      construction. Noted in passing: the "1122 < 40²" positive control now has a
      visible shelf life — the gap is 478 elements, about six more per-machine
      parameters each carrying an index vector — and the slope assertion is the
      actual claim.
- [x] Both new exports (`GenerationRamp`, `generation_ramp`) checked clear against
      GLMakie — `intersect(names(GridSim), names(GLMakie))` is still empty. A third
      (`ramp_magnitude`) was considered and dropped: a one-line product is not worth
      an export to keep clear.
- [x] **A nonzero ramp on a GOVERNED machine, and a ladder on top of it** — the
      configuration step 6 needs, which every test above left out by ramping the
      governor-free G1. It is also the counterfactual for the one claim
      `GenerationRamp`'s docstring makes in prose: **headroom does not move with the
      ramp**. The governor still saturates at `Pmax − P0`, so the machine's total
      mechanical ceiling travels *down* with the loss and ends at `Pmax +
      rate·duration` — asserted as a number (`−1.0 pu`, a machine that ends up
      absorbing), so a later "fix" making headroom track `Pm_eff` goes red. Then the
      shed on that same machine: three independent decisions (a shed steps `Pm`, the
      ramp adds to `Pm`, headroom sits on `P0`) whose **agreement** is what would
      break silently, so the composed settling point is asserted rather than reasoned.
- [x] 1657 core / 78 UI tests green. The one `dt was forced below floating point
      epsilon` warning in the suite was checked against `HEAD` and is **pre-existing
      and unchanged** — it comes from `step!(integ, 0.01, true)` accumulating float
      error and needing a sub-epsilon final step to land on `t = 10`, in step 1's
      freeze test, whose state is bit-identical before and after this change.

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
      condition. *(Holds for step 1's four new testsets, step 2's four, and step 3's
      six, whose longest is a 6,000-step (60 s) run; re-check per step.)*
- [ ] **Both dependency resolutions tested**, not just the developer machine's —
      the gitignored manifest makes the dev machine systematically the stale one.
      *(Re-resolved and green at step 2, step 3 and step 4, none of which changed a
      dependency. Left open because it has to be re-run by whichever later step does
      change one.)*

## Housekeeping folded into the first docs commit of this batch

- [x] `m1-tasks.md` still records unbounded trajectory growth as open; M2 step 3
      closed it (`src/engines/recorder.jl`). Fix the stale line. — **Already done**
      before this batch: `m1-tasks.md` line 111 reads "CLOSED at the head of M2
      step 3" and keeps the original entry beneath it for the record. Checked, not
      assumed, at the head of step 1.
- [x] Figure 3-67 is carried open in both `m1-tasks.md` and `m2-tasks.md` while
      ticking no acceptance criterion. Point both at M3 step 7, which has one. —
      **Already done**: both files carry the pointer and the criterion. Checked.
