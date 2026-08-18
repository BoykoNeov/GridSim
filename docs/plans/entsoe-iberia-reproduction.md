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
| 12:33:17+   |      49.80 |  49.669 | −0.131 |
| 12:33:20    |      48.50 |  48.732 | **+0.232** |

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

Two further observations are worth more than any of the agreement:

**(a) Inverter-based generation needs no new data model.** A PV/wind block is
already expressible as `GeneratingUnit(:PV, S, 0.0, P0, Inf, P0)` — zero inertia
contribution, `1/R = 1/Inf = 0` droop gain, zero headroom, and tripping it dumps
`P0` straight into `ΔP_dist`. Verified: aggregates stay finite, no `NaN`.
So the "renewables have no inertia" lesson is already representable.

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

Figures 1-3, 3-7 and 3-9 all plot **cumulative tripped generation** on a second
axis against voltage or frequency. The information is entirely in the event log;
the engine simply does not accumulate it. Small addition to the recorded
trajectory alongside `ts/fs/rocofs/pms`.

### 3.3 500 ms windowed RoCoF

**Every RoCoF number in the report is a 500 ms sliding window** (ENTSO-E best
practice, stated on p.116). `current_state` returns the instantaneous
`f0·dΔω/dt`. During the fast transient these differ substantially, so comparing
the instantaneous value against "−1 Hz/s at 12:33:20.560" would be comparing two
different quantities.

Add windowed RoCoF as an **additional post-processing read** over the recorded
trajectory — not as a replacement for the instantaneous value, which stays the
live readout and the closed-form validation target (`docs/SPEC.md` §7.6).

### 3.4 Two open questions to decide consciously, not by default

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
| Frequency with **horizontal threshold lines** and shed annotations | **3-67** | The single highest-value target; needs §3.1 |
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
  Makie-free script printing the waypoint comparison. Ticks §7.8's first
  criterion with real content. Still to add: the waypoint comparisons as *test
  assertions* (with tolerances that encode §1's two-window caveat, not a single
  band).
- **Batch after.** §3.1 LFDD callback + §3.2 cumulative bookkeeping + §3.3
  windowed RoCoF. Unlocks Figure 3-67, the most valuable single chart.
- **Then.** GLMakie UI, with the ENTSO-E chart archetypes in bucket A as the
  layout targets rather than an ad-hoc plot.
- **M2 candidate.** Two-area + tie-line, motivated by the bracket in §1b.

---

## 6. Note on the source material

The report is © ENTSO-E 2025. Extracted **numbers and event times** live in
`docs/scenarios/iberia-2025-04-28.md` with page citations; the PDF and any
rendered figure images stay out of the repo.
