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

## D4 — What "held" means in the AC OPF

`ac_powerflow` holds a PV bus's voltage until its reactive output reaches a limit,
then frees the voltage and holds the reactive output (M6 step 3). An optimiser
cannot make that switch without a discrete choice. **In the OPF, "held" is
`|V| = V_set` at every machine bus with reactive output inside `[Q_min, Q_max]`; a
point that needs more is infeasible, never switched.** Measured at step 0: on every
case9 fixture the reactive outputs stay at most 166 of 300 MVAr, so the two readings
agree wherever this milestone looks. If a fixture ever reaches a limit, the
handed-back comparison (Hurdle 24.1) is refused for it by name rather than banded.

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
  is added; `reference/Project.toml`'s comments restored after.

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
then "at its limit" when within `δ` + tolerance of the **margined** limit.

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
