# M1 — Real-time frequency & RoCoF after generator loss · Plan

Living document for the Milestone 1 implementation batch. Source of truth for the
*what/why* is `docs/SPEC.md` §7; this is the *how*. Companion files:
`m1-context.md` (where things live, decisions), `m1-tasks.md` (checklist).

## Goal

A real-time-steppable engine that simulates aggregate (center-of-inertia) system
frequency, lets the user trip a generator *while it runs*, and shows `f(t)`, RoCoF,
and nadir live. Acceptance criteria: `docs/SPEC.md` §7.8.

## Approach (incremental, each step commits & tests green)

1. **Dependencies.** Add to the core via `Pkg.add` (never hand-write UUIDs):
   `DifferentialEquations` (or the lighter `OrdinaryDiffEq`), `Observables`,
   `SparseArrays` (stdlib, for the habit/test plumbing — not strictly needed at
   M1 size). Keep the core free of Makie.
2. **Aggregates.** Pure function `aggregates(model, online_set) -> (H_sys, R_eq, D, Tg)`
   computing, on system base: `H_sys = Σ H_i·S_i / S_base`,
   `1/R_eq = Σ (1/R_i)·(S_i/S_base)`. Unit-test against hand arithmetic.
3. **ODE.** Two states `(Δω, ΔPm)`; parameters in a **mutable** struct `p` so
   events can change them. RHS (SPEC §7.2):
   - `dΔω/dt  = (ΔPm − D·Δω + ΔP_dist) / (2·H_sys)`
   - `dΔPm/dt = (−Δω/R_eq − ΔPm) / Tg`     ← with headroom saturation, see Pitfalls
4. **Engine.** `mutable struct FrequencyResponseEngine <: SimulationEngine`:
   - `init!(eng, model; t0=0.0, dt)` → build `ODEProblem`, `init` a `Tsit5`
     integrator; keep solver swappable on the engine (stiff tiers want `Rodas5`).
   - `step!(eng, dt)` → `step!(integrator, dt, true)`; record `(t, f, RoCoF)`,
     where `f = f0·(1+Δω)` and `RoCoF = f0·dΔω/dt`.
   - `current_state(eng)` → `(t, f, Δω, RoCoF, ΔPm)`; track running nadir.
   - `inject!(eng, ::TripGenerator)` → drop unit `k` from the online set,
     recompute `H_sys`/`R_eq`/`headroom`, `ΔP_dist -= P_k/S_base`. `Δω` stays
     continuous; `ΔPm` is re-init'd down to the new (shrunken) headroom if it was
     above it, and `u_modified!` invalidates the FSAL cache — a discrete event, not
     a bare parameter poke.
   - `inject!(eng, ::StepLoad)` → `ΔP_dist -= ΔP_pu` (added load ⇒ negative
     imbalance; nice-to-have), then `u_modified!`.
5. **Orchestration** (`src/orchestration/realtime_loop.jl`, NO Makie): event
   queue + `drain!`, `run_realtime!(engine, state_obs; rtf)` with wall-clock
   pacing via `Observables`. Headless: a script can run it and collect the series.
6. **Validation tests** — DONE (the learning payoff, SPEC §7.6; see Pitfalls for
   the exact closed forms). Closed forms swept over every unit at `rtol = 1e-6`,
   plus the low-inertia lesson asserted two ways: an inertia-only isolation
   (settling frequency provably unchanged, only the undershoot deepens) and the
   fewer-units-online demonstration. 177 tests green at that point; per-item
   detail and the testset names are in `m1-tasks.md`.
7. **Headless script** — DONE, proving AC #1 (frequency trajectory, no Makie) on
   the real ENTSO-E Iberian scenario rather than `example_system`. It pulled three
   mechanisms into core, in two new directories:
   - `src/protection/load_shedding.jl` — `LoadShedStage`/`ShedLadder`, armed via
     `init!(…; shed = stages)`; one downward-crossing `ContinuousCallback` per
     stage, root-finding the firing instant. The **sanctioned** callback path: it
     steps a parameter at a real discrete event, not the forbidden post-hoc clamp.
   - `src/analysis/postprocess.jl` — `windowed_rocof`, the 500 ms sliding window
     the ENTSO-E figures use. An *additional* read; the instantaneous value stays
     the live readout and the closed-form validation target.
   - Cumulative tripped **generation** on the engine, so the recorded trajectory
     is now `ts/fs/rocofs/pms/tripped_mws` and `state_series` gains `tripped_mw`.
   266 tests green. Detail, and the two mid-flight corrections the batch made to
   its own claims, are in `m1-tasks.md`.
8. **UI** in `ui/` (separate env) — DONE. Live `f(t)` plot + a `RoCoF(t)` trace +
   readouts + per-unit trip + play/pause + rtf slider + an `H_sys` indicator with a
   ghost of its pre-trip value. AC #2, #3 and #6 are ticked. Two decisions carried
   the batch:
   - **One `_build_window`, two entry points.** `launch` opens the real window;
     `smoke_render` builds the *same* figure offscreen and saves a PNG. Sharing the
     builder is what stops the verifiable artifact from drifting away from the
     thing the user actually sees — and the offscreen path is the only reason the
     window could be checked at all from a session with no screen.
   - **The window owns its plot buffers.** Fixed-capacity `RollingTrace`s plus a
     moving x-window and expand-only y-limits, rather than plotting the engine's
     ever-growing trajectory vectors. That is SPEC §3's "render state ≠ simulation
     state" paying for itself: it sidesteps the quadratic redraw *and* the
     unreadable compressed time axis. The expand-only limits are driven by running
     extremes accumulated on **every published state**, not by whatever state a
     30 fps repaint happens to sample — sampling clips the nadir, which is exactly
     the feature the window exists to show. (First render got this wrong and the
     dip was cut off by the axis box; the picture caught it.)
   Still open, deliberately: report **Figure 3-67** as a layout target (no new
   physics needed, but it ticks no acceptance criterion).

## Validation (closed-form — assert in `test/`)

- **Initial RoCoF** at the instant of a trip (`Δω=0, ΔPm=0`):
  `RoCoF0 = f0·ΔP_dist/(2·H_sys) = −f0·(P_k/S_base)/(2·H_sys)`.
- **Settling deviation, no AGC:** `Δω_ss = ΔP_dist / (D + 1/R_eq)`.
- **Monotone lesson:** fewer/less-inertia units online ⇒ steeper RoCoF, deeper
  nadir. Assert the ordering across two configs.
- Cross-fidelity vs PSID is a *later* milestone — not blocking M1.

## Pitfalls / carried-forward review notes

- **ΔPm headroom clamp = saturation in the derivative or a solver callback,
  NEVER post-hoc clamping of the state.** Clamping a state variable without
  touching its derivative corrupts the integration (the integrator keeps
  accumulating against a value you silently overwrote). Implement as: when ΔPm is
  at the aggregate headroom and its derivative would push further, zero that part
  of the derivative (or use a `PositiveDomain`/callback). Test that ΔPm never
  exceeds `Σ headroom_i / S_base`.
- **Mutable `p`, but type-stable.** Concrete fields; the online set changing must
  not introduce abstract containers in the RHS hot path.
- **`step!`/`solve!` name collision with CommonSolve — RESOLVED (scaffold batch).**
  `CommonSolve.jl` (re-exported via SciMLBase → OrdinaryDiffEq/DifferentialEquations)
  owns `step!` and `solve!`; had we kept them as GridSim-owned generics, the moment
  an engine did `using OrdinaryDiffEq` both would be in scope and an unqualified
  `step!(integrator, dt, true)` would error. Fix applied: `CommonSolve` added as a
  direct core dep (zero-dependency interface package — no heavy precompile, no
  Makie), and `engines/interface.jl` now does `import CommonSolve: step!, solve!`
  (the standalone `function step! end`/`solve! end` are gone). Engine methods will
  extend **those** generics. The other verbs — `init!`, `current_state`,
  `state_series`, `inject!` — stay uniquely ours (CommonSolve has `init`, not
  `init!`). Proven at scaffold time by `GridSim.step! === CommonSolve.step!` (a
  regression test); the `===` makes an export-ambiguity warning impossible. The
  final empirical check — `OrdinaryDiffEq.step! === CommonSolve.step!` — lands when
  the DiffEq dep is added in the M1 code batch (tracked in `m1-tasks.md`).
- **Integrator interface, not `solve()`** — so events/redraws interleave (SPEC §6).
- **No Makie in core** — verify the core dep closure excludes Makie (add a test).
- Trip-sign sanity: losing generation is a *negative* injection → `ΔP_dist` goes
  negative → frequency dips. Matches `RoCoF0` sign above.

## Out of scope for M1 (SPEC §8)

PowerSystems.jl data model · multi-machine/network solves · other engines ·
markets/OPF · maps. AGC (secondary control) is an *optional* add-on after the base
works, not required.
