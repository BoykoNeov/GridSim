# M10 step 1 — predictions, written 2026-10-18 BEFORE any pair code runs

Code under test (to be written): `dc_line_pair_outages(net)`. One sparse Cholesky
factorisation of B_r (as M8 step 2), one solve per branch `k` for
`phi_k = B_r \ (e_from − e_to)`, of which only the branch-to-branch column
`P[:, k] = b .* (phi_k[src] − phi_k[dst])` is kept (branches × branches; the
bus-indexed PTDF is never held). For the unordered pair `(k, l)`:

    M = [1 − P[k,k]   −P[k,l];  −P[l,k]   1 − P[l,l]]        (NOT symmetric in general)
    x = M⁻¹ [f_k; f_l]                                     (Cramer, with det M stored)
    post_e = f_e + P[e,k]·x_k + P[e,l]·x_l,   post_k = post_l = 0.0 exactly

A pair is a cut when the graph with both branches removed is disconnected (Graphs),
never from `det M`. `det M` is stored for every pair, cuts included.

M8's `dc_line_outages` is NOT edited (the pair code has its own copy of the
per-branch solve), so M8's gate holds by construction; a test ties the copy to
M8's numbers instead (P0).

Fixtures: the REPORT mesh (`scripts/outage_screen.jl` `mesh()`, seven branches
AB AC BC BD CD DE BE, X = .10 .20 .15 .25 .30 .10 .20); case9 (`_ed_case9`).

## Bands, stated before any gap is seen

- ordinary pair: `|ours − rebuild| ≤ 100·eps·scale`, scale = max |f| over the base
  and the rebuilt flows (M8 step 2's band, unchanged).
- near-cut pair: `≤ 100·eps·scale / |det M|`.
- the shortcut on a non-crossing pair: `|shortcut − ours| ≤ 100·eps·scale`.

## Predictions

P0  The copy of the per-branch solve IS M8's: `1 − P[k,k] === dc_line_outages(net).margin[k]`
    and `f + P[:,k]/margin_k·f_k` reproduces `dc_line_outages(net).flow[k]` with `===`,
    on the mesh and case9 (same operations in the same order).
P1  Cut set = rebuild refusals: case9 all 36 pairs; mesh exactly {AB+AC, DE+BE}.
P2  Mesh, 19 connected pairs: every one inside the ordinary band.
P3  det M at every cut pair is round-off: |det M| ≤ 10·eps, NOT all of one sign
    across case9's 36 + the mesh's 2 (printed; the sign is not asserted, it is
    platform round-off).
P4  The additive shortcut `f + LODF_k·f_k + LODF_l·f_l` (from M8's single-outage
    flows) is outside the ordinary band on most of the mesh's 19 pairs; NOT
    predicted how large or on which.
P5  Non-crossing control — two triangles sharing one bus (A–B–C and C–D–E):
    every within-triangle pair is a cut (6 of 15); the 9 cross pairs are connected,
    `|P[k,l]|, |P[l,k]| ≤ 10·eps`, and the shortcut equals ours inside the ordinary
    band. Ours equals rebuild inside the ordinary band.
P6  Near-cut: the mesh plus a weak branch A–D of reactance Xw ∈ {1e3, 1e5, 1e7}.
    AB+AC is then connected; each line's own margin `1 − P[k,k]` stays O(0.1) (the
    other line is a path round it), but `|det M| ~ 0.1/Xw` (1e-4, 1e-6, 1e-8).
    Exact reference with no ill-conditioning: A then hangs off A–D alone, which
    carries A's whole injection (G1's 1.5 pu); the rest is the four-bus grid with
    that injection moved to D. Predicted: ours inside the near-cut band at every
    Xw; the gap grows with Xw (gap at 1e7 ≥ 100 × gap at 1e3) and at 1e7 is outside
    the ORDINARY band. NOT predicted whether the rebuild drifts (M8 step 2 found it
    did not; recorded either way).

## Sabotages (in the pair code only; predicted RED / GREEN per testset)

Testsets: [tie] (P0), [cuts] (P1/P3), [mesh] (P2), [shortcut] (P4: "the shortcut is
measurably wrong on the mesh"), [bowtie] (P5), [near] (P6), [inverter].

S1  M's off-diagonals transposed (−P[l,k] at (1,2), −P[k,l] at (2,1)).
    [mesh] RED — but INVISIBLE on AB+DE and AC+BE (equal reactances ⇒ P[k,l] = P[l,k]);
    [near] RED (AB 0.10 ≠ AC 0.20); [bowtie] GREEN (both off-diagonals zero);
    [shortcut] GREEN; [tie] [cuts] GREEN.
S2  M replaced by its diagonal (= the additive shortcut).
    [mesh] RED; [shortcut] RED (ours now IS the shortcut); [near] RED;
    [bowtie] GREEN (the shortcut is exact there — by design, so the mesh must catch it);
    [tie] [cuts] GREEN.
S3  The second line's factor read from the first line's column (P[e,k] used for l).
    [mesh] RED; [bowtie] RED; [near] RED; [tie] [cuts] GREEN.
S4  (added beyond the plan) A pair called a cut only when one of its lines is a bridge.
    [cuts] RED on case9 (its 15 ring–ring pairs missed) AND on the mesh (no bridges,
    so both cut pairs missed). Flows then computed by dividing by a round-off det M.

## Changed after the first run, before the tests were written

- The case9 fixture is the report script's `case9()` (`scripts/outage_screen.jl`) — the
  grid step 0's census counted — not `_ed_case9` as written above. Same branch data
  (`test/m8_outage_screen.jl` asserts the two copies agree), and the DC screen reads
  nothing else, so no prediction moves. Chosen so the M10 tests depend on the report
  script alone.

## Outcomes (2026-10-18; `step1_pairs.jl`, the tests in `test/m10_double_outages.jl`)

P0 held: margins `===`, single-outage flows `===`, on both grids.
P1 held: case9 36 of 36 cut, mesh exactly {AB+AC, DE+BE}; every cut a rebuild refusal
   and every refusal a cut.
P2 held: worst 0.119 of the band (AB+BC); the 19 range 0.005–0.119.
P3 held: |det M| ≤ 2.6e-16 (1.2·eps) at every cut; case9 shows negative, −0.0, 0.0 and
   positive values. Two bridges (L14+L36 etc.) give an exact zero; a ring pair never does.
P4 held, stronger than predicted: the shortcut is outside the band on ALL 19 mesh pairs,
   9.8e11 to 2.5e13 times it.
P5 held: 6 cuts, 9 cross pairs; |P[k,l]|, |P[l,k]| ≤ 10·eps; shortcut = ours in band.
P6 held in every predicted part; det M = 4.86e-5 / 4.86e-7 / 4.86e-9 (predicted ~1e-4 at
   1e3 — the order, not the constant); margins 0.243, 0.486; gap 2.8e-12 / 3.6e-10 /
   3.3e-8, 0.004–0.005 of the near-cut band, 9.8e5 × the ordinary band at 1e7.
   **NOT predicted, and the reverse of M8 step 2: the rebuild DRIFTS** — 1.2e-11 / 1.0e-9 /
   1.2e-7 from the exact answer, four times the factors' own error. Probe
   (`W:\temp\claude\m10s1\gauge.jl`, not kept): with the reference moved from A to C the
   rebuild is exact (≤ 2.3e-16) while ours barely moves (2.1e-12 / 1.2e-10 / 1.6e-8). The
   cause is the gauge: with the reference on the nearly cut-off bus every other angle is
   ~1.5·Xw rad, and each flow is a difference of two such numbers. M8's near-bridge had
   its reference on the main grid. So the near-cut oracle is the closed form, and the
   test asserts both halves of the attribution.

Sabotages (`W:\temp\claude\m10s1\mutate.py`), testsets red:
S1 transposed  — [mesh] [near] (+ [inverter], the mesh again); [bowtie] [shortcut] [tie]
                 [cuts] green. As predicted.
S2 diagonal    — [mesh] [shortcut] [near] [inverter] AND [cuts], which was predicted
                 green: with M diagonal, det M at a cut is (1−P_kk)(1−P_ll), no longer
                 round-off, and the "det M at a cut is round-off" check sees it.
                 [bowtie] green, by design.
S3 wrong column — [mesh] [bowtie] [near] [inverter]; [tie] [cuts] green. As predicted.
S4 bridge-only cut — [cuts] (7 failures) and, downstream, [mesh] [shortcut] [bowtie]
                 [inverter] (cut pairs given flows or flows missing); [near] green (its
                 one tested pair is connected either way).
