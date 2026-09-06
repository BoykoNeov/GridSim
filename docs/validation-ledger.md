# Validation ledger — every mechanism, and what checks it

The bookkeeping decision D7 (`plans/m4-context.md`) asks for: every mechanism in
the repo carries a label saying **what checks it**. Un-oracled is a legitimate
label. Unmarked is not. This file is that list. It was started ahead of M4 step 4 so the
un-oracled rows would be visible *before* the oracle arrived rather than
discovered by it; step 4 has since added the external section at the bottom.

Labels, in the vocabulary M4 fixed:

- **closed form** — a formula derived independently of the code, asserted with a
  tolerance that the stated near-misses fall outside of.
- **derived** — a number computed from the model's own inputs by arithmetic that
  the test repeats (not a band that happened to pass).
- **cross-fidelity** — two tiers of the same scenario compared, with the exactness
  condition stated and the residual isolated.
- **convergence** — the answer survives the solver tolerance changing (M3's
  standing rule; a number below the solver's tolerance is not a result until it
  moves with it).
- **structural** — asserted as a property of the code (an invariant, a mapping, a
  dependency closure), usually with a mutation that must fail.
- **published** — numbers someone else printed (the ENTSO-E report), with the
  faithful window stated.
- **external** — an independent implementation (PowerDynamics 5.0, in `reference/`; M4 step 4, delivered).
- **un-oracled** — a stated choice nothing measures. Allowed, out loud.

Where a row says "test:", the name is the `@testset` in `test/runtests.jl`.

## Aggregate tier (M1) — `engines/frequency_response.jl`

| Mechanism | Checked by | Label |
|---|---|---|
| Swing equation `2H dΔω/dt = ΔPm − DΔω + ΔP` | Initial RoCoF `f0·ΔP/(2H)` swept over every single-unit trip; settling `Δω = ΔP/(D + 1/R_eq)` swept over every trip | closed form |
| Aggregation `H_sys`, `1/R_eq`, headroom | Hand arithmetic; IBR corner (`H = 0`, `R = ∞`) finite | derived |
| Governor lag `Tg` + headroom saturation **in the derivative** | Ceiling holds and releases unaided; a second trip after saturation does not freeze the integrator; settling is `Tg`-independent so the *gain* is pinned | closed form (gain); **un-oracled (lag shape)** — nothing measures the *shape* of the aggregate response, only where it lands |
| Event boundary (FSAL cache invalidation) | `dt`-refinement test that would be invisible to any read-out assertion | structural |
| Less inertia ⇒ steeper RoCoF, deeper nadir | Inertia-only isolation and fewer-units demonstration | derived |
| 500 ms windowed RoCoF | Definition test, actual-elapsed divisor | derived (definition from report p.116) |
| Cumulative tripped MW | Double-count guard | structural |

## Network tier (M2/M3) — `engines/swing.jl`, `model/network_model.jl`

| Mechanism | Checked by | Label |
|---|---|---|
| Per-unit conversion to system base (`machine_arrays`, `branch_arrays`) | Hand arithmetic, with the wrong conversions asserted *by name* (`Xd′·w`, `R·w`) | derived |
| Coupling `K_ij = E′ᵢE′ⱼ/X_ij` (E′ **at the bus**) | Two-machine inter-machine mode 1.5911 Hz through the real code path (V3), residual identified as damping; three wrong formulas outside tolerance | closed form |
| Branch ↦ edge mapping | Asserted as a permutation against `Graphs.edges` order; V2 provably cannot catch it | structural |
| Flat start | Fixpoint holds for the whole horizon (V1) | structural |
| Line trip equilibrium | Chain of `asin`s on the radial survivor (V6), near-misses outside tolerance | closed form |
| Generator trip: no equilibrium, common-mode drift | Settling rate `ΣPm_online/ΣD_online` (and with droop `…/(Σ1/R + ΣD)` over **survivors**, D11) | closed form |
| Droop as a third state | Governor-free invariance to every governor parameter (V1); droop settling on the running engine (V2); angle differences settle, common mode does not (V3); ceiling hold/release/no stall (V4) | closed form + structural |
| COI compiled view `coi_model` | Exact where the tripped machine has `D = 0` and survivors share `D/H` (V4a, 7e-15 Hz over 60 s); the swing residual isolated at 4.4325 µHz stable across tolerances (V4b); the damping gap dominating on the shipped ring, as a derived number (V4c); and **the aggregate view is blind to a line trip entirely** — it has no branches, so `TripLine` has no `inject!` method on it and the swing tier's 1.0758e-3 Hz ring is measured against a flat 50.0 Hz (M4 step 3, 333× the band, stable to 7 significant figures across reltol 1e-3–1e-9) | cross-fidelity + derived + convergence |
| Aggregate `Tg` in `coi_model` (droop-gain-weighted mean) | Nothing | **un-oracled** (stated in the docstring) |
| No down-regulation floor on `ΔPm` | Nothing | **known limit, stated** — matters on the over-frequency side of a split |
| Angle gauge | Differences asserted, absolutes never; `δ_coi` as the reference | structural |
| Recorder decimation | Retention invariant across capacities; nadir never read from the buffer | structural |
| Event log bounded | Cap test | structural |
| No `n²` structure anywhere the engine owns | V5 tripwire | structural |

## Protection and scenario inputs (M3) — `protection/`, `scenarios/`

| Mechanism | Checked by | Label |
|---|---|---|
| Load-shedding ladder (root-found, latching, downward only) | Both polarities asserted on an underdamped run; a fired stage never re-arms; shed integrated not just recorded (`dt` refinement); binds to *its own* machine's frequency and power (V5) | structural + derived |
| Ladder firing instants on the Iberian case | Report annotations (12:33:17.405 pump-storage stage; the ladder's arithmetic re-derived) | published, inside the faithful window only |
| Out-of-step relay (root-found upcrossing of `\|δ_from − δ_to\|`) | Separation instant is a root not a step (V6); tie power reverses before it fires; islands afterwards; disarmed by any other opening | structural + derived |
| Relay threshold (90°…180°) | Nothing — a **scenario parameter**, swept in M3 step 6 | **un-oracled by design** (D6) |
| Generation ramp | Delivers `rate·duration` path-independently; inert at the fixpoint; a trip takes its ramp with it; ends are corners protection root-finds through | derived + structural |
| Protection identical in both execution modes | Ladder and relay run under `run_realtime!` and `solve!`: same firings, root instants to 1.6e-6 s / better than `dt/100` | convergence (M4 step 1) |

## Execution modes (M4)

| Mechanism | Checked by | Label |
|---|---|---|
| `solve!` vs `run_realtime!` | Agreement inside `3·reltol·excursion` at two tolerances, gap shrinking ≥10× for 1000× tighter; positive control (an event off the real-time grid) and anti-vacuity control (tstops deleted) both executed | convergence |
| Output grid via `add_saveat!`, not the interpolant | Measured: reading `integ(t)` after a callback affect was wrong by 3.4e-2 Hz inside the step a shed ended (D9) | structural (measured) |
| `calck = true` explicitly | Measured to depend on whether a relay was armed | structural (measured) |
| Divergence read (`divergence`, `tolerance_band`, `system_frequency`) | Hand arithmetic; same-series-twice reads 0; the exact pair (V4a's fixture) inside the band at two tolerances; the shipped ring departs after the event and ends at V4c's derived number; the 4.4 µHz physical residual invisible at the default band and located once the band drops beneath it; straight-line resampling measured at **33.7× the band** | derived + cross-fidelity + convergence — executed 2026-09-02, numbers in `plans/m4-tasks.md` §Step 2's measured numbers |
| Cross-run comparison on one grid only | Two grids are refused; no resampling path exists in the code | structural |
| Playback overlay window (`ui/src/playback_window.jl`) | UI suite: the cursor's sample is asserted bitwise (`===`, since nothing is interpolated) against both the read-out's source and the *drawn* line; plotted gap and written summary pinned to one arithmetic; the band asserted equal to `tolerance_band` of the solve's own `reltol`, with no widget that could change it; caption and event labels asserted present in the figure's **layout**, not merely in an observable. Three mutations run against the source (cursor off by one, asymmetry never flagged, caption built into a different figure) — each caught, two by one assertion only | structural (mutation-checked) |
| Two tiers may receive different event lists | Explicit `aggregate_perturbations`, never a `hasmethod` filter (which would reclassify a method missing *by mistake* as a fidelity boundary); a line trip handed to both tiers is a `MethodError`, asserted; the asymmetry is drawn and marked per instant | structural |

## The Iberian case — `scripts/`, `docs/plans/entsoe-iberia-reproduction.md`

| Quantity | Checked by | Label |
|---|---|---|
| Aggregate-tier waypoints 12:32:55 – 12:33:17 | Report table, asserted by **sign** per window (too deep before 12:33:16, too shallow after) | published |
| The 12:33:20 waypoint | Asserted as a **known structural failure** (the model recovers where reality collapsed) | published (boundary stated) |
| Initial RoCoF independence from the 2.21–2.71 s `H` band | Keying `S_base` off `KE` makes it cancel — derived, and asserted | derived |
| Two-area inter-area mode | Closed form through `machine_arrays`/`branch_arrays`, residual tracks swing amplitude | closed form |
| Cascade magnitude 5,187 MW / 4.100 s | Re-derived from Table 3-1 in code (V7a) | derived (published inputs) |
| Separation timing within ~1 s across the lower two-thirds of the tie band | Sweep shape (V7e), not a cell value | published + derived |
| `KE_CE`, `H_CE`, `P_max` corridor, reserves, `D`, `Tg` | Nothing — inputs, labelled `[GUESS]`/`[CHOICE]` in the script | **un-oracled inputs, labelled** |
| The 5,000 MW export swing | **Cannot be reproduced at this tier** (constant voltage) — §7.3 (d) | out of scope, stated; the M5 exit criterion |
| Load inertia inside `H_tot` | Documented conflation, not modelled | **stated choice** |
| Inverter-based resources as `H = 0, R = ∞` units | Aggregates finite | arithmetic only — **no inverter dynamics; un-oracled as behaviour** |

## External oracle (M4 step 4) — `reference/`, PowerDynamics 5.0

The column this file was started for. Where a row says "test:", the name is the
`@testset` in `reference/test/runtests.jl`.

**The header claim, stated before the rows so no row is read as more than it is.**
The case is *compiled* from `NetworkModel` (D5), so both sides read the same
`machine_arrays` / `branch_arrays` / `_coupling`. Everything **downstream** of that
fork is externally checked; everything **upstream** of it is not, and a green suite
here is no evidence at all about the per-unit conversions. That is the price of
refusing to hand-maintain a parallel model, and it is the right price — but it has
to be written where the rows are, or the rows overclaim.

| Mechanism | Checked by | Label |
|---|---|---|
| Coupling `K_ij = E′ᵢE′ⱼ/X_ij` **as used**, and its sign | PowerDynamics reaches the same equilibrium and the same trajectory through complex bus voltages, a `PiLine` admittance and a current balance — a different formulation, not a different arithmetic. Ring + `TripLine(:B3, :B1)`, 10 s: `f_coi` to 6.6e-11 Hz, worst per-machine speed to 1.3e-9 pu, angle differences to 3.3e-8 rad | **external** |
| `find_fixpoint`'s answer | Handed to PowerDynamics as its initial state; every speed holds at zero to 1e-10 over 5 s. Positive control: bumping one initial angle by 0.01 rad makes the same check read *not* flat | **external** |
| Branch ↦ edge mapping | The oracle builds its graph from `ba.src`/`ba.dst` through PowerDynamics' own `compile_line`, an independent path from `Graphs.edges` | **external** (adds to the M2 structural row) |
| Event semantics — `TripLine`, `TripGenerator` | Mapped to `PiLine.active = 0` and to zero mechanical power + every incident line deactivated; agreement inside the band on both. An event with no mapping is **refused**, not dropped | **external** + structural |
| COI read-out weighting, including a machine leaving it | Recomputed on the oracle side from *our* `H` weights; asserted against a control that keeps the pre-trip weights and lands >100 bands away, and against the sample at the event instant still being the pre-event one | **external** + structural |
| The integration itself | 1000× tighter tolerance shrinks the cross gap by >10× — a fixed model disagreement would not move | convergence |
| `X′d`'s **inverse** per-unit weight (`machine_arrays`) | The only conversion the oracle reaches: a wrong weight would leave a `ClassicalMachine` residual that does **not** vanish with loading, and none survives at the 1e-12 floor | **external** (via signature) |
| `H`, `D`, `Pm` conversions to system base | **Nothing here.** The builder hands PowerDynamics the already-converted numbers; invert a weight and both sides integrate `H = 1.6` for `10.0` and agree to 1e-12 | unchanged: **derived** (M2 row) — explicitly *not* external |
| `K` as a **formula** | **Nothing here** — both sides are handed the same `K` | unchanged: **closed form** (M2 row) |
| Model bases (`S_base`, `f0`) reaching the oracle | PowerDynamics reads them from process-global state at construction. Tested on a 250 MVA / 60 Hz fixture with the global deliberately poisoned to 50 Hz first, plus an anti-vacuity half that reproduces the stale-base error on our side and lands >100 bands out | structural (mutation-checked) |
| Governor state `ΔPm` | **No PowerDynamics counterpart** at either tier — so `build_oracle` **throws** on a governed model rather than silently comparing against an ungoverned one | **un-oracled, and refused rather than faked** |
| `ClassicalMachine`'s torque form (D14) | Its mechanical input is `τ_m/ω` where ours is `Pm`. Isolated by a closed form (the survivor of a trip settles at `τ/D` for us, at the root of `D·ω·(ω−1) = τ` for it: −0.075000 vs −0.081670, each side landing on its own) and by the residual being **linear in loading** over two decades while the `Swing` residual does not move | closed form + **external** |
| The `E′`-behind-`X′d` radial reduction `X − X′d,ᵢ − X′d,ⱼ` | Exact — proven by the *absence* of any loading-independent residual once the torque term is accounted for. Enforced structurally: branch degree ≠ 1 and a non-positive reduced reactance are both thrown | **external** + structural |
| The oracle's own accuracy | Its self-convergence error is 3.5× ours at reltol 1e-3 and 18× at 1e-7 — **the floor is below us**, which is what D7 means by "not a ceiling" | convergence (measured) |

## Detailed (DAE) tier — M5 step 1, `src/engines/detailed.jl`

The tier's first rows. Nothing external yet: PowerDynamics' `SauerPaiMachine`
arrives at plan step 3, and the flux equations it would oracle do not exist until
step 2.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| The whole initialisation path — power flow, back-substitution, network assembly | **The flat run**: no disturbance, 10 s, every channel constant, asserted PER CHANNEL at two tolerances (`1e-3/1e-6` and `1e-8/1e-11`) on three fixtures. Worst drift measured 1.6e-14 against a 1e-10 gate | **self-consistency, per state** |
| The back-substituted state is a fixpoint of the network actually integrated | Asserted at BUILD time against the dynamic RHS, separately from the power-flow residual — they are residuals of different equation sets | derived (structural) |
| `Pm` from the power flow rather than from `Machine.P0` | Positive control is **the real bug**: substituting the schedule makes the run diverge 6.6 rad with `f_coi` moving 0.157 Hz. Has content only on `load_bus_system` — on every pre-M5 fixture the two are equal to the bit, and that vacuity is asserted too | **positive control (the real bug)** |
| The power flow's answer is the true one and not the collapsed one | The `\|V\| ∈ [0.9, 1.1]` band, and **not** the residual: the spurious solution converges 400× tighter (5.0e-16 against 1.8e-13). Unit-tested against a fabricated collapsed solution with a perfect residual | **discriminator (measured), not a comfort check** |
| The slack's effect | Invariance to machine precision (2.2e-16) where no load depends on voltage; a **measured, asserted difference** (ΔPm 4.6e-2) where one does, with each answer checked self-consistent against what the load actually draws | derived + **bounded discrepancy, sign and size** |
| A state written into the integrator survives | Measured both ways: bare write discarded (3.9e-15), `u_modified!` + `auto_dt_reset!` takes (5.06e-2). `_reinitialise_algebraic!` depends on this | structural (mutation-checked) |
| Consistent re-initialisation after a line trip | The algebraic rows of the dynamic residual hold below 1e-9 at the post-event point, and the run continues. **NOT the D8 check** — the flat run *across* an event is owed by the step that arms protection here | **partial; the real check is owed** |
| No admittance matrix (SPEC §6) | Structural, as M2's: the coupling is assembled edge by edge inside NetworkDynamics, and the state dimension is `2·n_bus + 3·n_machine` | structural |
| Cost against the classical tier (S3) | 41/45 accepted steps on the two-area case, 228/126 on the ring; 3,000–11,000× faster than real time. Two sizes only — not an extrapolation | **measurement (2 points), stated as such** |
| The two-axis machine, flux, the regulator, ZIP `a_i`/`a_p`, `inject!(::TripGenerator)`, two machines on a bus | **Nothing — not built.** Each refused by name at build time with the step that owns it, rather than approximated | **un-built, and refused rather than faked** |

## Owed rows

Rows M5 will need before it ships:

- The M5 rows: flux equations (two limits + small-signal `K`-constants), exciter,
  power-flow initialisation (flat run), algebraic network (Kirchhoff residual),
  voltage-dependent load. See `plans/m5-prestudy.md` §3–§5 for the oracle each
  one gets.
- M5 also inherited one **choice** from step 4: the detailed tier's external check
  wants `SauerPaiMachine`, which is above `ClassicalMachine`, so the torque
  convention (D14) had to be re-read from *that* component's source rather than
  assumed to carry over. **Read, 2026-09-06 — `plans/m5-prestudy.md` §2a.** It does
  not carry: their swing equation is ours term for term and D14's asymmetry is
  absent, but the convention question relocates into the stator, where their `ω`
  multiplies the flux terms and ours does not — the same order, and the same
  invisibility to every steady-state check. The second half of this row is now
  **wrong** and is replaced: running the bracket at low loading does *not*
  discriminate a torque-form term from a flux one, because flux decay scales with
  loading too. The separator is fidelity — flux off on both sides first, then on.

**Closed by M4 step 4**, recorded so the change of plan is visible rather than
silently dropped: the previous owed row asked for an external column via
`ClassicalMachine` "matched `E′`-behind-`X′d` configuration, `m5-prestudy.md` §7".
That is not how it was delivered. `Library.Swing` turned out to be our model
equation for equation and needs no reduction at all, so it carries the external
column on **any** topology — including the meshed ring the pre-study had ruled
out — and `ClassicalMachine` became a second, different check instead. See
`plans/m4-context.md` D13.
