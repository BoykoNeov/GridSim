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

- [ ] **Unbounded trajectory growth.** The engine pushes to `ts/fs/rocofs/pms` on
      every step forever — the same unbounded-memory problem the engine already
      avoids for the integrator's own storage (`save_everystep=false`). Harmless at
      test/script scale; it will show up in the UI batch over a multi-minute run.
      Fix later with a ring buffer or a decimated history, not by re-designing the
      engine now.
- [ ] **An exception inside an `@async` loop is silent.** `step!` deliberately
      `error()`s on a bad integrator retcode ("fail loud, not silent"), but once
      `run_realtime!` runs as `@async` with nobody calling `wait`, that throw kills
      the task quietly — the UI would simply stop updating with no message. Only
      bites in the async configuration, so no current test catches it. The UI batch
      must add `Base.errormonitor` on the task, or a `try`/`catch` that publishes
      the error into an Observable the window can display.
- [ ] **Check the new exports against GLMakie before writing UI code.** `ui/` will
      do `using GridSim, GLMakie`, and this batch exported `stop!`, `timestep`, and
      `drain!` — the same collision hazard that cost a round on `step!`/`solve!`.
      Run `julia -e 'using GLMakie; for n in (:stop!, :timestep, :drain!);
      println(n, " => ", isdefined(GLMakie, n)); end'` and decide rename-vs-qualify
      up front, not via an ambiguity error mid-UI-work.

## Validation tests (next batch)

- [ ] Initial RoCoF matches `−f0·(P_k/S_base)/(2·H_sys)` within tol.
- [ ] Settling `Δω_ss = ΔP_dist/(D + 1/R_eq)` within tol.
- [ ] Monotone lesson: less inertia ⇒ steeper RoCoF + deeper nadir (ordering).
- [ ] ΔPm never exceeds aggregate headroom.

## Headless proof & UI (next batch)

- [ ] `scripts/` generator-trip experiment → frequency trajectory, no Makie (AC #1).
- [ ] `ui/` GLMakie: live `f(t)`, readouts (f, RoCoF, nadir), per-unit trip,
      play/pause, rtf slider, `H_sys` indicator (AC #2, #3, #6).
