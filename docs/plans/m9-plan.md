# M9 — A frequency criterion for the outage screen · Plan

Companion docs: `m9-context.md` (decisions and, as steps run, what was measured),
`m9-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M8 trios.

**Read `m9-context.md` D0 first.** Hurdle 16 was named at M8's close and Hurdle 17
at M9's step 0, after a measurement (D1); every step below is justified against one
of them. The user's five choices are D2; the sourced limits are D3.

M9 has **no separate pre-study**. The physics is the swing equation, the classical
coupling with conductance, and a running minimum; the unknowns were how deep the
dip runs against the settled value, whether the dynamic tiers can run the report
grids, and what the limits are and where they come from — all three measured or
read at step 0.

## Goal

Make "secure" an answer about survival. After M9, every generator outage the screen
reports carries, beside its line-and-voltage outcome, a **frequency verdict**: the
settled deviation (from each screen), the lowest dip and the initial rate of fall
(from a dynamic run of that outage, on the same lossy grid the screen solved), each
judged against limits the caller supplies — with a cited preset for the two the
EU's operating rules publish. An outage survives only if both verdicts pass.

To get there the dynamic tiers learn line resistance, without moving a single
lossless number.

## What M9 is not

See `m9-context.md` D4: no load shedding inside the screen, no closed-form dip
estimate, no frequency verdict on line outages, and none of M8 D5's exclusions lifted.

## The order, and why it is the order

The ordering rule is M4 D7's, carried through M5–M8: **never let two things change
at once between a number and its check.** Resistance comes first, because the dip
cannot be measured on the report grids without it, and because its gate (nothing
lossless moves) must be closed before any new number is read on top of it. The
detailed tier goes before the swing tier, because the swing tier's lossy check *is*
the detailed tier's frozen-flux degeneration. The outside check comes third, on
both, so its band is stated once against a model that is no longer moving. Then the
verdict and its limits, on the settled value alone, because that is the one with an
exact oracle already in the repo — the type gets fixed before a dynamic number
feeds it. Then the dip, then the rate (which reuses the dip step's runs), then the
report, then the close.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs. It is done when its named check passes with a
positive control and an executed anti-vacuity mutation**, the standing rule since
M3.

### Step 1 — Line resistance in the detailed tier (Hurdles 17.1–17.4, 17.7)

The detailed tier's edge current becomes `(Vf − Vt)/(R + jX)`; `branch_power`
reads both ends honestly; `_assert_lossless_branches` is lifted for this tier only
and its docstring's list shrinks by one.

- **Before the first edit:** capture at HEAD M5's 169 criterion values and the
  83-case AC digest (`W:\temp\claude\gridsim-m8\criterion_snapshot.jl`,
  `ac_snapshot.jl`), M8's screen outputs on both report fixtures, and step 0's
  lossless dip table. **Gate:** all four bit-identical after the change.
- **Flat run:** a lossy `ac_powerflow` seeds the tier and nothing moves (no event).
- **Settled, as an identity (`m9-context.md` D0 17.4):** with every governor
  uncapped on constant-power loads, `Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw`, each
  side's post-outage losses read from its own solution. Regulator off, as the
  dip step will run it; not a band fitted to the gap. Lossless, both sides of the
  identity are zero (step 0's digit-for-digit match).
- **`t⁺` accounting:** the initial COI rate equals `(ΔP + Δlosses(t⁺))/(2ΣHS)`,
  where `Δlosses(t⁺)` is read from the network at the instants either side of the
  trip — an identity, not a tolerance.
- **Antisymmetry audit (17.7):** grep every caller of `branch_power` /
  `branch_power_series` that sums, negates or reads one end (M8's export-sum
  helpers, the windows); each is fixed or shown to read the right end, and the list
  is recorded.
- **Sabotages:** `R` with the wrong sign; `R` dropped from one end's current only;
  `R` read on the machine base. Which check each one can see is pre-registered —
  and one that the flat run is predicted blind to (a sabotage shared with the power
  flow's admittance builder, if the tier reuses it) is left for step 3.

### Step 2 — Line resistance in the swing tier (Hurdle 17.6)

The classical coupling gains its conductance: `Pᵢ = E′ᵢ²Gᵢᵢ + Σⱼ E′ᵢE′ⱼ(Gᵢⱼ cos δᵢⱼ +
Bᵢⱼ sin δᵢⱼ)`, built sparse (SPEC §6), `_assert_lossless_branches` lifted for the
tier, so nothing refuses `R` in `src/engines/` any more and the function is deleted
or left with an empty list on purpose.

- **Gate:** step 1's four captures and the M8 step 4 swing-against-DC agreement
  (1.5e-10) bit-identical at `R = 0`.
- **Cross-tier oracle:** the detailed tier at frozen flux on the same lossy network
  (M5 step 2's degeneration) matches the swing tier, within the band that oracle
  already carries.
- **Stated, not lost:** on a lossy grid the swing tier is no longer the DC screen's
  exact oracle; a test pins that the two differ there by the losses and nothing else.
- **Sabotages:** drop the self term `E′ᵢ²Gᵢᵢ`; `G` with the wrong sign; `cos` and
  `sin` swapped on the conductance term.

**Done 2026-10-08 (`m9-context.md` D6). What this plan missed:** a lossy grid has no
steady state at this tier until somebody picks up the losses — the reference bus
does, as in the detailed tier, through a static solve before the fixpoint. The
function was not deleted: `build_oracle` still calls it (step 3). Two sabotages were
added at review — a trip that zeroes `K` only, and self terms by the branch's ends.

### Step 3 — The outside check on both tiers (Hurdle 17.5)

`reference/src/oracle.jl` passes `R = br.R` to `Library.PiLine`. Both tiers are run
against PowerDynamics on a lossy meshed fixture, with the band **stated before the
gap is seen**, built with `convergence_band` — the cross-convergence method M4 step
4 adopted after measuring that a band from each side's *own* convergence never looks
at the gap it judges — and with M6 oracle B's caution that the oracle may be the
less accurate side.

- **The sabotage only this check can see:** one placed in whatever our tier shares
  with our power flow, so steps 1–2's flat runs and cross-tier checks stay green and
  this goes red. If nothing is shared, that is recorded and the mutation is the
  conductance sign.

### Step 4 — The frequency verdict and its limits, on the settled value (Hurdle 16.1)

A limits type (`FrequencyLimits` or similar): settled, dip and rate limits, each
optional, in Hz (deviations from `f0`, so a 60 Hz grid works), the rate carrying its
window as data and refused without one. A preset built from SO GL Annex III for
Continental Europe — settled 0.2 Hz, dip 0.8 Hz, **no** rate (D3) — named and cited
in its docstring, with the "design value, not a pass/fail rule" caveat. Each
generator screen's outcome gains a frequency verdict beside it, on its **own** `Δω`;
`compare_generator_screens` gains the disagreement as a class.

- **Gate:** with no limits given, every M8 output and test bit-identical — the
  separate-verdict choice (D2.5) made checkable.
- **Positive control:** the mesh's G1 loss (10.94 Hz) fails any sourced settled
  limit; **anti-vacuity:** a case that lands within a few mHz of the limit, either
  side, built from the closed form, so a sign or `≤`/`<` mutation flips it.
- **The disagreement class reached:** a fixture where DC and AC sit on opposite
  sides of a limit (M8 claim (e) says one exists; build it, do not assume it).

### Step 5 — The dip (Hurdles 16.2–16.6)

Per generator outage, a dynamic run in the detailed tier on the screened grid
(lossy, with its loads), started from the AC screen's own base solution. The engine
gains a per-machine running minimum beside `eng.nadir`.

- **Stopping rule, on the run's own settling** (never the screen's value, which
  default loads miss by 12–23 %, `m9-context.md` D1): the run stops once
  `|d f_coi/dt|` has stayed below a stated rate for a stated time, with a horizon of
  several `2ΣHS/ΣD` time constants — the damping-only slide of a governor-capped grid, the slowest case (mesh G1 needed ~100 s). A minimum followed by a
  recovery fixes the dip on its own; only the monotone, governor-capped case needs
  the settling test. A horizon reached first is the named outcome "not reached".
- **The solver pair is frozen here, before any lossy run:** FBDF at reltol 1e-6
  and at 1e-8 (abstol reltol/100 each). An outage is judged only when the two dips
  agree within `convergence_band`; a failure at either setting, or a disagreement,
  is its own named outcome. Never a third setting tried after the fact.
- **Positive control for 16.5, predicted from step 0:** on the lossless copy,
  mesh-default G2 fails at 1e-8 (`Unstable` at 5.6 s) and runs at 1e-6, so under the
  frozen pair it is **predicted to return the solver-failure outcome**, not a dip.
  That prediction is the control; it is not "fixed" by changing the pair.
- **Regression:** step 0's lossless table reproduced from the new code (lossless
  copies), dip and settled to the printed digits, wherever the frozen pair judges.
- **Refusal mismatch (16.6), reported not asserted empty:** the outages the tier
  refuses at re-initialisation while the AC screen says `:secure` get the named
  outcome "dynamic run refused at the trip". Step 0 predicts exactly one on the
  lossless copies, case9-constant-power G2; the lossy grids are measured.
- **Exactness:** the per-machine running minimum equals a dense-`saveat` minimum on
  a short run, and is never shallower than it (a decimated read can only miss a
  minimum, never invent one).
- **Sabotages:** the minimum read from the recorder; the COI read in place of every
  machine (mesh G2's 7.7 % is the fixture that sees it); the last sample reported
  when the horizon runs out; a single tolerance.

### Step 6 — The rate of fall (Hurdle 16.7)

From the dip step's runs, the rate over the caller's window, COI and per machine,
via `windowed_rocof`/`rocof_readouts` (M7), with the verdict naming which one it
judged.

- **Closed form:** on constant-power loads at `t⁺`, `(ΔP + Δlosses)/(2ΣHS)·f0`
  (step 1's identity); the windowed value approaches it as the window shrinks, and
  the direction of the gap is predicted before it is measured.
- **A limit without a window is refused**, by name.
- **Sabotages:** window ignored; `H` on the machine base; the lost machine's inertia
  left in `ΣHS`.

### Step 7 — The report

`scripts/outage_screen.jl` (or its successor) prints, per generator outage, the
line-and-voltage outcome and the frequency verdict side by side, on the **lossy**
report grids the dynamic tiers can now run, with the preset's caveat printed where
its numbers are used. Claim (d) is revisited here and only here. Claims asserted in
the test at the printed precision; prose written **after** reading the table (M3
step 6's rule). Whether a window shows it is the user's call at this step.

### Step 8 — Close

Manifests deleted and re-resolved in all three environments, counts re-measured,
step 1's captures re-run before and after and their digests recorded; ledger rows;
README row and hurdle list (16 and 17 closed or carried, with what closed each);
`SPEC.md`; memory.

## Cut-first, in order

1. A step-7 window, if one is chosen.
2. Step 6's per-machine rate (the COI rate and its closed form stay).
3. Step 3's swing-tier half (the detailed-tier half stays: it is the only check
   that sees a shared-builder sabotage on the tier the dip runs on).

Nothing else is cut without recording the decision in `m9-context.md` first.
