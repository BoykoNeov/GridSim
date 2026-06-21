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
     recompute `H_sys`/`R_eq`, `ΔP_dist -= P_k/S_base`. States `(Δω, ΔPm)` stay
     continuous — only `p` changes (this is why M1 needs no algebraic re-init).
   - `inject!(eng, ::StepLoad)` → `ΔP_dist += ΔP_pu` (nice-to-have).
5. **Orchestration** (`src/orchestration/realtime_loop.jl`, NO Makie): event
   queue + `drain!`, `run_realtime!(engine, state_obs; rtf)` with wall-clock
   pacing via `Observables`. Headless: a script can run it and collect the series.
6. **Validation tests** (the learning payoff, SPEC §7.6) — see Pitfalls for the
   exact closed forms.
7. **Headless script** in `scripts/` proving AC #1 (frequency trajectory, no Makie).
8. **UI** in `ui/` (separate env): live `f(t)` plot + readouts + per-unit trip +
   play/pause + rtf slider, and an `H_sys` indicator. Proves AC #2, #3, #6.

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
- **Integrator interface, not `solve()`** — so events/redraws interleave (SPEC §6).
- **No Makie in core** — verify the core dep closure excludes Makie (add a test).
- Trip-sign sanity: losing generation is a *negative* injection → `ΔP_dist` goes
  negative → frequency dips. Matches `RoCoF0` sign above.

## Out of scope for M1 (SPEC §8)

PowerSystems.jl data model · multi-machine/network solves · other engines ·
markets/OPF · maps. AGC (secondary control) is an *optional* add-on after the base
works, not required.
