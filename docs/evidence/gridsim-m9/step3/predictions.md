# M9 step 3 — sabotage predictions, written before any of them ran (2026-10-09)

The outside check: PowerDynamics' `PiLine`, handed `R` by `build_oracle` reading
`Branch.R` itself, at the swing tier (`Library.Swing`, our equation line for line) and
at the detailed tier (`SauerPaiMachine` at the `X″ = X′` degeneration), on the
three-machine ring with `R = 0.3·X` on every branch. Every sabotage goes in the
ARITHMETIC that reads `R`, never in `Branch` / `branch_topology` / `branch_arrays`:
the oracle reads that data path too, so a sabotage there is invisible to everyone
(the reference README's standing rule).

Sites that read `R` in arithmetic (grepped at `037c935`):

- detailed tier: `_branch_current!` (the edge, `p[3]`), `_series_current` (every
  read-out of the current);
- AC power flow: the admittance (`ac_powerflow.jl:99`) and the branch flows
  (`ac_powerflow.jl:818`);
- swing tier: `_lossy_coeffs` (via `br.R` at `swing.jl:1204`) and `_lossy_reach`
  (`bt.R` at `swing.jl:872`).

## T1 — `R` ×2 in the detailed tier AND the AC power flow, consistently (D5's mutation)

- core, M9 step-1 testsets: **green** — every one compares the tier with the AC solve
  or with itself, and both are equally wrong (D5's argument).
- core, M9 step-2 cross-tier testset (detailed at frozen flux against the swing tier,
  lossy pair): **red** — the swing tier still reads `R` once, so the two references'
  dispatch differs by the extra losses and the `1e-12` dispatch check fails first.
- core elsewhere: **red** wherever a lossy AC number is pinned (M6 steady-state, M8
  screening claims at printed precision).
- reference, new detailed-tier flat run (lossy ring): **red** — our fixpoint is for
  `2R`, theirs is for `R`, so their bus voltages leave it.
- reference, new swing-tier checks: **green** (untouched tier).
- reference, M6 oracle B (PowerFlows) lossy case: **red**.

So T1 is NOT seen by the outside check alone: step 2 already put a second, separately
written reader of `R` (the swing tier) beside the detailed one.

## T2 — `R` ×2 in the swing tier only (`_lossy_coeffs` and `_lossy_reach`)

- core, M9 step-2: independent end formula **red** (it reads `b.R` itself); the
  cross-tier testset **red**; the dispatch identity and swing-against-DC **green**
  (each reads losses through the engine's own `_end_power`).
- reference, new swing-tier flat run and transient: **red**.
- everything detailed / AC: **green**.

## T3 — `R` ×2 everywhere arithmetic reads it (T1 + T2)

- core, M9 step 1: **green**. Step-2 cross-tier: **green** (both tiers equally wrong).
  Step-2 independent end formula: **red** — it is written in the test from `b.R`, and
  no sabotage in `src/` can reach it.
- reference, both new checks: **red**. M6 oracle B lossy case: **red**.

**Prediction for the plan's sentence "the sabotage only this check can see":** there is
none among `src/` sabotages of `R` — each of T1–T3 is red in at least one in-house
check, because step 2 added two readers of `R` that do not share the detailed tier's
arithmetic (the swing tier, and a test-side formula). What only `PiLine` sees is the
class those in-house readers share by construction: an error in OUR understanding
written identically into the engine and into the test's own formula (e.g. which end
carries the self term, or the sign of the conductance term, written the same wrong way
in both). That is the step-2 sabotage S2 (conductance sign) applied to the swing tier
AND to the test formula — not a `src/`-only mutation, so it is run as a stated
two-site mutation, T4.

## T4 — the conductance sign wrong in the swing tier AND in the step-2 test formula

- core, M9 step 2: every check **green** (the independent formula now agrees with the
  equally wrong engine; dispatch and swing-against-DC read the engine's own ends — step
  2's S2 was green on those already). The cross-tier check: **red** — the detailed
  tier's `(Vf − Vt)/(R + jX)` has the right sign. So T4 is caught in-house too, by
  the detailed tier. Predicted outcome: green only where both tiers are not compared.
- reference, new swing-tier flat run: **red**.

## The in-test controls (not mutations of `src/`)

- C1 — R reaches PowerDynamics: our lossy run against an oracle built from the
  `R = 0` twin is red, on both tiers' flat runs.
- C2 — the dispatch reaches PowerDynamics: a swing-tier oracle seeded with the
  SCHEDULE (`Machine.P0`) instead of our reference's loss-carrying `Pm` is not flat.

## Added after T1–T4 ran, prediction still written before it ran: T5

T1–T4 each went red somewhere in-house (outcomes below). T5 is the case the outside
check exists for: the SAME misreading in every one of our readers — the detailed tier,
the AC power flow, the swing tier AND the test's own end formula — at ×1.1 (T1b showed
×2 pushes the report grids past having a steady state, which reds checks by refusal).

- core M9: the cross-tier and end-formula checks **green** (everything agrees with
  everything); every identity **green**; the `t⁺` testset **red by refusal** only (T1b's
  stalled re-initialisation after a trip, which T5 also contains).
- reference step 3: **red** on both tiers' flat runs.

## Outcomes (appended after the runs)

- T1: as predicted except the step-1 identities, which went red — **by refusal**
  (`R` ×2 leaves report-grid outages with no steady state), not by the identity.
- T1b (×1.1, added to separate the two): settled identity green; `t⁺` errors only on
  case9 G1, refused at HEAD by the voltage band and now a stalled solve.
- T2, T3: as predicted.
- T4: **wrong** — four in-house checks that the losses are positive see the sign
  error. Red in-house, so not "only PiLine".
- T5: as predicted — no in-house identity, comparison or formula sees it; the one
  in-house red is case9 G1's stalled re-initialisation (refused at HEAD anyway).
  PowerDynamics sees it on both tiers.

Full table: `docs/plans/m9-context.md` D7.
