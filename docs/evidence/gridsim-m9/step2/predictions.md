# M9 step 2 — predictions, written BEFORE the code and before any sabotage runs

## The design, decided before writing (advisor-reviewed)

- Lossless model (every `R == 0`): the pre-M9 network, edge, parameters and fixpoint
  path, textually. Nothing new is built. The gate measures that.
- Lossy model (any `R ≠ 0`): a double-sided edge on EVERY branch, parameters
  `(K, Kc, Gs, Gd)` = `(EᵢEⱼ·X/|Z|², EᵢEⱼ·R/|Z|², E_src²·R/|Z|², E_dst²·R/|Z|²)`, the
  self terms assigned by the GRAPH edge's own src/dst. Power INTO the branch at an end
  `a` (other end `b`, `Δ = δa − δb`): `P_a = G_a − Kc·cos Δ + K·sin Δ`. One helper
  computes it for the edge and for `branch_power`.
- The slack (NOT in the plan; found at orientation): with losses, `Σ P0 = 0` has no
  steady state, so the model's reference bus absorbs them — the detailed tier's own
  rule. A static network (δ only; the reference pinned at 0, every other vertex at its
  scheduled power) is solved first, the reference's power read off the same edge, then
  the dynamic fixpoint. A grid-forming inverter on the reference bus is refused on a
  lossy model (no rule for its setpoint).
- Headroom stays `(Pmax − P0)/S_base` — the detailed tier's rule (it is a cap on the
  DEVIATION `ΔPm`, so it cannot go negative when the slack picks up losses).
- Reachability on a lossy model: `Σ(Eᵢ²g − EᵢEⱼ|y|) ≤ Pᵢ ≤ Σ(Eᵢ²g + EᵢEⱼ|y|)`, every
  non-reference vertex; the reference is the static solve's to refuse.

## Checks

- (A) flat run on lossy fixtures, per state, two tolerances
- (B) dispatch: non-reference `Pm == P0/S_base` exactly; `Σ Pm` = losses read at both ends
- (C) each end of each branch against an INDEPENDENT complex formula
  `Re(V_a · conj((V_a − V_b)/(R + jX)))`, `V = E·e^{jδ}`, on a fixture whose branch is
  written against the graph's order and whose E′ differ
- (D) a tripped line and a tripped generator's branches carry exactly 0.0 at both ends
- (E) cross-tier: the detailed tier at the frozen-flux degeneration, reduced, lossy;
  dispatch asserted equal FIRST, then four channels inside `convergence_band` at two
  tolerances
- (F) swing − DC settled speed, uncapped outages: `(L_pre − L_post − 1[ref lost]·L_pre)/Σw`,
  including one outage of the reference machine
- (G) the lossy reachability guard refuses an absorber the lossless bound would pass
- gate: five captures byte-identical at R = 0

## Sabotages and predicted outcome (red = at least one assertion fails)

| | Sabotage | Predicted RED | Predicted GREEN |
|---|---|---|---|
| S1 | self term `G_a` dropped in the shared helper | B? no — B reads the same helper, so Σ Pm = losses holds (both wrong together); **C red** (independent formula), **E red** (dispatch differs from the detailed tier) | A (self-consistent), D, F (identity reads losses from the same helper — consistent) |
| S2 | conductance with the wrong sign (`g = −R/|Z|²`, all three coefficients) | **C red**, **E red**; F probably green (consistent) | A, B, D |
| S3 | `cos`/`sin` swapped on the conductance term (`Kc·sin Δ`) | **C red**, **E red** | A, B, D, F |
| S4 | a trip zeroes only `K` | **D red**; F red too (survivors still coupled to the dead bus through `Gs/Kc`, so post-trip export at the tripped bus ≠ 0 — the identity's `Σ Pe = L_post` breaks) | A, B, C, E (no trip in them) |
| S5 | `Gs`/`Gd` assigned by the BRANCH's orientation instead of the graph edge's | **C red** (fixture written against graph order, E′ unequal), E red only if the E fixture is reversed too (it will be) | A, B, D, F |
| S6 | the lossless path removed (lossy edge on every model) | **the gate**: swing capture moves (`EᵢEⱼ·X/X²` ≠ `EᵢEⱼ/X` in the last bit on some X) | every check with a tolerance |
| S7 | the slack solve also run on lossless models | **the gate** (reference `Pm` = P0 + roundoff) — predicted to move; if it does not, the skip is not needed and is said so | every check with a tolerance |

Expectation stated plainly: the internal checks that read losses from our own code
(B, F) are blind to S1–S3 by construction. C and E are the ones that see the edge
equation; that is why both exist.

## Amendment before running (still before any sabotage ran)

- S7 cannot be run on its own: the static slack solve reads the lossy edge's `Kc/Gs/Gd`
  parameters, which a lossless model does not have. S6 is therefore "the lossless path
  removed entirely" (lossy edge AND slack solve on every model); predicted: swing and
  criterion captures move in last digits; every tolerance check green.
- Found by the gate run, not predicted: `branch_power_series(eng, :B2, :B1)` on a
  lossless model returned the (:B1, :B2) series — the caller's order was ignored. Fixed;
  the swing capture differs from HEAD in exactly that line, by an exact negation.
- The flat-run check was first written at 1e-10 per state and failed: the lossless twin
  drifts as much (explicit RK, absolute angles). Rewritten as residual-at-start
  < 1e-13 plus drift falling with tolerance; for the sabotages this means the flat run
  sees NOTHING that keeps the static and dynamic solves consistent (all of S1–S5).
