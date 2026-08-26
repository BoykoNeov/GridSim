# Reproducing the ENTSO-E Iberian blackout report in GridSim

**Goal.** Use the 28 April 2025 Iberian blackout as GridSim's first *real* test
case — both as a validation target for the physics and as the source of a
visualisation vocabulary worth building toward.

**Data:** `docs/scenarios/iberia-2025-04-28.md` (extracted figures + page cites).
**Runnable:** `scripts/iberia_2025_04_28.jl` (headless, no Makie).
**Status:** the replay script exists; no *engine* changes have been made for this
yet — §3 lists the three mechanisms still missing.

---

## 1. The headline result: it already almost works

Before planning anything, the obvious question — *can today's engine reproduce
any of this?* — was tested directly. Answer: yes, a surprising amount, with
**zero new code**.

Feeding the report's own event sequence (net load rise +317 MW, then the 355 /
725 / 930 / ≈2,600 MW generation losses at their reported timestamps) into the
existing `FrequencyResponseEngine`, parameterised from the report's Iberian
kinetic energy (119,474 MWs, `H_tot = 2.46 s`):

**Reproduce with `julia --project=. scripts/iberia_2025_04_28.jl`** — that script
records every modelling choice behind these numbers (`S_base`, `D`, `Tg`, the
synchronous-block sizing) and marks which are report facts and which are ours.

| Report time | Reported f | Model f | Δ |
|-------------|-----------:|--------:|--:|
| 12:32:55    |      49.98 |  49.966 | −0.014 |
| 12:33:00    |      49.94 |  49.859 | −0.081 |
| 12:33:16+   |      49.90 |  49.865 | −0.035 |
| 12:33:17+   |      49.80 |  49.705 | −0.095 |
| 12:33:20    |      48.50 |  49.711 | **+1.211** |

> **Updated after the LFDD ladder landed (§3.1).** Two rows moved, and the
> prediction this section made below was confirmed. The 12:33:20 row went from
> **+0.232 to +1.211** — the ladder sheds 3,907 MW, the model recovers at 49.50 Hz,
> and the coincidental cancellation that made the old number look good is gone.
> The 12:33:17 row also moved (49.669 → 49.705), which is easy to miss: the
> 49.8 Hz pump-storage stage fires at 12:33:17.405, i.e. *before* that waypoint.
> The pre-boundary rows are otherwise unchanged, because nothing sheds above
> 49.8 Hz.

**The two windows fail in opposite directions, and reading this table as one
"close enough" verdict is wrong** — it papers over two unrelated causes and
would send someone tuning the wrong parameter.

- **Before 12:33:16 the model runs too deep** (−0.08 Hz at 12:33:00). Cause in
  (b) below.
- **After 12:33:16 the model runs too shallow** (+0.23 Hz at 12:33:20), and that
  last row is **coincidental cancellation, not calibration**. The script omits
  the ≈4,854 MW of pump-storage shedding that actually fired from 49.8 Hz
  downward (Table 3-14) — shedding pushes frequency *up*. Reality nevertheless
  fell *further* than the model, so the true late-window imbalance was well
  above the 2,600 MW injected. That is consistent with the report's own hedges
  (the 930 MW event "or even more than 1,100 MW"; the ≥2,600 MW figure is a
  floor; rooftop PV below the 1 MW reporting threshold is unobservable) and with
  the loss-of-synchronism export swing of §2. **Do not tune against this
  waypoint.** Adding the LFDD ladder (§3.1) will make this row *worse* before
  the under-modelled loss is corrected — that is expected and correct.
  **Confirmed:** the ladder landed and the row went to **+1.211**. With the real
  defence plan armed the model arrests the fall and recovers; reality shed
  ~15.5 GW and collapsed anyway. That divergence is now the headline of the
  script, and it is a cleaner statement of the boundary than the old near-miss
  ever was.

Two further observations are worth more than any of the agreement:

**(a) Inverter-based generation needs no new data model.** A PV/wind block is
already expressible as `GeneratingUnit(:PV, S, 0.0, P0, Inf, P0)` — zero inertia
contribution, `1/R = 1/Inf = 0` droop gain, zero headroom, and tripping it dumps
`P0` straight into `ΔP_dist`. Verified: aggregates stay finite, no `NaN`.
So the "renewables have no inertia" lesson is already representable. Now a
**regression test**, not just an observation — including the all-IBR corner
(`H_sys = 0`, `R_eq = Inf`, zero headroom, still no `NaN`).

**(b) The pre-separation window needs *two areas*, and the data proves it.**
Running the same script with a Continental-Europe-scale base instead of an
Iberian one gives 49.987 Hz where the report says 49.94 and the Iberian-only
model says 49.859. The observation is **bracketed** by the two single-area
parameterisations. That is exactly right physically: until 12:33:16 Iberia was
synchronously inside Continental Europe, so its effective response is neither
its own inertia nor the whole CE area's, but CE's *filtered through a finite
tie* — ≈3 GW of AC lines, with the 2 GW HVDC in constant-power mode contributing
no frequency support at all. Fig 1-4 (p.12) shows exactly this: the Iberian and
CE traces sit on top of each other, then split at ≈12:33:16.

Closing that bracket is a two-area model with a tie-line — a well-defined,
motivated next physics step, not a vague "more fidelity" wish.

---

## 2. The fidelity boundary (read this before claiming any validation)

**The centre-of-inertia model cannot reproduce the last ~5 seconds, and must not
be presented as if it could.**

The report is explicit. At the moment −1 Hz/s was first reached (12:33:20.560),
the Iberian imbalance was ≥6,150 MW, but ≈5,000 MW of that was the *export
swing* caused by the loss of synchronism — power sloshing across the ES–FR
border as the angle difference ran past 90° and then 270° (p.119). The report
states plainly that the border RoCoFs "were not only caused by the demand
generation imbalance … but were also strongly influenced by the transient
associated with the loss of synchronism" (p.118).

None of that mechanism exists in a two-state swing + governor model. Feeding the
cumulative-loss curve into a COI model and matching the collapse would be
matching a number while missing the physics that produced it.

**§7 shows how to get past this boundary** — and that it is a five-state model,
not a second process.

**Honest reproduction windows:**

| Window | Content | Status |
|--------|---------|--------|
| 12:32:00 – 12:33:16 | Slow drift, event 3 | Needs a tie or a CE-scale base; single-COI brackets it |
| 12:33:16 – 12:33:19.6 | Staged loss 49.9 → 49.8 → collapse onset | **Faithfully reproducible today** |
| 12:33:19.6 – 12:33:21.5 | Loss of synchronism, LFDD ladder, ES–MA trip | LFDD reproducible; the swings are not |
| 12:33:21.5 – 12:33:27 | Islanded Iberia, voltage collapse, blackout | **Out of scope** — needs angle + voltage dynamics |

---

## 3. What is missing — exactly three mechanisms

Everything else the frequency story needs, the engine already has.

### 3.1 Low-frequency load shedding as a latching threshold event

**DONE** — `src/protection/load_shedding.jl` (`LoadShedStage` / `ShedLadder` /
`shed_log` / `shed_total`), armed via `init!(…; shed = stages)`. Built as
separate `ContinuousCallback`s in a `CallbackSet` rather than one
`VectorContinuousCallback`: with ~12 stages a per-stage closure beats the vector
form's disarmed-sentinel bookkeeping. Two things were subtle enough to be worth
recording:

- **The latch must hold the sign it had *after* firing** (negative, for a
  downward crossing of `f − threshold`). Returning `+1.0` when disarmed
  manufactures a sign change at the disarm instant, which the rootfinder reads as
  a fresh crossing ⇒ double shed.
- **`affect!` is the upcrossing, `affect_neg!` the downcrossing.** Asserted in
  both polarities rather than trusted: `example_system` is underdamped, so one
  run supplies an upward and a downward crossing of the same threshold ~6 s
  apart, and the test demands silence on the first and a firing on the second.

One expectation did **not** survive contact: the shed `affect!` mutates `p`
without touching `u`, which is the stale-FSAL hazard `inject!` has to arm against
by hand — but `apply_callback!` sets `derivative_discontinuity` *before* invoking
the affect for a `ContinuousCallback`, so no explicit call is needed on this path.
Checked in the DiffEqBase source and verified empirically (removing it changes a
10× `dt` refinement by ~5e-14). A `dt`-refinement test guards it, because the
error would be invisible to any readout assertion — `current_state` recomputes
RoCoF algebraically, so it would report the right value while the integration
drifted.

The single architectural addition. Each threshold (49.5, 49.3, 49.0, 48.8, 48.6,
48.4, 48.2, 48.0 Hz) arms a one-shot shed of a known MW amount.

**Implement as a `ContinuousCallback` per stage, not as an `f < threshold` check
in the orchestration loop.** Two reasons:

1. The callback **root-finds the exact crossing instant**. The report annotates
   its charts with the precise time each stage fired; a per-step comparison in
   the loop is only accurate to `dt` and cannot produce that annotation.
2. Physics belongs in the engine, not in the loop. The orchestration loop is
   engine-agnostic by design (`docs/SPEC.md` §7.5) and must stay that way.

Downward direction only; `affect!` disarms its own stage so it fires once.

This is the **sanctioned** callback path, not the forbidden one: the project's
carried-forward correctness rule bans *post-hoc clamping of a state variable*.
A discrete, physically-real load-shedding event that steps `ΔP_dist` at a
root-found instant is a legitimate discrete jump — the same class as the
existing `inject!` event-boundary handling.

### 3.2 Cumulative tripped-MW bookkeeping

**DONE** — `eng.tripped_mw` plus a `tripped_mw` vector in `state_series`.
Generation only: shed load is not generation and is logged separately in the
ladder. Tested against double-counting a re-trip of an already-offline unit.

Figures 1-3, 3-7 and 3-9 all plot **cumulative tripped generation** on a second
axis against voltage or frequency. The information is entirely in the event log;
the engine simply does not accumulate it. Small addition to the recorded
trajectory alongside `ts/fs/rocofs/pms`.

### 3.3 500 ms windowed RoCoF

**DONE** — `windowed_rocof` in `src/analysis/postprocess.jl`, engine-agnostic
(takes vectors or a `state_series`). Same length as the input with `NaN` before
the window fills, so it overlays directly on `f(t)`; divides by the **actual**
elapsed time rather than the nominal window, since samples need not be uniformly
spaced. The script uses it for the one RoCoF claim that lies inside the faithful
window — the report's "|RoCoF| stayed within 1 Hz/s until 12:33:20.560" — which
the instantaneous value could not legitimately be checked against.

**Every RoCoF number in the report is a 500 ms sliding window** (ENTSO-E best
practice, stated on p.116). `current_state` returns the instantaneous
`f0·dΔω/dt`. During the fast transient these differ substantially, so comparing
the instantaneous value against "−1 Hz/s at 12:33:20.560" would be comparing two
different quantities.

Add windowed RoCoF as an **additional post-processing read** over the recorded
trajectory — not as a replacement for the instantaneous value, which stays the
live readout and the closed-form validation target (`docs/SPEC.md` §7.6).

### 3.4 Two open questions to decide consciously, not by default

**BOTH DECIDED**, in `scripts/iberia_2025_04_28.jl`.

*Load inertia:* documented, not modelled. `H_tot` sits entirely on the
synchronous fleet. That is **exact** for the frequency trajectory — the swing
equation only ever sees the total — and becomes an approximation the moment load
inertia would have to leave with shed load, which now matters, since the ladder
sheds 3.9 GW of load. Recorded at the top of the script; an `H_load` field is
deliberately *not* added at M1.

*Which base:* keyed off `KE`. The consequence is sharper than expected and is
worth stating plainly, because the script's own sensitivity table looks like a
result and is not: `S_base = KE/H_tot` makes `f0·ΔP/(2·H_sys)` collapse to
`f0·ΔP_MW/(2·KE)`, so **the published 2.21–2.71 s band cancels out of the initial
RoCoF exactly**. The band is uncertainty about how to *split* a measured kinetic
energy between machines and motor load, and a single-frequency model does not
care about the split. What the band does move is `S_base`, hence the fleet's
per-unit droop and damping (8.9 → 10.6), which nudges the disarmed nadir ~0.08 Hz
— *deeper at higher inertia*, the giveaway that it is not an inertia effect at
all. The genuine inertia-only comparison, everything else held fixed, lives in
`test/runtests.jl`. Bottom line: the ~1.2 Hz late-window gap **cannot** be
attributed to inertia uncertainty.

The original framing of both questions follows.

- **Load inertia.** The report's `H_tot = H_eq + H_loads`, and the 2.21–2.71 s
  range exists *because* `H_loads` is uncertain. GridSim has no load-inertia
  term, so setting `H_sys` from `H_tot` silently conflates rotating-load inertia
  with generator inertia. Either add a system-level `H_load` field or document
  the conflation. Either way the published range is a **ready-made sensitivity
  experiment**: run the scenario at 2.21 and at 2.71 and show how much the nadir
  moves.
- **Which base.** `S_base = KE/H_tot` makes the base an artefact of the inertia
  choice. Keying scenarios off `KE` directly (`RoCoF = f0·ΔP/(2·KE)`) is
  base-independent and less error-prone.

---

## 4. Visualisation catalogue

Sorted by *what a chart requires*, deliberately separating **visual archetype**
(a layout we can draw) from **physical mechanism** (state we would have to
simulate). A chart can be in bucket A even if part of its content is context we
draw rather than compute.

### Bucket A — buildable on M1 state

| Archetype | Report figure | Notes |
|-----------|---------------|-------|
| Frequency trace with nominal reference | 1-4, 3-8 (top) | The core M1 plot |
| Stacked frequency + RoCoF panel | 3-8, 3-11 | Two linked axes, shared time cursor |
| Frequency with **horizontal threshold lines** and shed annotations | **3-67** | **BUILT** (M3 step 7) — `docs/images/fig-3-67-two-area.png`, and on the two-area tier rather than this bucket's M1 one |
| Cumulative tripped MW on a second axis | 1-3, 3-7, 3-9 | Needs §3.2 |
| Dual-axis frequency + border exchange | 3-11 | Exchange is a scripted input at M1, not a simulated flow |
| Shed-per-threshold bars + cumulative line | 3-64, 3-68 | Pure post-processing of the shed log |
| Two frequency traces, one flat at 50.0 | 1-4 | The CE trace is **honest drawn context**, not a second simulated area — label it as such |

### Bucket B — needs the two-area / tie-line step (§1b)

| Archetype | Report figure |
|-----------|---------------|
| Two genuinely diverging area frequencies | 1-4 |
| Tie-line flow reversal and angle-driven swings | 3-12, 3-15 |
| Loss-of-synchronism impedance trajectories | 3-51, 3-54, 3-57 |

### Bucket C — needs network + voltage state (well beyond M1)

| Archetype | Report figure |
|-----------|---------------|
| Multi-bus voltage magnitude traces with limit bands | 3-4, 2-70 |
| Geographic voltage heat maps | 3-2, 2-80 |
| Event map with clustered, time-coded markers | 3-1 |
| Oscillation mode estimation (freq / amplitude / damping over time) | 2-66 |
| Mode-shape polar plots | 2-67, 2-77 |
| Spectrograms, band-pass filtered oscillation overlays | 2-64, 2-69 |
| Generation-mix stack during restoration | 4-24, 4-28 |

Bucket C is the honest answer to "reproduce the visualisations": most of the
report's *charts* are network- and voltage-aware, and GridSim is a
frequency-only simulator today. That is a roadmap, not a defeat — buckets B and
C name specific physics, in dependency order.

---

## 5. Sequencing — this is M1 content, not a parallel workstream

Every `docs/SPEC.md` §7.8 acceptance criterion is still unchecked, including
"core runs headless from a script and produces a frequency trajectory with no
Makie dependency". The queued work is: validation tests → headless script →
GLMakie UI.

This scenario should be **the content of that batch**, replacing `example_system`
as the demo, rather than being scheduled after it.

- **Done.** `scripts/iberia_2025_04_28.jl` — the staged sequence as a headless,
  Makie-free script. Ticks §7.8's first criterion with real content.
- **Done.** §3.1 LFDD callback + §3.2 cumulative bookkeeping + §3.3 windowed
  RoCoF, all three wired into the script, plus §3.4's two decisions. Everything
  Figure 3-67 needs is now computed: threshold lines, root-found shed instants to
  the millisecond, per-stage MW, and the cumulative-tripped second axis. Only the
  drawing is missing.
- **Done.** The waypoints as *test assertions*, with tolerances that encode the
  two-window structure by **sign** rather than a single band, and with the
  12:33:20 row asserted as a known structural failure rather than banded. The
  script is included as a module by the test file so the scenario stays
  single-sourced.
- **Done.** GLMakie UI, with the ENTSO-E chart archetypes in bucket A as the
  layout targets rather than an ad-hoc plot. Figure 3-67 was the first target and
  is built (M3 step 7) — though not where this line expected it: the annotation
  went into the **two-area** window, not the aggregate one, because by the time it
  was drawn the frequency worth annotating was Iberia's own and not an
  inertia-weighted mean of Iberia and Continental Europe (D5).
- **M2 candidate.** Two-area + tie-line, motivated by the bracket in §1b.

---

## 6. Note on the source material

The report is © ENTSO-E 2025. Extracted **numbers and event times** live in
`docs/scenarios/iberia-2025-04-28.md` with page citations; the PDF and any
rendered figure images stay out of the repo.

---

## 7. Getting past the fidelity boundary: two areas, not two instances

The obvious guess — run two GridSims and let them talk — is wrong twice over,
and the correct answer is much smaller than it sounds.

### 7.1 Why not two coupled instances

1. **It breaks a hard architecture invariant.** One process, no client/server,
   no IPC (`docs/SPEC.md` §3–4, `CLAUDE.md`).
2. **It is physically wrong, not merely inelegant.** The two areas are not two
   systems exchanging messages; they share one algebraic quantity,
   `P_tie = P_max·sin(δ₁ − δ₂)`, which must be evaluated **inside the
   derivative, at every solver stage**. Splitting it across processes forces an
   exchange at some finite interval — a co-simulation with an interface delay.
   Delay inside a feedback loop is artificial phase lag, which is artificial
   damping, and **the damping of that exact loop is the thing under study**. A
   split model can turn an unstable swing into a stable one and give a
   confidently wrong answer. This is the same class of error as the banned
   post-hoc state clamping.
3. **There is nothing to gain.** Two areas is **five states** instead of two.
   It is not a scaling problem; it is a modelling gap.

### 7.2 What to build instead

Rotor **angle** as a state, and a **nonlinear** tie. Per area `i`:

| State | Meaning |
|-------|---------|
| `δᵢ`  | rotor angle (rad) — the new one; this is what the COI model throws away |
| `Δωᵢ` | speed deviation (already have it) |
| `ΔPmᵢ` | governor state (already have it) |

with `dδᵢ/dt = 2π·Δfᵢ` and each area's imbalance carrying `∓(P_tie − P_tie,0)`.

**The sine is the entire mechanism.** A *linear* tie (`P = K·Δδ`) gives
diverging frequencies and the inter-area oscillation, but the angle then grows
without bound and power with it — it **cannot** lose synchronism. Only the sine
produces the real behaviour: transfer peaks at 90°, *falls* while the angle
keeps growing, reverses past 180°, and hits `+P_max` at 270°. That reversal is
the report's ≈5,000 MW export swing. Do not ship the linear version thinking it
is a step on the way.

### 7.3 What the probe establishes — and what it does not

> **SUPERSEDED BY AN IN-REPO RUN (M3 step 6).** Everything in this subsection came
> from a throwaway 90-line probe with a hand-rolled RK4, outside the repo. It has
> been replaced by `scripts/iberia_two_area.jl`, which runs the same case on the
> shipped `SwingEngine` with root-found protection, ships a closed-form reference
> check, and regenerates its whole grid in under a minute. Its assertions live in
> `test/runtests.jl` ("M3 step 6: Iberian two-area case").
>
> **The probe's own provenance warning stands and is the reason this section is
> kept rather than deleted** — it is the record of how a tuned parameter became a
> quoted result, and the milestone that replaced it was chosen for that reason
> (`m3-context.md` D10). Read the four findings below with these corrections:
>
> 1. **The cascade magnitude was wrong, and it is the input everything else moves
>    with.** The probe used 5,750 MW in §7.3's parameter list and 2,773 MW in
>    §7.4's sweep — the same quantity, 1.87× apart. Re-derived from Table 3-1
>    (`docs/scenarios/iberia-2025-04-28.md` §2.1): **5,187 MW over 4.100 s**,
>    being the report's cumulative for Spain at 12:33:20.560 *less* the 563 MW of
>    generation already lost before the cascade began, corroborated by the
>    table's own bottom-up floor of 4,907 MW. 5,750 unreduced double-counts those
>    563 MW; **2,773 reconstructs from nothing in Table 3-1 by any grouping**, and
>    §7.4's ±30 % cells are simply ±30 % of it.
> 2. **(b)'s 4,250 MW boundary does not survive**, and it was never a property of
>    the corridor — it was a property of the 2,773 MW figure. At the derived
>    cascade the in-repo sweep puts it at **≈5,500 MW**, and it lands at ≈3,300 MW
>    when the old figure is fed back in as a labelled cell of the same grid.
> 3. **(b)'s duration insensitivity DOES survive**, against the reasoning that
>    predicted it would not: at the derived magnitude the cascade is still arriving
>    when synchronism is lost (~76 % delivered at the 90° crossing), which says
>    duration ought to matter. Measured, the boundary moves by one or two 100 MW
>    scan steps across a 4× change in ramp duration, against ~2,700 MW across the
>    magnitude axis.
> 4. **(c) is replaced by a mechanism rather than a retraction.** The knife-edge
>    inference was retracted here on the grounds that the slip/no-slip boundary
>    *with* shedding sits inside the plausible band. The in-repo run says something
>    sharper: at the nominal cell the defence plan **cannot** prevent the
>    separation, because its first stage arms at 49.8 Hz and Iberian frequency does
>    not reach 49.8 Hz until *after* the angle has passed 90°. The 90° crossing is
>    identical to the millisecond armed and disarmed, while the frequency nadir
>    moves by nearly 3 Hz. Arresting frequency and holding synchronism are
>    different things, and the ladder can only do the first.
> 5. **(d)'s ceiling turns on a parameter the report does not state.** Its
>    arithmetic — "the swing peak *is* `P_max`, so 5,000 MW requires `P_max` ≈
>    6,000" — assumes Iberia was **exporting** 1,000 MW pre-event. `m3-context.md`
>    D8 says the opposite (−1,000 MW, *importing*), and the report as extracted
>    gives only the **change** (ES–FR active power fell ≈1,500 MW over
>    12:32:00–12:33:00, with the HVDC constant so the whole fall landed on the AC).
>    Read as importing, the swing is `P_max + 1,000`, so 5,000 MW needs `P_max` ≈
>    4,000 MW — **well inside the slipping band**, and both observations are
>    reproducible at once. Read as exporting, the ceiling holds. The in-repo sweep
>    carries the pre-event flow as an axis and asserts both readings, so the
>    honest statement is now *"this conclusion flips on the sign of the pre-event
>    AC tie flow"* rather than *"not both"* — weaker, and better, because it names
>    the single observation that would settle it.
> 6. **(a) is the one finding NOT re-derived in-repo**, and it stays a
>    throwaway-probe result. The bracket closure is a claim about frequency at
>    12:33:00, which needs the run to start at 12:32:00 and apply five discrete
>    injections to one machine; this tier has one scheduled ramp per machine and no
>    step-injection event, so the in-repo run starts at cascade onset with clusters
>    1–3 folded into the initial condition. That start is also a **stated bias**:
>    it begins at exactly 50.000 Hz with zero governor deployment where reality was
>    near 49.94 Hz with ~880 MW already standing, both of which give the model more
>    margin than the real system had — so every boundary above is a *conservative*
>    bound on tie stiffness.


A dependency-free 90-line probe (hand-rolled RK4, five states, scratch code in
`M:/claud_projects/temp/entsoe/two_area_probe.jl` — deliberately **not** in
the repo, so it cannot become a second maintained model) fed with the report's
own event sequence:

| | probe | report |
|---|---|---|
| f at 12:33:00 | 49.943 | 49.94 |
| f at 12:33:17 | 49.828 | ≈49.80 |
| angle past 90° (loss of synchronism) | 12:33:20.54 | 12:33:19.62 |
| out-of-step protection opens the tie | 12:33:21.94 | 12:33:21.54 |
| tie flow, import support then reversal | 1,000 → −3,500 → +3,500 MW | — |
| **export swing vs pre-event** | **2,500 MW** | **≈5,000 MW** |
| after separation | Iberia 48.7 → 46.8 Hz, CE recovers to 49.8 | islanded collapse → blackout 12:33:27 |

Parameters (all `[GUESS]` except Iberian KE): `KE₁ = 119,474 MWs`,
`KE₂ = 800,000 MWs`, `P_tie,0 = 1,000 MW`, `P_max = 3,500 MW`, `D = 1.5`,
`Tg = 8 s`; Iberian loss ramped to the report's 5,750 MW by 12:33:20.560.

**Provenance warning, stated up front.** `P_max` was *not* derived — it was set
to 6,500 MW first, at which value the tie was so stiff it simply supplied the
deficit and never slipped a pole, and then reduced to 3,500 MW. The parameter
that decides whether loss of synchronism happens was adjusted until loss of
synchronism happened. Everything below is the result of sweeping it back out
(`two_area_sweep.jl`, same folder) over `P_max` 2,500–5,000 MW × `KE₂`
600k–1,200k MWs, to separate what survives that sweep from what does not.

**(a) The §1(b) bracket closure is robust — this is the strong claim.**
Frequency at 12:33:00 across the *entire* sweep grid lands in
**49.923 – 49.974 Hz** against the report's 49.94, and varying `P_tie,0` over
500–2,000 MW does not widen that. The COI model gives 49.859. So the worst cell
in the grid is 0.017 Hz off where the single-area model is 0.081 Hz off — a
five-fold improvement that holds everywhere, not at one tuned point. Adding a
second area with a tie fixes the pre-separation window regardless of how the tie
is parameterised, because the mechanism (Continental Europe propping Iberia up)
is what was missing, not a coefficient. **The single quoted 49.943 should be
read as "somewhere in 49.92–49.97", not as three-decimal agreement.**

**(b) That the pole slips at all is `P_max`-dependent, and honestly so.**
90°-crossing time, shedding disabled (report: 12:33:19.62):

| `P_max` (MW) | `KE₂`=600k | 800k | 1000k | 1200k |
|---|---|---|---|---|
| 2,500 | 19.58 | 19.46 | 19.38 | 19.32 |
| 3,000 | 20.12 | 20.01 | 19.94 | 19.90 |
| 3,500 | 20.60 | 20.54 | 20.50 | 20.46 |
| 4,000 | 21.20 | 21.09 | 21.00 | 20.92 |
| 4,250 | 22.29 | 21.52 | 21.37 | 21.28 |
| ≥ 4,500 | never | never | never | never |

So: for any tie weaker than ≈4,250 MW the peninsula loses synchronism, and the
timing degrades *gracefully* from 0.3 s early to 2.7 s late across that whole
band — best near `P_max` ≈ 2,750–3,000, which is also where the report's own
"~3 GW AC corridor" figure sits (§1.2). Above ≈4,500 MW the tie holds and there
is no separation at all. `KE₂` barely matters.

**The 4,250 MW boundary is a property of (tie, cascade) jointly, not of the tie
alone** — the cascade ramp is the direct competitor to tie stiffness in deciding
whether the angle runs away, so it was swept too. Largest `P_max` that still
slips:

| cascade ramp duration | 1,941 MW | 2,357 MW | **2,773 MW (report)** | 3,189 MW | 3,605 MW |
|---|---|---|---|---|---|
| 1.5 s | 3,600 | 4,100 | 4,500 | 4,900 | 5,300 |
| **2.46 s (report)** | 3,500 | 3,900 | **4,300** | 4,600 | 5,000 |
| 3.5 s | 3,500 | 3,900 | 4,300 | 4,700 | 5,100 |
| 5.0 s | 3,400 | 3,800 | 4,200 | 4,600 | 5,000 |

Two readings. The boundary tracks cascade **magnitude** almost one-for-one
(±30 % in MW moves it ±~900 MW), so the 4,250 figure must always be quoted *at
the report's cascade profile* — it is not a standalone property of the corridor.
But it is near-**insensitive to ramp duration** (3,400–3,600 MW across 1.5–5 s):
how fast the deficit arrives barely matters, only how much of it there is. That
second fact is useful, because the report's within-cascade event ordering is
explicitly uncertain (§5) while the cumulative total is comparatively solid.

The defensible statement is therefore: *at the report's cascade profile, a
two-area classical model reproduces the separation, at any tie strength in the
lower two-thirds of the plausible corridor, to within ~1 s* — not *the model
predicted 12:33:20.54*.

**(c) The knife-edge inference does not survive the sweep — retracted.**
Earlier wording claimed that because the probe hangs at −95° when the realised
4,854 MW of pump-storage shedding is included, while reality slipped anyway, the
true late-window deficit must exceed the report's floor figures — offered as
independent confirmation of §1. **It is not independent.** The slip/no-slip
boundary with shedding on sits at `P_max` ≈ 2,500 (at `KE₂`=600k) to ≈3,500 (at
1,200k) — *inside* the plausible band, not outside it. At `P_max` = 2,500 MW the
slip completes with the full shedding present. So "shedding suppresses the slip"
is a statement about the chosen tie stiffness, not about the deficit. The
alternative explanations — `P_max` set slightly high, `KE₂` slightly large, or
the cascade ramp slightly slow — fit equally well. §1's under-modelling finding
stands on its own evidence; it gains nothing from here.

**(d) The ceiling of this tier, stated in advance — the most useful result here.**
The probe's export swing against pre-event flow is 2,500 MW where the report
attributes ≈5,000 MW of the imbalance to the swing. That is not a calibration
shortfall to be closed later: the swing peak *is* `P_max`, so producing 5,000 MW
requires `P_max` ≈ 6,000 MW, which sits far inside the band where the tie never
slips at all. **A constant-voltage two-area reduction can reproduce the
separation, or the swing magnitude, but not both.** The tie strength that lets
the peninsula fall out of step is structurally too weak to carry the observed
surge.

This belongs in the same category as "a linear tie cannot slip a pole" (§7.2):
a boundary you can name *before* building anything, not a defect discovered
afterwards. And it names its own exit criterion — the real surge rode on
collapsing voltages across several corridors (ES–FR AC, ES–PT, ES–MA), so
**matching the swing magnitude is the point at which voltage state stops being
optional.** Whoever builds the M2 engine should treat reproducing the separation
timing as in scope and reproducing the 5,000 MW swing as out of scope, and
should not tune toward the latter.

### 7.4 Design sketch

- **Data model.** `Area` (units, load, D, Tg) and `TieLine` (from, to, `P_max`
  or `X` + terminal voltages, protection settings). `SystemModel` gains a vector
  of each. Build for **N areas** with a sparse incidence structure from the
  start (`SPEC` §6), with two as the first instance.
- **One canonical model preserved.** Today's single-area `SystemModel` becomes a
  **compiled view**: collapse every area into one COI. `FrequencyResponseEngine`
  stays as the *fast surrogate*; the multi-area engine is its *accurate sibling*
  behind the same `SimulationEngine` interface — precisely the fidelity-tier
  arrangement `SPEC` §3.3 was written for, now with a concrete second tier.
- **New events.** `TripLine`. Out-of-step protection as a `ContinuousCallback`
  on `|δᵢ − δⱼ|` crossing 180°/270°, or on apparent impedance entering a relay
  zone — the latter also produces the bucket-B impedance-trajectory figures.
  The probe uses the pure 270° threshold with **no timer**: its 1.4 s gap
  between the 90° crossing and the trip is simply how long the angle takes to
  travel 90°→270°. Don't read that gap as a protection delay to be reproduced.
- **HVDC in constant-power mode** is a fixed injection with **no angle
  dependence**. One extra term, and the model then *demonstrates* rather than
  merely asserts why it gave no frequency support.

### 7.5 Validation targets, in order

1. **Equal-area criterion** — closed-form, textbook; critical clearing time.
   This is the reference check `SPEC` §6 demands of every engine.
2. **Small-signal mode frequency**, closed form:
   `f = (1/2π)·√(2π·f₀·K_s·(1/2KE₁ + 1/2KE₂))`, `K_s = P_max·cos δ₀`.
   Over the §7.3 sweep band this implies **0.29–0.41 Hz** (0.358 Hz at the
   probe's own `P_max` = 3,500 MW); the nonlinear run must ring at whatever the
   closed form says for its own parameters. Note this mode is *not* the report's
   0.21 Hz observation — see §7.6.
3. **The scenario**: time of the 90° crossing and of the out-of-step trip.

**On identifying `P_max` — weaker than it first looks.** In principle
`δ₀ = asin(P_tie,0 / P_max)` and the export-swing peak *is* `P_max`, so the
report's ≈5,000 MW swing would pin it. But §7.3(d) shows that value sits in the
range where the tie never slips, so the two report observations (swing magnitude,
separation occurring) cannot both be honoured by one constant-voltage tie.
Treat `P_max` as **a fitted parameter with a plausible range** (2,500–4,250 MW),
report results as ranges over it, and record which conclusions depend on it —
not as a quantity read off the report.

### 7.6 What this tier still will not do

The classical model holds voltage magnitude constant behind a reactance. So it
gets **angle** instability right and **voltage** instability not at all — the
final phase (12:33:21.5 → 27, voltage collapse to blackout) stays in bucket C.

One trap worth naming: the report's **0.21 Hz East-Centre-West oscillation is a
three-area mode** (Iberia is its western end, but France and the east are the
rest of it). A two-area Iberia/CE reduction will not reproduce it, and nobody
should tune `P_max` trying to hit 0.21 Hz — that would wreck the swing
behaviour, which is the one thing this tier exists to capture. Three areas, if
that mode is ever a target.
