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

## Current state of the repo (scaffold complete)

- `src/GridSim.jl` includes: `model/system_model.jl`, `events/events.jl`,
  `engines/interface.jl`. Loads clean; 18 scaffold tests pass.
- `model/system_model.jl`: `GeneratingUnit`, `SystemModel`, `example_system()`
  (a 4-unit, S_base=550 MVA, f0=50 Hz system).
- `events/events.jl`: `PerturbationEvent`, `TripGenerator`, `StepLoad`.
- `engines/interface.jl`: `SimulationEngine` + the generic verbs `init!`,
  `step!`, `solve!`, `current_state`, `state_series`, `inject!` (no methods yet).
- `engines/frequency_response.jl` and `orchestration/realtime_loop.jl` are
  **placeholders** (comments + outline), NOT yet `include`d by the module.
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

- `DifferentialEquations.jl` (big, heavy precompile) vs `OrdinaryDiffEq.jl`
  (lighter, enough for `Tsit5` + callbacks)? Lean toward `OrdinaryDiffEq` for TTFX.
- Exact mechanism for the ΔPm headroom saturation (in-RHS clamp of the derivative
  vs a `DiscreteCallback`/`ManifoldProjection`). Decide when writing the RHS.
- Whether the running nadir lives in the engine state record or is derived by the
  orchestration layer. (Leaning: engine records `(t,f,RoCoF)`, nadir derived.)
- `step!`/`solve!` collide with CommonSolve's exports once a DiffEq pkg loads —
  must `import CommonSolve: step!, solve!` and extend those, not the standalone
  generics in `engines/interface.jl`. See `m1-plan.md` Pitfalls.

## Reference

- Full brief: `../SPEC.md` (esp. §7 for M1, §3–4 for invariants, §8 non-goals).
- Project guide: `../../CLAUDE.md`.
