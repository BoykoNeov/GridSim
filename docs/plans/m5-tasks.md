# M5 — Tasks

The checklist. Companion to `m5-plan.md` (the how) and `m5-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate** — which in M2, M3 and M4 was every round's most
valuable line.

Status: **steps 0b, 1, 2, 3, 4, 5, 6 and 7 done; step 8 open.** Entered at `86651ab` with
**1873 core / 172 UI / 82 reference**; the suite split left the core count
unchanged, step 1 brought it to **2083 core**, step 2 to
**2253 core / 172 UI / 82 reference**, step 3 to
**2253 core / 172 UI / 298 reference**, and step 4 to
**2342 core / 172 UI / 421 reference**, step 5 to **2503 core**, step 6 to
**2696 core / 281 UI / 986 reference**, and step 7 to
**2835 core / 281 UI / 986 reference** (+139 for the criterion and M3's protection
re-validated one tier up). The detailed tier now carries the
two-axis machine, reproduces `SwingEngine` at the frozen-flux degeneration,
initialises from a power flow whose machine model is the steady state of that
machine, is checked against PowerDynamics' `SauerPaiMachine` at both fidelities,
and — with the flux live — against a closed form and against its own `T′ → 0`
limit. **The three oracles resolve the same equations four orders apart, and the
external one is the coarsest** (step 4, F3).

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

- [x] Every helper defined between testsets moved to `test/helpers.jl`, `include`d
      at top level **before** the outer testset — the scope trap named in
      `docs/plans/README.md` §Structure notes. All fifteen: `argerr_msg`,
      `RECORD_ENTRY_POINTS`, `scale_inertia`, `trip_and_run`, `P0_of`,
      `governed_ring`, `_split_speed_net`, `_pole_slip_net`, `_SLIP_THR`,
      `ratio_ring`, `lockstep_coi`, `pb_steps!`, `pb_exc`, `pb_both`,
      `overlay_pair`.
- [x] One file per milestone, `include`d in the same order as today — **and the
      two halves of that sentence turned out to be incompatible.** See F1.
- [x] **Gate: the test count is identical, 1873 core.** Measured on both sides
      rather than read off the old note: `86651ab` gives 1873/1873, the split gives
      1873/1873.
- [x] No assertion text changed in this commit. A move and an edit in one diff is
      unreviewable — and here it is provable rather than asserted, see F2.
- [x] Anti-vacuity: delete one `include` line and confirm the count *drops*.
      Deleting `m3_two_area.jl`'s include gives **1811/1811**, 62 fewer.
- [x] **All three suites re-run, not just the one that changed.** The status line
      above states an entry state of 1873 core / 172 UI / 82 reference, so all
      three are the claim: **1873 / 172 / 82**, each green after the split. Neither
      `ui/test/` nor `reference/test/` reaches into `test/` — checked before
      running, since a suite that `include`d a hoisted helper would have broken
      silently — but a suite nobody ran is not a suite that passed.

### What this step found that the plan did not anticipate

**F1 — "one file per milestone" and "the same order as today" cannot both hold,
because the milestones interleave.** M3 inserted its steps 1–5 *ahead of* M2's own
tail: the line-trip block that `89c7074` appended at the end of M2's tests now sits
at line 3301, after 1,600 lines of M3. Preserving the execution order was chosen
over grouping by milestone — the gate for a refactor is that nothing changed but
the boundaries, and reordering execution is the one thing the count cannot
attribute. So M2 and M3 each occupy **two** files (`m2_network.jl` /
`m2_events_and_coi.jl`, `m3_governors_protection.jl` / `m3_two_area.jl`), and each
says in its own header why it sits where it does. Grouping by milestone remains
available as a *separate* later commit that only reorders — then a failure is
attributable to the reorder.

**F2 — the count is a weak gate, and the anti-vacuity run proved exactly how
weak.** With one `include` deleted the suite reported 1811/1811, `Pkg.test()` exited
**0**, and the last line still read `Testing GridSim tests passed`. Nothing about a
green suite distinguishes "every test ran" from "sixty-two of them silently did
not"; only reading the number does. So this step's real gate is a **reconstruction
check**: the split was emitted mechanically from a table of line ranges, and a
verifier reassembles the original from the files **on disk** by those ranges and
diffs it against `git show 86651ab:test/runtests.jl` — confirmed to be the same
blob as the working tree it was actually taken from, since `git diff 86651ab
97bcb33 -- test/runtests.jl` is empty. All **4,892** content lines
come back byte-identical, the ranges tile the original exactly once, and the frame
(`using`s, the two scenario modules, the outer testset) is verbatim. A dropped line,
a mis-closed testset, a stray edit or a line-ending slip all fail there; none of
them fails a count.

**F3 — the working copy was CRLF while `.gitattributes` mandates LF.** `*
text=auto eol=lf` means a fresh checkout hands back LF, but the file on disk was
CRLF, and `text=auto` normalises on comparison so `git status` called it clean. The
first split was generated from the stale copy; committing it would have produced a
whole-file diff and made the pure-move claim unverifiable. The splitter now takes
its line ending from the source it reads, and the verifier refuses mixed endings.

**F4 — hoisting is a name-collision hazard, because locals shadow and globals
collide.** Inside the outer testset those fifteen helpers were *locals*: a name that
`GridSim` or `Test` exports would have been silently shadowed. At module scope the
same name is a redefinition. `intersect` against `names(GridSim)`, `names(Test)` and
`names(Base)`: **none**. This is the M1 export-collision bug class one level in, and
it is worth re-running whenever a helper is added.

**F5 — two Julia facts make the layout legal, and both are load-bearing.**
`include` evaluates its file at **module** top level, never in the local scope of
the block the call appears in — which is *why* the helpers had to be hoisted, not a
style preference. And `@testset` nesting is **dynamic**, not lexical: `Test` keeps a
task-local stack, so a `@testset` inside an included file registers as a child of
whatever testset is running when the `include` executes. That is what lets the
includes sit inside the outer testset and still report as one tree. Both are written
into `runtests.jl` itself, because the next person to add a file needs them.

**F6 — one comment the move made visibly stale, left verbatim.** `# Two shared
helpers, defined once for the block below.` is followed by *three* helpers, and
"below" now means another file. The "two" was already wrong before the split. It is
not corrected here because this commit is a pure move; the group header added above
it names the file that uses them.

**F7 — wall-clock is not measurable on this machine right now, and step 1 needs
it to be.** Four runs of suites with identical content took 1m25, 2m28, 5m15 and
1m46, tracking an unrelated long-lived `julia.exe`. So **no timing claim is made
about the split**. This matters beyond bookkeeping: **S3** (D10) is a wall-clock
measurement and it is the number that decides D2. It must be taken on a quiet
machine, with the contending processes checked first, or it will decide D2 on noise.

## Step 1 — algebraic network, power flow, flat run (D1, D3, D7)

The three land together because none is testable without the others.

**Model (D3)**
- [x] A load type at a bus, and buses without machines, expressible in
      `NetworkModel`.
- [x] The one-machine-per-bus and machine-free-bus **rejections moved out of the
      constructor** and into `SwingEngine` as a build-time precondition, shaped
      like `reference/src/oracle.jl`'s `_assert_governor_free` / `_assert_radial`:
      refused by name, with the tier named in the message.
- [x] `coi_model` gains the **same precondition** (D3): it refuses a model with
      loads or machine-free buses rather than quietly aggregating over the
      machines. It is SPEC §3.2's one working proof that reduced models are
      derived views; an unvalidated ZIP-into-`D` fold does not go inside it.
- [x] Existing M2/M3 scenarios construct unchanged and every existing test still
      passes — the count from step 0b, not a new one. A negative-`P0` machine
      stays a machine (the M2a load convention is added to, not replaced).
- [~] The detailed parameters arrive as keywords (D4) — the single validated path
      stays single, and the inner signature does not grow to ~22 positionals.
      **Ticked in error at step 1: nothing implemented it.** There were no detailed
      parameters to carry until step 2 added them, so the box belonged there and is
      done there. The *outer* constructor D4 asked for also turned out to be
      impossible — see step 2's findings.
- [x] Anti-vacuity: hand `SwingEngine` a two-machine bus and confirm the new
      precondition throws. The rejection must be *loud*, which was its whole
      purpose in `network_model.jl`'s header.

**Network**
- [x] Bus vertex carrying `(V_re, V_im)` with `mass_matrix = 0`, residual =
      Kirchhoff's current law over incident edges.
- [x] Stiff solver (`Rodas5P` or `FBDF`) with NetworkDynamics' Jacobian sparsity.
      **No admittance matrix is formed anywhere** (SPEC §6) — assert structurally,
      as M2 did.

**Initialisation (D7)**
- [x] `find_fixpoint` on the **static** network from a flat guess.
- [x] The solution is **checked, not trusted**: `|V| ∈ [0.9, 1.1]`, branch flows
      below rating, residual `< 1e-10`.
- [x] Machine states back-substituted in closed form (`m5-prestudy.md` §4), with
      `Pm` the **air-gap** power, not the terminal power.
- [x] Never solved jointly with the dynamic states from a flat guess — the joint
      problem has spurious equilibria (a machine at `δ + π`) that look converged.
      Assert the guard, not just the comment.

**The flat run — the check no overlay can perform**
- [x] No disturbance, full horizon, **every state constant** to solver tolerance.
- [x] Asserted **per state**, never on `f_coi`: a wrong `E′d` leaves frequency
      flat while the voltage rings.
- [x] At **two tolerances**.
- [x] Positive control: a deliberately mis-initialised state (perturb one `E′q` by
      1 %) must make the flat run visibly non-flat, and the per-state assertion
      must be the thing that catches it.

**Measurement S3 (D10) — the number that decides D2**
- [x] Steps per simulated second and wall-clock per simulated second, two-area,
      DAE against the classical tier at the same tolerance. Recorded in
      `m5-context.md` under D2 with the machine and Julia version, as M4 recorded
      its dependency probes.


### What this step found that the plan did not anticipate

Six things, and four of them changed the design rather than merely being noted.

**1. The rotational gauge is NOT the reason the joint solve is unusable — and the
plan's reason was the right one for the wrong stated cause.** `find_fixpoint` on
the dynamic network fails from a flat guess (MaxIters, residual `2.6e-10` against
its `1e-10` tolerance — a factor of 2.6, close enough that loosening the tolerance
would "fix" it). The obvious explanation is the rotational null direction, and the
Jacobian does have exactly one (singular values `2.72, 0.472, 2.6e-11`). **But
`SwingEngine`'s fixpoint problem is rank-deficient in the same way** (`1.46e-14`
against `314`) **and converges anyway**, and pinning the slack angle *inside* the
dynamic network converges to `1.3e-15`. So the gauge alone does not force the
separate static network; seeding at the true solution does not help either, which
rules out the guess.

**2. What DOES force it: the joint solve finds wrong equilibria, and its residual
actively misleads.** Measured on the ring, slack pinned, seeding one rotor angle
away from its true value:

| seed for δ₂ | converged δ₂ | \|V\| | residual |
|:---|---:|:---|---:|
| true (−0.0287) | −0.028673 | (1.010, 1.004, 0.978) | 1.8e-13 |
| true + π | 2.943790 | (0.389, 0.203, 0.131) | **5.0e-16** |
| true + 2.5 rad | 2.943790 | (0.389, 0.203, 0.131) | 4.4e-16 |

The spurious point is self-consistent and converges **400× tighter than the true
one**, so no residual test separates them — only the `|V| ∈ [0.9, 1.1]` band does,
which is why that band is in the code as the discriminator and not as a comfort
check. The basin is narrower than π: 2.5 rad already falls in. Back-substitution
sidesteps the question entirely, because `δ` is never *seeded*, only computed.

**3. THREE guards had to move, not two — and the third for a stronger reason.**
The plan named the machine-free-bus and two-machine-bus rejections. The
`|P0| ≤ Σ K` reachability guard had to move too, because `K = E′ᵢE′ⱼ/X` is
**uncomputable** when a bus has no machine — not merely inappropriate. A guard
that cannot be evaluated cannot stay in a constructor that must accept the case.

**4. The slack is not a gauge choice, and the "free positive control" has a
precondition.** The plan's shape (D5's, one level down) says a parameter surviving
nowhere is a control, so changing it must change nothing. Measured:

| model | max\|ΔV\| | max\|Δ(δ−δ₁)\| | max\|ΔPm\| |
|:---|---:|---:|---:|
| `two_machine_system`, `three_machine_ring` (no load) | 2.2e-16 | 2.8e-17 | 1.1e-16 |
| `load_bus_system` (constant-impedance load) | 3.6e-4 | 1.5e-2 | 4.6e-2 |

**It survives, into the dispatch.** The slack absorbs the mismatch between a
schedule that balances at `|V| = 1` and a network that does not sit there. Both
answers are correct: with G1 as slack `Σ Pm = 1.054270` and the load draws
`1.054270`; with G2, `1.053793` and `1.053793`. So it stays an engine keyword —
a decision about a case — but the invariance check now carries its boundary, and
would have failed the first time anyone put a load in a model.

**5. The flat run is VACUOUS on every fixture the repo shipped before M5.** With
`Ra = 0` and no `Load`, the air-gap power equals `P0` exactly for every non-slack
machine, so `Pm := Pe` versus `Pm := P0` is unobservable and the check would pass
against the bug it exists to catch. `load_bus_system()` was built for this: the
slack settles at `0.65427` against a scheduled `0.7`, because the load at
`|V| = 0.979` draws `1.054` rather than `1.100`. The positive control is therefore
**the real bug** (take `Pm` from the schedule), and it makes the run run away by
6.6 rad with `f_coi` moving 0.157 Hz.

*Honest limit on the per-state form:* at step 1, `f_coi` would also have caught it.
"Assert per state, never on `f_coi`" is required for step 2's flux states, where a
wrong `E′d` rings a voltage and leaves frequency flat. The test says so rather than
implying the necessity has been demonstrated here.

**6. A state written into the integrator is silently discarded** (M3's finding,
re-confirmed and now load-bearing). A bare write to `integrator.u` left the run
flat at 3.9e-15; the same write followed by `u_modified!` + `auto_dt_reset!`
produced the seeded 0.05 offset. `_reinitialise_algebraic!` writes bus voltages
this way, so this is pinned by a test rather than trusted.

**7. The flat run claimed more than it earned until it was forced to step.** Left
to choose its own step size, `Rodas5P` crosses a 20 s flat horizon in **four
accepted steps**. So a 10 s flat run sampled at `saveat = 0.05` was asserting ~200
points that are almost all interpolations inside a handful of enormous steps —
which really only establishes that an implicit solver parks on an equilibrium,
something it will do even for equations that are wrong in ways that cancel *at*
the fixpoint. A third pass with `dtmax = 0.05` forces 201 real steps.

Measured, and it holds: worst drift `4.4e-14` under forced stepping against
`1.6e-14` unforced — the same order, which is what makes the unforced result
meaningful rather than merely quiet. Both facts are now pinned by assertions (the
forced pass must have taken ≥150 steps; the lazy pass must have taken <20), so a
future change to either cannot silently turn the third pass into a duplicate of
the first. `dtmax` became a constructor keyword for the same reason the tolerances
did in M4: a knob no constructor accepts is a knob the standing "run it again and
see if the number survives" rule cannot turn.

**And one scope note the plan implies but does not state:** the two-area case has
a **single tie**, so a line trip islands it and the DAE has no second angle
reference. S3 was therefore measured with an identical off-equilibrium start on
both tiers rather than with an event. That constraint belongs to step 7 as well.

### S3 — the measurement that decides D2

Both tiers, same tolerances (`reltol 1e-3`, `abstol 1e-6`), 20 s horizon,
`saveat = 0.02`, identical +0.05 rad offset on machine 1. Steps per simulated
second is the primary number (deterministic); wall clock is best-of-3 and noisy.

| case | tier | accepted steps | steps / s-sim | wall / s-sim |
|:---|:---|---:|---:|---:|
| two-area (2 bus, 1 branch) | classical, `Tsit5` | 41 | 2.05 | 1e-5 s |
| two-area | detailed, `Rodas5P` | 45 | 2.25 | 9e-5 s |
| ring (3 bus, 3 branch) | classical, `Tsit5` | 228 | 11.40 | 3e-5 s |
| ring | detailed, `Rodas5P` | **126** | 6.30 | 3.2e-4 s |

**The answer is comfortable, and one number is the opposite of the expected
sign.** On the ring the DAE takes *fewer* steps than the ODE (126 against 228),
because the implicit method is not paying for the stiffness the explicit one is.
The cost is per step, not per second: ~8.5× on the two-area case. In absolute
terms the detailed tier runs 3,000–11,000× faster than real time on both cases, so
**it is real-time steppable** and D2's playback-only default is a caution that the
measurement lifts rather than confirms. Julia 1.12.6, NetworkDynamics 1.3.0,
OrdinaryDiffEq 7.8.1, Windows 11.

Two caveats, stated rather than buried: these are 2- and 3-bus cases, and the
per-step cost of a sparse linear solve grows with size in a way two points cannot
extrapolate; and `step!` is still not implemented for this tier, so "steppable"
is a measurement about the solver, not a shipped capability.

## Step 2 — the two-axis machine and the frozen-flux degeneration (D4, D6)

- [x] `src/engines/detailed.jl`: the machine of `m5-prestudy.md` §2, **power
      form** (D6), on terminal buses. `_stator` is the stator algebra; the vertex
      carries `(V_re, V_im, δ, ω, ΔPm, E′q, E′d)`.
- [x] Playback half of the interface (D2) — **already satisfied by step 1**, and
      ticked with that note rather than rebuilt: `init!` / `solve!` /
      `state_series` / `inject!(::TripLine)` / `_record_at!` /
      `_aggregate_weight` all exist and step 2 only widened them.
      `inject!(::TripGenerator)` still refuses by name; the machine-status path it
      needs is **owed to the step that arms protection here** (step 7), and is
      recorded as owed rather than carried silently. `step!`/`timestep` remain the
      deferred methods.
- [x] New `machine_arrays` columns (`Xd, Xq, Xq′, Td0′, Tq0′, Ra`), reactances
      scaling **inversely** with `S_rated/S_base`, time constants base-free.
      The old `Xd` column — which held the *transient* reactance — was renamed
      `Xd′` in a separate commit first, because a column named `Xd` holding a
      transient reactance beside a new synchronous `Xd` is the kind of quiet
      mismatch this repo pays a round for.
- [x] Defaults degenerate to classical (D4), so existing scenarios are the
      degeneration case without a parallel set of constructors. Verified the
      strong way: `two_machine_system()`, `three_machine_ring()` and
      `load_bus_system()` all initialise to `E′d = 0` (< 1e-13) and
      `E′q = Machine.E′`.
- [x] Anti-vacuity on the conversion: the **wrong** conversions asserted by name
      (`X·w` where `X/w` belongs — wrong by `w² = 6.25` on the fixture), plus
      "no conversion at all", plus that the time constants take *neither* weight.

**The internal oracle**
- [x] At `X′d = X′q`, `T′do = T′qo = Inf`: reproduces `SwingEngine` **at two
      tolerances** on `two_machine_system()`. Gap / band = **0.31-0.33** at
      `reltol` 1e-4 and 1e-7 alike, on all four channels — the same ratio M4 step 4
      measured against PowerDynamics, which is what a band derived from each side's
      own convergence is supposed to produce.
- [x] The `E′`-at-the-bus vs `E′`-behind-`X′d` reconciliation, **radial pair
      only**, and the test records why the ring is excluded here and simultaneously
      valid in step 3. `reduced_line_reactance` itself lives in `reference/` and
      could not be called from a core test, so `terminal_bus_reduced` in
      `test/helpers.jl` is the same reduction applied to our own tier — and it
      indexes through `machine_arrays(net).bus` rather than assuming machine `k`
      sits on vertex `k`, which is an assumption `reduced_line_reactance` does make.
- [x] Anti-vacuity: perturbing `X′q` by 1 % goes red by **64-173x the band** on
      the four channels. **And the invisibility of a flux mutation is MEASURED
      rather than asserted**: thawing both time constants from `Inf` to 5.0 / 0.5 s
      moves the trajectory by 2.3e-14 at worst, four orders below the loosest band
      in the file.
- [x] `docs/validation-ledger.md` rows added, with the exactness condition stated
      and what this check **cannot** see named explicitly.

### What this step found that the plan did not anticipate

**1. D4's "keywords on an OUTER constructor" cannot be built, and the inner one is
the better answer anyway.** Keyword arguments do not participate in Julia's
dispatch, so an outer `Machine(id, bus, S_rated, H, D, Xd′, E′, P0; Xd = …)` has the
*same* positional signature as the inner constructor's eight-argument form — a
redefinition, not a second method. Keywords **on the inner constructor** give both
things D4 actually wanted (one method, one place validation lives, six names that
are never positional) with nothing extra. Pinned by a `MethodError` test, so a later
positional twelfth argument cannot silently land in one.

**2. The power flow's machine model had to be generalised, and it silently
reinterprets `Machine.E′`.** The static network's machine is now a q-axis source
behind `(Ra + jXq)` rather than behind `jX′d`, because that is what a two-axis
machine's steady state actually pins: `Ẽ = V + (Ra + jXq)·I` lies on the q-axis, so
`|Ẽ|` plus the scheduled `P` closes the solve. At the defaults `Xq = X′d`, `Ra = 0`
and this is bit-identical to step 1 — which is *why* it was the choice. But it means
`Machine.E′` denominates a different physical quantity at the two tiers with nothing
erroring in between, and with a realistic `Xq ≈ 1.8` the terminal voltage sits well
below `E′`, close enough to `_check_power_flow`'s `[0.9, 1.1]` band to matter when
step 4 builds a fixture with real synchronous reactances. Written into `Machine`'s
docstring and into D4 rather than left to be found.

**3. The re-initialisation needed a THIRD static mode (D16).** Step 1's `_PF_PIN`
re-solves the algebraic states with the machine's *steady-state* source — fixed
`|Ẽ|` — which is a statement about a machine at rest and is false mid-transient once
the flux can move. `_PF_HOLD` evaluates the machine's actual stator algebra at the
held `(δ, E′q, E′d)`. At the degeneration the two agree exactly, so step 1's version
was not wrong, only narrower than it looked.

**4. The classical tier needed a DATA precondition nobody listed (D17).** Once
`Machine` can carry `(Xd, Xq, X′q, T′do, T′qo, Ra)`, `SwingEngine` and `coi_model`
read none of them — that tier *is* the limit in which they do not matter — so a
machine with real detailed data would run there as a different machine than its data
describes, silently and plausibly. `_assert_frozen_flux` refuses it by name.
`build_oracle` in `reference/` has the same hole and it is **owed to step 3**, which
is where the `:sauer_pai` tier lands.

**5. The rotor-frame convention is pinned by exactly ONE check, and the other two
that look like they pin it provably do not.** Both mutations were run:

| mutation | build-time residual | flat run | `E′d = 0 / E′q = E′` |
|:---|:---|:---|:---|
| reflected frame (`Vd = Vre·sin δ + **+** Vim·cos δ`) | **caught, 5.03** | — | caught |
| consistent turn (`δ → δ + π/2` at both sites) | passes | passes | **caught** |

A reflection is not a rotation and stops preserving the inner product, so the
back-substituted-fixpoint check sees it. A consistent turn cancels out of every
expression that rotates *both* sides — including the free air-gap-power identity
this step added — and lands `E′d = [1.05, 1.02]`, `E′q ≈ 0`. Only asserting *which
state holds the magnitude* sees that.

**6. The "no dense admittance matrix" structural check was a bad proxy, and step 2
is what exposed it.** It read `length(u) < nb² + 2nb`; with five states per machine
on the 3-bus fixture that became `16 < 15` and failed. The state count is
`2·nb + 5·nm` — **linear in both** — and bounding a linear count by a quadratic one
says nothing on a small system and would pass against a genuinely dense engine on a
large one. Replaced by a **growth** assertion: `load_bus_system()` is
`two_machine_system()` plus one machine-free bus and costs exactly two more states,
where an admittance formulation would cost `O(nb)` more.

**7. `terminal_bus_reduced` was written with the ring's exclusion as a COMMENT, and
that is the failure `oracle.jl` names in its own words.** The arithmetic works on the
ring — every `X′d` converts to 0.10, so it returns `X = 0.05 > 0`, a positive
reactance and a model that builds, on a reduction that does not exist for a machine
of branch degree 2. The helper now **throws**, and the ring is the test of the
refusal rather than a caveat in a comment: *"a comment saying the ring is not a valid
oracle case is exactly the thing that gets stepped over later; a thrown error is
not"* (`reference/src/oracle.jl`, `_assert_radial`). Caught in review, not by a run —
which is the point of the review.

**8. `_PF_HOLD` is exercised only where it is provably identical to the mode it
replaced.** It exists because the steady-state source is false mid-transient once
the flux moves; at the degeneration the flux does not move, so every run that
exercises it is a run in which `_PF_PIN` would have given the same answer. The
ledger says so out loud rather than letting the row read as coverage — the
distinguishing case has no oracle until step 4 gives the flux something to do.

**9. Two tooling traps, both of which hid a real failure for a while.**
`reference/test/runtests.jl` had four `ma.Xd` sites the rename missed, because the
first sweep grepped `reference/src` and not `reference/test` — found only by running
the third suite, which is the standing rule and not bookkeeping. And a background
command written as `cmd > log 2>&1; echo "EXIT=$?"` reports the **echo's** status,
so a suite with four errors was reported to the session as exit 0. That is M4's
`| tail` trap in a new shape: anything appended after the command becomes the status
that is read.

## Step 3 — PowerDynamics with flux off on both sides (D5, D6, D10)

**Done 2026-09-06. 2253 core / 172 UI / 298 reference** (82 M4 + 216 new), all
three green. `reference/src/oracle.jl` gains the `:sauer_pai` tier;
`reference/test/runtests.jl` gains the step's eight testsets.

**Spikes first — a skipped spike becomes an assumption.**
- [x] **S1**: `T′ = Inf` **IS** expressible on PowerDynamics' multiplied form.
      `mtkcompile` accepts `Inf·ẋ ~ rhs` and the derivative is exactly zero, so
      the planned large-but-finite fallback is **not needed** and the exactness
      assertion is available. Recorded in D10. See F1 — the first version of this
      spike was vacuous.
- [x] **S2**: the `bounds = (0, Inf)` are **metadata, not enforced**. A machine
      with `τ_m_set = −0.5` builds, solves, and returns `τ_e = −0.316` straight
      through the declared bound. No model precondition is needed, and every
      fixture in the repo — all of which balance with a negative-`P0` machine —
      is runnable. See F2 for why M4's green suite did **not** already answer this.

**The comparison**
- [x] `build_oracle(net; tier = :sauer_pai)` — a third tier alongside `:swing`
      and `:classical`, **compiled from `NetworkModel`, never typed beside it**
      (`m4-context.md` D5). `X″ = X′` in both axes, so their sixth-order machine
      is our fourth-order one exactly.
- [x] `vf_input = false`, `τ_m_input = false`, `stator_dynamics = false` all
      passed **explicitly** — a default is not a guarantee (`oracle.jl`'s own
      stated reason). `Sn`/`Vn` are deliberately **not** passed: their
      `initf_weak` defaults are the ratio-of-one the builder wants, and passing
      them makes them live parameters scaling the terminal equations.
- [x] `X_ls < min(X′d, X′q)` enforced at build time — **both** axes, since
      `γ_q1` divides by `X′_q − X_ls` too. Without it the failure is a NaN
      trajectory inside somebody else's component, not an error.
- [x] Their two sub-transient states **seeded from our fixpoint** by the closed
      forms in `m5-prestudy.md` §2a, through `GridSim._stator` — the very
      function the engine's own RHS calls, so the rotor-frame rotation and the
      stator inversion exist once rather than twice.
- [x] Flux frozen on both sides; band written **before** the gap is seen, derived
      by `convergence_band` from each side's own coarse/fine pair.
- [x] **The stator-`ω` residual is identified by its signature**, not absorbed.
      `gap(V) / (peak slip × |V|) = 0.995 ± 0.002` across a factor of four in
      disturbance size, and doubling the disturbance doubles the gap to 0.1 %.
      The **coefficient** is asserted, not merely proportionality — see F6.
- [~] **The free positive control (D5)**: `X_ls` varied across a run moves every
      channel by ~1e-10, which is below the band but **not** bit-identical, and
      `===` turns out not to be available at all here. F4 is the reason and it
      cost nothing to find: the assertion is a band, and the *why* is a finding.
- [x] The ring runs here — both sides on terminal buses, no reduction, the case
      `m5-prestudy.md` §7 had ruled out for the classical tier
      (`m4-context.md` D13). The flat run passes on it at first attempt.
- [x] Anti-vacuity: **run, and it does not go red — the engine refuses to build
      first** (F7). A 1 % error in `_stator`'s `Iq` coefficient is caught at build
      time by the back-substitution residual (0.010 against a 1e-10 gate). What
      does go red, and on which channel, is F8.
- [x] The hole M5 step 2 named: `build_oracle(:swing)` / `(:classical)` now call
      core's own `_assert_frozen_flux`, so all three consumers of the frozen-flux
      assumption refuse detailed data and cannot drift apart.
- [x] `base_250_60` re-run at the new tier with the process-global bases
      deliberately poisoned first — a new tier is a new place for them to go stale.

### What this step found that the plan did not anticipate

**F1 — a spike can be vacuous in exactly the way a test can, and the first one
was.** S1's first form set `X_d = X′_d` (the degeneration), which makes the flux
equation's right-hand side identically zero — so `E′q` held for *every* `T′`, and
the spike would have "confirmed" `Inf` against a dead equation. Re-run with
`X_d = 1.8` the ladder is exact: drift 3.547e-9 at `T′ = 1e8`, 3.547e-7 at 1e6,
3.548e-5 at 1e4 — a clean `1/T′` law — while `Inf` gives 0.0. The fallback the
pre-study wrote (large-but-finite plus a convergence check) is not needed, and the
ladder became its own positive control instead.

**F2 — the argument that S2 was already answered was reading a different
component's source.** M4 ran `ClassicalMachine` with a negative mechanical input,
green, 82/82 — but `ClassicalMachine`'s `τ_m_set` carries **no bounds at all**.
`SauerPaiMachine` adds `bounds = (0, Inf)` to `vf_set`, `τ_m_set` and to the
variables `vf`, `τ_m` and `τ_e`, and `τ_e` is the one that would bite on a
generating machine's neighbour. Two components by the same authors, two different
declarations — the same shape as §2a's torque finding, one level down.

**F3 — the read-out had been silently choosing between two samples at an event
instant.** Writing "the returned times must equal the requested grid" as an
assertion immediately produced 252 stored rows against a 251-point grid: a
callback firing **at** a grid point makes the solver store that instant twice,
before and after the affect. The old read (`sol(t; idxs = …)`) took one of them
without saying which. `_sample_rows` now takes the **first** — the pre-event one,
which is the convention the GridSim playback driver already keeps. M4's 82/82 is
unchanged by the switch, so the two agreed; the point is that it is now a decision
rather than an accident.

**F4 — "frozen" is frozen to round-off, not to the bit, and ONE cause explains
three separate results.** `E′q`'s derivative is exactly zero and it still drifts by
one ulp (2.2e-16) on the ring; `X_ls` varied across a run moves every channel by
~1e-10; their two decoupled `ψ″` states seeded **×2** move things by ~6e-11. All
three are the implicit solver's linear algebra: a differential state with a zero
Jacobian row still sits in the Newton system, and the LU that solves it mixes the
other rows in at round-off. Taking the adaptive error norm out of it entirely
(fixed `dt`) tightens all three to ~1e-15 **without reaching zero**, so bit-identity
is not recoverable and `===` is simply not available for a decoupled state inside
an implicit solver. Our own side drifts by the identical 2.2e-16 — this is stiff
integration, not PowerDynamics.

**F5 — three parameters reach nothing at this degeneration, and one of them was
the planned positive control.** `X_ls` (theirs), `X_d` (both sides) and — found by
the control failing — `vf_set`. The field voltage enters only the flux derivative,
which `T′ = Inf` zeroes, so perturbing it by 1 % moves the trajectory by 8.9e-16.
The flat run's positive control was exactly that perturbation. Replaced by a 1 %
perturbation of the seeded `E′_q` (6.9e-3, four orders clear), with the inert one
kept as an assertion so the next reader does not have to take it on trust.

**F6 — the stator-`ω` residual is the first residual in this repo pinned by a
COEFFICIENT rather than by a ratio.** §2a predicted `(ω − 1)·V`: first order in
slip, coefficient of order one. Measured: `gap(V) / (peak slip × |V|)` = 0.996,
0.996, 0.995 at three disturbance sizes spanning a factor of four, and the gap
doubles when the disturbance doubles to within 0.1 %. D14 could only assert
proportionality (linear in loading over two decades); here the predicted number
itself is available, so the assertion is the number.

**F7 — the anti-vacuity mutation the plan asked for cannot go red, because a
different guard fires first.** A 1 % error in `_stator`'s `Iq` coefficient makes
the back-substituted state stop being a fixpoint of the network, and
`DetailedEngine`'s build-time residual throws (0.010 against a 1e-10 gate) before
any oracle runs. The two guards are in series, and which one fires is worth
knowing: a reader who credited the external check with catching that class of
error would be wrong about what the oracle covers.

**F8 — what CAN go red, and the channel it goes red on, is the step's most useful
measurement.** A 1 % `X′d` error on our side only is **invisible on voltage**
(1.6e-15, i.e. the honest gap), because the initialisation re-derives
`E′q = Vq + X′d·Id` from the power flow and buys a compensating internal voltage —
the terminal behaviour is unchanged. It is caught on the `E′q` channel by twelve
orders (1.6e-4 against 2.2e-16), and linearly in the error (20× at a 20 % error).
This is the measured justification for the plan's "assert per state, never on an
aggregate": here the channel that hides the error is not `f_coi`, it is `V`.

**F9 — the transient comparison's resolution is bounded by the residual it exists
to measure, and that is now asserted rather than caveated.** On the transient
voltage channel the stator-`ω` residual is ~2.8e-3, while a **twenty** per cent
`X′d` error moves our own trajectory by only ~4.8e-4. So with the flux frozen the
reactances are pinned by the FLAT run and by nothing else. Step 4 is what makes
`(X_d − X′_d)` live and gives them a transient check; the boundary is written as a
test so it stays true.

**F10 — the gitignored-manifest trap, third occurrence.** `reference/Manifest.toml`
predated step 1 adding `LinearAlgebra` to core, so the package would not load at
all. `Pkg.resolve()` fixed it with a one-line change and **no library version
moved**, so M4's numbers and step 3's sit on the same tree. One correction while
here: the earlier note that this manifest "pins PowerDynamics 5.0.0" is loose — the
pin is the compat bound in `reference/Project.toml`; the manifest is a local
resolve and is not in the repo.

## Step 4 — flux on: the equations step 2 could not see

**Done 2026-09-07. 2342 core / 172 UI / 421 reference** (82 M4 + 216 step 3 +
**123** step 4), all three green. Three oracles, and they turned out to have
three *different resolutions* on the same equations (F3).

- [x] **The other limit.** `T′do, T′qo → 0` reproduces the steady-state
      constant-`Efd` `(Xd, Xq)` machine. Written as a MODEL rather than as a limit
      (`flux_limit_model`: `X′d := Xd`, `X′q := Xq`, `T′ := Inf`), which shares the
      fast machine's power flow to the bit and needs nothing matched by hand. The
      gap falls **linearly in `T′`** — 1.35e-4, 4.15e-5, 1.39e-5 on the bus voltage
      at `λ` = 1e-3, 3e-4, 1e-4 — and the smallest is still 70× the two sides' own
      convergence spread, so it is a model residual and not solver noise. With
      step 2 this brackets the flux equation from both sides.
- [x] **The closed form.** Single machine, infinite bus through `Xe`, regulator
      off: `T′d = T′do·(X′d + Xe)/(Xd + Xe)`. **Exact**, not approximate — fitted
      against predicted to 3e-9 at `reltol` 1e-9 and 3e-6 at 1e-6 — and the reason
      it is exact is the fixture's design rather than a tolerance (F1). The GAIN
      is asserted too — `ΔE′q(t) = K₃·ΔEfd·(1 − e^{−t/τ})`, since a constant fitted
      from the *shape* and a gain read off the *endpoint* are different functions
      of the same two reactances — and the finite horizon went into the
      **prediction** rather than into the tolerance (F9).
- [x] **The anti-vacuity mutation lives here**, and it is a predicted move rather
      than merely a move: `Xd` 1.8 → 1.0 pu moves the predicted constant from
      2.8866 s to 4.3077 s, a ratio of 1.4923, and the measured ratio lands on it
      to 1e-3. Stated as the ratio, which cancels anything common to the two runs.
- [x] **External**: PowerDynamics with the flux on, same band machinery. The
      *change* from step 3 is the flux term by construction — and the sharpest
      form of that is the step-3 mirror (F6): on ONE fixture with `T′` as the only
      difference, a 1 % `Xd` error is **bit-identical** frozen and **12.7 bands**
      live.
- [x] Two tolerances on every numeric claim here.
- [x] Ledger rows: the flux equations move from `un-oracled` to `closed form` +
      `external` + `internal limit`, with each one's **resolution** recorded,
      because they differ by four orders (F3).

### What this step found that the plan did not anticipate

**F1 — the closed form's precondition is the LOADING, not the inertia, and the
obvious lever does not work at all.** The Heffron-Phillips law holds with the rotor
angle fixed, and the obvious way to hold it is a very large `H`. Measured across a
**64× range of inertia**, the fitted time constant's error does not fall: +21.8 %
at `H = 200` and +25.8 % at `H = 12800`. The reason is that the rotor's *new
equilibrium angle* after a field step is `ΔP/K_syn`, which contains no `H` at all —
a heavier rotor only reaches the same place more slowly, and over a fit window of a
few `τ` the contamination does not shrink. What DOES make the law exact is **zero
loading**: at `P0 = 0` the whole solution sits on the real axis, so `δ ≡ 0`,
`Iq ≡ 0`, `E′d ≡ 0`, therefore `Pe ≡ 0`, and the swing equation has nothing to
integrate. The rotor is not merely heavy, it is immobile, and the fit lands on the
prediction to 3e-9. Both halves are now tests: the exact one, and the boundary.

*And the first pass measured the wrong angle.* It read `|δ_G1 − δ_G1(0)|`, which
stayed at 2.8e-3 and looked like successful pinning, while the **infinite-bus
machine's own rotor** had moved 1.4e-2. An infinite bus made out of a machine has a
rotor; the quantity in the law is the relative angle. The 21 % error is
quantitatively what that excursion predicts.

**F2 — the `T′ → 0` limit identifies `Xd` and is BLIND to `X′d`, and both halves
are measurements.** `Xd` enters the fast model only through the flux numerator
`(Xd − X′d)·Id`, which the limit model's `T′ = Inf` divides away — so a wrong `Xd`
on the fast side alone is an error the reference is *structurally* immune to, and
its signature is the right one: the ladder **stops converging** (gap ratio 0.84 per
rung instead of 0.34) and lands 5.7× above the true one. `X′d` is the opposite: it
cancels out of the limit entirely and only sets the *rate* of approach, so a **10 %**
`X′d` error — ten times the size of the `Xd` mutation — moves the comparison by
1.4 % where `Xd` moves it by a third. `X′d` is pinned by step 2's frozen limit and
by the flat run; it is not pinned here, and the test says so with a number.

**F3 — three oracles, three resolutions, and the external one is the coarsest.**
This was not anticipated and it changes how the ledger reads:

| oracle | resolves a wrong `T′do` / `(Xd − X′d)` at | limited by |
|:---|:---|:---|
| closed form (`test/`) | **1e-4** asserted; the fit itself agrees to 3e-9 | the fit, at two tolerances |
| `T′ → 0` limit (`test/`) | ~1 % on `Xd` | the linear-in-`T′` residual it measures |
| PowerDynamics (`reference/`) | ~10 % | **the stator-`ω` residual, not solver noise** |

The external check's honest `E′q` gap is 1.56e-5, which is 304 bands — it is not
noise, it is the step-3 residual arriving on the flux channel through `Id`. A 1 %
`Xd` error only doubles it. So the newest and most impressive-looking oracle is the
least sharp of the three on these equations, and the closed form — the oldest and
cheapest technique in the repo — is four orders better.

**F4 — the d-axis and q-axis flux errors are separated BY CHANNEL, and neither is
visible on voltage or on frequency.** Measured, three mutations on our side only,
against the honest gap:

| mutation | `V_B1` | `E′q_G1` | `E′d_G1` | `f_coi` |
|:---|---:|---:|---:|---:|
| `T′do × 1.10` | ×0.9 | **×14.8** | ×2.8 | ×1.0 |
| `Xd × 0.90` | ×0.9 | **×27.0** | ×4.6 | ×1.0 |
| `T′qo × 1.10` | ×1.0 | ×1.9 | **×13.6** | ×1.0 |

So a per-state comparison does not merely catch more here — it says *which
equation* is wrong. And the terminal voltage sees none of them, because the
stator-`ω` residual on that channel (2.0e-3) is a hundred times anything a flux
error does to it. This is the third distinct shape of "assert per state, never on
an aggregate": M4's hidden channel was `f_coi`, step 3's was `V`, and step 4 has
both at once.

**F5 — the flat run's new content is a DIFFERENT vacuity from step 1's, and the
two must not be merged.** Step 1 recorded that `Pm := Pe` versus `Pm := P0` is
unobservable without a load. This one is the flux half of the fixpoint: on every
frozen-flux fixture `E′d = (Xq − X′q)·Iq` reads `0 = 0`, so the initialisation
could write anything into `E′d` and a flat run would still be flat.
`detailed_pair()` is the first fixture in the repo where it is a real condition
(`E′d = 0.184`), and the d-axis condition is asserted beside it even though it holds
by construction — a definition living in exactly one place is what makes a later
second definition invisible.

**F6 — the mirror of step 3's disclaimer, closed on one fixture.** Step 3 asserted
`all(t9 .=== tb)` for a ×4 `Xd` and closed the testset with "step 4 is what makes
`(X_d − X′_d)` live". Step 4 re-makes that assertion at ×0.99 on `detailed_pair()`
and then re-runs it with `T′` finite: bit-identical becomes 12.7 bands, with the
flux time constants as the only difference between the two runs. **And the channel
that hides it is `f_coi`** — 0.01 bands, a hundredth of the band — which is asserted
rather than discovered later.

**F7 — `X_ls` and the `ψ″` seeding survive the flux being switched on, and that had
to be measured rather than argued.** `γ_d2` multiplies `ψ″_d` *inside* the `E′q`
equation, and step 3 ran that equation with a zero derivative in front of it — so
"the sub-transient states drive nothing" was established in the one configuration
where the equation that would couple them was dead. Re-run with the flux live:
`X_ls` at 0.1 and 0.9 of its range moves every channel by 1.2e-10 against a 2.2e-6
band, and their two `ψ″` states seeded ×2 and shifted still move nothing above it.

**F9 — the endpoint check failed, and the fix was to sharpen it rather than to
loosen it.** Comparing `ΔE′q` at the end of a 25 s run against the `t = ∞`
asymptote is short by `e^{−25/τ} = 1.73e-4` — and that is exactly what the suite
reported, twice, at an `rtol` of 1e-4. Widening the tolerance past it would have
worked and would have thrown away the one place the exponential's SHAPE reaches
the endpoint assertion. Carrying the `(1 − e^{−t/τ})` factor in the prediction
instead tightens the agreement to **3e-7** and makes the check a statement about
the whole first-order response rather than about its limit.

**F8 — a helper defined inside a `@testset` is invisible to its sibling**, which is
M5 step 0b's scope lesson in a second file. `both_detailed`, `gap`, `peak_slip` and
`chan` lived inside the step-3 testset; step 4 needs the same four, and a `@testset`
block is a scope. They were **hoisted, not copied** — the alternative is two copies
of the one helper that decides what "the same scenario on both sides" means.
`detailed_pair()` went further and moved into `GridSim` itself, beside
`two_machine_system`, because the core suite needs the same fixture now.

## Step 5 — the voltage regulator

- [x] Static exciter, one lag, hard limits (`m5-prestudy.md` §2). `Efd` is a STATE
      unconditionally — a vertex model's state count is fixed at compile time, so
      "a parameter when off, a state when on" was never available — and `T_E = Inf`
      is the regulator-off default by the same `finite/Inf` arithmetic the flux uses.
- [x] **Limits are saturations in the derivative**, never a clamp on the state.
- [x] **`Vref` is DERIVED at initialisation**, not model data. Not on the plan's
      list; it is the `Pm`-from-the-power-flow rule one mechanism along, and
      without it the flat run is a startup transient.
- [ ] ~~`isoutofdomain` gains two indices per machine~~ — **written, measured to
      make the ceiling UNREACHABLE, and removed.** See "what this step found".
- [x] Closed form for the ceiling: it holds under sustained demand and **releases
      unaided** when demand falls, at a time the same closed form predicts to the
      sampling grid; and a second disturbance after saturation does not freeze the
      integrator, checked with a prediction rather than only a retcode.
- [x] External comparison for the **unlimited** exciter only
      (`build_oracle(tier = :sauer_pai_avr)`), on `infinite_bus_system` rather than
      the three-path fixture — `_assert_sauer_pai_tier` refuses a machine-free bus.
      The limited exciter is **refused by name**, with the reason in the message.
- [x] Anti-vacuity: clamp the state instead of saturating the derivative, RUN, and
      report which checks survive it. Three of four do, and one is *more* green
      under the bug.

### What this step found that the plan did not anticipate

**F1 — the `isoutofdomain` guard makes a saturating limit UNREACHABLE.** The plan
asked for two more indices per machine, by analogy with `ΔPm`. Written, the guard
kills the run: it accepts a step only if the state lands at or below
`limit + 1e-10`, and a state approaching from below with a finite derivative needs
an ever-smaller step to land inside that window. Measured — MaxIters at `dt` =
9.1e-11 / 1.7e-9 / 1.5e-8 across three exciter settings, and 199,944 accepted steps
on a raw solve that never reaches the limit. With the guard off the run succeeds and
the state exceeds its ceiling by **3.4e-8, once**. `engines/swing.jl` says in prose
that this cannot happen ("the derivative is already zero at the ceiling, which puts
the solution *at* headroom"); the derivative is zero there, and it does not follow
that the solution arrives.

**F2 — and the engines that still carry that guard are NOT stalling, for a reason
nobody chose.** A `SwingEngine` governor driven onto its headroom for 20,000 s
lands 3.1e-11 pu ABOVE its ceiling — inside the guard's absolute `1e-10` window with
3× to spare. The window a state needs scales with how fast it is: a 1 s governor lag
needs 3e-11, a 0.05 s exciter lag needs 5e-8. Left alone deliberately; changing the
constant would move M2, M3 and M4 numbers.

**F3 — the open-loop reading of a setpoint error is wrong by 11×.** The positive
control was written as "`Vref` off by `Δ` moves the field by `K_A·Δ`" and measured
0.180 pu against that 2.0. The loop closes through the network: the DC loop gain is
`G = K_A·Xe/(Xe + Xd) = 10.11` and the answer is `K_A·Δ/(1 + G)`, which lands to nine
digits. It became the only check in the milestone that reads `K_A` inside an equation.

**F4 — the headline ceiling check reads RED OR GREEN depending on WHERE IT LOOKS.**
The clamp mutation was written expecting "three of four claims stay green, and one is
*better* under the bug (exactly 0 excess against the correct engine's 5e-8)". Run, it
is sharper than that, and the prediction was half wrong. Sampled at the clamp
instants the broken state is exactly at its cap — 0.0 excess, at every step size
tried. Sampled anywhere else it is **0.378 pu above the cap** at `h` = 0.005, seven
million times the correct engine's excursion. One run, one state variable, two
maxima. A post-hoc clamp makes the answer a property of the recorder; a saturation in
the derivative has no such freedom, and that is the cleanest statement of *why* M1's
carried-forward rule is a rule. The closed form still goes red on its own.

**F4b — a settled observable cannot carry a rate.** The step-size signature was first
written on the endpoint flux and failed: halving `h` moved it by 0.78, not 0.5. The
h-scan says why — by 24 s the voltage loop has closed around the clamped run and it
has found an equilibrium of its own, so the endpoint is partly saturated. The
**excess field** is clean-linear in `h` over a 40× range (1.2128, 0.7089, 0.3777,
0.1942, 0.0789, 0.0396 for `h` = 0.02 … 0.0005; the endpoint flux over the same scan:
0.0140, 0.0128, 0.0110, 0.0086, 0.0052, 0.0031). The check was wrong, not the engine
— the second time in this step (see F3) that an open-loop intuition set a threshold
the closed loop does not obey.

**F5 — a hard saturation is a discontinuous RHS, and Rodas5P fails on one isolated
point.** Swept over eight ceilings, seven complete; `Efd_max = 1.2` does not — and it
is isolated in the TOLERANCE too, completing at reltol 1e-6 and 1e-11 and failing
only at the 1e-9 between. `FBDF` completes it. Documented rather than fixed, since
`init!` already takes a `solver`.

**F6 — the external oracle cannot use this step's own fixture.**
`_assert_sauer_pai_tier` refuses a machine-free bus, and `regulator_bus_system`'s
bare junctions are exactly that. The comparison moved to `infinite_bus_system`, which
is two buses — so a line trip would island the machine and the disturbance became a
**setpoint step**, a parameter on both sides. That turned out to be a gift: at zero
loading `ω ≡ 1` exactly, so the stator-`ω` residual that held step 4's oracle to ~10 %
vanishes identically and the exciter is the only difference left.

**F7 — the sample at an event instant is the PRE-event one**, on this engine as on
every other in the repo. Three checks read `findfirst(≥ t_event)` and got the old
network's voltage; the fix was `findfirst(>)`, and the check they became is stronger
— the algebraic relation `|V| = (E′q·Xe + X′d·E_inf)/(Xe + X′d)` is asserted at every
post-trip sample rather than at the jump alone.

## Step 6 — voltage-dependent load

**DONE, 2026-09-07.** 2696 core / 281 UI / 986 reference, all green (+193 core,
+417 reference). Commit: the ZIP load and its oracle.

- [x] ZIP at the bus (`m5-prestudy.md` §6); constant-impedance the default,
      because it has the closed form (it folds into the admittance) and is what
      `ZIPLoad` configures down to. **The whole thing collapsed to one voltage-
      dependent scalar on the admittance that was already there** —
      `I = (G + jB)·V·k(|V|)` with `k = a_z + a_i/|V| + a_p/|V|²` — so the change to
      the right-hand side is four lines and the rest of the step is checks.
- [x] Wired on BOTH paths: the dynamic vertex models and the power-flow ones, which
      are different vertex models calling the same function. The flat run is the
      only check that can see one of them missing, and it is the check this step
      leans on.
- [x] Closed form for the constant-impedance case, checked against the fixpoint —
      and **two more it did not ask for**: constant current (`P₀|V|`) and constant
      power (`P₀`, with no voltage in it at all, matched to 8.9e-16).
- [x] **The three-way ORDERING, which needs no tolerance at all**: at the solved
      `|V| = 0.975…0.979` the drawn powers are `1.054270 < 1.074905 < 1.100000` pu.
      A build that ignored the two new shares would make all three identical.
- [x] Frequency-dependent load stays on the machine until something measures the
      difference — recorded in `Load`'s docstring and in `m5-prestudy.md` §6, not
      silently omitted.
- [x] External: `ZIPLoad` configured to match, **after reading their source** (F3
      below). The two rejections `_assert_sauer_pai_tier` carried — no loads, no
      machine-free buses — are both lifted; a bare junction is `MTKBus()`.
- [x] A closed form with TWO roots (the P-V nose), which was not on this list and is
      the best thing in the step — see F2.
- [x] Both anti-vacuity mutations RUN, and one of them turned out to be the same run
      as a control already in the file (F4).

### What running step 6 found

**F1 — there is no guard at `|V| → 0`, and that is a decision rather than an
oversight (`m5-context.md` D23).** With `a_p > 0` the drawn current diverges as the
voltage collapses, because a load that draws constant power from a dead bus is a
model with no solution. A low-voltage cut-over to constant impedance is what
production load models do and it is a threshold nobody here has chosen; step 7's
collapse runs are what would earn one. Two things support leaving it bare: D20 already
measured that a step-rejecting domain guard does not compose with this engine's
construction, and **PowerDynamics made the same call** — their `ConstantCurrentLoad`
carries an explicit `ε` regularisation and their `ZIPLoad`, the component we are
checked against, carries none.

**F2 — the constant-power load has a closed form with TWO roots, and it gives the
step a DERIVED limit.** A machine-free load bus fed from one machine through a
reactance is the textbook P-V nose: with `u = |V|²`,
`u² + u(2QX − E²) + (PX)² + (QX)² = 0`. Two voltages serve the same load, both are
honest roots of the residual the solver drives to zero (0.9718 and 0.1952 pu on the
fixture), and the discriminant vanishing gives `P_max = E·√(E² − 4QX)/(2X)`.
Measured: `P_max` = 1.62524 pu; at 1.62 pu the roots are still distinct and the solve
returns an answer, at 1.63 pu there is nothing to find and the fixpoint solver says
so. **A limit derived on paper predicts, to better than half a percent, where
somebody else's Newton stops converging** — and it also separates two refusals that
look alike: at 1.30 pu the high root exists (0.885364, matched to six digits) and it
is the `|V| ∈ [0.9, 1.1]` band, not the nose, that rejects the case.

**F3 — reading their source first settled four conventions, and one of them is a
restriction on OUR side.** (1) Their `Pset` is an INJECTION — `guess = -1`, and their
`ConstantYLoad` writes `iload = −Y·u` — so a drawing load is negative and the builder
negates. (2) `Vset = 1` makes their `Vrel` our `|V|`, so the shares normalise where
ours do and the comparison is not measuring the normalisation. (3) `ZIPLoad` carries
no state, so nothing new is seeded and the band is not one lag richer the way
`AVRTypeI`'s is. (4) **They give `P` and `Q` SEPARATE share triples and we give them
one**, so a `ZIPLoad` whose two triples differ is a model we cannot express. Recorded
now rather than discovered as a disagreement later — the M4 step 4 rule, applied.

**F4 — the obvious anti-vacuity mutation is numerically the SAME RUN as a control
already in the file, and only running it showed that.** "The dynamic path drops the
shares the power flow honoured" gives +0.157 Hz and ~6.6 rad — identical, to three
digits, to step 1's `Pm`-from-the-schedule control. Not a coincidence: both are the
same 0.046 pu imbalance between what the machines inject and what the load draws, and
the trajectory cannot see which side of that equality is wrong. **A mutation's
magnitude is not its identity.** The control that does discriminate is the mirror one
— the power flow solves a constant-impedance load and the dynamic path draws constant
power — which is the same 0.046 pu the other way and lands at **−0.15616 Hz**. The
sign is the finding, and it is what is asserted.

**F5 — a settled system's frequency cannot carry a difference of EQUILIBRIA, and the
oracle's load check must therefore name a position channel.** Building our side on a
constant-impedance load and theirs on a constant-power one puts the two sides at
different equilibria — 8.1e-3 on a rotor angle, 4.0e-3 on the load bus voltage,
against the 1e-13 the honest comparison agrees to. But **both runs are still perfectly
flat**, so every rate-like channel is at round-off: `f_coi` reads 1.4e-14, exactly
what it reads unmutated, and so do `ω`, `E′q`, `E′d` and `Efd`. A load model wrong by
4 % in drawn power reads GREEN on the channel that is the default everywhere else in
that file. This is step 5's F4b turned around — there, a settled observable could not
carry a rate. Nor can every position channel: `δ_G1` is the SLACK, pinned at zero on
both sides, and cannot carry it either (7.8e-14).

**F6 — the transient gap is step 3's residual and the load adds none, shown by
scaling rather than assumed.** On a run with real slip the two sides differ, and a
magnitude bound could never separate the known stator-`ω` residual from a load-model
error hiding inside it. So `gap / (slip × |V|)` was measured at four ZIP splits and
three disturbance sizes: it holds to **three digits over a fourfold change in
disturbance** at every split (Z 0.962, I 1.077, P 1.232, mix 1.121) and is of order
one throughout. A load-model error would put a slip-independent offset into the gap
and the ratio would fall as the disturbance grew. It does not.

**F7 — the gitignored-manifest trap, for the third time in this repo.** The
`reference/` environment could not load GridSim at all: `TOML` became a dependency
when the scenario editor landed two days ago, and `reference/Manifest.toml` — which is
gitignored, like every manifest here — still described the old dependency set.
`Pkg.resolve()` fixes it and reports "no packages added or removed", because a
dev-dependency's dep LIST changing is not a package change. Nothing in git ever looked
wrong. Previous occurrences: `m4-context.md` D15, and the 2026-08-18 stale dev
manifest found in M4 step 5.

**F8 — the refusal step 5's F6 worked around is gone.** `_assert_sauer_pai_tier`
refused a machine-free bus, which is why step 5's external comparison had to move off
`regulator_bus_system` to `infinite_bus_system`. That refusal is lifted here. Step 5's
F6 is left as written — it is a dated record of why that step did what it did — but
the workaround it describes is no longer necessary.

## Step 7 — the criterion (the milestone's purpose)

- [x] Locate the classical tier's slip boundary on the two-area case — **scan the
      boundary, do not bisect it** (M3 step 6's rule), rebuilding per cell rather
      than mutating a live coupling (the fixpoint depends on it). Unchanged from
      M3: `slip_boundary()` is reused as it stands, and the boundary at the derived
      cascade is **5,500 MW**.
- [x] At that same tie strength, run the detailed tier and measure both: does it
      lose synchronism, and does the export swing peak **exceed** the classical
      tier's `P_max`? **Yes and yes** — it slips, and the peak export is
      **1.0295 × P_max** (5,662.4 against 5,500 MW) at `reltol = 1e-5`, 1.0317 at
      `1e-3`. The classical tier's own peak in the same run is `P_max` exactly, to
      four decimals: the bound is attained, not merely respected.
- [x] **The anti-vacuity control is specific and must be run**: freeze the
      voltages (step 2's degeneration) and the criterion must **fail**. It does —
      **0.9614 × P_max**, and it fails against a **derived** prediction rather than
      a tolerance (F4). It is not "the classical tier", and F4 says why that makes
      it sharper rather than weaker.
- [x] Positive control: the criterion's two halves are checked separately, so a
      run that slips but does not swing (or the reverse) is distinguishable from a
      pass. The frozen control **is** the first of those — it slips and does not
      exceed — so the distinction is exercised rather than only asserted.
- [x] M3's protection wired at this tier and **re-validated**, not assumed to
      carry: the shed ladder, the out-of-step tie relay and the generation ramp,
      each against the M3 closed form that still applies (D8). All three go through
      `engines/swing.jl`'s own binders rather than copies, so every guard is the
      shipped guard with the shipped message. Measured: the ramp's settled speed
      `ω_ss = ΔP/(Σ1/R + ΣD)` to **9.5e-11** relative; the ladder root-found inside
      its one-`dt` bracket and off the grid, stepping its machine's `Pm` by exactly
      the block, with the settled speed landing on the closed form **that includes
      the block** (2.2e-9); the relay firing with `|δ|` at the reported instant
      equal to its threshold to **1e-10**, opening the branch through the engine's
      own `inject!(::TripLine)` and surviving the re-initialisation. **One piece
      does NOT carry and is refused by name** — see F7.
- [x] `inject!`'s consistent re-initialisation (D8) exercised: **the flat run
      across an event**, on a system whose post-trip equilibrium is known.
      `quiet_ring()` — every machine at zero injection with the same internal
      voltage, so every branch carries exactly zero current and removing one
      changes nothing — comes through a line trip with a **departure of exactly
      0.0** on every channel. Paired with a loaded-ring positive control (0.286 rad
      on `δ_G2`), because the quiet fixture alone cannot discriminate (F8).
- [x] Every number lands in `entsoe-iberia-reproduction.md` under §7.3's
      discipline — `[GUESS]` inputs marked, and a tuned parameter is not a result.
      New §7.7. Every detailed machine parameter is a [CHOICE] on an aggregated
      area and every one is **swept**: 14 of 14 cells satisfy both halves, over a
      3× range of `T′do`, 47 % of `Xd`, 8× of `K_A` and 3.2× of the field ceiling.
      **The prose was written after the table**, and it had to be: two paragraphs
      drafted from the reasoning were wrong (F3, F5).

### What this step found that the plan did not anticipate

**F1 — "one model, two tiers" is not available, and the reason is a guard M5
itself added.** The plan's construction was to hand ONE `NetworkModel` to both
engines, on the grounds that `SwingEngine` reads none of the detailed fields. It
does not read them — and it **refuses** them, by name, in `_assert_frozen_flux`
(step 2) and `_assert_no_regulator` (step 5), because a classical engine handed a
real `Xd` would run a machine its own data does not describe, silently. So the
comparison is between two models, and the claim that replaces it is stronger
because it can be checked field by field: the two agree **bit for bit** in every
quantity the classical tier reads (`bus`, `H`, `D`, `X′d`, `E′`, `Pm`, `1/R`,
`headroom`, `Tg`, `Ra`, and the branch `X` and `K`) and differ in exactly the set
that tier refuses. The difference between the two runs **is** the tier boundary.

**F2 — the quantity the criterion measures is not in the state read-out at all,
and the obvious fix was refused.** `current_state`/`state_series` carry bus
voltage MAGNITUDES; the tie transfer needs the angles. The obvious answer is a
`P_<branch>` channel next to `V_<bus>` — and `reference/`'s external oracle
asserts `keys(o) == keys(t)` at four comparison sites, so a channel added here is
a channel PowerDynamics must grow too, with bands of its own. Step 7 would then
depend on an oracle change it has no business making. So the transfer is
**derived** from the integrator's own saved samples (`branch_power_series`), read
the way `_playback!` itself reads them and never through the interpolant — which
the playback driver's own comment measures as wrong across a step a callback
ended. `branch_power` gives ONE name to `K·sin(δ_from − δ_to)` and
`Re(V·conj(I))`, so the two tiers' transfer has one implementation rather than two
call sites with a sign and an orientation each.

**F3 — letting the flux move ALONE moves the answer the wrong way, and the first
draft of the prose said the opposite.** The expectation was that voltage dynamics
are what beat the constant-voltage ceiling. Measured: with the flux live and no
regulator the peak export is **0.886** of `P_max` against **0.961** with it
frozen, and the bus voltage falls to **0.809** as the demagnetising current pulls
`E′q` down. A voltage that can fall is a mechanism for falling **short** of the
ceiling. What exceeds it is the REGULATOR — which can only act through the flux
equation, so the two mechanisms are not separable even though one of them on its
own points the wrong way. This is why the table has three detailed rows and not
two: with only "frozen" and "flux + AVR" the finding is invisible.

**F4 — the anti-vacuity control has a DERIVED prediction, and the first number
disagreed with it until the tolerance moved.** At the frozen-flux degeneration
`X′d = X′q`, so each machine is a constant source behind one reactance and the
transfer is bounded by `|E′₁||E′₂| / (X_tie + X′d₁ + X′d₂)` — a formula, not a
measurement. The first run came out **0.03 % above** it, which is the kind of small
excess that gets rationalised. It was solver error: at `reltol = 1e-5` the ratio is
0.999999 and at `1e-7` it is 1.000000. Two consequences. The control's failure is
quantitative rather than merely negative — it fails by hitting a bound that is
**strictly tighter than `P_max`**, because the classical tier puts `E′` at the bus
and this one puts it behind `X′d`. And so the control is **not "the classical
tier"**; it is the classical MECHANISM inside the detailed engine, which is the
comparison the tier boundary in F1 actually allows.

**F5 — `abstol`, not `reltol`, decides whether these runs complete, and it does so
at ISOLATED points.** Swept on the flux-only cell at `reltol = 1e-5`:

    1e-5  ok (2,050 steps)   1e-6  ok (2,870)   1e-7  FAILS (step size collapses
    1e-8  ok (3,400)         1e-9  ok (15,049)  1e-10 ok (3,491)   at t = 12.92 s)

with every completing cell agreeing to **2 parts in 10,000**. So the failure is
conditioning at a kink and not a boundary of the model — M5 step 5's finding
arriving on a second case, where it was isolated in both the ceiling and the
tolerance. The governor headroom is a hard saturation and is live even in the
cells with no regulator, so this is not the exciter's doing alone. Two things
came out of it: `init!` now exposes the **integrator's own `maxiters`** (library
default 1e5, and a 20 s pole slip does not fit inside it at any tolerance worth
quoting — this is a different counter from `solve!`'s playback cap and is reached
first), and a sweep cell that does not complete is **retried once at a looser
`abstol` and MARKED**, rather than dropped or silently re-tolerated.

**F6 — the field voltage overshoots its own stated ceiling by ~2 %**, 5.18 pu at
`reltol = 1e-3` and 5.11 at `1e-5` against 5.0. This is step 5's measurement, on a
state fast enough to make it visible: the derivative saturation zeroes the
derivative *at* the limit, so the only excursion possible is the single step that
crosses, and its size is set by how fast the state is. It shrinks with the
tolerance. It is also why the `Efd_max` axis is swept rather than fixed — at
`Efd_max = 2.5`, half the centre value, the criterion still holds at 1.0164, which
is what rules out the overshoot as the thing carrying the result.

**F7 — the one piece of M3's protection that does NOT carry, refused rather than
documented.** A shed ladder steps its machine's `Pm`. At the classical tier `Pm`
is a NET injection, so disconnecting load raises it by exactly the block; at this
tier `Pm` is MECHANICAL power and the load is a separate element with its own
voltage dependence. On a model carrying a `Load` the same operation would add
generation instead of removing load, and the two differ by exactly the mechanism
step 6 built. Documenting that is too weak — it is refused by name, on a model
with a `Load`, with the step that lifts it named in the message. On the models
where the load is folded into a machine's net injection (the two areas, and every
M2/M3 fixture) the convention carries unchanged, and the test asserts both halves.

**F8 — the flat run across an event needs a fixture whose post-trip equilibrium is
its pre-trip one, and even then it cannot discriminate on its own.** `quiet_ring()`
puts every machine at zero injection with the same internal voltage, so every bus
sits at the same complex voltage, every branch carries exactly zero current, and
removing one changes nothing at all — the departure across a line trip is
**exactly 0.0** on every channel, `==` and not a tolerance. But a re-initialisation
that did nothing would also come out flat there: the re-solve starts at the answer
and lands on it. So the check ships in two halves and the test says which carries
what — the quiet fixture proves no artefact is **injected**, and the loaded-ring
positive control (0.286 rad on `δ_G2` through the same trip) proves the event is
reaching the system at all.

## Step 8 — the voltage-visible window (D12, first to be cut — NOT cut, delivered)

- [x] Playback overlay on M4's scrubbable window: bus voltage magnitude alongside
      frequency, classical against detailed. `ui/src/voltage_window.jl`, the
      fourth window — a separate builder rather than a mode on M4's, because that
      file's header is eighty lines arguing why ITS pair can show one lesson of
      three, and this pair shows a second one.
- [x] `smoke_render` offscreen **first**, then the live window. Render before
      claiming. Four offscreen passes; the first two changed the design (see
      below), and the live window was then opened, dragged and closed.
- [x] A `Label` with the right text that was never added to the figure passes
      every text assertion anyone can write about it — assert it is *in* the
      figure (M4 step 3). Six labels asserted in the layout, with a control that
      proves the helper can say no. **It caught one**: the "frequency channel
      only" qualifier lived in a `section_label!` heading nobody held, so no check
      could reach it; it moved into the block it qualifies.
- [x] The M4 promise it discharges is named in the window's own docstring, so the
      commitment and the delivery are in one place — quoted verbatim, in the file
      header and in `voltage_playback`'s docstring, along with the half that is
      NOT discharged.
- [x] If cut (D11): the inherited promise is **restated in the follow-on batch**,
      not quietly dropped. Not cut.

### What the renders changed, in order

1. **The pre-event offset is bigger than the disturbance.** The two runs start
   0.135 pu apart and the ramp moves the voltage 0.096 — so the largest number on
   the voltage panel is `Machine.E′` serving two denominations at `t = 0`, not a
   result. This is M4's "0.857 Hz that is not the lesson" in voltage form, met a
   second time. It is drawn, named on the caption, and separated from the movement
   in the read-out; and the frozen-flux control, where it collapses tenfold, is
   what says it is denomination rather than a broken comparison.
2. **A generation ramp was the wrong disturbance, twice over.** `DetailedEngine`
   refuses `TripGenerator` by name and a line trip moves this ring by 1.5 mHz, so
   a ramp was forced. But a ramp on a GENERATOR unloads it and the voltage RISES
   toward the classical constants — which reads as the tiers converging. The
   shipped ramp adds LOAD, and the voltage sags. The rejected run is kept as the
   control that the direction claim is not vacuous.
3. **Twenty seconds was too short** (`T′do = 8 s`, so the flux was still moving at
   the right-hand edge and "largest movement" was just the last sample), and the
   read-out column overflowed into the caption.

### The mutation, and what it found

Running the bus→machine mutation — the check the whole mapping testset existed for
— showed the transposition is **unreachable**: `NetworkModel` stores machines
sorted by bus, and the classical tier refuses a bus without exactly one machine, so
machine index equals vertex index and the positional form returns the identical
vector. **The test's own premise was wrong**, and the fixture built to be "out of
order" comes back in order from the constructor. The testset now asserts the
invariant that makes the two equivalent, and says the lookup is kept because that
equivalence is a property of two *other* invariants rather than of this code.

## Housekeeping owed by this milestone

- [x] `docs/SPEC.md` §7.6's third lesson (IBR behaviour) still has no tier —
      stated as un-scheduled rather than implied by M5's voltage work. §7.6 now
      lists all three lessons with which window draws which, and IBR as owed and
      unplanned.
- [x] `docs/validation-ledger.md` gains a detailed-tier section, every row
      labelled, `un-oracled` rows stated out loud. Step 8's own section added; the
      passive bus is the `un-oracled — out of reach` row.
- [x] `docs/plans/README.md` M5 row updated as steps land.
- [x] Re-resolve all three environments from deleted manifests at the end, as M4
      step 5 did — the gitignored-manifest trap has now caught this repo twice
      (`m4-context.md` D15, and the 2026-08-18 stale dev manifest). Done: all three
      manifests deleted and re-resolved, giving **NetworkDynamics 1.3.0, GLMakie
      0.13.14** (up from 0.13.13, on which the standing export-collision check was
      last measured — re-run, still empty) and **PowerDynamics 5.0.0**. All three
      suites then re-run ON the fresh manifests: **2835 core / 382 UI / 986
      reference**. The reference count in particular is MEASURED here and not
      carried over — quoting it from the old manifest, in the commit that replaced
      that manifest, is exactly M4 step 5's "same counts, but nobody knew".
- [x] `Pkg.add` rewrites `Project.toml` and drops every comment — `git diff` after
      any dependency change and put them back. No dependency changed in step 8.
