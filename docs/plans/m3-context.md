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

## Open questions to resolve during M3

- **What does `coi_model` compile now?** It deliberately produced a governor-free
  `SystemModel` so the cross-fidelity comparison differed by inter-machine
  dynamics *alone*. With real droop on the network model, either it compiles the
  real aggregate droop (and the comparison changes meaning) or it keeps producing
  a governor-free view (and the comparison is no longer like-for-like). Decide in
  step 1 or 2, write it in the code, and record the choice here.
- **Does the `isoutofdomain` predicate cost measurable time** in the hot loop when
  it can never fire (governor-free networks)? M1 pays it on two states; M3 would
  pay it on `3N`. Measure before assuming either way.
- **Does the out-of-step threshold belong to the branch or to the protection
  object?** `Branch` already carries a `rating` it does not use. Resist the pull to
  put protection settings on the topology type — the ladder is a separate object
  for good reasons and this probably should be too.

## Reference

- `docs/plans/entsoe-iberia-reproduction.md` — §2 the fidelity boundary, §3 the
  three mechanisms, §7 the two-area model and the probe's provenance warning.
- `docs/scenarios/iberia-2025-04-28.md` — the report's own figures and citations.
- `src/engines/frequency_response.jl` — M1's governor, headroom saturation, and
  the `isoutofdomain` discipline being generalised here.
- `src/protection/load_shedding.jl` — the callback pattern step 3 rebinds.
- `src/engines/swing.jl` — the tier, the sign convention, the edge-ordering hazard,
  and the "no guard here" header note step 1 must amend.
