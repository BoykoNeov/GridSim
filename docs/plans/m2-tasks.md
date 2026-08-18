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

## Step 1 — dependency bump, on its own commit (DONE)

- [x] `NetworkDynamics` v1.1.0 + `Graphs` v1.14.0 added via `Pkg.add`. **`Pkg` wrote
      the `[compat]` entries itself**, matching the house convention (floor =
      version resolved at add time) — nothing hand-edited.
- [x] **M1 suite run before the add as a baseline** (273/273) so the "after" number
      means something, and again after.
- [x] **The spike's version prediction did not hold, and that is the finding.** The
      real repo kept `OrdinaryDiffEq` 7.0.1 / `SciMLBase` 3.30.1 because it already
      had a `Manifest.toml` and Pkg preferred the minimal change. The spike's copy
      had none, so it resolved fresh to 7.6.0 / 3.49.1. **Both were then tested:
      273/273 either way.** Since the manifest is gitignored, a fresh clone gets the
      *second* resolution — so the developer machine is systematically the stale
      one, and the fresh resolve is the one that must be tested.
- [x] `derivative_discontinuity!` and `successful_retcode` — the two SciMLBase
      internals M1 reaches for by name, and exactly what a minor-version move
      relocates — verified to resolve under **both** versions.
- [x] No-Makie dependency-closure test strengthened: `NetworkDynamics` and `Graphs`
      added as explicit positive controls (the scan is only evidence about the new
      closure if it demonstrably *read* the new closure), plus a wider negative —
      a transitive plotting dep would violate SPEC §3.1 without containing the
      string "Makie".

## Step 2 — canonical network model (DONE)

- [x] `src/model/network_model.jl`: `Bus`, `Branch`, `Machine`, `NetworkModel`.
      Concrete field types only (asserted with `isconcretetype`). The canonical
      model is array-of-structs; the contiguous numeric arrays the engine
      integrates against are **derived** (`machine_arrays` / `branch_arrays`),
      never stored — the SPEC §4 habit without a second copy to keep in sync.
- [x] Field semantics map onto PowerSystems concepts (mapping written down in the
      file header), and all validation lives in the inner constructor, so
      `from_powersystems` can be a sibling constructor that cannot bypass it (D5).
- [x] `two_machine_system()` — the case with a closed form.
- [x] `three_machine_ring()` — the case without one.
- [x] Constructor guards, each with its own test asserting the *message* (so a
      guard test cannot pass because a different guard fired): duplicate ids ·
      unknown bus references · a bus with no machine or with two · parallel
      circuits · disconnected network · `Σ P0 ≠ 0` · `|P0ᵢ| > Σⱼ K_ij`.
- [x] **FINDING, recorded not patched: "E′ behind X′d" is not realisable on a
      meshed network under D2 + D3.** Folding the end reactances into each branch
      double-counts the internal reactance of any machine with more than one line.
      M2a therefore puts `E′` at the bus: `K_ij = E′ᵢE′ⱼ/X_ij`, exact on every
      topology (D8). `Machine.Xd′` stays as carried, validated data for M2b, with
      a regression test that ×10 on every `X′d` moves no coupling. Full write-up
      in `m2-context.md`.
- [x] 350/350 core tests green (273 entering M2), on the fresh resolve as well as
      the incremental one.

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

- [x] **Unbounded trajectory growth — DONE, on its own commit before the engine.**
      `src/engines/recorder.jl`: a shared, fixed-capacity `TrajectoryRecorder` that
      **decimates** when full (halve the buffer, halve the rate from then on) rather
      than dropping the oldest — a ring buffer would discard precisely the initial
      RoCoF and the nadir, which are the headline numbers. `FrequencyResponseEngine`
      was retrofitted onto it **in the same commit and with no new engine alongside**,
      because M1's 350 tests are the only oracle in the repo that can find a bug in
      the recorder; bundled with `SwingEngine`, a failure would have been ambiguous
      between "recorder wrong" and "swing model wrong". 411/411 core + 33/33 UI green.
      Two consequences now load-bearing rather than incidental:
      **(a) time is a mandatory channel** — the constructor prepends `:t` and refuses
      to be handed one, because decimation changes the sample interval mid-run and any
      consumer assuming a fixed `dt` breaks silently after the first halving
      (`windowed_rocof` already divided by *actual* elapsed time, so it was safe by
      habit; that habit is now a requirement). **(b) Running summaries must not be
      derived from the buffer** — `minimum(series.f)` is the lowest *retained* sample,
      not the lowest that occurred. A test pins this: the same run at capacity 64 and
      at 200 000 reports the *same* nadir, while the small buffer's retained minimum is
      strictly above it.
- [ ] Report **Figure 3-67** as a layout target — still open, still ticks no
      acceptance criterion.

## Known hazards to check off explicitly

- [x] The two-machine closed form re-derived against the **real** code path, not
      copied from the spike — the spike hard-coded its coupling, the real model
      computes it from internal voltage and reactance, and that is one more place a
      per-unit convention can go wrong. **It did go wrong** (the D8 finding), and
      re-deriving is what caught it. Prediction now pinned in `test/` through the
      real `machine_arrays`/`branch_arrays`: `K = 4.284 pu`, `δ₀ = 0.140518 rad`,
      `f_osc = 1.5911075 Hz`. Step 4 must make the *running engine* measure it.
- [ ] Per-machine speed deviation is not M1's aggregate deviation. Check the names
      in the exported API do not invite the confusion.
- [x] **A model that is "wrong on its face" is rejected at construction**, and each
      guard's *message* is asserted — several invalid models violate more than one
      rule, so "it threw" would not prove the intended guard fired.
- [x] **The per-unit split is confined to `machine_arrays`/`branch_arrays`.** The
      example machines are rated away from `S_base` (250/400 MVA on a 100 MVA base)
      so a missing or inverted conversion changes the answer instead of hiding
      behind a weight of 1, and the tests assert against the wrong conversions by
      name rather than only asserting the right one.
- [x] Check new exports against `GLMakie` before writing UI code — the collision
      hazard that cost a round in M1 (`stop!`, `timestep`, `drain!`). All 14
      candidates checked clear, including the ones later steps will need:
      `Bus` · `Branch` · `Machine` · `NetworkModel` · `machine_arrays` ·
      `branch_arrays` · `machine_at` · `two_machine_system` · `three_machine_ring` ·
      `SwingEngine` · `TripLine` · `coi_model` · `buses` · `branches`.
- [ ] Any long-running loop test self-terminates (finite duration, or a state
      stopper plus a wall-clock watchdog). A hung suite is worse than a failing one.
