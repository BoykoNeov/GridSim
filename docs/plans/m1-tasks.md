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
