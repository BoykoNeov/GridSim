# M4 — Tasks

The checklist. Companion to `m4-plan.md` (the how) and `m4-context.md` (the
decisions and the measurements behind them). Living document: each step ticks its
own boxes and records what it found, including what it found that the plan did
not anticipate.

Status: **steps 1–3 done and executed.** Entered at `ab3a87f` with 1719 core /
102 UI tests green; step 1 leaves 1787 / 102, step 2 leaves 1870 / 102, and step 3
leaves **1870 / 172** — the core number unchanged, and that is the result rather
than an omission: the playback window takes already-solved series and needed no
core change at all.

Step 2 was *written* on 2026-09-02 in a remote session with **no Julia toolchain and the
Julia download/package hosts blocked**, so its six new testsets shipped unrun; they
were executed on merge the same day (Julia 1.12.6) and every one of them passed
first time, including the four numeric assertions reconstructed from the V4/V6
notes. Measured numbers are recorded under step 2 below.

## Step 0 — planning (this batch)

- [x] Dependency probes run in `M:\claud_projects\temp\`, never against the repo
      (`m4-context.md` §The dependency probes, five probes).
- [x] PSID established as unusable **by measurement**, not by argument.
- [x] PowerDynamics established as resolving against the repo's pinned stack with
      nothing moved, and its component library enumerated.
- [x] Plan trio written (`m4-plan.md`, `m4-context.md`, `m4-tasks.md`).
- [x] `docs/SPEC.md` §7.6 and §9 item 4 still name PSID; the amendment is
      **deliberately deferred to step 4**, where the oracle harness exists and the
      role is filled in fact rather than in plan. Tracked in **one place only** —
      step 4's list — because an item carried in two places is exactly how Figure
      3-67 got carried through three milestones.

## Step 1 — `solve!`, the contract's unexecuted half

**DONE.** 1787 core / 102 UI green (from 1719 / 102). New file
`src/engines/playback.jl` — the shared driver — plus a one-line `solve!` per
engine.

- [x] `solve!(eng::SwingEngine, tspan; perturbations=[], saveat=…)` — the first
      method of `solve!` in the repo's history.
- [x] `solve!(eng::FrequencyResponseEngine, tspan; …)` — the second, so the
      overlay pair of step 3 has two playback-capable engines.
- [x] Scheduled perturbations landed on exactly with `add_tstop!` and applied
      through the same `inject!` the real-time loop uses; **state-triggered
      protection left exactly as the constructor already builds it** (D4).
      **Deviation from this plan, recorded as D8**: not a `PresetTimeCallback`,
      which is unreachable without changing both engines' types and which would
      have created a second path for a scheduled trip to reach the engine — the
      shape D4 exists to forbid.
- [x] `interface.jl`'s "supplied up front rather than injected live" docstring
      **corrected**, not inherited — it is false for M3's protection.
- [x] Agreement check: same scenario via `run_realtime!` and via `solve!`.
      **The band was written down before the comparison ran**: `3 · reltol ×
      that channel's own peak excursion`. Three because two independently
      controlled paths contribute two errors; the excursion because a relative
      tolerance is relative to the signal being resolved. Measured at the default
      tolerance: 1.3e-6 Hz against a band of 1.1e-2 (network tier), 9.4e-4 against
      4.2e-3 (aggregate tier).
- [x] **Run at two tolerances**, and asserted as *convergence*, not as "it passed
      twice": tightening `reltol` 1000× must shrink the gap at least 10×. It does,
      on every channel of both engines.
- [x] Positive control: a perturbation at a time the real-time grid cannot
      represent (half an output step off) — outside the band by 6.5× and 12.8×.
      Run on a **coarse** grid on purpose: the discrepancy IS the offset, so a
      coarse grid separates the control cleanly instead of leaving it at the
      band's edge. Strengthening a control by making the effect bigger, never by
      making the band tighter.
- [x] Anti-vacuity control, **executed against the source** on 2026-08-26: the
      tstops for scheduled events deleted, so a trip lands late. Every assertion
      in the agreement testset went red, plus the pre-event-sample test and the
      protection test. Reverted; green. The in-suite form (schedule the event one
      output step late) ships alongside it and stays red for the same reason.
- [x] Every new long-running test self-terminates on a fixed step count — and so
      does the driver itself (`maxiters`), asserted by setting the cap to 3.

**Written beyond the list, and one of them found the round's bug:**

- [x] **Protection under playback is asserted, not argued** (D4). A two-stage shed
      ladder run both ways: same number of firings, same blocks, same thresholds,
      root-found instants agreeing to 1.6e-6 s, and the trajectories agreeing
      through both firings. This check was not in the plan; it is the only
      scenario shape in which D9's bug is visible.
- [x] **The interpolant is the solver's own, armed or not** — `calck` asserted on
      a bare engine, an armed engine and the aggregate engine, plus a behavioural
      check **on a transient** (at the flat start every state is ~1e-20 and a
      correct interpolant, a linear fallback and a stale cache all agree).
- [x] The record-then-apply ordering asserted from outside the driver: the sample
      AT an event instant is the pre-event one, in both modes.
- [x] Guards, one message each; an explicit irregular `saveat` grid; continuing a
      solve from where the engine is.

**Added on review, after the first commit of the step:**

- [x] **The relay path too, not just the ladder.** D9 was measured on a shed
      ladder, whose affect steps a parameter. An out-of-step relay's affect does
      strictly more — it opens a branch through `inject!(::TripLine)` and calls
      `auto_dt_reset!` — and it is the affect M3 built for the Iberian case. Run
      both ways on `_pole_slip_net()`: root-found instants agree to better than
      `dt/100`, the angles at firing to 1e-9, both event logs match, and the
      trajectories agree to <1e-4. The claim generalises.
- [x] **`integ.sol` growth across chained solves, measured and pinned** rather
      than left to be rediscovered. `add_saveat!` writes into the integrator's own
      solution object, which never decimates: four 1 s solves at `saveat = 0.02`
      leave 201 entries there against a decimating recorder. Accepted — it is one
      entry per sample the caller asked for, not the wall-clock-unbounded history
      the constructors refuse, and reclaiming it would mean resizing behind the
      integrator's internal `saveiter`. Asserted as an equality so a later change
      that made it grow faster says so.
- [x] **The "no callback may change who is online" constraint made structural.**
      It was a comment; it is now a per-step check in the driver with a named
      error. Unexercised by design (nothing can trip it today), so what the test
      asserts instead is that the watched quantity is live: it equals the engine's
      own inertia read-out, moves on a generator trip, and does NOT move on a load
      step.
- [x] Two guards that both said "outside the horizon" now match on distinct
      clauses, so a test cannot pass by reaching the wrong one; and one compound
      `@test` split so a failure names which half broke.

**Findings, written up in `m4-context.md` §What step 1 measured:** the `calck`
flag depends on whether a relay is armed; the interpolant is retroactively
invalidated by a callback affect (D9 — the round's real cost); `run_realtime!`
runs `N` or `N+1` steps for `duration = N*dt` depending on floating point; and
neither constructor forwarded solver tolerances, so the "two tolerances" rule was
not expressible against these engines until now.

## Step 2 — resampling and divergence in `postprocess.jl`

**WRITTEN, NOT EXECUTED** (see the status line). `src/analysis/postprocess.jl`
gains `divergence`, `tolerance_band` and `system_frequency`; `test/runtests.jl`
gains six "M4 step 2" testsets and an `overlay_pair` helper. Both were written by
reading the engines and the step-1 tests, not by running anything.

**The finding that settled the step's shape — by reading, not measuring (D10).**
The plan offered "the solver's interpolant, or a shared `saveat` grid". Only one
of those exists: both constructors build their integrator `dense = false`,
`save_everystep = false`, `calck = true`, so the interpolation coefficients live
for the *current* step only and are gone the moment it closes. After `solve!`
returns there is nothing to resample with. The read therefore takes **no
resampling path at all** and refuses two grids with a named error — "never
straight-line between decimated samples" became structural rather than a rule.

- [x] ~~Resample two series onto one grid via the solver's interpolant, or~~ a
      shared `saveat` fixed before the solve. **Only the second is possible**
      (above); the two-series `divergence` checks the grids agree to 1e-9 s (the
      step-1 measured roundoff between the two modes' grids is < 1e-12 s) and
      throws otherwise. Nothing interpolates.
- [x] Divergence read compares **inertia-weighted average to inertia-weighted
      average**: `system_frequency` picks `f_coi`, else `f`, never a per-machine
      channel, and is the default `channel` of `divergence`; anything else is an
      explicit selector (the tests use `s -> s.δ_G1 .- s.δ_G2`, gauge-free).
- [x] Lives in `src/analysis/postprocess.jl`; tested headless.
- [x] **The band is a REQUIRED keyword**, and `tolerance_band(reference; reltol)`
      derives it the way step 1 did (`3·reltol·excursion`), so `t_depart` — the
      first instant the gap leaves the band, the "where do they part company"
      number — cannot be read against a band chosen after seeing the gap.
- [x] Anti-vacuity control: same series twice reads exactly 0,
      `t_depart = NaN`.
- [x] Positive control for *agreement*: V4a's `ratio_ring`
      (where the aggregate is the same scalar ODE) solved by **both** engines via
      `solve!` onto one grid reads inside the band, at two tolerances, with the
      gap shrinking ≥10× for 1000× tighter. This is the comparison
      `lockstep_coi` could not make on recorded series (its own comment says why);
      a shared grid makes it possible.
- [x] Positive control for *divergence*: `three_machine_ring`,
      trip at `t = 1.0`: `t_depart` finite, after the event, after the early
      tracking window; end gap equals V4c's derived number; `max > 3·band`.
- [x] The 4.4325 µHz physical residual (V4b) reads as
      *indistinguishable* at the default band and is located (`0.2 < t_max <
      0.35`) and sized (5 %) once the tolerance is `1e-9` and the band drops
      beneath it. The read is only as sharp as the band it is handed, asserted.
- [x] Second anti-vacuity control, in the only form the finding
      leaves: the same engine at `saveat = 0.02` and `0.2`, the coarse run
      straight-lined onto the fine grid, must read outside the band by 3× on a
      ringing angle difference (estimated ~10–50× from `h²/8·(2πf)²·A`); and at
      the shared instants the two runs agree, so what the read finds *is* the
      resampling.
- [x] `Pkg.test()` green at the root — **1870 / 1870**, Julia 1.12.6, 2026-09-02.
      None of the three fragile points predicted here needed touching: the
      convergence assertion had 28× of margin (it wanted 10× and got 279×), the
      µHz peak landed 0.001 % off V4b's figure rather than the 5–8 % feared, and
      the V4c end gap matched at `1e-4` unmodified. Recorded because the *prediction*
      was the honest part: the numbers were reconstructions from notes, and this
      repo has had reconstructed notes turn out wrong before (M3 step 6). This time
      they did not.
- [x] `intersect(names(GridSim), names(GLMakie))` still empty with the three new
      exports (`divergence`, `system_frequency`, `tolerance_band`) — run from the
      `ui/` environment (never the root: putting Makie near the root project is the
      thing the invariant forbids), GLMakie 0.13.13, result `Symbol[]`.
- [x] Measured numbers, replacing the estimates — the table below, also in
      `m4-context.md` D10.

### Step 2's measured numbers

All at `saveat = 0.02` unless stated; gaps are on the centre-of-inertia frequency
except D, which is the gauge-free angle difference `δ_G1 − δ_G2`.

| read | band | max gap | when | note |
|---|---|---|---|---|
| A. exact pair (`ratio_ring`, V4a), reltol 1e-3 | 7.69e-3 Hz | 2.06e-5 Hz | never departs | rms 9.02e-6 |
| A. same, reltol 1e-6 | 7.69e-6 Hz | 7.39e-8 Hz | never departs | **279× smaller**, so it is solver error, not a fixed disagreement |
| B. shipped ring (`three_machine_ring`, V4c) | 8.57e-3 Hz | **0.8575 Hz** | departs 1.58 s, peaks 59.08 s | trip at 1.0 s; end gap 0.85706 Hz = V4c's derived number |
| C. swing residual (`ratio_ring D3=2`), reltol 1e-3 | 4.31e-3 Hz | 9.62e-6 Hz | never departs | the physics is *below* the band: invisible |
| C. same, reltol 1e-9 | 4.31e-9 Hz | **4.4325e-6 Hz** | located at 0.26 s | V4b's peak to five figures, now read under playback |
| D. straight-line resampling, 10× coarser | 8.45e-4 rad | 2.85e-2 rad | departs 0.42 s | **33.7× the band** — inside the plan's `h²/8·(2πf)²·A` estimate of 10–50× |

D is the one that matters: 33.7× outside the band is what the refusal to resample
is worth, and 0.42 s is the coarse span straddling the 0.5 s trip — the mechanism
the test names, not slack.

## Step 3 — the playback window: scrub, overlay, divergence

**DONE.** 1870 core (**unchanged, and byte-identical — this step needed no core
change at all**) / **172 UI** (from 102). New file `ui/src/playback_window.jl`
plus `ui/scripts/playback_overlay.jl` and two checked-in figures. Decisions D11
and D12, and the measurements, are in `m4-context.md` §What step 3 measured.

- [x] Time slider scrubs a solved series; cursor moves on the plot. **The slider
      indexes SAMPLES, not time** — a slider over time would need a value between
      two samples, and both ways of making one are the ways this milestone already
      rejected (there is no interpolant left, D10; straight-lining was measured at
      33.7× the band). Every number the read-out shows is a recorded sample
      verbatim, so the tests assert it with `===` rather than a tolerance.
- [x] Both curves drawn (centre-of-inertia tier vs network swing tier) with the
      divergence read-out from step 2. The band is **derived and displayed with
      its derivation, and there is no control that could change it** — `widgets`
      has exactly one field, asserted, because a band slider is precisely how step
      2's "state the band before you see the gap" discipline would die in a window.
- [x] `smoke_render` offscreen **first**, then the live window. Both done, in that
      order, and the offscreen render is what found the step's real problem (below).
      The live window opened on a real GLFW screen, the slider was dragged on it,
      and it closed cleanly.
- [x] The window's own text states that this pair shows **one of the three
      lessons** SPEC §7.6 names (inter-machine swings) and not the other two.
      **The caption carries a third claim the plan did not anticipate**, and it is
      the one this step had to learn: *a large gap is not by itself evidence of a
      swing* — the two models also differ in which machines' damping the aggregate
      keeps, and that difference is usually the larger one. All three claims are
      deliberately scenario-independent; a caption describing the run it happened
      to be over would be wrong the first time somebody passed a different one.
- [x] UI test count moves; both `ui/` and core suites green. **172 / 172 UI**,
      **1870 / 1870 core** — the core number is unchanged *and that is the result*,
      not an omission: the window takes already-solved series and adds nothing to
      the core, which also matters because **step 5 owns the fresh dependency
      re-resolve** and a core change here would have meant doing that work twice.

**Written beyond the list, and one of them changed what the step ships:**

- [x] **THE FIRST RENDER SHIPPED THE WRONG SCENARIO, AND THE PICTURE IS WHAT SAID
      SO.** The obvious default was a generator trip on `three_machine_ring()` —
      step 2's own positive control, every number matching its table to the digit.
      It is also a monotonic decline on both tiers with **no swing anywhere in
      it**, and its 0.857 Hz gap is V4c's settling-level difference (the aggregate
      keeps the tripped machine's damping). Bookkeeping, wearing the largest number
      the window has ever displayed — under a caption claiming inter-machine
      swings. The shipped default is now `TripLine(:B3, :B1)`, where the gap **is**
      the residual swing content: 1.076e-3 Hz at 333× the band, the rotors 0.28 rad
      apart, and the aggregate tier at *exactly* 50.0 Hz for all 1001 samples.
- [x] **Both figures are checked in, because the contrast is the finding.**
      `docs/images/fig-m4-playback-line-trip.png` and
      `…-generator-trip.png`, regenerated by `ui/scripts/playback_overlay.jl`. A
      doc that claims the tiers part company over swings, illustrated by the figure
      where they part company over something else, is the same promotion again.
      The contrast is also asserted, not merely written: the generator trip's gap
      is >100× the line trip's and sits at 99 %+ of its peak at the end of the run
      (it arrives and stays), where the line trip's decays to under 30 % (a swing).
- [x] **The new scenario's band was checked against the solver before it was
      trusted** (M3's standing rule, applied to a scenario step 2 never ran). At
      reltol 1e-3 / 1e-6 / 1e-9 the band falls six orders while the gap is stable
      to **seven significant figures** and `t_max`/`t_depart` do not move at all.
      Physics, not solver error — the mirror image of V4b, which was invisible
      until the band dropped beneath it.
- [x] **The two tiers do not both get the event, and the picture says so** (D12).
      The aggregate view has no branches, so `TripLine` has no `inject!` method on
      it; `aggregate_perturbations` is a second, explicit list. The **rejected**
      design — filter it automatically with `hasmethod` — is recorded and pinned by
      a test, because it would silently reclassify a method missing *by mistake* as
      a fidelity boundary, the one error this comparison exists to detect.
- [x] **The gap panel is logarithmic with a floor at `band/10`, and the axis label
      says so.** The gap spans nine decades, so a linear axis puts the band and the
      departure indistinguishably on the zero line, and `log10` of the
      same-series-twice case (an exact `0.0`) is `-Inf`. Only visible in the PNG.
- [x] Anti-vacuity: same series twice reads exactly `0.0`, `t_depart` NaN, and the
      summary says "never"; two series on different grids are refused at **build**
      time with the core's own message, never resampled onto one axis.
- [x] `wait_for_close` guarded with `haskey(win, :control)` rather than given a
      dummy control block — a playback window has no loop to stop.

**Three anti-vacuity mutations RUN against the source, each caught by exactly the
assertion built for it:**

- [x] Cursor reads sample `k+1` → caught, **by the `===` assertion alone**.
      Adjacent samples differ by ~1e-6 Hz, so any `atol` form of that check would
      have passed. Exactness is available here, and it is the only thing that
      catches the off-by-one that is this window's real available bug.
- [x] `asymmetric = false` (the picture never flags a mismatched event list) →
      caught, on both the flag and the drawn label's text.
- [x] The caption `Label` built into a *different* `Figure` — right text, simply
      not in the window → caught **only** by the layout check; all six of its text
      assertions still passed. M3 step 7's "a check that reads the log where it
      should read the picture", demonstrated. Hence `in_layout` walks nested
      `GridLayout`s, and the suite carries a control that it can return `false`.

## Step 4 — `reference/`: PowerDynamics as an external oracle

- [ ] New package `reference/`, depending on `GridSim` and `PowerDynamics`,
      never the reverse — same structural enforcement as `ui/`.
- [ ] **`NetworkModel → PowerDynamics` builder** (D5). This is the step's real
      work; a hand-typed PowerDynamics case beside `two_machine_system()` is the
      forked parallel model SPEC §3.2 forbids, and it would drift silently, which
      is the worst possible property in an oracle.
- [ ] Core's dependency-closure test still passes, and gains a clause: core must
      not reach PowerDynamics either.
- [ ] Two-machine case run through PowerDynamics with `Library.ClassicalMachine`
      — **our fidelity, someone else's implementation**.
- [ ] **The agreement band is derived and stated BEFORE the comparison runs** —
      from the solver tolerance, the per-unit base conversion and the two sides'
      initialisation conventions. Two independent implementations of the classical
      machine will not agree to 1e-10, and a tolerance chosen after seeing the gap
      tests nothing. This is the step-4 form of M3's "identify a residual by its
      signature rather than bounding it with a tolerance", and it is the box most
      likely to be quietly skipped.
- [ ] Divergence read from step 2 applied across the two. Disagreement here is a
      bug in *our* engine, not a lesson about fidelity — record which it turned
      out to be.
- [ ] **Positive control for the external check**: the comparison must read
      *agreement* when agreement is real, inside the pre-stated band. Without it,
      "the oracle agrees" cannot be distinguished from "the comparison always
      agrees" — and for an external oracle this is the harder half of the pair.
- [ ] Anti-vacuity control, **executed**: perturb one coefficient in our swing
      vertex equations; the external agreement check must fail.
- [ ] Every mechanism now carries a label saying what checks it (D7). Write the
      list — PowerDynamics-checked, alternatively-oracled, or explicitly
      un-oracled. Un-oracled is allowed; unmarked is not.
- [ ] `docs/SPEC.md` §7.6 / §9 item 4 amended: the role is "an external
      full-fidelity reference", the package is PowerDynamics, and the reason PSID
      is not it is one sentence with a pointer to `m4-context.md`.

## Step 5 — the dependency housekeeping, in its right place at last

- [ ] **Both dependency resolutions tested**, not just the developer machine's —
      the box M3 left open at `m3-tasks.md:795` for "whichever later step does
      change a dependency". Step 4 changes one. Delete `Manifest.toml`, re-resolve
      fresh, run all three suites.
- [x] `[sources]` entry in `ui/Project.toml` so the dev link to core survives a
      fresh clone — the fix M3 identified and declined as out of scope. Added
      2026-09-02 without re-resolving (no toolchain), and **verified the same day**:
      `ui/Manifest.toml` deleted, `Pkg.instantiate()` with **no** `Pkg.develop` by
      hand resolved `GridSim v0.1.0 `..``, and `Pkg.test()` in the `ui/` environment
      is green (102 / 102). Still open, and NOT closed by that run: the section is
      honoured from Pkg 1.11 and the dev machine runs 1.12, so this exercised the
      *honoured* path only. It says nothing about the `julia = "1.10"` compat floor
      still declared in `ui/Project.toml` — whether older Pkg ignores the section or
      errors on it is untested here. Raise the floor to 1.11, or test on 1.10.
- [ ] `reference/Project.toml` carries `[sources]` **from birth**, not added
      later — the gitignored-manifest trap has cost this repo time twice.
- [ ] Tick the M3 box in `m3-tasks.md` with a pointer here, rather than leaving a
      third milestone's reader to wonder whether it was forgotten.

## Known hazards to check off explicitly

- [x] **Resampling error contaminates the measured quantity.** Shared `saveat`
      only — there is no interpolant to use (D10) — and two grids are refused. The
      cost of the alternative is measured by the step-2 control (33.7× the band).
- [x] **Gauge-arbitrary comparison.** `system_frequency` is the default channel;
      anything else is an explicit selector. (Step 2.)
- [x] **An overlay that validates nothing.** Same-series-twice ~0 *and* a
      different-runs positive control are written (step 2) and **run** — green on
      2026-09-02, and again in the window itself (step 3), where the
      same-series-twice case reads exactly `0.0` with `t_depart` NaN.
- [x] **The one-lesson-of-three trap.** Discharged in step 3, and it turned out to
      have a second half nobody had written down: the pair shows inter-machine
      swings only (voltage coupling and inverter behaviour need M5's tier), **and
      not every gap it draws IS that lesson**. The first shipped scenario's 0.857 Hz
      gap was a damping-bookkeeping difference; the caption now says so, and the
      default scenario was changed to the one where the number is the thing.
- [ ] **Playback and real-time must stay the same system.** If protection is
      ever pre-baked into `perturbations=`, every comparison in this milestone is
      measuring the wrong thing.
- [ ] **Every long-running test self-terminates** on a fixed step count, never on
      a condition. Re-check per step.
- [ ] **The oracle must not become a ceiling** (D7). Exceeding PowerDynamics'
      scope is allowed; exceeding it while still speaking as if checked is not.

## Carried into M5 (not this milestone's work)

Recorded so it is not re-derived. Detail in `m4-plan.md` §Why the detailed tier
is M5 — **and now worked on paper in `m5-prestudy.md`**, which corrects two of
the bullets below: the degeneration oracle is *frozen flux* (`T′do = T′qo = ∞`,
`X′d = X′q`), not constant field voltage, and it cannot check the flux equations
at all (they are switched off in that limit — the two-limit bracket and the
`K₃T′do` closed form do); and the network formulation recommendation is reversed
to the algebraic (DAE) network, with what happens to `isoutofdomain` and the
protection callbacks written out. The pre-study also gives the Iberian exit
criterion as one relative measurement (swing peak vs `P_max`) and the three
convention questions step 4 must settle before its band is written.

- The detailed machine tier: two-axis machine with flux dynamics, a voltage
  regulator, and transmission branches carrying voltage as a real unknown.
- The **power flow solve and initialisation** it requires — roadmap item 5's
  territory arriving early, to be scoped deliberately (two-area, sparse, no
  `PowerFlows.jl`).
- The **flat-run test**: no disturbance at all, every state constant for the
  whole horizon. This is what catches a bad initialisation; no overlay will.
- The **degeneration oracle, all three conditions together**: constant field
  voltage, equal transient reactances on both axes, no damper winding. Shrinking
  a time constant alone is *not* the classical limit and would pass against a
  wrong flux equation.
- **Dynamic RL branches, not the algebraic constraint** — or, if reversed, an
  explicit account of what happens to `isoutofdomain` and the step-rejecting
  protection, which do not survive unchanged.
- **"Better than PowerDynamics" needs a named axis and a measurement** —
  accuracy against a closed form, cost per simulated second, or real-time
  steppability — on the same case at the same tolerance.
