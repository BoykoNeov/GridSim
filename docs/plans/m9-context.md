# M9 context — decisions, and what the steps actually measured

Companion to `m9-plan.md` (the how) and `m9-tasks.md` (the checklist). Read D0
first: the hurdles were named before the plan, after the step-0 measurement in D1.

## D0 — Why this milestone, and the hurdles it exists for (named BEFORE the plan)

M8's close left one hurdle open, the first close since M4 that did not leave the
list empty: **16 — a secure screen is not a surviving grid** (`m8-context.md` D9).
`:secure` means the lines and voltages are inside their limits after an outage
settles, and nothing about frequency. Losing the mesh's G1 caps both remaining
governors, leaves 105 MW to damping alone, settles 10.94 Hz low, and both screens
call it secure. The user chose (2026-10-08) to take it as M9, and then chose its
shape (D2): the settled value, the lowest dip **and** the rate of fall; line
resistance taught to **both** dynamic tiers so the dip can be measured on the grids
the screen reports on; limits a required input with a cited preset; a frequency
verdict **beside** the existing outcome, never replacing it.

**Why "add a limit to the settled Δω" is not the milestone.** Both screens already
compute the settled deviation for every generator outage (M8 steps 4–5), and M8
checked it against the swing tier to 1.5e-10. A threshold on it is one comparison
with a ready oracle — the trap `docs/plans/README.md` records for M6, a milestone
with no hard part. What is hard is everything a static screen cannot see, and the
measurement that lets it be seen at all. Step 0 measured both before this was
written (D1).

- **Hurdle 16 — A secure screen is not a surviving grid** (sub-claims, measurable):
  1. **The settled value is two numbers.** Each screen judges its own `Δω` and the
     two can land on opposite sides of a limit — M8 claim (e) measured DC's
     settled value as no bound on AC's in either direction (AC deeper by
     0.6–15.5 % on constant power, shallower down to half on default loads). So
     each screen carries its own verdict, and `compare_generator_screens` gains the
     disagreement as a class. Neither is declared the reference.
  2. **The dip needs inertia, and the screen has none.** Step 0 measured the lowest
     COI frequency 1.20–1.65× deeper than the settled value in every outage whose
     governors stay uncapped (D1), so a dip criterion is **not** vacuous on these
     fixtures; where the governors cap it degenerates to the settled value
     (monotone, reached after ~100 s). The dip comes from a dynamic run per
     generator outage — exact for the model, and costly.
  3. **Whose frequency.** M3 D5 binds load shedding to one machine's own speed,
     never the inertia-weighted mean, because that mean can sit between two
     machines that are separating. Step 0 measured the worst single machine up to
     7.7 % deeper than the COI dip (mesh G2). The dip verdict therefore judges every
     machine and reports the average beside it.
  4. **The dip is a running minimum over a run that must be long enough, and the
     recorder cannot give it.** The recorder decimates, so the per-machine minimum
     is tracked in the engine as `eng.nadir` already is. A run that ends before
     frequency has turned or come within band of the screen's settled value
     reports a named "not reached" outcome — never its last sample. (Mesh G1's dip
     arrives at ~100 s; step 0's mesh-default G2 was still moving at 60 s.)
  5. **A solver failure is an outcome, never a verdict.** Step 0's mesh-default G2
     fails with `Unstable` under FBDF at reltol 1e-8 and runs under FBDF 1e-6, FBDF
     1e-10 and Rodas5P 1e-8, all three agreeing to four digits. Retrying until a
     setting passes would be choosing an answer. Each outage runs at two tolerances
     and is judged only when the two agree within `convergence_band`; a failure or
     a disagreement is its own outcome.
  6. **The dynamic tier's refusals should be the AC screen's `:voltage` set.** At
     step 0 the detailed tier refused exactly case9's three outages the AC screen
     refuses for voltage (re-initialisation outside the band). Pre-registered as a
     check, measured at the dip step, not assumed.
  7. **The rate of fall is not one number** (M7 Hurdle 10: three RoCoFs under three
     names; the instantaneous one measured the smallest). A RoCoF limit is
     meaningless without its window, and the sources disagree on the window (D3).
     The verdict names which RoCoF it judges (COI or per machine, and the window),
     and the limit carries its window as data. At `t⁺` on constant-power loads the
     COI value is `ΔP/(2ΣHS)·f0` (step 0: within 2–3 % over a 0.1 s read), the
     closed form the rate check rests on.

- **Hurdle 17 — Line resistance in the dynamic tiers, without moving a lossless
  number.** `Branch.R` is read by the power flows (M6) and refused by both dynamic
  tiers (`_assert_lossless_branches`, whose docstring calls itself "the list of what
  still has to learn it"). Step 0 found this the first blocker: **neither report
  fixture can run dynamically**, both being lossy. Measurable claims:
  1. **Invariance.** At `R = 0` every existing number is bit-identical: M5's 169
     criterion values, the 83-case AC digest, M8's screen outputs, and step 0's
     lossless dip table (which becomes the dip step's regression). Captured at HEAD
     before the first edit.
  2. **The flat run.** A lossy `ac_powerflow` seeds the detailed tier with no
     transient — Hurdle 8's check carried to a lossy network.
  3. **Exact accounting at `t⁺`.** On a lossy grid the initial COI rate departs from
     `ΔP/(2ΣHS)` by exactly the instantaneous change in losses (plus load relief on
     default loads, M7 D16's identity with a losses term added).
  4. **Settled agreement.** On constant-power loads the lossy detailed tier settles
     to the AC screen's lossy `Δω` (M8 step 5 checked only lossless).
  5. **An outside check that does not share our builder.** If the detailed tier's
     edge current reuses the power flow's admittance code, the flat run cannot see
     a sabotage there. PowerDynamics' `Library.PiLine` already takes `R` (the
     oracle passes `R = 0.0` today, `reference/src/oracle.jl`); the band is stated
     before the gap is seen, and the oracle is a floor, not a ceiling (M4 D7).
  6. **The swing tier's classical coupling with conductance** — `E′ᵢE′ⱼ(Gᵢⱼcos δᵢⱼ +
     Bᵢⱼsin δᵢⱼ)` plus the `E′ᵢ²Gᵢᵢ` self term — checked against the detailed tier's
     frozen-flux degeneration (M5 step 2's oracle) now on a lossy network, and
     against `Library.Swing` with lossy lines. At `R = 0` the swing tier stays the
     DC screen's exact oracle (M8 step 4); on a lossy grid it no longer can be,
     because the DC screen has no losses, and that is stated rather than lost.
  7. **Antisymmetry is gone.** With `R ≠ 0`, `branch_power(a, b) ≠ −branch_power(b,
     a)`. Every caller that sums, negates or reads one end is audited — the class of
     M2's edge-order finding and M8's read-by-position bug — including M8's
     export-sum helpers and the windows.

## D1 — Step 0 measured the dip before the plan named it (2026-10-08)

Spike `W:\temp\claude\gridsim-m9\step0_dips.jl`, predictions written first in
`W:\temp\claude\gridsim-m9\step0_predictions.md` (outcomes appended there). Every
generator outage of `scripts/outage_screen.jl`'s two fixtures, both load models, in
the detailed tier (the one dynamic tier that takes `Load`), trip at 1 s, FBDF at
reltol 1e-8, 150 s.

**First, not predicted: the dynamic tiers refuse line resistance**, so the spike ran
on lossless copies (`R` dropped), with the AC screen re-run on the same copies.

| outage | dip Hz | s after trip | settled Hz | AC screen Hz | dip/settled | RoCoF₀ Hz/s | worst machine Hz |
|---|---|---|---|---|---|---|---|
| case9 cp G1 | refused at re-init: B1 0.773 pu | | | | | | |
| case9 cp G2 | refused at re-init: B2 0.889 pu | | | | | | |
| case9 cp G3 | −0.741 | 1.41 | −0.449 | −0.449 | 1.65 | 0.935 | G2 −0.744 |
| case9 def G1 | refused at re-init: B1 0.882 pu | | | | | | |
| case9 def G2 | −0.656 | 1.41 | −0.397 | −0.455 | 1.65 | 0.827 | G1 −0.658 |
| case9 def G3 | −0.581 | 1.41 | −0.352 | −0.398 | 1.65 | 0.734 | G2 −0.583 |
| mesh cp G1 | −10.94 | ~103 | −10.94 | −10.94 | 1.00 | 3.60 | G3 −10.94 |
| mesh cp G2 | −0.510 | 1.38 | −0.424 | −0.424 | 1.20 | 0.771 | G3 −0.550 |
| mesh cp G3 | −0.255 | 1.03 | −0.193 | −0.193 | 1.32 | 0.468 | G2 −0.263 |
| mesh def G1 | −8.67 | ~72 | −8.67 | −11.22 | 1.00 | 3.10 | G3 −8.67 |
| mesh def G2 | FBDF 1e-8 `Unstable` at 5.6 s; FBDF 1e-6 / 1e-10 and Rodas5P 1e-8 agree: −0.391 at 1.34 s, −0.322 at 60 s and still moving | | | | | | |
| mesh def G3 | −0.167 | 1.03 | −0.127 | −0.163 | 1.32 | 0.308 | G2 −0.174 |

Against the predictions: the initial rate held (within 2–3 % of `ΔP/(2ΣHS)·f0` on
constant power, smaller on default loads); the dip ratio was **partly wrong** —
case9's 1.65 inside the predicted 1.5–3.0, the mesh's 1.20–1.32 below it; the capped
case is monotone as predicted; the worst machine is deeper than the average by under
10 % as predicted. Default loads settle shallower dynamically than the AC screen says
(load relief, M8's known gap) — the mesh's G1 by a lot, −8.67 against −11.22 Hz.
**The solver failure on mesh-default G2 was not predicted** (Hurdle 16.5).

All dips here are on invented dynamics (`outage_screen.jl` says so); a pass or fail
on them proves nothing about a real grid. Checks rest on algebra and on agreement
between tiers, never on a fixture's verdict.

## D2 — The user's choices (2026-10-08)

1. **What is judged: the settled value, the lowest dip, and the rate of fall** —
   over the recommended "settled + dip". The rate is the third limit to source.
2. **Line resistance taught to the dynamic tiers, rather than a lossless copy.** Over
   the recommendation ("lossless copy, stated"), which would have kept M9 smaller.
3. **Both dynamic tiers learn it** — the swing tier as well as the detailed one,
   over the recommendation ("detailed only"). The swing tier cannot run the report
   grids either way (it refuses `Load`); it gains resistance for completeness, and
   keeps its role as the DC screen's exact oracle on lossless grids only.
4. **Limits are a required input, with a cited preset** — no silent default. The
   preset carries only what a source gives (D3).
5. **A separate frequency verdict beside today's outcome.** `:secure` keeps M8's
   meaning; nothing M8 built or asserted moves. An outage survives only if both pass.

## D3 — The limits, from their sources (read 2026-10-08)

Copies under `W:\temp\claude\gridsim-m9\sogl\`.

- **Commission Regulation (EU) 2017/1485 (SO GL), Annex III Table 1, OJ L 220/116**
  (read from the page image): Continental Europe — standard frequency range ±50 mHz,
  **maximum instantaneous frequency deviation 800 mHz, maximum steady-state frequency
  deviation 200 mHz**. GB 800 / 500 mHz; IE/NI 1000 / 500; Nordic 1000 / 500.
- **SO GL Article 153(2)(b)(i):** the Continental Europe reference incident is
  3 000 MW in each direction.
- **What these are:** design values — "the maximum expected" deviation after an
  imbalance up to the reference incident, on a whole synchronous area (Article 3,
  definitions 47 and 144). They are not a pass/fail rule for an outage on a small
  grid, and the preset says so. Applied naively to step 0's lossless table, no
  uncapped dip exceeds 800 mHz and most settled values exceed 200 mHz (5 % droop on
  a small grid) — a statement about the invented droop, not a result.
- **The rate of fall has no area-wide sourced value.** NC RfG Art. 13(1)(b) and NC
  DCC Art. 28(2)(k) leave it to the relevant TSO (DCC: "calculated over a 500 ms time
  frame"); NC HVDC Art. 12 gives ±2.5 Hz/s averaged over the previous 1 s, for HVDC
  systems only (ENTSO-E IGD "RoCoF withstand capability", 29 March 2017, p. 2);
  ENTSO-E RG-CE "Frequency Stability Evaluation Criteria" (2016) states 2 Hz/s as a
  "study hypothesis" with no window. So **the preset carries no RoCoF limit**; a
  caller who judges the rate must supply the limit and its window together, and a
  limit without a window is refused.

## D4 — What M9 does not do

- **No under-frequency load shedding inside the screen.** If a dip crosses a shed
  stage the real grid sheds and settles elsewhere; M9 reports that the stage would
  be reached, not the post-shed grid. Modelling the shed changes the screen's
  question, and is named for later if wanted.
- **No closed-form dip estimate.** The dip comes from dynamic runs (the user's
  choice of what to judge, D2); the aggregate tier's refusal of `Load` (M7 D16) stays
  owed and off the critical path.
- **No line charging, no N-2, no batched/GPU runs, no map** — as M8 D5.
- **Line outages get no frequency verdict.** A line outage loses no generation; a
  split that islands generation is already a named outcome. Stated, not built.
