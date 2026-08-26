# M3 — Primary response and armed protection on the network tier · Plan

Companion docs: `m3-context.md` (decisions and what was measured behind them),
`m3-tasks.md` (the checklist). Layers on `docs/SPEC.md` §3–6 and the M2 trio.

## Goal

Give the multi-machine swing tier the two things the 28 April 2025 Iberian
blackout scenario needs and M2 does not have — **generation that responds to
falling frequency** (governor droop) and **protection that arms itself and fires
on the system's own state** (low-frequency demand disconnection per area, and
out-of-step tripping of a tie) — and then run the two-area Iberian case *inside
the repo*, on the real engine, replacing the throwaway probe whose numbers
`entsoe-iberia-reproduction.md` §7.3 already flags as tuned.

The milestone is chosen for exactly that reason: it closes work the repo has
already labelled unsound, and it needs **no new dependency**.

### Why this is one state, not a new model

`entsoe-iberia-reproduction.md` §7.2 names the five-state two-area model the
fidelity boundary needs: `δ`, `Δω`, `ΔPm` per area, with a **nonlinear** tie
`P = P_max·sin(δ₁−δ₂)`. M2 built the first two states and the sine. A two-area
system *is* `two_machine_system()` — two machines, one branch. What is missing is
`ΔPm`, the shedding ladder's binding to a named area, and the out-of-step trip.

## Fidelity tier — what this is and what it is not

Still the **reduced classical (network-swing)** tier: constant internal voltage
`E′` at each bus, no bus voltage as an unknown, pure ODE, no admittance matrix.
M3 does not move the tier — it adds a *control* state on top of it.

What M3 therefore still cannot do, unchanged from M2:

- **No voltage dynamics.** The report's last window (12:33:21.5 → blackout) is
  voltage collapse in an islanded system. Out of scope, and must not be claimed.
- **No AC power flow, no load buses, no network reduction** (M2b / roadmap step 4).
- **No turbine/boiler detail.** One first-order lag per machine, as SPEC §7.2.

And one thing M3 deliberately does not add, stated because the obvious assumption
is wrong (see below): **no secondary control / AGC.**

## The correction that shapes step 2

> With governors the system has a real equilibrium after a trip.

**False, and the plan is written against it.** At settle `dΔPm/dt = 0` and droop
gives `Δω = −ΔP / (1/R_eq + D)` — **non-zero**, because part of the deficit is
carried by load damping, which is not mechanical power. So `dδ/dt = ω₀·Δω ≠ 0`
and every angle still grows without bound. Governors make the drift *slower*, not
absent. M2's two standing rules therefore carry forward **verbatim**:

- never call `find_fixpoint` on a post-trip state — it cannot converge;
- never assert on an absolute angle — only on differences.

Only AGC (`dζ/dt = Δω`, `ΔP_agc = −Ki·ζ`; SPEC §7.2 "optional") drives `Δω → 0`
and makes angles settle. It is **out of scope for M3** and named here so that a
later reader knows the omission was chosen. Step 2's criterion is consequently
*"speed converges to the droop closed form and angle **differences** converge"*,
not "the system reaches a fixpoint".

## Approach (incremental; each step commits and leaves tests green)

### Step 1 — the governor state, alone on its own commit

`Machine` grows `R` (droop, pu on the machine's own base), `Pmax` (MW) and `Tg`
(s). Each vertex grows a third state `ΔPm`, per-unit on the system base:

```
dδᵢ/dt   = ω₀·ωᵢ
dωᵢ/dt   = (Pmᵢ + ΔPmᵢ + esumᵢ − Dᵢ·ωᵢ) / (2Hᵢ)
dΔPmᵢ/dt = (−ωᵢ/Rᵢ − ΔPmᵢ) / Tgᵢ        saturated at headroomᵢ in the DERIVATIVE
```

A governor-free machine is `R = Inf`, `Pmax = P0`: the derivative becomes
`−ΔPm/Tg`, which from a zero start holds `ΔPm ≡ 0`. So M2's models remain
expressible and every existing test still describes a real system.

**No new scenario ships alongside this step.** The 1234-test suite is the only
oracle in the repo that can find a bug in a state-layout change — the same
discipline as M2's recorder retrofit, for the same reason.

**M2's numbers get re-pinned once, here, and the plan says so in advance.**
Bit-identity with M2 is not achievable and this was measured, not assumed (see
`m3-context.md` D1): the solver's error norm is averaged over the state vector,
so adding a third entry per machine — even one whose derivative is identically
zero — changes the accepted step sequence from the second step onward. The
safety net is therefore *agreement to solver tolerance*, with the old values
recorded in the context doc beside the new ones.

> **Outcome (step 1, measured): the re-pin did not happen.** Every gauge-free
> quantity came out bit-identical to M2 — `f_coi`, the angle differences, and the
> accepted/rejected step counts themselves. D1's probe measured a **free-running**
> integration; this engine is driven by `step!(integrator, dt, true)`, which forces
> a stop at every `dt`, and both versions were already taking exactly one internal
> step per `dt`. The mechanism the probe identified is real and had no room to act.
> The one number that moved was the fixpoint's arbitrary gauge. Full table and the
> transferable lesson — a numerical probe must reproduce the *stepping discipline*
> of the code it predicts, not just its right-hand side — in `m3-context.md` D1.

**The `isoutofdomain` guard, and the header note it contradicts.** M1 uses an
`isoutofdomain` predicate to reject (not clamp) steps that overshoot headroom.
`swing.jl`'s header currently states there is deliberately **no** such guard here,
because nothing in the engine is bounded and a copied guard would fire spuriously
on the drifting angles. That reasoning is still correct for `δ` and `ω` and is now
incomplete: `ΔPm` *is* bounded. The predicate must test **only the `ΔPm` indices**,
and the header note must be amended **in the same commit** — otherwise the file
reads as forbidding the guard it contains.

### Step 2 — what primary response actually does, asserted

Validation only (V1–V4 below). No new mechanism, no `src/` change, no new export.

> **Outcome (step 2): green, +68 tests, and two things the plan had wrong.**
> The settling denominator sums the survivors, not every machine (D11, above and
> in `m3-context.md`) — a 3.75 % error that would have read as broken physics. And
> V1's real content turned out not to be the three closed-form constants, which the
> M2 testsets already assert against this engine, but **invariance to the governor
> parameters** now that `Tg` and `Pmax` are read by the fixpoint solve: three of
> four variants come out bit-identical and the fourth differs by 4 ulp, which a
> gauge-shift probe then attributes to the fixpoint's arbitrary gauge rather than
> to `Tg` — step 1's D1 finding, in a second place.

### Step 3 — the shedding ladder, unbound from the M1 engine (refactor)

`ShedLadder` today triggers on `FrequencyResponseEngine`'s single `f` and steps a
global `ΔP_dist`. On a two-area model that is **wrong in a way that still runs**:
Iberia sheds and Continental Europe does not, and `f_coi` across a separating pair
is the "weighted average of two unrelated numbers" `swing.jl`'s own header calls
meaningless. A ladder driven by it would produce a plausible trace and shed at the
wrong instants.

So a ladder **binds to one named machine** and firing changes **that machine's**
`Pm` parameter. On the aggregate engine the named machine is the whole system, so
M1's behaviour is the one-machine case of the general one — this is a refactor of
working code and ships as one, with M1's existing shed tests unchanged.

### Step 4 — out-of-step protection (new mechanism)

> **Two interactions this section did not anticipate, both settled in step 4
> (`m3-context.md` D6).** A **generator** trip at either end disarms the relay — the
> dead rotor's angle freezes while the survivors drift on forever, so the angle across
> an incident branch crosses any threshold on pure gauge drift, on a branch whose
> coupling that same trip had already zeroed. And **opening a branch disarms every
> relay on it, whoever opened it**, because `inject!` no-ops on an already-open branch
> and a relay left armed would otherwise log a protection operation that opened
> nothing. Same asymmetry as the shedding ladder, in the same direction.

A `ContinuousCallback` root-finding the instant `|δ_from − δ_to|` crosses a
threshold on a named branch, which then trips that branch through the existing
`inject!(::TripLine)` path. Latching, like a shed stage: it does not re-close.
This is the report's tie separation at 12:33:21.54, and it is the reason the
scenario ends in two islands rather than in a numerical runaway.

Separate step and separate commit from step 3: one is a refactor of code that
works, the other is a mechanism with no precedent in the repo.

### Step 5 — generation lost as a ramp, not an instant

The report's cascade arrives over ≈2.46 s. **Its magnitude must be re-derived, not
inherited** — the doc being replaced quotes two figures that differ by more than
2× (`m3-context.md` D7), and the sweep's own finding is that the slip boundary
tracks cascade magnitude almost one-for-one. M2 has only instant
trips. Rather than staircase it into N discrete trips — whose edges would give the
root-finding protection of step 4 artificial firing instants — the vertex carries
a ramp: `Pm_eff = Pm + rate·clamp(t − t_start, 0, duration)`. Exact, continuous,
three extra parameters, and it is the input the sweep varies.

### Step 6 — the Iberian two-area case, in-repo, with its sweep

A `NetworkModel` of two machines and one tie, from the report's own figures, run
by a script beside `scripts/iberia_2025_04_28.jl`. **Acceptance is the sweep, not
the trace**: the step is done when the parameter sweep over tie strength, remote
inertia and cascade profile is in the repo and regenerable, and the single-point
numbers are either deleted or explicitly labelled as one cell of that grid. A port
that prints three tuned numbers again has recreated the exact problem this
milestone was chosen to close (`entsoe-iberia-reproduction.md` §7.3–7.4).

### Step 7 — Figure 3-67, or drop it explicitly — **BUILT, not dropped**

Frequency trace with horizontal threshold lines and shed annotations — the single
highest-value figure in the report's catalogue, carried open across M1 **and** M2
because it ticked no acceptance criterion. It gets one here: *the shed-annotated
panel renders offscreen from the two-area run, with each stage's marker at the
root-found instant from the shed log, and the offscreen render is checked in as
the proof.* If the batch runs short this is the item to drop — the sweep being
in-repo is worth more — and dropping it means saying so, not carrying it a third
time.

> **Resolved by building it.** The drop clause is for a batch that has run short,
> and this one had not: steps 1–6 were done and green, and the criterion above was
> both small and, for once, falsifiable. `docs/images/fig-3-67-two-area.png`,
> rendered by `ui/scripts/figure_3_67.jl`. It is an **annotation on the real
> window**, not a bespoke figure — the repo's standing rule that a headless PNG
> must be a picture of the window a user opens, or it drifts from it.
>
> Two things the criterion did not anticipate, both in `m3-tasks.md` step 7. The
> aggregate overlay had to be **suppressible**, because on a two-area model it is
> the quantity D5 calls meaningless and it is the heaviest line in the panel — and
> suppressing the line alone would have moved that number to the top of the
> read-out, where it reads as the answer. And the cell being drawn **still loses
> synchronism with the defence plan armed**, which is the opposite of what the
> older aggregate-tier notes led us to write, so the figure's caption says which
> of the two failures the plan prevents and which it does not.

## Validation (assert in `test/`)

- **V1 — governor-free equivalence, against a solver-independent oracle.** A
  network with `R = Inf` on every machine must still satisfy M2's **closed-form**
  predictions — `K = 4.284 pu`, `δ₀ = 0.140518 rad`, `f_osc = 1.5911075 Hz`, and
  the V3 gap inside its stated bound — because those are derived, not measured,
  and a re-pinning cannot move them. Asserting instead against "M2's recorded
  values" would be circular: step 1 re-pins those very constants, so the check
  would pass by construction. The re-pinning is then what it should be — a
  measurement that must still satisfy an independent prediction, not a new
  baseline that defines its own success. Both old and new measured values are
  recorded in `m3-context.md`.
- **V2 — the droop closed form.** Step imbalance `ΔP`: speed settles at
  `Δω = −ΔP/(1/R_eq + D)` and mechanical power rises by `−Δω/R_eq`. Asserted on
  the **running engine**, not on the formula.

  > **Corrected in step 2 (`m3-context.md` D11): the sums run over the SURVIVING
  > machines.** The line above is M1's, where `D` is one system-wide *load* damping
  > that a trip does not change. Here `D` is per machine and bolted to a rotor, and
  > `inject!` zeroes the coupling of every branch incident to a tripped bus — so the
  > dead rotor is electrically islanded, holds `ω ≡ 0` exactly, and its damping
  > enters nobody's balance. The two readings differ by 3.75 % on `governed_ring`,
  > which is too big to hide in a tolerance and too small to look like a bug.
- **V3 — angle differences settle, absolute angles do not.** Post-trip, assert
  `δᵢ − δⱼ` converges and assert that the common mode keeps drifting at
  `ω₀·Δω_settle`. This pins the correction above as a *tested property* rather
  than a paragraph.
- **V4 — headroom saturates in the derivative.** A machine given headroom smaller
  than droop would command stops at exactly `headroom`, comes **off** the ceiling
  unaided once frequency recovers, and the `isoutofdomain` predicate never fires
  during continuous integration. Plus: the predicate ignores `δ` and `ω` — assert
  it directly against a state with a large drifted angle.
- **V5 — the ladder sheds the right area.** Two machines, one falling; assert the
  falling one's `Pm` changes and the other's does not, and that a ladder bound to
  the *other* machine does not fire. A `f_coi`-driven ladder would pass a
  "something shed" test — this is the assertion that would catch it.
- **V6 — out-of-step timing is a root, not a step.** Halving `dt` moves the trip
  instant by less than solver tolerance; the tie's power reverses sign before the
  trip (the report's export swing); and the trip leaves two islands, each holding
  its own frequency.

  > **Corrected in step 4 (`m3-context.md` D6): the third clause, asserted alone,
  > passes with the relay deleted.** A fully slipping tie transfers almost no NET
  > power — `K·sin` of a monotonically growing angle averages to zero — so both areas
  > drift to their islanded closed forms whether or not anything opens the tie. On
  > the step-4 fixture the unarmed run reaches the same two frequencies to ~3e-5.
  > What discriminates, by four orders of magnitude, is the tie power itself (exactly
  > `0.0` armed against a full `±K` swing that never decays) and the residual ripple
  > in the two speeds (7.6e-10 against 3.1e-4). The closed forms are still asserted;
  > they are just labelled as the half that cannot tell the two runs apart. This is
  > step 3's V5 trap in a second place, and the step-3 fixture had to be measured and
  > rejected before a new one was built.
- **V7 — the sweep's shape, not its cells.** Assert the *monotone* property the
  sweep established (a stiffer tie slips later, and above a boundary never slips),
  not a tuned number. A cell value that moves with a solver version is not a
  result; the ordering is.

## Pitfalls carried into M3

- **Post-hoc state clamping is still banned.** Headroom is a derivative
  saturation plus a step-rejecting predicate. `inject!` re-seating `ΔPm` at an
  event boundary is a discrete jump at a discontinuity, not a mid-integration
  clamp — same justification as M1's, and it must be re-stated per machine.
- **Per-machine speed is not aggregate speed.** M2's four distinct names
  (`δ`/`ω` per machine, `ω_coi`/`f_coi` aggregate) now gain `ΔPm` per machine.
  Do not add an aggregate `ΔPm` read-out that invites the same conflation.
- **`coi_model` must be revisited.** It currently compiles a *governor-free*
  `SystemModel` (`R = Inf`, `Pmax = P0`) precisely so the cross-fidelity
  comparison differs by inter-machine dynamics alone. With real droop on the
  network model it must compile the real aggregate droop — and the comparison
  then means something different. Say which in the code, not just here.
- **Check every new export against `GLMakie`** before writing UI code — the
  collision hazard that has now cost a round twice.
- **The `ui/` manifest is gitignored too.** A dependency change in `src/` that the
  UI package needs is invisible until a UI test runs; M2 was bitten six steps
  after the fact.

## Out of scope for M3

Secondary control / AGC · voltage dynamics and the DAE tier · load buses and
network reduction (M2b) · `PowerSystems.jl` as canonical model (roadmap step 4) ·
the full-electromechanical playback overlay (roadmap step 3) · markets/OPF · maps ·
the report's post-separation collapse window.

## Carried over, still open

- ~~Figure 3-67 — now step 7, **with** an acceptance criterion for the first
  time.~~ **CLOSED.** Built at step 7 rather than dropped;
  `docs/images/fig-3-67-two-area.png`. The pointers in `m1-tasks.md` and
  `m2-tasks.md` are ticked and say where it landed. Nothing carries into M4.
- `m1-tasks.md` still records unbounded trajectory growth as open; M2 step 3
  closed it. Fix the stale line in the first docs commit of this batch.
