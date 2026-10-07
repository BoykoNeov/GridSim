# M8 — Tasks

The checklist. Companion to `m8-plan.md` (the how) and `m8-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate**.

Status: **steps 0–4 done (step 4 on 2026-10-07)**; step 5 next. Step 4 left **4869
core / 1262 reference / 568 UI**, all three gates run (+125 in `test/m8_screening.jl`,
+1 in M7's surface walk); the review follow-up added 16 test-only (grid-following),
so **4885 core by count** (full gate not re-run: nothing under `src/` changed). Step 3 left **4743 core by count** (4735 gated + 8 test-only at review; the full gate was not re-run) **/ 1262 reference / 568 UI** (step 2 left **4429 core / 1262 reference / 568 UI**; step 1: 4265 / 1251 / 568). Entered at `227d214` (the
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
        both entry points;
      - **the residual refusal reached through the solve**, after a review asked
        whether it really was unreachable as first written. The Newton's own
        `abstol` at 1e-6 stops case9 at a residual of 3.0e-7, giving
        `:no_solution` / `:residual`. The constructed overload at the same
        setting keeps `:overload` and withholds its solution.
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
      - **S5**, the voltage outcome listing one bus: red in the L56 two-bus row;
      - **S6**, an overload always keeping its solution: red only in the residual
        test's "withheld" line (`mutate2.py`);
      - **S7**, the residual check skipped: red in the residual test.
- [x] Gate:
      - **4265 core** (4134 + 131 new, so no pre-existing test changed; 4259
        at the first commit, before the residual testset);
      - **1251 reference / 568 UI**, unchanged, exit 0 each;
      - the M5 criterion is **bit-identical** (`criterion-STEP1.txt`, same MD5);
      - the AC capture is **bit-identical** (`ac-STEP1.txt`, MD5
        `5a5873deefd295a470dc5f71260be7ba` once three precompilation lines are
        removed), re-run on the final code (`ac-STEP1b.txt`, the same digest).

## Step 2 — DC line-outage factors, bridges from the graph — done 2026-10-06

Every prediction, band and outcome below was written to
`W:\temp\claude\gridsim-m8\step2_predictions.md` before the run it describes
(spikes `step2_spike.jl`, `step2_attrib.jl`; sabotages `mutate3.py`, `mut-M*.log`;
reference numbers `ref_m8_numbers.jl`).

- [x] `dc_line_outages(net) -> DCLineOutages` (`src/steadystate/screening.jl`): the
      base case from `dc_powerflow`, one Cholesky factorisation of the reduced
      susceptance matrix, one solve per outage, no PTDF formed (D4). `nnz` of the
      reduced matrix is `n + 2m − 1 − 2·deg(reference)`, checked on the mesh and
      case9. `_dc_susceptance` gained a method taking the susceptances, so the
      screen holds **one** `b` vector for its matrix and its flow weights; the old
      method calls it with the same numbers (the DC tests are unchanged and green).
- [x] Bridges from `Graphs.bridges`, matched on the unordered bus pair (a branch
      declared the other way round is still found). Split set = rebuild refusal set
      on the mesh ({DE}) and case9 ({L14, L36, L82}). **Measured: case9's bridge
      margins are −2.2e-16, 0.0, 0.0** — one negative, so a threshold on the margin
      would need its sign handled too, while a connected grid with a 1e7 pu second
      path has 1.0e-8.
- [x] Mesh: worst gap 1.8e-15, 0.06 of the 100·eps·max|f| band. case9 likewise;
      its ring factors are all 0 or ±1 to 1e-12 (asserted — the structural reason
      it is blind, below). Moving the reference bus A → C moves no flow (2.0e-15).
- [x] Near-bridge, second path C–E at 1e3, 1e5 **and** 1e7 pu: inside the
      `100·eps·max|f|/(1 − PTDF_kk)` band (0.052, 0.036, 0.035 of it). The gap
      grows as the margin shrinks (7.9e-13, 2.3e-11, 4.5e-9; at 1e7 it is 1.8e5
      times the ordinary band). **Found, not planned — whose error it is.** An
      exact answer needs no ill-conditioned solve (lose D–E and E hangs off C alone),
      and the rebuild sits at 1.1e-16 from it at every path reactance. **The whole
      gap is the factors'.** Predicted the other way (that the rebuild's matrix,
      equally ill-conditioned, would drift too), and wrong; step 0's prose was
      right. Asserted, so the attribution is a test, not a remark.
- [x] Sabotages in `screening.jl` only, predictions first:
      - **M1** denominator `1 + PTDF_kk`: red on mesh, case9, near-bridge;
      - **M2** transposed: red on mesh, case9, near-bridge. Implemented as `f_k` and
        `f_m` swapped in the update, because with a symmetric inverse a transposed
        PTDF index **is** M3 (`PTDF_km = (b_k/b_m)·PTDF_mk`);
      - **M3** the outaged line's `b_k` in the monitored weight: red on mesh,
        case9, near-bridge;
      - **M4** reference row and column kept: red **only** in the `nnz` testset.
        Every flow check stays green: CHOLMOD factorises the singular matrix, and
        every output is an angle difference while the right-hand side sums to zero,
        so the null direction cancels. Predicted at first to fail the factorisation,
        and wrong. It is an equivalent change, not a test gap, and the structural
        check is what sees it;
      - **M5** consistent wrong reactances (`1/X²` in the one `b` vector, matrix
        and weights alike): red on the mesh and the near-bridge. On case9 the
        **flows** stay green (the identity and the 0/±1 ring test) but the
        **margins** do not. First recorded here as "green on case9"; a review
        caught that `mut-M5.log` had a red case9 line (`margin > 0.1`), see below.
- [x] **The case9 finding, re-scoped.** The plan pre-registered "the reactance
      sabotage" (M3) as green on case9. **That prediction was wrong, by algebra and
      by run**: M3 makes each ring factor `±X_m/X_k`, and case9's ring reactances
      all differ, so it is red there (2.7e13 of the band). What a ring cannot see is
      a **consistent** set of wrong reactances, because losing a ring line reroutes
      all of its flow whatever they are. That is M5: case9's **flows** are blind
      to it and the mesh's are not. Its **margins** are not blind (`X_k²/ΣX²` in
      place of `X_k/ΣX`): Hurdle 13.2's blindness, now with the right sabotage
      attached. A uniform scaling of every reactance is invisible everywhere (the
      factors do not change), so it is not a sabotage at all.
- [x] Reference (`reference/test/runtests.jl`, 11 tests), our factor against theirs
      (their flow = our base + their `LODF[m,k]·f_k`), by arc:
      - Float32-exact reactances: 0.031 of round-off, no storage band;
      - ordinary reactances: 0.012 of `eps(Float32)·max|f|/(1 − PTDF_kk)`; the same
        comparison is 1.4e5 times round-off (the positive control that the sharp
        check can tell the fixtures apart);
      - anti-vacuity: reading `LODF[k,m]` is 7.1e5 times the band;
      - at the bridge D–E it answers: column ≤ 7.6e-17, diagonal −1.0 — "nothing
        else moves", while ours reports a split;
      - at a 1e5 pu second path its clamp cuts E off (C–E at 2.8e-6 pu after losing
        D–E) where ours reroutes the 40 MW (0.400000000023 pu).
- [x] **Found, not planned: M7's walk of the exported surface caught the new
      export.** The first full gate went 4414 / 1 red: `dc_line_outages` takes a
      model and was on neither the "refuses inverters" nor the "handles them" list.
      It handles them (an inverter only moves the base flows, which come from
      `dc_powerflow`), so it joined the learned list **with its own testset**: a
      grid-following inverter on the mesh matches rebuild-and-re-solve, and its
      30 MW offset by 30 MW more load at the same bus gives the inverter-free flows.
      The plan never listed this; the guard is why it was not missed. **Sabotage,
      run after a review pointed out this box was ticked without one** (predicted
      first): the grid-following loop dropped from `bus_injections` turns red
      exactly the "inverter-free flows" line, while the rebuild identity stays
      green, because both sides read that loop. The model's balance check does not
      read `bus_injections`, so nothing throws.
- [x] **Review follow-up: case9's margin check made principled.** The first
      version asserted every ring margin `> 0.1`, a floor chosen after seeing the
      numbers and 6 % under the smallest (L78, 0.106). On a single ring with
      everything else radial the margin has a closed form, `X_k / ΣX_ring`
      (0.6808 → 0.1351 … 0.1058, matching the spike), now asserted to 100·eps:
      the one check on the margin that shares no code with the rebuild. Re-run of
      M5 with predictions first: case9 flows green, the closed form red, mesh and
      near-bridge red as before; also red, not listed: the inverter testset's
      identity, which runs on the mesh.
- [x] Gate: **4428 core** at `922f9fd` (4265 + 163 new, the one changed pre-existing line being
      the learned list in `test/m7_inverters.jl`), **1262 reference** (+11),
      **568 UI**, exit 0 each, all at below-normal priority. The review
      follow-up changed only `test/m8_screening.jl` and docs (one check became two,
      so **4429 core** by count); it was gated by the M8 runner (294 green), and the
      full core suite was **not** re-run for it.

## Step 3 — the AC line screen, and what the shortcut missed — done 2026-10-06

Every prediction, band and outcome below was written to
`W:\temp\claude\gridsim-m8\step3_predictions.md` before the run it describes
(spikes `step3_spike.jl`, `step3_pc.jl`, `step3_pc2.jl`, `step3_fa.jl`; sabotages
`mutate4.py`, `mut-T*.log`). Nothing in `ac_powerflow.jl` changed, so the 83-case
AC digest was not re-run; the screen only calls `_ac_powerflow_outcome`.

- [x] `ac_line_outages(net) -> ACLineOutages` (`src/steadystate/screening.jl`): the
      base case through `ac_powerflow` (a refused base refuses the screen with
      `ac_powerflow`'s own message), bridges from `_bridge_mask`, and per other
      branch `_ac_powerflow_outcome` on the model rebuilt without it. Outcomes,
      solutions, every overloaded element, every low bus and the no-solution reason
      are kept in concretely typed fields.
- [x] `compare_line_screens(net, dc, ac) -> LineScreenComparison`. **It takes the
      model, which the plan's `(dc, ac)` did not**: the DC screen carries no ratings
      (D6). DC overloads are judged by the same `_rating_violations`, on `|f|`. The
      DC base is judged and reported, not refused. Classes: `:splits`, `:dc_blind`
      (AC voltage, no solution, or a grid-forming slack over its rating), `:agree`,
      `:dc_missed`, `:dc_false_alarm`, `:mixed`. AC solutions are one branch shorter
      and are read **by branch id**.
- [x] Checked (`test/m8_screening.jl`, +305 tests; the M8 runner 599 green):
      - **each outage IS the outcome solve on the rebuilt model**, `==` on every
        field, on case9 at 315 / 400 MW / default loads / a re-rated L94, and on
        step 3's mesh; bridges never solved;
      - a refused base refuses the screen with `ac_powerflow`'s message; mismatched
        screens are refused;
      - **case9's voltage demonstration**, no line charging stated beside it: at
        315 MW, L45 and L94 are `:dc_blind` (B5 0.873, B9 0.757) and the other four
        `:agree`; at 400 MW the one DC overload (L89 out, L56 at 100.7 %) is an AC
        voltage refusal, and five of six outages are `:dc_blind`;
      - **positive control**, L94 rated 100 MVA: L67 and L89 out overload it at
        both fidelities (`:agree`, `[:L94]` each), L56 and L78 out are secure at
        both, the base is secure at both;
      - **`:dc_missed`**, L14 rated 150 MVA, L89 out: 96.0 MW in DC, 105.3 MW of
        real power in AC (the slack also covers the losses), 159.7 MVA in AC. Real
        power alone is under the rating at either fidelity, and the reactive part
        takes it over;
      - **`:dc_false_alarm`, on the published case9 only with the default loads**:
        L94 rated 105, L67 out is
        109.8 MW in DC and 100.4 MVA in AC (the voltages sag and the loads draw
        less). The same rating on constant-power loads is `:agree` (121.1 MVA);
      - a grid-forming slack pushed over its rating by an outage is `:dc_blind`;
      - `S_base` 100 against 250: the same classes and over-lists, MW/MVA to 1e-9;
      - an inverter: 30 MW grid-following plus 30 MW more load at B5 screens like
        case9, and is the outcome solve on the rebuilt model with it carried.
- [x] **The miss split and the ladder.** Reactive part `max|S| − max|P|` (≥ 0 by
      algebra, stated, not tested), real-power part `max|P_ac| − |P_dc|`, both ends'
      max so the sign claim holds. Five rungs, one change each, on case9 and the
      mesh, with "no reactive limit bound" asserted on every rung:
      - **A0**, lossless, a zero-P helper machine at `V_set = 1` on every bus
        without a source (load **and** junction buses: case9's B4, B6, B8 would sag
        too), every machine at 1 pu: every `|V|` is exactly 1, and AC − DC sums to
        zero at every bus (≤ 2.5e-14 against a 1e-11 band): **a pure loop flow**;
      - so **case9's ring outages are blind at A0** (each leaves a tree; ≤ 2.4e-14),
        while its intact ring shows 5.0e-5 and the mesh's outages 2.4e-5 … 3.4e-3;
      - A1 + R, A2 + published `V_set`, A3 − helpers (= the published model), A4 +
        default loads: each rung moves the intact model's miss by > 1e-3 (asserted,
        so no rung is a no-op). The **second machine per bus** the plan asked to
        check is moot: helpers go only on buses with no source.
- [x] **Found, not planned: the plan's rung order could not be run.** "Then
      realistic `V_set`" was two changes (helpers off, published setpoints on), and
      with helpers off at `V_set = 1` the mesh's **base** sags out of band (D 0.847
      at the first invented `R = X/5`, 0.877 at `X/10`), so that rung has no screen
      at all. Reordered before any test: published `V_set` with helpers on, then
      helpers off. The mesh's `R = X/10` and `V_set` 1.05 / 1.04 are invented and
      declared.
- [x] **Found, not planned: DC can over-report.** On the published
      constant-power models no AC apparent power fell below its DC flow (smallest
      margin +0.16 MW, case9 at 315 MW; +2.6 at 400; mesh +1.97). On
      constant-impedance loads the sag lowers what the loads draw, so DC exceeds AC
      by up to 12.7 MW (case9 315, L45 out), 23.0 (case9 400) and 19.2 (mesh), and
      a false alarm is reachable. M6 step 7's rule again: a claim made on constant
      power is re-run on the default. **First written as "only on the default
      loads"; the review measured it wrong:** constant power lets DC exceed AC too
      on every ladder rung with a helper machine on each sourceless bus (case9
      A1/A2 −6.3 MW, mesh A0, which is lossless, −0.15, mesh A1 −0.51). What those rungs share is the
      helpers, not resistance (A0 has none) nor 1 pu (A2 has the published
      setpoints); a first rescoping said "1 pu with resistance on" and was wrong
      too. What holds is the scoped claim, asserted in "which loads let DC exceed
      the AC apparent power".
- [x] Sabotages in `screening.jl` only, predictions written first; **all eight red
      exactly where predicted, and nowhere else**:
      - **T1**, the miss read by position: red in the false alarm (L94 is past the
        end of an 8-branch solution) and the A0 tree check. Green, as predicted, in
        the `:dc_missed` test, because L14 comes before the outaged L89 (true at
        e857b52; the review follow-up's L94 by-id check in that test now catches
        it);
      - **T2**, `abs` dropped from the DC judgement: red in the positive control,
        the false alarm and case9 at 400 MW (each overloaded flow is negative in
        model orientation). `S_base` invariance green, both bases equally wrong;
      - **T3**, a hard-coded 100 in the DC judgement: red **only** in `S_base`
        invariance;
      - **T4**, `:voltage` not `:dc_blind`: red in every class vector with a
        voltage row;
      - **T5**, a secure outage storing the base solution: red in the identity, the
        ladder and the inverter test;
      - **T6**, the base not refused: red only in the refusal test;
      - **T7**, the missed and false-alarm labels swapped: red in those two tests;
      - **T8**, a grid-forming slack overload not `:dc_blind`: red only in its own
        test, which was **added for this sabotage** after seeing no fixture
        reached that branch.
- [x] Gate, below-normal priority, exit 0 each:
      - **4735 core**, the count predicted before the run: 4429 + 305 new + 1 from
          M7's surface walk, which now reaches `ac_line_outages` (on its learned
          list, with the inverter testset);
      - **1262 reference / 568 UI**, unchanged.

      Logs: `core-step3.log`, `ref-step3.log`, `ui-step3.log`.
- [x] **Review follow-up (test-only and docs-only, after e857b52).** The review
      found an overclaim, two untested branches and a wrong figure:
      - "false alarm only on default loads" scoped to the measured claim above;
      - L14's "96.0 MW in both" was wrong: 105.3 MW of real power in AC, because
        the slack covers the losses. The `:dc_missed` test's tautological check was
        replaced by a by-id check on L94 (index 8 once the outaged L89 is gone);
      - **`dc_base_over` had no fixture**: step 2's lossless mesh on default loads
        at `V_set` 1.05 / 1.04, DE rated 39, overloads in DC only (40.0 MW against
        37.9 MVA), `dc_base_over == [:DE]`;
      - **`:mixed` had no fixture**: default-load case9, L94 at 105 and L82 at 125,
        L67 out: DC flags L94, AC flags L82;
      - sabotages, predicted first: **T9** (`dc_base_over` always empty) red only
        in its new test; **T10** (`:mixed` folded into `:dc_missed`) red only in
        its new test; **T1** re-run against the new tests is red in the
        `:dc_missed` test's L94 check (as intended) and also in the "which loads"
        test, which was **not predicted** (that test reads AC solutions on
        outages past the removed index);
      - M8 runner 607 green (+8 tests), so core is 4743 by count. The full core
        gate was **not** re-run: nothing under `src/` changed.

## Step 4 — generator outages in the DC screen

- [x] Read how the swing tier's loads respond to frequency **and voltage**, before
      any assertion; oracle fixture with constant-power loads (or relief accounted
      for), finite `R`, `Pmax > P0`, no infinite bus. **Answered from the source**
      (D7): the tier refuses a `Load` and holds `E′` at every bus, so there is no
      voltage term; a load is a damped negative-`P0` machine. Fixture: one machine
      per bus, no bridge and no cut vertex, bases 300/150/120 MVA.
- [x] `pickup_shares(net, lost)` from `machine_arrays`; `dc_generator_outages(net)`.
      Grid-forming inverters share too (gain `1/K_p` from `_inverter_arrays`, no
      cap), every machine is screened including negative-`P0` ones, and the solve
      walks the bends exactly (D7). Flows equal the rebuild to ≤ 2.2e-16.
- [x] Swing-tier `TripGenerator` settled pickup and `Δω` match, within a band
      stated first. Band 1e-7 pu; measured ≤ 1.5e-10 (pickups, from the network
      side) and ≤ 1.5e-12 (every survivor's speed), at 300 s and 450 s, uncapped,
      capped and with an inverter. **Found:** `branch_power(::SwingEngine)` threw on
      every inverter model since M7 step 3; fixed (D7).
- [x] Zero damping reduces to droop alone; damped differs by the predicted amount.
      Closed form only: the zero-damping swing run **never settles** (spread 3e-3
      pu at 300 s), measured and asserted as the reason.
- [x] Cap fixture: one governor at headroom; that machine at `headroom − Δω·D`;
      the swing tier agrees. G3 settles 1.45 MW above its `Pmax` in both tiers;
      its `ΔPm` sits 9.1e-11 past the headroom.
- [x] Refusals by name, exactly two: nothing responds to frequency; `ΣD = 0` with
      every governor capped. A damped huge loss reports its `Δω` (−0.1265 pu, 6.3
      Hz). Outcomes in the screen, throws in `pickup_shares` (D3). case9 as M6
      builds it refuses all three (`:no_response`).
- [x] Losing the slack's own machine: decided and recorded. **DC:** screened like
      any other; the reference is a gauge (≤ 6.7e-16 with it moved). **AC:** the
      user's call, at step 5.
- [x] Sabotages: drop `D`; weights on the machine's own base; cap on the damping
      term too. Plus grid-forming inverters left out. All four red, each in the
      swing-tier comparison as well as in closed form (D7's table).

## Step 5 — generator outages in the AC screen: a shared reference

- [ ] Shared-reference AC solve; `ac_powerflow` unchanged.
- [ ] All weight on the slack equals `ac_powerflow` exactly.
- [ ] Pickup = lost power + change in losses, as an identity.
- [ ] Detailed-tier settled source trip against it, band and reason stated first.
- [ ] **Decide whether a screen flags a grid-forming inverter pushed past its
      rating by its share of a lost generator** (found at step 4, D7: the DC screen
      does not, the swing tier has no limit, and only the `Inverter` constructor
      noticed). The AC solve already calls a grid-forming slack over its rating an
      `:overload`.

## Step 6 — the report

- [ ] The bridge-to-a-lone-source decision, recorded in context.
- [ ] `scripts/outage_screen.jl` on the meshed fixture and case9, both fidelities.
- [ ] Claims in `test/m8_outage_screen.jl`, prose written after reading the table.
- [ ] Window or no window: the user's call.

## Step 7 — close

- [ ] Manifests deleted and re-resolved in all three environments; counts re-measured.
- [ ] **After the re-resolve, re-run both captures** (`criterion_snapshot.jl`,
      `ac_snapshot.jl` in `W:\temp\claude\gridsim-m8\`) and record the new
      digests beside the old ones. Re-measuring only the test counts is how M5's
      values moved unseen at M7's close (step 1's finding).
- [ ] Ledger rows; `SPEC.md` §9 item 8 annotation; README row and hurdle list; memory.
