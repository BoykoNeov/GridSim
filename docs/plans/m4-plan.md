# M4 — Run-then-playback, cross-fidelity overlay, and the first external oracle · Plan

Companion docs: `m4-context.md` (decisions and what the probes actually measured),
`m4-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–3 and the M1–M3 trios.

## Goal

Build the **second execution mode** the architecture has claimed since day one and
never implemented — run-then-playback — and then use it for what SPEC §2 says the
two modes exist for: **overlaying two fidelities of the same scenario and reading
where they part company**.

Three things land:

1. `solve!` gets its first method in the repo's history. Today `src/engines/interface.jl`
   documents `solve!`/`state_series` as the playback half of the contract and
   **no engine implements it** — `grep` finds the docstring and nothing else. Half
   the durable abstraction has never been executed.
2. A divergence read between two trajectories, in `src/analysis/postprocess.jl`
   where it gets a headless test, not buried inside a window.
3. A scrubbable playback window with two curves on it, and the first **external**
   check on our own physics: PowerDynamics, driven from our own model, as an
   oracle for the swing tier.

## What M4 is not

- **Not the detailed machine tier.** Voltage as a genuine unknown, flux dynamics,
  exciters, and the power flow + initialisation they require are **M5**. See
  "Why the detailed tier is M5" below — this is a size decision, taken openly.
- **Not `PowerFlows.jl` / `PowerSystems.jl`.** Roadmap item 5 still owns those.
- **Not a shipped PowerDynamics tier.** PowerDynamics enters as a *validation
  oracle* in its own package, not as an engine the UI can run (see D3).

## The roadmap deviation, stated once

`docs/SPEC.md` §9 item 4 and §7.6 both name **PSID** (PowerSimulationsDynamics)
as the full-fidelity sibling. **PSID cannot be added to this repo**, and this was
measured, not reasoned about (`m4-context.md` §The dependency probes):

- Against the repo's actual `Project.toml` + `Manifest.toml`, `Pkg.add` fails
  outright — `Unsatisfiable requirements detected for PowerSimulationsDynamics`.
- The only resolution that succeeds drags **NetworkDynamics 1.1.0 → 0.10.17** (a
  pre-1.0 API) and **OrdinaryDiffEq 7.6.0 → 6.111.0**. `src/engines/swing.jl` is
  1,309 lines written against NetworkDynamics 1.x. The price of honouring the
  roadmap's letter is rewriting the M2/M3 engine against an older interface.

The root cause is one shared package a generation apart: PSID 0.16.2 pins
**SciMLBase 2.155.2**, while NetworkDynamics 1.1.0 requires SciMLBase 3.x.

**PowerDynamics 5.0.0 takes its place** — same ecosystem, built on the same
NetworkDynamics we already use, and it resolves against the repo's pinned stack
with *nothing moved*: NetworkDynamics stays 1.1.0, OrdinaryDiffEq stays 7.6.0,
SciMLBase stays 3.49.1. Cost is ~49 additional packages (not the ~123 measured in
`m2-context.md` D1 — most of that overlap is already installed since M2).

M2 deferred PowerDynamics because "M2's single machine type does not need a
component library." M4 is the milestone where that stops being true: the library
carries `ClassicalMachine`/`Swing`/`PSSE_GENCLS` at *our* fidelity — which is what
makes it an oracle rather than merely a bigger model.

## Approach (incremental; each step commits and leaves tests green)

### Step 1 — `solve!`, the contract's unexecuted half

A playback method for `SwingEngine` and for `FrequencyResponseEngine`: solve a
whole horizon in one call, record onto a *chosen* grid, expose it through the
existing `state_series`.

**The interface docstring contains a promise M3 falsified, and this step fixes
the wording rather than inheriting it.** `interface.jl` says playback engines take
perturbations "supplied up front rather than injected live." That is true of a
scheduled generator trip. It is **false of everything M3 built**: the shed ladder
and the out-of-step relay fire on the system's own state at an instant nobody can
know in advance. So:

- `perturbations=` carries **scheduled** events only (trip at `t = 3.2 s`) —
  compiled to a `PresetTimeCallback`.
- **State-triggered protection stays exactly where it is**, as the callbacks the
  `SwingEngine` constructor already builds. Playback changes *who drives the
  integrator*, not what the physics is allowed to do.

Anything else would mean a playback run and a real-time run of the same scenario
are different systems — which would silently invalidate every comparison in
steps 2–4.

**Validation:** the same scenario stepped by `run_realtime!` and solved by
`solve!` must agree to solver tolerance. Run at **two tolerances** — M3's standing
rule, because a number below the solver's own tolerance is not a result until it
survives the tolerance changing.

### Step 2 — resampling and divergence, in `postprocess.jl`

Two trajectories from two engines land on **different solver-chosen time grids**.
Comparing them requires putting them on one grid, and the way that is done is the
whole result:

- Resample via the solver's own **interpolant** (or a shared `saveat` grid fixed
  before the solve). **Never** straight-line interpolation between recorded
  samples — that error lands in exactly the quantity being measured, and the
  recorder decimates, so late in a run the samples are far apart.
- Compare **like with like**: the inertia-weighted average frequency on both
  sides, never machine 1 against the aggregate. M2 spent four distinct names
  learning that a raw per-machine quantity is gauge-arbitrary.

Lives in `src/analysis/postprocess.jl` so it is testable without a screen.

### Step 3 — the playback window: scrub, overlay, divergence

A GLMakie window over a solved series: a time slider that moves a cursor through
the run, both curves drawn, and a divergence read-out. Built with the repo's
standing UI discipline — `smoke_render` offscreen first, then the live window;
render before claiming.

**The overlay pair is the two engines that already exist** — the M1
centre-of-inertia model against the M2/M3 network swing model. That is free, and
it exercises the machinery on a pair whose answer we already know.

**It delivers exactly one of the three lessons SPEC §7.6 names.** The spec says
the divergence shows "inter-machine swings, voltage coupling, IBR behavior". This
pair can only ever show the **first**. Voltage coupling and inverter behaviour
need a tier that has voltage in it, and that is M5. This is written down here so
step 3 does not later get presented as the milestone's payoff.

### Step 4 — `reference/`: PowerDynamics as an external oracle

A **third package**, mirroring `ui/`: `reference/` depends on `GridSim` and
`PowerDynamics`, and never the reverse. Core keeps its six dependencies and its
dependency-closure test keeps passing unchanged.

The step's real work is **not** the dependency add. It is a
**`NetworkModel → PowerDynamics` builder**. SPEC §3.2 is explicit that reduced
models are *derived views*, never parallel hand-maintained copies; a PowerDynamics
case typed out beside `two_machine_system()` would be precisely the forked
parallel data the invariant forbids. The builder is also the piece M5 reuses, and
the shape roadmap item 5 will want when `PowerSystems.jl` arrives.

Then: the same two-machine case, PowerDynamics configured with
`Library.ClassicalMachine` — **our fidelity, someone else's implementation** — and
the step-2 divergence read applied across the two. Disagreement here is a bug in
*our* engine, not a lesson about fidelity. That is the entire point of doing it at
matched fidelity first: when the detailed tier lands in M5, a disagreement can be
attributed, instead of leaving "the simple model drops swings" and "our model has
a bug" indistinguishable.

### Step 5 — the dependency housekeeping M3 left open, now in its right place

`m3-tasks.md:795` carries one open box: both dependency resolutions tested, not
just the developer machine's. M3 left it open "because it has to be re-run by
whichever later step does change one." **Step 4 changes one** — so this milestone
owns it, and the ambiguity ends here.

Folded in: the `[sources]` entry in `ui/Project.toml` that M3 declined for being
a dependency change. Without it the `ui/` package's link to core lives only in a
gitignored manifest, so a fresh clone cannot resolve it. `reference/` gets the
same entry from birth rather than inheriting the trap.

## Why the detailed tier is M5, not M4

The accurate sibling — two-axis machine with flux dynamics, a voltage regulator,
transmission branches carrying voltage as a real unknown — is plausibly larger
than M2 and M3 combined, and it drags in work this repo has never done:

- **A power flow solve.** With voltage as an unknown you can no longer start from
  chosen angles and speeds. Initial bus voltages come from a power flow, and each
  machine's internal states and field voltage are back-substituted from its
  terminal condition. This is roadmap item 5's territory arriving early, and it
  needs to be scoped deliberately rather than absorbed.
- **The failure mode that looks like a discovery.** A mis-initialised detailed
  model opens with a transient nobody injected. The check that catches it is a
  **flat run** — no disturbance at all, every state constant for the whole horizon
  — and no cross-fidelity overlay will catch it.

Splitting keeps M4 independently shippable (playback mode, the divergence read, a
scrubbable overlay window, and the first external check on our physics) and gives
the detailed tier a milestone sized to it. M5's own trio gets written when M4
lands, informed by what the oracle harness turns out to cost.

**What M5 already knows it must do**, recorded now so it is not re-derived:

- **The degeneration oracle, stated precisely.** Shrinking flux time constants
  does *not* reduce a two-axis machine to the classical model — that gives a
  steady-state flux model, a different thing. The clean limit is three conditions
  **together**: constant field voltage (regulator off), equal transient
  reactances on both axes, and no damper winding. Two of those are parameter
  choices rather than limits, so a check that only shrinks a time constant would
  pass against a wrong flux equation. So configured, the detailed tier must
  reproduce `SwingEngine` to solver tolerance, at two tolerances, on the same
  network — and its anti-vacuity mutation is to perturb one flux coefficient and
  watch the equality fail.
- **Network formulation: dynamic RL branches, not the algebraic constraint.**
  Both are open — `VertexModel` takes a `mass_matrix`, so a DAE is available. But
  the algebraic route makes every bus voltage a constraint for a stiff DAE
  solver, and `isoutofdomain`, the step-rejecting protection, the recorder and
  `step!` are all built around a plain stepping ODE integrator. Dynamic branches
  keep it an ODE, the M2/M3 apparatus keeps working, and the accurate tier stays
  steppable. If M5 reverses this, it must say what happens to the step-rejection
  predicate and the protection callbacks, because they do not survive unchanged.
- **"Better than PowerDynamics" is a claim with a measurement attached.** The
  ambition is real and welcome, but it must name *which axis* — accuracy against
  a closed form, cost per simulated second, or steppability in real time — and be
  measured on the same case with the same tolerance. An unmeasured "ours is
  better" is the same category of statement as M3's three printed numbers that
  looked like results and were not.

## Exceeding the oracle is allowed — silently exceeding it is not

Adding an external checker must not turn the checker into a ceiling. Building
beyond what PowerDynamics can express — a mechanism it has no component for, a
fidelity above `SauerPaiMachine`, a formulation it does not offer — is permitted
work. The stated ambition is that we can build parts of it *better*, and a model
that never leaves the oracle's envelope cannot be better than it.

The discipline is bookkeeping, not permission (`m4-context.md` D7):

- Every mechanism carries a label saying **what checks it** — PowerDynamics, or a
  named alternative: a closed form, a degeneration limit, a conservation
  argument, convergence under refinement, or a published benchmark.
- **Un-oracled** is a legitimate label, used sparingly and stated out loud. M3
  already ships one (its aggregate governor time constant). The sin is the
  *unmarked* unvalidated choice, not the unvalidated one.
- When our tier exceeds the oracle, **configure both down to matched fidelity
  first**, establish agreement, and only then switch the extra mechanism on. A
  new mechanism and a fresh discrepancy in the same run leave the discrepancy
  unattributable — which is the very failure the oracle was added to prevent.

## Standing rules carried forward from M3

Every check ships a **positive control** and an **anti-vacuity control**, and the
anti-vacuity mutation is **run**, not merely described — M3 step 7 found a real
bug that way. For an overlay the mutations write themselves:

- Feed the same series twice: divergence must read ~0. (Positive control: two
  genuinely different runs must read clearly non-zero.)
- Make the resampling sloppy — straight-line between decimated samples instead of
  the interpolant — and a check must fail.
- Mutate the scheduled-event compilation so a trip lands one step late, and the
  playback-vs-real-time agreement check must fail.

And: every long-running test self-terminates on a fixed step count, never on a
condition.
