# M11 context — decisions, and what the steps actually measured

Companion to `m11-plan.md` (the how) and `m11-tasks.md` (the checklist). This file
is where a decision is argued once, with the measurement behind it, so nobody
re-litigates it from the code. Read it before disagreeing with the plan.

Convention carried from M2–M10: decisions are `D<n>`, numbered in the order they
were *taken*, not the order the steps run. A section headed "What step N measured"
is added underneath a decision when a step either confirms it or destroys its
stated reason.

---

## D0 — Why this milestone, and the hurdles it exists for (named BEFORE the plan)

M10's close left `docs/plans/README.md`'s hurdle list empty a sixth time, and the
M10 cleanup (2026-10-21) fixed two of the items owed beside it. The topic is the
user's choice (2026-10-21), the first item on the owed list since M6: **the network
optimal power flow** — the cheapest dispatch *subject to* the network's line limits
(and, in AC, its losses and voltages). M6 built only the network-free rung, because
its gate's criterion 4 failed: no outside checker resolved (`m6-tasks.md` step 6).
This section was written after a step-0 measurement (D1) and before the plan.

**The hurdle M6 named is gone, and it is not this milestone's.** "No external
checker" was true on 2026-09-23 and false on 2026-10-21: PowerModels 0.21.7 allows
NLsolve 5, which co-resolves with our stack, and moves nothing of ours (D1.1). So
the hurdles are what stands between "an optimiser exists" and "its answer is
checked", measured at step 0:

- **Hurdle 22 — A network optimum the network actually constrains.** Measured at
  step 0 (D1.2): **on case9 as published no line limit binds**, in DC or in AC with
  voltages held, up to 1.5× load in AC and 1.75× in DC. The DC network optimum *is*
  M6's network-free one (5216.03 $/h both). A network OPF checked only there is
  checked on nothing the network does. Four measurable claims:
  1. **Degeneration, a gate and not an oracle.** With no limit binding, the DC
     network optimum equals `economic_dispatch`'s, to the two solvers' tolerances
     (both are HiGHS, so this is the formulation checked against itself, and says
     so).
  2. **A generator's own line binding is that generator's cap.** L14, L36 and L82
     each connect one machine; in DC their flow *is* that machine's output, so
     rating one at `r` is exactly `economic_dispatch` with that machine's maximum
     at `min(Pmax, r)`. Measured at step 0: the first line to bind under load
     growth is L82, this kind. True by algebra, so it is checked as an identity —
     and it is NOT the network effect the milestone is for.
  3. **A ring line binding reroutes power — the real network effect.** Only L45,
     L56, L67, L78, L89, L94 do this (D1.2). The fixture is case9 with one ring
     line rated below its unconstrained flow — an **invented rating, labelled as
     such** wherever it is printed. The answer must move every unit, not only the
     two the line joins.
  4. **A closed form with one binding line, independent of every solver.** With
     quadratic costs and one line at its limit, the free units satisfy
     `2a₂ₖpₖ + a₁ₖ = λ − μ·PTDF_ℓ,bus(k)`, plus balance and `flow_ℓ = rating`:
     `n + 2` linear equations. On a hand-built three-bus triangle the PTDFs are
     fractions of the reactances written by hand (never read from our DC code),
     and the system is solved with a backslash. M6's equal-incremental-cost closed
     form, one constraint up.

- **Hurdle 23 — An outside check that is not the solver grading itself, on the
  model it was meant to check.** PowerModels solves its DC OPF with Ipopt; ours
  uses HiGHS (already the dispatch extension's) — two solvers, one formulation.
  Three measurable claims:
  1. **Our formula, in their model.** PowerModels' DC branch strength is
     `x/(r² + x²)`; ours is `1/X` (D1.3). At one dispatch on case9 every ring
     line's flow differs by 0.014 MW — enough to fail a strict comparison with no
     bug on either side. The user's choice (D2): the oracle's DC copy carries
     `R = 0`, which IS our formula, so the comparison stays strict. The 0.014 MW is
     kept as a measured fact, not a band.
  2. **The oracle's input does not pass through our conversion.** Its data is
     MATPOWER `case9`'s rows, typed into the reference test from the file (D7),
     never built from our `NetworkModel`. A per-unit or cost-conversion mistake
     shared by both sides would otherwise be green everywhere (M4's lesson; M6
     met it three times). Measured free at step 0: PowerModels' DC cost on the
     published case (5216.0266) equals M6's network-free optimum, so the two
     already read `gencost` the same way.
  3. **A band stated before the gap is seen**, from the two solvers' tolerances,
     on dispatch, cost and every branch flow, on the binding fixtures of Hurdle 22
     — never only on case9 as published, where nothing binds.

- **Hurdle 24 — An AC optimum with held voltages: its own physics, a local answer,
  and a shared solver.** In AC the optimiser and PowerModels both use Ipopt (no
  second open-source NLP solver is on the stack), so agreement between them checks
  the formulation, not the solver. And Ipopt returns a *local* optimum. Five
  measurable claims:
  1. **Handed back to the power flow, the optimum reproduces itself.** The OPF's
     dispatch, run through `ac_powerflow` (our Newton, NonlinearSolve's solver),
     gives the OPF's own voltages, angles and flows to a band stated before. This
     is the check a second, hand-written copy of the AC equations inside an
     optimiser needs — it is the one that sees the two copies disagree — and it
     uses no optimiser.
  2. **Never more expensive than a feasible point we already have.** M6's
     network-free dispatch handed to the flow is a feasible AC point on case9 at
     published load (if, and only if, it passes the band and the ratings — checked
     first); the OPF's cost may not exceed it. Measured at step 0: 5325.27 against
     5325.29, a margin of 0.02 $/h — so the bound is **recomputed in the test**,
     never taken from rounded figures.
  3. **The network shapes the AC optimum through voltage before any rating.**
     Measured at step 0 (D1.4): at 1.5× load `ac_powerflow` refuses the DC
     dispatch (B9 at 0.8996 pu) and the AC OPF moves the dispatch to hold B9 at
     exactly 0.9000. That is the AC fixture with a binding constraint; the refused
     DC dispatch is its positive control.
  4. **"Locally infeasible" is reported as that, never as "infeasible".** From
     1.75× the held-voltage OPF has no answer (Ipopt: LOCALLY_INFEASIBLE). Measured
     cause: the 0.9 pu floor at the load buses — not reactive limits (at most 166 of
     300 MVAr) and not ratings; lowering the floor or freeing the generator
     voltages solves it. The outcome carries the solver's word, and a test pins
     that the cause is the voltage floor.
  5. **One local answer, reached twice.** The same answer from two starting points
     (a flat start and the DC OPF's), as the cheapest check that the reported
     optimum is not an accident of where the search began. Agreement with
     PowerModels is not proof of a global optimum, and no text claims it is.

---

## D1 — Step 0: what was measured before the plan (2026-10-21)

Evidence: `docs/evidence/gridsim-m11/step0/` (`README.md` and the scripts it names).
Julia 1.12.6.

1. **PowerModels resolves now, and moves nothing.** PowerModels 0.21.7 + Ipopt
   1.16.0 resolve alone (79 packages), beside core (220), beside core + the
   reference package (319) and beside core's test target with JuMP + HiGHS (223).
   Every package of ours holds its version in each (NonlinearSolve 4.32.0 /
   4.30.0, NonlinearSolveBase 2.55.0 / 2.48.0, SciMLBase 3.58.0, OrdinaryDiffEq
   7.8.1, NetworkDynamics 1.3.0; PowerDynamics 5.0.0, PowerSystems 5.12.4,
   PowerFlows 0.25.4 in `reference/`). PowerModels' Julia floor is 1.10, ours. The
   cause of M6's failure: PowerModels ≤ 0.21.6 required NLsolve 4; 0.21.7 allows
   `"4, 5"`.
2. **Usable, and where limits bind.** On MATPOWER `case9`: AC OPF 5296.6862 $/h, DC
   5216.0266 (PowerModels' answers, measured, not checked against a
   MATPOWER-stored solution). Shaped as ours — no line charging, G1–G3 held at
   1.04 / 1.025 / 1.025: AC 5325.2661 (5310.0704 with the voltages free). No line
   binds up to 1.5× (AC) or 1.75× (DC); at 2× the first is L82, G2's own line. At
   published load, each line rated at 60 % of its unconstrained DC flow binds and
   moves the dispatch; only the six ring lines reroute power.
3. **The DC conventions differ.** PowerModels `x/(r² + x²)` (`calc_branch_y`,
   `form/dcp.jl`), ours `1/X` (`dc_powerflow.jl`). At one dispatch on case9 every
   ring line differs by 0.014 MW, the generator lines (R = 0) not at all. A grid
   whose lines share one R/X ratio (the mesh) sees no difference.
4. **The held-voltage AC case is bound by the load-bus voltage floor.** At 1.5× the
   optimum sits at min |V| = 0.9000; from 1.75× Ipopt reports LOCALLY_INFEASIBLE,
   unchanged with reactive limits or ratings removed, solved with the floor at 0.8
   (13469.23) or the generator voltages free (13354.99).

---

## D2 — The user's choices (2026-10-21)

Asked in plain words, the recommended option first; all five taken as recommended.

1. **Which OPF: the DC one first, then the AC one** — each with its own outside
   check. (Not: DC only; AC only.)
2. **Generator voltages in the AC OPF: held at their set-points** — as every other
   part of GridSim treats a generator, so the optimum can be handed straight to a
   simulation. (Not: free within the band, 5310 against 5325 $/h on our case9; not
   both.)
3. **PowerModels lives in the reference package** (`reference/`), beside
   PowerDynamics and PowerFlows — measured to resolve there and move nothing.
   Never in core.
4. **case9 only** — the mesh has no costs, and none are invented. The binding
   fixtures are case9 variants (an invented rating, labelled) and small hand-built
   grids.
5. **The DC oracle gets our formula**: its copy of the grid carries `R = 0` in the
   DC comparison, so the comparison stays strict; the 0.014 MW difference of
   formulas is recorded as a fact (Hurdle 23.1).

---

## D3 — The DC OPF's formulation

Unknowns: each machine's output `p` and each bus angle `θ` (the declared slack's
fixed at 0). Constraints: power balance at **every bus** (not one total), each
branch's flow `(θ_f − θ_t)/X` within `±rating/S_base` in both directions, each
machine within `[Pmin, Pmax]`. Objective: M6's quadratic cost through
`cost_arrays` (per-unit, one conversion in one place). Solver: HiGHS, in the
existing `GridSimDispatchExt` (no new dependency for the DC half). Loads are their
nominal `P0` (DC has no voltage, so a load's voltage dependence does not enter).

Same refusals as `economic_dispatch` (no machines, an uncosted machine, an
unreachable load, an inverter) plus the network's own: a grid in pieces (refused by
name — dispatching pieces separately is M10's business, not an OPF's), and a
rating of zero. **Infeasible limits are an outcome**: HiGHS's infeasibility proof
on an LP/QP is a real certificate (unlike Ipopt's local word), and the result says
which.

**The angles carry no cost, and HiGHS regularizes its QP Hessian** (`qp_regularization_value`,
M6's 2.0e-4 MW finding): with `θ` as variables the regularization also touches them,
so the θ formulation is not exactly `economic_dispatch`'s problem even where nothing
binds. 22.1's band is sized for that, or measured with the regularization off, as M6
did — written in step 1's predictions before the comparison.

The answer is a schedule for the existing tools: a dispatch handed to
`dc_powerflow` reproduces the OPF's flows (an identity of the formulation, checked
once as a gate), and handed to `ac_powerflow` shows what the network adds — M6's
`dispatch_loss_gap` reading, now from a network-feasible start.

### What step 1 measured (2026-10-21)

`docs/evidence/gridsim-m11/step1_predictions.md` (written first, not edited after);
`step1/` holds the probe it cites (`probe.jl`, first run from scratch), the script that
printed the numbers below (`numbers.jl`) and the sabotage definitions (`sabotage.py`).
Code: `src/steadystate/dc_opf.jl`, the HiGHS half in `ext/GridSimDispatchExt.jl`; tests
in `test/m11_dc_opf.jl` (74). `τ = 1e-9`, `δ = 1e-6` throughout.

- **22.1 degeneration.** case9 as published binds nothing; the OPF equals
  `economic_dispatch` to 6.1e-13 pu against a band of 2.6e-8, at `ε = 0` and `1e-7`;
  5216.03 $/h. The `dc_powerflow` identity holds on every fixture.
- **22.2.** L82 at 100 MVA: `at_limit == [:L82]`, L82 at −99.9999 MW, outputs
  104.68 / 100.00 / 110.32 MW — `economic_dispatch` with G2 capped, within the band.
- **22.3.** L89 at an invented 50 MVA: only L89 binds (+49.9999 MW); G1 +35.32,
  G2 −33.80, **G3 −1.53 MW**; +234.65 $/h. The directions are as predicted, but G3's
  move only just clears the predicted "more than 1 MW" — the prediction was right by a
  margin of half a megawatt, not comfortably. The closed form on case9's own PTDFs
  agrees within its band.
- **22.4.** Control: 122.56 / 77.44 MW, A→C 130.64, nothing binds. Binding (A–C at
  120): 80.00 / 120.00 MW, A→B −40.00, B→C 80.00; λ = 64.6, μ = 66.4 > 0 from the
  backslash solve. **The predictions file's 22.4 band has an arithmetic slip**: its
  formula `2·4·1.5·(n+1)τ` gives 4.8e-8 pu, not the 3.6e-8 written. The test does not
  use that number; it uses the `‖K⁻¹‖∞` band of the literal 4 × 4 system, 5.6e-8 pu
  (5.6e-6 MW).
- **Infeasible is an outcome.** B5 fed by two 40 MVA lines → `:infeasible` with
  HiGHS's certificate, NaN fields, no throw; `dispatch_schedule` refuses it. The
  control at 46 MVA is optimal **with L56 binding** (L45 44 MW, L56 46 MW into B5):
  the control is a feasible point *at* a limit, not a slack one.
- **Refusals.** The shared checks now take the caller's name (`who`), so `dc_opf`
  refuses as `dc_opf: …` — including the inverter (`I2`). As predicted, a grid in
  pieces and a zero rating cannot reach the OPF: `NetworkModel` and `Branch` refuse
  them first, and the tests assert those refusals instead. An `Inf` rating is
  reachable and means no limit (no row written).
- **Flows are recomputed from θ**, not read from the solver's expressions, and the
  dispatch is projected into `[Pmin, Pmax]` with a refusal past the tolerance — the
  result is what `dc_powerflow` would say, by construction.
- **Sabotages, all five run, every one red.** (A solver time limit was added to each
  mutant, after S4's first run spun for two hours without an answer.)
  - S1a (upper limit only): 22.2 red, as predicted.
  - S1b (lower limit only): 22.3 and 22.4 red, as predicted.
  - S2 (rating not ÷ `S_base`): 22.2, 22.3, 22.4 red, as predicted.
  - S3 (`X` for `1/X`): identity, 22.3, 22.4 red, as predicted.
  - S4 (balance on the total): identity, 22.2, 22.3, 22.4 red, as predicted — but
    on case9 by a **thrown solver error**, not a wrong answer: HiGHS stops with
    `OTHER_ERROR` on 22.1–22.3 and hits the time limit on the infeasible and `Inf`
    fixtures (without the limit, that was the two-hour spin). Only on 22.4's
    triangle does the mutant give an answer, and it is wrong: 42.6 MW off the
    closed form, the identity red, A→B at +250 instead of −40.
  - **Not in the table:** the infeasible fixture is red under S1a, S1b and S2. The
    table had no column for it; it catches a missing limit in **either** direction,
    because it needs both lines' limits (L45 carries power into B5 forwards, L56
    backwards).
  - **Contradicts the table — 22.1 is not green under every sabotage.** Under S3 its
    dispatch-vs-dispatch check fails once (7.4e-8 pu against 2.6e-8). This is
    consistent with the regularization acting on angles the mutant makes far larger,
    but not isolated. Under S4, HiGHS cannot solve 22.1 at all (`OTHER_ERROR`): with
    one total balance row, the angles appear only in the limit rows. The prediction
    that the degeneration is a gate, and blind, was wrong in the safe direction (it saw
    more than predicted).
- **Gate.** All eleven captures (the M9 harness's six, the oracle, the M10 snapshot
  directory, both report scripts, the dynamic-run capture) are byte-identical to fresh
  `-HEAD` captures taken before the change; every run exited 0. The only stderr change
  is the oracle's one-off precompile lines. Core 25242 = 25167 + the 74 new tests
  + **1 not planned**: M7's walk of the exported surface (`test/m7_inverters.jl`)
  reaches `dc_opf`, a new one-argument `NetworkModel` function, and it passes by
  refusing the inverter (`_assert_no_inverters`, through the shared
  `_dispatch_problem`), so no list needed growing. Reference 1439 and UI 4212, unchanged.

## D4 — What "held" means in the AC OPF

`ac_powerflow` holds a PV bus's voltage until its reactive output reaches a limit,
then frees the voltage and holds the reactive output (M6 step 3). An optimiser
cannot make that switch without a discrete choice. **In the OPF, "held" is
`|V| = V_set` at every machine bus with reactive output inside `[Q_min, Q_max]`; a
point that needs more is infeasible, never switched.** Measured at step 0: on every
case9 fixture the reactive outputs stay at most 166 of 300 MVAr, so the two readings
agree wherever this milestone looks. If a fixture ever reaches a limit, the
handed-back comparison (Hurdle 24.1) is refused for it by name rather than banded.

### What step 3 measured (2026-10-21)

`docs/evidence/gridsim-m11/step3_predictions.md` (written first, not edited after); `step3/`
holds the probes it cites, the gap table and the sabotage definitions. Code:
`src/steadystate/ac_opf.jl` (`ac_opf`, `ACOPF`, `dispatch_schedule(net, ::ACOPF)`), the Ipopt
half in a new extension `ext/GridSimOPFExt.jl` on JuMP + Ipopt; tests in
`test/m11_ac_opf.jl` (216).

- **The root environment.** Re-measured on a scratch copy first (190 → 201 with Ipopt,
  → 215 with the test target's JuMP + HiGHS; nothing moved or removed), then
  `Pkg.add("Ipopt"; target = :weakdeps)` and the extension, `[compat]` (1.16.0),
  `[extras]` and test target by hand. `Project.toml` carries no comments, so none were
  lost. Both extensions load in one session.
- **The two copies.** The optimiser's AC equations are written in branch form (each
  end's power from the series admittance, summed per bus) with the loads' draw as the
  polynomial `a_z|V|² + a_i|V| + a_p`; `ac_powerflow` writes bus-admittance form through
  `_ac_flows` and `_zip_scale`. The answer is read back through the flow's own
  `_ac_branch_flows` and `_zip_scale`, and anything past a margined limit by more than
  `near = 2(n + 1)τ` is refused, as `dc_opf` refuses a projection past `tol` (the plan
  review's addition).
- **The schedule handed back is NOT the OPF's outputs verbatim** — a departure the plan
  did not foresee. `NetworkModel` refuses a schedule that does not balance at nominal
  voltage, and an AC dispatch carries the losses (and, on default loads, the load-draw
  shift). So `dispatch_schedule(net, ::ACOPF)` gives every machine but the slack's its OPF
  output and the slack's machine the nominal balance; the flow never reads the slack's
  `P0`, and 24.1 compares the flow's solved slack output with the OPF's. Refused by name: a
  non-optimal answer, a slack bus with several machines, a balance over the slack's Pmax.
- **The margins, sized against the re-solve, not the solver** (the plan review's point).
  The handed-back flow can move |V| and θ by `band_x = 2κ(2τ + ρ_pf)` and a branch's |S| by
  `6.82·|y|max·band_x`; κ, the flow Jacobian's inverse norm, is 1.30 – 1.42 at the five
  handed-back points (computed in the test, at each). At `τ = 1e-9`: 5.4e-9 – 5.9e-9 pu and
  6.4e-7 – 7.0e-7 pu. **`margin_S` is therefore 1e-5 by default**, not step 1's 1e-6: 1e-6
  of L94's 60 MVA is 6e-7 pu, below the flow band. `margin_V` stays 1e-6. The test asserts
  both inequalities on every fixture's own κ.
- **24.1, handed back** (published cp and default, 1.5× cp, L94 at an invented 60 MVA cp and
  default): every gap at round-off — |V| and θ ≤ 1.5e-14, flows and |S| ≤ 1.3e-13, the
  slack's output ≤ 3.4e-14 pu, against the bands above. The answer's own recomputed balance
  residual is 4e-15 – 1e-14: Ipopt's final equality violation is far below its stated
  `τ`, so the bands are 5–7 orders wider than the gaps. They are the tolerance's bands,
  stated first, and the sabotages below are what shows they are not blind.
- **24.2.** M6's dispatch handed to the flow is feasible for the OPF's own margined problem
  on both load models (Q of all three machines inside ±300 MVAr, the slack inside its
  limits, min |V| 0.9537 / 0.9592, worst branch L82 at 143 / 142 of 250 MVA). The OPF is
  cheaper by **0.019638 \$/h** on constant power (5325.266075 against 5325.285712) and
  **14.219829 \$/h** on default loads (4883.325762 against 4897.545590). Asserted as
  recomputed inequalities.
- **24.3.** The control's margin on the EXACT dispatch is 4.5e-4 pu (B9 at 0.899554), not
  the 0.8996-on-rounded-numbers the plan worried about, so 1.5× stays. **On default loads
  the DC dispatch already passes at 1.5×** (min |V| 0.9189), so the voltage fixture is a
  constant-power fixture only. The OPF holds B9 at `0.9 + margin_V` = 0.900001 (cost
  10241.634349 against the DC 9857.82), and its schedule passes `ac_powerflow` with B9 at
  0.9000010000.
- **24.4.** 1.75× on constant power: LOCALLY_INFEASIBLE. With the floor at 0.8 it solves
  (13469.230919, step 0's PowerModels figure); with the reactive limits removed it does not.
  So the cause is the floor. On default loads 1.75× solves (10146.29; the loads sag).
- **24.5.** Flat and DC-OPF starts reach the same answer on all five fixtures: gaps ≤ 2.6e-14
  pu, at most 0.2 % of step 2's band form `2(c_flat + c_dc) + ρ`.
- **L94 at an invented 60 MVA, the AC rating fixture** (chosen from the unconstrained
  optimum's end-to-end table: L94 carries the larger |S| at its receiving end, 68.59 → 71.73
  MVA). It binds there on both load models, the sending end 2.8 MVA below; every unit moves
  (G1 −36.9 MW on constant power); +257.43 \$/h. At 50 MVA it is locally infeasible; L56 at
  45–50 MVA stops Ipopt at ALMOST_LOCALLY_SOLVED, which throws.
- **Ipopt at `tol = 1e-11`** stops at SLOW_PROGRESS or ALMOST_LOCALLY_SOLVED on three
  fixtures; the tight run is 1e-10. Its own convergence `|run(1e-8) − run(1e-10)|`: 4e-13 –
  6.2e-12 pu.
- **Sabotages, all five run, every one red where predicted** (each with Ipopt's 120 s CPU
  limit; none hit it).
  - SA1 (every branch's `R` dropped from the optimiser's copy): 24.1 red on all five
    fixtures — on the published ones by 4.5 MW on the slack and up to 11 MW on a branch
    (bands ~6.5e-5 MW), and on 1.5× and L94 by the
    handed-back flow refusing (B9 at 0.89955; L94 at 65.65 MVA over 60); 24.3 red.
    **Not in the table:** the answer's own read-back residual (0.22 pu against 2e-8), the
    L94 testset (on default loads L94 no longer binds), and **24.2 on default loads** (4916.03
    against 4897.55 — the table called 24.2 blind to a lossless copy. The cost is read from
    the outputs alone, so the mutant's dispatch itself is dearer; the likely reading, not
    isolated, is that without resistance its voltages sag less and its default loads draw
    more).
  - SA2 (only L94's `R` dropped — added, stricter than the plan's): 24.1 red on the
    published fixtures, on L94 (|V| off by 1.9e-3) and on 1.5× (the flow refuses B9).
  - SB (the rating at the sending end only): the L94 fixture red on both load models — the
    read-back refuses L94 at 62.85 / 62.52 MVA against 59.9994. **Not in the table:** 24.4's
    floor-lowered variant, where L82's receiving end runs to 260.55 MVA against its 250.
  - SC (the held voltages left free): 24.1 red everywhere (|V| off by up to 0.10 pu, Q by up
    to 1.8 pu; the flow refuses 1.5× and L94), 24.3 red, the read-back residual
    red (1.38 pu).
  - SD (every load read as constant power): 24.1 red on both default-load fixtures (|V| off by
    5.5e-3, the slack by 0.19 pu) and green on every constant-power one — blind there by
    construction, as predicted. **Not in the table:** 24.2 on default loads (the mutant
    serves the full load: 5325.27 against 4897.55).
  The 24.5 two-starts check is green under every sabotage, as predicted: it checks that one
  local answer is reached twice, not that it is the right problem's.
- **Gate.** All eleven captures byte-identical to fresh `-HEAD` captures taken before
  `Project.toml` changed; every run exited 0; stderr differs only by one-off precompile
  lines. Core 25242 → **25450** = + 207 new + 1, the +1 read as M7's exported-surface walk
  reaching `ac_opf` (the mechanism step 1 measured for `dc_opf`; not isolated this time).
  Then, from the closing review: **nine more tests make every new guard fire once** — the
  read-back's three breach refusals (on a doctored problem), two machines on one bus with
  different `V_set`, the schedule's several-slack-machines and over-Pmax refusals, and a
  failed DC OPF as the start — plus a docstring corrected (the over-Pmax refusal has no
  lower end). Core **25459**, all passing; the source change was the docstring alone, so
  the captures were not re-taken.
  Reference 1493 and UI 4212 unchanged; all passing. `ACOPF`/`ac_opf` checked clear against
  `names(GLMakie)` in `ui/`.
- **For step 5 (raised after the step closed, checked in the code):** the slack's
  scheduled `P0` is the nominal balance, not its OPF output, so anything that reads `P0`
  directly starts the slack a few MW off the optimum. The detailed tier takes `Pm` from the
  power flow (`_seed_from_powerflow`), but its governor headroom is still `Pmax − P0` from
  `machine_arrays` — on case9 at published load the slack's headroom is overstated by the
  losses (schedule 86.26 MW, optimum 90.72 MW). Not new to M11: every schedule in the repo
  balances at nominal load and the slack picks up the losses only in the flow. Before step 5
  claims the optimum "feeds the simulators as is", list which engines read `P0` (the
  frequency and swing tiers do, and the detailed tier's headroom) and either state the gap
  or close it.
- **For step 4:** in `reference/` only `GridSimDispatchExt` precompiled after the change,
  although Ipopt and JuMP are both there — its manifest still records GridSim's old
  extension list. Re-resolve `reference/` (and check `GridSimOPFExt` loads) before the AC
  oracle is written.

## D5 — What M11 is not

Not built, and not implied: unit on/off decisions (M6 D16 §7); several hours at
once; **security-constrained dispatch** (an OPF that also survives M8's or M10's
outages — the natural next rung, owed); **locational prices** (the per-bus duals —
a classic DC-OPF output, owed with its own check); free generator voltages (the
user's choice, D2.2); losses priced in the DC OPF; inverters as dispatchable units
(refused, as in M6); a cost on the mesh (D2.4); a window unless the user chooses one
at the report step.

## D6 — Where the solvers live

- **DC: HiGHS, through the existing `GridSimDispatchExt`.** Nothing new.
- **AC: Ipopt, a new weak dependency, in a new extension** (`GridSimOPFExt` on
  `JuMP` + `Ipopt`, name provisional) — core does not grow for a session that never
  optimises (M6 D16 §4). Measured at step 0 that Ipopt + PowerModels beside core's
  test target move nothing; **re-measured at step 3 in the root environment itself**
  before `Project.toml` changes (M6 step 4's rule: the probe's environment is not
  the one being changed). `Pkg.add` drops `Project.toml`'s comments — `git diff` and
  restore them.
- **PowerModels: `reference/` only** (D2.3), re-measured there at step 2 before it
  is added; `reference/Project.toml`'s comments restored after. (Step 2: with Ipopt,
  JuMP and HiGHS — the last two so that our `dc_opf` runs there; "What step 2
  measured", under D7.)

## D7 — The oracle's data: typed from MATPOWER's file, read by PowerModels' own reader

The reference test carries case9's rows (bus, gen, branch, gencost) **typed from the
file**, with its URL and the commit it was fetched at, as
`test/m6_economic_dispatch.jl` already carries the cost rows. They are written out
as **MATPOWER-format text and handed to `PowerModels.parse_matpower(IOBuffer(...))`**
— their reader, the path step 0 measured (5216.0266) — never as a hand-built
PowerModels dictionary, which would be a third conversion (per-unit, angles, cost
scaling) checked by nothing. Nor is the input ever built from our `NetworkModel`: a
conversion mistake shared by both sides would be invisible (Hurdle 23.2). The
invented binding fixtures are edits to the same text on the oracle's side and to the
same literals on ours.

`case9.m` itself is not committed: the test needs only its rows. (MATPOWER's licence
covers its code and says its case files are not covered by it; the typed rows are
the same data the repo has carried since M6.)

**PowerModels' reader adds a constraint we do not have**: `correct_voltage_angle_differences!`
tightens case9's ±360° branch angle-difference bounds to ±60° (1.0472 rad, measured
in the installed 0.21.7 source). Steps 2 and 4 name it and assert it never binds.

### What step 2 measured (2026-10-21)

`docs/evidence/gridsim-m11/step2_predictions.md` (written first, not edited after);
`step2/` holds the probes it cites and the sabotage definitions. Code:
`reference/src/opf_oracle.jl` (`matpower_edit`, `oracle_dc_opf`); tests in
`reference/test/m11_dc_opf_oracle.jl` (54), included by `reference/test/runtests.jl`.

- **Four packages, not two.** The task line named PowerModels + Ipopt. Our `dc_opf` runs
  only with `GridSimDispatchExt` loaded, so `reference/` also needed **JuMP and HiGHS**
  (the package imports HiGHS for that side effect). Re-measured on a copy of
  `reference/`'s own environment first: 300 → 321 packages, nothing of ours moved,
  nothing removed; the real add then gave the identical manifest. `[compat]` floors
  PowerModels at 0.21.7, the first release that resolves here; comments restored.
  **And Printf in the test target**: the test includes the report script for our side
  (D10), the script uses Printf, and `Pkg.test()`'s sandbox cannot see a stdlib it does
  not list — the first full run failed to load the file exactly so (the probes ran outside
  the sandbox and passed). Added by `Pkg.add`, moved to `[extras]` as the root has it.
- **The source, pinned.** MATPOWER `data/case9.m` last changed at `31e3308e` (2017-10-31),
  byte-identical at master `80b6e16f` (2026-10-21), sha256 `ee50fc7b…8623`. The typed
  rows parse `==` to the downloaded file through `parse_matpower(IOBuffer)`.
- **D9's margin, as read for an outside comparison.** Our side runs at `margin = 0`
  against PowerModels' unmargined ratings — the same problem on both sides. D9's reason
  (strict tools downstream) does not apply to a comparison, and on the binding fixtures
  the margin (5e-7 pu on L89) is four to five orders above the tolerance terms, so a band that
  covered it would be blind below it. This replaces D9's "their band covers δ" for
  step 2; step 4 decides its own reading.
- **The band** is each side's own convergence, summed and doubled, plus a stated
  round-off allowance `ρ = 1e-11` (pu; `1e-11·|cost|` on cost). Our convergence is
  **exactly 0** (HiGHS's QP is active-set: one linear solve once the active set is
  found); HiGHS also refuses tolerances below 1e-10, so our tight run is 1e-10, theirs
  1e-11 (Ipopt reports SLOW_PROGRESS at 1e-13 on the binding fixtures).
- **Agreement, strict.** On F1 (published), F2 (L82 at 100 MVA), F3 (L89 at 50 MVA) and
  F4 (L45 and L56 at 46 MVA) every output, flow, angle and cost agrees within the band:
  gaps 2.5e-13 to 1.4e-12 pu, bands 1.05e-11 to 1.28e-11 pu; cost gaps ≤ 9.1e-10 \$/h
  against ~5.5e-8. **The gap is Ipopt's own convergence**: on F1 it equals their
  `|run(1e-8) − run(1e-11)|` (2.52e-13) to three figures, so our answer matches their
  tight run to round-off. The same line binds on both sides, on its rating. Their ±60°
  bound is present on every branch and never within 0.9 rad of binding (largest angle
  difference 0.116 rad). 23.2: both costs round to 5216.0266.
- **F5, the infeasible fixture**: ours `:infeasible` with HiGHS's certificate; theirs
  LOCALLY_INFEASIBLE / INFEASIBLE_POINT. Reported side by side, not called agreement.
- **23.1, the formula difference with `R` left in**: on F1 every ring line differs by
  **0.01399 MW** (the same circulating amount on all six; step 0's "0.014"), the
  generator lines and the outputs not at all beyond the strict band. On F3, with L89
  binding, `R` moves the outputs too: G1 0.092, G2 0.202, G3 0.294 MW. Both asserted to
  exceed the strict band; never used as one.
- **Sabotages, all three run, every one red where predicted.**
  - SA1 (our L89 `x` 0.161 → 0.116, script only): F1 red on flows and angles (outputs
    green — nothing binds), F2 red on flows and angles, F3 and F4 red on everything; F5
    green (blind), as predicted. Largest gap 0.088 pu.
  - SA2 (our G2 `c1` 1.2 → 1.25): F1, F3, F4 red on everything; F2 red on cost ALONE,
    by exactly 5.0 \$/h (0.05 \$/MWh × G2's 100 MW pinned by its line — the predicted "other
    two may move" did not happen: with G2 on its line the other two see no change);
    F5 green. **Not in the table:** 23.2 red (the cost) and 23.1 red twice (its strict
    halves compare outputs and generator-line flows).
  - SB (the invented rating written into their text in pu): F1 green (blind), F2, F3,
    F4 red, F5 green, as predicted. **Not in the table:** the input testset is red too
    (it reads the edited rating back through their reader, 0.005 for 0.5 pu). SB is
    the plan's sabotage turned round: the plan's "rating in MW where pu is expected" can
    only happen in a hand-edited parsed dictionary, which this code never builds (D7), so
    it has no path to break. The unit mistake that CAN happen is in the text edit, pu
    written where the file expects MVA, and that is the one run.
  SA1 and SA2 red is Hurdle 23.2 shown: a literal wrong on our side only is seen, so
  their input does not pass through our data.
- **Gate.** The reference oracle capture (`oracle_snapshot.jl`, the one capture that runs
  in `reference/`) is byte-identical before and after the package change; its stderr
  differs only by the one-off precompile lines. Core and UI environments were not
  touched, so their captures and counts are not re-run at this step. Reference suite
  1439 → 1493 (the 54 new tests), all passing.

## D8 — Bands are stated before the gap is seen

Every comparison against an outside or a second answer — PowerModels' DC and AC,
the handed-back power flow, the two starting points, the degeneration to
`economic_dispatch` — has its band written into
`docs/evidence/gridsim-m11/stepN_predictions.md`, derived from the solvers'
tolerances, **before** the comparison first runs (M4 D7, M6's oracle B: the
oracle's accuracy is a floor, not a ceiling).

## D9 — An optimum ON a limit, handed to a check that refuses strictly

The binding fixtures exist to put the optimum exactly on a limit — B9 at the 0.9 pu
floor, a ring line at its rating. An interior-point solver holds a constraint only to
its tolerance, so B9 can come back at 0.8999999…, and `ac_powerflow` (and the detailed
tier's initialisation) refuse a bus below 0.9 or a branch over its rating **strictly**.
M6's `30.000000000000004` lesson, one level up: the handed-back check (24.1), the
voltage fixture (24.3) and step 5's flat run would then fail by round-off, with no bug
anywhere.

**Decided: the optimiser works against limits pulled in by a stated margin** — the
voltage band to `[0.9 + δ_V, 1.1 − δ_V]`, each rating to `rating·(1 − δ_S)`, with
`δ` stated, at least the solver's constraint tolerance, and **carried on the result**
(as M6's `tol` is), so an answer is strictly inside every limit the strict checks
read. The alternative — comparing the handed-back solve through a path that skips
the refusals (`_ac_first_round`/`_ac_newton`) — was rejected: the claim is that the
schedule *feeds the simulators as they are*, and a path around their checks does not
show that. The outside comparisons (steps 2, 4) give PowerModels the unmargined
limits and their band covers `δ`, stated before the run. A binding constraint is
then "at its limit" when within `δ` + tolerance of the **margined** limit. (Step 2 read
the outside comparison differently, before its run: our side at `margin = 0`, the same
problem on both sides — "What step 2 measured", under D7.)

## D10 — Where the costed case9 lives

The report grids' `case9()` (`scripts/outage_screen.jl`) carries no costs and no
`Pmin`, so `economic_dispatch` — and the OPF — refuse it by name. The only costed
case9 is `_ed_case9` in `test/m6_economic_dispatch.jl`, and a deliverable script must
not reach into the test suite (that script's own rule). **Decided: `case9` gains a
`costed` keyword** (default `false`, so no existing caller or capture moves) that
adds MATPOWER's `gencost` rows and the 10 MW minimums, typed in the script; a test
asserts the two copies agree row for row — the pattern M8 used for the branches.
Checked at step 0: `_ed_case9`'s set-points (1.04 / 1.025 / 1.025) and reactive
limits (±300 MVAr) are the shape the AC evidence used.

**`Machine` refuses `P0 > Pmax`**, so 22.2's "G2's maximum lowered to the rating"
model moves G2's schedule down with it (and the slack's up) — the schedule is not
what the dispatch reads, but the model must exist to be dispatched.

## D11 — On voltage-dependent loads the AC optimum can buy cheaper load, not cheaper generation

`Load`'s default is constant **impedance**: a load draws less at a lower voltage. An
AC optimiser with the default loads can lower its cost by choosing a dispatch that
lets the load-bus voltages sag — serving less load, not generating more cheaply. M6
met the same term after the fact (−318 $/h on case9's default loads, `m6-tasks.md`
step 7, F7). **Decided: M6's rule carries** — the AC result reports the load-draw
shift (`Σ Pload` at the solved voltages − `Σ P0`) separately from the losses, and no
text calls the cost difference against the network-free optimum "the cost of the
network" on default loads. The bound (24.2) compares two points feasible for the
*same* problem — same load model — so it holds as an inequality on either load
model; the report says what the difference is made of.
