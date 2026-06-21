# GridSim — project guide for Claude

Power-grid simulator in **Julia (≥1.10)**. Grows from a tiny correct frequency
model toward a full energy-system simulator. Single user, single process, no
server. Full spec: `docs/SPEC.md`. Current milestone plan: `docs/plans/`.

This layers on top of the global `~/.claude/CLAUDE.md`; that still applies.

## Architecture invariants (do not violate — see SPEC §3–4)

- **Core has zero UI dependency.** `src/` (the `GridSim` package) must NEVER
  import Makie or any plotting/UI package. This is enforced *structurally*: UI
  lives in `ui/` (a separate package that depends on `GridSim`, never the
  reverse). Do not add Makie to the root `Project.toml`. Live state crosses the
  seam via `Observables.jl` (standalone; safe in core), not a socket.
- **One process. No client/server / IPC.** A socket between core and UI is wrong.
- **One canonical model.** Reduced/surrogate models are *compiled views derived
  from it*, never hand-maintained parallel copies.
- **Render state ≠ simulation state.** UI state (positions, camera, selection,
  colors) is derived and lives separately from physics state.
- **Fidelity tiers + mode router.** Every physics gets a fast surrogate and an
  accurate sibling behind the one `SimulationEngine` interface
  (`src/engines/interface.jl`). Real-time engines do `init!`/`step!`/`inject!`;
  playback engines do `init!`/`solve!`/`state_series`.

## Conventions (SPEC §6)

- **Per-unit internally** on system base `S_base`; convert to engineering units
  (MW, Hz) only at the UI boundary. Document `S_base` and `f0`.
- **Integrator, not `solve()`, for real-time engines.** Drive
  DifferentialEquations.jl via `init(prob, solver)` + `step!(integrator, dt, true)`
  so the loop can interleave events/redraws. Perturbations mutate `integrator.p`.
- **Sparse from day one.** When network solves appear, never build a dense
  admittance (Y-bus) matrix — use `SparseArrays`, even on toy systems.
- **Type stability.** Concrete-typed struct fields only. Abstractly-typed fields
  are Julia's single biggest performance cliff.
- **Struct-of-arrays** for numeric parameter arrays (GPU/batched-friendly), kept
  separate from topology/metadata. (Habit now; matters at scale.)
- **Validation-first.** Every engine ships a reference check (closed-form or
  cross-fidelity). This is also the main learning payoff.

## Milestone 1 scope (SPEC §7)

Real-time aggregate (center-of-inertia) frequency & RoCoF after generator loss.
Only `FrequencyResponseEngine` — do NOT build the engine zoo. Do NOT adopt the
full PowerSystems.jl data model yet; use the minimal `SystemModel`
(`src/model/system_model.jl`).

**Carried-forward correctness note:** the "clamp ΔPm to headroom" requirement
must be a **saturation in the derivative / a solver callback**, NOT post-hoc
clamping of the state variable (which corrupts the integration).

## Working in this repo

- **Run Julia:** `julia` is on PATH via juliaup (Windows Store alias). If a
  session can't find it: `"$LOCALAPPDATA\Microsoft\WindowsApps\julia.exe"`.
- **Load core:** `julia --project=. -e 'using GridSim'`
- **Run tests:** `julia --project=. -e 'import Pkg; Pkg.test()'`
- **Add a dependency:** `julia --project=. -e 'import Pkg; Pkg.add("Foo")'`.
  NEVER hand-write package UUIDs into `Project.toml` — let `Pkg` resolve them.
  (`Test`, an stdlib, is the one already wired, via `[extras]`/`[targets]`.)
- `Manifest.toml` is gitignored (this is a package, not a pinned app).

## Workflow

- **Plan first** for non-trivial work; keep the M1 plan trio in `docs/plans/`
  (`m1-plan.md` / `m1-context.md` / `m1-tasks.md`) as living documents.
- **Commits:** Conventional Commits, small and incremental; each commit should
  load and pass tests. Don't reference "Claude"/"AI" in commit subjects (the
  `Co-Authored-By` trailer is fine).
- **Batch end / "session end":** update memory + the relevant docs, then commit
  and push. (Standing instruction from the user.)
- Repo: https://github.com/BoykoNeov/GridSim (public).
