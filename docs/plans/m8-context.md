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
  3. **Its misses have a direction that can be stated before they are seen.** A
     rating is in MVA and the DC flow is `P` alone; `|S| ≥ |P|`, so the reactive
     term can only make DC **under**-report loading — from that cause alone every
     miss is "DC says fine, AC says overloaded". Angle linearisation, losses and
     voltage magnitude can push either way. They are isolated one at a time:
     lossless branches, constant-power loads and `V_set = 1` first, then each
     cause switched back on. The run is then repeated on `Load`'s **default**
     constant-impedance loads, because M6 step 7 found a claim that flipped there,
     and an outage moves voltages, which moves what those loads draw. An
     `S_base`-invariance check ships with it (M6 step 7's one-factor-short
     mutation, again).
  4. **It cannot see voltage at all — measured at step 0, and the larger
     miss.** On our case9-without-line-charging at its published 315 MW, the DC
     screen passes all six ring outages (worst 79.3 % of a rating), while
     `ac_powerflow` refuses two of them for voltage: `|V|` = 0.873 pu at B5 after
     losing L45, 0.757 pu at B9 after losing L94. At 400 MW, DC flags one overload
     (100.7 %), and AC refuses five of six for voltage and fails to converge on
     the sixth. **Caveat, stated with the number:** this model has no line
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
     brute force, because nothing was thresholded.
  2. **What a split means is a decision, not an error.** case9's three bridges
     are exactly its three generator connections, so losing L14 *is* losing G1.
     Whether a bridge whose far side is a lone source is screened as that source's
     outage (Hurdle 15) or reported only as a split is decided in the plan, by
     name. Until then it is a split.

  The outside checker's behaviour at a bridge is a finding about the **oracle**,
  not a hurdle, and lives in D1.

- **Hurdle 15 — Who picks up a lost generator, and what the dynamic tiers
  settle to.** A static screen must say where a tripped generator's power comes
  from. The user chose "the way the grid's own speed control shares it" (D2).
  Read off `swing_vertex!` (`src/engines/swing.jl`, lines 221–237), that is
  **not** droop alone. At a settled `Δω`, machine `i`'s extra output is
  `−Δω·(1/Rᵢ + Dᵢ)` on the system base, and a machine whose governor reaches its
  headroom (`Pmax − P0`) stops at exactly that, while the rest share the remainder.
  Five measurable claims:
  1. **The static rule matches a simulated trip.** Solve
     `Σᵢ min(−Δω·(1/Rᵢ + Dᵢ), headroomᵢ…) = P_lost` for `Δω`, and the per-machine
     pickup equals the swing tier's settled `TripGenerator` run, to the solver's
     tolerance and to a band stated before the gap is seen. The swing tier is
     lossless, so this is checked against the DC screen. The repo's damping term
     acts only through `ω`; whether the swing tier's loads add a frequency term of
     their own is **not yet read** and is the first thing the step checks.
  2. **Damping is load-bearing.** A zero-damping fixture must reduce to droop
     alone, and a damped one must differ from droop alone by the predicted
     amount. Both are run, so the damping term cannot be dropped silently.
  3. **The cap redistributes.** A fixture where one machine hits its headroom
     must give that machine exactly its headroom, the others the remainder at a
     larger `|Δω|`, and the swing tier must agree. The swing tier saturates *in
     the derivative* (the M1 rule), so its settled value is the same fixed point.
  4. **No speed control means no defined split, and that is refused by name.** If
     `Σ(1/Rᵢ + Dᵢ) = 0` over the remaining machines (or every one is capped
     before the loss is covered), there is no steady state to report. case9 as
     the M6 test builds it (`R = Inf`, `D = 0`) is exactly this case, so it needs
     droop data before it can screen a generator outage, and that data is
     declared invented wherever it appears.
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

## D2 — A lost generator's power is shared by droop **and damping**, capped at headroom (2026-10-06, the user's choice)

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
`−Δω·(1/Rᵢ + Dᵢ)` on the system base, no machine beyond its headroom, with `Δω`
whatever makes the pickups cover the loss.** That keeps the independent check
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
