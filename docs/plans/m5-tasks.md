# M5 — Tasks

The checklist. Companion to `m5-plan.md` (the how) and `m5-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate** — which in M2, M3 and M4 was every round's most
valuable line.

Status: **not started.** Entered at `86651ab` with **1873 core / 172 UI / 82
reference** tests green. The physics is worked on paper in `m5-prestudy.md`; no M5
code exists.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed* — not when the code
runs. Five planned M3 checks would each have passed against the very bug they
targeted; M4 step 4's round-winning check was not on the plan's list at all.

---

## Step 0 — planning (this batch)

- [x] `m5-prestudy.md` written and, after M4 landed, extended with §2a
      (`SauerPaiMachine` read from source at the pinned 5.0.0).
- [x] Plan trio written (`m5-plan.md`, `m5-context.md`, `m5-tasks.md`), citing the
      pre-study rather than restating it (§8 states that boundary itself).
- [x] Verified that `m4-plan.md`'s superseded degeneration bullet **already
      carries** its inline `Superseded — see m5-prestudy.md §3 and §2a` note, so
      §3's "correct it when the trio is written" is discharged rather than
      duplicated. An item carried in two places is how Figure 3-67 got carried
      through three milestones.
- [x] `docs/plans/README.md` M5 row updated off "Pre-study only", and its two
      stale "owed" lines corrected — the export-collision check and step 2's test
      execution are both ticked in `m4-tasks.md`.

## Step 0b — split `test/runtests.jl` (D9)

Refactor before feature: the old suite is the only oracle, and D3 changes the one
type every existing test constructs.

- [ ] Every helper defined between testsets (`ratio_ring`, `lockstep_coi`,
      `pb_both`, `overlay_pair`, …) moved to `test/helpers.jl`, `include`d at top
      level **before** the outer testset — the scope trap named in
      `docs/plans/README.md` §Structure notes.
- [ ] One file per milestone, `include`d in the same order as today.
- [ ] **Gate: the test count is identical, 1873 core.** A mechanical move that
      silently drops a testset is the one failure this step can introduce.
- [ ] No assertion text changed in this commit. A move and an edit in one diff is
      unreviewable.
- [ ] Anti-vacuity: delete one `include` line and confirm the count *drops* —
      i.e. that the count is actually being read and compared, not printed.

## Step 1 — algebraic network, power flow, flat run (D1, D3, D7)

The three land together because none is testable without the others.

**Model (D3)**
- [ ] A load type at a bus, and buses without machines, expressible in
      `NetworkModel`.
- [ ] The one-machine-per-bus and machine-free-bus **rejections moved out of the
      constructor** and into `SwingEngine` as a build-time precondition, shaped
      like `reference/src/oracle.jl`'s `_assert_governor_free` / `_assert_radial`:
      refused by name, with the tier named in the message.
- [ ] Existing M2/M3 scenarios construct unchanged and every existing test still
      passes — the count from step 0b, not a new one.
- [ ] Anti-vacuity: hand `SwingEngine` a two-machine bus and confirm the new
      precondition throws. The rejection must be *loud*, which was its whole
      purpose in `network_model.jl`'s header.

**Network**
- [ ] Bus vertex carrying `(V_re, V_im)` with `mass_matrix = 0`, residual =
      Kirchhoff's current law over incident edges.
- [ ] Stiff solver (`Rodas5P` or `FBDF`) with NetworkDynamics' Jacobian sparsity.
      **No admittance matrix is formed anywhere** (SPEC §6) — assert structurally,
      as M2 did.

**Initialisation (D7)**
- [ ] `find_fixpoint` on the **static** network from a flat guess.
- [ ] The solution is **checked, not trusted**: `|V| ∈ [0.9, 1.1]`, branch flows
      below rating, residual `< 1e-10`.
- [ ] Machine states back-substituted in closed form (`m5-prestudy.md` §4), with
      `Pm` the **air-gap** power, not the terminal power.
- [ ] Never solved jointly with the dynamic states from a flat guess — the joint
      problem has spurious equilibria (a machine at `δ + π`) that look converged.
      Assert the guard, not just the comment.

**The flat run — the check no overlay can perform**
- [ ] No disturbance, full horizon, **every state constant** to solver tolerance.
- [ ] Asserted **per state**, never on `f_coi`: a wrong `E′d` leaves frequency
      flat while the voltage rings.
- [ ] At **two tolerances**.
- [ ] Positive control: a deliberately mis-initialised state (perturb one `E′q` by
      1 %) must make the flat run visibly non-flat, and the per-state assertion
      must be the thing that catches it.

**Measurement S3 (D10) — the number that decides D2**
- [ ] Steps per simulated second and wall-clock per simulated second, two-area,
      DAE against the classical tier at the same tolerance. Recorded in
      `m5-context.md` under D2 with the machine and Julia version, as M4 recorded
      its dependency probes.

## Step 2 — the two-axis machine and the frozen-flux degeneration (D4, D6)

- [ ] `src/engines/detailed.jl`: the machine of `m5-prestudy.md` §2, **power
      form** (D6), on terminal buses.
- [ ] Playback half of the interface only (D2): `init!` / `solve!` /
      `state_series`, via the shared driver in `src/engines/playback.jl` plus
      `_record_at!` and `_aggregate_weight`.
- [ ] New `machine_arrays` columns (`Xd, Xq, X′q, T′do, T′qo, Ra`), reactances
      scaling **inversely** with `S_rated/S_base`, time constants base-free.
      `machine_arrays` stays the single place any conversion happens.
- [ ] Defaults degenerate to classical (D4), so existing scenarios are the
      degeneration case without a parallel set of constructors.
- [ ] Anti-vacuity on the conversion: assert the **wrong** conversions by name
      (`Xd·w` where `Xd/w` belongs), as M2 did for `Xd′` and `R`.

**The internal oracle**
- [ ] At `X′d = X′q`, `T′do = T′qo = Inf`: reproduces `SwingEngine` to solver
      tolerance, **at two tolerances**, on `two_machine_system()`.
- [ ] The `E′`-at-the-bus vs `E′`-behind-`X′d` reconciliation uses
      `reduced_line_reactance` — **radial pair only**. Record in the test *why*
      the ring is excluded here and simultaneously valid in step 3: the two
      comparisons have opposite topology restrictions
      (`m5-prestudy.md` §7 point 1, §2a).
- [ ] Anti-vacuity: perturb a **stator algebra** coefficient (not a flux one) and
      watch it go red. A flux mutation is *invisible* in this limit
      (`m5-prestudy.md` §3) — write that down in the test so nobody later reads
      this check as covering the flux equations.
- [ ] `docs/validation-ledger.md` rows added, with the exactness condition stated
      and what this check **cannot** see named explicitly.

## Step 3 — PowerDynamics with flux off on both sides (D5, D6, D10)

**Spikes first — a skipped spike becomes an assumption.**
- [ ] **S1**: is `T′ = Inf` expressible on PowerDynamics' multiplied form
      (`Inf·ẋ ~ finite` through `mtkcompile`)? Result recorded in `m5-context.md`
      D10 either way. If not: large-but-finite `T′` with a `1/T′` **convergence**
      check (residual falls a decade as `T′` rises one), scoped as a different
      check from an exactness assertion.
- [ ] **S2**: what does MTK's initialiser do with `bounds = (0, Inf)` on `vf`,
      `τ_m`, `τ_e`? If the bounds bite, add a build-time model precondition
      shaped like `_assert_governor_free`.

**The comparison**
- [ ] `build_oracle(net; tier = :sauer_pai)` — a second tier alongside `:swing`,
      **compiled from `NetworkModel`, never typed beside it** (`m4-context.md` D5).
- [ ] `vf_input = false`, `τ_m_input = false`, `stator_dynamics = false` all
      passed **explicitly** — a default is not a guarantee (`oracle.jl`'s own
      stated reason).
- [ ] `X_ls < X′d` enforced at build time (their `γ_d1` divides by `X′d − X_ls`).
- [ ] Their two sub-transient states **seeded from our fixpoint** by the closed
      forms in `m5-prestudy.md` §2a, so the flat run checks *our* initialisation
      rather than their power flow. A per-state flat comparison **skips those two**
      — a state that drives nothing has no counterpart to be equal to.
- [ ] Flux frozen on both sides; band written **before** the gap is seen, derived
      as `oracle_band` already derives it.
- [ ] **The stator-`ω` residual is identified by its signature**, not absorbed:
      `(ω − 1)·V`, first order in slip, zero at synchronous speed (D6). Assert the
      sign and the size, as M4 did for D14 — do not widen a tolerance around it.
- [ ] **The free positive control (D5)**: vary `X_ls` across a run; every
      comparison channel must be **bit-identical** (`===`, the only thing that
      caught M4's off-by-one). If anything moves, the degeneration did not take.
- [ ] The ring runs here — both sides on terminal buses, no reduction, the case
      `m5-prestudy.md` §7 had ruled out for the classical tier
      (`m4-context.md` D13).
- [ ] Anti-vacuity: perturb one coefficient in our stator algebra; the external
      check must go red. **Run it.**

## Step 4 — flux on: the equations step 2 could not see

- [ ] **The other limit.** `T′do, T′qo → 0` reproduces the steady-state
      constant-`Efd` `(Xd, Xq)` machine. With step 2 this brackets the flux
      equation from both sides.
- [ ] **The closed form.** Single machine, infinite bus through `Xe`, regulator
      off: field flux decays with `T′d = T′do·(X′d + Xe)/(Xd + Xe)`
      (Heffron–Phillips `K₃T′do`).
- [ ] **The anti-vacuity mutation lives here**: perturb `(Xd − X′d)` and the
      *measured* time constant must move by the **predicted** amount — not merely
      move. Predicted first, measured second.
- [ ] **External**: PowerDynamics with flux on, against the same band. The
      *change* from step 3 is the flux term by construction — that is why step 3
      is a separate step (D6).
- [ ] Two tolerances on every numeric claim here.
- [ ] Ledger rows: the flux equations move from `un-oracled` to `closed form` +
      `external`.

## Step 5 — the voltage regulator

- [ ] Static exciter, one lag, hard limits (`m5-prestudy.md` §2).
- [ ] **Limits are saturations in the derivative**, never a clamp on the state —
      the M1 carried-forward rule, and independently the construction
      PowerDynamics' `AVRTypeI` arrived at.
- [ ] `isoutofdomain` gains two indices per machine, for the reason `ΔPm` has one.
- [ ] Closed form for the ceiling: it holds under sustained demand and **releases
      unaided** when demand falls, and a second disturbance after saturation does
      not freeze the integrator (M1's exact test, at this tier).
- [ ] External comparison for the **unlimited** exciter only. Recorded in the
      ledger that the **limited** exciter is *not* a matched-fidelity comparison:
      `AVRTypeI`'s limits sit on the regulator output `vr`, not on `Efd`, and its
      degeneration to our form needs `Ta → 0`, a limit rather than a setting
      (`m5-prestudy.md` §2a).
- [ ] Anti-vacuity: clamp the state instead of saturating the derivative and show
      a check goes red. This is the M1 bug reproduced deliberately, at a new tier.

## Step 6 — voltage-dependent load

- [ ] ZIP at the bus (`m5-prestudy.md` §6); constant-impedance the default,
      because it has the closed form (it folds into the admittance) and is what
      `ZIPLoad` configures down to.
- [ ] Closed form for the constant-impedance case, checked against the fixpoint.
- [ ] Frequency-dependent load stays on the machine until something measures the
      difference — recorded, not silently omitted.
- [ ] External: `ZIPLoad` configured to match.

## Step 7 — the criterion (the milestone's purpose)

- [ ] Locate the classical tier's slip boundary on the two-area case — **scan the
      boundary, do not bisect it** (M3 step 6's rule), rebuilding per cell rather
      than mutating a live coupling (the fixpoint depends on it).
- [ ] At that same tie strength, run the detailed tier and measure both: does it
      lose synchronism, and does the export swing peak **exceed** the classical
      tier's `P_max`?
- [ ] **The anti-vacuity control is specific and must be run**: freeze the
      voltages (step 2's degeneration) and the criterion must **fail** — the
      classical tier provably cannot satisfy it. If it passes with voltages
      frozen, the criterion is not measuring what it claims.
- [ ] Positive control: the criterion's two halves are checked separately, so a
      run that slips but does not swing (or the reverse) is distinguishable from a
      pass.
- [ ] M3's protection wired at this tier and **re-validated**, not assumed to
      carry: the shed ladder, the out-of-step tie relay and the generation ramp,
      each against the M3 closed form that still applies (D8).
- [ ] `inject!`'s consistent re-initialisation (D8) exercised: **the flat run
      across an event**, on a system whose post-trip equilibrium is known.
- [ ] Every number lands in `entsoe-iberia-reproduction.md` under §7.3's
      discipline — `[GUESS]` inputs marked, and a tuned parameter is not a result.
      **Write the prose after reading the table**: two M3 claims went in ahead of
      the numbers and both were wrong.

## Step 8 — the voltage-visible window (D12, first to be cut)

- [ ] Playback overlay on M4's scrubbable window: bus voltage magnitude alongside
      frequency, classical against detailed.
- [ ] `smoke_render` offscreen **first**, then the live window. Render before
      claiming.
- [ ] A `Label` with the right text that was never added to the figure passes
      every text assertion anyone can write about it — assert it is *in* the
      figure (M4 step 3).
- [ ] The M4 promise it discharges is named in the window's own docstring, so the
      commitment and the delivery are in one place.
- [ ] If cut (D11): the inherited promise is **restated in the follow-on batch**,
      not quietly dropped.

## Housekeeping owed by this milestone

- [ ] `docs/SPEC.md` §7.6's third lesson (IBR behaviour) still has no tier —
      stated as un-scheduled rather than implied by M5's voltage work.
- [ ] `docs/validation-ledger.md` gains a detailed-tier section, every row
      labelled, `un-oracled` rows stated out loud.
- [ ] `docs/plans/README.md` M5 row updated as steps land.
- [ ] Re-resolve all three environments from deleted manifests at the end, as M4
      step 5 did — the gitignored-manifest trap has now caught this repo twice
      (`m4-context.md` D15, and the 2026-08-18 stale dev manifest).
- [ ] `Pkg.add` rewrites `Project.toml` and drops every comment — `git diff` after
      any dependency change and put them back.
