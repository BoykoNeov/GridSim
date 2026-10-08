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
Spike: `docs/evidence/m7-step0/spike_pd_inverters.jl`. Case: a two-bus system,
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

---

## D9 — A grid-forming inverter's damping leaves with it in the aggregate (taken before step 2)

Raised by review after step 1. The aggregate model (`SystemModel`) carries damping
as ONE system-wide constant `D`, so a tripped unit's damping stays behind — M2
recorded that for machines, where it was a small error (a machine's `D` is ~2 on
its own rating). A grid-forming inverter's equivalent damping is `1/K_p` = **20** on
its own rating at the defaults, ten times larger. Folded into the system constant,
a grid-forming trip in the aggregate would keep most of the departed inverter's
response, and step 7's "largest-unit trip" makes that case likely rather than
exotic: at high inverter share the largest unit may be an inverter.

Two options were on the table — refuse `TripGenerator` on a grid-forming unit in
the aggregate, or make its damping leave with it. **Taken: it leaves.**
`GeneratingUnit` gains a per-unit damping field, **default `0.0`**, and
`aggregates` adds the online units' share to the system constant. Every existing
unit carries zero, so every M1/M2 number is the number it was (`x + 0.0`). A
grid-forming inverter's `1/K_p` goes on its unit; a machine's `D` stays where M2
put it.

That leaves a **stated asymmetry**: in the aggregate, a tripped machine's damping
still stays behind and a tripped grid-forming inverter's does not. Moving machines
onto the per-unit field would fix the old error and move M2's recorded
cross-fidelity gap, which is a finding with tests pinned to it — so it is named
here as available and not taken in M7. The settling closed form
`Δω_ss = ΔP/(D_sys + Σ_online D_unit + 1/R_eq)` is asserted only where it is exact:
on trips of grid-forming inverters and grid-following ones, and on machine trips
only with the old system-wide reading of `D`.

## D10 — An inverter's reactive output against its rating is named in step 4, not assumed

Also from review. Step 4's check "the power flow of a grid-forming bus is
bit-identical to the same model with a `Machine` in its place" is exact only
because the power flow reads `P0` and `V_set` from both — and the rating is where
the two really differ: a machine has no reactive cap unless `Q_min`/`Q_max` say
so, an inverter's reactive output is bounded near `√(S_rated² − P0²)`. The
constructor checks only the *dispatched* `Q0`. So step 4 either checks the
**solved** reactive output at a grid-forming bus against the rating (refusing, or
switching to a limit as M6 D12 does for machines), or names it as unchecked in the
docstring and the ledger. Which one is decided in step 4, with the measurement.

### What step 4 settled (the measurement first)

Measured before choosing, on step 3's ring with the inverter's reactive output
unlimited (a `Machine` twin with no `Q` limits, which the power flow cannot tell from
the inverter): at the default 150 MVA rating and `V_set = 1.01` the inverter bus is
asked for **0.158 pu against a capability of 1.375 pu**; at `V_set = 1.05` for
0.539 pu. Cut the rating to 65 MVA at the same 60 MW and the capability falls to
0.25 pu — well inside what an ordinary voltage schedule asks for.

**Taken: the rating is a reactive limit, and it switches.** `ac_powerflow` gives a
grid-forming bus `Q ∈ ±√(S_rated² − P0²)` through the same bind-only switch M6 D12
built for machines. So on the power flow an inverter IS a machine with those limits,
and the check is an `==`: the solved flow is bit-identical to the `Machine` twin
carrying the same `P0`, `V_set` and hand-converted limits, both when nothing binds
(where the unlimited twin is ALSO identical — one solve happened) and when the limit
binds (the bus becomes a load bus at 0.25 pu and cannot hold 1.05).

**The slack is the blind spot, and it is closed separately.** Switching never caps
the slack, and a grid-forming inverter is the default slack of a model with no
machine (step 7's all-inverter corner). There the solved `|P + jQ|` is checked
against the rating after the solve and refused by name
(`_ac_check_inverter_slack`); with a machine on the slack bus the split is not the
solve's to decide and nothing is checked. The fixture that exercises it uses a
CONSTANT-POWER load, because the default constant-impedance load draws `P0·|V|²` at
the solved 0.97 pu and the hand estimate (51.6 MVA) turned into a measured 48.5 —
the M6 lesson about running claims on the default, met in the other direction.

The DC flow needs no decision: it has no reactive power, and a grid-forming
inverter is an injection there exactly like a machine's.

## D11 — `V_set` is the BUS voltage at every tier, and the droop's intercept is derived (taken in step 4)

**The question.** The detailed tier puts the grid-forming inverter's voltage behind
`X_c` (D3). So "the magnitude it holds" could mean the magnitude it FORMS behind the
reactance — the way a machine's static vertex holds `|E| = Machine.E′` — or the
magnitude at its BUS. The first reading makes the static vertex one unknown shorter
and mirrors the machine; it would also give `Inverter.V_set` three meanings across
three consumers (the swing tier and `ac_powerflow` already read it at the bus). That
is M5 step 8's "one field serving two denominations" trap, which there produced a
pre-event offset between tiers LARGER than the disturbance — and a machine at least
has two fields for its two meanings; the inverter has one.

**Taken: the bus voltage, as the plan's own sentence says ("the inverter's bus a
voltage-controlled bus").** The static vertex carries `(V_re, V_im, δ, E)` — the
formed magnitude is the fourth unknown and `|V| − V_set` the fourth residual
(`E − E_held` on a re-initialisation). Rejected argument, recorded because it
sounded decisive: "PowerDynamics' `Vset` is the source magnitude, so the other
reading keeps the external check to model data." It does not — `build_oracle` seeds
PowerDynamics from OUR fixpoint, so their check never sees which reading was taken.

What this bought, measured: on a model where every source is a grid-forming
inverter, the engine's own static solve and the separately written `ac_powerflow`
hold the same unknowns, and they agree to 1e-11 — an independent check of the new
static vertex that the machine reading could not have had.

**The droop's intercept is ONE derived number.** `IdealDroopInverter` writes
`V = V_set − K_q·(Q_filt − Q_set)`; only `V_set + K_q·Q_set` enters the dynamics, so
two setpoints cannot be data without one of them being redundant. The engine derives
`V_ref = E + K_q·Q` at the solved operating point (M5's `Vref` precedent: a setpoint
that does not match the dispatch turns the flat run into a startup transient), and
it derives it THROUGH `_gfm_voltage`, the law the right-hand side integrates, so a
change to the droop law moves the derivation with it and the build-time residual
check cannot be what catches a sabotage of it. Consequence, stated in the
`Inverter` docstring: `Q0` is read by no consumer of a grid-forming inverter — the
power flow solves its `Q` (it is a PV bus) and the detailed tier derives the
intercept. It is still checked by the constructor's rating guard.

**Power measured at the source, not the bus.** `P` is the same at both ends of a
lossless reactance; `Q` is not — the source sees `Q_bus + |I|²X_c`. Taken at the
source because the component this is checked against measures at its own terminal,
which is the source (D3). Executed as a mutation: moving the measurement to the bus
is INVISIBLE to every in-house check (both the flat run and the droop-gain check
follow the mutated `Q` consistently), and only the PowerDynamics comparison can see
it — which is what that comparison is for. Measured in step 4's commit C: it is
red there, and the FLAT RUN is what catches it first — their power filter starts
0.016 pu away from rest, which is `|I|²X_c` at that operating point.

## D12 — The PLL is PowerDynamics' `PLL_LPF`, taken exactly (step 5)

The plan left "whichever PLL form is chosen" open. Taken: `PLL_LPF` line for line —
the error `e = −sin θ·u_r + cos θ·u_i` (NOT divided by `|V|`), a PI on it into a
first-order filter on the frequency, `θ̇ = Δω`. Hurdle 12's claim is that the gap to
`SimpleGFL` shrinks as its current loop stiffens; that is clean only if the current
loop and the filter inductor are the ONLY differences. Leave the output filter out
and the gap levels off at the filter's share, so "shrinks" becomes "shrinks to a floor
that then needs explaining".

Costs, stated: one new field, `Inverter.τ_pll` (default `1/(2π·300)`, guarded > 0,
walked by the scenario file like every numeric field); the gains act on `|V|·sin`,
so "base-free, on an angle" is exact only at `|V| = 1`; and the loop is THIRD order —
D0 and the plan said second. The phase-step prediction is therefore the matrix
exponential of the linearised 3×3 loop, computed by hand in the test.

## D13 — The transfer limit is behind the band, so it is checked in two halves (step 5)

The plan's scan — "initialisation succeeds below `P = |V_g|²/(2X)` and is refused
above it" — is UNREACHABLE as written. At unity power factor the nose sits at
`V_t = V_g/√2` ≈ 0.71 pu for ANY `X`, and every steady-state solve here refuses
`|V| < 0.9` (M5's band: the only discriminator between the real solution and the
collapsed one). So through the solvers the band refuses first.

Split, both pre-registered in closed form on the two-bus fixture (`X = 0.2`):

  (a) **where the solvers refuse** — the band edge, `P_band = 0.9·√(V_g² − 0.81)/X`
      = 1.9615 pu: `ac_powerflow` succeeds at 0.9999·P_band and refuses at
      1.0001·P_band;
  (b) **where the equations stop** — the nose, `P = V_g²/(2X)` = 2.5 pu, on the
      band-free first round (`_ac_first_round` + `_ac_newton`): it converges at
      0.9, 0.99, 0.999 and 0.9999 of the nose, every time on the HIGH branch of
      the closed form (agreement 1e-14), and fails at 1.0001.

The band's error message said the case was "genuinely infeasible, or the spurious
basin"; between the two points it is neither — a real operating point on the right
branch — and the message now says so. The constant-current bound `X·i_d ≤ V_g` from
D0 is a different (and also unreachable) statement and is not what a constant-power
power flow meets.

### What step 5 measured against `SimpleGFL` (Hurdle 12)

The claim held and its signature is clean on three channels: stiffening their current
loop by k (both PI gains) shrinks the gap as 1/k — ratios 3.85–4.42 per factor of 4
on the bus voltage, the PLL angle and the grid-forming frequency, with every
`convergence_band` at least 1e4 below the smallest gap. The PLL FREQUENCY gap fell
faster (15.3, then 7.7): it reads the current loop's fast transient at the trip
through a derivative. Not predicted; recorded rather than fitted.

The size is the honest part. At their default gains the voltage gap right after the
trip is 0.014 pu on a 0.021 pu excursion — the ideal current source is a coarse model
of the first milliseconds after an event, which is exactly the time scale Hurdle 12
says a phasor tier cannot hold. It is a fidelity boundary with a number on it, not a
tolerance.

## D14 — The read-outs: a bus meter, a live instantaneous RoCoF, and where zero weight lives (step 6)

**A measurement-only PLL, `PLLMeter` — the user's choice, taken before the code.**
Step 7's table has a "worst local RoCoF as a PLL measures it" column, and a PLL
existed only inside a grid-following inverter — so in the sweep that displaces
machines by GRID-FORMING inverters there would have been no PLL anywhere and that
column would have been empty, or filled by a different instrument than in the other
sweep. Put to the user in those words; taken: a meter at any named bus, the SAME
loop (`_pll_rhs`, the one copy of `PLL_LPF`, now shared with the grid-following
vertex) injecting nothing. An **engine keyword** (`DetailedEngine(…; meters)`), like a
relay or a shed ladder — an instrument armed on a case, not network data — so the
scenario file does not change. Channels `θmeter_<bus>`/`ωmeter_<bus>`, a prefix of
their own because a bus id and an inverter id may be the same symbol. Built as a
wrapper (`_Metered`) that appends three states and three gains to whatever vertex
kind the bus already is and leaves that kind's equations untouched; with no meter
armed the network is the four vertex models it was, and a captured step-5
grid-following run is `==` before and after the refactor
(`docs/evidence/m7/step6/gfl_capture.jl`).

How it is checked: (a) INJECTS NOTHING, structurally — kick every meter state far off
and every other row of the right-hand side is `==` unchanged; (b) the positive
control — a meter with an inverter's gains at that inverter's bus reads the
inverter's own PLL. Predicted bit for bit, and **that was wrong**: the Rosenbrock step
solves one linear system over the whole state, so two identical row blocks at
different positions pick up different round-off — 6.5e-17 / 6.2e-17 / 4.3e-17 at
reltol 1e-8 / 1e-10 / 1e-12, NOT falling with the tolerance, so round-off rather than
solver error, on a 2.0e-3 excursion. A meter on the neighbouring bus is off by ~1e-3.

**The instantaneous centre-of-inertia RoCoF is a LIVE read (`coi_rocof`), not a
recorded channel.** It comes off the model's right-hand side — never from differencing
recorded samples, which is the windowed read with the window set to the sample step
and would have made "three ways" two. A recorded channel was considered for the
detailed tier (playback-only, so the per-sample cost is irrelevant, and re-evaluating
the RHS on saved states after the run is WRONG — `inject!(::TripLine)` writes the
line's status into the parameters, so pre-event samples would be read against the
post-event network). Refused because `reference/src/oracle.jl` rebuilds
`state_series(::DetailedEngine)` channel for channel and the reference suite asserts
the key sets equal: a right-hand-side derivative has no counterpart on the
PowerDynamics side, so the channel would have forced a fabricated one there. On the
aggregate tier the read is the `RoCoF` field `current_state` has always carried.

**The three, and their names.** `coi_rocof(engine)` (instantaneous, what the closed
forms predict); `rocof_readouts(engine; window).coi` (`windowed_rocof` on `f_coi`);
`rocof_readouts(…).pll` (the SAME `windowed_rocof`, same window, on each PLL's
`f0·(1 + ω)`, keyed by channel name — so the only thing that differs between 2 and 3
is the frequency differenced).

**Zero weight — where it is reachable, path by path** (Hurdle 10 claim 3):
- `coi_model` — refuses a model with nothing to follow (step 2).
- `FrequencyResponseEngine` — refuses a zero-inertia model and a trip into zero
  inertia, before anything moves (step 2).
- `DetailedEngine` — unreachable: a model with no source is refused at `init!` (D5)
  and a generator trip is refused outright at this tier.
- `SwingEngine` with everything tripped — the live `f_coi` channel reads `NaN`. That is
  M2's decision ("the honest answer, and one plotting skips"), pinned by the network
  window's test; D6's "the read-out refuses" is honoured in the read-outs M7 ADDED:
  `coi_rocof` and `rocof_readouts` both refuse by name. The live channel was not
  flipped.

"Per-bus PLL channels" are the step-5 `ωpll_<inverter>` channels: the detailed tier
refuses two sources on one bus (machines and inverters together), so per inverter IS
per bus there, and renaming would have broken two pinned key lists for nothing.

### What step 6 measured

**The phase-jump spike, closed form (Hurdle 10 claim 1), on a real network event.**
Fixture built so NOTHING but a phase can move: one machine, a lossless triangle, a
CONSTANT-POWER load and a ZERO-current grid-following inverter at B; trip A–B. B's
angle falls by Δ = −0.0604 rad (sign pre-registered: the path to the load lengthens),
|V_B| = 0.9325 after. Pre-registered closed form: with the PLL's output filter removed
the estimate jumps at t⁺ to `K_p·|V|·Δ` (|V| because the error is not normalised,
D12), and the filter's leftover must shrink as τ does. Measured leftover 0.0592 /
0.0114 / 0.0022 at τ = τ₀, τ₀/10, τ₀/100 — 5.2× per decade, both decades (linear
theory 5.4, 6.7; the difference at the smallest τ is the sin φ ≈ φ term, ~Δ²). A
first-order correction `K_p|V|Δ·[1 − ε((1 − κ)ln(1/ε) − 1)]` (ε = K_p|V|τ,
κ = K_i/(K_p²|V|)), derived by matching the filter's fast mode to the slow loop, holds
to 1.1 % at the default gains. A 0.06 rad jump reads as −0.53 Hz. The PLL error
normalised by |V| is the mutation this is built to catch (the leftover at the smallest
τ would be ~7 %, not 0.2 %).

**…and the centre of inertia does not move at all**: `coi_rocof` at t⁺ = 5.6e-17 Hz/s,
and `f_coi` deviates from 50 Hz by exactly 0.0 over the run, while the PLL at B and
the meter at C both dip. That is the anti-vacuity case for D6: averaging a PLL into
`ω_coi` moves a channel that, here, must not move.

**The phantom RoCoF — a 1/window law, from below.** A window longer than the spike
reaches back to before the jump, so the windowed PLL RoCoF reaches spike/W — ~1.06
Hz/s at 500 ms at B, from a line switching that moved no rotor. Predicted as an
equality and measured not to be one at short windows: a window that starts ON the
spike ends on the PLL's opposite-signed ringing, which adds 1.3e-3 of the spike at
W = 0.25 s, 2e-8 at 0.5 s, nothing at 1 s. So it is spike/W as a lower bound,
approached as the window outlasts the ringing.

**The window's own cost on a known trajectory (claim 2).** One aggregate unit, no
governor, H = 1 s, D = 2: after a load step the frequency is exactly first order with
T = 2H/D = 1 s, so every windowed sample is a closed form, matched to 1e-7, and the
windowed extreme is `RoCoF₀·T(1 − e^{−W/T})/W` — 0.94 / 0.88 / 0.79 / 0.63 of the
true RoCoF₀ at W = 1/8 … 1 s. Binary-exact dt and W, so the lookup `tᵢ − W` is itself
a sample and cannot land one early.

**The three side by side — and the prediction written before the run was wrong.**
On step 5's grid-following ring with a line trip, the test comment first said "the
window under-reads the instantaneous value". Measured: instantaneous at t⁺ −1.5e-4
Hz/s; 500 ms window on `f_coi` 0.066 Hz/s (~450× larger); 500 ms window on the PLLs
0.22 (the inverter's), 0.91 and 0.69 (meters at the two machine buses) Hz/s. The
imbalance BUILDS after t⁺: at the instant the inverter's current is where it was and
barely moves P; then its PLL swings the held current round and |V| sags, and `f_coi`
falls 0.045 Hz. So on this case "RoCoF₀", the quantity every closed form in the repo
predicts, is the SMALLEST of the three. The meters at machine buses read the most:
they see that machine's own swing on top of the jump.

**Found, not planned — a step-7 blocker, recorded here and put to the user before
step 7.** The detailed tier refuses `TripGenerator`, `StepLoad` exists only on the
aggregate engine and has no bus, and grid-following inverters exist only in the
detailed tier. So step 7's "largest-unit trip at each share" cannot run as the plan
writes it. Available: the machine vertex already multiplies its stator current by a
status parameter (`mstat`, always 1.0 today) — the hook for a source-status trip path;
or a load step located at a bus; or a different study event.

## D15 — Step 7's event: a real source trip in the detailed tier (taken 2026-09-29, the user's choice)

D14 found that "the largest-unit trip at each share" has no event at the tier step 7
needs. Three options were put to the user — a source on/off switch in the detailed
tier, a load step located at a bus, or a line trip instead — with the consequence of
each: the switch keeps the study as planned and is the most work; a load step asks a
different question ("load jumps", not "the biggest unit is lost"); a line trip is
the event on which step 6 measured the instantaneous centre-of-inertia RoCoF as the
SMALLEST of the three read-outs, so the study would say something else entirely.

**Taken: build the trip.** Its scope, stated before any code so step 7 cannot shrink
it quietly:
- **All three source kinds**, not only machines: at high inverter share the largest
  unit is likely an inverter (D9's argument). The machine vertex already multiplies its
  stator current by `mstat` (always 1.0 so far); the grid-forming and grid-following
  vertices need the equivalent.
- **The centre-of-inertia bookkeeping drops the tripped unit's weight** (`w`, `Σw`,
  `gfm.H`), as the swing tier does — and a trip that would leave no inertia online is
  refused, as the aggregate engine's is (step 2).
- **The re-initialisation after a trip** must solve the network the right-hand side
  then integrates, with the tripped source injecting nothing — never `E = 0`, which
  `inject!(::TripGenerator)`'s refusal text already names as the wrong shortcut.
- Checked before the study uses it: `coi_rocof` at `t⁺` against the aggregate
  `RoCoF₀` closed form, per source kind.


### What step 7 measured about the trip itself (built first, as D15 said)

**How it switches a unit off.** One in-service flag per source, multiplying its
CURRENT and written into BOTH networks: the machine's `mstat` (carried since M5,
never written before), a new `istat` on both grid-forming vertices, and, for a
grid-following inverter, its current setpoint itself. Also zeroed: a machine's `Pm`,
governor gain, reserve and ramp (with `ΔPm` re-seated), a grid-forming inverter's
`P_set` (so its idle droop settles at zero speed instead of drifting at `K_p·P_set`),
the unit's inertia weight, and every relay at its bus and ladder on it. A trip that
would leave no machine and no grid-forming inverter online is refused before anything
moves (D5), at this tier as at the aggregate one. `is_online(eng, id)` reads it back.

**The re-initialisation now checks the network it hands to the integrator.** Before
step 7 only the STATIC solve was checked, and the two networks agree only because every
event writes the same change into both parameter vectors. A trip writes four such
pairs. So after every re-solve the DYNAMIC network's Kirchhoff rows are evaluated at
the new state and must be below `1e-10` — the advisor's addition, and the only check
that can see a status written on one side only (sabotages T7-3, T7-4, T7-7).

**The closed form at t⁺, per kind, exact** (`test/m7_inverters.jl`): on a lossless
ring with `Ra = 0` and a CONSTANT-POWER load, `coi_rocof` just after the trip equals
`−f0·P_lost/(2·H_post)` to `rtol 1e-8` for a machine (slack and non-slack), a
grid-forming inverter and a grid-following one, with `P_lost` read from the NETWORK
side and `H_post` written by hand from the formula. The one further condition is that
**no grid-following inverter survives the trip**: it holds its current, so its power
at t⁺ moves with |V|. With one surviving, the balance is still exact once that change
is counted (`Σ 2Hω̇ = ΔP_pv − P_lost`), and without it the formula misses by more than
1 %.

**Gates:** M5's criterion values bit-identical to the capture at HEAD before the first
edit (`docs/evidence/m7/step7/criterion-HEAD7.txt` / `criterion-TRIP.txt`); step 6's
captured grid-following run `==` after the new `istat` parameter.

## D16 — Step 7's study: TWO events, default loads, and an exact control (taken 2026-10-03, the user's choice)

**What was measured before asking.** The study fixture is M1's `example_system()`
units on a seven-bus network (four unit buses, three load buses), so its zero-share
row has M1's own number to hit. Three findings, in the order they arrived:

1. **The planned event leaves the tier's voltage band.** M1's largest unit, G1, is 150
   of 390 MW — 38 % of the generation in one step. With the machines at `E′ = 1.05`
   the trip leaves G1's own bus at 0.874 pu at t⁺, below the 0.9 band every
   re-initialisation enforces (the discriminator against the collapsed solution, never
   a tolerance to loosen). Scanned rather than tuned: `E′ = 1.10` with `X = 0.05` pu
   lines starts every bus at 1.018–1.034 and leaves 0.946–0.959 at t⁺.
2. **On that network the zero-share control is exact**: `coi_rocof` at t⁺ =
   −3.488372093022 Hz/s against M1's recorded −7500/2150 = −3.488372093023 (gap
   1.3e-12), on constant-power loads.
3. **Grid-following displacement turns the big trip into a voltage event.** Swapping
   G4 alone for a grid-following inverter at matched dispatch drops B1 to 0.80 pu at
   t⁺ (0.81–0.89 however stiff the lines were made, X = 0.05 → 0.01); swapping two
   leaves the post-trip network with no solution at all. The inverter holds its
   current, so it neither picks up any of the lost power nor holds a voltage; the
   machines that remain must do both through their own reactance. Grid-forming
   displacement runs at every share.

**The choice put to the user, in those words:** trip the smallest unit (G4, 60 MW,
15 % — the event M1 itself used for its "less inertia" lesson, because there the
governors have the reserve to cover it), keep the largest as planned, or report both;
and run the table on constant-power loads (the formula exact at every share, the
grid-following sweep stopping after one swap) or on the repo's default loads with a
separate exact control row.

**Taken: both events, default loads, and the exact control as its own section.** The
big trip is where grid-following displacement becomes a voltage story and the small
one is where the frequency story can be told; the table runs on the default
(constant-impedance) loads — M6's lesson that a claim made only on a convenient load
model is a claim about the load model — and section 1 of the script repeats the
zero-share trip on constant-power loads against M1's number.

**Rejected, and why:** relaxing the 0.9 band (it is the discriminator, D13); moving
`coi_model` to accept constant-power loads so the aggregate tier could draw the
overlay (the advisor's objection: it also refuses every bus with no generating
element, so the change would spread into the function SPEC §3.2 points at as the
proof that reduced models are derived; the overlay is the closed form written from
the model data instead).

### What the study measured (`scripts/low_inertia.jl`, asserted in `test/m7_low_inertia.jl`)

**Design held fixed.** M1's units on two layouts of the same seven buses — `:ring`
(meshed) and `:chain` (the same buses in a line). Each sweep displaces the units OTHER
than the tripped one, smallest first, then the tripped unit itself; a displaced
machine becomes an inverter at the same bus and rating at MATCHED DISPATCH, read off
the all-machine power flow (a grid-forming inverter holds the voltage the machine left,
a grid-following one injects the machine's P and Q), so every row of a sweep starts
from the same operating point — asserted to 1e-8 in every bus voltage. Default
(constant-impedance) loads; solver tolerance 1e-6 (the engines' real-time 1e-3 is three
orders too loose for a three-decimal table, and the one after-t⁺ comparison between two
runs — rows 3 and 4 below — is shown to close as it tightens: 1.9e-5 Hz at 1e-3,
1.3e-11 at 1e-6, round-off at 1e-8).

**The positive control holds on both layouts:** zero share, constant-power loads, the
network's `coi_rocof` at t⁺ against M1's own engine on `example_system()` — gaps
1.4e-12, 3.1e-13, 7.9e-13, 2.2e-16 Hz/s for G1/G4 on ring/chain.

**The finding that reorganised the claims: on the default loads the formula and the
network RANK THE TWO INVERTER KINDS OPPOSITE WAYS.** By the formula `−f0·P_lost/(2H)`
grid-forming displacement steepens RoCoF₀ less than grid-following (it keeps 1 s of
virtual inertia). In the network column grid-forming is steeper in every cell where
both ran, and on the chain one grid-following swap reads SHALLOWER than no inverters at
all (−0.745 → −0.622 Hz/s). The advisor caught it — the first draft of the claims read
the formula column. Measured rather than narrated: with two new columns read from bus
voltages at t⁻ and t⁺, the balance `Σ2Hω̇ = −P_lost + relief + ΔP_gfl` holds to
`rtol 1e-8` in every cell tested. Grid-following holds a current and supports no
voltage, so the dip at t⁺ is deeper and more constant-impedance load sheds itself
(62.7 MW against 22.4 MW at one swap on the ring's big trip). That load relief is what
the instantaneous number is mostly made of on default loads.

**The claims, written after both layouts' tables** (script section 4; each asserted):

- (a) above.
- (b) **Grid-forming displacement moves RoCoF₀ and the nadir in OPPOSITE directions**:
  RoCoF₀ steeper, nadir shallower, at every share, both events, both layouts (ring, small
  trip: 48.79 → 49.13 → 49.42 → 49.62 Hz). The nadir benefit is the DROOP, not the
  virtual inertia: τ_p → 0.001 s moves the nadir < 0.05 Hz while RoCoF₀ explodes (to
  −1092 Hz/s instantaneous, a number with no physical reading). **Scoped to no current
  limit (D8):** most grid-forming rows run above rating (1.26–1.63× on the big trip,
  1.02–1.19× on the small one); the clean cell is the ring's small trip with no machine
  left, at 0.97×.
- (c) **The relay's 500 ms reading barely follows RoCoF₀**: from no inverter to no
  machine left, RoCoF₀ steepens 3.8–4.7× while the windowed COI reading changes by −19 %
  to +3 %, not monotonically. Removing the virtual inertia raises the windowed reading
  5–15 % while machines remain and ~1 % once none do.
- (d) **Grid-following displacement deepens the nadir in every cell that ran**, and on the
  big trip stops being a frequency question at a third of the generation: |V| at t⁺ =
  0.863 (ring) and 0.874 (chain) pu, below the band. In its one running big-trip cell
  the reserve is gone and the frequency sinks with no recovery to 44.30 Hz (ring) /
  44.66 Hz (chain) — measured at 120 and 240 s, and within 3 mHz of that at 30 s. **Two
  corrections from the final review:** a "~39 Hz on damping alone" estimate written here
  ignored the constant-impedance loads' relief and was wrong by 5 Hz; and the
  still-falling flag first fired on "the minimum is the last sample", which a monotone
  settle also satisfies — it now reads the slope over the last second, and a test shows
  it fires on the same cell cut off at 3 s.
- (e) **The layout matters most to voltage**: at 46 % grid-following share on the small
  trip the ring's lowest voltage is 0.963 pu and the chain's t⁺ voltage is 0.899 — a
  refusal ON the band edge, so the claim is the gap (ring − chain > 0.05 pu, asserted),
  never the refusal. On the chain the PLL meters read up to twice the centre-of-inertia
  RoCoF (1.45 against 0.685 Hz/s at one grid-following swap). WHERE that excess comes
  from — the trip's phase jump or a machine's own swing at its bus, both of which step 6
  measured — is not separated here, and the first draft's "the phase jump, which no
  rotor felt" was a story, not a measurement.

**Drafted before the tables and wrong** (M3 step 6's lesson, met again): "grid-forming
steepens RoCoF₀ less than grid-following" (true of the formula, false of the network on
default loads); "the 500 ms reading falls under grid-forming displacement" (it rises at
first on three of four tables, and ends higher on one); "removing the virtual inertia
barely moves the 500 ms reading" (5–15 %). Also: the n = 3 and n = 4 grid-forming rows
coincide — the tripped unit's kind cannot matter once it is gone — which is a consistency
check of the machine and inverter trip paths, not a finding.

**The reference oracle's generator-trip mapping stays refused at the detailed tiers,
for a new reason.** It was refused because our engine could not trip; now it can, but
ours switches the source's current off with the bus (and its load) connected, while the
oracle's mapping deactivates every incident line — two different events. The refusal
text says so and its test reads it (the advisor's final-review check).

**Not done, and said so:** the aggregate tier's NADIR is not overlaid — `coi_model`
refuses any model carrying a `Load` (and any bus with no generating element), and widening
it was rejected in D16; the overlay is the RoCoF₀ closed form only.

## D17 — Step 8's window: the study drawn, re-run per control (taken 2026-10-03, the user's choices)

**Built, not cut.** The plan marked the window cut-first; the user asked for it built.
Two choices were put to the user before any of it was written, and both recommended
options were taken: **one shared plot plus meter panels** — the three runs'
centre-of-inertia frequency overlaid on top, and below it one panel per inverter kind
with the per-bus PLL meters drawn behind that run's own centre of inertia — and **all
three controls**: which generator trips (G1 150 MW / G4 60 MW), how many units are
displaced (0–4, the study's order), and the layout (ring / chain).

**"Live" means re-run, not animated.** The detailed tier is the only one that holds a
grid-following inverter, and it has no real-time loop (`step!` is not implemented for
it, m5-context.md D2). So a control change runs three simulations to completion and
redraws; results are cached per (layout, event, kind, share).

**The study is not copied.** `ui/src/low_inertia_window.jl` `include`s
`scripts/low_inertia.jl` into a submodule, exactly as `test/runtests.jl` does — so the
UI package now depends on a file outside `ui/src`, and the window header says so.
`study_cell` gained `keep = true`, which adds the run's `state_series` and changes
nothing else (the cell body moved into `_study_cell`, which returns the engine beside
the row). Refactor gate: the whole core suite, the 119 study checks among it, green
unchanged (4134 = 4113 + step 8's 21 helper checks). The window's read-out is the
study's row; a test asserts `isequal` with `study_cell` at the window's tolerance.

**The window's tolerance is NOT the study's — measured, then chosen.** Warm timings,
one cell per kind, two settings (ring/G4, chain/G1, one unit displaced):

| reltol | time per run | moves vs 1e-6 |
|---|---|---|
| 1e-6 (study) | 1.5–8 s; one cell **36 s** (chain, G1, grid-forming) | — |
| 1e-5 | 0.6–4 s | nadir of the sinking cell by **4.5 mHz** |
| 1e-4 | 0.2–2 s | RoCoF₀ and min \|V\| by nothing at 6 decimals; COI 500 ms ≤ 1e-6; PLL 500 ms ≤ 2.5e-4 Hz/s; nadir ≤ 1e-5 Hz except the sinking cell, **2.3 mHz** |

Three runs per click at the study's tolerance is a 5–50 s wait. The window runs at
1e-4 by default and names it in the read-out heading; `reltol = 1e-6, abstol = 1e-8`
reproduces the study exactly. **Found, not planned:** in the one cell whose frequency
sinks to the end of the run (the big trip, one grid-following swap) the nadir's third
decimal is not converged at ANY tolerance tried — 1e-5 is further from 1e-6 than 1e-4
is. The study's claim (d) quotes that value to two decimals (44.66 / 44.30 Hz), which
holds; the table's third decimal there is noise. The 36 s cell (2.1 s at 1e-5) was not
investigated.

**The meter panels' scale is the centre of inertia's.** Autoscaled, the meters'
spike at the trip sets the axis and flattens the trace the panel exists to compare
against. Both panels share one y-range: the two runs' centre-of-inertia traces over the
zoom window, padded by max(25 %, 0.1 Hz); any meter sample outside it is reported in the
panel as a number ("meter peak … Hz at t = …, off scale") rather than drawn. A test
asserts both halves — the limits are exactly that rule, and "a point off scale" ⇔ "a
note" — because the second alone passes on an autoscaled axis too. **The first render
zoomed 4 s after the trip**, and the grid-following run's 2 Hz fall set the shared scale
so the meters' departure from the centre of inertia was a sliver at the edge; the meters
rejoin it by ~1.5 s, so the zoom is 1.5 s.

**Held from earlier milestones:** each run on its own time axis, overlaid and never
subtracted (M4 — the three integrations' samples differ); a refused run draws what it
recorded before the refusal and its reason in place of the rest, and nothing from the
previous setting survives a change (the editor's solve-overlay rule); at zero share the
two inverter runs are the same model built twice and are asserted `==` sample for
sample, and different at one unit (the window's own anti-vacuity control).

**Not in it, and said:** no time cursor (the read-out is the study's summary row, not a
per-sample read); no aggregate-tier overlay (D16); no current limit on the grid-forming
inverters (D8) — the caption says that `GFM S/S_rated` above 1 means the model ran them
past their rating. **And the window blocks while it runs**: the three runs happen inside the
click handler, so the live window does not redraw for up to ~6 s per click at 1e-4
(far longer at the study's 1e-6); offscreen tests cannot show it, so `ui/README.md`
says it. The caption and README first explained the meters' departure as "a swing no
rotor made" outright — the cause D16 withdrew for the chain, moved from the off-scale
note into the caption rather than removed (the advisor's final review); both now say a
meter shows the phase step AND nearby machines' swings, unseparated here.
