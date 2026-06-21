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

- [ ] Add deps via `Pkg.add` (OrdinaryDiffEq vs DifferentialEquations decided).
- [ ] When the DiffEq dep lands, assert **both** `OrdinaryDiffEq.step! ===
      CommonSolve.step!` *and* `OrdinaryDiffEq.solve! === CommonSolve.solve!`
      empirically — that's the moment the real collision would have surfaced (for
      the real-time *and* the playback verb) and the proof our `import CommonSolve`
      resolution is sound for the whole interface.
- [ ] `aggregates(model, online)` + unit test vs hand arithmetic.
- [ ] Mutable, type-stable parameter struct `p`.
- [ ] ODE RHS for `(Δω, ΔPm)` with **headroom saturation in the derivative**.
- [ ] `FrequencyResponseEngine`: `init!`, `step!`, `current_state`.
- [ ] `inject!(::TripGenerator)` (states continuous, params recomputed).
- [ ] `inject!(::StepLoad)` (nice-to-have).
- [ ] Include the engine file in `GridSim.jl`.

## Orchestration (next batch)

- [ ] Event queue + `drain!`.
- [ ] `run_realtime!(engine, state_obs; rtf)` with wall-clock pacing (Observables).
- [ ] No Makie import (assert core closure excludes Makie).

## Validation tests (next batch)

- [ ] Initial RoCoF matches `−f0·(P_k/S_base)/(2·H_sys)` within tol.
- [ ] Settling `Δω_ss = ΔP_dist/(D + 1/R_eq)` within tol.
- [ ] Monotone lesson: less inertia ⇒ steeper RoCoF + deeper nadir (ordering).
- [ ] ΔPm never exceeds aggregate headroom.

## Headless proof & UI (next batch)

- [ ] `scripts/` generator-trip experiment → frequency trajectory, no Makie (AC #1).
- [ ] `ui/` GLMakie: live `f(t)`, readouts (f, RoCoF, nadir), per-unit trip,
      play/pause, rtf slider, `H_sys` indicator (AC #2, #3, #6).
