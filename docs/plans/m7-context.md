# M7 context — decisions, and what the steps actually measured

Companion to `m7-plan.md` (the how) and `m7-tasks.md` (the checklist). This file
is where a decision is argued once, with the measurement behind it, so nobody
re-litigates it from the code. Read it before disagreeing with the plan.

Convention carried from M2–M6: decisions are `D<n>`, numbered in the order they
were *taken*, not the order the steps run. A section headed "What step N measured"
is added underneath a decision when a step either confirms it or destroys its
stated reason.

---

## D0 — Why this milestone, and the hurdles it exists for (named BEFORE the plan)

M6's close left `docs/plans/README.md`'s hurdle list empty and said, in so many
words, that **M7's first act is to name the hurdle it exists for, before any plan
prose** — the thing M6 had to do after the fact (`m6-context.md` D0). This section
was written first, and the plan below was written against it.

The topic was the user's choice, carried from before the M6 close: **renewables
and grids with little spinning inertia**, with `SPEC.md` §7.6's owed third lesson
(inverter-based resources, "IBR behaviour — no tier, and UN-SCHEDULED") folded in
under it. `SPEC.md` §9 item 7 names the same thing ("Renewables / low-inertia
studies — the M1 lesson, scaled up"). So this time the roadmap and the hurdle list
point the same way; the hurdles are what make it a milestone rather than a
parameter sweep.

**Why "scaled up" is not enough on its own.** `entsoe-iberia-reproduction.md` §1 (a)
already showed that the M1 version of the lesson needs no new physics: a PV block
is `GeneratingUnit(:PV, S, 0.0, P0, Inf, P0)` — zero inertia, zero droop, zero
headroom — and "less inertia ⇒ steeper RoCoF" is already a regression test,
including the all-inverter corner. Re-running that at larger shares would teach
nothing the M1 closed form does not already say. What the repo cannot express is
everything that makes an inverter *not* a machine with small numbers, and that is
where the three hurdles are.

- **Hurdle 10 — Frequency without a rotor.** Every frequency the repo reports is
  a rotor speed, or the inertia-weighted mean of rotor speeds (`ω_coi = Σ Hᵢωᵢ / Σ
  Hᵢ`). An inverter has no rotor. A grid-following one has only a phase-locked
  loop's *estimate* of its bus frequency, and in the detailed tier a bus angle is
  an algebraic unknown, so "bus frequency" is the derivative of something that
  jumps at every event. Three measurable claims:
  1. **A phase jump reads as a frequency spike.** A step in a voltage *angle*
     changes no frequency anywhere, yet a PLL reports one, of a size fixed by its
     gains. Measured at step 0 in PowerDynamics: a 0.05 rad step at the slack
     drove `SimpleGFL`'s PLL to `ω = 1.00644` pu — a 0.32 Hz excursion at 50 Hz
     from an event with no frequency content. Our PLL must reproduce the
     **closed-form** peak of its own second-order response, not just "a spike".
  2. **Measured RoCoF depends on the measurement.** The windowed RoCoF a relay
     reads (`windowed_rocof`, the report's 500 ms window) and a PLL-derived one
     differ from the centre-of-inertia value by amounts that are functions of the
     window and the gains. The repo reports all three under three names and never
     one of them as "the" RoCoF.
  3. **The weighting stops being defined.** With every synchronous machine
     displaced by grid-following inverters, `Σ Hᵢ → 0` and `ω_coi` is `0/0`. The
     read-out must **refuse** there (by name), not return `NaN` or a number —
     and, before that corner, a model with no voltage source at all has no
     operating point to report a frequency *of* (a grid-following inverter needs
     a grid to follow; D5).

- **Hurdle 11 — A converter that is secretly a machine, and one that is not.**
  A grid-forming inverter with power-frequency droop and a first-order power
  filter is **algebraically identical** to a classical swing machine with
  `2H = τ_p/K_p`, `D = 1/K_p`, `P_m = P_set` on the same power base — provided its
  voltage magnitude is held (`K_q = 0`). Substituting `Δω = −K_p(P_filt − P_set)`
  into `τ_p·Ṗ_filt = P_e − P_filt` gives `(τ_p/K_p)·Δω̇ = P_set − P_e − Δω/K_p`,
  which is `swing_vertex!`'s line with `ΔPm = 0`. That is an exact oracle of the
  kind this repo prizes (`m5-prestudy.md` §3's degeneration, again) — and it is
  also a trap: a check that builds the inverter *as* a `Machine` with converted
  numbers reads its answer from its own source, which this repo has been caught by
  twice (M6 step 3's six sabotages). And it means `SPEC.md` §7.6's sentence "an
  inverter … has no swing equation, so it is not a machine with different numbers"
  is **true for grid-following and false for droop grid-forming** — pre-registered
  here as a prediction, and to be corrected in `SPEC.md` only once step 3 has
  measured it on our side. Three measurable claims:
  1. Ours-against-ours, the inverter built from its own droop states, agrees with
     the converted machine to round-off on a network-side disturbance, with two
     mutations opening a gap: `K_q ≠ 0` (voltage no longer held) and `K_p` on the
     wrong power base.
  2. **The equivalence is not total, and where it breaks is predicted.** A step in
     the inverter's *setpoint* `P_set` moves `ω = 1 − K_p(P_filt − P_set)`
     **instantly** by `K_p·ΔP_set`; a machine's speed is a state and cannot jump.
     So under a setpoint step the two differ by exactly that jump at `t⁺`, and
     under a network disturbance they do not differ at all.
  3. A grid-following inverter has no such equivalent — it holds a **current**,
     not a voltage, and needs something else to set the voltage it follows. Its
     own closed form is an **existence** limit (D5): with an ideal current source
     behind a reactance `X` from a stiff source `|V_g|`, an operating point exists
     iff `X·i_d ≤ |V_g|`, and the power it can deliver at unity power factor peaks
     at `P = |V_g|²/(2X)`, which is reached first.

- **Hurdle 12 — Time scales a phasor tier cannot honestly hold.** The detailed
  tier is a phasor (RMS) model with algebraic branches: it assumes the network
  settles instantly relative to what it simulates. An inverter's inner current
  loop runs in milliseconds and a PLL at ~10 Hz — at or above the scale where that
  assumption is safe. PowerDynamics' `SimpleGFL` carries a **dynamic** filter
  inductor (`(X_f/ω_base)·di/dt`, a 0.16 ms time constant at its defaults) and a
  PI current loop inside an otherwise algebraic network. Our grid-following model
  will be an **ideal** current source (current equals its setpoint, no filter
  state). The measurable claim: the gap between the two is a **fidelity** gap that
  **shrinks as their current loop is made stiffer**, identified by that
  signature and never absorbed into a band — and the existence limit of Hurdle 11
  is an **upper bound** on where their model loses synchronism, not a prediction
  of it (their extra dynamics can lose stability before the limit). What a phasor
  tier cannot represent at all (sub-synchronous interaction, anything needing
  electromagnetic transients) is named in D8 as out of scope, not implied.

Hurdle 10 is the one the user's question actually lives in ("what does low
inertia *do*?"). Hurdle 11 is what makes the milestone checkable. Hurdle 12 is
where the milestone admits what it cannot see.

---

## D1 — Step 0 measured the outside components before the plan named them

M4's plan named the wrong PowerDynamics component and the source said so
(`m4-context.md` D13). So both inverter components were **built and run** in
`reference/`'s environment at its current manifest before this plan mentions them.
Spike: `W:\temp\claude\m7-step0\spike_pd_inverters.jl`. Case: a two-bus system,
`SlackAlgebraic` at `V = 1∠0`, one lossless line `X = 0.2` pu, the device at bus 2
dispatched at `P = 0.5` pu, `S_base = 100` MVA, `f0 = 50` Hz; disturbance a
0.1 rad step in the slack's voltage angle at `t = 0.5` s (a **network-side**
disturbance — see Hurdle 11 claim 2 for why not a setpoint step); `Rodas5P` at
`reltol = abstol = 1e-10`.

| Case | Initialises | Flat-run residual | Result |
|---|---|---|---|
| (a) `Library.IdealDroopInverter`, `K_p = 0.05`, `τ_p = 0.1`, `K_q = 0` | yes, `P_set = 0.5`, `V_set = 1.0` solved by their `initialize_from_pf` | 1.3e-13 | angle swing 0.156 rad |
| (b) `Library.Swing`, `M = τ_p/K_p = 2`, `D = 1/K_p = 20`, `V = 1`, `P_m = 0.5` | yes, `θ₀` = (a)'s `δ₀` to 3e-15 | — | **max \|δ_(a) − θ_(b)\| = 5.4e-11 rad, max \|ω_(a) − ω_(b)\| = 7.2e-12 pu** |
| (a′) as (a) with `K_q = 0.05` | yes | — | max \|δ − θ_(b)\| = **1.1e-4** rad — the mutation opens a gap 2×10⁶ larger |
| (c) `Library.ComposableInverter.SimpleGFL`, defaults, `pfPQ(P = 0.5, Q = 0)` | yes, `i_set_d = 0.502545`, `i_set_q ≈ −3e-14` | 2.0e-13 | PLL `ω` ∈ [0.99974, 1.00644] after a 0.05 rad slack angle step |

What that settles:

- **Hurdle 11's equivalence holds on the outside implementation**, at the solver
  tolerance, and the `K_q` mutation is not vacuous. So when our own check runs,
  a disagreement will be ours.
- **Their `K_p` is on the SYSTEM base.** `IdealDroopInverter` measures
  `P_meas = u·i` from terminal quantities, which PowerDynamics denominates on
  `S_base`. Our `Machine` carries `H` and `D` on the machine's **own** rating. So
  the inverter's gains must be declared on one base and converted in exactly one
  place — and the wrong-base mutation is the second anti-vacuity check.
- **`SimpleGFL` lives at `Library.ComposableInverter.SimpleGFL`**, not
  `Library.SimpleGFL` — the name the source file suggests and the export list
  does not carry at top level. Its states are the PLL's three (`θ`, `Δω`, the PI
  integrator — it is `PLL_LPF`, with a 300 Hz output filter), the current loop's
  two integrators, and **two filter-current states**: the dynamic inductor of
  Hurdle 12. Its initial current matches the ideal-current-source closed form
  exactly: `V_t = √(1 − X²i_d²) = 0.99494`, `P = V_t·i_d = 0.50000`.
- **Hurdle 10 claim 1 is real on the outside model**: a 0.05 rad phase step,
  which changes no frequency anywhere, reads as a +0.32 Hz frequency excursion
  through their PLL.

---

## D2 — A new `Inverter` type, not a `Machine` with `H = 0`

`Machine`'s constructor rejects `H = 0` and says why in its own comment: the swing
equation divides by `2H`, and "a zero-inertia converter … as a vertex in a swing
network has no differential state, which is the grid-forming/following tier, not
this one." That comment was written in M2 as a pointer to this milestone.

Three reasons for a separate type rather than relaxing the guard:

1. **A grid-following inverter has none of `Machine`'s states.** No rotor angle,
   no speed, no flux, no field voltage. A `Machine` with most fields meaning
   "absent" is a second source of truth about what a component *is*.
2. **The equivalence oracle needs two independent constructions.** If a
   grid-forming inverter were stored as a `Machine` with `H = τ_p/(2K_p)`, the
   step-3 check would compare a machine with itself.
3. **Every consumer that reads `net.machines` today must see an inverter
   explicitly or refuse it by name.** A new collection makes that a compile-time
   fact about each reader rather than a hope that each one checks a flag.

One struct with a `mode` field (`:grid_forming` / `:grid_following`) rather than
two types: `NetworkModel` keeps a concretely typed `Vector{Inverter}` (SPEC §6's
type-stability rule), the two modes share their rating, dispatch and location, and
the fields one mode does not read are defaulted and documented as unread — the
precedent `Machine` already sets for its tier-specific fields.

Gains are declared on the **inverter's own rating**, like `Machine.H` and
`Machine.D`, and converted to the system base in the compiled view only (D1's
base finding). The field list is settled in step 1, not here.

### What step 1 settled

The fields are `id`, `bus`, `mode`, `S_rated`, `P0`, `Q0`; the grid-forming
`K_p`, `τ_p`, `K_q`, `τ_q`, `V_set`, `X_c`; the grid-following `K_pll_p`,
`K_pll_i`. Everything after `mode` is a keyword with a default, and the defaults
are chosen the way `Machine`'s are:

- **`K_q = 0` is the default because it is the degeneration** — the voltage is
  held, which is what makes the grid-forming inverter exactly a swing machine
  (Hurdle 11). `K_p = 0.05` and `τ_p = τ_q = 0.1` are `IdealDroopInverter`'s own
  defaults, so a default-built inverter is the one step 0 measured; `X_c = 0.1`
  is a typical filter-plus-transformer reactance and is unread outside the detailed
  tier.
- **The PLL defaults are `SimpleGFL`'s** (`2π·10` and `(2π·10)²/4`): a 10 Hz loop,
  critically damped, asserted in `test/`.
- **One rating check, and only one**: `|P0 + jQ0| ≤ S_rated`. A machine is not
  checked this way (it has a short-term overload); an inverter's switches are rated
  for their current, so a dispatch above its rating is wrong on its face.
- **Every guard fires in both modes**, including on fields that mode does not
  read — `Machine.Tg`'s precedent (data that is only sometimes read is the data
  that gets set wrong and noticed a milestone later).
- **No frequency response on the grid-following mode.** D3's table allowed "zero
  response unless given frequency droop"; step 1 gives it none, so a grid-following
  inverter in M7 is always a constant-power source. Named in the docstring as not
  here, with current limiting.

Two bookkeeping choices the plan did not spell out:

- **An inverter id may not equal a machine id.** Generation is looked up by id
  ("the unit that tripped"), so the two collections share a namespace. Loads do not
  join it.
- **The default reference bus**, with no machine in the model, is the first
  grid-forming inverter's bus — never a grid-following one's, and the first bus
  when there is neither. With any machine present the pre-M7 default is untouched,
  so no existing default moves.

**The refusal goes FIRST in every tier guard.** An inverter's bus usually carries
no machine, so where a tier's guards run "one machine per bus" before the inverter
check, the message reports the symptom (a bus with nothing on it) instead of the
cause. Caught while writing step 1's tests: `SwingEngine` and `coi_model` both had
the order wrong on the first draft.

---

## D3 — Which tier holds which inverter

| | Aggregate (`coi_model`) | Network swing (`SwingEngine`) | Detailed (`DetailedEngine`) | Power flow |
|---|---|---|---|---|
| grid-forming | virtual inertia `τ_p/(2K_p)` and damping `1/K_p` (its equivalence, used as the compiled view it is) | **yes** — voltage magnitude held *at the bus*, which is exactly this tier's convention for machines and exactly `IdealDroopInverter`'s | **yes** — behind a coupling reactance `X_c` (filter + transformer), current injected into the bus's Kirchhoff sum, like a machine; `K_q` live here | voltage-controlled bus (`P`, `|V|` given) |
| grid-following | zero inertia; zero response unless given frequency droop | **refused by name** — it is a current source, and this tier has no bus voltage to inject a current *into* | **yes** — ideal current source in its PLL's frame | load-type bus (`P`, `Q` given), sign reversed |

The swing tier's refusal is a **tier boundary, not unbuilt work**, in the words
this repo uses for the load refusal: a constant-voltage-at-the-bus network has no
algebraic voltage for a current source to set.

The grid-forming inverter in the swing tier sits at the bus with **no** coupling
reactance, and in the detailed tier behind `X_c`. That is the same asymmetry
machines already carry (`network_model.jl`'s tier note: "E′ at the bus" against
"E′ behind X′d"), and it is chosen for the same reason — each tier's convention
matches the external component it is checked against (`Library.Swing` /
`IdealDroopInverter` at the bus; `IdealDroopInverter` plus an explicit line of
reactance `X_c` against the detailed tier).

---

## D4 — The equivalence is used as an ORACLE in two tiers and as the MODEL in one

In the swing and detailed tiers, the inverter is built from **its own droop
states** (`δ`, `P_filt`, and `Q_filt` where `K_q` is live), never by converting to
a machine and calling the machine vertex. That keeps Hurdle 11's check a check.

In the aggregate tier the reverse is correct: `coi_model` is a **compiled view**
(SPEC §3.2), and the view of a grid-forming inverter is its equivalent inertia and
damping. There is no inverter state to integrate in a one-state-per-system model.
The step-2 check therefore cannot be the equivalence (it would be the view
checking itself); it is the aggregate closed forms (`RoCoF₀`, settling) with the
virtual inertia counted, cross-checked against the swing tier's run of the same
model.

---

## D5 — A grid with nothing to follow is refused, and the reference bus must hold a voltage

A grid-following inverter injects a current phased to the voltage it measures. On
a network where **no** bus carries a voltage source (a machine or a grid-forming
inverter), the detailed tier's Kirchhoff system has no solution that pins a
voltage — there is nothing to follow. That model is refused **by name** at the
engine boundary, and at the power flow the reference bus must carry a machine or a
grid-forming inverter.

As with M5 D3 and M6 D3, the *model* stays constructible (the editor must be able
to hold a half-built draft), and the refusal lives where the solve is.

---

## D6 — The existing COI read-out is extended, not redefined

`ω_coi = Σ Hᵢωᵢ / Σ Hᵢ` stays the system frequency, with grid-forming inverters
entering at their virtual inertia `τ_p/(2K_p)` (their `ω` *is* a speed in the
equivalence) and grid-following ones at weight zero. PLL readings are **per-bus
measurements under their own names**, never averaged into `ω_coi`. When the
weights sum to zero the read-out refuses (Hurdle 10 claim 3). The alternative —
defining system frequency as a PLL average — was rejected because it would make
the headline number a function of controller gains nobody chose for that purpose.

---

## D7 — Iberian claims use only what the scenario file already holds

Any Iberian number in this milestone is taken from
`docs/scenarios/iberia-2025-04-28.md` (page-cited from the ENTSO-E factual report)
and nowhere else — not from recollection of later reports. In particular the
scenario file records *that* inverter-based resources contribute no inertia and
*how much* PV tripped; it does not record their control modes, so no step may
claim to reproduce an Iberian mechanism that depends on them.

---

## D8 — What M7 does not do

- **No electromagnetic transients.** The tier stays phasor. What that cannot show
  is named (Hurdle 12), not approximated.
- **No inverter current limiting, fault ride-through or DC-link dynamics** at the
  outset. Current limiting is the single most consequential omission — a real
  grid-forming inverter's "inertia" is capped by its overcurrent headroom — and it
  is named here as owed, the way M3 named the missing governor floor.
- **No wind-turbine mechanics** (rotor inertia behind a converter, synthetic
  inertia drawn from it).
- **No network OPF.** Still owed from M6 (`m6-context.md` D7 criterion 4).
- **No AGC.** Out of scope since M3.
