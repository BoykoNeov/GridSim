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
     is tracked in the engine as `eng.nadir` already is. The run stops on its **own**
     settling, never on the screen's value (D1: default loads settle 12–23 % away
     from it). A run that reaches its horizon first reports a named "not reached"
     outcome — never its last sample. (Mesh G1's dip arrives at ~100 s; step 0's
     mesh-default G2 was still moving at 60 s.)
  5. **A solver failure is an outcome, never a verdict.** Step 0's mesh-default G2
     fails with `Unstable` under FBDF at reltol 1e-8 and runs under FBDF 1e-6, FBDF
     1e-10 and Rodas5P 1e-8, all three agreeing to four digits. Retrying until a
     setting passes would be choosing an answer. Each outage runs at two tolerances
     and is judged only when the two agree within `convergence_band`; a failure or
     a disagreement is its own outcome.
  6. **The dynamic tier refuses outages the AC screen calls secure.** The two judge
     voltage at different instants: the detailed tier's re-initialisation checks the
     band the instant after the trip, with the field flux held and (by default) no
     regulator; the AC screen checks it after settling, with every `V_set` held.
     Measured at step 0 (first written here, wrongly, as "the same set" — the spike
     had not printed the AC outcome for the refused runs; corrected the same day by
     `docs/evidence/gridsim-m9/step0_refusals.jl`): case9's G1 is refused by both,
     on both load models; **case9-constant-power G2 is refused dynamically (B2 at
     0.889 pu) and `:secure` in the AC screen**, lossless and lossy alike. So "the
     dynamic run refused at the trip" is a named outcome of the frequency verdict —
     never a silent pass, and never borrowed from the AC verdict — and the dip step
     reports the mismatch set rather than asserting it empty.
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
  4. **Settled agreement, as an identity rather than a band.** Lossless on constant
     power the total pickup is the lost power, whatever the voltages, which is why
     step 0 matched to the digit. Lossy, the pickup is the lost power **plus the
     change in losses**, and losses depend on voltages the two sides hold
     differently (field flux against `V_set`, M8 step 5). So the check is: with every
     governor uncapped, on constant-power loads, `Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw`,
     each side's post-outage losses read from its own solution, `Σw` the summed
     droop-and-damping weights. A band fitted to the gap is exactly what this
     replaces.
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

Spike `docs/evidence/gridsim-m9/step0_dips.jl`, predictions written first in
`docs/evidence/gridsim-m9/step0_predictions.md` (outcomes appended there). Every
generator outage of `scripts/outage_screen.jl`'s two fixtures, both load models, in
the detailed tier (the one dynamic tier that takes `Load`), trip at 1 s, FBDF at
reltol 1e-8, 150 s.

**First, not predicted: the dynamic tiers refuse line resistance**, so the spike ran
on lossless copies (`R` dropped), with the AC screen re-run on the same copies.

| outage | dip Hz | s after trip | settled Hz | AC screen Hz | dip/settled | RoCoF₀ Hz/s | worst machine Hz |
|---|---|---|---|---|---|---|---|
| case9 cp G1 | refused at re-init: B1 0.773 pu (AC: `:voltage`) | | | | | | |
| case9 cp G2 | refused at re-init: B2 0.889 pu (**AC: `:secure`**) | | | | | | |
| case9 cp G3 | −0.741 | 1.41 | −0.449 | −0.449 | 1.65 | 0.935 | G2 −0.744 |
| case9 def G1 | refused at re-init: B1 0.882 pu (AC: `:voltage`) | | | | | | |
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
**The solver failure on mesh-default G2 was not predicted** (Hurdle 16.5), and
neither was the refusal mismatch (Hurdle 16.6): case9-constant-power G2 is refused
dynamically and `:secure` in the AC screen. That mismatch was first written into D0
as a match — the spike skipped the AC column for refused runs — and caught at review
the same day.

**What default loads mean for stopping a run.** The default-load runs settle 12–23 %
away from the AC screen's value (load relief; case9 G2 −0.397 against −0.455, the
mesh's G1 −8.67 against −11.22). A stopping rule keyed to the screen's settled value
would call every default-load outage "not reached", so the dip step stops on the
run's own settling instead (plan step 5).

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

Copies under `docs/evidence/gridsim-m9/sogl/`.

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

## D5 — Step 1 measured: line resistance in the detailed tier (2026-10-08)

**The change.** The edge current is `(Vf − Vt)/(R + jX)` in both compiled networks
(`_branch_current!`; `R` appended to the edge parameters so `X` and `status` keep
their slots). `AntiSymmetric` is kept, and is exact: a series branch with no shunt
carries one current, so the far end sees `−I`; what stops being equal and opposite
is the power, and that is read where power is read. `branch_power` and
`branch_power_series` read the receiving end as `Re(V_to·conj(−I))`.
`branch_topology` carries `R`. The refusal is gone from this tier;
`_assert_lossless_branches` now names what is left (the classical tier, step 2, and
`build_oracle`, step 3).

**Bit-identity needed the old arithmetic kept — in one place out of the three
where it was first kept.** In the edge equation, written in real arithmetic, `bX/X²`
and `b/X` are the same number in exact arithmetic and not in floating point, so at
`R = 0` `_branch_current!` runs the pre-M9 expressions textually. Removing that path
(sabotage S6) moves 86 of M5's 169 recorded criterion values in their last digits.
The current read-out (`_series_current`) was first written with the same branch, and
it is **not needed**: dividing by `complex(0, X)` is dividing by `im·X`, the same
operation on the same operands, and removing the branch (S6b) moved none of the 169
values, which read the tie through it — so the branch was deleted, measured rather
than argued. The receiving-end read (`_end_power`) does need its branch (`−Re(Vf·I*)`
and `Re(Vt·(−I)*)` round differently), and **no capture gates it**: no full-precision
capture reads a lossless branch against its orientation, so its bit-preservation
rests on inspection. With these, all four captures taken at HEAD before the first edit
— M5's criterion values, the 83-case AC digest, every field of `outage_screen` on both
report grids and load models, and step 0's lossless dip table at full precision —
are byte-identical after the change.

**What was measured on the lossy report grids** (spike
`docs/evidence/gridsim-m9/step1/spike.jl`, log beside it):

- **Each end at its own terminal.** At the seed, each branch's two end powers sum
  to `ac_powerflow`'s `loss` within 2.2e-16, from separately written admittance code.
- **Flat run.** Seeded from a lossy `ac_powerflow`, both grids, both load models, two
  tolerances: worst drift 4.2e-13 on any state over 50 s.
- **`t⁺`, exactly.** On constant-power loads, `Σ2H·ω̇(t⁺) = −(P_lost + ΔL)` closes to
  6.7e-14 or better on the four outages that pass the trip (case9 G3, mesh G1–G3);
  the losses change it accounts for is −1.9e-3 to +1.7e-2 pu, so the term is what
  closes the identity, not decoration. (On default loads the load-relief term
  dominates, as M7 D16 found; not asserted here.)
- **Settled, as an identity.** `Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw` holds to
  4e-14 on case9 G3 and 5e-14 on mesh G3 at 400 s, against gaps of 3.0e-5 and
  2.8e-5 pu (1.5 and 1.4 mHz): **the dynamic tier settles slightly deeper than the
  AC screen, and the difference is the losses and nothing else.** What limits the
  residual is how settled the run is, not the solver (case9 G3: 5e-9 at 100 s,
  4e-12 at 200 s, 4e-14 at 400 s).

**Found, not planned.**

1. **Only two outages qualify for the settled identity**, not three: the mesh's G2
   caps G3's 5 MW of headroom on the lossy grid, so it is excluded with case9's G1
   and G2 (refused at the trip) and the mesh's G1 (both governors capped).
2. **The refused-at-the-trip set on the lossy grid is step 0's lossless one**:
   case9 G1 and G2 on constant-power loads, by the voltage band. Now pinned.
3. **The tier's own steady state (no `powerflow`) refuses lossy case9** on the
   voltage band: that path holds each machine's internal voltage at `Machine.E′`
   (1.0 on case9), not at `V_set`. Lossless case9 on constant-power loads is refused
   there already; on default loads the lossless copy passes and the lossy one sags
   B9 to 0.889 pu. A real effect of the resistance on a path the screen does not
   use; that check runs on the mesh.
4. **A check was too lenient, and a sabotage found it.** The `t⁺` test first skipped
   any re-initialisation error as "refused at the trip". With `R` written into the
   dynamic network only (S4), the dynamic-Kirchhoff check's own throw was swallowed,
   and the test went red only through its count of cases. The catch now takes the
   voltage-band refusal alone and the refused set is asserted.
5. **The detailed tier's rating check reads the sending end only** (`_branch_flows`),
   while `ac_powerflow` judges the larger end. The two ends differed before M9 — in
   reactive power, by `|I|²X` — and now differ in real power too. Widening it would
   move lossless refusals, which this step's gate forbids, so it is **carried, not
   changed**. At initialisation on the seeded path it is moot (`ac_powerflow` has
   refused any overload at either end); at a re-initialisation after an event it is
   not.

**The antisymmetry audit (Hurdle 17.7).** Every reader of a branch's power or
current in this tier, and every hand-written copy of `ΔV/(jX)`:

| Where | Reads | Verdict |
|---|---|---|
| `branch_power(::DetailedEngine, a, b)` | the end named first | fixed: receiving end read at its own terminal |
| `branch_power_series(::DetailedEngine, …)` | same | fixed, same way |
| `_branch_flows` (rating check) | sending end `|S|` | `R` read; sending-end-only carried (finding 5) |
| `scripts/iberia_two_area.jl` `peak_export` | `:ES → :FR`, the branch's own orientation | correct end; lossless fixture |
| `scripts/low_inertia.jl` `bus_export` | its own copy of `ΔV/(jX)` | now `ΔV/(R + jX)`, the same number at `R = 0` |
| `test/m5_detailed.jl`, `test/m7_inverters.jl` | hand copies of `ΔV/(jX)` | same change, same reason |
| `test/m8_screening.jl` `export_of` | the bus's own end of each branch | correct once `branch_power` reads each end honestly |
| `test/m5_detailed.jl` antisymmetry asserts | `a,b` against `b,a` | lossless fixtures; true there, still asserted |
| the windows (`ui/`) | none — no window calls `branch_power` | nothing to fix |
| `branch_power(::SwingEngine, …)` | the classical tier | step 2's — audited in D6 |

**Sabotages** (predictions written first, `docs/evidence/gridsim-m9/step1/predictions.md`):

| | Sabotage | Red | Green |
|---|---|---|---|
| S1 | `R` with the wrong sign | seeded start refused (residual 0.36), so every seeded check | the tier's own steady state (shares the edge with itself) |
| S2 | receiving end read as minus the sending end | both-ends check, `t⁺`, settled — and the own-steady-state check through its losses read (**predicted green; wrong, harmlessly**) | flat runs |
| S3 | `R` scaled by a machine base | as S1 | as S1 |
| S4 | `R` in the dynamic network only | own steady state (residual 0.15), `t⁺` and settled (dynamic Kirchhoff check at the trip, 0.26) | seeded flat run, both-ends check (the seeded path never solves the static network before an event) |
| S5 | `R` in the static network only | every seeded check, own steady state | — |
| S6 | the edge's `R = 0` path removed | the gate: 86 / 169 criterion values move | every check with a tolerance |
| S6b | the current read-out's `R = 0` path removed | nothing — 0 / 169 move: the path was not needed, and is deleted | everything (an equivalent change) |

**For step 3 — corrected at review the same day.** First written here as "step 3
will have no mutation that only the outside check catches", because the tier's edge
and `ac_powerflow`'s admittance share no code and S1 (the sign) is already caught
by the seeded flat run. **Wrong.** Get `R` wrong *the same way* in both — scale it
×2 in `_branch_current!`/`_series_current` and in `_ac_branch_flows` and the AC
admittance — and every step-1 check stays green: the seeded run is flat against an
equally wrong solution, the two ends sum to an equally wrong loss, and both identities
read each side's losses from its own, equally wrong, solution. Only PowerDynamics'
`PiLine`, reading `br.R` itself, sees it. That is M8's "a consistent wrong reactance
set hides from the flows" one level up, and it is **step 3's mutation**: red there,
green in every check here. Not sharing code does not make two copies independent
when both make the same mistake.

## D6 — Step 2 measured: line resistance in the swing tier (2026-10-08)

**The change.** A lossy model (any `R ≠ 0`) compiles every branch to a two-ended edge
(`swing_edge_lossy!`) with parameters `(K, Kc, Gs, Gd)` = `(EᵢEⱼX/|Z|², EᵢEⱼR/|Z|²,
E_src²R/|Z|², E_dst²R/|Z|²)`; the power into the branch at an end is
`G_a − Kc·cos Δ + K·sin Δ` (`_end_power`, read by the edge and by `branch_power`
alike). The self terms are filled by the **graph edge's** ends, never the branch's.
A lossless model compiles exactly the pre-M9 network — the `AntiSymmetric` edge, the
one parameter, the same fixpoint call — so `_assert_lossless_branches` is gone from
the tier and its only caller left is `build_oracle` (step 3).

**Found at orientation, not in the plan: a lossy grid has no steady state at this
tier as it stood.** Every `Pm` is a fixed parameter and the schedule sums to zero
(`NetworkModel`'s guard), so with losses nobody makes them up and `find_fixpoint` is
handed a system with no equilibrium. Decided (advisor-reviewed, not the user's
call — the step's own cross-tier oracle only works under this rule): **the model's
reference bus picks up the losses, the detailed tier's own rule.** A static network
(one state per vertex, `δ`; the reference pinned, every other vertex at its
schedule; the same lossy edge) is solved first, the reference's power read off the
edges, and the dynamic fixpoint solved from the static angles. Never run on a
lossless model. Headroom stays `(Pmax − P0)/S_base`, as in the detailed tier — it
caps the governor's DEVIATION, so a reference whose dispatch rises by the losses
keeps its headroom. A grid-forming inverter on a lossy model's reference bus is
refused by name (its droop setpoint would have to move; no rule validated).

**The reach guard changed shape.** Per branch an end moves `Ea²g ± EaEb|y|`, which is
not symmetric about zero once `g ≠ 0`, so the lossless `|P| ≤ Σ K` would refuse some
feasible exporters and pass some infeasible absorbers. On a lossy model the bound is
`[Σ(Ea²g − EaEb|y|), Σ(Ea²g + EaEb|y|)]`, every vertex but the reference (whose power
the static solve decides). Pinned: a 6 pu absorber behind X = 0.1, R = 0.05 builds
lossless and is refused lossy (bound −4.94 pu).

**Measured** (`test/m9_line_resistance.jl`, step-2 testsets; probes under
`docs/evidence/gridsim-m9/step2/`):

- **Dispatch.** On five lossy fixtures (the reversed pair with each end as reference,
  a ring, M8 step 4's mesh, the mesh with a grid-forming inverter) every
  non-reference source holds its schedule exactly (`==`) and the reference's extra
  equals the losses read at both ends of every branch, to 1e-12.
- **Each end against a formula that shares no code** —
  `Re(Va·conj((Va − Vb)/(R + jX)))` from the phasors — to 1e-13, on the three
  machine-only fixtures, one branch written against the graph's order between unequal
  `E′`.
- **The flat run, and a gate that was wrong first.** Written at step 1's 1e-10 per
  state and red: the drift is the explicit Runge–Kutta's, in an absolute angle, and
  **the lossless twin drifts as much** (`probe_flat.jl`, 50 s: ring 2.0e-6 lossless
  against 3.2e-7 lossy at reltol 1e-6; mesh 6.4e-7 / 6.6e-7; ~3e-10 for both at
  1e-10). The start's residual is at machine precision in both (≤ 1.1e-15). So the
  check is the residual at the start (< 1e-13) and drift that falls with the
  tolerance; the radial pair is flat to the bit at both.
- **The cross-tier oracle.** The detailed tier at the frozen-flux degeneration on the
  reduced pair (`terminal_bus_reduced`, which **dropped `R` and the reference bus**
  when it rebuilt the model — fixed, and asserted): the two tiers' dispatch agrees to
  1e-12 with each end as reference, then all four channels inside `convergence_band`
  at two tolerances — M5 step 2's oracle, unchanged, now on a lossy line.
- **Swing against DC, exactly.** With every surviving governor uncapped,
  `ω_swing − Δω_DC = (L_pre − L_post − [reference lost]·L_pre)/Σw`, the last term
  because a lost reference takes the losses it carried. Mesh G3 and LB lost
  (reference elsewhere) and G3 lost as the reference: to rtol 1e-6, with the gap
  more than 10³ × the residual. At `R = 0` the gap is zero and M8 step 4's check is
  unchanged (the gate).
- **A trip leaves nothing on a dead branch** at either end, line or generator.

**Found, not planned.**

1. **`branch_power_series` ignored the caller's order on a lossless model** — asked
   for `(:B2, :B1)` it returned the `(:B1, :B2)` series. The swing capture written for
   this step's gate printed both and showed it. Every caller in the repo names the
   stored order, so nothing moved; the sign now follows the caller, as
   `branch_power`'s does, and the capture differs from HEAD in exactly that line, by
   an exact negation (verified line by line).
2. **`terminal_bus_reduced` (test helper) silently made the reduced model lossless**
   and reset its reference bus — the lossy cross-tier check would have compared a
   lossy swing tier against a lossless detailed one. Fixed and asserted.
3. **The gate.** Five captures at HEAD before the first edit — step 1's four (each
   byte-identical to step 1's own) plus a new full-precision swing-tier capture
   (`swing_snapshot.jl`: seven fixtures, every generator and line trip, the state,
   both ends of every branch, `coi_rocof`, one playback series) — are byte-identical
   after the change, but for finding 1's one line.
4. **The no-steady-state refusal was the library's, not ours.** Under sabotage S3 the
   static solve did not converge and NetworkDynamics' `NetworkInitError` surfaced,
   naming neither the reference bus nor the losses. It is now re-thrown as the tier's
   own refusal, and a test reaches it: two exporters each inside its own reach bound
   that a shared lossy ring cannot carry at once.

**Sabotages** (predictions first, `docs/evidence/gridsim-m9/step2/predictions.md`;
runner `mutate.py`, logs `mut-S*.log`):

| | Sabotage | Red | Green | Against the prediction |
|---|---|---|---|---|
| S1 | self term dropped from `_end_power` | independent end formula, cross-tier dispatch and trajectories, the losses themselves (negative), dead-branch residual, the playback ends; swing-against-DC — **through its precondition** (a governor capped once the dispatch moved, then the run failed), not through the identity | — | predicted the identity green; it is, in itself — red only because its precondition broke |
| S2 | conductance with the wrong sign | independent formula, cross-tier, the losses (negative), playback ends, live-branch residual | flat run, dispatch identity, **swing-against-DC** | as predicted |
| S3 | `cos`/`sin` swapped on the conductance term | independent formula, cross-tier; and every mesh build — the mesh has no steady state under the wrong formula (finding 4) | the pair's flat run | predicted dispatch and flat run green; they are red on the mesh by refusal — safe direction |
| S4 | a trip zeroes `K` only | both dead-branch checks; swing-against-DC (the dead bus stays coupled, the run fails at MaxIters) | everything without a trip | as predicted |
| S5 | self terms by the BRANCH's ends | independent formula (reversed branch, unequal `E′`), cross-tier | everything else | as predicted |
| S6 | the lossless path removed (lossy edge and slack on every model) | **the gate**: 225 of 312 swing-capture lines and 3 of 182 criterion lines move | every check with a tolerance (289 / 289) | as predicted |

S7 (the slack solve alone on lossless models) could not be run separately — the
static solve reads the lossy edge's parameters — and was folded into S6, written down
before any sabotage ran. **What sees what:** the dispatch identity and the
swing-against-DC identity read losses through the engine's own `_end_power`, so a
wrong edge equation leaves them self-consistent (S2 is green there). The independent
end formula and the detailed tier at the frozen-flux degeneration are the two checks
that see the equation, and between them they are red under all five edge sabotages.
The step-1 lesson stands one level up: a resistance misread the same way in BOTH
tiers' builders would be green here too, and is step 3's to catch.

**Found at review (the same day), and fixed in a follow-up commit.**

5. **`coi_model` accepted a lossy model in silence.** The classical tier's aggregate
   reads no branch and never called `_assert_lossless_branches` — the guard's
   docstring named every tier but this one, and the ledger said "all three tiers"
   refused `R`. Harmless while the tier it is derived from was lossless; from this
   step that tier's reference bus carries the losses while the aggregate balances
   `Σ P0 = 0`, a derived view disagreeing with its source in silence. Now refused by
   name (no caller passed a lossy model: the playback window and the M2/M7 tests
   use lossless fixtures). The guard has two callers left, `build_oracle` and
   `coi_model`.
6. **The antisymmetry audit for this tier (Hurdle 17.7)**, step 1's table carried
   on — every reader of a classical-tier branch power, and every hand copy of
   `K·sin Δ`:

| Where | Reads | Verdict |
|---|---|---|
| `branch_power(::SwingEngine, a, b)` | the end named first | lossy: each end at its own terminal (`_lossy_end`); lossless unchanged |
| `branch_power_series(::SwingEngine, …)` | same | lossy as above; lossless now honours the caller's order (finding 1) |
| `_zero_edge!` (both trips) | — | zeroes all four coefficients on a lossy model (S4) |
| `scripts/iberia_two_area.jl` `peak_export`, `K·sin`, `asin(P/K)`, `Ks = K·cos δ₀` | `branch_arrays(net).K`, the stored orientation | lossless two-area fixture; `branch_arrays.K` keeps its lossless meaning on purpose |
| `test/m2_network.jl`, `test/m2_events_and_coi.jl` | hand copies of `K·sin`, `asin(P/K)`, live `K_pidx` | lossless fixtures; true there |
| `test/m5_detailed.jl` antisymmetry asserts on `sw` | `a,b` against `b,a` | lossless fixture; still asserted |
| `test/m8_screening.jl` `export_of` | the bus's own end of each branch | correct with losses as it stands |
| `ui/` windows | none call `branch_power`; the network and playback windows build `SwingEngine` | a lossy model now runs in the network window; the playback window refuses it through `coi_model` (finding 5); the voltage window's tier-pair guard compares branches with `==`, `R` included |


## D7 — Step 3 measured: line resistance reaches PowerDynamics (2026-10-09)

**The change.** `build_oracle` hands `Branch.R` — read from the branch itself, not
from a view our tiers build — to `Library.PiLine` at `:swing` and `:sauer_pai`, the
two tiers M9 taught `R`. Their line current is `(V₁ − V₂)/(R + jX)` (read from their
source, `Library/Branches/PiLine.jl`), so their network is lossy by their own
arithmetic. `:classical` (its line reduction was derived lossless) and
`:sauer_pai_avr` (the exciter comparison was measured lossless) refuse `R` by name
with their own message; `_assert_lossless_branches` is left with one caller,
`coi_model`. The two transformer ratios `PiLine` carries are now passed as `1.0`
explicitly (their default; the file's rule that a default is not a guarantee).

**Found at orientation (advisor-flagged): the swing-tier seed handed PowerDynamics
the SCHEDULE.** `Library.Swing` was built with `Pm = Machine.P0`, while since step 2
our reference bus's `Pm` is the schedule plus the losses. The seed now reads our
engine's `Pm`, as `_seed_sauer_pai!` always did at the detailed tier. Control C2 is
what says it matters: handed the schedule, their run leaves our state by 0.10 Hz.

**The gate.** Five captures (step 2's set) and a new one — `oracle_snapshot.jl`, every
channel of eight lossless oracle runs across all four tiers and the inverter case at
full precision — taken at HEAD (`037c935`) before the first edit, byte-identical after.
Reference entry count re-measured at HEAD: 1262 (unchanged from step 2's close).

**Measured** (`reference/test/runtests.jl`, M9 step 3; values printed by
`docs/evidence/gridsim-m9/step3/probe_values.jl`; fixture `m9_lossy_ring`: `three_machine_ring()` with `R` = 0.05, 0.08,
0.10 pu on its three branches, so no uniform rescaling of `R` is a symmetry of it;
the reference picks up 0.0655 pu of losses at the swing tier, 0.0606 at the detailed):

| Check | Tier | Result | Control |
|---|---|---|---|
| flat run, per state | swing | ω flat to 4e-16, angle difference 3.5e-15 | C1 (their `R` zeroed under our seed): angle moves 1.0e-2; C2 (schedule seed): frequency moves 0.10 Hz |
| line trip `B3–B1`, band stated before the gap | swing | gap 0.30 of `convergence_band` on `f_coi`, the angle difference and all three speeds | the same trip on the lossless ring lands 1.1e8 bands away (the loss change after the trip moves the COI 0.19 Hz) |
| generator trip `G2` | swing | gap 0.25–0.29 of the band on every surviving channel | 6.1e6 bands from the lossless run |
| flat run, per state | detailed | every state agrees to 9.5e-15 | C1: `V_B1` moves 2.7e-3 |
| stator-ω residual | detailed | still linear in slip, coefficient 1.014–1.015 (lossless ring: ≈ 1) | — the transient is NOT judged by a band: lossless, it sits outside one by design (M5 step 3) |

**Sabotages** (predictions first, `docs/evidence/gridsim-m9/step3/predictions.md`;
runner `mutate.py` beside it; every sabotage in the ARITHMETIC that reads `R`, never
in `Branch`/`branch_topology`, which the oracle reads too):

| | Sabotage | In-house red | PowerDynamics | Against the prediction |
|---|---|---|---|---|
| T1 | `R` ×2 in the detailed tier and the AC solve | cross-tier (dispatch 0.630 against 0.616); `t⁺` and settled **by refusal** (×2 leaves report-grid outages no steady state); M6/M8 pinned numbers; oracle B | detailed red (flat run off by 2.4; signature coefficient 5–21); swing green | step-1 identities predicted green: red, but only by refusal |
| T1b | T1 at ×1.1 | cross-tier; `t⁺` errors on case9 G1 (refused anyway — now a stalled solve instead of the voltage-band refusal); **settled green** | detailed red | as predicted once refusal is set aside |
| T2 | `R` ×2 in the swing tier | the test's end formula; cross-tier | swing red (flat and transient); detailed green | as predicted |
| T3 | T1 + T2 | end formula; `t⁺`, settled by refusal; M6/M8; oracle B; **cross-tier green** | both red | as predicted |
| T4 | conductance sign, swing tier AND the test's end formula | **the losses' positivity** (the reference's pickup, `Pf + Pt > 0`, the playback ends, a live branch's losses); cross-tier | swing red | predicted green but for cross-tier — **wrong**: four checks that the losses are positive see a sign error that every identity reads consistently |
| T5 | T3 at ×1.1 AND the test's end formula ×1.1 | **nothing but case9 G1's stalled refusal** — all 151 step-2 checks, every identity, the cross-tier check green | both red (72 failures) | as predicted |

**What this establishes.** No single `src/` sabotage of `R` is invisible in-house:
step 2 put two readers of `R` beside the detailed tier's that share none of its
arithmetic — the swing tier (seen through the cross-tier check) and a formula
written in the test (which no `src/` edit can reach) — and a sign error is caught by
the losses having to be positive. The plan's "the sabotage only this check can see"
is therefore **T5**: one misreading of `R` written the same way into every reader we
have, test included — the "same hands" failure M4 built this package for, one level up
from D5's "not sharing code does not make two copies independent". No in-house
identity, comparison or formula sees it; its one in-house red is case9 G1's
re-initialisation stalling where at HEAD it is refused by name — a convergence failure
on an outage refused either way, not a detection. PowerDynamics sees it on both tiers.

**Found, not planned.**

1. **The swing-tier seed** (above): a lossy model would have been compared from a
   dispatch nobody had solved for, and read as a line-model disagreement.
2. **A stalled re-initialisation surfaces as the library's `NetworkInitError`**, not
   as the tier's refusal. At HEAD case9 G1 is refused by name (B1 at 0.646 pu after
   the trip); at ×1.1 `R` the same re-initialisation stalls (residual 1.5e-3) and the
   library's error comes out (`docs/evidence/gridsim-m9/step3/probe_trip_refusals.jl`,
   run at HEAD and under T1b). Step 2 re-threw the swing tier's static-solve failure
   as its own refusal; the detailed tier's re-initialisation does not. **Carried to
   step 5**, whose "refused at the trip" and "solver failure" outcomes must tell
   these apart — not changed here, since no step-3 check depends on it.
3. **A line trip on a lossy ring moves the COI by 0.19 Hz where the lossless ring
   moves it by 1e-3 Hz**: the trip changes the losses, the reference's `Pm` is held,
   and a governor-free grid settles off nominal by the change over its damping. A
   loss change is a load change — the mechanism step 1's `t⁺` identity accounts for.

## D8 — Step 4 measured: the settled verdict and its limits (2026-10-10)

**The change.** A new file, `src/steadystate/frequency_verdict.jl`, and nothing in
M8's code: `FrequencyLimits` (settled, dip, rate + window; each optional, Hz deviations
from `f0`), the preset `continental_europe_limits()` (D3's 0.2 / 0.8 Hz, no rate,
cited with the design-value caveat), and `frequency_verdicts(net, screen, limits)`,
which reads a FINISHED screen — the generator comparison or the whole
`OutageScreen` — and returns a separate `FrequencyVerdicts`. The limits are a required
positional argument (D2.4); the verdict never enters an M8 struct, so the gate (D2.5)
holds by construction and the capture confirms it.

**The decisions, each a rule now:**

- **Reaching a limit exactly passes** (`|Δf| ≤ limit`): SO GL states a *maximum*
  deviation. Judged on the size, so a rising frequency is judged too.
- **Each screen on its own `Δω`**, never the other's; the pair gets its own class
  (`:both_pass`, `:both_fail`, `:dc_only_fails`, `:ac_only_fails`, `:one_unjudged`,
  `:unjudged`, `:no_limit`), separate from M8's `class`, whose priority order it would
  otherwise tangle with.
- **No value is never a verdict.** DC stands behind its `Δω` when it shares
  (`:secure`/`:overload`); AC when it solved an operating point
  (`:secure`/`:overload`/`:voltage`). A refusal, and AC's `:no_solution` even where the
  solve got as far as a `Δω` (a switching backoff), is `:no_value` and its number is
  not reported. A screen that claims a solved outcome with a non-finite `Δω` is thrown.
- **The dip and the rate are `:not_run`** where a limit is given — never `:pass`, and
  never the settled value read in their place, even where a capped grid's dip equals
  it. Steps 5–6 fill those two vectors; the shape does not change.
- **Rows of the outage screen:** a line is `:not_applicable` (D4); a line that IS a
  lone generator's outage carries that generator's verdict.
- **A limit set with no limit at all is refused**, as is a rate without its window and
  a window without a rate; every limit must be finite and positive.

**Found, not planned.**

1. **The preset alone splits the two screens, both ways** — the plan expected to
   *build* a disagreement fixture with a chosen limit (M8 claim (e)); none was needed.
   Mesh, constant power, losing G3: DC 0.19324 Hz passes 0.2, AC 0.20022 Hz fails (its
   losses deepen it past the limit by 0.2 mHz). case9, default loads, losing G1: DC
   0.40116 Hz fails, AC 0.19505 Hz passes (the sagging voltage sheds load). On the
   two report grids with the preset, every other generator outage fails at both
   fidelities except the mesh's default-load G3, which passes at both. This is a
   statement about the invented droop (D3), not a result.
2. **Machine ids cannot tell two screens apart**: case9 and the mesh both have G1–G3,
   so the first identity check let a case9 comparison be judged against the mesh. The
   comparison carries only machine ids and, per solved outage, one entry per branch, so
   the check now reads both; the `OutageScreen` form checks branch ids as well. Found by
   the test's own refusal check, before any sabotage.
3. **The plan's "a few mHz either side" cannot tell `<` from `≤`.** The anti-vacuity
   pair (±2 mHz around the closed form `−P₃/Σ(1/R + D)`, exact to 1e-14 relative) is
   kept, and a limit set to exactly `|Δf|` — read from the verdict's own arithmetic —
   passes while one ulp below fails. That is the check that caught S2.
4. **Every fixture runs at 50 Hz**, so a missing or hard-coded `f0` is invisible on
   all of them; a 60 Hz copy of the mesh (same per-unit `Δω`, bit for bit) crosses a
   0.21 Hz limit that the 50 Hz grid passes.

**The gate.** `screen_snapshot.jl` (every field of `outage_screen` on both report grids
and both load models, then the script's report) at HEAD (`330ddb5`) before the first
edit and after: byte-identical.

**Sabotages** (`docs/evidence/gridsim-m9/step4/`, where S1–S11 are `mutate.py`'s
M1–M11; each written down before the run, each red; the check that went red is the
one written for it):

| | Sabotage | Red |
|---|---|---|
| S1 | `Δf ≤ lim` (no `abs`) | 12 — the positive control (−10.94 Hz "passes") |
| S2 | `<` for `≤` | 1 — the limit set exactly on the value |
| S3 | `f0` dropped | 15 |
| S4 | `f0` hard-coded to 50 | 2 — only the 60 Hz copy |
| S5 | the no-value guard dropped | 6 — the refusals and AC's `:no_solution` come out `:fail` |
| S6 | DC judged on AC's `Δω` | 14 + 1 error |
| S7 | only falls judged (`−Δf ≤ lim`) | 1 — the rising frequency |
| S8 | AC's `:no_solution` judged | 2 |
| S9 | the dip given the settled verdict | 3 |
| S10 | a lone-source line ignores its machine | 12 |
| S11 | the identity check by machine ids only | 1 — case9's screen against the mesh |
