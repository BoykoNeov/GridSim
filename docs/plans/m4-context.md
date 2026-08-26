# M4 — Context

Where things live, what was decided and why, and what the dependency probes
actually measured. Companion to `m4-plan.md` (the how) and `m4-tasks.md` (the
checklist).

## Environment

Unchanged from M3. Julia is on PATH via juliaup; the machine runs **Julia 1.12.6**
while the package `[compat]` floor stays at 1.10. `Manifest.toml` is gitignored —
this is a package, not a pinned app — so every resolved version recorded below is
what *this* machine resolved on 2026-08-26, not a lock.

## State of the repo entering M4

M3 complete and committed at `ab3a87f`, working tree clean. **1719 core tests and
102 UI tests green.** All seven M3 steps ticked; `m3-plan.md:295` states in its own
words that nothing carries into M4. One open box exists anywhere in the plan docs
(`m3-tasks.md:795`, the dependency re-resolve), and `m4-plan.md` step 5 claims it.

Core (`src/`) deps: `CommonSolve`, `Graphs`, `NetworkDynamics`, `Observables`,
`OrdinaryDiffEq`, `SciMLBase`. No Makie, enforced by a dependency-closure test
with a positive control.

The repo currently resolves to **181 packages** in total.

## The dependency probes (run before this plan was written)

Five probes, all in throwaway projects under `M:\claud_projects\temp\`, never
against the repo. The plan's whole shape depended on the answers, so they were
**measured, not reasoned about** — the same discipline as `m2-context.md`'s spike,
including its lesson that a bare environment and the real repo resolve
differently.

### Probe 1 — PSID in a bare environment

`Pkg.add(["PowerSimulationsDynamics","PowerSystems"])` in an empty project:
**succeeds.** 183 packages, ~163 s of precompilation.

| Package | Version |
|---|---|
| `PowerSimulationsDynamics` | 0.16.2 |
| `PowerSystems` | 5.12.3 |
| `SciMLBase` | **2.155.2** |

That third row is the entire story, and it is exactly the case
`m2-context.md` warns is the *wrong* one to plan from.

### Probe 2 — PSID against the repo's actual `Project.toml` + `Manifest.toml`

**Fails.** `Unsatisfiable requirements detected for package
PowerSimulationsDynamics [398b2ede]`:

```
├─restricted by compatibility requirements with SciMLBase [0bca4576]
│  to versions: 0.1.0 - 0.5.1 or uninstalled
│ └─SciMLBase log:
│   ├─possible versions are: 1.0.0 - 3.49.2 or uninstalled
│   └─restricted to versions 3.30.1 - 3 by GridSim [eb5af87e]
```

Read that carefully: given SciMLBase pinned in 3.30.1–3.49.2, the newest PSID the
resolver can reach is **0.5.1** — years old. Current PSID wants SciMLBase 2.x.

### Probe 3 — was it just our `[compat]` ceiling?

No, and the reason matters for anyone who re-litigates this later. Raising
GridSim's own bounds (`SciMLBase = "3.30.1, 4"`, `OrdinaryDiffEq = "7, 8"`,
`NetworkDynamics = "1"`, `Graphs = "1"`) **still fails, identically**.

The binding constraint is our **floor, not our ceiling**. The resolver caps PSID
at 0.5.1 *given* SciMLBase ≥ 3.30.1 — so raising the upper bound was never the
lever, and a future reader who tries it will waste the attempt. The only lever
that could work is dropping the floor below 3.x, which NetworkDynamics 1.1.0
forbids outright. That is what probe 4 then measures the price of.

### Probe 4 — can PSID and NetworkDynamics coexist at all?

Yes, at a price. A fresh environment asked for both resolves — 279 packages — by
**downgrading**:

| Package | Repo today | Coexistence resolution |
|---|---|---|
| `NetworkDynamics` | **1.1.0** | **0.10.17** (pre-1.0 API) |
| `OrdinaryDiffEq` | 7.6.0 | 6.111.0 |
| `SciMLBase` | 3.49.1 | 2.155.2 |

`src/engines/swing.jl` is 1,309 lines written against NetworkDynamics 1.x.
Honouring the roadmap's letter means rewriting it against a pre-1.0 interface.

### Probe 5 — PowerDynamics against the repo's pinned stack

**Succeeds, moving nothing.**

| Package | Version after | Moved? |
|---|---|---|
| `PowerDynamics` | 5.0.0 | new |
| `NetworkDynamics` | 1.1.0 | unchanged |
| `OrdinaryDiffEq` | 7.6.0 | unchanged |
| `SciMLBase` | 3.49.1 | unchanged |
| `Graphs` | 1.14.0 | unchanged |

Total 230 packages against the repo's 181 — **~49 added**, not the ~123 measured
in `m2-context.md` D1, because NetworkDynamics arrived in M2 and most of the
overlap is already installed.

PowerDynamics 5.0 is ModelingToolkit-based (`ModelingToolkitBase` 1.68.0,
`ModelingToolkitStandardLibrary` 2.29.7, `Symbolics` 7.36.0) and its component
library is what makes it usable as an oracle rather than merely a bigger model:

- **At our fidelity** — `ClassicalMachine`, `Swing`, `PSSE_GENCLS`.
- **Above it** — `SauerPaiMachine`, `PSSE_GENROU`/`GENROE`/`GENSAL`/`GENSAE`.
- **Regulators and governors** — `PSSE_EXST1`, `PSSE_IEEET1`, `PSSE_SCRX`,
  `TGOV1`, `PSSE_IEEEG1`, `PSSE_HYGOV`, `TurbineGovTypeI`.
- **Network and loads** — `PiLine`, `PiLine_fault`, `ZIPLoad`,
  `VoltageDependentLoad`, `ConstantYLoad`, shunts, `RXGroundFault`.
- **Inverters** — `ComposableInverter`, `IdealDroopInverter`.
- **Power flow and initialisation** — `solve_powerflow`, `initialize_from_pf`.

## Decisions

### D1 — PowerDynamics replaces PSID as the external reference

**Because PSID is unusable here, measured in probes 2–4**, not because it is
inconvenient. The deviation from `SPEC.md` §9 item 4 and §7.6 is deliberate and is
recorded in `m4-plan.md` §The roadmap deviation. SPEC's own §7.6 wording ("run the
same trip in PSID full electromechanical playback and overlay") should be read as
naming the *role*, not the package; M5 will amend the SPEC line once the oracle
harness exists and the role is filled in fact rather than in plan.

### D2 — We build the detailed machine ourselves; PowerDynamics checks it

The user's call, taken with the cost named. The concern raised against it, once,
for the record: SPEC §1 says "learning through experimentation, not through
reimplementation — stand on the mature Julia ecosystem; build only the parts that
don't exist," and a two-axis machine model does exist off the shelf.

The real risk was never the writing — it was that with two in-house tiers and no
outside implementation, **a disagreement cannot be attributed**: "the simple model
drops swings" and "our model has a bug" look identical. Adding PowerDynamics as
an oracle removes exactly that risk, which is why the two halves of this decision
belong together and neither is sufficient alone.

The stated ambition is that we can build parts of it better. That is a claim with
a measurement attached — see `m4-plan.md` §Why the detailed tier is M5, last
bullet.

**This does not close the attribution risk permanently, by design.** D7 
deliberately permits building beyond what PowerDynamics can express, and in that
region the risk is back in full — there is no outside implementation to say which
side is wrong. D7 handles it by labelling rather than by prohibition, which is the
right mechanism; but D2 should not be read as "risk closed" when D7 reopens it on
purpose.

### D3 — PowerDynamics lives in `reference/`, a third package, not in core

Dependency direction is the enforcement mechanism this repo already uses: `ui/`
depends on `GridSim` and core never imports Makie, checked by a closure test with
a positive control. `reference/` gets the same shape.

Consequences, chosen:

- **Core keeps six dependencies.** `Pkg.test()` at the root stays fast and does
  not resolve 49 extra packages.
- **PowerDynamics is not a runnable tier in the UI.** It is the checker, not an
  engine the mode router offers. Promoting it later is a small change (it is
  already a `SimulationEngine`-shaped thing behind the builder); doing it now
  would put a component library in the hot path for no current payoff.
- The cross-fidelity **overlay in the UI** is therefore ours-against-ours
  (centre-of-inertia vs network swing in M4; vs the detailed tier in M5), while
  PowerDynamics-against-ours is a validation run.

### D4 — Scheduled events go up front; state-triggered protection stays a callback

`interface.jl`'s docstring says playback perturbations are "supplied up front."
That promise predates M3 and M3 falsified it: the shed ladder and the out-of-step
relay fire on the system's own state, at an instant that is not knowable in
advance. Splitting them (`PresetTimeCallback` for the scheduled trip; the existing
constructor-built callbacks for protection) is what keeps a playback run and a
real-time run of the same scenario **the same system** — without which every
comparison in steps 2–4 is measuring the wrong thing. The docstring gets corrected
in step 1 rather than inherited.

### D5 — The PowerDynamics case is compiled from `NetworkModel`, never typed beside it

SPEC §3.2: reduced models are derived views, never parallel hand-maintained
copies. A PowerDynamics system written out next to `two_machine_system()` would be
the forked parallel data the invariant exists to forbid — and it would drift
silently, which is the worst possible property in an oracle. The builder is most
of step 4's cost, and it is the piece M5 reuses and roadmap item 5 will want in
`PowerSystems.jl` shape.

### D6 — M4 owns the dependency-resolution box, and it is no longer ambiguous

`m3-tasks.md:795` was left open for "whichever later step does change" a
dependency. Step 4 changes one, so the box is claimed here and closed here,
together with the `ui/Project.toml` `[sources]` entry M3 declined as out of scope.
`reference/` carries a `[sources]` entry from birth rather than inheriting the
gitignored-manifest trap that has now cost this repo time twice.

## Hazards specific to this milestone

- **Resampling error contaminates the exact quantity being measured.** Two
  engines land on different solver-chosen grids; the recorder decimates, so late
  in a run samples are far apart. Straight-line interpolation between them would
  put its own error into the divergence read. Use the solver's interpolant or a
  shared `saveat` grid fixed before the solve.
- **Comparing a gauge-arbitrary quantity.** Inertia-weighted average against
  inertia-weighted average, never machine 1 against the aggregate — M2 learned
  this the expensive way.
- **A "validated" overlay that validates nothing.** Same series twice must read
  ~0 divergence; two genuinely different runs must read clearly non-zero. Both
  controls, and the mutation is run, not described.
- **The one-lesson-of-three trap.** The M4 overlay pair can only show
  inter-machine swings. Presenting it as the cross-fidelity payoff would repeat
  M3's pattern of numbers that look like results and are not.

### D8 — Scheduled events reach playback through `inject!`, not a `PresetTimeCallback`

`m4-plan.md` step 1 said "compiled to a `PresetTimeCallback`". Step 1 did not do
that, and the reason is worth more than a code comment.

**It is not reachable.** Both engines are parametric on their concrete integrator
type; the callback set is fixed when `init` runs, and an already-built integrator
does not accept a new callback. Honouring the letter would have meant either a
second integrator type per engine or a schedule field threaded through both
constructors, to be filled by `solve!` — real structural cost for a mechanism that
is not the point.

**And the replacement is better for what D4 actually asks.** A `PresetTimeCallback`
needs its own affect: a SECOND way for a scheduled trip to reach the engine,
alongside the `inject!` the real-time loop uses. Two paths that must stay identical
is precisely the shape D4 exists to forbid. `add_tstop!` at the event instant plus
a call to the very same `inject!` gives one path, and it is the path
`run_realtime!` already exercises. (`inject!` also already performs its own
`derivative_discontinuity!` / `auto_dt_reset!` at the boundary — the work a
callback's `u_modified!` would have signalled.)

**The anti-vacuity control survives the change intact**, which is the thing worth
confirming when a mechanism is swapped out from under a control written against
it. `m4-tasks.md` step 1 named the mutation "make a trip land one step late". With
tstops that is "delete the tstops": the solver then steps straight over the event
instant and `_playback_apply!` fires it at the end of whichever step passed it.
**Run** on 2026-08-26, against the source: every assertion in the agreement testset
went red, plus the pre-event-sample test and the protection test. Reverted; green.

### D9 — The output grid is handed to the integrator, not read off the interpolant

The obvious playback loop steps freely and then reads each output sample off the
finished step's interpolant with `integ(t)`. **It is wrong, and only sometimes**,
which is what makes it worth a numbered decision instead of a comment.

When a `ContinuousCallback` fires, the framework shortens the step to the root,
runs the affect (which steps a *parameter*), and marks the state modified — which
makes it recompute the end-of-step derivative against the NEW parameters, bending
the interpolant back across the interval that has just closed. Measured on a
two-stage shed ladder: every sample inside the step a shed ended was wrong by up to
**3.4e-2 Hz, six times the agreement band**, while its neighbours on either side
were right to 1e-9. The error did not shrink cleanly with the tolerance either,
because its size is set by the step length, which moves around unpredictably as
the tolerance changes — so a convergence check alone would have muddied rather
than exposed it.

The framework's own `savevalues!` runs inside `apply_callback!` **after** the step
is shortened to the root and **before** the affect — the one instant at which the
interpolant is both complete and still valid, and an instant no caller can reach
from outside `step!`. So `_playback!` hands the grid over with `add_saveat!` and
drains the samples back out of `integ.sol`. This does **not** put the solver back
on forced steps: `saveat` interpolates inside freely chosen steps, unlike a tstop,
so playback stays a genuinely different numerical path from `run_realtime!`.

Two consequences worth carrying: the fix depends on `calck` (below), which is the
second reason that flag is set; and the drain must happen before the scheduled
`inject!` for the same instant, because a trip changes the COI weights
`_record_at!` uses.

### D7 — The oracle is a floor, not a ceiling

Going **outside** PowerDynamics' scope and fidelity is explicitly allowed, and
this is written down because D2/D3 could easily be misread as the opposite. Where
our model does something PowerDynamics cannot express — a mechanism it has no
component for, a fidelity above `SauerPaiMachine`, a formulation it does not
offer — that is permitted work, not a violation.

What is **not** allowed is drifting past the oracle silently and continuing to
speak as though checked. The rule is therefore about bookkeeping, not permission:

- **Every mechanism is labelled with what checks it.** Either "cross-checked
  against PowerDynamics" or an explicitly named alternative oracle. The valid
  alternatives this repo already uses: a **closed form** (M1's initial-RoCoF and
  settling identities), a **degeneration limit** (the configured-down detailed
  tier must reproduce `SwingEngine` — see M5's three conditions), a **conservation
  or invariance argument**, **convergence under refinement** (the answer must
  survive the tolerance changing — M3's standing rule), or a **published benchmark
  case** with numbers someone else printed.
- **Un-oracled is a legitimate third label**, used sparingly and stated. M3
  already ships one: the aggregate governor time constant, shipped as "a stated,
  unvalidated choice rather than a formula presented as settled." That is the
  template — the sin is not the unvalidated choice, it is the unmarked one.
- **The comparison is run at the highest fidelity PowerDynamics *can* reach**,
  and the excess is then isolated. If our tier exceeds it, configure both down to
  the matched fidelity, establish agreement there, and only then turn the extra
  mechanism on — so what the extra mechanism changes is separable from whether
  the shared part was right. Turning on a mechanism the oracle lacks *and*
  discovering a discrepancy in the same run leaves the discrepancy unattributable,
  which is the failure D2 exists to prevent.

## What step 1 measured that the plan did not anticipate

Four, recorded here rather than only in code comments because three of them are
properties of the *framework* and one is a property of an M1 file, and none is
discoverable by reading this repo.

- **Whether a step's interpolation coefficients exist depends on whether a relay
  happens to be armed.** OrdinaryDiffEq derives `calck` at `init` from roughly
  `dense || !isempty(saveat) || <a rootfinding callback is present>`. Measured:
  `SwingEngine(net)` came out with `calck = false`, and the same engine with one
  out-of-step relay armed came out `true`. Playback reads inside a step, so this
  would have made a recorded trajectory's accuracy depend on an unrelated
  configuration switch, quietly and in the third decimal. Both constructors now
  pass `calck = true` explicitly — **not** `dense = true`, which stores the whole
  history and is the unbounded growth both constructors already refuse.

- **The interpolant is retroactively invalidated by a callback affect.** See D9.
  This is the round step 1 actually cost, and the check that caught it — the
  protection-under-playback comparison — was not in the plan's step-1 list at all.
  It was written because D4 demanded the claim be asserted, and it turned out to
  be the only scenario shape in which the bug is visible.

- **`run_realtime!(duration = N*dt)` runs `N` or `N+1` steps, decided by floating
  point.** The loop stops on `t < t_stop` and `t` is accumulated by repeated
  addition, so at `dt = 0.1` a `duration = 1.0` ran **eleven** steps, not ten: ten
  accumulated `0.1`s fall a hair short of `1.0`. The real-time event then landed a
  whole output step from where playback put it, and the agreement check failed for
  a reason with nothing to do with playback. The tests take `(n - 0.5) * dt`, which
  roundoff cannot decide. **Deliberately not "fixed"**: `while t < t_stop` is a
  correct reading of "run for `duration` seconds of simulation time", and rounding
  instead would move the step count of every existing caller. A later step may
  weigh it; it is written down so it is weighed rather than rediscovered.

- **Neither engine constructor forwarded anything to `init`**, so `reltol` and
  `abstol` were unreachable and M3's standing "a number below the solver's own
  tolerance is not a result until it survives the tolerance changing" rule was not
  expressible against these engines at all. Both constructors now take them,
  defaulted to OrdinaryDiffEq's own `Float64` defaults so nothing moved.
