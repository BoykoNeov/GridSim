# M8 context — decisions, and what the steps actually measured

Companion to `m8-plan.md` (the how) and `m8-tasks.md` (the checklist). This file
is where a decision is argued once, with the measurement behind it, so nobody
re-litigates it from the code. Read it before disagreeing with the plan.

Convention carried from M2–M7: decisions are `D<n>`, numbered in the order they
were *taken*, not the order the steps run. A section headed "What step N measured"
is added underneath a decision when a step either confirms it or destroys its
stated reason.

---

## D0 — Why this milestone, and the hurdles it exists for (named BEFORE the plan)

M7's close left `docs/plans/README.md`'s hurdle list empty a third time, and said
the next milestone names its hurdle before any plan prose. This section was
written first (2026-10-06), after a step-0 measurement (D1) and before the plan.

The topic was the user's choice (2026-10-06), picked from `SPEC.md` §9 item 8
("national scale … batched/GPU contingency"): **single-outage screening** — "what
if this one element fails", asked of every element in turn. The user chose it over
batched/GPU runs and over the geographic map, and chose to cover **generators as
well as lines**, with a lost generator's power **shared the way the grid's own
speed control shares it** (D2). Neither the GPU nor the map is in M8 (D5).

**Why "loop over outages and re-solve" is not enough on its own.** Brute force
needs nothing new: rebuild `NetworkModel` without the element and call
`dc_powerflow` or `ac_powerflow`. What makes screening a subject is that nobody
screens that way at scale — they use a **shortcut**, the line-outage factors
derived from the linear network, which turns each outage into a rank-one update of
one base case. The three hurdles are where that shortcut, and the brute force it
stands in for, stop meaning what they appear to mean.

- **Hurdle 13 — A shortcut that is exact on its own model and blind on the real
  one.** The line-outage factors are an exact identity *of the DC power flow*: the
  post-outage flow on line `m` after losing `k` is `f_m + LODF_mk·f_k`, with
  `LODF_mk = PTDF_m,k / (1 − PTDF_k,k)` in transfer terms. Exact there, and an
  approximation of everything the DC flow drops. Four measurable claims:
  1. **Exact against its own model.** Our factors reproduce rebuild-and-re-solve
     DC flows to round-off on a meshed fixture with a bus of degree ≥ 3 and
     unequal reactances, and sabotages placed **in the factor code** go red. The
     factors and the brute force share `_dc_susceptance` and `bus_injections`, so
     a sabotage there is invisible to this comparison by construction; those two
     lean on M6 step 2's independent three-bus check instead. M6 step 2 found
     superposition blind to a wrong *linear* map, and these factors are linear —
     so the discriminator is the algebra of a fixture with no symmetry, not a
     linearity test.
  2. **The obvious fixture is blind, predicted.** MATPOWER case9's meshed part
     is a single six-bus ring. Removing any ring line leaves the rest radial, so
     every factor is ±1 or 0 *whatever the reactances are*. Pre-registered: a
     reactance sabotage in the factor code stays **green** on case9 and goes red
     on the meshed fixture. Run both, and record the green one as the finding.
     **Corrected at step 2, by algebra and by run:** the sabotage the plan named
     (the outaged line's reactance in the monitored line's place) is **red** on
     case9, because it makes each ring factor `±X_m/X_k` and the ring's reactances
     all differ. "Whatever the reactances are" holds only while the factor code's
     matrix and its weights agree with each other. The sabotage a ring cannot see
     is a **consistent** wrong set (`1/X²` in both): case9's **flows** stay green
     under it and the mesh's go red. Its **margins** still see it (D4, "What step 2
     settled").
  3. **Its miss splits into a part with a sign and a part without one.** A
     rating is in MVA and the DC flow is `P` alone. What DC misses on a branch is
     `|S_ac| − |P_dc| = (|S_ac| − |P_ac|) + (|P_ac| − |P_dc|)`. The first term is
     the reactive part, and it is `≥ 0` by algebra: it is **stated, not checked**,
     because a check of `|S| ≥ |P|` cannot fail. The second term is the real-power
     error (angle linearisation, losses, voltage magnitude). It can go either way,
     and it is **measured**, never predicted in sign. Both are reported per
     branch per outage. The causes of the second term are isolated one at a time:
     lossless branches and constant-power loads first, with **every** bus's
     magnitude held at 1. `V_set = 1` holds only generator buses and load buses
     still sag, so each load bus also gets a zero-`P` machine at `V_set = 1` with
     unlimited `Q` (whether `NetworkModel` accepts a second machine at a bus is
     checked first; `machines_at_bus` is a vector). Then each cause is switched
     back on. The run is then repeated on `Load`'s **default**
     constant-impedance loads, because M6 step 7 found a claim that flipped there,
     and an outage moves voltages, which moves what those loads draw. An
     `S_base`-invariance check ships with it (M6 step 7's one-factor-short
     mutation, again). **Run at step 3 (D6):** the ladder had to be re-ordered
     (one rung hid two changes, and the mesh could not be solved as written). With
     every bus at 1 pu and no resistance the miss is a pure loop flow, so case9's
     ring outages are blind to it. The real-power part does go both ways: negative
     enough to give a DC false alarm; on the published case9 that needs the
     default loads (constant power also lets DC exceed AC on the ladder rungs
     with a helper machine on every sourceless bus, measured at review).
  4. **It cannot see voltage at all — measured at step 0, and the larger
     miss.** On our case9-without-line-charging at its published 315 MW, the DC
     screen passes all six ring outages (worst 79.3 % of a rating), while
     `ac_powerflow` refuses two of them for voltage: `|V|` = 0.873 pu at B5 after
     losing L45, 0.757 pu at B9 after losing L94. At 400 MW, DC flags one overload
     (100.7 %), and AC refuses four of six for voltage, fails to converge on a
     fifth (L94), and solves the sixth (L67) inside every limit. (First written
     here as "five of six for voltage". Step 0's own log says four, and step 1
     re-measured four.) **Caveat, stated with the number:** this model has no line
     charging (`m6-context.md` D4), and case9's charging is reactive support, so
     part of that sag is the missing shunt and not the outage. The claim the
     milestone makes is the structural one — a screen that reads only `P` has no
     channel through which a voltage problem could appear — and the case9
     voltages are its demonstration, never its proof.

- **Hurdle 14 — An outage that splits the grid.** Losing a **bridge** (a line
  whose removal disconnects the graph) leaves `1 − PTDF_k,k = 0` in exact
  arithmetic, and the factor divides by it. In floating point it comes out near
  `1e-16`, not zero, so a threshold on it is the wrong test: a true bridge can
  sit above any cut-off, and a weak-but-real alternate path can sit below it.
  Two measurable claims:
  1. **Splits are decided from the graph, never from a tolerance.** `NetworkModel`
     already refuses a disconnected model, so brute force refuses a bridge outage
     *by construction*. The screen finds bridges with `Graphs.bridges` and reports
     each as a split, by name, and the two sets must be equal. On a constructed
     near-bridge (a second path of reactance `1e5` pu), our factors still match
     brute force, because nothing was thresholded, but **not to round-off**.
     `1 − PTDF_kk ≈ 1e-6` is a difference of two nearly equal numbers, so the
     factor loses about `eps/(1 − PTDF_kk)` of relative accuracy (roughly 1e-10
     there), and brute force does not. That band is stated here, before the run,
     and its `1/(1 − PTDF_kk)` scaling across two path reactances is the
     signature. "No threshold" costs accuracy, not correctness.
  2. **What a split means is a decision, not an error.** case9's three bridges
     are exactly its three generator connections, so losing L14 *is* losing G1.
     Whether a bridge whose far side is a lone source is screened as that source's
     outage (Hurdle 15) or reported only as a split is decided in the plan, by
     name. Until then it is a split. **The same decision covers losing the
     reference machine.** case9's G1 is the slack and L14 is its only line, so
     losing L14 is losing the slack's source, and `ac_powerflow` refuses a slack
     bus with no source. Steps 4–6 name what the screen does there (a new
     reference chosen by a stated rule, or a named refusal). It is never picked
     silently.

  The outside checker's behaviour at a bridge is a finding about the **oracle**,
  not a hurdle, and lives in D1.

- **Hurdle 15 — Who picks up a lost generator, and what the dynamic tiers
  settle to.** A static screen must say where a tripped generator's power comes
  from. The user chose "the way the grid's own speed control shares it" (D2).
  Read off `swing_vertex!` (`src/engines/swing.jl`, lines 221–237), that is
  **not** droop alone, and the cap is **not** on the whole of it. The rotor line
  carries `−D·ω` and the governor state `ΔPm` carries `−ω/R`, and the saturation
  acts on `ΔPm` **only**. So at a settled `Δω` machine `i`'s extra output is

  `pickupᵢ = min(−Δω/Rᵢ, headroomᵢ) − Δω·Dᵢ` (system base, `headroomᵢ = Pmax − P0`),

  with `Δω` whatever makes the pickups cover the loss. Two consequences, both
  from the equation and not from intuition: as long as any remaining machine has
  `D > 0` a settled `Δω` **always exists**, since damping keeps growing as
  frequency falls; and a damped machine whose governor is capped settles **above
  its `Pmax`**, by `−Δω·Dᵢ`, because that is what the dynamic tier does.
  (Corrected the day it was written: the first draft put `min(…)` around both
  terms, and a review caught it against the very lines quoted above.) Five
  measurable claims:
  1. **The static rule matches a simulated trip.** Solve
     `Σᵢ pickupᵢ(Δω) = P_lost` for `Δω`, and the per-machine pickup equals the
     swing tier's settled `TripGenerator` run, to the solver's tolerance and to a
     band stated before the gap is seen. The swing tier is lossless, so this is
     checked against the DC screen. **Two other terms can move the total, and
     both are read in the source before an assertion is written:** a frequency
     term in the swing tier's loads, if any, and a **voltage** term. If its loads
     draw by voltage, the settled pickup is `P_lost` *less the load relief* (M7
     D16 measured exactly that), and the per-machine comparison would fail for a
     reason that is not the pickup rule. So the oracle fixture uses constant-power
     loads, or accounts for the relief explicitly. It also has no infinite-bus
     machine, finite `R`, and an explicit `Pmax` above `P0`. The default
     `Pmax = P0` is zero headroom, which would leave only damping under test.
  2. **Damping is load-bearing.** A zero-damping fixture must reduce to droop
     alone, and a damped one must differ from droop alone by the predicted
     amount. Both are run, so the damping term cannot be dropped silently.
  3. **The cap acts on the governor only.** In a fixture where one machine's
     governor reaches its headroom, that machine settles at exactly
     `headroom − Δω·D` above its schedule (above `Pmax` when `D > 0`). The others
     share the remainder at a larger `|Δω|`, and the swing tier agrees, because it
     saturates *in the derivative* (the M1 rule), so its settled value is the
     same fixed point.
  4. **The refusals are exactly two, and they are named.** No steady state exists
     only when nothing left responds to frequency (`Σ(1/Rᵢ + Dᵢ) = 0` over the
     remaining machines), or when the remaining machines have `ΣD = 0` **and**
     every governor is capped before the loss is covered. With any damping present,
     a large loss gives a large `|Δω|` rather than a refusal, and the screen
     reports that `Δω` instead of hiding it. case9 as the M6 test builds it
     (`R = Inf`, `D = 0`) is the first case. So it needs droop data before it can
     screen a generator outage, and that data is declared invented wherever it
     appears.
  5. **The AC version needs a reference shared the same way.** `ac_powerflow`
     has one slack that absorbs every imbalance. After a generator outage the AC
     screen must share the lost power **and the change in losses** by the same
     rule, which is new solver work (a distributed reference). That is the cost
     the user accepted with this choice.

Hurdle 13 is the one the user's question lives in ("what does the cheap screen
miss?"). Hurdle 14 is where the arithmetic has a hole in it. Hurdle 15 is what
makes the generator half checkable: the one place a static answer has an
independent dynamic oracle already in the repo.

---

## D1 — Step 0 measured the outside checker before the plan named it

`PowerNetworkMatrices` 0.24.3 (already in `reference/Manifest.toml` through
`PowerFlows`; reached as `GridSimReference.PF.PNM`, no new package) computes
`PTDF`/`LODF` from a `PowerSystems.System`. The model was converted through the
existing `to_powersystems`. Results were mapped **by arc**, `(from, to)` bus
numbers, which `to_powersystems` makes the vertex indices, so a reordering cannot
pass for a match. Spike: `W:\temp\claude\gridsim-m8\step0_probe.jl`. The fixture
is five buses: a meshed core A–B–C–D (`X` = 0.10, 0.20, 0.15, 0.25, 0.30;
B and C of degree 3), plus a radial spur D–E (`X = 0.10`), so it has exactly one
bridge. G1 at A is the slack (150 MW) and G2 at C carries 60 MW; the loads are
80/90/40 MW, constant power.

| Measurement | Result |
|---|---|
| Index convention | `lodf[monitored, outaged]`; the transposed reading is off by 0.21 pu |
| Connected outages, ordinary reactances | checker vs our brute force: **2e-9 to 4e-9 pu** — not round-off |
| Same topology, every `1/X` exact in `Float32` (`X` ∈ {1/8, 1/4, 1/2}) | **≤ 1.1e-15** — round-off |
| … with one reactance nudged off that grid (0.125 → 0.1251) | 4e-11 to 1.5e-10 again, **except the outage of the nudged line itself**, which stays 1.8e-15 (its susceptance leaves the problem) |
| Bridge outage (D–E) | ours **refuses** by name (`NetworkModel`: not connected). The checker returns every other flow **unchanged from before the outage**: E's 40 MW of load silently vanishes, and the outage reads as harmless |
| Near-bridge, second path C–E at `X` = 1e3 pu | checker correct (1.9e-9) |
| … at `X` = 1e5, 1e6, 1e7 pu | checker wrong by **0.400 pu** on the D–E outage, i.e. the whole flow: it answers as if E were cut off, when the power actually reroutes |

What that settles:

- **The checker's factors carry single-precision rounding**, though they are
  stored in `Float64`. `BA_Matrix(ybus::Ybus)` (`BA_ABA_matrices.jl`, the loop
  after line 122) reads each branch's susceptance back out of the admittance
  matrix, `x_eq = imag(1 / Y_ft)`, and that matrix is `ComplexF32`
  (`definitions.jl` line 1: `const YBUS_ELTYPE = ComplexF32`). This is M6 oracle
  B's finding (`m6-context.md` D15) reached by a second route: the oracle is a
  floor, not a ceiling, a third time. The band against it is a statement about
  their storage. The Float32-exact fixture is the sharp check, and it needs no
  band at all.
- **At a bridge the checker answers, silently.** `_build_lodf_demand`
  (`lodf_calculations.jl`) clamps `1 − PTDF_k,k` to 1.0 below
  `LODF_ENTRY_TOLERANCE = 1e-6`, so the outage's column comes out as zeros and the
  diagonal as −1. That is "nothing else moves", not a refusal. Any comparison
  against it **must exclude bridges by our graph**, and must show, as a finding,
  that it answers there.
- **The same clamp misfires on a connected grid**, but only once a path's
  reactance reaches about 1e5 pu — `1 − PTDF_k,k ≈ X_k/X_path` crosses 1e-6
  there. No physical line has that reactance, so this is recorded and not
  claimed as a practical danger. Our side does not threshold, which is Hurdle 14
  claim 1, and the 1e5 fixture is where that is shown.

### Also measured at step 0: case9's single-outage table

Spike `W:\temp\claude\gridsim-m8\case9_n1.jl`, run on the case9-without-line-charging
network from `test/m6_economic_dispatch.jl` with constant-power loads and the
machines on the Pmax-share schedule. Its three bridges (L14, L36, L82) are refused
by construction. The six ring outages are in Hurdle 13 claim 4. That table is why
D3 exists.

---

## D2 — A lost generator's power is shared by droop **and damping**, the droop part capped at headroom (2026-10-06, the user's choice)

Offered three ways: the reference bus takes it all, shared by droop, or both side
by side. The user chose **shared by droop**, on the grounds that it is what a real
grid does in the seconds after a trip, and that the dynamic tiers settle to it.
That was an independent check already in the repo.

**The offer was imprecise, and the record says so.** It said the dynamic tiers
settle to "exactly this split". A side review the same day pointed out that M1's
notes settle on **damping plus droop** (`Δω_ss = ΔP/(D + 1/R_eq)`, the
inertia-free settling law). Reading `swing_vertex!` confirmed the review and added
a second effect: the governor stops at its headroom. So the rule M8 implements is
the one the user's reasons actually point at: **each remaining machine picks up
`min(−Δω/Rᵢ, headroomᵢ) − Δω·Dᵢ` on the system base, with `Δω` whatever makes
the pickups cover the loss.** Only the droop part is capped. The damping part is
not, so a damped machine can settle above its `Pmax`.

**And the correction needed a correction.** The first version of this section,
committed the same day, wrote the cap around both terms ("no machine beyond its
headroom"), and the user was told "each plant capped at its spare capacity". A
review read the saturation in `swing_vertex!` again: it acts on the governor
state `ΔPm` alone, while `−D·ω` sits in the rotor equation outside it. It is fixed
here and in Hurdle 15, and the user was told in plain words. The consequence that
changes the plan: with any damping present there is always a steady state, so
"the loss exceeds all headroom" is not a refusal (Hurdle 15 claim 4). That keeps the independent check
real. Droop alone is the zero-damping special case, and it is checked as one
(Hurdle 15 claim 2). The user was told the correction the same day, with pure
droop on zero-damping fixtures offered as the alternative.

The weights come from `machine_arrays`, the one place the per-unit conversion
lives (`invR` and `D` are already on the system base there). They are never
rebuilt from `Machine.R` and `Machine.D` beside it.

---

## D3 — A screen reports what each outage does; it does not throw (the blocker, settled before any step)

`ac_powerflow` throws on an overloaded branch (`_check_branch_ratings`), on a
voltage outside the band, and on a failed Newton. For a single solve that is
right. For a screen it refuses exactly the results the screen exists to find:
step 0's case9 run met all three on six outages.

**The alternative that was rejected:** calling `_ac_first_round` + `_ac_newton`
directly. That path skips reactive-limit switching (it exists to locate where the
equations stop having a solution, M7 D13), so it is a *different model* from
the one the repo calls the AC flow. Every DC-vs-AC gap measured through it would
then have two causes.

**The decision:** the screen runs the same solve `ac_powerflow` runs, switching
included, and classifies each outage's outcome instead of throwing on it:

| Outcome | Meaning |
|---|---|
| `:secure` | solved, inside the band, every branch within its rating |
| `:overload` | solved and inside the band; the branches over their rating are listed, with how far over |
| `:voltage` | solved, but a bus is outside the band; the buses are listed with their `|V|` |
| `:no_solution` | the Newton did not converge, or switching did not settle. Reported, never retried with a different start |
| `:splits` | a bridge (Hurdle 14); not solved at all |

The guards on the **base case** stay exactly as they are: a screen run on a model
whose own pre-outage flow is refused refuses as a whole, by name. This is done by
**splitting** the existing checks into named pieces, the way M6 step 3 split
`_check_power_flow` (`m6-context.md` D10). It is never done by copying their
constants. `ac_powerflow`'s own behaviour does not change by a bit, and the
existing suite plus M5's recorded criterion values are the proof.

`:voltage` before `:overload` is the band-first order `ac_powerflow` already
uses, for the same reason: a branch flow on a collapsed-voltage solution is not a
flow on the operating point anyone asked about.

### What step 1 settled (2026-10-06)

The split is one solve read two ways, not two solves. `ac_powerflow`'s body became
an internal `_ac_solve` that returns a verdict. `ac_powerflow` throws the verdict's
exception, and `_ac_powerflow_outcome` returns `(outcome, detail, solution)`. Each
check gained a piece that returns **every** offender. The throwing check takes the
first, with the identical message. **The order the checks run in is written once**,
in `_ac_solve`, and it is the order the throws already ran in: the Newton or the
switching cap, back-off, the band, the ratings, the residual, the slack inverter's
rating.

**The four refusals the table above did not name**, each decided by name:

| Refusal | Outcome | Why |
|---|---|---|
| back-off (a limited bus on the wrong side of its setpoint) | `:no_solution`, `reason = :backoff` | the solver cannot stand behind the answer (M6 D12) |
| residual over `1e-10` after a converged Newton | `:no_solution`, `reason = :residual` | the same. Reached through the solve by loosening its own `abstol`: at 1e-6 case9 stops at 3.0e-7 (first written as unreachable, which was never tried) |
| a grid-forming slack over its rating | `:overload`, `kind = :inverter_slack` | the network solved, and a source cannot carry it, like a branch |
| a slack bus with no voltage source | still **throws** `ArgumentError` | losing the reference's source is the Hurdle 14.2 decision (steps 4–6), not this function's |

**What each outcome hands back.** `:secure` and `:overload` carry the
`ACPowerFlow`, because an overload's flows are the result step 3 compares with DC.
An overload whose residual also fails carries `nothing`, and the same loose `abstol` reaches that branch. `:voltage` carries
`nothing` and lists every bus with its `|V|`, for this section's own reason: a flow
on a solution outside the band is not a flow anyone asked about.

**Found, not planned: the planned gate could not see this step's code.** M5's
criterion harness (`scripts/iberia_two_area.jl`) never calls `ac_powerflow`. It
reaches only the detailed tier's `_check_power_flow`, so it covers the split pieces
on their passing path and nothing else. A second capture was therefore taken at
HEAD before the first edit (`W:\temp\claude\gridsim-m8\ac_snapshot.jl`). It records
83 cases: case9 at 315 and 400 MW, constant-power and default loads, `±0.3` pu
reactive limits (switching binds), ratings at 60 % (overloads), every outage, the
grid-forming slack at 50 and 60 MVA, and a slack with no source. For each it prints
every `ACPowerFlow` field at round-trip precision, or the exception type and full
message. The cases come out as 20 solved, 20 voltage, 6 overload, 11 Newton
failures, 2 named refusals, and 24 bridges the model refuses. Before and after
the edit the captures are **identical** (MD5 `5a5873deefd295a470dc5f71260be7ba`,
once three precompilation lines are removed). M5's 169 values are identical too
(value-line MD5 `1eeed2cc84937cb544eee5c35d0091cf`).

**Found, not planned: M5's recorded values moved at M7's close, and nobody
re-captured them.** Today's HEAD capture differs from every M7 capture in 89 of
169 lines. The differences are about 1e-5 relative (`av.over` 1.02952749 →
1.02952570), solver step counts change (`av.n_steps` 96811 → 56529), and every
`over` stays on its side of 1. Attributed by two runs, not by argument:

- the pre-rename commit `bf52e09` on today's manifest gives today's values (0
  differ), so the `derivative_discontinuity!` rename moved nothing;
- today's code on the manifest saved before M7's close
  (`W:\temp\claude\m7-close\Manifest-root.toml`, `SciMLBase` 3.56.1) reproduces
  M7 step 6's capture exactly (0 differ).

So the dependency re-resolve at M7's close moved them (`SciMLBase` 3.56.1 →
3.57.0 and 19 other bumps). No test count moved, because every assertion on them
carries a tolerance. "Bit-identical" in this repo means within one manifest. Step
7's close therefore has its own box: re-run both captures after the re-resolve and
record the new digests next to the old ones, because "counts re-measured" is the
wording that let this through at M7's close.

**The planned anti-vacuity mutation was blind as written.** Moving ratings ahead
of the band changes an outcome only where a voltage violation and an overload
occur on the same solve. L45 at 315 MW has no overload (B5 at 0.873 pu, every
branch within its rating), so the reorder still reports `:voltage` there. The
plan's "or `:secure`" was unreachable under any reorder. Case9 offers a natural
fixture where the two do coincide: **L89 out at 400 MW** puts B9 at 0.854 pu and
L56 at 152.6 MVA against 150. The precedence test uses it and shows the masked
overload from the same solve. The reorder turns that case into `:overload`.

---

## D4 — The outage factors are a compiled view, never stored, never dense

`CLAUDE.md`'s "one canonical model" and "sparse from day one" both bind here.
The factors are **derived from `NetworkModel`** each time a screen runs, never kept
beside it. A full `PTDF` is dense (branches × buses), which is exactly the shape
the repo refuses for an admittance matrix. So the screen factorises the reduced
susceptance matrix **once**, sparsely, and computes each outage's column with one
solve against that factorisation. Only the column in use is ever held. On case9 that
looks like ceremony, and it is what lets the same code run on a national model.
It is pinned by the same `nnz` check M6 step 2 uses.

### What step 2 settled (2026-10-06)

`dc_line_outages(net)` returns a `DCLineOutages`: the base `DCPowerFlow`, a split
flag per branch from `Graphs.bridges`, `1 − PTDF_kk` for every branch (bridges
included, so their round-off is visible), and per outage the post-outage flow on
every branch, with the outaged branch exactly `0.0` and a split left empty. The
`flow` table is branches × branches because that is the size of the question; the
matrix that would be dense, the PTDF, is never formed. Judging flows against
ratings is step 3's.

**One susceptance vector.** The screen reads `b = 1/X` once and uses it for both
the matrix (through a new `_dc_susceptance` method that takes the susceptances) and
the per-branch flow weights. Two reads could disagree, and a ring cannot see that
disagreement (below), so it is not left possible.

**Measured, worth not re-deriving:**

- **A bridge's margin has no reliable sign.** case9's three come out −2.2e-16, 0.0
  and 0.0. A connected grid with a 1e7 pu second path comes out 1.0e-8, under the
  checker's 1e-6 clamp. The graph is the only test that answers the question.
- **Near a bridge, the error is the factors' alone.** The rebuild stays 1.1e-16
  from an exact answer at second-path reactances of 1e3, 1e5 and 1e7 pu, while the
  factors drift by 7.9e-13, 2.3e-11, 4.5e-9, inside the `eps/(1 − PTDF_kk)` band
  Hurdle 14.1 stated (0.035–0.052 of it). The prediction that the rebuild would
  drift too, because its matrix is as ill-conditioned, was wrong: the badly
  conditioned direction is the far bus's angle, and no other flow reads it.
- **The case9 blindness belongs to a different sabotage than the plan named** (D0,
  Hurdle 13.2, corrected there). Wrong reactance in the weight only: red on case9.
  A consistent wrong set: case9's flows green, the mesh's red. case9's margins
  are NOT blind to it: on a single ring `1 − PTDF_kk = X_k / ΣX_ring`, asserted in
  closed form, and `1/X²` turns that into `X_k²/ΣX²`. (Recorded at first as "green
  on case9" outright; the run had a red margin line, and a review caught the
  overstatement.) Scaling every reactance
  by one factor is invisible on every grid, because the factors do not change, so
  it is not a sabotage.
- **A transposed index is the reactance sabotage again** when the inverse is
  symmetric (`PTDF_km = (b_k/b_m)·PTDF_mk`), so the transposition was run as the
  two flows swapped in the update instead.
- **Keeping the reference row is an equivalent change for every flow.** CHOLMOD
  factorises the singular matrix, every right-hand side sums to zero, and every
  output is an angle difference, so the null direction cancels. Only the `nnz`
  check sees it. The reference bus is a gauge: moving it moves no flow (2e-15).
- **The checker, on top of D1:** 0.012 of its storage band on ordinary reactances,
  0.031 of round-off on Float32-exact ones; at a bridge, column ≤ 7.6e-17 and
  diagonal −1.0; at a 1e5 pu second path it leaves the far bus cut off.

---

## D5 — What M8 does not do

- **No transient stability after an outage.** Whether the machines stay in step
  through the seconds after a trip is the dynamic tiers' question and already
  answerable there (M3's out-of-step relay). A static screen says where the grid
  settles if it settles; it never claims that it does.
- **No batched or GPU runs, and no geographic map** (`SPEC.md` §9 item 8's other
  two halves). They are not chosen, and not implied.
- **No double outages.** N-2 changes the counting and the factor algebra, and
  nothing in M8's three hurdles needs it.
- **No corrective action.** Re-dispatching around an overload is the network
  optimal power flow, which stays owed on `m6-context.md` D7 criterion 4.
- **No parallel circuits.** `NetworkModel` refuses them (one branch per bus pair).
  Real cases carry them, and supporting them is its own decision.
- **No line charging.** Hurdle 13 claim 4's caveat is a consequence of this, and
  it is stated wherever a case9 voltage appears.

---

## D6 — The AC line screen and the comparison: four decisions taken at step 3 (2026-10-06), and what it measured

Taken before any run, and written to `W:\temp\claude\gridsim-m8\step3_predictions.md`
with the predictions:

1. **The comparison takes the model: `compare_line_screens(net, dc, ac)`**, not the
   plan's `(dc, ac)`. An overload is a flow judged against a rating, and
   `DCLineOutages` carries flows and no ratings. Giving the screens a copy of the
   ratings would be a second place the same fact lives. The DC flows are judged by
   the very comparison the AC solve uses (`_rating_violations`), on `|f|`, because
   a DC flow may run against a branch's declared direction and a rating does not
   care. Both screens' branch lists are checked against the model, and a mismatch
   is refused.
2. **The DC base case is judged, not refused.** The AC screen refuses a base that
   `ac_powerflow` refuses (D3). A DC base over a rating is reported in
   `dc_base_over` instead, because it is already a disagreement between the two,
   and refusing would hide exactly what the comparison exists to show.
3. **The two parts of the miss are taken on one end convention, the rating's.**
   `S = max(|S_from|, |S_to|)`, `P_ac = max(|P_from|, |P_to|)`, `P_dc = |f|`;
   reactive `= S − P_ac`, real `= P_ac − P_dc`. With both maxima on the same footing,
   `reactive ≥ 0` holds by algebra, end by end. Mixing ends would break that, and it
   would be a claim nobody could test.
4. **AC solutions are read by branch id.** Each one is one branch shorter than the
   model, so after the outaged branch every index is one lower. Reading by
   position is the step's most likely silent bug, and it was run as a sabotage (T1).

### The ladder, re-ordered before any test

Hurdle 13.3 asks for the real-power miss with its causes switched on one at a time.
The plan's order (every bus at 1 pu, then `R`, then "realistic `V_set`", then the
default loads) hid two changes in its third rung: removing the helper machines and
restoring the published setpoints. Run as written, with the helpers off and every
setpoint at 1 pu, **the mesh's own base case sags out of band** (bus D at 0.847 pu
with the first invented resistance `R = X/5`, and at 0.877 with `X/10`), so that rung
has no screen at all. The shipped ladder, one change per rung:

| Rung | Change | What it isolates |
|---|---|---|
| A0 | lossless; a zero-P, unlimited-Q helper machine at 1 pu on **every** bus without a source; every setpoint 1 pu | the angle linearisation alone |
| A1 | + branch `R` | losses |
| A2 | + published `V_set` (helpers still on) | the setpoints |
| A3 | − helpers: the published model | load and junction voltages free |
| A4 | + `Load`'s default constant-impedance shares | voltage-dependent draw |

"Every bus without a source" includes junction buses: case9's B4, B6 and B8 carry
nothing and sag like the load buses. The plan's "check that a second machine at a
bus is accepted" is moot, because a helper only goes where there is no machine. The
mesh's `R = X/10` and setpoints 1.05 / 1.04 are invented and declared. Every rung
asserts that no reactive limit binds, so case9's ±3 pu limits are inert throughout
and no rung is secretly a different switching state.

### What step 3 measured

- **At A0 the miss is a pure loop flow.** Every injection equals the DC one (no
  losses, every `|V|` exactly 1, constant power), so `P_ac − P_dc` sums to zero at
  every bus: ≤ 2.5e-14 on every outage of both fixtures, against a band of 1e-11
  (ten times the Newton's `abstol`). A loop flow is zero on a tree, and **every
  case9 ring outage leaves a tree**: there A0's miss is ≤ 2.4e-14, while case9's
  intact ring shows 5.0e-5 and the mesh's outages show 2.4e-5 to 3.4e-3. case9 is
  blind a second time, for the same structural reason as Hurdle 13.2, and its
  intact ring is the control that A0 is not zero by construction.
- **Each later rung moves the intact model's miss by more than 1e-3**, asserted, so
  no cause looks absent because its rung did nothing. From A1 on, the loop-flow
  identity breaks by about the losses (3.7e-2 on case9's intact model).
- **case9, no line charging, as predicted at step 0.** At 315 MW the DC screen
  passes all six ring outages and the AC screen refuses L45 (B5 0.873) and L94 (B9
  0.757) for voltage: `:dc_blind`. The other four agree, and the bridges split. At
  400 MW five of six outages are `:dc_blind`, and the DC screen's only overload (L89
  out, L56 at 100.7 %) is an outage the AC solve refuses for voltage anyway. A
  voltage refusal has no AC flows, so no miss is reported for it.
- **The two directions of disagreement, each on a natural fixture.** With L14
  re-rated to 150 MVA, losing L89 leaves 96.0 MW on it in DC, 105.3 MW of real
  power in AC (the slack also covers the losses) and 159.7 MVA: `:dc_missed`, and the reactive part is what
  crosses the rating, because L14 carries the slack's reactive output. The
  opposite, `:dc_false_alarm`, needs **the default loads on the published case9**: with L94 at
  105 MVA, losing L67 gives 109.8 MW in DC and 100.4 MVA in AC, because the AC
  voltages sag and constant-impedance loads draw less. The same rating on
  constant-power loads overloads at both (121.1 MVA). On the published
  constant-power models no AC apparent power fell below its DC flow (smallest
  margin +0.16 MW, case9 at 315 MW); on the default loads DC exceeds AC by up to
  12.7 MW (case9 315), 23.0 (case9 400) and 19.2 (mesh). M6 step 7's rule a second
  time: a claim made on constant power is re-run on the default. **First written
  as "exists only on the default loads", and wrong:** constant power lets DC exceed
  AC too on every ladder rung with a helper machine on each sourceless bus (case9
  A1/A2 −6.3 MW; mesh A0, which is lossless, −0.15; mesh A1 −0.51). The shared
  feature is the helpers, not resistance (A0 has none) nor 1 pu everywhere (A2
  carries the published setpoints): on the mesh even the lossless loop flow can
  push one branch's |P| below its DC value, and case9's A0 hides it only because
  each outage leaves a tree. A first rescoping said "1 pu with resistance on" and
  was wrong too. The scoped claim is what the test asserts.
- **Positive control**, L94 rated 100 MVA. Its DC flow runs against its declared
  direction (−125.0 MW after L89 out), which is what makes a forgotten `abs`
  visible.
- **All eight sabotages went red exactly where predicted.** The one worth keeping:
  reading the AC solution by position was **invisible** to the `:dc_missed` test
  at e857b52, because L14 sits before the outaged L89 and the indices still agree
  there (the review follow-up added an L94 by-id check to that test, which now
  catches it). It is
  seen by the false alarm (L94 is past the end of an 8-branch solution) and by the
  A0 tree check. The grid-forming-slack branch of `:dc_blind` had no fixture until
  its sabotage was written, and got one (a triangle whose slack is rated 0.1 %
  above its own intact output).
- **Review follow-up.** `dc_base_over` and `:mixed` had no fixture; both got one
  (step 2's mesh on default loads with DE at 39: 40.0 MW DC against 37.9 MVA AC;
  default-load case9 with L94 at 105 and L82 at 125, L67 out), each with a
  sabotage red only in its own test.
