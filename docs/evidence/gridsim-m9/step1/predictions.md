# M9 step 1 — sabotage predictions (written 2026-10-08, BEFORE any sabotage was run)

Checks the step ships (test/m9_line_resistance.jl, planned):
- C1 seeded flat run on lossy case9 + mesh, both load models (init!'s own dynamic-network
     residual at the seed, plus 50 s drift per state)
- C2 fixpoint path (powerflow = nothing) on a lossy model: builds and is flat
- C3 end-power identity at the seed: branch_power(a,b) + branch_power(b,a) == AC loss[e]
- C4 t⁺ identity: Σ2H·ω̇(t⁺) = −(P_lost + ΔL(t⁺)), constant power, lossy
- C5 settled identity: Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw, constant power, uncapped
- G  the gate: four captures bit-identical (lossless) — blind to every sabotage below
     by construction, since each touches only R ≠ 0 arithmetic (except S6).

| id | sabotage | predicted RED | predicted GREEN (blind) |
|----|----------|---------------|-------------------------|
| S1 | `R` with the wrong sign in `_branch_current!` (both networks, consistent) | C1 (init residual throws on the seeded path), C3/C4/C5 (cannot init seeded) | C2 (static and dynamic share the edge, so the fixpoint is self-consistent), G |
| S2 | `R` dropped from the receiving-end read (`_end_power` reverse = −sending end) | C3, C4 (ΔL reads as 0 — red only if ΔL ≫ residual), C5 (L_dyn reads 0) | C1, C2 (dynamics untouched), G |
| S3 | `R` read on a machine base (×S_base/S_rated of the first machine, both networks) | C1 (seeded init residual), C3–C5 | C2, G |
| S4 | `R` written into the dynamic network (`p0`) but not the static one (`sp`) | C2 (fixpoint: static solve lossless, dynamic residual check throws), C4/C5 (re-init at the trip solves a lossless static network; M7's dynamic-KCL check throws) | C1 (seeded path never solves the static network before an event), C3 |
| S5 | `R` into `sp` but not `p0` | C1 (seeded init residual), C2, C3–C5 | G |
| S6 | the `R == 0` fast path removed (general formula always) | G (bits move at R = 0) — the gate's own anti-vacuity | C1–C5 (all tolerant of rounding) |

Shared-builder finding (for step 3): the tier's edge current (`_branch_current!`,
`_series_current`) and `ac_powerflow`'s admittance (`_ac_*`, `inv(complex(R, X))`) are
written separately; nothing is shared. So no sabotage is predicted to hide from C1
because of a shared builder, and step 3's "only the outside check sees it" mutation
falls back to the plan's conductance sign.

"R dropped from one end's current only" (the plan's wording): `AntiSymmetric` gives the
far end exactly `−I`, and a series branch with no shunt carries one current, so the
dynamics cannot drop R at one end only. The one place an end can lose it is the power
READ-OUT — S2.

## Outcomes (appended after the runs, 2026-10-08)

S1, S3, S5 red/green exactly as predicted. S2 also turned the own-steady-state check
red (through its losses read) — predicted green, wrong in the safe direction. S4 red
as predicted, but the t⁺ test first caught it only through its case count (its catch
swallowed the dynamic-Kirchhoff throw); the catch was tightened and S4 re-run: red at
the right lines. S6: 86 / 169 criterion values move. S6b (added at review: the current
read-out's R = 0 path removed): 0 / 169 move — the path was unnecessary and is deleted.

## Corrected at review — the shared-builder paragraph above is WRONG

"Nothing is shared, so no sabotage hides from C1" holds only for sabotages in ONE of
the two codes. R misread the same way in both (×2 in the tier's edge AND in the AC
admittance/branch flows) is green in C1–C5: every one of them compares the tier to
the AC solve. Only an outside implementation reading Branch.R itself sees it. That
consistent two-site sabotage is step 3's mutation.
