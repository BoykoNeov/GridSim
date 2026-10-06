# M8 — Tasks

The checklist. Companion to `m8-plan.md` (the how) and `m8-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **steps 0–1 done (2026-10-06)**; step 2 next. Step 1 left **4259 core / 1251 reference / 568 UI**. Entered at `227d214` (the
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
      AC refuses four for voltage, fails to converge on one, and passes L67. No
      line charging in this model, stated with every number. (Recorded here at
      first as "five for voltage". The spike's own log says four, and step 1
      re-measured four.)
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

## Step 1 — the AC checks split into named pieces, `ac_powerflow` unmoved (D3) — done 2026-10-06

- [x] M5's recorded criterion values captured at HEAD **before the first edit**
      (`W:\temp\claude\gridsim-m8\criterion-HEAD.txt`, M6's harness unchanged):
      169 values, value-line MD5 `1eeed2cc84937cb544eee5c35d0091cf`.
- [x] **Found, not planned: that capture differs from every M7 capture in 89 of
      169 lines.** The differences are about 1e-5 relative, `av.n_steps` goes from
      96811 to 56529, and no `over` crosses 1. Two runs attribute it. The pre-rename
      commit on today's manifest gives today's values, so the rename moved nothing.
      Today's code on the manifest saved before M7's close reproduces M7 step 6's
      capture exactly. **M7's close re-resolve moved them** (`SciMLBase` 3.56.1 →
      3.57.0 among 20 bumps) and was never re-captured (D3, "What step 1
      settled"). Step 7 re-captures after its re-resolve.
- [x] **Found, not planned: the M5 gate cannot see this step's code.** The
      criterion harness never calls `ac_powerflow`. A second HEAD capture was taken
      before the first edit (`W:\temp\claude\gridsim-m8\ac_snapshot.jl`). It holds
      83 cases: every `ACPowerFlow` field at round-trip precision, or the full
      refusal. 20 solved, 20 voltage, 6 overload, 11 Newton failures, 2 named
      refusals, 24 bridges.
- [x] Verdict-returning pieces: `_voltage_band_violations`, `_rating_violations`,
      `_residual_ok`, `_ac_backoff_violations`, `_ac_inverter_slack_excess`,
      `_ac_newton_attempt`. Each returns **every** offender; the throwing check
      takes the first, with the identical message. `ac_powerflow` is now a thin
      thrower over `_ac_solve`, which owns the check order. That order is written
      once, and it is the order the throws already ran in.
- [x] `_ac_powerflow_outcome(net)` returns `(outcome, detail, solution)`. The four
      refusals D3's table left unnamed are decided in D3, "What step 1 settled":
      back-off and residual give `:no_solution`; a grid-forming slack over its
      rating gives `:overload` (`kind = :inverter_slack`); a slack with no source
      still throws.
- [x] Checked (`test/m8_screening.jl`, 125 tests):
      - **outcome and `ac_powerflow` agree** on 56 fixtures, with `==` on every
        field when secure and the named message otherwise;
      - case9's step-0 outages by name: at 315 MW, L45 and L94 give `:voltage`
        and the rest `:secure`; at 400 MW, four `:voltage`, L67 `:secure`, L94
        `:no_solution`, and L56 lists both B5 and B9;
      - a constructed four-branch overload, every offender listed and recomputed
        from the returned flows;
      - switching included (`limited == [:B2, :B3]` at ±0.3 pu), and a switching
        cap of 0 gives `:no_solution`;
      - the slack inverter at 50 MVA against 60; the no-source slack throws from
        both entry points.
- [x] **Found, not planned: step 0's 400 MW count was wrong in the prose.** It read
      "five of six for voltage". Its own log, and step 1, say four voltage, one
      secure (L67) and one non-convergence. Corrected in D0 and step 0 above.
- [x] Anti-vacuity, **re-scoped**: the planned reorder could not move L45, which
      has no overload, and `:secure` was unreachable. It runs on L89 at 400 MW,
      where B9 sits at 0.854 pu and L56 carries 152.6 MVA on the same solve. Five
      sabotages were executed with predictions written first
      (`W:\temp\claude\gridsim-m8\mutate1.py`, `mut-S*.log`). All five went red
      exactly where predicted:
      - **S1**, ratings before band: red in the 400 MW table and the precedence
        test. The agreement test stayed **green, as predicted**, because both
        entry points read one ordered body;
      - **S2**, the throwing band check naming the last offender: red only in the
        pieces test, because the solver builds its own message;
      - **S3**, the ratings piece returning the first offender only: red in the
        overload and pieces tests;
      - **S4**, switching skipped: red in the switching test;
      - **S5**, the voltage outcome listing one bus: red in the L56 two-bus row.
- [x] Gate:
      - **4259 core** (4134 + 125 new, so no pre-existing test changed);
      - **1251 reference / 568 UI**, unchanged, exit 0 each;
      - the M5 criterion is **bit-identical** (`criterion-STEP1.txt`, same MD5);
      - the AC capture is **bit-identical** (`ac-STEP1.txt`, MD5
        `5a5873deefd295a470dc5f71260be7ba` once three precompilation lines are
        removed).

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
