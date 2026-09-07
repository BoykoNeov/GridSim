# M6 context — decisions, and what the steps actually measured

Companion to `m6-plan.md` (the how) and `m6-tasks.md` (the checklist). This file
is where a decision is argued once, with the measurement behind it, so nobody
re-litigates it from the code. Read it before disagreeing with the plan.

Convention carried from M2–M5: decisions are `D<n>`, numbered in the order they
were *taken*, not the order the steps run. A section headed "What step N measured"
is added underneath a decision when a step either confirms it or — as happened
four times in M5 — confirms the decision while destroying its stated reason.

---

## D0 — Why this milestone, when the repo's own selection criterion had run out

`docs/plans/README.md` carries a list, "The scientific hurdles, in dependency
order", and says explicitly that a milestone is chosen against *that* list rather
than against `SPEC.md` §9's numbering. At M5's close **all six hurdles were
resolved** — 1 and 2 in M4, 3 through 6 in M5. So the criterion was empty, and M6
was chosen against the roadmap numbering by default, which is the thing that file
warns against.

That is recorded rather than hidden, and the debt is paid in this milestone: M6
**names three new hurdles** (7, 8, 9 below and in the README), of which one is
already closed by its own step-0 measurement. A milestone that adds no hurdle
leaves the next one to be chosen the same way this one was.

- **Hurdle 7 — A solve whose convergence is not its own validation.** See D6. The
  repo already holds the evidence that residual and correctness are uncorrelated
  here.
- **Hurdle 8 — Two sources of one steady state that must agree, with neither
  defined as correct.** See D5. The `find_fixpoint` initialisation and the power
  flow both claim to say where the grid sits; making them agree is a real check,
  and declaring either one the reference by fiat destroys it.
- **Hurdle 9 — Adopting an external data model without inheriting its dependency
  floor.** Raised by M4's PSID failure and **closed by measurement in step 0**, in
  D1 below.

---

## D1 — `NetworkModel` stays canonical; `PowerSystems`/`PowerFlows` is the second
oracle, in `reference/`

`SPEC.md` §9 item 5 reads: *"Steady-state ladder: DC power flow → AC power flow
(Newton) → AC-OPF (adopt `PowerFlows.jl`; introduce `PowerSystems.jl` as canonical
model here)."*

**The second half of that parenthesis is refused. The first half is kept**, one
layer out from where the line put it.

### The measurement that makes the refusal informed (step 0, 2026-09-07)

M4's PSID attempt failed on a dependency floor, so the first question was whether
this one even *could* be adopted. Measured in a throwaway environment under
`W:\temp\claude\gridsim-m6-resolve\`, on Julia 1.12.6:

| probe | result |
|---|---|
| `PowerSystems` + `PowerFlows` alone | resolves — **150 packages**, v5.12.3 / v0.25.2 |
| the same, added on top of our exact stack (184 packages) | **resolves — 258 packages, +74** |
| `SciMLBase` / `OrdinaryDiffEq` / `NetworkDynamics` after adoption | **unchanged** — 3.53.1 / 7.8.1 / 1.3.0 |
| anything of ours forced to move | no; three minor transitive packages nudged (`NonlinearSolveBase` 2.49.4→2.48.0, `OrderedCollections` 2.0.1→1.8.2, `TimerOutputs` 1.2.1→0.5.29) |
| usable, not merely resolvable | **yes** — a two-bus case built and solved by both `ACPowerFlow()` and `DCPowerFlow()`, returning bus voltages, branch flows, losses and angle differences |

So **hurdle 9 is closed, and closed in the direction that removes the excuse**:
this adoption is not blocked the way PSID was. The refusal below is therefore a
design choice made with the constraint lifted, which is the only kind worth
recording.

### Why the canonical model does not move anyway

1. **`SPEC.md` §3.2 is an invariant and §9 is a roadmap.** "One canonical model;
   reduced models are compiled views" is architecture. A roadmap line that would
   replace the canonical model is the weaker of the two documents, and M2 D1 and
   M4 D1 both already set the precedent of a roadmap line being overruled by a
   measurement and a stated reason.
2. **The blast radius is the whole repo and the physics payoff is zero.** Four
   engines, the scenario file, the editor, every fixture and 2,835 core tests are
   written against `NetworkModel`. Rewriting them buys no new dynamics — it buys a
   different spelling of the same data.
3. **Their component library does not line up with ours field-for-field, and we
   already know it.** M4 D13/D14 found this the hard way with PowerDynamics: the
   component the plan named took a torque where ours takes a power, and the
   component that actually matched was a different one. A migration would have to
   resolve that mismatch for *every* type at once, with no oracle left over to
   catch it — because the oracle would have become the model.
4. **74 packages in the core package is a cost the core does not pay elsewhere.**
   `reference/` exists precisely so a heavyweight external check can be carried
   without the simulator carrying it.

### What this costs, said out loud

We do **not** get standard case-file import (PSS/E, MATPOWER) for free, and we do
not get their component library. If a future milestone wants a published
100-bus case, it will want an importer, and that importer will most cheaply be
written *through* the adapter this milestone builds. That is a reason to keep the
adapter honest and bidirectional-friendly, not a reason to migrate now.

**Action owed:** `SPEC.md` §9 item 5 gets an inline note saying which half was
kept and pointing here — the M4 precedent, where a superseded roadmap line was
annotated in place rather than left to mislead.

---

## D2 — The equations are ours; the nonlinear solver is the ecosystem's

`SPEC.md` §8 says: *"No hand-rolled solvers where the ecosystem has them. Build
the loop and router, not the integrators or power-flow/dynamics math."*

Read precisely, that names two different things, and M6 splits them the same way
every previous milestone has:

- The **solver** — Newton with a sparse Jacobian, line search, convergence
  control — is `NonlinearSolve.jl`'s job, exactly as time integration is
  `OrdinaryDiffEq`'s. We do not write it.
- The **residual equations** — what power balance means at a bus, what a generator
  bus holds fixed, when a reactive limit binds — are *model*, not solver. We write
  those, the same way we write every ODE right-hand side in the repo and hand it
  to an integrator.

This is not a loophole; it is the shape of every engine already in `src/`. The
alternative reading — translate our case into `PowerSystems`, call their solver,
map the answer back — was considered and rejected: it puts 74 packages in the core
package, requires a lossless round-trip our `Machine` type cannot make, and leaves
nothing to validate, because a translator checked against its own translation is
not a check.

**Dependency cost, measured (step 0):** `NonlinearSolve` 4.29.2 and `SparseArrays`
1.12.0 are **already in the dev manifest transitively**, via the SciML stack. Both
become direct dependencies at **zero new packages**.

A side note worth keeping: `src/` currently never names `SparseArrays` at all —
`NetworkDynamics` has owned every sparse structure to date. Step 2 is the first
matrix this repo assembles itself, so it is the first place `CLAUDE.md`'s "never a
dense Y-bus" rule binds our own code, and the first place it can be tested
structurally rather than trusted.

---

## D3 — Bus type is derived from what is attached, plus one declared slack

A power flow needs to know, per bus, what is held fixed. The standard encoding is a
stored type per bus (slack / PV / PQ). **This repo stores one field and derives the
rest**:

- `NetworkModel` gains `slack::Symbol` — one declared reference bus. This is a
  *promotion*, not an invention: `DetailedEngine` has carried exactly this field
  privately since M5, and M5 D13 already established that the slack is a **dispatch
  choice, not a gauge choice**. Moving it into the model is making an existing
  decision visible to something other than one engine.
- Every other bus's role is a function of what is attached: at least one machine →
  a generator bus (holds `P` and `|V|`); otherwise → a load bus (holds `P` and
  `Q`).

Why derived: a stored type is a second source of truth about the same fact, and it
can disagree with the components attached to the bus. The repo has paid for that
shape before — M5 step 8's mapping mutation found a lookup table guarding against a
transposition that *could not happen*, because a different invariant already made
the two orders identical. A derived type cannot fall out of step with the model
because it **is** the model, read.

The cost is that a generator bus cannot be forced to behave as a load bus by
declaration — only by its reactive limits binding, which is the physical reason it
should happen anyway.

---

### What step 1 measured (2026-09-07)

**D3's word "promotion" was not literally true, and the correction is a lookup
rather than a rename.** `DetailedEngine`'s private `slack` names a **machine**
(`init!` refuses a non-machine by name — "a passive bus has no rotor angle to
pin"), and `NetworkModel.slack` names a **bus**. They are two fields in bijection
only where the reference bus carries exactly one machine, so moving one into the
other would have silently reinterpreted every call site that passes an explicit
machine — `scripts/iberia_two_area.jl` passes `slack = :CE`, and its 5,662.4 MW is
the milestone the repo just certified. What actually moved is the **default**:

- the keyword still names a machine, unchanged;
- the default is now the machine at `net.slack` instead of `net.machines[1]`;
- `NetworkModel.slack` defaults to `machines[1].bus` **after the bus sort**, not to
  `buses[1].id`. Since M5 a bus may carry no machine, and `machines` is stored
  bus-sorted, so `machines[1]` is the machine on the first *machine-carrying* bus —
  which is exactly what the old `ids[1]` picked. That identity is what makes the
  change bit-identical rather than merely equivalent, and it is why the default is
  written against the machine vector and not against the bus vector.

**"The slack bus carries a machine" is an ENGINE guard, not a model guard.** The
model validates only that the slack names a real bus. This is M5 D3's precedent
applied again (three guards moved out of `NetworkModel` into `SwingEngine` because
each was a property of a tier and not of the data), and it has a concrete
consequence the scenario editor needs: a half-built draft — buses placed, no
machines attached yet — must still be constructible.

---

## D4 — `R = 0.0` is the default, and "no number moves" is step 1's gate

Every `Branch` in the repo today is a pure reactance. Adding `R` with a default of
zero means every existing fixture builds an identical model and every recorded
number stays bit-identical — which turns the whole of step 1 into a checkable
invariant rather than a leap of faith.

This matters more than it sounds. `Branch.X` is read by `branch_arrays`, the
`SwingEngine` edge model, the `DetailedEngine` static and dynamic edge models, and
`_branch_flows`. A resistance that silently reaches any of those paths would move
M5's criterion numbers without anyone noticing, and M5's numbers are the milestone
this repo just certified. So the gate is: **the full core suite passes unchanged,
and the anti-vacuity mutation sets one branch's `R` non-zero in an isolated fixture
and shows a number does move.** Without the second half the first half is vacuous —
a test that passes because nothing reads the field at all.

**Named as absent rather than implied:** line charging susceptance (`B`) and
transformer tap ratios are **not** added. A branch model with `R` and `X` and
nothing else is a short line, and this is stated in the type's own documentation so
a reader cannot mistake incompleteness for a modelling choice. The moment a case
needs a long line or a tap, that is a new decision with its own oracle question,
not a field quietly appended.

---

### What step 1 measured — and the one box the plan mis-scoped (2026-09-07)

**The anti-vacuity mutation as the plan wrote it could not pass, and the reason is
the plan's own ordering rule.** All five readers of `Branch.X` are lossless *by
construction*: `_coupling` is `E′ᵢE′ⱼ/X` with no place for a resistance;
`branch_arrays` and `branch_topology` return `X` alone; both `DetailedEngine` edge
models and `branch_power` compute `(Vf − Vt)/(jX)`. So the honest step-1 answer at
all five sites is **"deliberately unchanged"** — which the checklist permits — and
then "set one branch's `R` non-zero and show a number moves" has nothing to move.
Wiring `R` into those paths *is* a physics change, inside the step whose gate is
"no number moves".

Rather than quietly dropping the box or quietly widening the step, the mutation was
**re-scoped, and the real one re-assigned**:

- **Step 1's mutation is behavioural, not numerical.** `R ≠ 0` now makes every tier
  **refuse the model by name** (`_assert_lossless_branches`, called from
  `SwingEngine`, `DetailedEngine` and `reference/`'s `build_oracle`). This is
  exactly the shape M5 used for `Load`'s ZIP shares — validated by the type from the
  step that adds it, refused by the engines until the step that solves it — and it
  is what makes "nothing reads `R`" a *stated boundary* instead of an untested
  hope. Setting `R` therefore demonstrably changes what the repo does; what it does
  not change is any number a run produces, because there is now no such run.
- **The numerical mutation moves to step 3**, where it already has a home: the
  losses identity (the slack's pickup equals the summed branch losses) is red the
  moment `R` fails to reach the residual equations.

**The step could not be confined to the model file, and a guard is why.**
`test/scenario_file.jl` asserts `fieldnames(Machine) == (:id, :bus,
_MACHINE_FIELDS...)`, so growing `Machine` turns that test red until the writer
grows too. That is the guard working exactly as designed ("if `Machine` grows a
field this test goes red before a file silently stops carrying it"), so step 1
carries the file change for the three machine fields, and `Branch.R` and the
top-level `slack` key went in with it rather than leaving a mid-milestone window in
which the file silently drops a field. What remains genuinely step 5's is the
**decision** in D8: turning the slack's read-side default into a rejection, its
message, and the pre-M6 round-trip test.

**Two integration sites the plan named neither of.** `ui/src/editor.jl` rebuilt
`Bus`/`Branch`/`Load` generically by splatting `fieldnames` into the positional
constructor, which a keyword-only `Branch.R` breaks outright — `Branch` now has its
own rebuild method, the way `Machine` already did. And the editor had to start
**carrying** the slack (through open, save, rename and delete), because otherwise
opening a file with a declared slack and saving it again re-defaults it silently —
D8's failure mode arriving through the UI instead of through the reader.

**One thing left owed to step 5, named here so it is not discovered:**
`docs/scenarios/three-machine-ring.toml` is a real pre-M6 file with no slack key.
It reads correctly today on the read-side default, and it is the file
`ui/README.md` tells a reader to open. When step 5 makes a missing slack a
rejection, that file and that documented entry point break unless step 5 updates
them.

---

## D5 — The existing fixpoint is not a power flow, and cannot be extended into one

The obvious plan — "we already have a checked network solve, generalise it" — does
not exist, and saying so here is cheaper than discovering it in a refactor.

`DetailedEngine`'s steady state specifies the **machine's internal state** (`E′`,
the field voltage, the rotor angle) and solves for bus voltages consistent with it;
`Vref` is then *derived backwards* from the solved answer. A power flow specifies
the **terminal conditions** — `P` and `|V|` at a generator, `P` and `Q` at a load —
and solves for the machine's reactive output and the slack's pickup.

The unknowns and the givens **swap places**. There is no generalisation that
contains both; there are two solves that answer two questions.

So both survive, and the interesting thing is that they overlap: given a power-flow
solution, the machine states that produce it are a back-substitution M5 already
built, and running the result through `DetailedEngine` must therefore be **flat**.
That is hurdle 8, that is step 4's oracle A, and it is the strongest check in this
milestone precisely because neither solve is declared correct — they are made to
agree, or one of them is wrong.

---

## D6 — The `|V|` band is inherited as the discriminator, not re-derived

M5 measured, in this repo, on this network: the collapsed low-voltage solution is
self-consistent and converges to a residual of **5.0e-16** against the true
solution's **1.8e-13**. The spurious answer is *400× "better"* by the metric a
solver reports. `_check_power_flow`'s comment already says the `|V| ∈ [0.9, 1.1]`
band is the only thing that separates them and that the residual is "necessary and
conspicuously not sufficient".

The new solver inherits that discriminator explicitly rather than re-deriving it,
and the AC step's checks are ordered the same way: band first, branch ratings
second, residual third and last.

With generator buses and reactive limits there are **more** spurious basins than
M5 faced, not fewer — a limit that binds changes which equation is active, so the
iteration can settle into a self-consistent state where the "wrong" set of buses is
limited. The step-3 gate therefore includes a case whose limits are set so wide
they cannot bind, which must reproduce the unlimited solution *exactly*, and a case
where a limit is known from algebra to bind, which must report exactly that bus.

---

## D7 — The optimisation rung is a gate, and here is what decides it

Step 6 is written as a decision, not as work, and the criteria are fixed now so
the decision cannot be made by whichever answer is convenient at the time.

**It opens only if all four hold:**

1. Steps 1–5 are done and all three suites are green.
2. A cost representation can be added to `Machine` that is a *model* field with a
   physical meaning (a heat-rate curve or a piecewise-linear cost), not a number
   invented to make an optimiser run. If the only way to get costs is to make them
   up, the result is `entsoe-iberia-reproduction.md` §7.3's failure again — a tuned
   input quoted as a result — and the gate stays shut.
3. `JuMP` plus an open-source optimiser resolves against the stack, measured the
   way D1 measured `PowerFlows`, and does not move our bounds.
4. There is an oracle. An optimum with no independent check is a number, not a
   result; if nothing can confirm the dispatch is optimal rather than merely
   feasible, the rung is not worth building yet.

**If it does not open**, it is written into the README as owed with the criterion
that failed, in the form M3 step 7 finally used for Figure 3-67: an item that keeps
being carried is missing a criterion, not missing work.

---

## D8 — The scenario file takes read-side defaults, with the slack as the one
exception that rejects

`scenario_file.jl` writes **every** machine field explicitly, precisely so a
changing default cannot change a file's meaning. Step 1 adds fields, and every
scenario file already on disk becomes incomplete.

Two ways out, and the choice is taken here:

- **A file-format version marker**, with the reader branching on it. Rejected:
  it adds a branch that must be kept alive forever and tested on both sides, for
  one transition, in a repo whose entire on-disk corpus is a handful of files.
- **Read-side defaults, chosen.** A missing `R` reads as `0.0`; a missing `V_set`
  reads as the value the constructor would have derived; missing limits read as
  unlimited. The writer still writes everything, so a file written *after* this
  milestone is still fully explicit, and only files written before it lean on a
  default.

**The slack is the exception, and it is not a defaulting decision at all.** The
rule above works because each of those fields has a value that is *physically*
what the absent field meant: a line with no resistance recorded was a lossless
line, and it still is. `NetworkModel.slack` has no such value. It is a top-level
model field, not a machine or bus record, so it needs its own key and its own rank
in `_KEY_RANK` — and no bus is the "obviously intended" reference. Picking the
first bus, or the largest machine, would be inventing a dispatch choice and
recording it as if the file had said so, which is M5 D13's point (the slack is a
**dispatch** choice, not a gauge choice) turned into a silent one.

So a file without a slack is **rejected**, with a message naming the buses it could
be. The general rule is therefore: *read-side defaults for every field whose
absence has a physical meaning; the slack rejects, because its absence has none.*
This was caught as an inconsistency between this decision's prose and
`m6-tasks.md` step 5's checklist — the checklist was right — and is settled here
rather than at the point a test goes red.

The invariant that keeps this honest is the one the reader already has: **the file
goes through the same constructors as everything else** (M5 D5), so a defaulted
field is validated identically to a written one, and a file cannot build a model
the constructors would refuse. The round-trip test gains a case that reads a
pre-M6 file and asserts the defaults land where they should — which is the only
thing standing between "a default" and "a silent reinterpretation of old files".

---

## D9 — The DC solve reads its dispatch from the model, and does not police `R`

Two API decisions taken in step 2 that the plan did not pose, and that would each
be expensive to reverse once step 5's editor and step 4's oracles call in.

**No injection argument.** `dc_powerflow(net)` takes a model and nothing else.
The tempting alternative — `dc_powerflow(net, P)` — makes superposition a
three-line test instead of a three-model one, and that convenience is exactly why
it is wrong: an injection argument is a second source of truth about the dispatch,
free to disagree with the machines and loads actually attached. It is the same
shape D3 refuses for bus type, and the same one SPEC §3.2 refuses for the model
itself. The assemble-and-solve core is factored out internally, but the tests go
through the public entry point, because a superposition check run on the internal
helper is close to asserting that a linear solve is linear.

The cost is real and worth naming: `NetworkModel` rejects a model whose scheduled
injections do not balance, so the two halves of a superposition case must each
balance **on their own** — two separate generator/load pairs on one shared
topology, not two arbitrary halves of one dispatch. That constraint shaped the
fixture before a line of it was written.

**No `_assert_lossless_branches` call.** Every engine in `src/` refuses a model
with `R ≠ 0`, and reaching for the same guard here is reflex. It would be wrong.
The guard exists because a lossy model run at a lossless *tier* is a different
network than its data describes, silently and with a plausible answer. The DC
power flow is not a tier: dropping `R` is one of the four assumptions it is made
of, it is stated in the docstring, and the AC solve in step 3 reads `R` on the
same model. A DC solve that refused a lossy case would refuse exactly the cases
step 3 exists for. The test pins both halves — the engine refuses the lossy model
**by its resistance**, and the DC solve returns the lossless answer.

### What step 2 measured, and what it costs step 3 (2026-09-07)

**A check that a wrong implementation still passes is not the step's
discriminator.** Four sabotages of the DC source were run against the whole M6
suite, and superposition — the check the plan singled out as "a property only a
linear model has, so it is a real discriminator" — survived every one of them.
The reasoning behind the plan's claim was about the *class* of model and does not
transfer to the implementation: a wrong linear map is still linear. The full
blindness map is in `m6-tasks.md` step 2 (F6).

This has a direct consequence for step 3, whose listed positive control is "the
AC angles approach the DC answer as loading falls, at the rate the small-angle
approximation predicts". That is a **rate**, not an identity, and it is a
comparison between two of our own solves — so the same question has to be asked
of it before it is written: *which wrong AC implementation would still produce
that rate?* Any AC bug shared with the DC assembly (both read the same topology
and the same injections) would be invisible to it. Step 3's own checks must
therefore include at least one whose answer is fixed by algebra outside both
solves — the losses identity with `R ≠ 0` is the candidate, since the slack's
pickup equals the summed branch losses and neither side of that is a tolerance.


---

## D10 — The three acceptance checks are SPLIT, not copied, and the AC path runs
them in the order the M5 docstring already claimed

D6 says the `|V|` band is *inherited* from `_check_power_flow` rather than
re-derived. Step 3 had to decide what "inherited" means in code, because the
tasks list also asked for a different **order** — band, then ratings, then
residual — and `_check_power_flow` ran the residual first.

Reading it before changing anything turned up the smaller half of the answer:
**the M5 docstring already listed them in the significance order and the code
already contradicted it**, with "Listed third deliberately" written above a
residual check that executed first. So the ordering was not a new requirement; it
was a documented intent that had never been implemented.

Three options, and the choice:

- **Copy the band into the AC file.** Rejected outright — two copies of a
  discriminator is how a discriminator drifts, and D6 exists to prevent exactly
  that.
- **Call `_check_power_flow` from the AC solve.** Rejected for two reasons: it
  takes complex voltages, which the AC solve does not have (it solves in
  magnitude and angle and would have to *build* complex numbers to be checked),
  and it would import the residual-first order rather than fix it.
- **Split it into `_check_voltage_band`, `_check_branch_ratings` and
  `_check_residual`, chosen.** Each is one named check with its own docstring;
  `_check_power_flow` becomes the three composed, and the composition now runs
  them in the order it always claimed. The AC path composes the same three in the
  same order.

The band check takes **magnitudes** rather than complex voltages, which is the AC
solve's native form and costs the M5 caller one `abs.(V)`. One text change went
with it: the residual message used to say "see the band check below", which is a
statement about a position in a function; it now names the band without pointing
at where it sits.

**What this costs, stated:** M5's callers now report a band or a ratings failure
in preference to a residual failure on a solve that fails more than one. That is
the order the docstring always said was the right one, and no M5 test asserts the
selection.

---

## D11 — A load bus holds a ZIP schedule, not a constant complex power, and step
4 is the reason

The textbook power flow's PQ bus holds a constant complex power. This repo's
`Load` is a **ZIP** load whose default share is constant *impedance*, and the
detailed tier integrates all three shares through `_load_current` (M5 step 6).

So the AC residual had a choice: hold `P0 + jQ0` at a load bus (textbook), or
hold the ZIP schedule evaluated at the solved magnitude (this repo's load model).
**It holds the ZIP schedule**, and the reason is entirely about step 4:

> Oracle A is a solved power flow fed to `DetailedEngine` as its initial
> condition, which must then produce a run that does nothing. That is a check on
> the *solve* only if both sides model the load identically. Hold constant power
> in the power flow and ZIP in the DAE tier, and the flat run acquires a floor
> that has nothing to do with either being wrong.

"Identically" is taken literally rather than as physics: `_zip_k` — the voltage
scalar — was **extracted from `_load_current`** and is now called by both.
`_zip_scale` is `|V|² · k`, which is `S_load = V·conj(I_load)` exactly. The
grouping is preserved rather than expanded to the algebraically equal
`a_z|V|² + a_i|V| + a_p`, because the grouping is what makes `k = 1` hold *in
floating point* at `|V| = 1` for any split and at `a_i = a_p = 0` for any voltage.
`_load_current`'s early return is untouched, so the constant-impedance hot path
still takes no square root and is bitwise the arithmetic M5 measured.

**Two consequences, both scheduled rather than left to be discovered:**

1. **Step 4's oracle-B fixtures need `a_p = 1.0` loads.** `PowerFlows`' PQ bus is
   constant power. Compared on a default `a_z = 1` model the two sides are solving
   different networks, and the gap would be a load model rather than a solver.
2. **The `|V| → 0` singularity is inherited, not re-taken.** With `a_p > 0` the
   load current diverges at a collapsed bus — M5 D23's decision, and it is the
   model telling the truth rather than a missing guard.

And one rule that fell out of the mutation run rather than the design: **no check
of the load model may evaluate it through `_zip_scale`.** The losses identity did,
and was blind to a sabotage that dropped a whole power of `|V|` from it. See
`m6-tasks.md` step 3, F10.

---

## D12 — Reactive-limit switching is bind-only, and the missing half refuses
rather than answers

A generator bus holds its terminal voltage only while its machines can supply the
reactive power that takes. Past `Q_max` it becomes a load bus **at that limit**.
The classical implementation also does the reverse — a bus comes back **off** its
limit when the network no longer needs it there — and that reverse is what makes
the PV/PQ iteration cycle between two classifications forever.

**Bind-only, chosen**, with three things attached so that it is a boundary rather
than an omission:

1. **The missing half is a refusal, not a silence.** After convergence, a bus held
   at `Q_max` whose magnitude ended up *above* its setpoint (or at `Q_min` and
   below) is exactly the state back-off exists for, and `_ac_assert_no_backoff`
   throws by name, saying so. It is a separate function precisely so it can be
   exercised directly — no fixture reaches a pathology by accident, and a guard
   that never runs is decoration (M5 step 8's lesson, and `_check_power_flow`'s
   own precedent).
2. **The round cap throws with the bus list** rather than returning a
   half-switched answer. Bind-only switching should terminate, so reaching the cap
   is a bug or a genuinely limitless case; either way the answer is not one.
3. **The first solve IS the unlimited solve.** A round in which nothing switches
   exits without re-solving, which is what makes the positive control — limits set
   so wide they cannot bind must reproduce the unlimited answer **exactly** — an
   `==` rather than an `≈`. That is a constraint on the loop's shape, not only on
   the test, and it is written into the loop's comment where someone might
   otherwise "tidy" it into an always-one-more-pass form.

**The slack's own reactive limits are not enforced**, and that is named here
rather than discovered. The slack is the bus whose injection is whatever the
network needs; limiting it requires a distributed or area slack, which no type in
this repo expresses.

---

### What step 3 measured (2026-09-07)

**The rate control's exponent is a statement about the fixture, and the fixture
was proved load-bearing by measurement.** The band [7.5, 8.5] on the ratio of
successive gaps was written into the test before any number was looked at, from
the truncation order alone. Measured: **8.020, 8.005, 8.001** at λ = 0.4 → 0.05,
with the smallest gap 1.06e-07, three orders above the solve tolerance. Then the
same check on the same topology with a **scaled reactive load** — the one
condition the derivation forbids — gives **4.220, 4.106, 4.052**. The two bands do
not overlap, so the 8 is a claim about the physics rather than a number a smooth
solve would produce anyway. Both are now in the suite: the second is what makes
the first mean something.

**A lossless `Y` is the DC `B` — but not to the bit, and the reason is Julia's
complex reciprocal rather than anything about the model.** `==` was tried first
and failed at 3.55e-15. `inv(complex(0.0, X))` returns exactly `-1/X` for some
reactances (0.25, 0.3) and one ulp off for others (0.1, 0.2, 0.4); the real part
is exactly zero in every case. The check is therefore stated in ulps of the
largest susceptance (bound 1.3e-14) rather than as a tolerance, and it is the only
check that ties the two matrix assemblies together.

**`Pgen` is read back from the solved network, not copied from the schedule.**
`Pgen = P_network + P_load`, so a non-slack machine's reported output equals its
schedule only to the residual (measured 4e-16). Copying the schedule in would have
made "the machine produces its schedule" a vacuous test; reading it back makes it
a check on the solve, and the price is that two assertions are `≈` rather than
`==`.

---

## D13 — Oracle A is blind to the schedule, so the seeded path checks it itself

The flat run is the strongest check in this milestone and it has a hole, found by
mutation rather than by argument, and the hole is structural rather than
incidental.

`init!(DetailedEngine, net; powerflow = sol)` **derives** the machine's mechanical
power and its regulator setpoint from the solved voltages — that is the whole
design, and it is what makes the seeded state a fixpoint of equations nobody tuned
it to. The consequence is that a solve for the **wrong schedule** back-substitutes
into a perfectly good fixpoint at an operating point nobody asked for. Every check
downstream is blind to it: `_check_power_flow` passes, the dynamic-network residual
passes at machine precision, and the run is flat.

Measured, on `load_bus_system` and `detailed_pair`:

| what was broken | result |
| --- | --- |
| the reactive-power equation's sign | refused, residual 0.61 / 0.040 |
| the admittance's off-diagonal sign | refused, \|V\| band / residual 8.0 |
| the scheduled `P`, scaled by 1.1 | **flat to 8.6e-14 / 2.0e-14** |
| `V_set`, misread by 2 % | **flat to 5.1e-13 / 2.1e-14** |

A **load** schedule bug was always caught (a wrong load makes the seeded voltages
fail Kirchhoff, because loads appear in the dynamic network's own algebraic
equations). A **generation** schedule bug never was, because generation does not
appear in those equations at all — `Pm` is a derived parameter. The asymmetry is the
mechanism, not a coincidence, and it is the reason a fifth and sixth check were not
enough: no check written *downstream of the solve* can close it.

**So `_assert_seed_is_this_dispatch` closes it upstream**, in `src/` rather than in a
test, because every seeded `init!` needs it. It compares the solution's held
quantities against the model read through `machine_arrays` / `load_arrays`
**directly** — not through `_ac_schedule`, which is the thing under test. With it,
all four mutations above are refused by name, at the right bus, naming the right
quantity.

**What it still cannot see, stated now rather than discovered later:** a misread
reactive *limit*. A bus wrongly switched to its limit holds a `Q` nobody scheduled
and its magnitude becomes an unknown, so neither comparison applies; the answer is
self-consistent and the run is flat. That is oracle B's, and it is the second thing
oracle B is for after the lossy branch.

---

## D14 — Both refusals oracle A was designed around were already there

Two guards were written into `_seed_from_powerflow` on the reasoning that the seeded
path needs a lossless network (the AC flow's admittance is `1/(R + jX)`; this tier's
edge is `ΔV/(jX)`) and one machine per bus (the flow solves one reactive output per
bus, and nothing says how two machines split it). Both were **dead code**.
`_assert_detailed_tier` — written at M6 step 1, for this tier's own reasons — refuses
both models outright, before `init!` reaches the seeding, and its lossy message
already points here ("use the M6 power flow, which does read it").

This is M5 step 8's finding in a new place: *the mutation found its own check's
premise wrong*. Worse, one of the two messages was **false** — it told the reader
that the engine's fixpoint solve handles a multi-machine bus, and the fixpoint solve
refuses it too. A guard that cannot fire is decoration; a guard that cannot fire and
misdescribes the alternative is a trap. Both are deleted, the preconditions are
documented as *guaranteed by a guard that predates this one*, and the test that
found it is kept — it asserts the tier's guards fire on **both** paths, which is the
fact the seeding now rests on.

**The cost is recorded rather than hidden: oracle A can never see a lossy branch.**
With `R = 0` the loss channel is zero to round-off and `flow + flow_rev` vanishes, so
the resistive half of `ac_powerflow` — the one thing `Branch.R` was added for — is
outside this oracle's reach entirely. `PowerFlows.jl` models resistance; that half is
oracle B's, and it is now a *requirement* on oracle B rather than a nice-to-have.

---

### What step 4 measured (2026-09-07)

**The two steady states are genuinely different, which is what makes the flat run a
cross-check rather than a self-check.** On `load_bus_system` the power flow and the
engine's own fixpoint put the bus voltage magnitudes **2.35e-2 to 2.52e-2 pu apart**,
the rotor-angle differences **6.3e-3 rad apart**, and the slack machine's dispatch
**5.0e-2 pu apart** (0.604 against 0.654) — the last because the two operating points
draw different power through a voltage-dependent load. Both are flat to 1e-13. The
flow holds `|V| = V_set` at the generators; the fixpoint holds `|E| = Machine.E′`;
those pin different things and land in different places.

**The internal voltage the flow implies is not `Machine.E′`, by 2.7e-2 to 5.0e-2 pu.**
`|Ẽ| = |V + (Ra + jXq)·I|` at the flow's operating point is 1.023 against a declared
1.05 on `load_bus_system`'s `G1`, and 1.049 against 1.00 on `detailed_pair`'s. The
seeded path uses the derived one and ignores the declared one, which is correct and
is worth having written down: it is M5 step 8's "the pre-event offset is larger than
the disturbance" one tier along.

**Flat to 1.5e-13 over 50 s, on the first attempt, on all five fixtures tried.** The
window is 50 s rather than M5's 10 because `detailed_pair`'s slowest mode is
`Td0′ = 8 s`. Left to itself the solver crosses that horizon in **five accepted
steps**, so the third pass of the sweep forces `dtmax = 0.1` — M5 step 1's rule,
reused rather than re-argued.

**No single fixture catches the mutation set, and two of the ten mutations were
no-ops on the fixture they were first run against.** `load_bus_system` is the only
fixture with a `Load`, so the load-schedule mutations do nothing on `detailed_pair`;
its machines are at the frozen-flux defaults (`Tq0′ = Inf`, `Xq = Xd′ = Xq′`), so
*taking the rotor angle from the bus voltage instead of from the internal phasor*
left it flat to 2.5e-13 — with the flux equations frozen, a wrong rotor frame costs
nothing — and swapping `Xq` for `Xd′` was arithmetically the identity. `detailed_pair`
catches both (residuals 0.68 and 0.58). The sweep therefore runs both fixtures, and
the first run of the set was **misread as a finding** until the no-op was spotted:
a mutation that does not mutate looks exactly like a check that does not check.

**The branch flows agree exactly.** `ac_powerflow`'s own `V·conj(y·ΔV)` and the
engine's `_branch_flows` dividing by `im*X` give bit-identical `|S|` on every R = 0
fixture (difference 0.0e+00). Asserted at 1e-14 rather than as `==`, because
bit-equality of two different complex divisions is not a promise Julia makes — step
3 already measured `inv(complex(0.0, X))` landing one ulp off for some reactances.
The `loss` channel is **not** exactly zero either: −5.6e-17 on one branch, because it
is the sum of two separately-rounded products rather than a structurally absent term.

**The plan's anti-vacuity instruction does not survive contact and was split in
two.** "Perturb the solved solution and confirm the run is not flat" cannot be done:
a perturbed voltage violates the algebraic block, so `init!` throws and there is no
run to be non-flat. The two halves are (a) bend the solution → refused at build time,
and (b) overwrite `Pm` with the schedule → the run moves by 6.6 rad. Only (b) is the
anti-vacuity check; (a) is a guard test that happens to be worth having.

**And the identity check on the solution is weak in this repo.** `two_machine_system`
and `detailed_pair` share every bus id, every branch id and the same slack, so
"is this solution for this model" written on ids alone passes on a solution for a
completely different case. It is the *dispatch* comparison (D13) that refuses it.
