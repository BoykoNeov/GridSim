# M5 — Tasks

The checklist. Companion to `m5-plan.md` (the how) and `m5-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate** — which in M2, M3 and M4 was every round's most
valuable line.

Status: **steps 0b, 1 and 2 done, steps 3-8 open.** Entered at `86651ab` with
**1873 core / 172 UI / 82 reference**; the suite split left the core count
unchanged, step 1 brought it to **2083 core**, and step 2 to
**2251 core / 172 UI / 82 reference**. The detailed tier now carries the two-axis
machine, reproduces `SwingEngine` at the frozen-flux degeneration, and initialises
from a power flow whose machine model is the steady state of that machine.

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

**7. Two tooling traps, both of which hid a real failure for a while.**
`reference/test/runtests.jl` had four `ma.Xd` sites the rename missed, because the
first sweep grepped `reference/src` and not `reference/test` — found only by running
the third suite, which is the standing rule and not bookkeeping. And a background
command written as `cmd > log 2>&1; echo "EXIT=$?"` reports the **echo's** status,
so a suite with four errors was reported to the session as exit 0. That is M4's
`| tail` trap in a new shape: anything appended after the command becomes the status
that is read.

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
