# M8 — Tasks

The checklist. Companion to `m8-plan.md` (the how) and `m8-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **step 0 done (2026-10-06)**; step 1 next. Entered at `227d214` (the
`derivative_discontinuity!` rename, after M7's close) with **4134 core** measured
at that commit; reference and UI carried from M7's close at **1251 / 568**. Neither
suite reads the renamed call, and both are re-measured at step 1's gate.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed*, not when the code
runs.

---

## Step 0 — hurdles named, the outside checker measured, plan written (2026-10-06)

- [x] **Topic chosen by the user:** single-outage screening, lines **and**
      generators, a lost generator's power shared by the grid's own speed control
      (`m8-context.md` D0, D2).
- [x] **The hurdles named before any plan prose** (D0): 13 a shortcut exact on its
      own model and blind on the real one, 14 an outage that splits the grid, 15 who
      picks up a lost generator and what the dynamic tiers settle to. Added to
      `docs/plans/README.md`'s list.
- [x] **The outside checker measured before the plan named it** (D1; spike
      `W:\temp\claude\gridsim-m8\step0_probe.jl`, reference environment, nothing
      added). `PowerNetworkMatrices` 0.24.3 `LODF` indexes `[monitored, outaged]`.
      It agrees with our brute force to 2e-9–4e-9 pu on ordinary reactances and
      to ≤ 1.1e-15 when every `1/X` is exact in `Float32`. That is single-precision
      rounding via their `ComplexF32` admittance matrix (`BA_Matrix(ybus)`), M6
      oracle B's finding by a second route. **At a bridge it answers silently**:
      "nothing else moves", the far bus's load vanishing. Its 1e-6 clamp also
      misfires on a connected grid, but only at a path reactance of ~1e5 pu.
- [x] **case9's single-outage table measured** (D1; spike
      `W:\temp\claude\gridsim-m8\case9_n1.jl`). Three bridges, the generator
      connections. At 315 MW, DC passes all six ring outages while AC refuses two
      for voltage (0.873 / 0.757 pu). At 400 MW, DC flags one overload (100.7 %),
      AC refuses five for voltage and fails to converge on one. No line charging
      in this model, stated with every number.
- [x] **Found, not planned — the pickup rule as first offered was wrong.** It was
      offered as "droop sharing, which the dynamic tiers settle to exactly". A
      side review pointed at M1's damping-plus-droop settling law, and
      `swing_vertex!` confirmed it and added the headroom cap. The rule is
      therefore droop **and damping** (D2), and the user was told the same day.
      **Then the correction itself was wrong**: it put the cap around both terms.
      A second review read the saturation again. It acts on the governor state
      only, so the rule is `min(−Δω/Rᵢ, headroomᵢ) − Δω·Dᵢ`: a damped machine can
      settle above `Pmax`, and with any damping there is always a steady state.
      Fixed in D0/D2/plan/README the same day, and the user told.
- [x] **Also from that review, pre-registered before any step runs:** what DC
      misses splits into a reactive part (≥ 0 by algebra, stated, not tested) and
      a real-power part (measured, sign not predicted); holding every bus at 1 pu
      needs a voltage-holding machine on each load bus; the swing-tier oracle must
      control for load **voltage** relief, not only frequency; the near-bridge
      check carries an `eps/(1 − PTDF_kk)` band, not round-off; losing the slack's
      own machine (case9's L14) is a named decision.
- [x] **The blocker settled before any step** (D3): a screen classifies each
      outcome rather than throwing, through the same solve `ac_powerflow` runs,
      switching included, never through `_ac_first_round`.
- [x] Plan written against the hurdles (`m8-plan.md`).

## Step 1 — the AC checks split into named pieces, `ac_powerflow` unmoved (D3)

- [ ] M5's recorded criterion values captured by MD5 at HEAD **before the first edit**.
- [ ] Verdict-returning check pieces; `ac_powerflow` calls them and throws as before.
- [ ] `_ac_powerflow_outcome(net)` in D3's vocabulary.
- [ ] Checked on case9's step-0 outages (`:secure`, `:voltage`, `:no_solution`)
      plus a constructed `:overload`.
- [ ] Anti-vacuity: ratings-before-band reorder goes red on L45.
- [ ] Gate: the whole suite green, criterion values bit-identical, reference and
      UI suites re-measured.

## Step 2 — DC line-outage factors, bridges from the graph

- [ ] `dc_line_outages(net)`: one sparse factorisation, one solve per outage, no
      dense PTDF (D4); `nnz` checked.
- [ ] Bridges from `Graphs.bridges`; the split set equals the brute-force refusal set.
- [ ] Meshed fixture: matches rebuild-and-re-solve to round-off.
- [ ] Near-bridge fixture: matches brute force within the pre-stated
      `eps/(1 − PTDF_kk)` band, at two path reactances so the scaling shows.
- [ ] Four sabotages in the factor code, each red on the meshed fixture.
- [ ] The reactance sabotage run on case9: **predicted green**, recorded.
- [ ] Reference: `LODF` on the Float32-exact fixture with no band; ordinary
      fixture within a band stated first; the checker's bridge answer pinned.

## Step 3 — the AC line screen, and what the shortcut missed

- [ ] `ac_line_outages(net)` and `compare_line_screens(dc, ac)`.
- [ ] The miss split: reactive part reported, real-power part measured; every
      bus held at 1 pu first (second machine per bus checked accepted), then `R`,
      `V_set` and default loads added one at a time.
- [ ] `S_base` invariance.
- [ ] Positive control: one outage that overloads at both fidelities.
- [ ] case9's voltage demonstration, with the caveat.

## Step 4 — generator outages in the DC screen

- [ ] Read how the swing tier's loads respond to frequency **and voltage**, before
      any assertion; oracle fixture with constant-power loads (or relief accounted
      for), finite `R`, `Pmax > P0`, no infinite bus.
- [ ] `pickup_shares(net, lost)` from `machine_arrays`; `dc_generator_outages(net)`.
- [ ] Swing-tier `TripGenerator` settled pickup and `Δω` match, within a band
      stated first.
- [ ] Zero damping reduces to droop alone; damped differs by the predicted amount.
- [ ] Cap fixture: one governor at headroom; that machine at `headroom − Δω·D`;
      the swing tier agrees.
- [ ] Refusals by name, exactly two: nothing responds to frequency; `ΣD = 0` with
      every governor capped. A damped huge loss reports its `Δω`.
- [ ] Losing the slack's own machine: decided and recorded.
- [ ] Sabotages: drop `D`; weights on the machine's own base; cap on the damping
      term too.

## Step 5 — generator outages in the AC screen: a shared reference

- [ ] Shared-reference AC solve; `ac_powerflow` unchanged.
- [ ] All weight on the slack equals `ac_powerflow` exactly.
- [ ] Pickup = lost power + change in losses, as an identity.
- [ ] Detailed-tier settled source trip against it, band and reason stated first.

## Step 6 — the report

- [ ] The bridge-to-a-lone-source decision, recorded in context.
- [ ] `scripts/outage_screen.jl` on the meshed fixture and case9, both fidelities.
- [ ] Claims in `test/m8_outage_screen.jl`, prose written after reading the table.
- [ ] Window or no window: the user's call.

## Step 7 — close

- [ ] Manifests deleted and re-resolved in all three environments; counts re-measured.
- [ ] Ledger rows; `SPEC.md` §9 item 8 annotation; README row and hurdle list; memory.
