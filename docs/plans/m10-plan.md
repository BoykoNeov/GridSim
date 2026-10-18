# M10 — Double-outage screening · Plan

Companion docs: `m10-context.md` (decisions and, as steps run, what was measured),
`m10-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M9 trios.

**Read `m10-context.md` D0 first.** Hurdles 18–21 were named at step 0, after a
measurement (D1); every step below is justified against one of them. The user's
four choices are D2; the restore rule they chose is made exact in D3.

M10 has **no separate pre-study**. The physics is M8's — the DC factors, the AC
solve, the pickup rule — applied to pairs, to pieces of a split grid, and to a
restored schedule. The unknowns were how many pairs split the report grids, and
whether the dynamic tiers can run a simultaneous split; both measured at step 0.

## Goal

Screen every pair of elements — two lines, two generators, one of each — at the DC
and AC fidelities, both lost at once and one after the other with frequency
restored in between. A pair that cuts the grid is answered piece by piece: each
live piece settles at its own frequency, a piece with no source is load lost, a
piece with no load is its sources lost. Every outcome is reported, never thrown
(M8 D3), with the settled frequency of each piece judged by M9's verdict.

## What M10 is not

See `m10-context.md` D5: no filtering of pairs, nothing beyond pairs, no per-pair
dip or rate verdict, no re-dispatch beyond restoring frequency, no secondary control
in the dynamic tiers, and none of M8 D5's exclusions lifted.

## The order, and why it is the order

The ordering rule is M4 D7's, carried through M5–M9: **never let two things change
at once between a number and its check.** The DC pair factors come first, on
connected pairs only, because they have an exact oracle and touch nothing else.
Pieces come second, in DC, because the swing tier is their exact oracle and needs no
new engine work. The AC version of both comes third, on top of two fixed DC
answers. The detailed tier's simultaneous event comes fourth: it is engine work,
and it is needed only to *check* steps 2–3 at the fidelity with real loads, so it
must not be what those steps lean on. Restoring comes fifth, because Hurdle 18.4
(order does not matter without it) must be measured before a rule that makes order
matter is added. Then the report, then the close.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs. It is done when its named check passes with a
positive control and an executed anti-vacuity mutation**, the standing rule since
M3. Predictions are written to `docs/evidence/gridsim-m10/stepN_predictions.md`
before each sabotage runs.

### Step 1 — Two-line DC factors, and cut pairs from the graph (Hurdle 18.1–18.3)

`dc_line_pair_outages(net)` (name provisional): for every unordered pair of
branches, the post-outage DC flows through the rank-two update, built on M8's
single factorisation — one solve per branch, reused across every pair it is in, no
PTDF formed (M8 D4). A pair is a cut when the graph with both removed is
disconnected, decided by the graph; its flows are not computed here (step 2).

- **Gate:** every M8 output bit-identical (nothing in `dc_line_outages` changes; if
  its per-branch solve is factored out for reuse, M8's captures prove it).
- **Exactness:** rebuild-and-`dc_powerflow` on all 19 connected mesh pairs, to
  round-off.
- **The additive shortcut's error (18.2):** measured per pair on the mesh; a
  fixture with two lines whose transfers do not cross gives zero, the control.
- **Cut pairs:** the set equals the pairs whose rebuild `NetworkModel` refuses;
  case9 all 36, the mesh AB+AC and DE+BE. `det M` printed beside each, to show it
  as round-off of either sign.
- **Near-cut band:** a third path of reactance `X`; the band `~eps/|det M|` stated in
  the predictions file before the run; its scaling across two `X` is the signature.
- **Sabotages:** the off-diagonal terms of `M` transposed; `M` replaced by its
  diagonal (= the additive shortcut); the second line's factor read from the first
  line's column. Which fixture sees each is pre-registered (a transposition is
  invisible when the two lines' susceptances are equal).

### Step 2 — Pieces, and generators, in DC (Hurdles 18.4, 19.1–19.4)

Every pair kind in DC. A generator pair shares the total loss by M8's rule; a
line-and-generator pair applies the generator's pickup, then the line. A split is
answered per piece: the imbalance of each live piece shared by its own units
(`_pickup_solve` with an `alive` mask per piece), a sourceless piece reported as
load lost, a loadless piece as its sources lost; D4's collapse for two names of one
event.

- **Brute-force oracle:** each live piece built as its own `NetworkModel` with its
  units at schedule + pickup, `dc_powerflow` on it; flows and pickups match.
- **The exact dynamic oracle (19.2):** the swing tier, lossless, loads as negative
  machines, both elements out at one instant, a generator cut off alone tripped in
  that same instant (19.4), run until **each piece** settles (judged on its own
  machines — never `coi_rocof`); every machine's `ω` equals its piece's static
  `Δω` within M8 step 4's band (1e-7, stated before), and the network-side exports
  match the pickups. Fixtures: case9-shaped with its loads as machines (L45+L67:
  one piece up, one down), and one stranding a `P0 < 0` machine — which checks the
  **rest** of the grid's answer to a lost load; the stranded machine's own speed is
  excluded by name (19.3's own check is step 4).
- **Order (18.4), in the swing tier — static is true by construction:** trip A,
  settle, trip B, settle, against both at once, every pair kind, including a pair
  where the first loss caps a governor (the cap must be seen to bind). A
  no-restore sequential pair is **never** computed by rebuilding with the first
  pickups (`m10-context.md` D6.1).
- **Sabotages:** the whole grid's units share a piece's imbalance; the sign of a
  surplus flipped; a sourceless piece's load left in the balance; a `P0 < 0`
  machine classified as a source.

### Step 3 — Pairs and pieces in AC (Hurdle 19.5)

Every pair through the AC solve, classified (M8 D3). Each live piece gets its own
shared reference (M8 step 5's solve, run per piece), its own losses and reactive
limits; outcomes per piece; the DC-vs-AC comparison per pair, matched by ID (M8
step 3's rule), reporting where the two disagree and why.

- **Degenerations:** a connected line pair = `ac_powerflow` on the rebuilt model; a
  piece that is the whole grid = M8's shared solve, bit for bit or within 1e-10
  (M8 step 5's stated reason for a band).
- **Lossless, every bus at 1 pu (M8's ladder rung):** a piece's AC answer reduces
  to step 2's DC answer except for the loop-flow term M8 step 3 measured.
- **Run on both load models** (M6 step 7's rule; M8 claim c).
- **Sabotages:** one reference for the whole grid across a split; a piece's losses
  charged to the other piece; reactive limits read from the whole grid.

### Step 4 — One event, one re-solve, in the detailed tier (Hurdle 20)

An event that takes out a set of elements at once (`TripElements` or similar; the
swing tier gains it too, as two zeroed couplings), with one re-solve of the final
network. Buses with no path to a source are de-energised by the graph — loads off,
voltage out of the solve — on both load models. A refused event changes nothing, or
leaves an engine that refuses to run on; which is measured and decided here, and
`inject!(::TripLine)`'s half-applied refusal (D1) is fixed the same way.

- **Positive control (20.1):** case9 default loads, L45+L67 — refused as two events
  at step 0, run as one.
- **Dead piece (20.3):** L45+L56 on both load models — today 1.8e9 pu and 0.0 pu —
  runs, with B5 reported dead and D5's 90 MW lost.
- **Nothing half-done (20.2):** after a refused event the engine's state, parameter
  vectors, `lines_online` and log are identical to before it, or every later call
  refuses — asserted, with a mutation that skips the rollback, **on both the direct
  `inject!` and the out-of-step relay's path** (it calls the same `inject!` from a
  solver callback).
- **A generator cut off alone is tripped in the same event** (19.4), so the D9
  equivalence is carried out in the run.
- **The oracle it exists for:** on constant-power loads, the settled per-piece
  frequency of a simultaneous split against step 3's AC piece answer, through M9's
  losses identity (`m9-context.md` D0 17.4) **taken per piece** — that piece's
  `Σw`, losses and settling, never the whole grid's — one piece rising and one
  falling.
- **Gate:** M9's seven captures bit-identical — a single-element event is not
  re-routed through the new one unless that is proved to move nothing.

### Step 5 — Fail, restore, fail again (Hurdle 21)

The restored schedule (D3), per piece, exact by the bend walk at `Δω = 0`, with its
named refusal; the second loss screened on the rebuilt, restored model at both
fidelities; every ordered pair.

- **Exactness (21.1):** frequency on target in every piece; shares in proportion to
  gain, capped, re-shared; a fixture where a cap binds.
- **Refusal (21.2):** a piece whose remaining headroom is short of its imbalance;
  the settle answers it (damping) and the restore refuses it — both reported.
- **`Pmin`:** honoured when given, on the way down; a unit settling or restoring
  below zero output is flagged (`m10-context.md` D3).
- **Identity (21.3), stated not checked:** the second loss is M8's screens on the
  restored model — true by construction, so no test pretends to check it.
- **Order (21.4):** A-then-B, B-then-A and both-at-once tabulated on both report
  grids; the claim written after reading the table.
- **Dynamic check — Hurdle 21's only independent one, not cuttable:** the detailed
  tier initialised on the restored model, the second element tripped; its
  per-piece settled frequency against the screen's, M9's losses identity per piece.
- **Sabotages:** shares by damping as well as gain; the cap ignored; `Pmin`
  ignored; the restore run on the whole grid across a split.

### Step 6 — The report

`scripts/double_outage_screen.jl` (or an extension of `scripts/outage_screen.jl`):
every pair on both report grids and both load models, both timings, outcome per
piece at both fidelities, the settled frequency of each piece under M9's verdict and
the preset's printed caveat. Claims asserted in the test at the printed precision;
prose written **after** reading the table. Whether a window shows it is the user's
call at this step.

### Step 7 — Close

Manifests deleted and re-resolved in all three environments, counts re-measured,
the captures re-run before and after and their digests recorded; ledger rows;
README row and hurdle list (18–21 closed or carried, with what closed each);
`SPEC.md`; memory.

## Cut-first, in order

1. A step-6 window, if one is chosen.
2. Step 4's swing-tier half of the new event (the detailed tier's half stays: it is
   the only one that re-solves a network). Step 2's swing-tier checks trip lines
   with back-to-back `TripLine`s, which is already one event in that tier.

Step 5's dynamic check is **not** cuttable: it is Hurdle 21's only independent
check (`m10-context.md` D6.1).

Nothing else is cut without recording the decision in `m10-context.md` first.
