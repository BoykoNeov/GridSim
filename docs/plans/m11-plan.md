# M11 — The network optimal power flow · Plan

Companion docs: `m11-context.md` (decisions and, as steps run, what was measured),
`m11-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M10 trios.

**Read `m11-context.md` D0 first.** Hurdles 22–24 were named at step 0, after a
measurement (D1); every step below is justified against one of them. The user's
five choices are D2.

M11 has **no separate pre-study**. The physics is M6's — the DC and AC power flows,
the quadratic costs — with the network moved from *after* the optimisation (M6's
`dispatch_loss_gap`) to *inside* it. The unknowns were whether an outside checker
resolves and whether the network binds anything on the case with costs; both
measured at step 0.

## Goal

The cheapest dispatch of case9's machines **subject to the network**: in DC, every
bus balanced and every line within its rating; in AC, with losses, every bus in the
voltage band, generator voltages held at their set-points and reactive output within
limits. Each checked against PowerModels in `reference/`, on fixtures where the
network actually binds, and against checks that use no optimiser at all. The answer
is a schedule the existing power flows and simulators take as is.

## What M11 is not

See `m11-context.md` D5: no unit on/off, no multi-hour, no security constraints, no
locational prices, no free generator voltages, no losses in the DC OPF, no costs on
the mesh, no window unless chosen at step 5.

## The order, and why it is the order

M4 D7's rule, carried through M5–M10: **never let two things change at once between
a number and its check.** The DC OPF first, because it is linear-constrained with
one answer, uses the solver already in the tree, and has a closed form on a small
grid. Its outside check second, because the reference package changes and nothing
else does. The AC OPF third, on top of a fixed DC answer (its second starting point)
and with a new solver. Its outside check fourth. Then the report, then the close.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs. It is done when its named check passes with a
positive control and an executed anti-vacuity mutation**, the standing rule since
M3. Predictions and bands are written to
`docs/evidence/gridsim-m11/stepN_predictions.md` before each comparison or sabotage
runs (D8).

### Step 1 — The DC OPF (Hurdle 22)

`dc_opf(net; tol, regularization)` (name provisional): D3's formulation, HiGHS in
`GridSimDispatchExt`, a result carrying each machine's output, each bus angle, each
branch flow, the cost **recomputed from the answer** (M6's rule), the lines at their
limit, and an outcome (`:optimal`, or the infeasibility HiGHS proves).

- **Gate:** every M6–M10 capture and suite count unchanged — nothing existing
  changes; the extension only gains a method. `case9(; costed = true)` added to
  `scripts/outage_screen.jl` (D10), its rows checked against `_ed_case9`'s; the
  default path byte-identical.
- **Degeneration (22.1):** case9 as published — equal to `economic_dispatch` within
  the stated band (sized for HiGHS's regularization touching the angles, D3); no
  line at its limit.
- **A generator's own line is its cap (22.2):** L82 rated below G2's unconstrained
  output ≡ `economic_dispatch` with G2's maximum lowered to that rating (its
  schedule moved down with it, D10) — an identity, so the band is the solver's
  alone.
- **A ring line reroutes (22.3):** case9 with one ring line's rating invented below
  its unconstrained flow (chosen from step 0's table, printed as invented); the
  line sits at its limit, all three outputs move, the cost rises.
- **The closed form (22.4):** a three-bus triangle, hand-written PTDFs, one line
  binding: the `n + 2` linear system solved by backslash, against the OPF, within
  the stated band. A control with the same triangle and a rating that does not
  bind: the closed form degenerates to M6's equal-incremental-cost one.
- **Identity:** the dispatch handed to `dc_powerflow` gives the OPF's flows (a
  formulation check, once).
- **Refusals:** a model in pieces, an uncosted machine, a zero rating — by name; an
  infeasible set of limits is an outcome, not an error.
- **Sabotages:** a limit enforced in one direction only; the rating not divided by
  `S_base`; `X` where `1/X` belongs; balance on the total instead of per bus. Which
  fixture sees each is written down first (a one-direction limit is invisible on a
  line whose flow never reverses).

### Step 2 — PowerModels' DC OPF in `reference/` (Hurdle 23)

PowerModels + Ipopt added to `reference/` after re-measuring resolution **in that
environment** (D6); comments restored. The oracle's data typed from MATPOWER's file
(D7), its DC copy with `R = 0` (D2.5).

- **Band (23.3)** stated before the run, from Ipopt's and HiGHS's tolerances and
  D9's margin, on every output, cost and branch flow.
- **Input through their reader** (D7): the typed rows written as MATPOWER text,
  `parse_matpower(IOBuffer(...))`; the ±60° angle bound it adds named and asserted
  never binding.
- **Fixtures:** case9 as published (cost 5216.0266 already measured — the cost
  conversion's free check, 23.2), and every binding fixture of step 1 that exists on
  case9.
- **The formula difference, kept as a fact (23.1):** the same comparison with the
  oracle's `R` left in, its gap measured and printed, never used as a band.
- **Sabotages:** a mistyped literal on our side only (the test must catch it,
  proving the input path is independent); the oracle given our rating in MW where
  it expects per-unit.

### Step 3 — The AC OPF, voltages held (Hurdle 24)

`ac_opf(net; ...)` (name provisional): the AC power equations as constraints —
**a second hand-written copy** of what `ac_powerflow` solves, which is why 24.1 is
the step's centre — generator voltages fixed at `V_set` and reactive output bounded
(D4), the load-bus voltage band, each branch's `|S|` at its larger end within its
rating (the M10-cleanup reading, the same one the detailed tier uses), constant-
power and the default voltage-dependent loads. Ipopt in a new extension (D6),
added after the root environment's own re-measurement. Every limit pulled in by
D9's stated margin, carried on the result; the load-draw shift reported apart from
the losses (D11).

- **Handed back (24.1):** the dispatch through `ac_powerflow` reproduces the OPF's
  `|V|`, angles and flows within the stated band, on both load models.
- **The bound (24.2):** case9 at published load — M6's network-free dispatch handed
  to the flow is checked feasible first, then the OPF's cost may not exceed its
  cost, **recomputed in the test**.
- **The voltage fixture (24.3):** 1.5× load — `ac_powerflow` refuses the DC dispatch
  (positive control), the OPF's answer passes it, with B9 at the margined floor.
  The control's margin (0.8996 against 0.9) was measured on a dispatch rounded to
  0.01 MW: re-measured on the exact dispatch first, and a load between 1.5× and
  1.75× chosen instead if it stays that thin.
- **Locally infeasible (24.4):** 1.75× — reported as Ipopt's word, never as
  "infeasible"; a test pins the voltage-floor cause by the floor-lowered variant.
- **Two starts (24.5):** flat and DC-OPF starts agree within the band.
- **Sabotages:** a line's `R` dropped from the optimiser's copy only (24.1 must
  see it; PowerModels would see it too, but must not be the only one); the rating
  read at the sending end only; a held voltage left free; the load model read as
  constant power where it is not.

### Step 4 — PowerModels' AC OPF in `reference/` (Hurdle 24, its outside check)

Constant-power loads only (PowerModels has no voltage-dependent load), voltages held
by `vmin = vmax` at the machine buses, line charging zero, `R` kept (the AC physics
is the same on both sides), input through their reader (D7). Band stated before,
covering D9's margin; the ±60° angle bound asserted never binding. **Named, not hidden:** both sides
use Ipopt, so this checks the formulation, not the solver — 24.1, 24.2 and 24.5 are
the solver-independent checks, and they are already green at step 3.

- **Fixtures:** case9 at published load, the 1.5× voltage fixture, and a ring-line
  rating fixture if one binds in AC (measured, not assumed).
- **Sabotage:** a reactive limit typed wrong on our side only.

### Step 5 — The report

`scripts/network_dispatch.jl` (name provisional): case9 and its binding fixtures,
DC and AC, beside M6's network-free dispatch — cost, outputs, what binds, and what
the network adds; the optimum handed to the detailed tier's flat run as the "held
voltages feed a simulation" claim made concrete. Claims asserted in the test at the
printed precision; prose written **after** reading the table. Whether a window shows
it is the user's call at this step.

### Step 6 — Close

Manifests deleted and re-resolved in all three environments, counts re-measured,
the captures re-run before and after and compared byte for byte (a fresh `-HEAD`
capture taken first); ledger rows (the "un-oracled: network OPF" row closed or
narrowed); README row and hurdle list (22–24 closed or carried); `SPEC.md`; memory.

## Cut-first, in order

1. A step-5 window, if one is chosen.
2. Step 5's detailed-tier flat run (the handed-back power flow of 24.1 already
   shows the schedule is usable).

Steps 2 and 4 are **not** cuttable: each is its OPF's only outside check. Step 3's
24.1 is not cuttable: it is the only check that does not share the optimiser.

Nothing else is cut without recording the decision in `m11-context.md` first.
