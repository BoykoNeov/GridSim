# M1 — Task checklist

Living checklist for Milestone 1. Update as work proceeds. Detail in `m1-plan.md`;
acceptance criteria in `../SPEC.md` §7.8.

## Scaffold (this batch — DONE)

- [x] Repo structure (`src/{model,engines,events,orchestration}`, `test`,
      `scripts`, `ui`, `docs`).
- [x] Minimal core `Project.toml` (fresh UUID, `[compat] julia=1.10`, test target).
- [x] Domain model: `GeneratingUnit`, `SystemModel`, `example_system`.
- [x] Events: `PerturbationEvent`, `TripGenerator`, `StepLoad`.
- [x] `SimulationEngine` interface (generic verbs).
- [x] `step!`/`solve!` collision resolved: added `CommonSolve` (direct dep) and
      `import CommonSolve: step!, solve!` so we share one generic with the SciML
      stack; `init!`/`current_state`/`state_series`/`inject!` stay GridSim-owned.
      Regression test asserts `GridSim.step! === CommonSolve.step!`.
- [x] Scaffold tests green (`Pkg.test()` → 21 pass).
- [x] Separate `ui/` package; lean `CLAUDE.md`; `README`; SPEC relocated.
- [x] Julia 1.12.6 installed (juliaup); package loads + tests pass.

## M1 engine (next batch)

- [x] Add deps via `Pkg.add` (chose **`OrdinaryDiffEq` v7.0.1**, not the heavier
      `DifferentialEquations` meta-package — M1 only needs `Tsit5`, later stiff
      tiers get `Rodas5`/`Verner` which OrdinaryDiffEq still bundles; keeps the
      core closure lighter and Makie-free). Also added `Observables` v0.5.5 for
      the orchestration loop. `Pkg` wrote caret `[compat]` bounds.
- [x] DiffEq dep landed: `test/runtests.jl` now `import OrdinaryDiffEq` and asserts
      **both** `OrdinaryDiffEq.step! === CommonSolve.step!` *and*
      `OrdinaryDiffEq.solve! === CommonSolve.solve!` (real-time *and* playback verb),
      plus the transitive `GridSim.step!/solve! === OrdinaryDiffEq.step!/solve!` —
      two `using`-imported `===` bindings cannot raise an ambiguity, so an engine's
      `using GridSim, OrdinaryDiffEq` sees one generic each. Full suite green (25 pass).
- [x] `aggregates(model, online) -> (; H_sys, R_eq, D, Tg)` (COI, on system base)
      in `engines/frequency_response.jl`, included in `GridSim.jl` (unexported —
      internal engine helper). Unit-tested vs hand arithmetic (all-online,
      post-G1-trip, and empty-set → `R_eq=Inf`); 35 tests pass.
- [x] `aggregates` extended to also return `headroom = Σ(Pmaxᵢ−P0ᵢ)/S_base` — a
      COI aggregate recomputed on every trip (a tripped unit's own reserve leaves
      the pool too). Existing aggregates tests updated.
- [x] Mutable, type-stable parameter struct `FRParams` (all `Float64` fields:
      `H_sys, R_eq, D, Tg, ΔP_dist, headroom`).
- [x] ODE RHS `fr_rhs!(du, u, p, t)` for `(Δω, ΔPm)` with **headroom saturation
      in the derivative** (zero `dΔPm` when `ΔPm ≥ headroom && dΔPm > 0`). Decision:
      the user's "solver callback" pick rides on top in `init!` as an
      `isoutofdomain`/thin-callback **guard** against adaptive-step overshoot — it
      cannot *replace* the derivative logic (a callback can only clamp the state,
      which is the forbidden post-hoc clamp). Derivative-zeroing also gives release
      for free. Unit-tested: initial-RoCoF closed form, binding, **release** (the
      test a naive clamp fails), below-ceiling ramp, `R_eq=Inf`. `@inferred` for
      type stability. **49 tests pass.**
- [x] `FrequencyResponseEngine{I}` (parametric on the concrete integrator type for
      a type-stable `step!` boundary): `init!(::Type{…}, model)` returns a fresh
      fully-typed engine (resolves the build chicken-and-egg — no half-built engine
      to mutate), `step!` (`step!(integ, dt, true)` + record + nadir), `current_state`
      (`f=f0(1+Δω)`, `RoCoF=f0·dΔω/dt`). The headroom **`isoutofdomain` guard**
      (`u[2] > headroom + tol`) rejects/retries oversteps — never overwrites state,
      so it rides on the derivative saturation, not the forbidden post-hoc clamp.
      `init` seeds an explicit initial `dt`, uses a large *finite* tspan, and turns
      off `save_everystep`/`dense` (no unbounded real-time memory leak).
- [x] `inject!(::TripGenerator)`: look up unit (KeyError on unknown id), then if
      online drop it, recompute aggregates into the **shared** `params`
      (`integrator.p === eng.params`, asserted), `ΔP_dist -= P0/S_base`. `Δω`
      continuous; `ΔPm` re-init'd to the shrunken headroom at the event boundary
      (prevents a second-trip freeze), then `u_modified!` invalidates the FSAL
      cache. Already-offline trip is a no-op.
- [x] `inject!(::StepLoad)` (nice-to-have): `ΔP_dist -= ΔP_pu` (added load lowers
      frequency), then `u_modified!`.
- [x] Engine file wired into `GridSim.jl` (`import OrdinaryDiffEq`; engine exported).
      Tests: build, origin, type-stable `current_state` (`@inferred`), live trip,
      closed-form initial RoCoF, unsaturated settling (`Δω_ss=ΔP_dist/(D+1/R_eq)`,
      via a small G4 trip), and `max ΔPm ≤ headroom`. **72 tests pass.**

## Orchestration (DONE)

- [x] `EventQueue` + `drain!` in `src/orchestration/realtime_loop.jl`. Lock-guarded
      (`ReentrantLock`) so the UI can push from any task; `drain!` **swaps** the
      vector under the lock (O(1) critical section, caller iterates lock-free) and
      returns a shared `const _NO_EVENTS` when nothing is pending — no allocation on
      the ~50 event-free steps per second. `push!`/`isempty`/`length`/`empty!` are
      **`import Base:`**-extended, not redefined: defining them bare inside the module
      would shadow Base's for the whole package (same collision class as `step!`).
- [x] `timestep(engine)` added to the engine interface (+ `FrequencyResponseEngine`
      method returning `eng.dt`) so the loop never hard-codes a cadence.
- [x] `RealtimeControl` — `running` / `paused` / `rtf` as concrete `Observable`s, so
      the UI binds play-pause and the speed slider straight to it. Plus `stop!`.
- [x] `run_realtime!(engine, state_obs=nothing; rtf, control, queue, dt, duration,
      max_lag)`. Engine-agnostic (only the interface verbs). Pacing **re-anchors
      rather than accumulating debt**: `rtf` is re-read every pass (the slider moves
      mid-run), the deadline advances by `dt/rtf`, and if a step overruns by more
      than `max_lag` the clock restarts from now instead of sprinting through the
      backlog — same re-anchor on resume from pause, so a long pause does not wake
      up owing seconds. `rtf = Inf` ⇒ no sleeping: the headless/batch path is the
      *same code path* as the paced UI run. `state_obs` is a function argument with
      `_publish!(::Nothing)` / `_publish!(::Observable)` dispatch — never a
      `Union{Observable,Nothing}` struct field (concrete-fields rule).
- [x] Runs as a cooperative task (`@async`), not `Threads.@spawn` — GLMakie is not
      safe to mutate off the main thread, and the Observable write is what triggers
      the redraw; every wait inside yields.
- [x] No Makie: `Pkg.dependencies()` closure test asserts **both** that Makie is
      absent *and* (positive control, so it can't pass vacuously) that Observables
      is present. Needed `Pkg` in `[extras]`/`[targets]` (UUID resolved via
      `Base.identify_package`, not hand-written).
- [x] Loop tests all self-terminate — finite `duration` with `rtf=Inf`, or a state
      callback stopper plus a wall-clock watchdog. A hung suite is worse than a
      failing one. **116 tests pass.**

### Known, deferred (not this batch)

- [x] **Unbounded trajectory growth — CLOSED at the head of M2 step 3**
      (`src/engines/recorder.jl`): one bounded, *decimating* `TrajectoryRecorder`,
      shipped on its own commit with M1 retrofitted onto it and no new engine
      alongside. Decimating rather than a ring buffer because the nadir and the
      initial slope live at the *start* of a run. Two rules became binding with it:
      time is a mandatory channel (decimation changes the sample interval mid-run),
      and running summaries are tracked outside the buffer (the retained minimum is
      not the minimum that occurred). See `m2-tasks.md` step 3.
      *Original entry, kept for the record:* the engine still pushes to
      `ts/fs/rocofs/pms/tripped_mws` on every
      step forever, so memory still grows over a multi-minute window session. What
      the UI batch fixed is only the half it owns: the window plots from its own
      fixed-capacity `RollingTrace` buffers, never from the engine's vectors, so
      the quadratic redraw this item predicted (re-uploading an ever-longer array
      every frame, and a time axis compressing to an unreadable smear) does not
      happen. The core-side fix — ring buffer or decimated history — is still to
      come, and is not a UI change.
- [x] **An exception inside an `@async` loop is silent — RESOLVED.** `launch`
      wraps the loop task in **both** remedies this item offered, because they do
      different jobs: `Base.errormonitor` puts the stack trace on stderr, and a
      `try`/`catch` writes the message into the `status` Observable the window
      displays, so the failure is visible to someone looking at the window rather
      than only to someone watching the terminal. It rethrows after publishing —
      the throw is not swallowed.
- [x] **Check the new exports against GLMakie before writing UI code — DONE,
      nothing collides** (detail in the UI section above). `ui/` will
      do `using GridSim, GLMakie`, and the orchestration batch exported `stop!`,
      `timestep`, and `drain!` — the same collision hazard that cost a round on
      `step!`/`solve!`. The headless batch added five more: `LoadShedStage`,
      `ShedLadder`, `shed_log`, `shed_total`, `windowed_rocof`. Run
      `julia -e 'using GLMakie; for n in (:stop!, :timestep, :drain!, :shed_log,
      :shed_total, :windowed_rocof, :LoadShedStage, :ShedLadder);
      println(n, " => ", isdefined(GLMakie, n)); end'` and decide rename-vs-qualify
      up front, not via an ambiguity error mid-UI-work. Deliberately **not** run in
      the headless batch — it needs GLMakie installed in `ui/`, which is the UI
      batch's setup cost, not this one's.

## Validation tests (DONE)

All four closed forms are asserted in `test/runtests.jl`; the testset that
satisfies each is named below. **177 tests green** at the time of that batch
(was 116); **266 after the headless batch**.

- [x] Initial RoCoF matches `−f0·(P_k/S_base)/(2·H_sys)` — *"closed form: initial
      RoCoF, swept over every single-unit trip"*. Swept over all four units, not
      one instance; `H_sys` is the **post-trip** aggregate; the state is read
      un-stepped so it is still exactly the origin. The all-offline edge
      (`H_sys = 0` ⇒ RoCoF → ∓Inf) is out of M1 scope and asserted away.
- [x] Settling `Δω_ss = ΔP_dist/(D + 1/R_eq)` — *"closed form: settling
      deviation, swept over every trip"*, at `rtol = 1e-6` (≈10⁴× tighter than
      the ±0.02 Hz the engine testset uses; that looseness is what once absorbed
      the stale-FSAL bug). The unsaturated precondition is asserted, not assumed
      — and stated on the **equilibrium** (`ΔPm_end < headroom`), because G2's
      overshoot transiently touches the ceiling without moving the fixed point.
      G1 is the deliberate counter-case: its droop demand exceeds the surviving
      reserve, so it pins at the ceiling and settles *below* the formula.
- [x] Monotone lesson: less inertia ⇒ steeper RoCoF + deeper nadir — *"less
      inertia ⇒ steeper RoCoF and deeper nadir (inertia-only)"*, four inertia
      scalings (2×, 1×, 0.5×, 0.25×) of `example_system` with S_rated/P0/R/Pmax
      carried through verbatim, so `ΔP`, `R_eq`, `D` and `headroom` are identical
      and the comparison is inertia-only. Three guards make the ordering
      non-vacuous: (a) settling frequency is **inertia-free**, so all four must
      land on the *same* `f_ss` and differ only in undershoot — asserted
      alongside the ordering, a sharper statement than ordering alone; (b) the
      ceiling must **not** bind in any config, or the deeper nadir would be
      partly reserve exhaustion rather than inertia; (c) each nadir must be a
      genuine undershoot (`< f_ss − 0.1`), so an edit that overdamped the system
      could not make the ordering pass on floating-point noise. RoCoF0 is checked
      against the exact `1/H` ratio, not just the ordering. Measured: RoCoF0
      −0.46 → −3.69 Hz/s, nadir 49.06 → 48.15 Hz, `f_ss` 49.69466 Hz throughout.
- [x] `ΔPm` never exceeds aggregate headroom — already covered before this batch
      by *"FrequencyResponseEngine: build, step, trip, closed-form checks"*
      (`maximum(eng.pms) ≤ headroom`) and *"second trip after saturation does not
      freeze the integrator"* (post-trip slice vs the **shrunken** ceiling). This
      batch adds the ceiling check to the settling sweep and both AC #6 testsets.
- [x] SPEC §7.8 AC #6, literal wording — *"fewer units online ⇒ steeper RoCoF and
      deeper dip"*. Labelled the **demonstration**, not the isolation: taking a
      unit offline moves inertia, droop gain and reserve together, so the two
      configs do not settle to the same frequency (the inertia-only equality
      assertion deliberately does not apply here). Both effects push the same
      way, which is the operational point; the depleted config additionally
      exhausts its reserve (ΔPm pins at the ceiling) while the full one does not.

## Headless proof (DONE) & UI (next batch)

- [x] `scripts/` generator-trip experiment → frequency trajectory, no Makie (AC #1),
      on the **real ENTSO-E scenario** rather than `example_system`. SPEC §7.8's
      first acceptance criterion is now ticked. The script prints five sections:
      the waypoint comparison, the defence-plan stages that fired (root-found to
      the millisecond, against the report's own annotations), cumulative tripped
      generation, 500 ms windowed vs instantaneous RoCoF, and the published
      inertia band run as a sensitivity experiment.
- [x] `ui/` GLMakie: live `f(t)`, readouts (t, f, RoCoF, nadir, `H_sys`), per-unit
      trip, play/pause, rtf slider, `H_sys` indicator (AC #2, #3, #6). Two files:
      `ui/src/GridSimUI.jl` (the module, which `ui/` did not previously have — the
      `Project.toml` named a package with no `src/`) and `ui/src/window.jl`.
      Structure: one `_build_window` shared by **both** entry points, so the PNG
      the headless path saves is a picture of the very window `launch` opens and
      cannot drift from it.
      - `launch(model; …)` — the real window. `wait_for_close` blocks the process,
        without which a `julia -e` one-liner exits and takes the window with it.
      - `smoke_render(; path, trips, duration)` — the same window offscreen
        (`GLMakie.activate!(visible = false)`), driven through a scripted trip
        timeline flat out, saved as a PNG. **This is what made the batch
        verifiable at all** from a session with no screen; decided up front rather
        than after the window was written.
- [x] Verified on the **visible** window, not only offscreen: a frame grabbed from
      the running renderer (`Makie.colorbuffer(screen)` — hence `launch` returns
      the screen handle) shows a live mid-run trace, the tripped unit's button
      greyed, the slider at 2.0×, and the inertia bar below its ghost.
- [x] Pacing measured rather than assumed. Headless: 1.99× / 4.93× / 9.94× against
      2 / 5 / 10 asked. With the window visible: **4.01× against 4.0×**. An earlier
      reading that looked like "2× runs at 1×" was window *startup* (GLFW creation
      + shader compilation) inside the measurement window, not a pacing bug — the
      loop is starved for those few seconds and accurate afterwards.
- [x] Export-collision check run (the item below), *before* writing UI code:
      **nothing collides.** All 19 names checked — `stop!`, `timestep`, `drain!`,
      `shed_log`, `shed_total`, `windowed_rocof`, `LoadShedStage`, `ShedLadder`,
      the new accessors, and the engine verbs — are undefined in GLMakie. The UI
      still imports from the core name-by-name (`using GridSim: …`, never
      wholesale) as cheap insurance: an explicit import shadows anything a
      wholesale `using` brings in, so a future export cannot reopen this.
- [x] Two small **core** accessors added for the UI, so the window never reaches
      past the engine interface into `eng.params`/`eng.online`:
      `system_inertia(eng)` (the `H_sys` indicator, SPEC §7.7 names it) and
      `is_online(eng, id)` (trip-button state). Tested against `aggregates` before
      and after a trip — the indicator must *agree with the aggregate*, not merely
      be non-zero. Core suite: **266 → 273 tests**.
- [x] `ui/test/runtests.jl` — **33 tests, all offscreen**, plus `Test` wired into
      `ui/Project.toml`'s test target (UUID resolved by `Base.identify_package`,
      never hand-written). The controls are driven the way a user drives them:
      setting `b.clicks[]` runs the very handler a real click runs, so the
      click → `EventQueue` → `inject!` path is exercised end to end. Physics and
      pacing are deliberately **not** duplicated from the core suite.
- [x] **Comparison renders must pin both runs to one scale.** The live window's
      y-limits are expand-only (nobody can choose limits for a run that has not
      happened yet), which is right on screen and *wrong* for comparing two runs:
      each picture fills its own frame, so the first AC #6 pair drew a −0.93 Hz/s
      spike and a −3.6 Hz/s spike as visually identical shapes — the pictures
      argued against the very claim they were evidence for. `smoke_render` now
      takes `ylims_f`/`ylims_rocof`; the live window's behaviour is unchanged. A
      test asserts the pin holds against a dip that would otherwise force the box
      open, *and* that the same run unpinned does force it open.
- [x] The README's own launch one-liner was run end to end, not assumed:
      `window_open[]` is already `true` when `launch` returns, so `wait_for_close`
      blocks properly (6.32 s against a 6 s scripted close) and the loop stops on
      window close. Worth checking rather than reasoning about — had `display`
      not realised the window synchronously, the documented command would have
      exited instantly with no window and no error.
- [x] Report **Figure 3-67** as a layout target — **CLOSED at M3 step 7**, which
      gave it an acceptance criterion for the first time and then met it:
      `docs/images/fig-3-67-two-area.png`, rendered offscreen by
      `ui/scripts/figure_3_67.jl` from the two-area run, markers at the root-found
      shed instants. The original entry is kept below for the record, because the
      lesson is the entry and not the figure — it needed no new physics from the
      day it was written, and it drifted across two milestones anyway, purely
      because nothing it could fail was ever attached to it.

      > It needs no new physics (threshold lines, shed annotations and the
      > cumulative second axis are all computed already), and it ticked no
      > acceptance criterion, which is exactly why it drifted across two
      > milestones.

### What the headless batch added to core

- [x] `src/protection/load_shedding.jl` — `LoadShedStage` / `ShedLadder` /
      `shed_log` / `shed_total`, armed with `init!(…; shed = stages)`. One
      downward-crossing `ContinuousCallback` per stage in a `CallbackSet` (not one
      `VectorContinuousCallback` — per-stage closures beat sentinel bookkeeping at
      ~12 stages). **The sanctioned callback path:** it steps a *parameter* at a
      root-found instant, which is a real discrete event, not the forbidden
      post-hoc clamp of a state variable.
      Two traps, both now asserted: a disarmed stage's condition must hold the sign
      it had **after** firing (a `+1.0` sentinel manufactures a crossing at the
      disarm instant ⇒ double shed); and `affect!` is the *upcrossing* while
      `affect_neg!` is the *downcrossing* — tested in both polarities in one run,
      since `example_system` is underdamped enough to supply both crossings of the
      same threshold ~6 s apart.
      One expectation was **wrong and is recorded as such**: no explicit
      `derivative_discontinuity!` is needed here (unlike `inject!`), because
      `apply_callback!` sets it before invoking the affect for a
      `ContinuousCallback`. Checked in the DiffEqBase source *and* verified
      empirically — removing the call moves a 10× `dt` refinement by ~5e-14. The
      `dt`-refinement test stays as the guard, because that error would be
      invisible to any readout assertion (`current_state` recomputes RoCoF
      algebraically, so it would read correctly while the integration drifted).
- [x] Cumulative tripped **generation**: `eng.tripped_mw` and a `tripped_mw` vector
      in `state_series` — the second axis of report Figs 1-3 / 3-7 / 3-9. Shed load
      is not generation and does not leak into it.
- [x] `windowed_rocof` in `src/analysis/postprocess.jl` — the 500 ms sliding window
      every report RoCoF figure uses. An **additional** read; the instantaneous
      value stays the live readout and the closed-form validation target. NaN-padded
      to the input length so it overlays `f(t)`, and divided by the **actual**
      elapsed time rather than the nominal window.
- [x] `Printf` added to the test target (UUID resolved via `Base.identify_package`,
      never hand-written) — the script formats report timestamps and `Pkg.test()`'s
      sandbox does not carry undeclared stdlibs.

## ENTSO-E Iberian scenario (folded into the batches above)

Plan: `../plans/entsoe-iberia-reproduction.md`. Data: `../scenarios/iberia-2025-04-28.md`.

Prototyped and confirmed working with **zero new code** — the existing engine
tracks the report's frequency waypoints when fed the real event sequence. This
becomes the content of the headless script and the UI demo, replacing the
synthetic `example_system`.

- [x] Headless script `scripts/iberia_2025_04_28.jl`: staged sequence
      (`StepLoad(+317.3/S_base)` then trips of 355 / 725 / 930 / ≈2,600 MW at
      their reported timestamps), printing the waypoint comparison. No Makie.
      **No new mechanisms needed.** (AC #1.)
- [x] Promote those waypoints to test assertions. Done by **sign**, not by band:
      each pre-boundary waypoint must sit *below* the report (too deep) and within
      0.15 Hz. The 12:33:20 row is deliberately **not banded** — it is asserted as
      a known structural failure (the model recovers, reality collapsed), so
      closing it demands a conscious edit to the assertion rather than a parameter
      tuned until the number matches. The test includes the script as a module, so
      the scenario stays single-sourced.
      **The last row got worse on purpose:** +0.232 → **+1.211**, because arming
      the real defence plan removed the coincidental cancellation that made the old
      number look good. The 12:33:17 row also moved (49.669 → 49.705) — the 49.8 Hz
      stage fires at 12:33:17.405, i.e. *before* that waypoint.
- [x] Inverter-based resources: `GeneratingUnit(:PV, S, 0.0, P0, Inf, P0)` — now a
      regression test, including the all-IBR corner (`H_sys = 0`, `R_eq = Inf`,
      zero headroom, no `NaN`) and an end-to-end trip producing a finite dip.
- [x] Low-frequency load shedding as a **latching `ContinuousCallback` per
      threshold** — see "What the headless batch added to core" above. The script
      arms the full 12-stage Fig 3-67 ladder (15,532 MW); four stages fire, shedding
      3,907 MW, and **the model recovers at 49.50 Hz while reality collapsed**.
      That divergence is the honest headline, not a defect: the report's own
      numbers say ~15.5 GW was shed and the system went down anyway, because of
      ~5,000 MW of loss-of-synchronism export swing this model has no state for.
- [x] Cumulative tripped-MW accumulator on the recorded trajectory (the second
      axis in report Figs 1-3 / 3-7 / 3-9). Reported at the report's own
      checkpoints, flagged as a **lower bound** — the ≥2,600 MW cluster is a floor
      the report states as such.
- [x] **500 ms windowed RoCoF** as an additional post-processing read. Used for
      the one RoCoF claim inside the faithful window (|RoCoF| within 1 Hz/s until
      12:33:20.560, p.116), which the model satisfies. The report's −1 Hz/s and
      −2 Hz/s figures are *past* the boundary and are marked not-a-target in the
      script's own output. The instantaneous value remains the live readout and the
      closed-form validation target; a test asserts the windowed read is strictly
      shallower, so the two cannot be conflated later.
- [x] Decide consciously: load inertia. **Documented, not modelled** — `H_tot`
      sits entirely on the synchronous fleet. Exact for the frequency trajectory
      (the swing equation only sees the total); an approximation the moment load
      inertia would have to leave with shed load, which now matters since the
      ladder sheds 3.9 GW of it. No `H_load` field at M1.
      The published range ran as the sensitivity experiment and the result needed
      correcting mid-flight, which is worth remembering: **all three inertias give
      an identical armed nadir**, and that is *not* insensitivity to inertia — the
      2,638 MW stage at 49.5 Hz pins the nadir to a protection setting. Disarmed,
      the band moves the nadir ~0.08 Hz and moves it *deeper at higher inertia*,
      because keying `S_base` off measured kinetic energy makes the initial RoCoF
      exactly `f0·ΔP_MW/(2·KE)` — H-independent by construction — leaving only a
      base-rescaling artefact. So the ~1.2 Hz late-window gap **cannot** be blamed
      on inertia uncertainty. Both the identical column and the wrong-direction
      column are asserted in tests, so neither can be misread later as a result.

### Fidelity boundary — do not overclaim

The COI model **cannot** reproduce the final ~5 s. Of the ≥6,150 MW imbalance at
the −1 Hz/s point, ≈5,000 MW was export swing from loss of synchronism, which
has no representation in a two-state swing + governor model. Faithful window is
12:32:00 → ~12:33:19.6. Detail in the plan doc §2.

- Two-area / tie-line model (M2 candidate, evidence-backed and sweep-tested):
  see `docs/plans/entsoe-iberia-reproduction.md` §7. A 5-state probe closes the
  pre-separation bracket robustly (49.92–49.97 Hz across the whole parameter
  sweep vs report 49.94; the single-area model gives 49.859) and reproduces the
  Iberia/Continental-Europe separation to within ~1 s for any tie strength below
  ≈4,250 MW. One process, one integrator — **not** two coupled GridSim
  instances. Read §7.3 for which claims survive the sweep and which were
  retracted; `P_max` is a fitted parameter, not a figure from the report.
