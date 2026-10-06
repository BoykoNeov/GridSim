# M8 — Single-outage screening · Plan

Companion docs: `m8-context.md` (decisions and, as steps run, what was measured),
`m8-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M7 trios.

**Read `m8-context.md` D0 first.** The three hurdles there were named before this
plan was written, after a step-0 measurement (D1), and every step below is
justified against one of them.

M8 has **no separate pre-study**. The algebra (line-outage factors, the
droop-and-damping settling law) is textbook and fits in D0. The genuine unknowns
were how the outside checker behaves, and what case9 does under single outages,
and both were measured at step 0 rather than argued.

## Goal

Make the repo able to answer **"what happens if this one element fails?"** for
every line and every generator of a model, and answer it twice: with the cheap
linear shortcut real screens use, and with the full nonlinear flow. The gap
between the two is what gets checked and explained.

By the end of M8 a `NetworkModel` can be screened for every single line outage
and every single generator outage, at both fidelities. Each outage gets a named
outcome (`m8-context.md` D3), not an exception. A tripped generator's power is
shared by droop and damping, the droop part capped at headroom (D2), and checked against what the
dynamic tiers settle to after the same trip. Grid splits are found from the graph,
never from a tolerance. One script screens case9 and the meshed fixture and prints
what the cheap screen missed and why.

## What M8 is not

See `m8-context.md` D5: no transient stability, no batched/GPU runs, no
map, no N-2, no corrective re-dispatch, no parallel circuits, no line charging.

## The order, and why it is the order

The ordering rule is M4 D7's, carried through M5–M7: **never let two things
change at once between a number and its check.** So the AC checks are split into
named pieces first, under an invariant that `ac_powerflow` does not move by a bit,
because every later step reads outcomes through that split. The DC line-outage
factors go next, because their check is an exact identity against brute force.
The AC line screen follows, because it is the first step whose answer differs from
its reference, and that difference is Hurdle 13's subject. Generator outages come
after lines: the DC version first, because its pickup rule has an exact dynamic
oracle in the lossless swing tier, and the AC version after it, because it needs
new solver work (a shared reference) and its oracle is weaker. The report comes
last, because it is the first step that is a *result* rather than a mechanism.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs. It is done when its named check passes with a
positive control and an executed anti-vacuity mutation**, the standing rule since
M3.

### Step 1 — The AC checks split into named pieces, `ac_powerflow` unmoved (D3)

`_check_voltage_band`, `_check_branch_ratings`, `_check_residual` and the
non-convergence path become callable pieces that **return** a verdict. The single
solve keeps calling them and throws exactly as today. An internal
`_ac_powerflow_outcome(net)` runs the identical solve, switching included, and
returns `(outcome, detail, solution-or-nothing)` in D3's vocabulary.

- **Gate:** the whole suite green **and** M5's recorded criterion values
  bit-identical by MD5, captured at HEAD before the first edit (M6 step 1's
  method). The outcome function is checked on step 0's case9 outages, which
  between them produce three of the five outcomes, plus a constructed overload.
- **Anti-vacuity:** reorder the verdicts (ratings before band). The L45 case
  must then report `:overload` or `:secure` instead of `:voltage`, and a test
  must go red. **Re-scoped at step 1 (`m8-context.md` D3, "What step 1
  settled"):** L45 has no overload, so the reorder cannot move it, and `:secure`
  was never reachable. The mutation runs on L89 at 400 MW, where both
  violations occur on one solve.

### Step 2 — DC line-outage factors, bridges from the graph (Hurdles 13.1, 13.2, 14.1)

`dc_line_outages(net)` returns, per branch, either the post-outage flow on every
other branch or `:splits`. It is computed from one sparse factorisation of the
reduced susceptance matrix and one solve per outage (D4). Bridges come from
`Graphs.bridges`.

- **Checks:** against rebuild-and-re-solve on the meshed five-bus fixture
  (step 0's), to round-off. The split set equals the brute-force refusal set. The
  near-bridge fixture (second path `X = 1e5` pu) still matches brute force, within
  the `eps/(1 − PTDF_kk)` band D0 states in advance, and at two path reactances so
  the scaling shows. `nnz`
  of the factorised matrix is as M6 step 2 predicts.
- **Sabotages, in the factor code only:** wrong denominator sign; the
  monitored/outaged index transposed; the outaged line's own reactance used where
  the monitored one belongs; slack row not deleted. Each one red on the meshed
  fixture. The reactance sabotage is **also run on case9** and is predicted green
  there (Hurdle 13.2); that green is recorded as the finding. **Re-scoped at step
  2:** that prediction was wrong (red on case9, `±X_m/X_k`). The green belongs to a
  fifth sabotage, a consistent wrong set of reactances, run as well; case9's flows are blind to it, its margins are not. "Slack row not
  deleted" turned out an equivalent change for every flow, seen only by `nnz`
  (`m8-context.md` D4, "What step 2 settled").
- **Oracle (reference/):** `PowerNetworkMatrices.LODF` on the Float32-exact
  fixture with **no band**, and on ordinary reactances within a band stated before
  the gap is seen, derived from their storage (D1). Bridges are excluded by our
  graph, and a test pins that the checker *answers* at a bridge (the silent
  "nothing changes") rather than refusing.

### Step 3 — The AC line screen, and what the shortcut missed (Hurdles 13.3, 13.4)

`ac_line_outages(net)` runs step 1's outcome solve per non-bridge outage.
`compare_line_screens(dc, ac)` reports, per outage, both outcomes and every
disagreement, classified as "DC fine, AC overloaded", "DC overloaded, AC fine", or
"AC voltage / no solution", which DC cannot express.

- **The miss, split in two (Hurdle 13.3):** per branch per outage, the reactive
  part `|S_ac| − |P_ac|` (≥ 0 by algebra, so stated and not tested) and the
  real-power error `|P_ac| − |P_dc|` (measured, sign not predicted). Its causes
  come one at a time: lossless branches and constant-power loads with every bus
  held at 1 pu (a zero-`P`, unlimited-`Q` machine at `V_set = 1` on each load bus,
  after checking that a second machine at a bus is accepted). Then `R`, then
  realistic `V_set`, then `Load`'s default constant-impedance shares, each
  reported separately.
- **`S_base` invariance:** the same physical case on two bases gives the same
  outcomes and the same MW/MVA.
- **Positive control:** a fixture with one outage that genuinely overloads at
  both fidelities. Without it a screen that reports `:secure` everywhere passes.
- **case9's voltage demonstration**, with D0's line-charging caveat printed
  beside every number.
- **Re-scoped at step 3 (`m8-context.md` D6):** the comparison takes the model,
  `compare_line_screens(net, dc, ac)`, because the DC screen carries no ratings.
  The "realistic `V_set`" rung was two changes, and the mesh's base case cannot be
  solved with the helpers off at 1 pu. So the ladder runs: published `V_set` with
  the helpers on, then the helpers off.

### Step 4 — Generator outages in the DC screen, shared by droop and damping (Hurdles 15.1–15.4)

`pickup_shares(net, lost)` solves `Σ min(−Δω/Rᵢ, headroomᵢ) − Δω·Dᵢ = P_lost` for
`Δω`, using weights from `machine_arrays`. The cap is on the droop term only (D2). `dc_generator_outages(net)` applies the shares and reuses step
2's machinery for the flows.

- **First, read how the swing tier's loads respond to frequency and to
  voltage** (D0 Hurdle 15.1), before any assertion is written. A voltage-dependent
  load turns part of the loss into load relief. So the oracle fixture uses
  constant-power loads, or accounts for the relief explicitly. It also carries
  finite `R`, an explicit `Pmax > P0`, and no infinite bus.
- **The cross-tier oracle:** a swing-tier `TripGenerator` run, settled, gives
  the same per-machine pickup and the same `Δω`, within a band stated first.
- **Zero damping reduces to droop alone. Damping on differs by the predicted
  amount.** Both are run.
- **The cap:** a fixture where one machine's governor reaches its headroom.
  That machine settles at `headroom − Δω·D`, above `Pmax` when damped. The swing
  tier agrees, because it saturates in the derivative.
- **Refusals by name, exactly two:** nothing left responds to frequency; or
  `ΣD = 0` with every governor capped before the loss is covered. A damped case
  with a huge loss reports its large `Δω` and does **not** refuse.
- **Losing the slack's own machine:** decided here, with the bridge-to-a-lone-source
  case it is the same as in case9 (D0 Hurdle 14.2).
- **Sabotages:** drop `D` from the weights; build the weights from `Machine.R`
  on the machine's own base (the per-unit mutation); cap applied to the damping term too.

### Step 5 — Generator outages in the AC screen: a shared reference (Hurdle 15.5)

The AC solve gains a reference shared by the D2 rule. The lost power **and the
change in losses** are spread by droop-and-damping weight, and `Δω` becomes one
more unknown. `ac_powerflow` itself does not change.

- **Degeneration oracle:** with all weight on the slack, the shared-reference
  solve equals `ac_powerflow` exactly. That is the sharp check, and it needs no
  band.
- **Losses identity:** total pickup = lost power + change in losses, as an
  identity rather than a tolerance (M6 step 3's form).
- **Cross-tier, weaker:** the detailed tier's settled source trip (M7 step 7)
  against this solve, with the band and its reason stated before the gap is seen.
  The two do not hold voltage the same way (field regulators against `V_set`), so
  an exact match is not predicted, and the plan does not promise one.

### Step 6 — The report, and the bridge-to-a-lone-source decision (Hurdle 14.2)

Decide, and record in context, whether a bridge whose far side is a lone source is
screened as that source's outage. `scripts/outage_screen.jl` screens the meshed
fixture and case9 at both fidelities and prints, per outage, the two outcomes and
the reason for every disagreement. Claims are asserted in
`test/m8_outage_screen.jl`, and the prose is written **after** reading the table
(M3 step 6's rule).

Whether a window shows the screen on the editor's map is **the user's call at
this step**, not assumed.

### Step 7 — Close

Manifests deleted and re-resolved in all three environments, counts re-measured,
both step-1 captures (M5's criterion values and the AC solve) re-run and their new
digests recorded,
ledger rows, `SPEC.md` §9 item 8 annotation, README row and hurdle list, memory.

## Cut-first, in order

1. A step-6 window, if one is chosen.
2. Step 5's cross-tier comparison against the detailed tier (the degeneration
   oracle and the losses identity stay).
3. Step 3's constant-impedance re-run reduced to case9 alone.

Nothing else is cut without recording the decision in `m8-context.md` first.
