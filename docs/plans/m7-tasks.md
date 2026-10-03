# M7 — Tasks

The checklist. Companion to `m7-plan.md` (the how) and `m7-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **Steps 0–8 done (2026-10-03)** — 4134 core / 568 UI at step 8 (reference not
re-run in step 8: no code it reads moved beyond one added helper; step 9 re-measures all
three on re-resolved manifests). Step 7 closed at 4113 / 1251 / 449. Step 6 closed at 3950 core / 1251 reference / 449 UI (step 5 closed at 3868 / 1251 / 449; step 3 at 3778 / 1143 / 449) (step 2 closed at 3753) (step 1 closed at 3730: 3714 at its first commit, +16 from the walked-surface fix). Entered at `372fd35` (M6 closed) with
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
- [x] Vertex behind `X_c`, `K_q` live, initialised through the static network
      (commit B). **D11 taken**: `V_set` is the BUS voltage at every tier — the static
      vertex carries the formed magnitude as a fourth unknown — and the droop's
      intercept is one derived number. Power measured at the source (as
      `IdealDroopInverter` does). On an all-inverter model the engine's own steady
      state and `ac_powerflow` agree to 1e-11.
- [x] Equivalence at `K_q = 0` against a classical detailed machine, `X′d = X_c`,
      both started from `ac_powerflow`: **exactly zero gap at t = 0**, then solver
      error falling with the tolerance (6.1e-8 / 9.8e-10 / 9.3e-12 rad at reltol
      1e-6 / 1e-8 / 1e-10) — not round-off, as pre-registered from step 3. `K_q = 0.05`
      opens 3.7e-4 rad; the droop is checked against the `Q_filt` state with the gain
      converted by hand.
- [x] The rating at this tier (D10): the engine's own steady state refuses an
      inverter asked beyond its rating and points at `powerflow = ac_powerflow(net)`,
      which caps it; the capped start sits exactly at the rating and is flat.
- [x] **Found, not planned:** M5 step 7's out-of-step binder looked up rotor angles
      by BUS number in a MACHINE-indexed list. Measured on committed code: with a
      load-only middle bus, a relay on B1–B2 read G3's angle as B2's (its start
      guard fired at 0.99·|δ_G1 − δ_G3| and called that "the angle across that
      branch"); one on B2–B3 threw a BoundsError. Every relay fixture had a machine on
      every bus. Now looked up by bus, and refused by name at a bus with no source.
- [x] Mutations B1–B7 executed: six red (`K_q` sign, `X_c` nearly dropped, `X_c` on
      its own base, virtual inertia out of the COI weight, re-init re-solving `E`,
      relay lookup by machine index); **B7, `Q` measured at the bus, GREEN in-house as
      pre-registered** — only the PowerDynamics comparison can see it.
- [x] Gates: core **3832**, M5 criterion **bit-identical** (`W:\temp\claude\m7\criterion-STEP4.txt`).
- [x] PowerDynamics `IdealDroopInverter` + line `X_c`, `K_q` live, band stated
      before the gap is seen (commit C). `build_oracle(:sauer_pai)` puts each
      grid-forming inverter on its own internal vertex after the buses, joined by a
      line of `X_c`; its gains and `X_c` are converted to the system base IN THE
      BUILDER from the inverter's own fields, so a wrong base in core is a
      disagreement (M4's blind spot, closed for this component). The fixture has
      **no machine** — every detailed machine carries M5's stator-ω residual, which
      a band around the sum would hide an inverter error inside. Measured: the flat
      run agrees to 1e-9 on every channel; after a line trip the two agree to
      **~1e-12** on every channel against `convergence_band`s of 1e-8–1e-9, while the
      trip moves each channel by 1e-4–6e-3 (≥ 1e4 bands). The seed could not set the
      internal vertex's voltage: their component SETS it, so it is an observable.
- [x] Mutations against PowerDynamics, each red: `K_q` sign; `X_c` on its own base
      (gap 8.9e-3 against a 3.5e-7 band); **`Q` measured at the bus — B7, green
      in-house — red here, caught first by the FLAT RUN** (their filter starts
      0.016 pu off rest: `|I|²X_c`). A data mutation on our side only (`K_q` +20 %,
      `X_c` +20 %) is in the suite itself.
- [x] **Step 4 gates:** core **3832**, reference **1210** (1143 + 67), UI **449**,
      M5 criterion bit-identical.

## Step 5 — grid-following in the detailed tier

- [x] **Power flows (commit A)**: a grid-following inverter is a constant-power
      `P0 + jQ0` injection on a load-type bus in `ac_powerflow` (fixed `Qfix`, not the
      ZIP law), and an injection in `bus_injections`/`dc_powerflow`; closed form
      `V_t² = (V_g² + √(V_g⁴ − 4X²P²))/2` to 1e-12. `Inverter.τ_pll` added (D12).
- [x] **The transfer limit, in two halves (D13)**: band edge 1.9615 pu bracketed to
      1e-4 through `ac_powerflow`; the nose 2.5 pu bracketed to 1e-4 on the band-free
      first round, always on the high branch. The plan's single scan was unreachable.
- [x] D5: a model with nothing to follow is refused naming the inverters.
- [x] Mutations C1–C4 executed, each red. Core **3848**.
- [x] Ideal current source in its PLL frame (commit B): `I = (i_d + j·i_q)·e^{jθ_pll}`,
      d-axis along the PLL angle (PowerDynamics' `_dq_to_ri`, not the machine's `_dq`);
      PLL = `PLL_LPF` exactly (D12). Static vertex: constant POWER at start-up,
      constant CURRENT at the held PLL angle on a re-initialisation — what the RHS
      injects. Channels `θpll_`/`ωpll_`, weight zero (D6).
- [x] Existence limit — in two halves, commit A (D13).
- [x] PLL phase-step peak predicted before the run from the linearised 3×3 loop's
      matrix exponential, on a ZERO-CURRENT inverter (an exactly stiff bus): relative
      error 3.4e-4 / 8.4e-5 / 2.1e-5 at Δ = 0.05 / 0.025 / 0.0125 rad — ratio 4.0 per
      halving, the Δ² signature of sin φ ≈ φ. A 0.05 rad step reads as −0.47 Hz.
- [x] No-voltage-source model refused by name (D5), FIRST in `init!`.
- [x] **The wrong-frame check the plan did not have**: the injected current, read
      from the branches and rotated into the PLL frame, stays at dispatch to < 1e-10
      through a line trip while the PLL is up to 0.0105 rad off the bus angle.
- [x] Mutations D1–D4, each red: PLL error sign; current in the BUS frame (caught
      ONLY by the network-side check, as pre-registered); output filter removed;
      re-init at constant power.
- [x] Gates (commit B): core **3868**, M5 criterion bit-identical.
- [x] PowerDynamics `SimpleGFL` (commit C): an injector ON its bus, `Rf = 0`,
      `Xf = 0.05` a builder constant (the inductor we do not have), PLL from the
      inverter's fields, current-loop gains × `cc_scale`; filter current, PLL and
      loop integrators seeded from ours through THEIR equations. Flat run agrees to
      ~5e-15. After a line trip the gap falls as **1/k**: V_B 0.0141 → 0.00367 →
      0.000849, θpll 5.6e-4 → 1.3e-4 → 3.1e-5, ω_gf 7.1e-6 → 1.8e-6 → 4.4e-7 (ratios
      3.85–4.42); **ωpll falls FASTER** (15.3, 7.7) — not predicted, recorded, asserted
      only as ≥ 1/k. Bands ≥ 1e4 below the smallest gap. At their default gains the
      gap on V_B (0.014) is two-thirds of the excursion (0.021): the ideal source is a
      coarse model of the first milliseconds after an event, now with a number.
- [x] Mutations against `SimpleGFL`, each red: PLL error sign (fails even the FLAT
      run — the flipped loop is unstable, so round-off grows off rest); current in the
      bus frame (flat run passes, the 1/k signature breaks).
- [x] **Step 5 gates:** core **3868**, reference **1251**, UI **449**, M5 criterion
      bit-identical.

## Step 6 — frequency read-outs

- [x] **Per-bus PLL channels**: step 5's `ωpll_<inverter>` ARE per bus (the detailed
      tier refuses two sources on one bus), kept, not renamed. **Plus a
      measurement-only `PLLMeter`** at any named bus (the user's choice, D14), so
      step 7's grid-forming sweep has a PLL to read: an engine keyword, channels
      `θmeter_<bus>`/`ωmeter_<bus>`, one PLL law (`_pll_rhs`) shared with the
      grid-following vertex. Refactor gate: a captured step-5 grid-following run `==`
      before and after (`W:\temp\claude\m7\step6\gfl_capture.jl`). Meter checks:
      injects nothing (meter states kicked, every other RHS row `==`); the positive
      control — `PLLMeter(inv)` at the inverter's bus reads `ωpll_` to round-off
      (6e-17, NOT bit for bit as predicted: the Rosenbrock linear solve; does not fall
      with the tolerance); guards and refusals (unknown bus, two on one bus).
- [x] **Centre of inertia with virtual inertia** (built in step 4) and **the refusal at
      zero weight**, path by path (D14): `coi_model` and the aggregate engine refuse
      (step 2); the detailed tier cannot reach it (D5 + no generator trip); the swing
      tier's live `f_coi` stays `NaN` (M2's decision, UI-pinned) and the NEW read-outs
      `coi_rocof` and `rocof_readouts` refuse by name.
- [x] **RoCoF three ways side by side**: `coi_rocof(engine)` (instantaneous, off the
      right-hand side, all three tiers, a LIVE read — not a channel, because the
      reference oracle mirrors the detailed channel list, D14), and
      `rocof_readouts(engine; window)` → `coi` and `pll`, one `windowed_rocof`, one
      window. `coi_rocof` checked against step 3's hand RHS arithmetic (`==`), the
      aggregate `RoCoF₀` at two trips, and on the detailed tier against a closed form
      read from the bus voltage alone (`0.4·(|V₁(0)|² − |V₁(t⁺)|²)/(2Σw)`), inverter
      and machine twin agreeing to 1e-9. **Measured on the grid-following ring: the
      instantaneous value is the SMALLEST of the three** (−1.5e-4 against 0.066
      windowed and 0.22–0.91 PLL, Hz/s) — the prediction written before the run said
      the opposite.
- [x] **Closed forms**: the phase-jump spike `K_p·|V|·Δ` on a real network event, its
      filter leftover 0.059 → 0.011 → 0.0022 as τ falls by decades (5.2× each, >4×
      pre-registered), a first-order correction to 1.1 % at default gains, sign
      pre-registered (a DIP); the phantom RoCoF spike/W from below (the PLL's ringing
      adds 1.3e-3 at 250 ms, nothing at 1 s — equality predicted, bound measured); and
      the window's cost on an exactly first-order aggregate trajectory,
      `T(1 − e^{−W/T})/W`, every sample to 1e-7.
- [x] **Anti-vacuity: a PLL averaged into `ω_coi`** moves the centre of inertia on the
      phase-jump fixture, where it measurably does not move (`coi_rocof` 5.6e-17 Hz/s,
      `f_coi` flat to exactly 0.0).
- [x] **Mutations, eight executed, each red** (`W:\temp\claude\m7\step6\mutate6.py`,
      log `mut6.log`): S6-1 a PLL averaged into `ω_coi` (4 failures — the flat `f_coi` and the zero windowed COI); S6-2 a meter re-seeded to the new bus angle at re-initialisation (7 — the spike vanishes); S6-3 a meter on the neighbouring bus (6); S6-4 the PLL error normalised by |V| (5 — the leftover at the smallest τ); S6-5 the detailed `coi_rocof`'s grid-forming term sign-flipped (2); S6-6 the swing `coi_rocof` reading an inverter's raw state rate (2); S6-7 `rocof_readouts`' zero-weight guard removed (1); S6-8 PLL frequency not converted to Hz (10).
- [x] **Step 6 gates:** core **3950** (3868 + 82), reference **1251**, UI **449** (both unchanged — no meter is armed outside the new tests, so no channel list moved), M5 criterion **bit-identical** (`W:\temp\claude\m7\criterion-STEP6.txt`).
- **Found, not planned — step 7 cannot run as written**: the detailed tier refuses
  `TripGenerator`, `StepLoad` is aggregate-only and has no bus, and grid-following
  inverters live only in the detailed tier, so "the largest-unit trip at each share"
  has no event. Recorded in D14 and put to the user before step 7 (the machine vertex
  already carries a stator-current status parameter, `mstat`, always 1.0 today).

## Step 7 — the low-inertia study

- [x] **First: a source trip in the detailed tier (D15, the user's choice)** — machines,
      grid-forming and grid-following; weights leave with the unit; zero-inertia trip
      refused; `coi_rocof` at `t⁺` against the aggregate `RoCoF₀` per kind. Built as an
      in-service flag on each source's CURRENT in both networks (`mstat`, new `istat`,
      the grid-following setpoint), never `E = 0`; the re-initialisation now also checks
      the DYNAMIC network's Kirchhoff rows (the advisor's addition). Closed form exact
      to `rtol 1e-8` per kind on a lossless constant-power ring, and exact WITH a
      surviving grid-following inverter once its own power change is counted.
      M5's step-1 refusal test and step 6's zero-weight test rewritten on purpose.
      Gates: core **3994** (3950 + 43 + 1), reference **1251** unchanged, M5 criterion
      bit-identical, step 6's grid-following capture `==`.
- [x] **Trip sabotages, nine executed, each red, predictions written first**
      (`W:\temp\claude\m7\step7\mutate7.py`, log `mut7.log`): T7-1 the `E = 0`
      shortcut (predicted: the "exports nothing" check; actually caught EARLIER — the
      leftover X′d is a shunt that pulls B1 to 0.505 pu and the re-solve's band refuses
      it); T7-2 weight not removed; T7-3 static machine status not zeroed, T7-4
      grid-following setpoint zeroed on one side, T7-7 grid-forming status ignored by
      the dynamic vertex — all three caught by the NEW dynamic-Kirchhoff check and by
      nothing else; T7-5 `Pm` left on a tripped machine — caught, as predicted, only
      through the dead rotor's own speed channel (0.14 pu where it should decay) plus
      the parameter read-back; T7-6 grid-forming setpoint left (its idle speed sits at
      0.02 pu = K_p·P_set); T7-8 relays not disarmed; T7-9 the last-source guard moved
      after the unit is taken out (the "nothing was changed" snapshot).
- [x] **The event and the loads put to the user (D16)**: the largest unit is 38 % of the
      fleet and grid-following displacement turns its trip into a voltage event below
      the band — taken: BOTH events (G1 and G4), the default loads, and the exact M1
      control as its own section.

- [x] `scripts/low_inertia.jl`, both displacement kinds, per-share table — both events
      (D16), matched dispatch asserted (every pre-trip bus voltage to 1e-8), default
      loads, solver tolerance 1e-6, and the RoCoF₀ gap between formula and network
      ACCOUNTED for exactly (`−P_lost + load relief + ΔP_gfl`, rtol 1e-8 — the
      advisor's addition, which reversed the first draft's ranking of the two kinds).
- [x] Zero share reproduces M1's recorded values — `coi_rocof` at t⁺ against M1's own
      engine on `example_system()`, constant-power loads, gaps ≤ 1.4e-12 on both layouts
      and both events.
- [x] Second topology (`:chain`) — NOT cut; claims written after both tables (section 4
      of the script, five claims, each asserted; three drafted earlier did not survive).
- [x] Anti-vacuity: `τ_p → 0` — the t⁺ imbalance is identical and `coi_rocof·H_post`
      invariant to 1e-9 (read on the network column; the formula column would check its
      own input); the nadir moves < 0.05 Hz, so the grid-forming nadir benefit is the
      droop, not the virtual inertia.
- [x] Study sabotages, three, each red (`mutate7b.py`, `mut7b.log`): grid-following Q
      not matched (the matched-dispatch check, and one cell tipped into a refusal);
      load relief read as constant power (the accounting); τ_p never reaching the
      inverter (the anti-vacuity block). Rows 3 and 4 of a grid-forming sweep coincide —
      a consistency check of the two trip paths, its after-t⁺ gap shown to be solver
      error falling with the tolerance.
- [x] **Step 7 gates:** core **4113** (3994 + 119 study checks), reference **1251**
      (the oracle's detailed-tier trip refusal kept, its reason rewritten — the two sides
      would now run different events — and its test reads the reason), UI **449** (two
      stale comments in the voltage window corrected, no code moved).
- [x] **Final review (advisor) fixed three things before close:** a "~39 Hz" settle
      estimate (measured: 44.30 / 44.66 Hz, within 3 mHz at 30 s) and the still-falling
      flag that mistook a monotone settle for a fall; a phase-jump explanation of the
      chain's PLL excess that nothing measured (cut to the measured fact); and a test that
      pinned the chain's 0.899-against-0.9 refusal (now asserts the voltage gap).
- **Not done, and said:** the aggregate tier's NADIR overlay (`coi_model` refuses a
  `Load`; widening it rejected in D16) — the overlay is the RoCoF₀ formula only.

## Step 8 — editor (not cut) and window (cut-first #1)

- [x] **Editor: step 1's refusal lifted, on purpose** — `ScenarioEditor(net)` and `load!`
      now carry inverters; step 1's UI refusal test is rewritten into the round trip
      (every field away from its default, both modes, layout and slack kept).
- [x] **Core `_inverter_with`** (beside `_machine_with`): walks `fieldnames(Inverter)`,
      several changes in ONE rebuild; tested in `test/m7_inverters.jl` (a mode switch
      and back is `===` the original; rating + dispatch lowered together accepted,
      either alone refused).
- [x] Editor state: `inverters` (insertion order), `add_inverter!` (grid-forming by
      default), every walk of the collections (`_collection`, `all_ids`/`fresh_id`,
      `remove!(:bus)`, `rename!(:bus)`), `power_balance` counting inverter `P0`,
      `build_model`/`load!`/`validation` carrying them, and `effective_slack` following
      the widened rule — first grid-forming inverter in BUS order with no machine.
      Its agreement test now builds drafts with inverters added out of bus order, only
      grid-following, mixed, and a mode switch moving it.
- [x] **Panel: fields by ELEMENT** (`editable_fields(::Inverter)` is the mode's set), a
      **switch to …** button that rebuilds the panel, and **apply as ONE rebuild**
      (`set_fields!`). Found while planning (advisor): field-by-field apply refused an
      inverter's rating and dispatch lowered together at the first box, after earlier
      boxes had been written — D4's "nothing half-applied" was broken for every kind.
- [x] Window: inverter tool (tools four to a row), hexagon glyph filled for
      grid-forming and hollow for grid-following, label `GFM`/`GFL`, highlight, sources
      sharing one row above a bus, solve's schedule counting an inverter on the slack
      bus, run's status counting inverters and catching the swing tier's
      grid-following refusal (an `ArgumentError`, already caught).
- [x] **Rendered and looked at** (`W:\temp\claude\m7\step8\ed-*.png`). Found: a machine's and an
      inverter's labels on one bus written through each other (spacing 0.9 → 1.9
      offsets); the first fixture REFUSED by solve (two `V_set`s on one bus — the
      refusal path, working); and the multi-machine window that **run ▶** opens drew a
      grid-forming inverter's trace with NO trip button and counted it as a machine —
      it now has one, under **trip a source**, and the status counts inverters.
- [x] Precompile workload renders the editor with an inverter selected.
- [x] **Sabotages, eleven, each red** (`W:\temp\claude\m7\step8\mutate8.py`, logs `mut8*.log`):
      S8-1 balance ignores inverters; S8-2 derived slack in insertion order; S8-3
      deleting a bus keeps its inverters; S8-4 renaming a bus strands them; S8-5
      `_inverter_with` drops `τ_pll`; S8-6 open does not carry inverters; S8-7 apply
      field by field; S8-8 mode switch without a panel rebuild; S8-9 solve's schedule
      ignores inverters; S8-10 no inverter trip button; S8-11 (after the advisor's
      final review) a taken id checked only AFTER the fields are written — apply wrote the
      numbers, failed the rename, and said "not applied" over a changed record. The id is
      now validated before anything is written.
- [x] **Window — BUILT, not cut** (the user's call; layout and controls the user's too,
      `m7-context.md` D17): `low_inertia_playback` / `low_inertia_render`
      (`ui/src/low_inertia_window.jl`). Top: the three runs' centre-of-inertia frequency;
      below, per inverter kind, the per-bus PLL meters behind that run's own centre of
      inertia; controls for the tripped unit, the share (0–4) and the layout; the
      read-out is the study's row. Re-run per control (the detailed tier has no
      real-time loop), cached.
- [x] **No second copy of the study**: the script is `include`d into a UI submodule;
      `study_cell(…; keep = true)` adds the samples and changes nothing else. Refactor
      gate: core **4134** green with the change in (the 119 study checks unchanged).
- [x] **Tolerance measured, then chosen** (D17): the study's 1e-6 costs 1.5–36 s a run;
      the window defaults to 1e-4 (0.2–2 s) and names it; `reltol = 1e-6` is the study
      exactly. Found: the sinking cell's nadir third decimal is unconverged at every
      tolerance tried.
- [x] Window checks: read-out `isequal` the study's row; at zero share the two inverter
      runs `==` sample for sample, different at one; a refusal at the trip AND one
      before the run (no samples at all) both leave nothing of the previous setting;
      the meter scale IS the centre-of-inertia rule; an off-scale meter is reported, and
      its number is the most extreme reading.
- [x] **Sabotages, eight, all red in the end — two were GREEN first** (`mutate8w.py`,
      `mut8w*.log`): W8-2 (previous curves not cleared) passed because the refusal tested
      was one at the trip, whose pre-trip samples overwrite the old curve anyway; W8-5
      (off-scale note suppressed) passed because no meter left the scale in the tested
      setting. A sweep of every setting found the two paths (all four units
      grid-following; chain/G4 at three or four) — and **a real bug**: the off-scale note
      printed "meter peak 0.000 Hz" (the extreme-reading search was seeded with 0.0, so
      nothing near 50 Hz could beat it). W8-8 reintroduces it and is red. The others:
      W8-1 tolerance ignored, W8-3 share off by one, W8-4 autoscaled meters, W8-6
      refusal reason dropped, W8-7 columns swapped.
- [x] **Rendered and looked at**, three times: the 4 s zoom flattened the meters'
      departure (now 1.5 s); a refused run's reason now names it in the status line; the
      off-scale note ran off the panel AND attributed the reading to the phase jump —
      which D16 withdrew for the chain — so it now gives the number only.
      `docs/images/fig-m7-low-inertia.png` (chain, G4, one unit): the grid-following
      meters dip to ~49.3 Hz at the trip while the centre of inertia barely moves.
- [x] Precompile workload renders the window (its first open measured 57 s before).

## Step 9 — close

- [ ] Manifests re-resolved, counts re-measured, ledger, SPEC, README, memory.
