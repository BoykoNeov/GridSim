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

## Where the project stands (updated 2026-11-13)

Milestones 1–11 are done. This section used to describe Milestone 1's scope ("only
`FrequencyResponseEngine`, do not build the engine zoo"); that scope ended with M1 and
the text was stale for ten milestones.

- **Three dynamic tiers** behind the one interface: aggregate
  (`FrequencyResponseEngine`), network swing (`SwingEngine`), detailed
  (`DetailedEngine`). **Steady state** in `src/steadystate/`: power flows, dispatch
  with and without the network, single and double outage screens, frequency verdicts.
- **Nine windows** in `ui/`, one launcher (`GridSim.bat` → `ui/scripts/start.jl`).
- **`NetworkModel` is the canonical model.** Adopting `PowerSystems.jl` as the data
  model was measured to work and refused on purpose (`docs/plans/m6-context.md` D1).
- **What is next is the owner's choice**, and a milestone names the hard thing it is
  for (its "hurdle") before it is planned: `docs/plans/README.md` (the index and the
  hurdle list), `docs/plans/next-steps.md` (ready work packages and the candidates).
- **Unfamiliar word?** `docs/glossary.md` — and write for the owner in those plain
  terms, not in the plans' shorthand.

**Carried-forward correctness note (M1, still live in every tier):** a limit on a
state — a governor's power ceiling, a regulator's output limits — must be a
**saturation in the derivative and/or a solver callback that lands on the limit**
(`_governor_cap_callbacks` in `src/engines/detailed.jl`), NEVER post-hoc clamping of
the state variable (which corrupts the integration).

**A change that can move a recorded number** takes the captures before the first
edit and again after, and compares them byte for byte
(`docs/evidence/gridsim-m9/harness/README.md`). A green suite is not that check: its
assertions carry tolerances.

## Working in this repo

- **Run Julia:** `julia` is on PATH via juliaup (Windows Store alias). If a
  session can't find it: `"$LOCALAPPDATA\Microsoft\WindowsApps\julia.exe"`.
- **Load core:** `julia --project=. -e 'using GridSim'`
- **Run tests:** `julia --project=. -e 'import Pkg; Pkg.test()'`
- **Add a dependency:** `julia --project=. -e 'import Pkg; Pkg.add("Foo")'`.
  NEVER hand-write package UUIDs into `Project.toml` — let `Pkg` resolve them.
  (`Test`, an stdlib, is the one already wired, via `[extras]`/`[targets]`.)
  `Pkg.add` REWRITES the target `Project.toml` and drops every comment in it
  (it did to `ui/Project.toml` on 2026-09-05) — `git diff` it afterwards and
  put the comments back.
- `Manifest.toml` is gitignored (this is a package, not a pinned app).
- **Evidence** the plan docs cite (predictions, spikes, gate captures) lives in
  `docs/evidence/`; the runnable gate harness is `docs/evidence/gridsim-m9/harness/`.
  Scratch output still goes to `W:\temp\claude`, never into the repo.

## Workflow

- **Plan first** for non-trivial work; each milestone keeps a plan trio in
  `docs/plans/` (`mN-plan.md` / `mN-context.md` / `mN-tasks.md`) as living documents.
- **A UI change is not done until its figure is rendered and looked at**
  (`julia --project=ui ui/scripts/figures.jl <scratch folder>`).
- **Commits:** Conventional Commits, small and incremental; each commit should
  load and pass tests. Don't reference "Claude"/"AI" in commit subjects (the
  `Co-Authored-By` trailer is fine).
- **End of a work batch, end of planning, or "session end":** ALWAYS update
  memory + the relevant docs, then commit and push **to `main`**. Don't ask at
  these checkpoints — it's standing, durable authorization from the user.
- Repo: https://github.com/BoykoNeov/GridSim (public).
