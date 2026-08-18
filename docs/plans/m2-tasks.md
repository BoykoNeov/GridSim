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

## Step 3 — the swing engine (DONE)

- [x] **Step 3 opened with the trajectory recorder, on its own commit** — see the
      carried-over section at the bottom. That ordering was deliberate and is the
      first thing to read if this batch is being reconstructed.
- [x] `src/engines/swing.jl`: NetworkDynamics vertex model (machine) and edge model
      (branch), assembled into a `Network` compiled *from* `NetworkModel`. `ω₀`
      rides in the vertex parameters rather than a closure, so every model shares
      one compiled `Network` type instead of forcing a recompile per system.
- [x] `SwingEngine <: SimulationEngine` — `init!`, `step!`, `current_state`,
      `state_series`, `timestep`, `inject!(::TripGenerator)`. Parametric on the
      concrete network, integrator **and** recorder types (the recorder's channel
      count depends on the machine count), built through `init!` as constructor of
      record. `TripLine` remains step 5.
- [x] **The contract held: `interface.jl` needed no changes**, asserted in `test/`
      rather than claimed. The one strain — `state_series` returns a different set
      of channels per engine — is recorded as a **finding about the abstraction**
      in `m2-context.md` and left for step 7 to handle honestly, not patched by
      widening the interface on speculation.
- [x] `current_state` exposes per-machine `δ` and `ω` **and** `ω_coi`/`f_coi` under
      distinct names, with a test that walks a transient asserting `ω_coi` really is
      the inertia-weighted mean *and* that the machines genuinely spread apart — so
      the equality is not holding trivially.
- [x] Accessors: `machine_ids`, plus `system_inertia` / `is_online` reused verbatim
      for the new engine, so `ui/` reads both engines through one API. Both new
      exported names checked clear against GLMakie first.
- [x] **FINDING: graph edge order is not branch order, and V2 provably cannot catch
      a mis-mapping.** `[L12, L23, L31]` maps to graph edges `[1, 3, 2]`. Defended
      structurally (edge parameters filled in one pass over the graph's own edge
      list, keyed by bus pair — no index to permute) *and* asserted directly, since
      the fixpoint solver converges on any self-consistent wrong network and the
      injection check then balances against the same wrong couplings. Full write-up
      in `m2-context.md`.

## Step 4 — initialization, with its tests in the same step (DONE)

- [x] Steady state via `find_fixpoint`; no hand-rolled power flow (D6). It ships in
      the step-3 commit because the engine cannot be smoke-tested at all without a
      start state.
- [x] **V1 flat start**: residual `6e-18` (two machines) / `2e-17` (ring) at
      `t = 0`, and a 2 s pre-disturbance window that does not move.
- [x] **V2 injection check**: reproduces to `2e-16`, recomputed from the *model's*
      couplings rather than from what the engine handed the solver.
- [x] **V3 closed-form swing frequency, on the running engine**: measured
      **1.5909869 Hz** against the pinned **1.5911075 Hz**, excited by a 10 mrad
      angle displacement (a trip would remove the equilibrium the oscillation is
      about) and averaged over every cycle in a 12 s window by interpolated zero
      crossings. The `1.2e-4 Hz` gap is the damping the undamped closed form omits;
      the test asserts the **sign** of that offset and **bounds its size** rather
      than widening the tolerance until it passes. Three wrong versions of the
      formula are asserted to fall outside the tolerance — dropping `cos δ₀` is the
      near miss at `8e-3 Hz`, which is what sets the tolerance at `5e-4`.
- [x] Tests assert angle **differences**, never absolute angles — and the gauge
      symmetry itself is asserted (displace every angle by 0.7 rad, residual still
      zero) rather than pinning wherever the solver happened to land.
- [x] **Recorded, not patched: the post-trip system has no equilibrium.** No
      governors in this tier, so a trip leaves `Σ Pm ≠ 0` permanently: speed falls
      until damping balances it (`ω_coi → ΣPm/ΣD`, matched to 1e-4) and angles then
      drift together forever. Never call `find_fixpoint` on a post-trip state.

## Step 5 — events (DONE)

- [x] `inject!(::SwingEngine, ::TripGenerator)` — **DONE in step 3** (it is one of
      the interface verbs step 3 owed). Reuses the M1 event type; zeroes the
      machine's mechanical power and its incident branch couplings, and the state
      vector is asserted not to be resized.
- [x] `TripLine(from, to)` — zeroes that branch's coupling, never resizes the state.
      Named by **bus pair, either order**, not by branch id: the pair is what
      uniquely identifies a branch in this tier, and the parallel-circuit guard
      already justifies itself on `TripLine` needing that. A branch-id convenience
      constructor was considered and dropped (a second way to name a line is a
      choice step 7 would then have to make, and it would pull `NetworkModel` into
      an events file that has no model dependency).
- [x] `lines_online` is **tracked, not inferred from `K == 0`** — a generator trip
      also zeroes the coupling of every branch at its bus, and those lines are still
      in service. Inferring would report a healthy line as tripped the moment its
      neighbour's machine died. `is_online(eng, from, to)` is the UI read.
- [x] **THE HEADLINE: a line trip has an equilibrium, and it is a closed form.**
      Unlike a generator trip, `Σ Pm` is untouched, so the surviving network settles.
      Cutting one line of the ring leaves the radial path B1–B2–B3:
      `δ₁−δ₂ = asin(Pm₁/K₁₂)` and `δ₂−δ₃ = asin((Pm₁+Pm₂)/K₂₃)`, both read through
      the real `branch_arrays`. **Measured to `1e-13`** with every `|ω| < 1e-15`.
      Two wrong forms asserted outside: machine 2's own injection instead of the
      cumulative flow (`0.19 rad` out) and the wrong branch's coupling (`1.8e-3`
      out — the near miss that sets the `1e-9` bound).
- [x] **Run to 240 s, not 60 — and the reason was measured, not assumed.** The
      settling is far slower than the swing period (error `1.2e-3` at 40 s, `9.7e-5`
      at 60 s, `1e-13` at 240 s). Asserting `1e-4` at 60 s would have looked like a
      solver-tolerance allowance; the *same* `-9.731e-5` comes out at `reltol` `1e-3`
      and `1e-10`, so it is settling physics. (The tolerance pass-through written to
      establish that was removed again — unused API on speculation is what this repo
      avoids.)
- [x] **FINDING: the two integrator-boundary calls are not separably observable.**
      With **both** `derivative_discontinuity!` and `auto_dt_reset!` removed the
      realized first post-trip step comes out **9.7 % low**; with *either one* alone
      it is correct to 0.01 %, because `auto_dt_reset!` re-evaluates the RHS as a
      side effect. So the test asserts what is measurable (first-step rate vs the
      analytically evaluated RHS, `rtol = 2e-3` against a 9.7 % failure) and **both
      calls stay**, since leaning on that side effect is depending on undocumented
      behaviour. Deliberately **not** asserted: `integrator.dt` — an OrdinaryDiffEq
      internal whose read-back semantics a minor bump can move.
- [x] The stale-derivative test runs over **both trip paths**, `TripGenerator` and
      `TripLine` — which is what "both" meant here.
- [x] **A line trip may split the grid, and the aggregate then lies.** Cutting the
      only line of the two-machine system leaves two islands running at **+12 %** and
      **−7.5 %** (`ωᵢ → Pmᵢ/Dᵢ`, verified to `1e-7`), reported as a single **−1 %**
      aggregate — neither island's frequency, and non-zero only because the two
      machines do not share an `H/D` ratio. Asserted as the derived value and as
      *far from both islands*, because "≈ 0" would read as "nothing happened". Not
      refused: it is a real event, and it is step 6's problem stated in advance.
- [x] **A second, independent bite on the edge-ordering hazard.** At the instant a
      line opens, only the machines at its two ends accelerate (`∓P/2H`, measured
      `+2.65e-2` / `−1.27e-2`) and the third is exactly zero (`1.9e-17`). This tests
      the mapping *through a live event*, not at construction — and V2 still cannot
      catch it.
- [x] A tripped machine is excluded from the aggregate frequency read-out even
      though its state keeps integrating — its inertia weight goes to zero, and the
      test checks both that it leaves the aggregate and that its own speed damps to
      rest harmlessly.
- [x] 1093/1093 core + 33/33 UI green (1046 entering step 5). No new package and no
      new upstream name in `src/`, so the two-resolution sweep from steps 3–4 still
      covers this step and was not re-run; the one new named reach is `integrator.f`
      in `test/`.

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
      **Both `record!` entry points share one retention decision and both are swept.**
      There is a varargs form (arity pinned by the type) and a vector form for engines
      whose channel count is only known at construction — and `SwingEngine` uses the
      vector one *exclusively*, so sweeping only the varargs path would have left the
      newer engine's actual code path unasserted. The duplicated retention logic that
      first shipped in the vector form was folded back into a single `_accept!`: a
      second copy inside the very file written to prevent second copies.
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
- [x] Per-machine speed deviation is not M1's aggregate deviation. `current_state`
      returns `δ`/`ω` (per machine, vectors) alongside `ω_coi`/`f_coi` (aggregate,
      scalars) — four distinct names, none reused from M1's `Δω`/`f`. The trace
      channels follow suit (`δ_G1`, `ω_G1`, …, `f_coi`).
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
- [x] Any long-running loop test self-terminates. Every M2 engine test drives a
      fixed step count (the longest is 6000 steps / 12 s of simulated time); none
      loops on a condition, so none can hang.
- [x] **Both dependency resolutions tested, not just the developer machine's.** The
      engine adds two named reaches step 1 never checked — `SciMLBase.auto_dt_reset!`
      (new here, and a runtime failure rather than a load failure if it moved) and
      `NetworkDynamics.SII` (a dependency's internal alias; its absence would break
      *construction*). Manifest moved aside, `Pkg.instantiate()` re-resolved to the
      fresh pair (`SciMLBase` 3.49.1 / `OrdinaryDiffEq` 7.6.0), all four named
      reaches resolve, and the suite is **1046/1046 on both**. V3 is the tightest
      solver-dependent assertion in the repo (measured gap `1.205e-4` against a
      `2.0e-4` bound), and it comes out **bit-identical** across the two
      resolutions — so that 1.66× margin is not solver-version slack. The dev
      machine has been left on the fresh resolve, which is what a clean clone gets.
