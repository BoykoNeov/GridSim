# M7 — Tasks

The checklist. Companion to `m7-plan.md` (the how) and `m7-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **Steps 0–3 done (2026-09-29)** — 3778 core / 1143 reference / 449 UI (step 2 closed at 3753) (step 1 closed at 3730: 3714 at its first commit, +16 from the walked-surface fix). Entered at `372fd35` (M6 closed) with
**3602 core / 1140 reference / 446 UI** as measured on re-resolved manifests at
M6's close.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed* — not when the code
runs.

---

## Step 0 — hurdles named, outside components measured, plan written (2026-09-29)

- [x] **The hurdles named before any plan prose** (`m7-context.md` D0): 10
      frequency without a rotor, 11 a converter that is secretly a machine and one
      that is not, 12 time scales a phasor tier cannot honestly hold. Added to
      `docs/plans/README.md`'s list.
- [x] **Both outside inverter components built and run before the plan named
      them** (D1; spike `W:\temp\claude\m7-step0\spike_pd_inverters.jl`, reference
      environment at its current manifest, nothing added). `IdealDroopInverter` and
      `ComposableInverter.SimpleGFL` both initialise from PowerDynamics' own power
      flow and hold flat (residuals 1.3e-13 / 2.0e-13).
- [x] **The droop/swing equivalence measured on the outside implementation**:
      `IdealDroopInverter(K_q = 0)` against `Library.Swing(M = τ_p/K_p, D = 1/K_p)`
      under a 0.1 rad network-side angle step — max angle gap **5.4e-11 rad** on a
      0.156 rad swing, max frequency gap 7.2e-12 pu. Mutation `K_q = 0.05` opens
      **1.1e-4 rad**. So the check is not vacuous and a later disagreement on our
      side will be ours.
- [x] **Their `K_p` is on the system base** (read from `IdealDroopInverter`'s
      terminal-power measurement); ours will be on the inverter's own rating, so a
      wrong-base mutation is a planned check.
- [x] **A phase step reads as a frequency spike through their PLL**: 0.05 rad at
      the slack → PLL `ω` peak 1.00644 pu (+0.32 Hz at 50 Hz). Hurdle 10 claim 1 is
      real on the outside model before ours exists.
- [x] **`SimpleGFL`'s initial current matches the ideal-current-source closed
      form**: `i_d = 0.502545`, `V_t = √(1 − X²i_d²) = 0.99494`, `P = V_t·i_d = 0.5`.
- [x] Plan trio written (`m7-plan.md`, `m7-context.md`, `m7-tasks.md`).
- [x] **M5's criterion values captured at HEAD before any code edit**, for step 1's
      gate: `W:\temp\claude\m7\criterion-HEAD.txt` (harness
      `W:\temp\claude\m7\criterion_snapshot.jl`, M6's, unchanged). **169 values,
      identical line for line to M6 step 7's capture**; digest of the value lines
      (`grep " = " | md5sum`) `bfea9f4b81d80dfba5b7ba97ee1e5cb1`. (M6's recorded
      `c79b7c07…` digest was taken over differently filtered text, so the two
      digests are not comparable with each other — the line-for-line diff is.)

## Step 1 — the `Inverter` type, no number moved, refused where unbuilt

- [x] `Inverter` struct (D2), fields settled and recorded in `m7-context.md` D2
      "What step 1 settled"; every guard fires in both modes; `|P0 + jQ0| ≤ S_rated`
      the one rating check; `K_q = 0` the default because it is the degeneration.
- [x] `NetworkModel(…; inverters = Inverter[])`, stored sorted by bus with an
      `inverters_at_bus` map and an `inverters_at` accessor; duplicate inverter ids,
      an inverter id equal to a machine id, and a missing bus all rejected; **the
      balance guard counts inverter `P0`** (`+ 0.0` on every pre-M7 model, so the
      arithmetic is unchanged to the bit).
- [x] Bus roles: a grid-forming inverter makes its bus `:generator`, a grid-following
      one alone leaves it `:load` — one predicate (`_holds_voltage`) shared by
      `bus_roles` and `bus_role`. Default reference bus with no machine: the first
      grid-forming inverter's bus, never a grid-following one's.
- [x] **Every consumer walked from the code** (`grep net.machines|machine_arrays(`
      over `src/`, `reference/src/`, `ui/src/`, `scripts/`), each recorded:
      - **refuses by name** (shared `_assert_no_inverters`, message names the
        inverter and the step that lifts it): `SwingEngine` (grid-following stated
        as a tier boundary, not unbuilt work), `DetailedEngine`, `coi_model` (so
        `FrequencyResponseEngine` too), `ac_powerflow`, `dc_powerflow`,
        `economic_dispatch`, `build_oracle`, `to_powersystems`, and the editor —
        both `ScenarioEditor(net)` and `load!`, the latter refusing **before**
        overwriting anything;
      - **carries inverters through** (a hand-listed rebuild): `dispatch_schedule`,
        `float32_admittance_twin`;
      - **deliberately unaffected**: `machine_arrays`, `branch_arrays`,
        `branch_topology`, `load_arrays`, `machine_at`/`machines_at` (views of the
        machines only; every engine that reads them refuses first), and
        `scripts/iberia_two_area.jl` (builds its own inverter-free model).
      - **Found by review after the first step-1 commit:** `bus_injections`, which
        is exported on its own, sums machines and loads only and returned
        `[0.5, −1.0]` on the two-bus inverter model — a vector that no longer sums
        to zero, and no error. The grep for `net.machines` that built the list did
        not reach it (it reads through `machine_arrays`). Now refuses itself; and
        the list is now **walked, not grepped**: a test calls every exported
        function with a one-argument `NetworkModel` method on an inverter model and
        requires a refusal naming the inverter, or membership of a named list of
        machine/load/branch views (with a count so the walk cannot pass by matching
        nothing). Mutation: removing `bus_injections`' refusal turns it red (3
        failures). First draft of the walk used `hasmethod`, which matched three
        TYPES through Julia's generic `convert` fallback (`Layout`, `StepLoad`,
        `TripGenerator`) — the walk now requires the signature to name
        `NetworkModel`.
      - **Found while writing the tests:** in `SwingEngine` and `coi_model` the
        one-machine-per-bus guard ran BEFORE the inverter check, so the refusal
        named the symptom (a bus with nothing on it) instead of the inverter. Both
        reordered; the inverter check now runs first.
- [x] Scenario file `[[inverters]]` read/write, every field, `τ` spelled `tau` on
      disk; written only when there are inverters, so a pre-M7 model writes the
      byte-identical file; the reader passes only the fields present, so absent ones
      take the constructor's own defaults rather than a second copy. Field-list
      guard: `fieldnames(Inverter)` equals the list the file walks.
- [x] Exports (`Inverter`, `inverters_at`) checked against `names(GLMakie)` —
      intersection empty.
- [x] **Gate (a):** all **3602** pre-existing core tests green (the run before the
      new file was wired in), then **3714** with it (+112), exit 0
      (`W:\temp\claude\m7\core-step1-a.log`, `core-step1-b.log`).
- [x] **Gate (b):** M5's 169 criterion values **bit-identical** to the HEAD capture
      — empty diff (`W:\temp\claude\m7\criterion-STEP1.txt`).
- [x] **Anti-vacuity, five mutations executed**, each turning the step's tests red
      (runner `W:\temp\claude\m7\mutate.py`, restoring from a backup after each):
      the balance ignoring inverters (9 errors); `dc_powerflow`'s refusal removed
      (2 failures — the refusal is per consumer, not shared by accident);
      `dispatch_schedule` dropping inverters (1); the writer skipping `K_q` (1);
      a grid-forming bus not counted as a generator bus (2).
- [x] Reference and UI suites re-run: **1143 reference** (1140 + 3: both builders
      refuse, `:swing` and `:sauer_pai`, and `to_powersystems`) and **449 UI** (446 + 3:
      the editor refuses both ways in and a refused open leaves it unchanged), exit 0
      each.

## Step 2 — the aggregate tier

- [x] `coi_model` compiles inverters (after the machines, bus order): grid-forming →
      unit `H = τ_p/(2K_p)`, `R = Inf`, `Pmax = P0`, unit damping `1/K_p` (all on
      the inverter's own base; `aggregates` weights them); grid-following → `H = 0`,
      no response. The structural precondition, with inverters present, becomes one
      generating element per bus (machine OR inverter); without them it is the
      pre-M7 check, message for message.
- [x] **D9 built:** `GeneratingUnit` gains a per-unit damping `D` (default `0.0`,
      guarded `≥ 0`), added by `aggregates` for ONLINE units only, so a tripped
      grid-forming inverter takes its `1/K_p` with it. Machines keep theirs in
      `SystemModel.D` — the stated asymmetry.
- [x] `RoCoF₀` closed form with both kinds present, expected values computed by
      hand from the fixture's literals (`_m7_mixed`: H_sys 16.5 s all online, 14.5 s
      after the grid-forming trip).
- [x] **Settling closed form, and the damping leaving**: grid-following trip →
      `Δω = −0.4/(11 + 40 + 60)`; grid-forming trip → `−0.6/(11 + 60)` at rtol 1e-6,
      and asserted NOT to match the "damping stays" reading `−0.6/(11 + 40 + 60)`
      (56 % apart). Unsaturated precondition asserted on the equilibrium.
- [x] Grid-following contribution **exactly** zero: `aggregates` with and without it
      online are `===` in every field.
- [x] Displacement factor `H_sys/(H_sys − H·S/S_base)` over a four-machine sweep,
      each machine in turn replaced by a grid-following inverter of the same
      dispatch and rating; tripped unit inertia-free so the ratio is exact.
- [x] **Hurdle 10 claim 3 / D5 refusals**: `coi_model` refuses a model with no
      machine and no grid-forming inverter ("nothing to follow", names the
      inverters); `FrequencyResponseEngine` refuses a zero-inertia model; and a
      **trip into zero inertia is refused before anything moves** (the engine's
      online set, `H_sys` and imbalance asserted unchanged). `aggregates` itself
      still returns `H_sys = 0` for an empty or all-inverter set — it is a pure
      function and M1's tests pin that corner; the refusal lives where the
      integration is.
- [x] **Four mutations executed, each red**: grid-forming damping on the wrong base
      (2 failures); virtual inertia on the wrong base (3); a tripped unit's damping
      staying (2); the zero-inertia trip refusal removed (2).
- [x] Gates: **3753 core** (3730 − 2 retired step-1 refusal tests + 25), M5 criterion
      **bit-identical** (`W:\temp\claude\m7\criterion-STEP2.txt`).
- **Found, not planned:** `FrequencyResponseEngine` would have stepped on into
  `Inf`/`NaN` after a trip that left no inertia online — dividing by `2·H_sys = 0`.
  No pre-M7 fixture could reach it (every M1 system keeps a machine online); a
  grid-forming inverter as the last inertia makes it one trip away. The plan named
  the all-grid-following refusal at `coi_model` and missed the engine's.
- Deferred to step 3, as planned: the cross-check of this aggregate against the swing
  tier's run of the same model.

## Step 3 — grid-forming in the swing tier

- [x] **Vertex model from the inverter's own states** (`gfm_vertex!`: `δ`, `P_filt`,
      and a structurally zero governor slot so every vertex exposes the layout the
      engine's bookkeeping indexes). **The speed is READ, not stored**: `_speed`
      returns the state for a machine and `−K_p·(P_filt − P_set)` for an inverter,
      so the setpoint-step jump emerges from the physics rather than being written
      into an event handler. With no inverters every `droop` is zero and the
      read-out is the state itself — the pre-M7 path, bit for bit.
- [x] Per-vertex compiled view `_swing_vertices` used ONLY when inverters are
      present (`K_p` converted to the system base once, COI weight `τ_p/(2K_p)`
      weighted by `S_rated/S_base`, bus voltage `V_set`); models without inverters
      still read `machine_arrays`/`branch_arrays` unchanged.
- [x] **Equivalence to a hand-converted machine** on a three-bus ring with a line
      trip, the inverter on its own 150 MVA base: identical flat start (3e-17), then
      max angle gap **6.5e-11 / 2.4e-12 / 5.3e-14 rad** at reltol 1e-6 / 1e-9 / 1e-11
      on a 1.4e-3 speed excursion. **The plan's "to round-off" was wrong**: the two
      integrate different state variables, so the gap is the solver's and the check
      is that it falls with the tolerance (≥ 100× over the range) — the convergence
      label, not "exact". Band 1e-12 stated in the test before the tight run.
- [x] **Mutations, four executed, each red**: `K_p` left on the inverter's own base
      (5 failures); the power filter made near-instant (4); speed read as the raw
      state (5); virtual inertia not weighted to the system base (3). Plus an in-test
      one needing no edit: a 10 % droop mismatch opens a gap > 1e-6.
- [x] **Positive control, Hurdle 11 claim 2**: a 0.1 pu setpoint step moves the
      inverter's speed by exactly `K_p_sys·ΔP = (0.05·100/150)·0.1` at the event
      boundary, with no step taken; the machine's does not move at all.
- [x] **Step 2's deferred cross-check**: at a trip instant the swing tier's COI
      frequency derivative, read off the RHS, equals the aggregate's `RoCoF₀` to
      1e-8 for both a machine trip and a grid-forming trip; after the grid-forming
      trip both tiers settle on `Δω = −0.6/10` (the swing tier because the vertex
      leaves, the aggregate because of D9). A machine trip is deliberately NOT
      compared at settling — M2's recorded damping asymmetry.
- [x] Refusals: grid-following (named a tier boundary), two sources on one bus, and
      a shed ladder or generation ramp armed on an inverter.
- [x] `SPEC.md` §7.6 amended **after** the measurement: "no swing equation" is true
      of grid-following only. §9 item 7 marked taken.
- [x] Gates: **3778 core**, M5 criterion **bit-identical**
      (`W:\temp\claude\m7\criterion-STEP3.txt`), **1143 reference / 449 UI**.
- **Found, not planned (1):** M2's `V5` tripwire — which counts every array the
  swing engine holds, to catch an all-pairs structure — moved by exactly `n`
  (1122 → 1162 at n = 40): the one new per-vertex `droop` vector. Accounted for in
  the test's own running record (28n + 2 → 29n + 2) rather than re-pinned, as that
  test asks; the slope assertion, which is the actual claim, never moved.
- **Found, not planned (2):** step 1's refusal test asserted that `SwingEngine` refuses
  every inverter; building the grid-forming vertex made that half of it wrong, and
  it now asserts the grid-following half only — the lifted refusal showing up as a
  failing test, which is the walked-surface design working as intended.

## Step 4 — grid-forming in the detailed tier

- [x] **Power flows (commit A)**: `ac_powerflow` treats a grid-forming bus as a
      source holding `P0` and `V_set`, `bus_injections`/`dc_powerflow` inject its
      `P0`; grid-following still refused (step 5). One per-unit conversion point for
      inverters, `_inverter_arrays`, now read by the swing tier too.
- [x] **D10 decided with the measurement** (`m7-context.md` D10): the rating is a
      switched reactive limit; bit-identical to the capped `Machine` twin binding
      and not; the slack's rating checked after the solve.
- [x] Mutations A1–A4 executed, each red: cap not added, inverter `P` not injected,
      slack check skipped, `V_set` not held. Core **3796** green.
- [ ] Vertex behind `X_c`, `K_q` live, initialised through the static network.
- [ ] Equivalence at `K_q = 0` against a classical detailed machine, `X′d = X_c`.
- [ ] PowerDynamics `IdealDroopInverter` + line `X_c`, `K_q` live, band stated
      before the gap is seen.
- [ ] Mutations: `K_q` sign; `X_c` dropped.

## Step 5 — grid-following in the detailed tier

- [ ] Ideal current source in its PLL frame; PLL form chosen and recorded.
- [ ] Existence limit `P = |V_g|²/(2X)` located by a scan.
- [ ] PLL closed-form phase-step response, peak predicted before the run.
- [ ] No-voltage-source model refused by name (D5).
- [ ] PowerDynamics `SimpleGFL`: gap shrinks as their current loop stiffens.
- [ ] Mutations: PLL error sign; wrong current frame.

## Step 6 — frequency read-outs

- [ ] Per-bus PLL channels; centre-of-inertia with virtual inertia; refusal at
      zero weight.
- [ ] RoCoF three ways side by side.
- [ ] Closed forms for the phase-step spike and the window dependence.
- [ ] Anti-vacuity: PLL averaged into `ω_coi` moves it where it must not.

## Step 7 — the low-inertia study

- [ ] `scripts/low_inertia.jl`, both displacement kinds, per-share table.
- [ ] Zero share reproduces M1's recorded values.
- [ ] Second topology (cut-first #2), claim written after both tables.
- [ ] Anti-vacuity: `τ_p → 0` loses the grid-forming benefit.

## Step 8 — editor (not cut) and window (cut-first #1)

- [ ] Editor: inverter tool, panel fields, save/open round-trip, render looked at.
- [ ] Window, or its cut recorded.

## Step 9 — close

- [ ] Manifests re-resolved, counts re-measured, ledger, SPEC, README, memory.
