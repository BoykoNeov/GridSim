# M3 — Context

What was decided and why, and what was measured rather than reasoned about.
Companion to `m3-plan.md` (the how) and `m3-tasks.md` (the checklist).

## Environment

Unchanged from M2 (`m2-context.md` §Environment). Julia on PATH via juliaup;
`[compat]` floor stays at 1.10. `Manifest.toml` gitignored, in the root **and in
`ui/`** — the trap that bit M2 six steps after the dependency change.

**M3 adds no dependency.** That is one of the reasons it was chosen over the
cross-fidelity playback rung, which almost certainly forces `PowerSystems.jl`
adoption (roadmap step 4) forward into a milestone that is supposed to be about
dynamics.

## State of the repo entering M3

M2 complete and committed at `ad3b861`: the canonical `NetworkModel`, the
multi-machine `SwingEngine` on NetworkDynamics, generator and line trips, the
bounded trajectory recorder, the derived `coi_model` view, and the multi-machine
GLMakie window. **1234 core tests and 74 UI tests green.**

Core (`src/`) deps: `CommonSolve`, `Graphs`, `NetworkDynamics`, `Observables`,
`OrdinaryDiffEq`, `SciMLBase`. No Makie, enforced by a dependency-closure test
with a positive control.

## Why this milestone, ahead of the roadmap's own numbering

`docs/SPEC.md` §9 puts the cross-fidelity playback overlay next. It was not
chosen, for two reasons recorded here so the departure from the roadmap is
deliberate rather than drift:

1. **There is flagged-unsound work already in the repo.**
   `entsoe-iberia-reproduction.md` §7.3 states in its own words that the
   headline two-area numbers come from a 90-line hand-rolled probe outside the
   repo, whose `P_max` "was adjusted until loss of synchronism happened". Closing
   that beats opening something new.
2. **M2 built the mechanism that probe was standing in for.** Rotor angle and the
   nonlinear tie are done and tested. The gap is one control state.

## Decisions

### D1 — One three-state vertex for every machine; M2's numbers get re-pinned

**Measured, not assumed.** The question was whether adding a third state whose
derivative is identically zero leaves the solver's accepted step sequence intact
— i.e. whether governor-free models could stay bit-identical to M2.

Probe (`M:\claud_projects\temp\m3\norm_probe.jl`, deliberately outside the repo):
the same harmonic oscillator integrated by `Tsit5` as two states and as three,
with `du[3] = 0`.

```
n steps: 2-state=32  3-state=31
identical step sequence: false
first divergence at step: 2
t2[1:5] = [0.01, 0.07806449, 0.23752821, 0.47752115, 0.78235998]
t3[1:5] = [0.01, 0.08002480, 0.24605223, 0.49716591, 0.81582766]
```

The reason is structural, not incidental: SciML's default error norm is
`sqrt(sum(abs2, err)/length(err))`, i.e. **averaged over the state vector**. Extra
zero entries lower the average, so larger steps are accepted. The 3-state run
reached the same end point in *fewer* steps.

**Therefore:**

- Bit-identity is impossible; do not write an acceptance criterion that assumes it.
- The alternative — two vertex models, so governor-free machines keep the exact
  M2 numerical path — was **rejected**. It preserves old numbers at the cost of
  two state layouts, two index maps, a `ΔPm` that exists on some vertices and not
  others, and a `coi_model` that has to branch. The property it protects (M2's
  last-bit values) is not a physical property.
- **V3's tight assertion is the thing to watch.** M2's tightest solver-dependent
  bound is a measured gap of `1.205e-4` against a `2.0e-4` limit — a 1.66×
  margin that M2 established is *not* solver-version slack (it came out
  bit-identical across two dependency resolutions). Step 1 must re-measure it and
  record the new value beside the old. If the margin shrinks materially, that is a
  finding about the assertion, not a licence to loosen it.

#### D1 — measured outcome after step 1: the re-pin was not needed, and why

The plan announced a re-pin in advance and was right to. The measurement says it
did not happen: **every gauge-free quantity is bit-identical between M2 and M3**
on the shipped fixtures. Measured by running the same script against a pristine
worktree of `9a1dd32` and against the M3 tree
(`M:\claud_projects\temp\m3\bitcompare.jl`, outside the repo):

| quantity | M2 (`9a1dd32`) | M3 step 1 |
|:---|:---|:---|
| `f_coi`, both fixtures, 10 samples over 30 s | — | **identical to the last bit** |
| `naccept` / `nreject`, both fixtures | 1500 / 0 | **1500 / 0** |
| δ₁−δ₂ at the fixpoint, both fixtures | — | **identical to the last bit** |
| V3 measured gap `f_pred − f_meas` | `1.205e-4` | `1.205465e-4` |
| V3 margin to the `2.0e-4` limit | 1.66× | **1.659×** |
| V4a max gap | 7.1e-15 Hz | 7.105e-15 Hz |
| V4b peak gap / its time | 4.4325e-6 Hz / 0.26 s | 4.43246e-6 Hz / 0.26 s |
| V4c late gap / early ratio | ~0.857 / ~2800 | 0.85714 / 2831.7 |

**Why the probe did not transfer, which is the part worth keeping.** D1's reasoning
about the error norm is correct — SciML averages over the state vector, so extra
zero entries buy larger steps. It measured that on a **free-running** integration.
This engine never runs free: `step!(integrator, dt, true)` forces a stop at every
`dt`, and `naccept == nsteps` with `nreject == 0` in *both* versions says the
controller was already taking exactly one internal step per `dt` and had no room to
lengthen one. The mechanism the probe measured cannot act here.

The general lesson, since it will recur: a numerical probe has to reproduce the
**stepping discipline** of the code it is predicting, not just its RHS. A bare
`solve` and a `step!`-driven integrator are different numerical objects.

**The one thing that did move, and it is the invariant confirming itself.** On
`two_machine_system` the absolute rotor angles from `find_fixpoint` shifted by
`2.14455e-3 rad` — *the same constant on both machines*. That is a pure gauge
shift: the fixpoint is degenerate under adding a constant to every `δ`, the solver
lands wherever the extra state's Jacobian column sends it, and `swing.jl`'s header
already says that number is meaningless and must never be asserted on. The
difference δ₁−δ₂ is bit-identical. `three_machine_ring` did not shift at all.

Nothing in the suite noticed, because M2's tests assert differences — which is the
rule paying for itself rather than a lucky escape.

### D2 — Governor data lives on `Machine`, per machine, in its own base

`R` (droop, pu on the machine's own base), `Pmax` (MW), `Tg` (s). Not system-wide
constants as in M1's `SystemModel`: two areas with different fleets have different
lag and different reserve, and the whole point of the two-area case is that they
respond differently.

The per-unit split stays exactly where M2 put it — `machine_arrays` is the single
place conversion to the system base happens, and `1/R` converts with the machine's
MVA weight (`(1/Rᵢ)·(Sᵢ/S_base)`), the same aggregation M1's `aggregates` does.

Governor-free is `R = Inf`, `Pmax = P0`, and `Tg` then irrelevant but still
validated (`Tg > 0`, it is a denominator).

### D3 — No AGC in M3, and the reason it is not optional-but-skipped

Droop leaves a **permanent** speed offset, so angles keep drifting after a trip
(see `m3-plan.md` "The correction that shapes step 2"). Adding AGC would settle
them — and would also change what the Iberian scenario shows, because within the
~20 s window of interest AGC has barely acted. Including it would make the model
prettier and the scenario less faithful. Out of scope, deliberately.

### D4 — Headroom on an *area* machine is data, not a nameplate

The trap: for a physical unit, `Pmax − P0` is its up-reserve. The Iberian machine
is **an aggregate of generation minus load**, whose `P0` is the area's *net
injection into the tie* (−1,000 MW pre-event: Iberia imports). `Pmax` there does
not mean "the biggest number this machine can produce" — it means
`P0 + area up-reserve`, and it has to be set deliberately.

Consequence for the constructor guard: `Pmax ≥ P0` must be enforced (zero reserve
is legal, negative is not), and the docstring must say what `Pmax` means on an
aggregated machine, or the first person to reuse the type will put a fleet
nameplate there and silently give Iberia hundreds of GW of reserve.

### D5 — A shedding ladder binds to a named machine, not to `f_coi`

The most likely silent-wrong-answer in the milestone. `f_coi` on a pair that is
about to separate is an inertia-weighted average of two frequencies that are
diverging — `swing.jl`'s own header calls that read-out meaningless for a split
network. A ladder driven by it *runs*, produces a plausible trace, and sheds at
the wrong instants.

So: one ladder, one machine id, and firing steps **that machine's** `Pm`. M1's
single-area behaviour is the one-machine case, so this is a refactor with M1's
existing shed tests as the oracle — they must not change.

**Built at step 3, with two corrections to what this entry assumed.**

1. **The planned V5 could not have seen the bug it was written for.** "The right
   area's `Pm` moves, the other's does not, and a ladder bound to the other does not
   fire" is satisfied in full by a ladder that reads `f_coi` and applies to a named
   machine. The check has to separate the two candidate *signals*, not just the two
   machines, so the fixture puts a small weakly-tied area beside one carrying 30× its
   inertia: over 60 s the bound machine goes 6.52 Hz below the threshold while the
   COI average never comes within 0.09 Hz of it. A `f_coi`-driven ladder fires zero
   times there. That gap is the assertion.

2. **"A dead machine would shed and inject power" is not reachable on this tier**,
   and finding that out was the price of writing the counterfactual for the disarm
   the trip now performs. After a generator trip the rotor obeys `dω/dt = −Dω/2H`
   and rises monotonically toward nominal, so no under-frequency stage can cross
   downward afterwards: a machine tripped below a threshold has already fired, one
   tripped above it moves away, and re-arming by hand leaves the run bit-identical.
   The disarm is kept anyway — it is reachable through a threshold *above* nominal
   (legal, and what M1's own polarity test uses), where without it a machine seven
   seconds dead sheds and injects; and step 5's ramp puts `t`-dependence into the
   vertex RHS, which is exactly what would re-open the physical case quietly.

The refactor's own bar was raised in passing: the new expression is arithmetically
identical to the old one, so "M1's tests still pass" is too weak a check. A recorded
M1 run from before the edit matches after it **to every digit**, `naccept` included.

### D6 — Out-of-step protection is a root-found event on an angle difference

Threshold on `|δ_from − δ_to|` for a named branch, `ContinuousCallback`, latching,
firing into the existing `inject!(::TripLine)` path. Same justification as the
shed ladder's callback (`load_shedding.jl` header): a root-found instant, not a
per-step comparison accurate only to `dt`, and physics inside the engine rather
than in the engine-agnostic orchestration loop.

Threshold: the report's separation is at a pole slip, which the probe detected as
the 90° crossing followed by protection at ≈120–180°. The *threshold is a
parameter of the scenario*, and the sweep varies it — it is not a constant of the
tier.

**Settled in step 4 — three things D6 did not say, two of which would have shipped.**

*Where the threshold lives.* On the **relay**, not on `Branch`. The open question
below is closed on the parallel step 3 made concrete: a relay is passed at engine
construction (`out_of_step = [(:B1, :B3) => OutOfStepTrip(2π/3)]`) and the
`NetworkModel` never hears about it, which is what lets **one** model be run with
the plan armed and disarmed. That is not a convenience — the armed/unarmed pair is
the counterfactual every step-4 test is built on, and step 6's sweep varies the
threshold across cells of one model.

*A generator trip at either end disarms the relay.* Step 2's V3 measured the
mechanism: a tripped machine's rotor is islanded and undriven, so its `ω` is exactly
`0.0` and its `δ` **freezes**, while the survivors' common mode drifts on forever at
`ω₀·ω_ss`. The angle across a branch with one dead end therefore grows at the *full
drift rate* and crosses **any** threshold — on a branch whose coupling that same trip
had already set to zero. Measured on `_pole_slip_net`: after `:ESG` trips, `L12`'s
coupling is exactly `0.0` and `|δ_B1 − δ_B2|` blows through 120° at **t ≈ 2.36 s**,
reaching ~199 rad by 30 s. Without the disarm the relay opens a line that has carried
nothing for over two seconds and calls it a pole slip. Same asymmetry as the shedding
ladder and in the same direction: a *line* trip is what a relay exists for, a
*generator* trip is what makes its signal meaningless. The disarm is **selective** —
only branches incident to that bus — and asserted so.

*Opening a branch disarms every relay on it, whoever opened it.* `inject!(::TripLine)`
no-ops on an already-open branch, so a relay left armed on one would root-find a
crossing, run its affect, change nothing, and log a protection operation that never
happened — breaking the engine's own rule that a log records what changed the system,
not what was asked for. One line in `inject!(::TripLine)`, placed after the no-op
guard, covers the user's trip, another relay's trip and the relay's own.

**A fourth guard that only exists because the fixpoint is solved in the constructor
— and the measurement overturned the reason it was written for.** A threshold *below*
the pre-fault transfer angle was refused on the argument that it "could never fire":
the trip is a downward crossing of `threshold − |δ|`, the condition starts below zero,
and a downward crossing needs a positive side to fall from. That argument is a claim
about the rootfinder that nothing observes from outside `init` — the exact shape of
wording step 2's V4 had to rewrite — so it was checked instead of asserted, **and it
is false.**

`|δ|` is not monotone. The export swing carries the angle *down through zero* before
it runs away, so on `_pole_slip_net` a relay set at 0.30 rad against a 0.3789 rad
steady state starts at `g = −0.0789`, is carried **inside** its own threshold at
t ≈ 0.41 s, and fires on the way back out at **t ≈ 1.25 s** — 1.7 s before the genuine
slip at 2.9336 s, on an angle excursion that is an ordinary consequence of the
disturbance and not a loss of synchronism at all. The guard is therefore preventing a
relay that trips a healthy tie early **and looks like it worked**, which is a great
deal worse than an inert one. Both crossings are pinned in `test/`, and the boundary
is tested from both sides: 0.38 rad legal, 0.30 rejected.

**How the relay reaches `inject!`, and what that costs.** The affect calls the engine's
**real** `inject!(::TripLine)` — not a copy of its body — so the no-op guard,
`lines_online`, the event log and both integrator-boundary calls are the shipped ones
by construction. `inject!` needs the engine and the engine cannot exist yet (the
callbacks are arguments to `init`, whose integrator is one of the engine's own type
parameters), so the affect closes over a `Base.RefValue{Any}` the constructor fills on
its last line. That box is a local captured by one closure, **not a struct field**, so
SPEC §4's concrete-field rule is untouched, and it costs one dynamic dispatch on an
event that happens at most once per relay per run. The alternative — factoring
`inject!` into a helper over the pieces that do exist early — was rejected because the
only genuinely engine-bound piece is the event log's `n_dropped` counter: it would move
the log into its own object to buy back type stability on a once-per-run call, and
leave two ways to open a branch.

**And the empirical half of that decision, because it was not obvious.** `inject!`
calls `auto_dt_reset!`, which is safe between `step!`s but is a different situation
inside a `ContinuousCallback` affect, where the integrator has just been interpolated
back to the root mid-acceptance. Measured rather than argued: with that call patched
out of the `TripLine` path (and a marker printed to prove the patch was live, since
"bit-identical" is also what a stale precompile cache produces), the trip instant, both
machine speeds and every digit of the state are **identical at three step sizes**. The
call is inert on this path and harmless, so calling the real `inject!` is safe.

**The event stamp is exact here, unlike a shed's would be.** Step 3 kept sheds out of
the `EngineEvent` log partly because the event stamp would be `dt`-quantised. On this
path it is not: `apply_callback!` interpolates the integrator back to the root *before*
the affect, so `inject!`'s own `_log_event!` reads the root-found instant. Asserted as
`evs[2].t == lg.t`, to the bit. A line trip is also exactly the change a played-back
trajectory cannot reconstruct, which is what the event log is for — so this one is
logged and a shed still is not, and the two decisions do not conflict.

### D7 — Generation loss ramps inside the RHS; it is not a staircase of trips

Three extra vertex parameters (`rate`, `t_start`, `duration`) and
`Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)`.

The staircase alternative (N discrete trips approximating a ramp) was rejected
because M3 adds **root-finding protection**: staircase edges are discontinuities
in the very signal the out-of-step and shed callbacks are root-finding on, so the
firing instants would be artefacts of the slice count. That is precisely the class
of error the sweep exists to rule out.

Cost, stated: the vertex RHS now carries a scenario input. Accepted because the
alternative puts a numerical artefact in the headline result.

**Two things the ramp must not break.** It introduces explicit `t`-dependence into
a right-hand side that `find_fixpoint` solves *before* `t_start`. M2's flat-start
acceptance criterion — a model placed off equilibrium rings from `t = 0` with a
plausible oscillation that is pure initialization artefact — must survive, and
step 5 must assert the ramp is **inert at the fixpoint solve**. A mis-signed
`t_start` would otherwise seed the run off equilibrium, and the resulting
oscillation would look exactly like physics.

**The cascade magnitude is NOT settled, and must not be inherited.** The doc being
replaced quotes two figures for the same cascade:

- §7.3's probe parameters: *"Iberian loss ramped to the report's **5,750 MW** by
  12:33:20.560"*;
- §7.4's sweep table: **2,773 MW** labelled *"(report)"*, with its ±30 % cells at
  1,941 and 3,605.

They differ by more than 2×, and the sweep's own headline finding is that the slip
boundary *"tracks cascade magnitude almost one-for-one"* — so this is not a
cosmetic discrepancy, it decides whether step 6 reproduces anything.

What the citation source (`docs/scenarios/iberia-2025-04-28.md`) actually supports:
cumulative **generation** loss in Spain reached **>2.5 GW by 12:33:18.020** (p.11)
and **≈5,750 MW by 12:33:20.560** (p.119). The 2,773 figure appears **nowhere** in
the scenario doc and does not reconstruct from its Table 3-1 clusters by any
grouping (4a+4b ≈ 725, 5a/5b ≈ 930, 6a/6b ≈ 650, 7–13 ≥ 2,600). It is an unsourced
intermediate.

Compounding it, §2 of the plan doc explains exactly how a 2× gap arises in this
event: at the −1 Hz/s moment the Iberian imbalance was ≥6,150 MW **of which
≈5,000 MW was the export swing**, not generation loss. So "imbalance" and
"generation lost" are different quantities here and one of the two figures may be
the wrong one.

**Therefore step 6 must re-derive the ramp magnitude from Table 3-1**, state which
quantity `rate·duration` represents (generation lost, not apparent imbalance), and
reconcile the staged discrete losses *before* the ramp with the cumulative 5,750 MW
at 12:33:20.560. It is a checklist item, not a discovery to be made mid-step.


**What step 5 found, and it was not on the checklist.** Three things, all of which
changed the shipped code rather than only its comments.

1. **`find_fixpoint` had been evaluating the vertex RHS at `t = NaN` since M2, and
   nothing had noticed.** NetworkDynamics' `find_fixpoint` defaults its evaluation
   time to `NaN` (it wraps the network in a `NetworkFixedT` and passes that through
   verbatim). That was harmless for four milestones because no vertex RHS read `t`
   at all. The moment one does it is fatal, and **not only for a real ramp**:
   `clamp(NaN − t_start, 0, d)` is `NaN`, `0.0 · NaN` is `NaN`, so a machine with
   `rate = 0` — every machine in every existing model — would have NaN'd the
   steady-state solve of the whole repo. The constructor now passes `t = t0`
   explicitly. That is also just the right question ("what is this system's
   equilibrium at the instant the run begins?"), and it is what makes the ramp
   *structurally* inert at the solve rather than inert by luck: `t_start ≥ t0` is
   enforced, so `clamp(t0 − t_start, 0, duration)` is exactly `0` there. Asserted
   directly, `swing_vertex!` at `t = NaN` and at `t = 0`, so the line cannot later
   be deleted as decoration.

2. **A generator trip has to take its ramp with it.** `Pm_eff = Pm + ramp`, so
   `inject!(::TripGenerator)` zeroing `Pm` alone leaves the ramp term standing on
   its own — and an offline machine is decoupled from every branch, so it would be
   a dead, undriven rotor still being injected into. This is precisely the
   re-opening the D5 note above predicted when it said *"step 5's ramp puts
   `t`-dependence into the vertex RHS, which is exactly what would re-open the
   physical case quietly."* It is closed by construction (the rate is zeroed with
   `Pm`, the droop gain and the headroom), and asserted from **outside** the
   parameter vector: the dead rotor's own undriven decay `ω_trip·e^{−t·D/2H}` to
   `rtol = 1e-6`. Reading `rate` back would have passed even if the RHS ignored it.
   The survivors' settling frequency is asserted too and labelled as the half that
   **cannot** tell the two runs apart, since a tripped machine's power reaches
   nobody either way — step 4's V6 lesson, applied before it could bite.

3. **The planned corner check was vacuous, and the rewrite is what has teeth.**
   "Arm protection whose threshold the run never reaches; assert nothing fires at
   `t_start` or `t_start + duration`" passes with the ramp term deleted from the
   RHS — nothing fires because nothing happens. That is step 3's V5 trap and step
   4's V6 third clause for a third time. What is asserted instead is a ladder whose
   threshold the ramp *does* cross, at 49.15 Hz, chosen so the crossing lands **10
   ms before** the far corner: it fires at `3.989737 s`, sits 100× closer to the
   recorded frequency crossing than to the corner it nearly touches, and moves by
   less than `6.2e-8 s` over a 4× change in `dt`.

**No `tstops` are pinned at the corners, and that was decided by measurement.** The
defensive move is to hand `init` a `tstops` at each kink so the solver lands exactly
on it. The `dt`-halving measurement above — four thresholds, crossings before,
straddling and after both corners — says the root-found instant is already stable to
`6.2e-8 s`, orders below anything asserted. And `tstops` would change the step
sequence, which would destroy the zero-rate bit-identity that proves this whole
parameter addition perturbed nothing. Cost with no benefit, so: none.

**`rate` is in pu/s on `S_base`, not MW/s.** The tempting choice is MW/s, to match
`Machine.P0`. It is wrong here for the reason the model file already states:
`machine_arrays`/`branch_arrays` are the *single* place model data converts to the
system base. A ramp is not model data — it is an engine-armed setting, and the
precedent is `LoadShedStage(threshold_hz, ΔP_pu)`, which takes pu for exactly this
reason. MW/s would have opened a second conversion site next to the invariant that
forbids one.

**Headroom deliberately does NOT move with the ramp**, and that is a physics
decision rather than an omission. The governor still saturates at `Pmax − P0`, so a
ramping machine's *total* mechanical ceiling is `Pmax + rate·(elapsed)` — it travels
down with the generation that is leaving. That is the right behaviour for a fleet
losing units, and it is already what `Pmax` means here: a net-injection ceiling, not
a nameplate (D4). It ships with the counterfactual step 1's rule demands — a governed
machine with 20 MW of reserve carrying a 150 MW ramp pins its `ΔPm` at exactly its
headroom and ends up **absorbing** 1.0 pu, which is asserted as a number. That same
fixture is also the first place a nonzero ramp, real droop and a shed ladder all sit
on ONE machine — the Iberian shape, and a configuration every other step-5 test
avoided by ramping the governor-free machine.

**The magnitude claim, which is what step 6 actually needs.** Where the system
settles depends only on the total `rate·duration`, never on the path — so one
closed form validates the ramp's magnitude *and* its shape at once. Three shapes
delivering the same −1.5 pu (`−0.5×3`, `−1.5×1`, `−0.15×10`) all land on step 2's
droop closed form `Δω = ΔP/(Σ1/Rᵢ + ΣDᵢ) = −0.009375` to `rtol = 1e-9`. Sizing that
run's reserve needs the **peak** governor command (≈1.19 pu) and not the settled one
(0.9375 pu) — 26 % apart, and a reserve chosen from the settled figure would have
silently saturated the run so the "closed form" was asserting the ceiling instead of
the droop. Step 2's lesson, and it recurred here unprompted.

### D8 — A real system base, chosen once

M1's Iberian script used `s_base(H_tot) = KE/H_tot`, making the base an artefact
of the inertia choice. That does not survive two machines carrying `H` on their
own bases. M3 fixes **`S_base = 10,000 MVA`** and derives everything onto it.

Proposed two-area data (all `[CHOICE]`/`[GUESS]` unless marked, sourced from
`docs/scenarios/iberia-2025-04-28.md` and the plan doc's own sweep):

| | Iberia | Continental Europe |
|---|---|---|
| kinetic energy | 119,474 MWs (Table 2-4, p.36) **[FACT]** | 800,000 MWs **[GUESS]** |
| `S_rated` | 48,567 MVA | 266,667 MVA |
| `H` (own base) | 2.46 s (midpoint of the report's 2.21–2.71) | 3.0 s |
| `P0` | −1,000 MW (net import over the tie) | +1,000 MW |
| `R` | 0.05 pu | 0.05 pu |
| `Tg` | 8 s | 8 s |

Both machines are rated **away** from `S_base`, on purpose: M2 established that a
rating equal to the base hides a missing or inverted per-unit conversion behind a
weight of 1.

`Σ P0 = 0` holds, which the `NetworkModel` constructor requires (lossless network).

### D9 — Tie strength is a reactance, and the sweep mutates `K`

`P_max` is not a field. With `E′ = 1.0 pu` on both machines and `K` in pu on the
system base, `K = E′₁E′₂/X` and therefore

```
X = E′₁·E′₂ / (P_max / S_base)
```

At `P_max = 3,500 MW`: `K = 0.35 pu`, `X = 2.857 pu`. Say this out loud in the
scenario file or the sweep quietly becomes a sweep over something else.

**Two checks the sweep must pass at its weakest cell**, not just at the nominal
point:

- The constructor's `|P0ᵢ| ≤ Σⱼ K_ij` guard. Pre-event flow is 1,000 MW = 0.1 pu;
  the weakest swept tie is 2,500 MW = 0.25 pu. Passes, with margin — but it is a
  *construction* error, so a careless widening of the sweep turns into a crash
  rather than a wrong number, which is the good failure mode.
- The resulting steady-state angle: `δ₀ = asin(0.1/K)` — 16.6° at the nominal tie,
  23.6° at the weakest. Both comfortably inside the stable branch.

The sweep should mutate `K` in the live parameter vector (`K_pidx` already exists
for `TripLine`) and re-solve, rather than rebuilding a `NetworkModel` per cell.

### D10 — Step 6 is done when the sweep is regenerable, not when the trace looks right

The reason this milestone was chosen is that three quoted numbers in
`entsoe-iberia-reproduction.md` §7.3 are tuned-parameter artefacts. §7.4 already
worked out what a defensible claim looks like: the bracket-closure result survives
the whole grid, the timing claim survives as *"within ~1 s at any tie strength in
the lower two-thirds of the plausible corridor"*, and the knife-edge inference is
retracted. So the acceptance criterion is the grid, in the repo, regenerable — and
every surviving single-point number labelled as one cell of it.

If step 6 ports the probe and prints three numbers again, it has recreated the
exact problem it was chosen to close.

### D11 — The droop settling denominator sums the SURVIVORS, not every machine

Found in step 2, and it is a correction to `m3-plan.md`'s own V2 line rather than
a detail of it. The plan states the settling speed as M1's closed form:

```
Δω = −ΔP / (1/R_eq + D)
```

In M1 that `D` is **one system-wide load-damping constant** which a generator trip
does not change — M1 has no per-machine anything. On the network tier `D` is per
machine and attached to a **rotor**, so transplanting the formula leaves a real
question the plan does not answer: after tripping G1, is `ΣD` taken over the
survivors, or over all three machines?

Both are defensible on inspection, and on `governed_ring` they are **3.75 % apart**
— `−0.8/154 = −0.0051948` against `−0.8/160 = −0.0050000`. That is far too large to
absorb into a tolerance and far too small to look like a bug: the wrong one would
have shipped as a validation failure that read as broken physics.

**The answer is survivors only, and the mechanism is not the one to reach for
first.** The tempting argument is "a dead rotor is still a mass with damping, still
coupled, so the survivors must feed its damping and its `D` belongs in the sum."
That would be right if the machine were still connected. It is not:
`inject!(::TripGenerator)` zeroes `Pm`, the governor gain, the headroom **and the
coupling `K` of every branch incident to that bus** (`src/engines/swing.jl`). The
dead rotor is therefore *electrically islanded*. Its RHS becomes
`dω/dt = −Dω/(2H)` and, from a flat start, `ω ≡ 0` exactly — it draws nothing,
supplies nothing, and its damping never enters anyone's balance.

Note what this is **not**: `inject!` does not zero `D`, and `D` is not even a
mutable parameter of the compiled network. Checking "does the trip zero `D`?" —
the obvious check — gives the wrong reason for the right answer, and would leave
the conclusion resting on a fact that a later refactor could quietly change. The
load-bearing fact is the coupling.

Two consequences worth carrying forward:

- **The balance closes over the survivors** because the edge terms are
  antisymmetric and every edge touching the dead bus now contributes zero, so
  `Σ_survivors esum = 0` still holds:

  ```
  ω_settle = Σ Pm_survivors / (Σ_survivors 1/Rᵢ + Σ_survivors Dᵢ)
  ```

  Measured against the running engine to **8.7e-14 relative** after 150 s.
- **`is_online` for a line and "the line carries something" are different
  questions**, which `swing.jl` already says of the read-out and which this makes
  quantitative: the lines out of a tripped bus stay *in service* and carry
  *nothing*. A future reader summing damping over "connected" machines has to mean
  connected-with-non-zero-coupling.

This also sharpens V3. The dead rotor's speed is pinned at exactly zero while the
survivors drift at `ω_settle`, so its **angle difference against them grows without
bound**. "Angle differences settle after a trip" is true of the synchronised,
online set and false of the tripped machine — a distinction the step-2 tests assert
in both directions rather than leaving to a reader of this paragraph.

## Open questions to resolve during M3

- ~~**What does `coi_model` compile now?**~~ **SETTLED in step 1: it compiles the
  real droop.** `R` and `Pmax` pass straight through to the `GeneratingUnit`, so a
  governed network compiles to a governed aggregate. The alternative — keep
  producing a governor-free view so the comparison stays like-for-like — was
  rejected because it breaks SPEC §3.2: a view that *deletes* a property of the
  canonical model is not a compiled view of it, and the first governed network
  would have been compared against an aggregate with no primary response, a
  difference that would read as network dynamics. The comparison therefore now
  differs by inter-machine dynamics **and** by the collapse of several governors
  into one lag. For every fixture M2 shipped this is byte-identical to M2's output,
  so the change costs nothing today and is honest tomorrow.

  **`Tg` is the loose end, and it is loose on purpose.** `SystemModel` carries one
  system-wide lag; the network carries one per machine, and an aggregate of
  first-order lags is only first-order when they are equal. The shipped choice is
  the **droop-gain-weighted mean** `Σ(invRᵢ·Tgᵢ)/Σ invRᵢ`, falling back to `1.0`
  when no machine has droop (reproducing M2's arbitrary value exactly rather than a
  `0/0`). **Nothing in the validation suite can distinguish it from any other
  aggregation**: V2's settling value `Δω = −ΔP/(1/R_eq + D)` is `Tg`-independent, so
  it pins the gain and not the lag. The tests assert that the *weighting* is by gain
  rather than by MVA or unweighted — which pins the choice against silent drift, not
  against being wrong. Treat the number as unvalidated until something measures the
  **shape** of the aggregate response.
- ~~**Does the `isoutofdomain` predicate cost measurable time?**~~ **MEASURED in
  step 1: yes, and it does not matter.** On `three_machine_ring` (governor-free, so
  the predicate can never fire) the predicate costs **271 ns/call** against
  **1974 ns** for the `step!` it guards — about **14 %**, and the solver calls it
  once per proposed step, not once per RHS evaluation. Not free, and not worth
  branching the engine into guarded and unguarded variants to avoid: that would be
  two numerical paths for a seventh of one step, and the second path would be the
  one nobody tests. Revisit only if a profile of a large network says so.
- ~~**Does the out-of-step threshold belong to the branch or to the protection
  object?**~~ **SETTLED in step 4: the protection object.** `Branch` carries a
  `rating` the dynamics do not read, so there was an obvious pull to hang a
  `slip_threshold` beside it; it is the wrong place for the reason the shedding
  ladder is not a field of `Machine`. A threshold is a setting of a *defence plan*,
  not a property of a conductor, and keeping it off the topology is what lets ONE
  `NetworkModel` be run armed and disarmed — the counterfactual every step-4 test is
  built on, and the axis step 6's sweep varies. See D6.

## Reference

- `docs/plans/entsoe-iberia-reproduction.md` — §2 the fidelity boundary, §3 the
  three mechanisms, §7 the two-area model and the probe's provenance warning.
- `docs/scenarios/iberia-2025-04-28.md` — the report's own figures and citations.
- `src/engines/frequency_response.jl` — M1's governor, headroom saturation, and
  the `isoutofdomain` discipline being generalised here.
- `src/protection/load_shedding.jl` — the callback pattern step 3 rebinds.
- `src/engines/swing.jl` — the tier, the sign convention, the edge-ordering hazard,
  and the "no guard here" header note step 1 must amend.
