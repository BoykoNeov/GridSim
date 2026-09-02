# Validation ledger — every mechanism, and what checks it

The bookkeeping decision D7 (`plans/m4-context.md`) asks for: every mechanism in
the repo carries a label saying **what checks it**. Un-oracled is a legitimate
label. Unmarked is not. This file is that list, started ahead of M4 step 4 (which
adds the PowerDynamics column) so the un-oracled rows are visible *now* rather
than discovered when the oracle arrives.

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
- **external** — an independent implementation (PowerDynamics; M4 step 4, none yet).
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
| COI compiled view `coi_model` | Exact where the tripped machine has `D = 0` and survivors share `D/H` (V4a, 7e-15 Hz over 60 s); the swing residual isolated at 4.4325 µHz stable across tolerances (V4b); the damping gap dominating on the shipped ring, as a derived number (V4c) | cross-fidelity + derived + convergence |
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

## Owed rows

Rows M4 step 4 must add, and rows M5 will need before it ships:

- **external** column for: swing equation + coupling on a radial pair (matched
  `E′`-behind-`X′d` configuration, `plans/m5-prestudy.md` §7); droop settling;
  line-trip equilibrium. Anything PowerDynamics has no component for stays in the
  column it is in, and says so.
- The M5 rows: flux equations (two limits + small-signal `K`-constants), exciter,
  power-flow initialisation (flat run), algebraic network (Kirchhoff residual),
  voltage-dependent load. See `plans/m5-prestudy.md` §3–§5 for the oracle each
  one gets.
