# M8 step 3 — predictions, written 2026-10-06 BEFORE the spike runs

## Design decisions taken before any run (go to m8-context.md as D6)

- `ac_line_outages(net) -> ACLineOutages`. Base: `ac_powerflow(net)` must return,
  else the whole screen refuses (D3). Bridges from `_bridge_mask` (the graph),
  never by catching the constructor's "not connected". Each non-bridge outage is
  `_ac_powerflow_outcome` on the model rebuilt without that branch.
- `compare_line_screens(net, dc, ac)`: takes `net`, departing from the plan's
  `(dc, ac)`, because `DCLineOutages` carries no ratings. DC overload = the SAME
  `_rating_violations(net, abs.(flow))`. Branch ids of both screens must equal
  the model's, else refused.
- The DC base is JUDGED, not refused: its overloads are reported as their own
  row. Refusing would hide exactly a disagreement (DC calls an overload AC does
  not), and the AC base is already guaranteed secure.
- AC outage solutions have one branch fewer: mapped BY ID, never by position.
- Miss split, one end convention: S = max(|S_from|, |S_to|) (the rating's
  quantity), P_ac = max(|P_from|, |P_to|), P_dc = |f_dc|.
  reactive = S − P_ac ≥ 0 by algebra (each end |S| ≥ |P|, max preserves it): stated.
  real = P_ac − P_dc: measured, sign not predicted.

## The ladder (one change per rung)

  A0  R = 0; every bus WITHOUT a source gets a zero-P helper machine at V_set = 1
      (unlimited Q); every machine V_set = 1; constant-power loads.
  A1  + branch R (case9 published; mesh: INVENTED R = X/5, declared)
  A2  − the helper machines (V_set still 1 everywhere a machine sits)
  A3  + published V_set (case9 1.04/1.025/1.025; mesh INVENTED 1.05/1.04)
  A4  + default constant-impedance loads
  Every rung: `isempty(sol.limited)` asserted, so case9's ±3 pu limits are inert.

## Predictions

Q1  A0: every |V| is exactly 1.0 (no bus solves a magnitude), limited empty.
Q2  A0: injections identical to DC (lossless, |V| = 1, constant P), so
    d = P_ac(from) − f_dc has ZERO divergence at every bus (≤ ~1e-12, Newton
    abstol 1e-12 × a few). The A0 miss is a pure loop flow.
Q3  A0 case9 ring outages: what remains is a tree, so a loop flow is zero:
    real miss ≤ ~1e-11 on every branch. case9 INTACT (a ring) at A0: nonzero,
    > 1e-6 pu. Mesh connected outages at A0: nonzero (> 1e-6), cycle rank 1 left.
Q4  A0 magnitude: sin δ ≈ δ − δ³/6; angles ~0.1–0.3 rad; predicted max |real
    miss| on the mesh 1e-4 … 1e-2 pu. Sign NOT predicted.
Q5  A1: the divergence identity breaks (losses), by about the total loss at the
    slack; nothing else predicted.
Q6  A2: load and junction buses sag below 1; reactive part grows vs A1.
Q7  A3 on case9 = `_ed_case9()` exactly (same model, `==` on the outcome solve).
Q8  case9 315 MW comparison: L45, L94 → DC :secure, AC :voltage → class
    :dc_blind; L56 L67 L78 L89 → :agree (both secure); bridges → :splits.
Q9  case9 400 MW: DC overload on exactly one outage (100.7 %, step 0), AC on that
    outage is :voltage or :no_solution → :dc_blind as well.
Q10 S_base 100 vs 250 on case9 (and on the ladder's A3): identical outcome
    vectors; MW/MVA agree to rtol 1e-10.
Q11 Positive control (to be FOUND by measurement, not assumed): a mesh rating
    set where the base is secure at both fidelities, one outage overloads at
    both, and one outage is secure at both.

## Outcomes (spike 2026-10-06; step3_spike.jl/.log, step3_pc*.jl/.log)

Q1 held (A0: every Vm 1.000000, limited empty, both fixtures).
Q2 held: A0 divergence ≤ 2.5e-14 on every outage, both fixtures.
Q3 held: case9 A0 ring outages max|real| 4.4e-16 … 2.4e-14; case9 INTACT 5.0e-5;
   mesh connected outages 2.4e-5 … 3.4e-3.
Q4 held loosely (mesh max 3.4e-3; one outage, AC, at 2.4e-5, under the 1e-4 floor).
Q5 held: A1 divergence 3.7e-2 … 9.1e-2 case9.
Q6 WRONG FORM, ladder REORDERED before any test: with helpers off and every
   V_set = 1, the MESH BASE sags out of band (D 0.847 at R = X/5, 0.877 at
   R = X/10) so the rung cannot be screened at all. New order, still one change
   per rung: A2 = + published V_set (helpers still on), A3 = − helpers. Mesh
   invented R moved X/5 → X/10 (A3 mesh base then 0.914 at D).
Q7 held: A3 is the published model.
Q8 held exactly. Q9 held: L89 at 400 MW, DC 100.7 % on L56, AC :voltage B9 0.854.
Q10 held (outcomes identical, 100 vs 250).
Q11 FOUND: case9 315 MW with L94 rated 100 MVA. Base L94 61.3 MW / 77.5 MVA;
   L89 out 125.0 / 144.6 and L67 out 109.8 / 121.1 (both fidelities over);
   L56 and L78 out secure at both. L94's DC flow is NEGATIVE in model
   orientation, so an `abs` dropped from the DC judgement is visible.
   "DC fine, AC over": L14 rated 140 → base 96.0/127.5, L89 out 96.0/159.7.
   "DC over, AC fine": on DEFAULT loads only (voltage sag lowers the draw):
   case9 zip 315 has DC − AC MVA up to +12.7 MW (L45 out). Not on constant P.

## Sabotages — predicted BEFORE mutate4.py runs (2026-10-06)

Testsets (start line in test/m8_screening.jl): ident 486, refuse 516, demo 528,
pos 555, missed 576, false 599, ladder 620, sbase 668, gfslack 684, inv 704.

T1 miss read BY POSITION (j = e if e <= length(sol.branches)): red false (L94 is
   index 9 > 8 → reads 0, `real < 0` fails) and ladder (case9 A0 tree check: a
   branch after k reads its neighbour's flow). GREEN missed (L14 is index 1, before
   the outaged L89, so position = id there — this test cannot see T1 alone).
T2 abs dropped from the DC judgement: red pos (L94 flow negative), false (same),
   demo (400 MW L56 negative after L89). Green sbase (both bases equally wrong).
T3 DC judgement inlined with a hard-coded 100 in place of S_base: red ONLY sbase.
T4 :voltage not classed :dc_blind: red demo, pos (class[2]), missed, false
   (class vectors with a voltage row).
T5 a :secure outage stores the BASE solution: red ident, ladder (tree check sees
   the ring's base flows), inv? (b.solution[3] is L56 secure → red).
T6 the base not refused (base from the outcome solve's solution): red ONLY refuse.
T7 :dc_missed and :dc_false_alarm labels swapped: red missed, false.
T8 inverter-slack overload not :dc_blind: red ONLY gfslack.

## Review follow-up sabotages — predicted BEFORE running (2026-10-06)
T1 again: now ALSO red in the :dc_missed testset (the L94-by-id line).
T9 dc_base_over always empty: red ONLY in "the two rarer verdicts" (base line).
T10 :mixed collapsed into :dc_missed: red ONLY in "the two rarer verdicts" (class line).
