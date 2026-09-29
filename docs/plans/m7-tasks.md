# M7 — Tasks

The checklist. Companion to `m7-plan.md` (the how) and `m7-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **Steps 0 and 1 done (2026-09-29)** — 3730 core / 1143 reference / 449 UI (3714 at the first step-1 commit; +16 from the walked-surface fix). Entered at `372fd35` (M6 closed) with
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

- [ ] `coi_model` counts grid-forming virtual inertia/damping, grid-following zero.
- [ ] `RoCoF₀` and settling closed forms with both kinds present; grid-following
      contribution exactly zero.
- [ ] Displacement factor `H_sys/(H_sys − H·S/S_base)` over a sweep.
- [ ] All-grid-following model refused by the aggregate read-out, by name.
- [ ] Anti-vacuity: wrong-base `K_p` moves `RoCoF₀` by the predicted factor.

## Step 3 — grid-forming in the swing tier

- [ ] Vertex model from the inverter's own states.
- [ ] Equivalence to the hand-converted machine, round-off, on a line trip.
- [ ] Mutations: wrong base; `τ_p → 0`.
- [ ] Positive control: `P_set` step — inverter frequency jumps by `K_p·ΔP_set` at
      `t⁺`, machine's does not.
- [ ] `SPEC.md` §7.6 corrected, after the measurement.

## Step 4 — grid-forming in the detailed tier

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
