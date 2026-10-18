# M10 step 3 — predictions, written before any of it ran

Step 3 screens every pair in AC, a split grid piece by piece (Hurdle 19.5). Everything
below was written before the code, the runs or the sabotages. What came out is in
`m10-context.md`, "What step 3 measured".

## The design these predictions are about

- **One Newton solve per live piece**, each with its own settled-frequency unknown, its
  own angle reference (the model's slack where it lies in the piece, else the piece's
  first bus, as step 2 does) and its own reactive limits. Dead pieces never enter a
  solve. The pieces share no branch, so solving them together would be the same
  equations, but one piece failing would then fail the other, and the outcome is per
  piece.
- **M8's shared solve is generalised in place, not copied** (`m10-context.md` D9): its
  setup takes a set of lost machines, the piece's vertices and the pair's branches.
  M8's single-machine call is the whole grid, nothing out, one lost — the same arrays
  and the same operations. The gate is the six M9 captures, byte for byte, which
  include every M8 AC screen output on both report grids and both load models.
- **A pair of lines that leaves the grid whole is `ac_powerflow` on the rebuilt model**
  (M8's line semantics: the slack takes the change in losses; `Δω` is `NaN`, as in
  `OutageScreen`'s line rows). So "connected line pair = `ac_powerflow`" holds **by
  construction** and is stated, not tested as evidence. Every other live piece — every
  piece of a split, and the whole grid when a machine is lost — goes through the shared
  solve.
- A piece's kind (live, sources lost, load lost, empty) is a fact of the graph and the
  equipment list, read by the same code as step 2. What a dead piece takes with it is
  read from the **AC base**: a slack machine cut off loses its solved output, base
  losses included (M8 D8.1).
- The AC base is refused exactly as M8's AC generator screen refuses it (a slack bus
  with more than one source; a base slack outside its reactive limits), by the same
  check code.
- Branch flows are rated **only on in-service branches inside live pieces**; the pair's
  own branches and every dead piece's branches are never handed a flow (an open line's
  two ends have independent angle references, so a "flow" there is meaningless and
  would be a spurious overload).

## Bands, stated now

- **B = 1e-10, solution against solution** (M8 step 5's `B1`), on Δω, every pickup,
  every |V| by bus id and every branch flow by branch id — never on angles (the
  reference differs between the compared solves; it is a gauge).
- **Per-piece losses identity**, read from the base and post solutions and the model,
  never from the screen's setup:

      Σ pickups in c = lost base output in c + Δ load draw in c
                       + Δ losses on c's internal branches − base export from c across the cut

  with the base export read at **c's own end** of each cut branch (`flow` at its
  `from` end, `flow_rev` at its `to` end — on a lossy line they differ by its loss),
  and the base internal losses including any of the pair's branches lying inside c.
  Bound `n_c · (res_base + res_piece)`, M8's bound restricted to the piece.

## The checks, and what each predicts

1. **Gate.** All six captures byte-identical after the refactor.
2. **A pair that is one outage (D4)** — case9 L14+G1, L82+G2, L36+G3 against M8's single
   AC outage of that machine: within B on both load models. Not bit for bit: the pair's
   solve has no cut-off bus, M8's keeps it as an empty dead-end bus. M8's solution
   carries a flow on the bridge of at most B (no current to an empty bus). Predicted to
   hold.
3. **Four paths to "G1 and G2 gone"** (L14+L82, L14+G2, L82+G1, G1+G2) — the split path
   against the whole-grid path — within B, both load models. Predicted to hold.
4. **The mesh's AB+AC is NOT G1's outage in AC, even in frequency** — unlike step 2's DC
   (where only the flows differed). With only G1 lost, A stays in the mesh and carries
   the loop flow; in AC that loop flow has losses (R = X/10), which the survivors pick
   up. Predicted: Δω differs by more than 1e3·B, the G1-only case lower (more to pick
   up). Order of magnitude not predicted (it depends on how many governors are capped).
5. **The losses identity** on every live piece that solved, every pair, both report
   grids, both load models. Predicted to hold; on the default loads the load term is
   predicted to move (|Δ load draw| > 1e-3 somewhere), and on these lossy grids the loss
   term too.
6. **Lossless rung** (R = 0, constant-power loads; published V_set). Δω and every pickup,
   per piece, AC against step 2's DC within B, every pair of both grids — the real-power
   balance is the same equations. Flows: on case9 every split pair that removes a RING
   line leaves trees, and a tree's flows are fixed by its injections, so AC flows should
   equal DC flows within B there **only when every bus is at 1 pu**; at the published
   V_set they will not (`P = V_i V_j sin θ / X`). So the flow half runs on M8's A0 rung
   (every bus held at 1 pu by zero-power helper machines with no droop, no damping),
   where tree pieces agree within B and meshed pieces carry a loop flow above B. On A0
   the helpers turn case9's three load-lost pairs into live pieces with nothing that
   responds: `:no_response` at both fidelities (predicted, and the kinds must agree).
7. **DC against AC per pair, by ID** — classes counted and tabulated, not predicted. One
   sharp prediction: each collapsed pair's class equals M8's generator comparison class
   for its machine.

## Sabotages, and where each should go red

| # | Sabotage | Red | Green (and why) |
|---|---|---|---|
| S1 | the slack machine's base output taken as its SCHEDULE (the base losses it carried dropped) | the identity on every piece that holds the slack's machine alive, on both lossy grids and both load models; check 2 for L82+G2 and L36+G3 | the four paths (G1 is gone in all four); the lossless rung (base losses zero); every piece without the slack |
| S2 | only the FIRST lost machine left out of the schedule | the identity on every two-machine pair; check 3 (G1+G2 now keeps G2); the lossless rung's machine pairs | every pair with at most one machine lost per piece |
| S3 | the pair's branches left in the admittance before it is cut to the piece (a cut line's diagonal stays at its surviving end, an admittance to ground) | every split pair (most probably fail to solve or leave the band, which turns the counts of solved pieces and the identity red); check 2; check 3; whole-grid line+machine pairs (the line is still there) | the whole-grid two-line pairs (they go through `ac_powerflow`, not the shared solve); pure machine pairs |
| S4 | each piece's pickup vector written whole, so a later piece overwrites an earlier one's with zeros | the identity on the FIRST live piece of every split with two live pieces that both solved (case9's 9 two-live pairs); the lossless rung's pickups there | every pair with one live piece — all whole-grid pairs, the collapsed pairs, the four paths, the mesh |

**Not expressible in this design, recorded rather than faked:**

- "One reference for the whole grid across a split": each piece is its own problem with
  its own reference; a piece with no reference has no problem to pose (its Jacobian is
  singular). There is no shared reference to get wrong.
- "Reactive limits read from the whole grid": the limits are per bus, and a lost
  machine's limits could only leak onto a bus that keeps another source. Neither
  report grid has a bus with two sources, so a mutation there is invisible on them by
  construction.

## Added 2026-10-18, after the first green run and BEFORE any sabotage ran

The table above is left as written. One row is wrong for a reason visible in the design,
caught while writing the sabotage runner:

- **S1 cannot turn check 2 red.** The single-machine screen is not a separate copy (D9):
  `ac_generator_outages` runs the same `_ac_piece_setup`, so S1 moves M8's answer for G2
  and G3 exactly as it moves the pair's, and the two still agree. Check 2 should stay
  GREEN under S1. Only checks that read the base solution and the model directly (the
  losses identity) can see it. S1 also changes M8's own screen, which M8's identity test
  would catch in the full suite; the focused runner does not load it.
- S3 is unaffected by that: M8's single-machine path removes no branch, so the extra
  admittance appears only on the pair's side, and check 2 should still go red under S3.

Two first-run results, recorded here only because they change what the checks can see
(the full account is in `m10-context.md`):

- **Check 3 has no solved answer to compare**: on constant-power loads every path to "G1
  and G2 gone" fails to solve, and on the default loads every path is `:voltage`. The
  test now compares outcome, Δω, pickups and the out-of-band voltages, which all four
  carry. So S2 should still turn check 3 red, provided G1+G2 under S2 (G2's power kept)
  gives a different outcome or Δω from the three paths that lose no second machine in
  the piece.
- **Check 4's sign was wrong**, and the reason too (see `m10-context.md`). The assertion
  is now the measured sign per load model. None of the sabotages is predicted to move it.

## Added 2026-10-19, after the inverter testset was added and BEFORE S5 ran

The inverter testset (step 2's two triangles) was added after S1-S4 ran, so it has no
sabotage of its own. S5 is aimed at the code only it reaches:

| # | Sabotage | Red | Green (and why) |
|---|---|---|---|
| S5 | a grid-forming inverter's bus kept as its MODEL vertex instead of its position in the piece (`inv_bus = ia.bus[js]`) | the inverter testset, on the grid-forming triangle's pieces that do not start at vertex 1 (AB+CA leaves {B, C}, AB+BC leaves {A, C}): the inverter is looked for at a position the piece does not have, so either its reactive capability is never found (C pinned at zero reactive output) or the rating check indexes past the piece and throws | every other testset in the focused run (the report grids carry no inverter), and every whole-grid piece (there the two numberings are the same, so M8's path is untouched by construction) |

M7's surface walk would also go red (its two-bus inverter model leaves {B2} alone, position 1,
vertex 2), but the focused runner does not load it.
