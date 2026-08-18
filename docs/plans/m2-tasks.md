# M2 — Task checklist

Checklist for the Milestone 2 batches. See `m2-plan.md` for the approach and
`m2-context.md` for decisions and the spike measurements behind them.

## Dependency spike (DONE — pre-plan)

- [x] `NetworkDynamics` v1.1.0 and `Graphs` v1.14.0 resolve against GridSim's
      existing `[compat]`; bumps `OrdinaryDiffEq` 7.0.1 → 7.6.0 and `SciMLBase`
      3.30.1 → 3.49.1, both **upgrades inside the current bounds**.
- [x] Steppable integrator via `init` + `step!(integ, dt, true)` — works.
- [x] Live parameter mutation takes effect (`NWParameter(integrator)`, then
      `auto_dt_reset!` + `derivative_discontinuity!`) — verified against the
      analytic new equilibrium `asin(P/K′)`.
- [x] `pflat(NWParameter(integ)) === integ.p` — M1's shared-mutable-parameter
      identity carries over rather than needing re-engineering.
- [x] Two-machine closed-form swing frequency: 2.0121 Hz predicted, 2.0121 Hz
      measured.
- [x] `find_fixpoint` converges on a 3-machine ring (residual 1.4e-17) despite the
      swing model's rotational symmetry, and reproduces every specified injection.
- [x] `PowerDynamics` v5.0.0 resolves but costs 123 extra packages
      (ModelingToolkit / Symbolics / DataFrames, ~305 s precompile) for a component
      library M2 does not need — **deferred, not rejected.**

## Step 1 — dependency bump, on its own commit (next)

- [ ] `julia --project=. -e 'import Pkg; Pkg.add(["NetworkDynamics","Graphs"])'`
      (never hand-write UUIDs).
- [ ] **Re-run the full M1 suite before writing any M2 code.** The solver bump is
      the risk; discovering it while debugging new physics is the expensive way.
      Record the result here either way — a green run is evidence, not a formality.
- [ ] Extend the no-Makie dependency-closure test so the new deps are covered by
      it, and confirm the positive control still makes it non-vacuous.

## Step 2 — canonical network model

- [ ] `src/model/network_model.jl`: `Bus`, `Branch`, `Machine`, `NetworkModel`.
      Concrete field types only; numeric arrays kept separate from topology and
      metadata (SPEC §4).
- [ ] Field semantics chosen to map onto PowerSystems concepts, and construction
      through a function, so `from_powersystems` can be a sibling constructor later
      (D5).
- [ ] `two_machine_system()` — the case with a closed form.
- [ ] `three_machine_ring()` — the case without one.
- [ ] Constructor guards in the spirit of `GeneratingUnit`'s headroom check: reject
      a model that is wrong on its face rather than letting it poison a solve.

## Step 3 — the swing engine

- [ ] `src/engines/swing.jl`: NetworkDynamics vertex model (machine) and edge model
      (branch), assembled into a `Network` compiled *from* `NetworkModel`.
- [ ] `SwingEngine <: SimulationEngine` — `init!`, `step!`, `current_state`,
      `state_series`, `timestep`, `inject!`. Parametric on the concrete integrator
      type, built through `init!` as constructor of record (same shape as
      `FrequencyResponseEngine`).
- [ ] `current_state` exposes per-machine angle and speed **and** the
      inertia-weighted system frequency — they are different quantities and the
      names must not blur (`ω_coi = Σ Hᵢ·ωᵢ / Σ Hᵢ`).
- [ ] Accessors for whatever the UI needs, so `ui/` never reaches into engine
      fields (the `system_inertia` / `is_online` precedent).

## Step 4 — initialization, with its tests in the same step

- [ ] Steady state via `find_fixpoint`; no hand-rolled power flow (D6).
- [ ] **V1 flat start**: `max|du| < 1e-10` at `t = 0`, and a 2 s pre-disturbance
      window stays flat. Acceptance criterion, not a nicety.
- [ ] **V2 injection check**: each machine's computed electrical power equals its
      specified mechanical power to `1e-8`. This is the sign-convention test — a
      flipped sign still oscillates, still settles, still has a nadir.
- [ ] Tests assert angle **differences**, never absolute angles (rotational
      symmetry means the gauge is arbitrary).

## Step 5 — events

- [ ] `inject!(::SwingEngine, ::TripGenerator)` — reuse the M1 event type; zero the
      machine's coupling and mechanical power, **do not resize the state vector**.
- [ ] `TripLine(from, to)` — new event; zero that branch's coupling. Template is
      NetworkDynamics' `cascading_failure.jl` example.
- [ ] Both paths call `derivative_discontinuity!` and `auto_dt_reset!`, and both
      are tested for it — the M1 lesson was that a stale cached derivative injects
      a small persistent error that no assertion catches unless one is written.
- [ ] A tripped machine is excluded from the aggregate frequency read-out even
      though its state keeps integrating.

## Step 6 — the COI view, derived

- [ ] `coi_model(net::NetworkModel) -> SystemModel` (D4) — the aggregate model is a
      compiled view, never a hand-maintained copy.
- [ ] **V4 cross-fidelity**: same trip through `SwingEngine` and through
      `FrequencyResponseEngine` on `coi_model(net)`. Assert **both** that they
      track early **and** that they diverge later — asserting only the agreement
      lets the test pass vacuously.
- [ ] Write down, in the test or beside it, *what* the divergence is (inter-machine
      swings the aggregate model averages away) so the number is not mistaken for a
      defect.
- [ ] **V5**: no dense network matrix is ever assembled.

## Step 7 — UI

- [ ] Per-machine rotor angle / speed traces plus the aggregate overlay.
- [ ] Offscreen render verified before anything is claimed about the live window —
      the M1 practice, and the reason M1's UI claims held up.
- [ ] Pinned axes for any comparison render (the M1 fix at `bb644f4`: an unpinned
      pair of panels argues against itself).
- [ ] Draw from fixed-capacity buffers, not from engine trajectory vectors.

## Carried over from M1 — decide, don't drift

- [ ] **Unbounded trajectory growth.** Both engines now have the same shape. Fix it
      once in a shared recording facility rather than duplicating the leak. Decide
      where it lives *before* `SwingEngine` grows its own vectors — retrofitting
      two engines costs more than designing one.
- [ ] Report **Figure 3-67** as a layout target — still open, still ticks no
      acceptance criterion.

## Known hazards to check off explicitly

- [ ] The two-machine closed form re-derived against the **real** code path, not
      copied from the spike — the spike hard-coded its coupling, the real model
      computes it from internal voltage and reactance, and that is one more place a
      per-unit convention can go wrong.
- [ ] Per-machine speed deviation is not M1's aggregate deviation. Check the names
      in the exported API do not invite the confusion.
- [ ] Check new exports against `GLMakie` before writing UI code — the collision
      hazard that cost a round in M1 (`stop!`, `timestep`, `drain!`).
- [ ] Any long-running loop test self-terminates (finite duration, or a state
      stopper plus a wall-clock watchdog). A hung suite is worse than a failing one.
