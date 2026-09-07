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

## Detailed (DAE) tier — M5 steps 1-6, `src/engines/detailed.jl`

External as of step 3: PowerDynamics' `SauerPaiMachine` at its `X″ = X′`
degeneration, with the flux frozen on **both** sides. The rows below that say
"un-oracled" for the flux equations still say it — freezing the flux is precisely
what makes this comparison clean, and step 4 is what switches it on.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| The whole initialisation path — power flow, back-substitution, network assembly | **The flat run**: no disturbance, 10 s, every channel constant, asserted PER CHANNEL at two tolerances (`1e-3/1e-6` and `1e-8/1e-11`) on three fixtures. Worst drift 1.6e-14 against a 1e-10 gate. **Plus a third pass at `dtmax = 0.05`**, because unforced the solver crosses the horizon in FOUR steps and the check would otherwise only be establishing that an implicit method parks on an equilibrium — forced to 201 steps the worst drift is 4.4e-14, the same order. Both step counts are themselves asserted | **self-consistency, per state (forced and unforced)** |
| The back-substituted state is a fixpoint of the network actually integrated | Asserted at BUILD time against the dynamic RHS, separately from the power-flow residual — they are residuals of different equation sets | derived (structural) |
| `Pm` from the power flow rather than from `Machine.P0` | Positive control is **the real bug**: substituting the schedule makes the run diverge 6.6 rad with `f_coi` moving 0.157 Hz. Has content only on `load_bus_system` — on every pre-M5 fixture the two are equal to the bit, and that vacuity is asserted too | **positive control (the real bug)** |
| The power flow's answer is the true one and not the collapsed one | The `\|V\| ∈ [0.9, 1.1]` band, and **not** the residual: the spurious solution converges 400× tighter (5.0e-16 against 1.8e-13). Unit-tested against a fabricated collapsed solution with a perfect residual | **discriminator (measured), not a comfort check** |
| The slack's effect | Invariance to machine precision (2.2e-16) where no load depends on voltage; a **measured, asserted difference** (ΔPm 4.6e-2) where one does, with each answer checked self-consistent against what the load actually draws | derived + **bounded discrepancy, sign and size** |
| A state written into the integrator survives | Measured both ways: bare write discarded (3.9e-15), `u_modified!` + `auto_dt_reset!` takes (5.06e-2). `_reinitialise_algebraic!` depends on this | structural (mutation-checked) |
| Consistent re-initialisation after a line trip | The algebraic rows of the dynamic residual hold below 1e-9 at the post-event point, and the run continues. Anti-vacuity: the DIFFERENTIAL rows are asserted **non-zero**, so a re-initialisation that quietly zeroed the state vector cannot pass, and the re-solved voltages are checked not to be a collapsed solution. **Still NOT the D8 check** — the flat run *across* an event is owed by the step that arms protection here | **partial (anti-vacuity closed); the real check is owed** |
| `_PF_HOLD` — the third static mode step 2 added (D16) | **Only where it is provably identical to `_PF_PIN`.** It exists because the steady-state source (`\|Ẽ\|` fixed) is false mid-transient once the flux moves; at the frozen-flux degeneration the flux does not move, so every run that exercises it is a run in which the mode it replaced would have given the same answer. What IS checked: the flux states survive the discontinuity untouched (1e-14), the post-event point satisfies the algebraic rows, and the mode really is switched. The mode's **distinguishing** behaviour has no oracle until plan step 4 gives the flux something to do | **un-oracled (the distinguishing case); the identical case is checked** |
| No admittance matrix (SPEC §6) | Structural, as M2's: the coupling is assembled edge by edge inside NetworkDynamics, and the state dimension is `2·n_bus + 5·n_machine`. **The `< n_bus² + 2·n_bus` form of this row failed in step 2 and deserved to** (`16 < 15` on the 3-bus fixture): a linear count bounded by a quadratic one says nothing small and passes against a dense engine large. Replaced by a GROWTH assertion — one extra machine-free bus costs exactly two more states, where an admittance formulation would cost `O(n_bus)` | structural (growth, not a quadratic bound) |
| Cost against the classical tier (S3) | 41/45 accepted steps on the two-area case, 228/126 on the ring; 3,000–11,000× faster than real time. Two sizes only — not an extrapolation | **measurement (2 points), stated as such** |
| The two-axis machine's swing equation, stator algebra, rotor-frame rotation, network and initialisation | **The internal degeneration oracle**: at `X′d = X′q`, `T′do = T′qo = Inf`, `Ra = 0` the tier reproduces `SwingEngine` on `two_machine_system()` at two tolerances (`1e-4/1e-7` and `1e-7/1e-10`). Gap / band = **0.31-0.33** on all four channels at both, where the band is `convergence_band` — each side's error estimated by its OWN coarse/fine pair, so it never looks at the gap it judges. Anti-vacuity: `X′q` perturbed 1 % goes red by 64-173x | **internal cross-fidelity, exact-by-construction limit** |
| **What that oracle cannot see, measured rather than assumed** | Thawing `T′do`/`T′qo` from `Inf` to 5.0 / 0.5 s moves the trajectory by **2.3e-14** — four orders below the loosest band in the file. At the degeneration `Xd − X′d`, `Xq − X′q`, `X′q − X′d` and `Ra` are all exactly zero, so no mutation of the flux equations, the saliency term or the stator resistance can move a number here | **un-oracled (flux, saliency, `Ra`) — and the blindness is a measurement, not a caveat** |
| The flux half of the fixpoint, `E′d = (Xq − X′q)·Iq` (M5 step 4) | The flat run on `detailed_pair()` — the first fixture in the repo where that condition is not `0 = 0`, since every frozen-flux machine has `Xq − X′q = 0` and the initialisation could write anything into `E′d`. Worst drift 1.4e-13 at two tolerances plus a 201-step forced pass, per state. **A different vacuity from step 1's** (`Pm := Pe` vs `P0`) and the two are not merged | self-consistency, per state |
| The d-axis flux coefficients `(Xd − X′d)` and `T′do` (M5 step 4) | **A CLOSED FORM**: machine on an infinite bus, regulator off, field-voltage step — `T′d = T′do·(X′d + Xe)/(Xd + Xe)`, fitted against predicted to **3e-9** at `reltol` 1e-9 and 3e-6 at 1e-6, with the asymptote `K₃·ΔEfd` read independently off the endpoint (a constant fitted from the shape and a gain read from the endpoint are different functions of the same two reactances). Anti-vacuity is a PREDICTED move: `Xd` 1.8 → 1.0 pu moves the predicted constant by 1.4923× and the measured ratio lands on it to 1e-3 | **closed form, 1e-4** |
| Why that closed form is exact (D18) | **The fixture's rotor is immobile, not merely heavy.** At zero loading the solution sits on the real axis, so `Iq ≡ 0`, `E′d ≡ 0`, `Pe ≡ 0` and the swing equation has nothing to integrate. Large `H` does NOT substitute: the rotor's post-step equilibrium angle is `ΔP/K_syn`, which contains no `H`, and 64× the inertia at 40 MW still leaves a 21-26 % error. Both halves are tests — the exact one and the boundary | derived + **bounded discrepancy (measured across 64× in `H`)** |
| The flux equations from the OTHER side (M5 step 4) | **The `T′ → 0` limit**, with step 2's frozen limit bracketing them. `flux_limit_model` (`X′ := X`, `T′ := Inf`) is the quasi-steady machine written as a MODEL, sharing the fast machine's power flow to the bit. The gap falls **linearly in `T′`** (1.35e-4 / 4.15e-5 / 1.39e-5 at `λ` = 1e-3 / 3e-4 / 1e-4) and the smallest is still 70× the reference side's own convergence spread. Anti-vacuity: `Xd` 1 % wrong on the fast side only — an error the `T′ = Inf` reference is structurally immune to — makes the ladder **plateau** (0.84 per rung against 0.34) at 5.7× the true gap | **internal limit, ~1 % on `Xd`** |
| What that limit cannot see | `X′d` cancels out of the limit entirely and only sets the RATE of approach: a **10 %** `X′d` error moves the comparison by 1.4 % where a **1 %** `Xd` error moves it by a third. Asserted with those numbers rather than caveated. `X′d` is pinned by step 2's frozen limit and by the flat run | **un-oracled here, bounded by assertion** |
| The q axis inside the closed form | **Nothing, and asserted**: at `δ ≡ 0` the q axis carries no current, so ten times `T′qo` moves the run by < 1e-12 — the same shape of blindness step 2 had for the d axis. Covered by the `T′ → 0` limit and by PowerDynamics, and by nothing in the closed form | **un-oracled there, named** |
| The rotor-frame convention (`Vd + jVq = V·e^{−j(δ−π/2)}`) | **One check, and the two that look like they cover it provably do not.** Both mutations run: a *reflected* frame is caught at build time by the fixpoint residual (5.03 against a 1e-10 gate); a *consistently turned* frame (δ → δ + π/2 at both sites) passes the residual, the air-gap-power identity and the flat run, and is caught only by asserting `E′d = 0` and `E′q = Machine.E′` at the degeneration — a turned frame lands `E′d = [1.05, 1.02]`, `E′q ≈ 0` | **structural (mutation-checked, both branches run)** |
| The air-gap power's two expressions agree | Build-time: the two-axis bracket `E′d·Id + E′q·Iq + (X′q−X′d)·Id·Iq` against the phasor `Re(Ẽ·conj(I))`. Provably one quantity (both reduce to `Vd·Id + Vq·Iq + Ra·\|I\|²`), so a gap is the rotation disagreeing with the stator inversion. **Its reach is stated in the code**: it cannot see a globally consistent frame turn | derived (structural), **reach named** |
| Detailed data handed to the classical tier | `_assert_frozen_flux` refuses `SwingEngine`, `coi_model` **and** `build_oracle(:swing)`/`(:classical)` by name (M5 steps 2-3, D17). `Ra` is in the list because it changes the *initialisation* even where it changes no dynamics. The third consumer calls core's own guard rather than a copy, so the three cannot drift | structural (guard); **all three entry points closed** |
| `inject!(::TripGenerator)`, two machines on a bus | **Nothing — not built**, and each is refused by name at build time with the step that owns it. (The flux equations left this row in M5 step 4, the regulator in step 5, and **the ZIP shares in step 6** — see the block below.) | **un-built, and refused rather than faked** |

### The voltage regulator (M5 step 5)

The exciter is `T_E·dEfd/dt = −Efd + K_A(Vref − \|V\|)` with hard limits saturating in
the DERIVATIVE. `Efd` is a state unconditionally, and the defaults (`K_A = 0`,
`T_E = Inf`) are the regulator OFF — which is what every step-1-to-4 row above still
runs on, so none of them moved.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| `Vref` is derived from the solved equilibrium, not supplied | The flat run on `regulator_bus_system()`, per state at two tolerances — a regulated machine starts at rest exactly as an unregulated one does. **Positive control is the real bug and it corrected the prediction**: `Vref` off by 0.01 pu does NOT move the field voltage by the open-loop `K_A·ΔVref = 2.0 pu`, it moves it by `K_A·ΔVref/(1 + G) = 0.180 pu` with `G = K_A·Xe/(Xe + Xd) = 10.11` the DC loop gain — 11× smaller, because the extra field raises the terminal voltage and cancels most of the error that produced it. Predicted 0.9660369472, measured 0.9660369472 | **closed form (closed-loop DC gain), 1e-8** |
| `K_A`, `T_E`, `Efd_min`, `Efd_max` do not convert with the machine base | `Efd` is a voltage, built as `E′q + (Xd − X′d)·Id`, and a reactance times a current is invariant under a change of power base. Control: the same PHYSICAL machine at **twice the rating** (`S_rated`, every machine-base reactance and the inverse of every machine-base power moved together) reproduces the ceiling run to < 1e-9 on `Efd`, `E′q` and `V`. Run through the SATURATED case, because a flat run agrees whether or not the gain converts | **positive control (rating-invariance)** |
| The ceiling HOLDS under sustained demand, and what the flux does under it | **Step 4's closed form with one constant changed**: while saturated `Efd ≡ Efd_max` is a constant, so the machine is the constant-field machine already validated to 3e-9. Same `T′d = T′do·(X′d + Xe)/(Xd + Xe)` (2.8453 s, fitted to 2e-3), new asymptote `E′q(∞) = [(Xd − X′d)·E_inf + Efd_max·(Xe + X′d)]/(Xe + Xd)` (endpoint to 1e-6 with the finite horizon in the prediction). Anti-vacuity is a PREDICTED move: `Xd` 1.8 → 1.0 shifts τ by 1.5× and the fit lands on the new value | **closed form, 1e-6** |
| It comes off the ceiling UNAIDED, and when | No event and no state surgery: the terminal voltage recovers under the ceiling field until `K_A(Vref − \|V\|)` falls back through `Efd_max`. The release interval is the same first-order law, `t = −T′d·ln((V_rel − V∞)/(V_sat − V∞))`, and it is checked as a FUNCTION of the ceiling rather than at one point — predicted 7.0106 / 3.8056 / 2.3982 s at `Efd_max` = 1.00 / 1.02 / 1.05, measured 7.010 / 3.805 / 2.398 to the 1 ms sampling grid. All three then settle at the same unlimited equilibrium (0.9928754), which is what "the limit left no trace" means | **closed form, 2 ms (the sample grid)** |
| A second disturbance while saturated | The run advances to 40 s with a successful retcode across a second line trip — and the claim is checked with a PREDICTION rather than only a retcode, because "still running" is compatible with running wrong: the new reactance changes `T′d` from 2.8453 s to exactly 4.0 s and REVERSES the flux's target (climbing to 1.01443, then falling to 1.00000, both exact). Fitted to 3e-3 | **closed form (post-event), 3e-3** |
| The state stays inside its limit | **Not by a guard — by the saturation, and the excursion is a measured number.** Above the ceiling the derivative is zero, so the only excursion is the overshoot of the single step that crosses: **5.0e-8 pu**, at two tolerances, not growing over 24 s of sitting there | **measurement (bounded overshoot)** |
| Clamping the state instead of saturating the derivative (**anti-vacuity**) | **RUN, and it reversed the prediction.** The clamp is applied from the test every `h` seconds to an engine with no limits — M1's bug, faithfully. The headline claim — "the field voltage never goes above its limit" — reads **red or green depending on where it looks**: 0.0 excess sampled at the clamp instants, **0.378 pu** of excess sampled anywhere else (`h` = 0.005), against the correct engine's 5e-8. Two of the remaining claims stay green regardless; the closed form goes red at >100× the honest error. The step-size signature is read on the **excess field**, which is linear in `h` over a 40× range — not on the endpoint flux, which by 24 s has settled into the clamped run's own equilibrium and only decays 0.78 per halving | **positive control (the M1 bug); the mutation makes the answer a property of the recorder** |
| The `isoutofdomain` guard the plan asked for | **Written, measured to make the ceiling UNREACHABLE, and removed.** The guard accepts a step only if it lands at or below `limit + 1e-10`; a state approaching from below with a finite derivative needs an ever-smaller step to land inside that window, so `dt` collapses geometrically. Measured: MaxIters at `dt` = 9.1e-11 / 1.7e-9 / 1.5e-8 across three exciter settings, and 199,944 accepted steps on a raw solve without reaching the limit. **`swing.jl`'s prose said this could not happen** | **measurement (falsifies a documented claim)** |
| …and whether the engines that still carry that guard are stalling | **They are not, and the reason is one number nobody chose.** A `SwingEngine` governor driven onto its headroom for 20,000 s LANDS — `ΔPm` settles **3.1e-11 pu above** its ceiling, inside the guard's absolute 1e-10 window with 3× to spare, `dt` around 0.09 s. The required window scales with the state's speed: a 1 s governor lag needs 3e-11, a 0.05 s exciter lag needs 5e-8 (500× the window). Left alone deliberately — changing the constant would move M2, M3 and M4 numbers | **measurement (margin quantified, not a fix)** |
| A hard saturation is a discontinuous RHS | Swept over eight ceilings (1.05 … 3.0) at reltol 1e-9: seven complete, and `Efd_max = 1.2` does not — and it is isolated in the TOLERANCE too, completing at 1e-6 (overshoot 8.3e-6) and 1e-11 (6.1e-10) and failing only at the 1e-9 between them. Non-monotone in two parameters is conditioning at the kink, not a boundary. `FBDF` completes it (1.7e-9) and is asserted; which Rodas5P version fails where is not something a test should pin | **measurement (isolated failure, workaround asserted)** |
| The exciter's steady-state gain, its lag, and the limits, against an outside implementation | See the `:sauer_pai_avr` block below — **the UNLIMITED loop only.** The limited exciter has no counterpart in `AVRTypeI` (their limits sit on the regulator output `vr`, one block upstream of the field voltage), and `build_oracle` refuses it by name rather than comparing two different models | **external (unlimited) / refused (limited)** |

### Voltage-dependent load (M5 step 6)

The ZIP load `P = P₀(a_z|V|² + a_i|V| + a_p)`, `Q` likewise. `Load` validated the
three shares from step 1 and the engine refused the two it did not solve; step 6
solves them, on the dynamic path and the power-flow path both. The default is
`a_z = 1`, which is the constant-impedance load every pre-step-6 row above runs on,
and it is **bitwise** what it was — so no earlier number moved.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| The ZIP current itself | Unit-tested with `===`, not `≈`, because both claims in its docstring are exact or nothing: the constant-impedance path is **bitwise** `I = (G + jB)·V`, and `k = 1` at `\|V\| = 1` for every share split (which is what makes `P₀` mean "drawn at nominal voltage"). Anti-vacuity in the same testset: away from `\|V\| = 1` the currents must differ, or a `k` hard-wired to one would pass both | **exact (`===`), with its own anti-vacuity** |
| The two new shares are actually solved | **The three-way ORDERING of drawn power, which needs no tolerance.** The network is lossless, so `Σ Pm` at the solved point IS the draw, read off the engine's parameters rather than recomputed: `1.054270 < 1.074905 < 1.100000` pu at `\|V\| ≈ 0.977`, strictly ordered by algebra, with the bus voltage falling the other way. A build that ignored `a_i`/`a_p` makes all three identical — and `load_bus_system` solves below 1.0 pu precisely so they cannot coincide | **derived ordering (no tolerance chosen)** |
| Each ZIP term's closed form | Three, one per term: `P₀\|V\|²` (step 1's), `P₀\|V\|`, and `P₀` **exactly** — the constant-power draw has no voltage in it at all, and matches the schedule to 8.9e-16 rather than to a power-flow tolerance | **closed form, 1e-14 (constant power)** |
| The dynamic RHS and the power-flow RHS agree about the load | **The flat run**, which is the only check that can see them disagree: they are different vertex models calling the same function, and if one lacked the shares the fixpoint would not be an equilibrium of the equations integrated. Four splits × two tolerances, per channel, worst 1.2e-13 against a 1e-10 gate | self-consistency, per state |
| …and the mutations that prove that flat run is not vacuous | **Both run, and one of them was found to be a DUPLICATE.** "Dynamic path drops the shares" gives +0.157 Hz — numerically the same run as step 1's `Pm`-from-schedule control, because both are the same 0.046 pu imbalance seen from opposite sides. The discriminating mutation is the mirror one (power flow constant-impedance, dynamics constant-power): **−0.15616 Hz**, and the SIGN is what is asserted | **positive control (sign); the duplicate is recorded, not hidden** |
| The solve landed on the right branch of a two-valued problem | **The P-V nose, in closed form.** One machine feeding a machine-free load bus through `X`: `u² + u(2QX − E²) + (PX)² + (QX)² = 0` with `u = \|V\|²`, so a constant-power load is served at **two** voltages (0.971792 and 0.195244 pu), both honest roots of the same residual. The fixpoint matches the high root to 1e-9 | **closed form (exact), branch identified** |
| How much a constant-power load can be served at all | **A DERIVED limit, not a chosen one**: `P_max = E√(E² − 4QX)/(2X)` = 1.62524 pu. At 1.62 pu the roots are still distinct and the solve returns an answer; at 1.63 pu the discriminant is negative and the fixpoint solver reports MaxIters. A limit derived on paper predicts to better than half a percent where somebody else's Newton stops converging. **And it is distinguished from the OTHER refusal**: at 1.30 pu the high root exists (0.885364, matched to six digits) and it is the `\|V\| ∈ [0.9, 1.1]` band that rejects the case, not the nose | **closed form (derived limit), 0.3 %** |
| `\|V\| → 0` with a constant-power share | **Nothing, and deliberately — see `m5-context.md` D23.** The current diverges, because a load drawing constant power from a dead bus is a model with no solution. No low-voltage cut-over is added: its threshold is a parameter nobody has chosen, and step 7's collapse runs are the ones it would corrupt. PowerDynamics' own `ZIPLoad` carries no regularisation either (their `ConstantCurrentLoad` does) | **un-guarded BY DECISION, stated** |
| Frequency-dependent load | **Nothing — it stays on the machine's `D`** until something measures the difference. Recorded in `Load`'s docstring and `m5-prestudy.md` §6 rather than silently omitted | **un-built, named** |
| `P` and `Q` sharing one ZIP split | **A restriction on OUR side, found by reading their source.** `ZIPLoad` carries separate triples for `P` and `Q`; `Load` carries one and applies it to both, so a load whose two splits differ is not expressible here. Asserted in the oracle suite (both of their triples receive ours) rather than left in prose | **restriction, asserted** |

## External oracle for the detailed tier (M5 steps 3-4) — `SauerPaiMachine` at `X″ = X′`

**The header claim, before the rows.** The case is compiled from `NetworkModel`
exactly as the M4 tiers are, so the same fork applies: everything downstream of the
per-unit conversion is externally checked and nothing upstream is. Two things are
specific to this tier. First, **both sides put the machine behind its reactance on
an algebraic terminal bus**, so no line reduction is needed and the meshed ring —
invalid for `:classical` — is a valid case here. Second, **the flux is frozen on
both sides**, which is what leaves exactly one predicted residual to identify.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| The whole detailed initialisation — power flow, back-substitution, algebraic network, KCL signs, rotor frame | **The flat run on the meshed ring**, per state at two tolerances: every channel constant and equal across the two implementations below 1e-8, including the bus voltages, which are STATES on their side too (`busbar₊u_r`/`u_i`) and not reconstructed observables. Positive control: their seeded `E′_q` bumped 1 % reads 6.9e-3 | **external, per state** |
| The stator-`ω` convention difference (`m5-prestudy.md` §2a) | **Identified by its coefficient, not bounded by a tolerance.** Predicted `(ω − 1)·V`; measured `gap(V) / (peak slip × \|V\|)` = 0.996, 0.996, 0.995 across a factor of four in disturbance size, with the gap doubling as the disturbance doubles to 0.1 %. Sharper than D14, which could only assert proportionality | **external, signature (coefficient)** |
| `T′ = Inf` on their MULTIPLIED form | Spike S1: `mtkcompile` accepts `Inf·ẋ ~ rhs`, derivative exactly zero. Positive control is the `1/T′` ladder (3.547e-9 / 3.547e-7 / 3.548e-5 at `T′` = 1e8 / 1e6 / 1e4) on a *live* flux equation — the first form of the spike ran at the degeneration, where the RHS is identically zero and any `T′` would have passed | measurement (with its own anti-vacuity) |
| Their `bounds = (0, Inf)` on `vf`, `τ_m`, `τ_e` | Spike S2: metadata, not enforced — `τ_m_set = −0.5` builds, solves, `τ_e = −0.316`. No precondition needed. It mattered because **every** fixture here balances with a negative-`P0` machine | measurement |
| The degeneration actually took | `X_ls` — a parameter of THEIR component that survives nowhere in the reduction — varied across a run moves every channel below the band. Sharper form: their two decoupled `ψ″` states seeded **×2** also move nothing above the band. Both are bands and not `===`, and the reason is a finding: a differential state with a zero Jacobian row still sits in the implicit solver's Newton system, so the LU mixes it in at round-off. Fixed `dt` tightens it to ~1e-15 without reaching zero | **positive control (band, with the reason for the band measured)** |
| Model bases at the new tier | Re-run on the 250 MVA / 60 Hz fixture with the process-global bases deliberately poisoned to 1.0/1.0 first. A new tier is a new place for construction-time globals to go stale | structural (mutation-checked) |
| A stator coefficient wrong on our side only | **Caught on `E′q`, invisible on `V`.** A 1 % `X′d` error moves the voltage by 1.6e-15 (the honest gap) because the initialisation re-derives `E′q = Vq + X′d·Id` and buys a compensating internal voltage; it moves `E′q` by 1.6e-4 against a 2.2e-16 honest gap, linearly in the error. This is the measured justification for "assert per state" — the channel that hides it here is `V`, not `f_coi` | **external, anti-vacuity (channel-specific)** |
| A branch reactance wrong on our side only | Flat-run `V` gap 2.5e-5 at a 1 % error and 2.5e-6 at 0.1 %, against a 8.9e-16 honest gap — nine to ten orders. The mapping class the oracle exists for | **external, anti-vacuity** |
| A coefficient wrong inside `_stator` itself | **Not this oracle's catch.** A 1 % error in the `Iq` coefficient is refused at BUILD time by the back-substitution residual (0.010 against a 1e-10 gate) and never reaches a comparison. The two guards are in series and it matters which fires | derived (structural) — **explicitly not external** |
| `X_d`, `X_q`, `vf_set` at this degeneration | **Nothing — and asserted, not caveated.** `X_d` scaled ×4 leaves every channel bit-identical; `vf_set` bumped 1 % moves 8.9e-16, because the excitation reaches only a derivative that `T′ = Inf` zeroes. On the transient voltage channel a **20 %** `X′d` error (4.8e-4) is smaller than the stator-`ω` residual (2.8e-3), so the reactances are pinned by the flat run and by nothing else here | **un-oracled at this step, bounded by assertion; step 4 owns it** |
| `TripGenerator` at the detailed tier | Refused by `build_oracle(:sauer_pai)` because `inject!(::DetailedEngine, ::TripGenerator)` refuses it too — an oracle case our own engine cannot run would read as a fidelity finding | structural (refused rather than faked) |
| Which stored sample an output time means | `_sample_rows`: the solver is handed the output grid as its own `saveat` and nothing is reconstructed from an interpolant, but a callback firing AT a grid point stores that instant **twice**. The pre-event row is taken, matching the playback driver's own convention. M4's 82/82 is unchanged by making the choice explicit. **All three of its throws are exercised directly** — a stored time nobody asked for, a solve that stopped early, samples past the end of the grid — because a guard nobody has seen fire is a guard nobody knows fires | structural (all branches exercised) |
| The flux equations with the mechanism ON (M5 step 4) | `detailed_pair()` (`T′do = 8 s`, `T′qo = 0.4 s`, `Xd = 1.8`, `Xq = 1.7`) against `SauerPaiMachine` with the flux live on both sides: flat run per state below 1e-8 at two tolerances; transient residual still **first order in slip**, coefficient 1.006 stable to 7e-4 across a 4× disturbance range. Our own flux moves 2.3e-3 – 9.7e-3 and the `E′q` gap is **191-424 bands**, where step 3's was 2.2e-16 — the channel carries information for the first time | **external** |
| `(Xd − X′d)` reaching the equations at all | **The step-3 mirror, on ONE fixture with `T′` as the only difference**: a 1 % `Xd` error is **bit-identical** (`===`) with the flux frozen and **12.7 bands** with it live. Step 3 asserted the first half and named step 4 as the owner of the second | **external (mutation-checked, both branches run)** |
| Which channel sees which flux error | Three mutations on our side only: `T′do` ×1.10 → ×14.8 on `E′q`; `Xd` ×0.90 → ×27.0 on `E′q`; `T′qo` ×1.10 → ×13.6 on `E′d` — and ×0.9-1.0 on `V_B1` and on `f_coi` in **every** case. The two axes are separated BY CHANNEL, so a per-state comparison says which equation is wrong. Each ships the control that separates "invisible" from "not applied" (our own trajectory moves 1.6e-5 – 5.1e-4) | **external, anti-vacuity (axis-specific)** |
| This oracle's RESOLUTION on the flux data (D19) | **~10 %, and the limit is not solver noise.** The honest `E′q` gap is 304 bands — step 3's stator-`ω` residual arriving through `Id` — and a 1 % `Xd` error only doubles it. The closed form is four orders sharper. Recorded because "checked externally" is not "checked tightly"; this is `m4-context.md` D7's floor-not-ceiling, quantified on a second set of equations | **measurement** |
| The `X″ = X′` degeneration, re-checked with the flux live | `X_ls` at 0.1 and 0.9 of its range moves every channel by 1.2e-10 against a 2.2e-6 band, and their two `ψ″` states seeded ×2 and shifted still move nothing above it. **Re-run rather than assumed to carry**: `γ_d2` multiplies `ψ″_d` INSIDE the `E′q` equation, and step 3 established the decoupling with a zero derivative in front of that equation | positive control, re-measured at the new fidelity |
| The read-out's shape actually satisfies `divergence` | The docstring's claim ("applies across the two sides with no adapter") is **called**, not described: `divergence` on the ring line-trip run reproduces the same worst gap the per-channel read gives, reports a departure (as it must — the stator-`ω` residual is real), and **throws** when handed two different grids. Matching key sets is a weaker claim and was the only one made before | structural |

## External oracle for the exciter (M5 step 5) — `AVRTypeI` at `Ta → 0`

**What is compared, and what deliberately is not.** `AVRTypeI` degenerates onto our
one-lag exciter exactly (`Kf = 0`, `Se1 = Se2 = 0`, `Ke = 1`, `tmeas_lag = false`,
`Ta → 0`) and does NOT have our limits. `Ta → 0` is a **limit, not a setting** — their
`Ta` multiplies a derivative — so this comparison is one lag richer than ours by
construction and the difference is first order in `Ta`.

The fixture is `infinite_bus_system(; K_A, T_E)` rather than the three-path one, and
that is structural: `_assert_sauer_pai_tier` refuses a machine-free bus, and the
three-path fixture's junctions are exactly that. Two buses means a line trip would
island the machine, so the disturbance is a **setpoint step** — a parameter on both
sides, needing no event type. It also makes the comparison unusually clean: at zero
loading `ω ≡ 1` exactly on both sides, so the stator-`ω` residual that held the step-4
oracle to ~10 % **vanishes identically** and the exciter is the only difference left.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| Seeding, and that our derived `Vref` is theirs | The flat run per state at two tolerances: their `vfout` and `vr` both seeded at OUR dispatched field voltage and their `vref` at OUR derived setpoint. A supplied (rather than derived) setpoint would show as a startup transient on one side only | **external, per state** |
| The exciter loop itself | A setpoint step: both sides move by the closed-loop DC gain `K_A·ΔVref/(1 + G)` to 1e-3, and the gap between them is bounded by the **derived** band `Ta·(1 + G)/T_E` × the excursion — written before the gap was seen, from the missing lag rather than from the measurement | **external, band derived from the model difference** |
| …and that the gap IS the missing lag | **The signature, not the size**: halving `Ta` halves the gap. A tolerance can be wrong in a way a signature cannot | **external, signature (first order in `Ta`)** |
| The stator-`ω` residual is absent here | Asserted, not assumed: `ω ≡ 0` to 1e-12 on both sides and the rotor angle fixed to 1e-9, because the fixture carries no real loading. That is what lets this band be tight where step 4's could not be | derived + **asserted** |
| The exciter is actually WIRED, not seeded and idle | Anti-vacuity: `K_A` doubled moves THEIR field voltage onto the new closed-loop gain (and their bus voltage by > 1e-3). A disconnected exciter would hold its seeded value and, at a small enough step, look like agreement | **external, anti-vacuity** |
| The LIMITED exciter | **Nothing, and refused rather than approximated.** Their limits are on `vr`, ours on `Efd`; a comparison would be two different models and the gap would read as a fidelity finding. Refused by `_assert_avr_tier` by name. The limit's oracle is the closed form above, which is four orders sharper than this comparison | **refused (not un-oracled — the closed form owns it)** |
| A regulator handed to the held-field tier | `build_oracle(tier = :sauer_pai)` calls core's own `_assert_no_regulator`, so an exciter cannot be silently dropped by picking the wrong tier. Core's guard, not a copy | structural (guard) |
| `Efd_<id>` at the `:sauer_pai` tier | **Nothing, and said out loud.** The channel is a held parameter on their side and a zero-derivative state on ours, so it is constant on both and carries no information there. It exists so the two key sets match, which `divergence` and the suite's `keys(o) == keys(t)` both require | **vacuous by construction, named** |

## External oracle for the load (M5 step 6) — `ZIPLoad`

**The header claim, before the rows.** `ZIPLoad` carries **no state** and its
polynomial with `Vset = 1` is ours term for term, so unlike the exciter comparison
there is no structural gap to allow for. Two rejections were lifted to get here: a
load is now a `ZIPLoad` injector on its bus, and a machine-free bus is `MTKBus()`
with the load as its only injector — or with none at all, for a bare junction. In
exchange the **classical** tiers now refuse a load by name, which they did not
before; that is a tier boundary (`SwingEngine` refuses the same model) rather than
unbuilt work.

| Mechanism | Checked by | Label |
|:---|:---|:---|
| The load equation itself | **The flat run, and it is the sharpest check here by four orders.** At `ω ≡ 1` the stator-`ω` residual vanishes identically (the same argument D22 used one mechanism along), so nothing separates the two sides but the load equation and round-off. Four splits × two tolerances, per channel: worst 1.1e-13 against a 1e-11 gate. Not a soft check — the seed is OUR fixpoint, so a difference in sign, normalisation or which share multiplies which power of `\|V\|` would move their bus voltages off it | **external, round-off (1e-11)** |
| …and how far it WOULD move | **Ten orders.** Our side built on a constant-impedance load and theirs on a constant-power one: 8.1e-3 on a rotor angle, 4.0e-3 on the load bus voltage. Repeated at every split | **external anti-vacuity (10 orders)** |
| …and the channel that cannot see it | **`f_coi` reads 1.4e-14 through that mutation — exactly what it reads unmutated.** Both runs are flat (each side at its OWN equilibrium), so every rate-like channel reports agreement: `ω`, `E′q`, `E′d`, `Efd`, and the slack angle `δ_G1` (pinned at zero on both sides, 7.8e-14). A load model wrong by 4 % in drawn power reads GREEN on the default channel. Asserted as a requirement, not a caveat — see `m5-context.md` D24 | **finding: the check must name a POSITION channel** |
| Whether the load adds a residual of its own on a transient | **No, and shown by SCALING rather than by a bound.** A magnitude bound could not separate a load error from step 3's known stator-`ω` residual. So `gap / (slip × \|V\|)` is measured at four splits × three disturbance sizes: it holds to three digits over a fourfold change in disturbance (Z 0.962, I 1.077, P 1.232, mix 1.121) and stays of order one. A load-model error would add a slip-INDEPENDENT offset and the ratio would fall as the disturbance grew | **external, signature (first order in slip)** |
| The sign convention | Read back off the constructed case: a load drawing 110 MW on a 100 MVA base appears as `Pset = −1.1`. Theirs is an INJECTION (`guess = -1`; their `ConstantYLoad` writes `iload = −Y·u`) and ours is a draw, so getting it backwards would turn a load into a generator of the same size | **structural, asserted from the built case** |
| The normalisation | `Vset = 1` asserted, which is what makes their `Vrel` our `\|V\|`. Anywhere else and their `Pset` denominates a different quantity from our `P₀`, and the comparison measures the normalisation | structural, asserted |
| Their share defaults | `KpC`/`KqC` have default EXPRESSIONS (`1 − KpZ − KpI`) that compute the right value. All six are passed explicitly anyway — a default is not a guarantee — and the test asserts the passed value equals what the default would have produced, so removing the default changes nothing | structural, asserted |

## The criterion, and M3's protection at the detailed tier — M5 step 7

The measurement the milestone exists for, plus the three armed mechanisms M3 built
re-checked one tier up. Numbers and their derivation:
`docs/plans/entsoe-iberia-reproduction.md` §7.7; decisions: `m5-context.md`
D25-D28; the script is `scripts/iberia_two_area.jl` section 5.

| Mechanism | Checked by | Label |
|---|---|---|
| **The criterion** — the detailed tier both loses synchronism and exceeds the classical tier's `P_max` | At the classical tier's own slip boundary (5,500 MW, derived cascade): slips, peak export **1.0295 × `P_max`** at reltol 1e-5 (1.0317 at 1e-3). The classical tier's own peak in the same run is `P_max` to four decimals — the bound is ATTAINED, so the comparison is against a reached ceiling and not a slack one. **Two halves asserted separately** | **derived (the tier's own equations), two tolerances** |
| …and it is not one cell | 14 of 14 cells of a one-axis-at-a-time walk satisfy BOTH halves: `T′do` 4-12 s, `Xd` 1.5-2.2, `K_A` 50-400, `Efd_max` 2.5-8.0. Range of peak/`P_max`: 1.0158 - 1.0416. Every one of those inputs is a `[CHOICE]` on an aggregated area, which is why the claim is the column | **sweep (§7.3's discipline)** |
| **The anti-vacuity control** — frozen flux must FAIL | It does: 0.9614 × `P_max`. And it fails against a **DERIVED prediction**, `\|E′₁\|\|E′₂\| / (X_tie + X′d₁ + X′d₂)`, met to **one part in a million** — not a tolerance fitted afterwards. The first run read 0.03 % ABOVE the bound and that excess was solver error, gone at reltol 1e-5 | **anti-vacuity with a closed-form prediction** |
| …and what that control actually is | **Not "the classical tier"**, and the ledger says so rather than letting the name stand: the bound is strictly TIGHTER than `P_max` because the classical tier puts `E′` at the bus and this one puts it behind `X′d`. It is the classical MECHANISM inside the detailed engine — the sharper comparison, and the only one the tier boundary (D25) allows | **named boundary** |
| Which mechanism actually beats the ceiling | **The regulator, and the flux alone points the OTHER way** — 0.8865 × `P_max` with the flux live and no exciter, against 0.9614 frozen, with `\|V\|` falling to 0.809. Recorded because the natural story ("voltage dynamics beat a constant-voltage ceiling") is wrong and would have shipped unchallenged with only two rows | **finding (three rows, not two)** |
| That the two runs are one case | **`==`, field by field**: the classical and detailed models agree bit for bit in every quantity `SwingEngine` reads and differ in exactly the set it REFUSES by name. The plan's "one model, both engines" is unavailable and the refusal is why (D25) | **structural, asserted (not intent)** |
| The generation ramp at this tier | `ω_ss = ΔP/(Σ1/R + ΣD)` to **9.5e-11** relative, per machine and on `ΔPm` too. Positive control: no ramp settles at `ω = 0` to 1e-12. **Anti-vacuity RUN**: ramp × 1.5 moves the settled speed × 1.5, which a formula wrong by a constant factor could not do. Precondition asserted: no machine touched its ceiling | **closed form (M3's, re-derived at this tier)** |
| …and that a zero-rate ramp changes nothing | `==` across every channel, not `≈` — `Pm + 0.0` is `Pm` bit for bit. Paired with a read-back that the ramp was actually armed, so the equality is about `rate = 0` and not about a dropped argument | **structural, bitwise** |
| The shed ladder at this tier | Root-found **inside the bare run's one-`dt` bracket and off the `dt` grid**; steps THAT machine's `Pm` by exactly the block (1e-14); and the settled speed lands on the closed form **that includes the block**, which is a different number from the un-shed one by a factor of three | **closed form + root-finding** |
| The out-of-step relay at this tier | `\|δ\|` at the reported instant **equals its threshold to 1e-10** — the direct check that the root was found on the intended quantity, not merely near it. Fires through the engine's own `inject!(::TripLine)`: branch out, one event logged, and `_reinitialise_algebraic!` accepted the post-trip solve (it throws with a number if it does not) | **root-found, and the re-init exercised by it** |
| …and the guards behind all three | `SwingEngine`'s OWN binders (`_bind_ramps`, `_bind_shed`, `_bind_out_of_step`, `_guard_out_of_step_start`), reached from this tier rather than copied — so a rule cannot come to differ between the tiers. Three messages asserted one by one | **structural (shared, not duplicated)** |
| **The one piece that does NOT carry** | A shed ladder on a model with a `Load`. At the classical tier `Pm` is a NET injection; here it is MECHANICAL power, so the same operation would ADD GENERATION instead of removing load, and the two differ by exactly step 6's voltage-dependence. **Refused by name**, with the step that lifts it in the message — and the test asserts the other half, that the same ladder on a load-free model builds | **refused (not approximated, not documented)** |
| `inject!`'s consistent re-initialisation (D8) | **The flat run ACROSS an event**, on `quiet_ring()` — every machine at zero injection with the same internal voltage, so every branch carries exactly zero current and the post-trip equilibrium IS the pre-trip one. Departure across a line trip: **exactly 0.0** on every channel, `==` | **known equilibrium, exact** |
| …and what that check cannot do alone | **It cannot separate a correct re-init from a no-op** — the re-solve starts at the answer and lands on it. Said out loud and paired: the quiet fixture proves no artefact is INJECTED, and a loaded-ring positive control (0.286 rad on `δ_G2` through the same trip) proves the event reaches the system | **stated limitation + positive control** |
| The transfer read-out itself | `branch_power` is ONE function answering for both tiers (`K·sin δ` and `Re(V·conj(I))`), asserted antisymmetric, against the closed form, and against Kirchhoff at a bus. `branch_power_series` walks the integrator's saved samples — never the interpolant — and **refuses** a branch any logged event touched rather than reporting the wrong coupling | **structural (one implementation, guarded)** |
| Why it is not a recorded channel | **Deliberate, and outside this engine**: `reference/`'s oracle asserts `keys(o) == keys(t)` at four sites, so a `P_<branch>` channel is one PowerDynamics must grow too. Step 7 would then depend on an oracle change it has no business making (D26) | **named boundary** |
| Solver conditioning at this tier | **`abstol`, not `reltol`, decides completion, at ISOLATED points**: on the flux-only cell at reltol 1e-5, abstol 1e-7 fails where 1e-5, 1e-6, 1e-8, 1e-9 and 1e-10 all complete and agree to 2 parts in 10,000. Step 5's finding on a second case, and on cells with **no regulator** — the governor headroom is a hard saturation too. A non-completing sweep cell is retried once at a looser `abstol` and **marked** | **measurement (with the sweep that justifies the retry)** |
| The field ceiling's overshoot | **Reported, not hidden**: 5.18 pu at reltol 1e-3 and 5.11 at 1e-5 against a stated 5.0 — the single step that lands on the limit (step 5's measurement, on a fast state). The `Efd_max` axis is swept for exactly this reason, and at 2.5 — half the centre value — the criterion still holds at 1.0164 | **measurement, with the sweep that rules it out as the cause** |
| The voltage COLLAPSE (12:33:21.5 → 27) | **Still nothing, and still said out loud.** The tier has bus voltages and the flux-only cell reaches 0.81 pu, but reproducing the collapse needs load that falls away and protection that trips on voltage. §7.6's boundary moves; it does not disappear | **un-oracled — out of scope, named** |

## Owed rows

Rows M5 will need before it ships:

- The M5 rows: flux equations, exciter, power-flow initialisation, algebraic
  network, **voltage-dependent load** — all delivered, steps 1-6 — and the **D8
  flat run across an event**, **M3's protection re-validated at this tier** and
  **the Iberian criterion itself**, all delivered by step 7 in the block above.
  Still owed: the voltage-visible window (plan step 8), and SPEC §7.6's third
  lesson (IBR behaviour), which has no tier and is **un-scheduled** rather than
  implied by M5's voltage work.
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
