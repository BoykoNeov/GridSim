# M1 — Context

Where things live and what's been decided, so a fresh session can pick up M1
without re-deriving. Pairs with `m1-plan.md` and `m1-tasks.md`.

## Environment

- **OS:** Windows 11. **Shell:** PowerShell primary; Git Bash available.
- **Julia:** 1.12.6, installed via **juliaup** (winget pkg `Julialang.Juliaup`).
  `julia` resolves on PATH through the Windows Store alias
  (`%LOCALAPPDATA%\Microsoft\WindowsApps\julia.exe`). If a session can't find it,
  call that full path.
- **Core compat** is pinned to `julia = "1.10"` (forward-compatible; 1.12 runs it).
- `Manifest.toml` is **gitignored** (this is a package). Run `Pkg.instantiate()`
  after cloning.

## Current state of the repo (M1 steps 1–5 done: engine + orchestration)

- **Deps (core):** `CommonSolve`, `OrdinaryDiffEq` v7.0.1, `SciMLBase`, and
  `Observables` v0.5.5 (`Pkg.add`; caret `[compat]`). No Makie in core — now
  *asserted* by a `Pkg.dependencies()` closure test (with Observables as the
  positive control). `Pkg` itself is a test-only extra for that check.
- `src/GridSim.jl` includes: `model/system_model.jl`, `events/events.jl`,
  `engines/interface.jl`, `engines/frequency_response.jl`, and
  `orchestration/realtime_loop.jl`. Loads clean; **116 tests pass**.
- `model/system_model.jl`: `GeneratingUnit`, `SystemModel`, `example_system()`
  (a 4-unit, S_base=550 MVA, f0=50 Hz system).
- `events/events.jl`: `PerturbationEvent`, `TripGenerator`, `StepLoad`.
- `engines/interface.jl`: `SimulationEngine`; GridSim-owned generic verbs `init!`,
  `current_state`, `state_series`, `inject!`, `timestep`; `step!`/`solve!`
  imported from `CommonSolve` and re-exported (one shared generic with SciML).
  Tests assert the same identity holds for `OrdinaryDiffEq` (both verbs).
- `engines/frequency_response.jl`: `aggregates` (COI `H_sys`/`R_eq`/`D`/`Tg`/
  `headroom`), `FRParams`, `fr_rhs!` (headroom saturation **in the derivative**),
  and `FrequencyResponseEngine{I}` with `init!`/`step!`/`current_state`/
  `state_series`/`timestep`/`inject!`.
- `orchestration/realtime_loop.jl`: `EventQueue` + `drain!`, `RealtimeControl` +
  `stop!`, and `run_realtime!`. Engine-agnostic (interface verbs only), publishes
  each state to an `Observable`, paces to wall-clock with re-anchoring instead of
  debt accumulation, `rtf = Inf` for the flat-out headless path. Designed to run
  as an `@async` task beside a GLMakie window (never `Threads.@spawn` — GLMakie is
  not thread-safe and the Observable write is what drives the redraw).
- `ui/` is a **separate package** (`GridSimUI`, own Project.toml), empty deps.

## Key decisions (and why)

- **Scaffold-first, M1 code next batch.** The handoff/spec are validation-first;
  with no engine numerics yet, we ship only the durable contracts that load+test.
- **Don't hand-write package UUIDs.** Always `Pkg.add`. The one exception present
  is `Test` (stdlib, fixed UUID `8dfed614-…`) wired via `[extras]`/`[targets]`.
- **No-Makie-in-core is structural,** via the separate `ui/` environment — not a
  lint rule. Add a test asserting the core closure excludes Makie during M1.
- **Engine choice:** `Tsit5` (non-stiff is fine for the COI model); keep the
  solver swappable on the engine for future stiff tiers (`Rodas5`/`FBDF`).

## Open questions to resolve during M1

- ~~`DifferentialEquations.jl` vs `OrdinaryDiffEq.jl`?~~ **RESOLVED:** chose
  `OrdinaryDiffEq` v7.0.1 (lighter closure, Makie-free; still bundles `Tsit5` now
  and `Rodas5`/`Verner` for later stiff tiers). `DifferentialEquations` rejected
  as too heavy for M1.
- ~~Exact mechanism for the ΔPm headroom saturation.~~ **RESOLVED (step 3):**
  saturation in the derivative (`fr_rhs!` zeroes `dΔPm` at the ceiling — which also
  gives release for free), with an `isoutofdomain` guard on top that *rejects and
  retries* an overshooting step (never writes state, so not the forbidden post-hoc
  clamp), plus a discrete re-init of `ΔPm` to the new ceiling inside `inject!`.
- ~~Whether the running nadir lives in the engine or is derived by orchestration.~~
  **RESOLVED:** the engine tracks it (`eng.nadir`, updated in `_record!`) — the
  orchestration loop stays a pure driver and holds no physics state.
- **Trajectory history is unbounded** (`ts/fs/rocofs/pms` grow on every step). Fine
  for scripts/tests; needs a ring buffer or decimation before long UI sessions.
  Tracked in `m1-tasks.md` under "Known, deferred".
- ~~`step!`/`solve!` collide with CommonSolve's exports~~ **RESOLVED (scaffold
  batch):** `CommonSolve` is now a direct core dep and `engines/interface.jl` does
  `import CommonSolve: step!, solve!`, so we share one generic with the SciML
  stack. `GridSim.step! === CommonSolve.step!` (regression test). `init!` and the
  other verbs stay GridSim-owned. See `m1-plan.md` Pitfalls.

## Reference

- Full brief: `../SPEC.md` (esp. §7 for M1, §3–4 for invariants, §8 non-goals).
- Project guide: `../../CLAUDE.md`.
