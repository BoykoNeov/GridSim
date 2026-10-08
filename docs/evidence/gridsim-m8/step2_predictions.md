# M8 step 2 — predictions, written 2026-10-06 BEFORE the spike runs

Factor code under test: one sparse factorisation of B_r (slack row/col deleted),
one solve per outage k for phi = B_r \ (e_f - e_t), PTDF_mk = b_m (phi_i - phi_j),
margin_k = 1 - b_k (phi_f - phi_t), post_m = f_m + PTDF_mk / margin_k * f_k.

Bands (stated before any gap is seen):
- ordinary fixtures: |ours - brute| <= 100 * eps * max|f| (max over base and post flows)
- near-bridge: |ours - brute| <= 100 * eps * max|f| / margin_k

P1  Meshed 5-bus (step 0's, spur DE): bridges = {DE} exactly, = brute-force refusal
    set. Five other outages inside the ordinary band.
P2  Near-bridge (+ CE at Xw): no bridges. Inside the near-bridge band at Xw = 1e3
    and Xw = 1e5. margin_DE ~ X_DE / X_loop, so ~1e-4 and ~1e-6. NOT predicted:
    that brute force is exact there. Its B_r is ill-conditioned by the same
    factor, so its own error may grow with Xw as well; whatever is seen is
    recorded, not explained away.
P3  Sabotages on the meshed fixture, each RED:
    S1 denominator sign (1 + PTDF_kk);
    S2 transposition, implemented as f_k <-> f_m swapped in the update (with a
       symmetric inverse, transposing the PTDF index is S3 again);
    S3 outaged line's b_k in the monitored row weight;
    S4 slack row/col not deleted -> factorisation fails (red by exception);
    S5 consistent wrong reactances: 1/X^2 in BOTH B_r and the row weights.
P4  case9 (the M6 test network, ring = L45 L56 L67 L78 L89 L94):
    S3 RED  (contradicts the plan's registered "green": ring factors become
             +-X_m/X_k, and case9's ring reactances all differ);
    S5 GREEN (a ring reroutes the whole flow whatever the reactances are, as
             long as the matrix and weights agree);
    S1, S2 RED.
P5  Moving the slack (meshed fixture, A -> C) leaves every post-outage flow
    unchanged within the ordinary band.

## Written after the first spike run, BEFORE the attribution probe

P6  Attribution at the near-bridge DE outage. Exact reference with no
    ill-conditioning: drop DE and CE, move E's 40 MW load to C; CE then carries
    exactly 0.4 pu and every other line equals that network's flow. Predicted:
    BOTH ours and brute force drift from it, both growing roughly as 1/margin
    (brute force's B_r has condition ~ Xw too). Not predicted which is larger.

## Outcomes (spike run 2026-10-06; step2_spike.jl, step2_attrib.jl)

P1 held: bridges {DE}, = refusal set; worst gap 1.8e-15, 0.06 of band.
P2 held: near-bridge gap/band 0.052 / 0.036 / 0.035 at Xw = 1e3/1e5/1e7; gaps
   7.9e-13 / 2.3e-11 / 4.5e-9, i.e. 31x / 896x / 1.8e5x the ORDINARY band.
P3 S1 S2 S3 S5 red (3e13 / 8e13 / 3e13 / 3e12 of band). **S4 WRONG: green**
   (1.1e-15). CHOLMOD factorised the singular full B without complaint, and every
   output is a difference of angles while the right-hand side sums to zero, so
   the null direction cancels. An equivalent change, not a test gap.
P4 held: case9 S3 RED (2.7e13), S5 GREEN (0.14 of band), S1 S2 red, S4 green.
   case9 bridge margins: -2.2e-16, 0.0, 0.0 (one NEGATIVE: a threshold on the
   margin's size would need abs, a threshold on its sign would call it no bridge).
P5 held: slack A -> C, 2.0e-15.
P6 WRONG: brute force stays at 1.1e-16 from the exact answer at every Xw. The whole
   gap is ours. (step0's prose "brute force does not" was right; my P6 was not.)

## Sabotages in src/steadystate/screening.jl — predicted BEFORE mutate3.py runs

Testsets: [nnz] [splits] [mesh] [case9] [slack] [near].
M1 denominator sign (/ margin -> / (2 - margin)): RED mesh, case9, near. Green nnz, slack.
M2 transposed (f[k] and f[e] swapped in the update): RED mesh, case9, near. Green nnz,
   slack (both sides mutated alike).
M3 outaged b_k in the monitored weight: RED mesh, case9, near.
M4 reference row/col kept: RED nnz only (size, nnz, keep). mesh/case9/slack GREEN (spike:
   equivalent). near: NOT predicted (singular factorisation at Xw = 1e7 may throw).
M5 1/X^2 in the one b vector (matrix AND weights): RED mesh, near. GREEN case9 (identity AND
   the 0/±1 ring test) — the finding. splits: not predicted (margin > 0.1 on case9 may move).

## Sabotage outcomes (mutate3.py, mut-M*.log) — every prediction held
M1 red mesh/case9/near (36 fails); M2 red mesh/case9/near (54); M3 red mesh/case9/near (35);
M4 red nnz only (6), every flow testset green incl. near (the unpredicted one: green);
M5 red mesh (identity), near (margin, identity), splits (case9 margin > 0.1);
   case9 identity AND ring test GREEN — the finding.

## Reference (PowerNetworkMatrices LODF) — bands stated BEFORE the reference run
Their post-outage flow = our base f_m + LODF_mk * f_k (only the factor is theirs).
R1 Float32-exact fixture (X = 1/8,1/4,1/2,1/4,1/2,1/8): within ROUND-OFF, 100*eps*max|f|.
   No storage band.
R2 Ordinary fixture: within eps(Float32) * max|f| / margin_k per outage (their susceptance
   read back from a ComplexF32 matrix; error amplified by 1/margin like ours). Step 0 saw
   2e-9..4e-9, so predicted ~1/100 of the band.
R3 Anti-vacuity: reading lodf[k, m] (transposed) is outside R2's band (step 0: 0.21 pu).
R4 Bridge DE: the checker ANSWERS, and its column means "nothing else moves": every
   |lodf[m, DE]| <= 1e-6 (its own clamp scale), lodf[DE, DE] = -1 within 1e-6. Ours: split.
R5 Near-bridge Xw = 1e5: ours puts 0.4 pu on CE after losing DE (within the near band);
   the checker's answer leaves CE within 1e-3 pu of its pre-outage flow, so it is wrong by
   ~0.4 pu (step 0: 0.400).

## Reference outcomes (ref_m8_numbers.jl) — every one held
R1 F32-exact 0.031 of round-off. R2 ordinary 0.012 of the storage band (vs round-off: 1.4e5x,
the positive control). R3 transposed 7.1e5x the band. R4 bridge column <= 7.6e-17, diag -1.0
exactly. R5 ours CE 0.400000000022749; theirs 2.8e-6 (base 2.4e-6): E cut off, 0.4 pu wrong.

## After review (2026-10-06, post-922f9fd) — predictions BEFORE the re-runs
Correction to the M5 record: case9 went red under M5 at the margin line (> 0.1), so the
claim is "case9's FLOWS are blind to a consistent wrong set; its margins are not".
The > 0.1 floor is replaced by the closed form on a single ring, 1 - PTDF_kk =
X_k / sum(X_ring) (0.6808 -> 0.1351 0.2497 0.1481 0.1058 0.2365 0.1249, matching the
spike), asserted to round-off.
Q1 clean: the closed form holds within 100*eps.
Q2 M5 re-run: case9 identity and ring-factor tests GREEN; the case9 closed-form margin
   RED (1/X^2 gives X_k^2/sum X^2: 0.0986 ... 0.0604); mesh and near-bridge red as before.
Q3 inverter sabotage, `_gfl_arrays` loop dropped from bus_injections: NetworkModel's
   balance check does not read bus_injections (grep), so no throw. The inverter
   testset's rebuild identity GREEN (shared path); its "base equals the inverter-free
   mesh" line RED. Elsewhere in the M8 file: nothing else uses a grid-following inverter,
   so no other red.
