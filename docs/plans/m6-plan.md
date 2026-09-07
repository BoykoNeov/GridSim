# M6 — The steady-state ladder: where the grid sits before anything moves · Plan

Companion docs: `m6-context.md` (decisions and, as steps run, what was measured),
`m6-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M5 trios.

M6 has **no pre-study**. M5 needed one because its physics (flux equations,
degeneration algebra, a foreign machine model read from source) was genuinely
unknown to the repo. The power-flow equations are not: they are textbook, they are
short, and the repo already carries a checked network solve. What is unknown here
is not the mathematics but **which of two solved states is which**, and that is a
repo-integration question, so it lives in this trio.

## Goal

Make the steady state a **first-class, reusable answer** rather than something an
engine computes on its way to somewhere else.

Today the only steady state in the repo is `DetailedEngine`'s initialisation: a
`NetworkDynamics.find_fixpoint` on a static network, checked by
`_check_power_flow` and used to start a run. It is a good solve and it stays. But
it answers a **different question** from a power flow, and the difference is the
whole milestone (D5):

| | given | solved for |
|---|---|---|
| `find_fixpoint` (today) | machine internal states (`E′`, `Efd`, rotor angles) | bus voltages consistent with them; `Vref` derived *backwards* |
| power flow (M6) | `P` and `|V|` at generator buses, `P` and `Q` at load buses | bus voltages **and** the generator reactive output and slack pickup needed to support them |

An operator specifies a dispatch and asks what the network does. That is the
second row, and the repo cannot currently ask it.

By the end of M6 the repo can take a `NetworkModel`, a declared dispatch and one
declared slack bus, and return a solved network state — **twice**, by a linear
approximation and by the full nonlinear solve — with the answer checked against
two independent oracles, and with the whole thing reachable from the scenario
editor's map.

## What M6 is not

- **Not a `PowerSystems.jl` migration.** `SPEC.md` §9 item 5 says "introduce
  `PowerSystems.jl` as canonical model here". **M6 refuses that line**, with the
  measurement that makes the refusal informed rather than lazy — see D1. The
  package is adopted, in `reference/`, as the second oracle. The canonical model
  stays `NetworkModel`, extended.
- **Not hand-rolled numerics.** We write the *equations* — that is model, and the
  learning payoff. The nonlinear solve goes to `NonlinearSolve.jl` exactly as the
  time integration goes to `OrdinaryDiffEq`. `SPEC.md` §8's "no hand-rolled
  solvers where the ecosystem has them" is honoured on the solver and read
  precisely on the equations (D2).
- **Not AC-OPF, unless a gate opens.** Step 6 is a go/no-go with stated criteria,
  not a commitment. It needs a second dependency mountain (`JuMP` plus an
  optimiser) and cost data no type in the repo has a field for.
- **Not inverter-based resources.** `SPEC.md` §7.6's third lesson is still owed
  and still unscheduled. M6 does not touch it and does not imply it.
- **Not a new engine.** Nothing here steps in time. The steady state is a
  *function of a model*, not a `SimulationEngine`, and it deliberately does not
  enter the mode router.
- **Not AGC.** Out of scope since M3 (`m3-context.md` D3), still out.

## The order, and why it is the order

The ordering rule is M4 D7's, applied to solved states: **never let two things
change at once between a number and its check.** So the data model moves first
under an invariant that forbids any existing number from moving; the linear solve
lands before the nonlinear one so the nonlinear one has a cheap sanity partner;
and both oracles arrive only once there is something unambiguous to compare.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs; it is done when its named check passes with a
positive control and an executed anti-vacuity mutation** — the standing rule since
M3, which has now caught a real bug in M3 step 7, M4 step 4, M5 step 6 and M5
step 8.

### Step 1 — The fields the ladder needs, added without moving a number

`Branch` gains `R` (series resistance, pu on system base). `Machine` gains `V_set`
(scheduled terminal voltage magnitude) and `Q_min` / `Q_max` (reactive limits).
`NetworkModel` gains a declared `slack::Symbol`, promoting the field
`DetailedEngine` has carried privately since M5 into the model where a power flow
can see it (D3).

Bus type is **derived, not stored** (D3): the declared slack bus is the reference;
a bus carrying at least one machine is a generator bus; every other bus is a load
bus. A stored type is a second source of truth that can disagree with what is
attached, and this repo has paid for that shape before.

**The gate is an invariant, not a feature:** with `R = 0.0`, `V_set` defaulted from
the existing data and the limits defaulted to unlimited, **every existing test
still passes and every recorded M5 number is bit-identical**. That is the positive
control. The anti-vacuity mutation is to set one branch's `R` non-zero in a fixture
nothing else touches and show a number *does* move.

Two things about that gate, because it is easy to under-execute. It is **two
claims**, and the suite going green checks only the first: M5's criterion numbers
are asserted with tolerances, so a float can move underneath a passing test —
"bit-identical" means printing and comparing values. And `Branch.X` has **five
readers** (`branch_arrays`, `SwingEngine`'s edge model, `DetailedEngine`'s static
and dynamic edge models, `_branch_flows`), so adding `R` beside it is a five-site
change where each site is stated as updated or deliberately unchanged. Step 0
already demonstrated the shape: one owed SPEC annotation turned out to be six.

Owed and named rather than smuggled in: line charging (`B`) and transformer taps
are **not** added here. They are real and they are absent, and D4 says so out loud
rather than letting a reader assume the branch model is complete.

### Step 2 — The linear (DC) power flow

The classical approximation: flat voltages, small angles, lossless branches, so
the whole thing collapses to one sparse linear solve `B·θ = P`. It is genuinely
nearly free on the reactance-only branches the repo already has, which is exactly
why it goes first — it produces a second opinion for step 3 at almost no cost.

This is the **first matrix the repo builds itself**; `NetworkDynamics` has owned
all sparsity to date. So it is also the first place `CLAUDE.md`'s "sparse from day
one, never a dense Y-bus" applies to our own code rather than to a dependency's,
and the check is structural: the assembled matrix is a `SparseMatrixCSC` and its
stored-entry count is the one algebra predicts from the branch list.

Checks: a two-bus closed form; a three-bus ring where the split between two
parallel paths is a ratio of reactances and can be written down; superposition
(two injections solved separately sum to the pair solved together, which is a
property only a linear model has and is therefore a real discriminator).

### Step 3 — The nonlinear (AC) power flow

Our residual equations — real and reactive power balance at every bus, in polar
form — handed to `NonlinearSolve.jl`. Generator buses hold `|V|` and `P`; load
buses hold `P` and `Q`; the slack holds `|V|` and angle and picks up whatever the
losses turn out to be.

Two things make this step harder than it looks, and each gets its own gate:

1. **Convergence is not validation.** M5 already measured the trap in this exact
   repo: the collapsed low-voltage solution is self-consistent and converges to a
   residual *400× tighter* than the true one (5.0e-16 against 1.8e-13). The
   `|V| ∈ [0.9, 1.1]` band is what separates them, and it is inherited from
   `_check_power_flow` rather than re-invented. With generator buses in the mix
   there are **more** spurious basins, not fewer (D6).
2. **Reactive limits switch the bus type mid-solve.** A generator bus that hits
   `Q_max` stops holding its voltage and becomes a load bus at its limit. This is
   what makes a power flow a power flow rather than an algebra exercise, and it is
   also where the iteration can cycle. It is in scope, with its own convergence
   test and its own anti-vacuity case (a limit set so wide it can never bind must
   reproduce the unlimited answer exactly).

The positive control for the whole step: with every `R = 0` and every generator
voltage at 1.0, the AC solution's angles must approach the step-2 linear answer as
the loading falls, at the rate the small-angle approximation predicts. That is a
comparison between two of *our* solves, so it catches an equations bug that both
oracles below might absorb.

### Step 4 — The two oracles

**Oracle A, the one we already own — the flat run.** A correctly solved power flow,
fed into `DetailedEngine` as its initial condition, must produce a run that does
nothing: no transient, no drift, every state flat to the solver's tolerance. M5
built both the machinery and the test shape for this. It is sharper than any
residual because it drives the *same* physical claim through a completely
different code path — and it is the check that makes the repo's two steady-state
sources agree without either being declared correct by fiat (D5, and hurdle 8).

**Oracle B, external — `PowerFlows.jl` in `reference/`.** A `to_powersystems`
adapter builds the same case as a `PowerSystems.System`; their Newton solve and
their DC solve run; bus voltages, angles and branch flows are compared. This is the
M4 pattern exactly: the external package lives in `reference/`, never in the core
package, and the case is **compiled from `NetworkModel`, never typed beside it**.

M4 D13/D14's lesson applies unchanged and is scheduled rather than discovered:
the convention questions — per-unit bases, the sign convention on loads, where a
shunt is booked, which bus is the angle reference, and whether their DC solve
carries losses — are answered from their source **before** the comparison runs, and
**the band is stated before the gap is seen**.

### Step 5 — The editor and the scenario file fold in

The scenario editor was built outside the milestone structure on 2026-09-07; from
here it belongs to whatever milestone changes the model, and M6 changes the model.

The file first: `scenario_file.jl` writes every machine field explicitly so a
changing default cannot change a file's meaning. Step 1's new fields therefore
touch the field list, the key ordering, the reader, **and** every scenario file
already on disk, which becomes incomplete the moment a field is required. D8 takes
that decision here rather than when a test goes red.

Then the payoff, which is the best UI this milestone can buy: the editor gains a
**solve** action. Place buses on the map, attach machines and loads, draw lines,
press solve, and the map colours by voltage with flow arrows on the branches and
the slack's pickup in the read-out. Every window before this one has drawn a
*time series*; this one draws the **network**, which is the thing the editor was
always for.

### Step 6 — The optimisation rung, gated

Not a commitment. The gate, its criteria and what decides it are in D7. A step
that is planned as a decision and executed as a decision is not a step that got
cut; an item that keeps getting carried without a criterion is (M3 step 7's
lesson, learned on Figure 3-67).

## What gets cut if the milestone runs long

Stated before anything is built, the way M5 D11 required:

1. **Step 6 first** — it is already a gate, so cutting it is the gate closing.
2. **Step 5's map rendering second**, but *not* step 5's file work: a scenario
   file that cannot round-trip the new fields is a broken repo, whereas a map that
   cannot draw flows is only a missing view.
3. **Nothing else.** Steps 1–4 are the milestone. A ladder with no external check
   and a solved state nobody cross-examined is exactly the shape this repo has
   spent five milestones learning not to ship.

## Standing rules carried forward

- Per-unit internally on `S_base`; engineering units only at the UI boundary.
- Sparse always — and for the first time that rule binds our own code (step 2).
- Concrete-typed struct fields; struct-of-arrays for numeric parameter arrays.
- Every new exported name checked against `names(GLMakie)` (a collision cost a
  round in M1).
- Every dependency change followed by `git diff` on the `Project.toml` — `Pkg.add`
  rewrites the file and drops every comment.
- Manifests are gitignored on purpose; re-resolve all three from deleted manifests
  at the milestone's end and **measure** the counts there rather than quoting them
  (M4 step 5, and the trap has now caught this repo three times).
