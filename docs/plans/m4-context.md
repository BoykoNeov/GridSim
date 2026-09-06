# M4 — Context

Where things live, what was decided and why, and what the dependency probes
actually measured. Companion to `m4-plan.md` (the how) and `m4-tasks.md` (the
checklist).

## Environment

Unchanged from M3 for every step run on the developer machine. **Step 2 was
written elsewhere**: a remote Linux session on 2026-09-02 with no Julia installed
and the Julia download and package hosts refused by the network policy, so nothing
from that session was executed — not the new tests, not the `[sources]` entry,
not the export-collision check. Everything it touched is marked in `m4-tasks.md`.

Otherwise unchanged from M3. Julia is on PATH via juliaup; the machine runs **Julia 1.12.6**
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

### D10 — The divergence read resamples nothing, because there is nothing to resample with

`m4-plan.md` step 2 offered two routes onto one grid: the solver's interpolant, or
a shared `saveat` grid fixed before the solve. **Only the second exists in this
repo, and that is a consequence of a decision both engines already took.** Their
integrators are built `dense = false`, `save_everystep = false` (a live run must
not grow without bound) with `calck = true` (step 1) — which keeps the
interpolation coefficients of the *current* step only. The instant a step closes
its interpolant is gone, and after `solve!` returns the only samples in existence
are the ones the caller's grid asked for, taken by `savevalues!` at the one moment
they are valid (D9).

So `divergence` (analysis/postprocess.jl) takes two series on one grid and
**refuses two grids** with a named error; there is no code path that draws a line
between two recorded samples. Three consequences:

- "Never straight-line between decimated samples" stopped being a rule someone
  must remember and became a property of the function.
- The plan's second anti-vacuity mutation ("swap the interpolant for straight-line
  resampling; a check must fail") cannot be performed on the function, because
  the function has nothing to swap. Its replacement measures what the refusal is
  worth instead: the same engine on a fine and a 10× coarser grid, the coarse run
  straight-lined onto the fine grid by hand in the test, must read outside the
  band. **Measured (2026-09-02): 2.85e-2 rad against a band of 8.45e-4 rad — 33.7×
  over**, departing at 0.42 s, which is the coarse span straddling the 0.5 s trip.
  The estimate `h²/8·(2πf)²·A ≈ 0.2·f²·A` predicted "tens of times over"; it was
  right, and the measurement is what now stands.
- The band is a **required** argument and `tolerance_band` derives it (step 1's
  `3·reltol·excursion`), so the "where do they part company" read (`t_depart`)
  cannot be taken against a band chosen after seeing the gap. The tests make the
  point the hard way: V4b's 4.4325 µHz physical residual is *invisible* at the
  default band and *located* once the tolerance is tightened past it. A
  divergence read is exactly as sharp as the band it is handed, and no sharper.

Recorded here as a decision because a later reader will want to "improve" the
function with an interpolating fallback for convenience, and this is the record
of why that convenience would put its own error into the one number the
milestone exists to produce.

## What step 2 found by reading (nothing was run *then*)

Everything in this section was established by reading the code, in a session with
no Julia. It was all executed on 2026-09-02 when step 2 was merged: 1870 / 102
green, the `names` intersection empty, and every number reconstructed from the
V4/V6 notes reproduced. The measurements are tabulated in `m4-tasks.md` step 2.
Two reconstructions worth naming, because M3 step 6 is the precedent for them
going the other way: V4b's inter-machine swing peak came back as 4.4325e-6 Hz at
t = 0.26 s under playback (the notes' figure to five figures), and V4c's end gap
as 0.85706 Hz (the derived closed form, at `1e-4`).

- **`lockstep_coi`'s reason for existing has expired.** Its comment says recorded
  series cannot be compared because the two recorders decimate independently and
  the channel sets differ. With `solve!` onto one `saveat` grid neither holds;
  `overlay_pair` in the tests is the recorded-series comparison it could not
  make. `lockstep_coi` stays — it also asserts live reads — but the next
  cross-fidelity test should be written the new way.
- **The M5 bullets carried in `m4-plan.md` need correcting before they are
  planned against.** `m5-prestudy.md` works them: the classical limit is frozen
  flux, not constant `Efd` (constant `Efd` with finite `T′do` is field-flux decay,
  a physical effect the oracle would then mis-read as a bug); and dynamic RL
  branches only avoid a DAE by adding bus capacitors whose µs time constants are
  a worse problem than the DAE. The recommendation is reversed to the algebraic
  network.
- **`ui/Project.toml`'s `julia = "1.10"` floor and its new `[sources]` entry do
  not agree** — the section is honoured from Pkg 1.11. Soft for now (the
  developer machine runs 1.12); flagged in step 5. The 2026-09-02 verification
  run does **not** close this: it exercised the honoured path on 1.12 only, so
  whether a 1.10 Pkg ignores the section or errors on it remains untested.

### D11 — The playback window takes solved series, and there is no third `launch`

`ui/src/playback_window.jl` is a **third window**, and it is a sibling of the
other two for a different reason than they are siblings of each other. `window.jl`
and `network_window.jl` differ because their *engines* accept different events.
This one differs because it is the other **execution mode**: `solve!` has already
finished, the whole trajectory exists as two plain vectors, and the only live
thing in the figure is where the reader put the cursor. So it carries no
`EventQueue`, no `RealtimeControl`, no `refresh!` throttle and no task — each of
those exists to manage a run in progress, and there is none.

Two things follow, and both were deliberate rather than incidental:

**The builder takes series, not a model.** `_build_playback_window` receives two
already-solved series plus the band. It cannot solve, cannot step and cannot
choose a grid, which is "render state is not simulation state" (SPEC §3) in the
strongest form available: the window is *incapable* of influencing the numbers it
draws. The pair-building is three lines (`_solve_overlay`) on top of `coi_model`,
the aggregate view the core already compiles down — so nothing here is a parallel
model, and **no core change was needed for this step at all** (core stayed at
1870 tests, byte-identical). That also matters for step 5, which owns the fresh
dependency re-resolve: a core change here would have meant doing that work twice.

**A different verb, not a third `launch` method.** Both execution modes run on the
same `NetworkModel`, so the model type cannot pick between them — and minting a
type purely to enable dispatch would be inventing a type to satisfy a pattern. The
core already draws this exact line by verb (`run_realtime!` against `solve!`), so
`ui/` mirrors it: `playback` and `playback_render`. `wait_for_close` gained a
`haskey(win, :control)` guard rather than a dummy control block on a window with
no loop to stop.

Three smaller shapes, each of which is a rule made structural rather than written
down:

  - **The cursor is an index, not a time.** A slider over *time* would need a value
    between two samples, and the only two ways to make one are the ways M4 already
    rejected: interpolate (there is no interpolant left — `dense = false` means a
    closed step's coefficients are gone, D10) or straight-line between recorded
    samples (measured at 33.7× the band, step 2). Indexing means every number the
    read-out shows is a recorded sample verbatim.
  - **The band is derived and displayed, never adjustable.** A window is exactly
    where step 2's discipline would die: a band slider lets a reader scrub, look at
    the gap, and then pick the band that puts the departure where they expected it.
    There is no such control — `widgets` has exactly one field. The band comes from
    `tolerance_band` on the solve's own `reltol` and is shown *with its
    derivation*, so it is auditable rather than magic. Exploring the tolerance
    means solving again on fresh engines, which re-derives the band with it.
  - **The gap panel is logarithmic with a stated floor.** The gap spans nine
    decades on a real run (1e-7 Hz before the event, ~1 Hz after), so a linear axis
    puts the band — and with it the departure — indistinguishably on the zero line;
    and `log10` of the same-series-twice case (an exact `0.0`) is `-Inf`. Floored
    at `band/10`, and the axis label says so, so nobody reads the flat bottom of
    the trace as data. **This was only visible in the PNG**, which is what
    render-before-claiming is for.

### D12 — The two tiers need not get the same events, and which ones they got is stated

The aggregate view has no branches, so `TripLine` has no `inject!` method on it at
all. `_solve_overlay` therefore takes **two** event lists — `perturbations` and
`aggregate_perturbations` — written out by the caller.

The rejected alternative was to filter the aggregate's list automatically, keeping
only events it has a `hasmethod` for. It reads well and it is wrong: a method
missing **by mistake** would then be silently reclassified as a fidelity boundary,
which is the one error this whole comparison exists to detect. A missing method is
better as a loud `MethodError` pointing at the real question, and the test suite
pins that (`@test_throws MethodError` on a line trip handed to both tiers).

`nothing` for either list means "the caller did not say": both unsaid gives the
shipped scenario; `perturbations` alone gives **both** tiers the same list (the
symmetric reading, which is the safe one); naming only `aggregate_perturbations`
is an `ArgumentError`, since a caller who names one has almost certainly not
thought about the other.

Because the lists can now differ, the figure has to say so, and it does — in
firebrick: *"events — THE TIERS DID NOT GET THE SAME ONES (swing tier's log: 1;
applied to the aggregate: 0)"*, with `[swing tier only]` on each unmatched row.
The marking is on the **instant**, not on the event: the swing side's list is the
engine's own log and the aggregate side's is the list of times something was
applied to it, so *"nothing was applied at this instant"* is a fact, while *"the
aggregate has no representation of this event"* would be an interpretation — and
on a tier simply not given an event it could have taken, the wrong one.

### What step 3 measured, and the number it stopped the window from promoting

**The first render shipped the wrong scenario, and the picture is what said so.**
Step 3 was built over the obvious default — a generator trip on
`three_machine_ring()`, step 2's own positive control for divergence. It renders
correctly and every number matches step 2's table to the digit. It is also a
**monotonic decline on both tiers with no swing anywhere in it**, and its 0.857 Hz
gap is V4c's derived settling-level difference: the aggregate keeps the tripped
machine's damping in its denominator and settles somewhere else. That is
bookkeeping. Meanwhile the window's own caption said the pair shows inter-machine
swings — a claim its shipped picture could not support, which is the exact failure
mode this milestone exists to catch, arriving through the front door.

The fix was to ship the scenario where the headline number **is** the lesson:

| scenario | band | max gap | ×band | when | at the end |
|---|---|---|---|---|---|
| `TripLine(:B3, :B1)` at 1.0 s (shipped default) | 3.227e-6 Hz | **1.0758e-3 Hz** | 333× | departs 1.02 s, peaks 1.48 s | decays to ~6 % of peak by 20 s |
| `TripGenerator(:G1)` at 1.0 s (the contrast) | 8.573e-3 Hz | **8.575e-1 Hz** | 100× | departs 1.580 s, peaks 59.08 s | **99 %+ of peak — it arrives and stays** |

The line trip is the clean case in every respect: the swing tier's centre-of-inertia
frequency rings at ~1 Hz and decays, the rotors pull 0.28 rad apart, and the
aggregate tier sits at **exactly** 50.0 Hz for all 1001 samples because it was
handed nothing at all. The whole gap is then residual swing content and nothing on
the screen competes with it. Both figures are checked in
(`docs/images/fig-m4-playback-line-trip.png`,
`docs/images/fig-m4-playback-generator-trip.png`, regenerated by
`ui/scripts/playback_overlay.jl`) precisely because the contrast is the finding: a
doc that claims the tiers part company over swings, illustrated by the figure where
they part company over something else, is the promotion again.

**The swing residual survives the tolerance moving, which is what makes it a
result.** M3's standing rule — a number below the solver's own tolerance is not a
result until it survives the tolerance changing — applied to a new scenario before
the band was trusted. Solving the pair at reltol `1e-3`, `1e-6` and `1e-9`:

| reltol | band | max gap | t_max | t_depart |
|---|---|---|---|---|
| 1e-3 | 3.2275e-6 | 1.0758275e-3 | 1.48 s | 1.02 s |
| 1e-6 | 3.2276e-9 | 1.0758606e-3 | 1.48 s | 1.02 s |
| 1e-9 | 3.2276e-12 | 1.0758606e-3 | 1.48 s | 1.02 s |

The band falls by six orders while the gap is stable to seven significant figures
and both instants do not move at all. It is physics, not solver error — the
opposite of V4b's µHz residual, which was *invisible* until the band dropped
beneath it (step 2). The two together are the same lesson from both sides: a read
is exactly as sharp as the band it is handed.

**Three anti-vacuity mutations were run against the source, and each was caught by
exactly the assertion built for it** (M3's standing rule: run the mutation, do not
merely ship its in-suite form):

  - cursor reads sample `k+1` instead of `k` → caught, **and by the `===` check
    alone**. Adjacent samples differ by ~1e-6 Hz, so any `atol`-based version of
    that assertion would have passed. Nothing here is interpolated, so exactness is
    available, and it is the only thing that catches the one bug this window can
    really have.
  - `asymmetric = false` (the picture never flags a mismatched event list) →
    caught, on both the flag and the drawn label's text.
  - the caption `Label` built into a different `Figure` — it exists, it has the
    right text, it is simply not in the window → caught **only** by the layout
    check. All six of the caption's text assertions still passed while it was
    absent from the picture. That is M3 step 7's "a check that reads the log where
    it should read the picture", demonstrated rather than remembered, and it is why
    `in_layout` walks nested `GridLayout`s and why the suite carries a control that
    `in_layout` can return `false`.

**Smaller things the step turned up:**

- The recorder's decimation cannot desynchronise the two tiers' grids. Both engines
  default to the same 200 000-sample capacity and playback records exactly one
  sample per `saveat` point in each, so `n_seen` and therefore the retention stride
  are identical. Checked before the window was written, because if it were not
  true the window's constructor would throw on any long horizon. `divergence`'s
  refusal remains the backstop.
- The read-out and the picture are pinned to one arithmetic: `maximum(win.gap) ===
  win.read.max` and `win.t[argmax(win.gap)] === win.read.t_max`, to the bit, so the
  panel and the summary cannot come to disagree about where the largest
  disagreement is.

### D13 — `Library.Swing` is the oracle, not `Library.ClassicalMachine`

**A deviation from `m4-plan.md` step 4 and `m5-prestudy.md` §7, made on a
measurement.** Both documents name `ClassicalMachine` as "our fidelity, someone
else's implementation". Reading PowerDynamics' source before writing the builder
showed that description fits a different component.

`src/Library/Machines/Swing.jl` is:

    Dt(θ)   ~ ωbase*(ω − ωframe)
    M*Dt(ω) ~ Pm − D*(ω − ωset) − Pel
    terminal.u_r ~ V*cos(θ);   terminal.u_i ~ V*sin(θ)

With `ωframe = ωset = 1`, `M = 2H` and `ω_PD − 1 = ω_ours`, that is
`swing_vertex!` line for line — **including the constant voltage magnitude AT THE
BUS**, which is the one representational choice the tier note at the head of
`src/model/network_model.jl` says our model makes and "E′ behind X′d" does not.
`ClassicalMachine` is the E′-behind-X′d model, i.e. the thing that tier note
spends forty lines explaining we are NOT.

Three consequences, and the second changes the step's shape:

- **The band collapses to solver error.** Nothing about the formulation differs,
  so a gap is an implementation difference and nothing else. That is the oracle
  D2 asked for — the one that can say "our engine is correct", rather than one
  whose disagreements have two possible causes.
- **The meshed ring becomes a valid oracle case.** `m5-prestudy.md` §7's "the ring
  is not a valid oracle case and must not be used as one" is a statement about the
  *radial reduction*, which is what fails on a degree-2 machine. `Swing` needs no
  reduction, so the ring — and specifically **M4 step 3's shipped default
  scenario**, `TripLine(:B3, :B1)` — goes through the external oracle. The window's
  caption claims a physics lesson; this is what says the physics underneath it is
  not our own arithmetic agreeing with itself.
- **`ClassicalMachine` is kept, as the SECOND comparison**, and it earns its place
  by answering a different question (D14). It is not the bug-detector.

The plan's instinct was not wrong about wanting a formulation difference — it was
wrong about which component carries it, and the correction cost an afternoon of
reading source instead of a milestone of unattributable gaps.

### D14 — `ClassicalMachine` takes a TORQUE where we take a POWER

`m5-prestudy.md` §7 lists three convention questions to settle before any band is
written: reactance placement, damping convention, and the `H` base. All three were
answerable from PowerDynamics' source and **all three come out our way** (`X′d`
reduces exactly on a radial pair; damping is `D·(ω−1)` with `ω` per unit; `H` is on
the base the component is given). There is a **fourth**, and nothing on the plan
had it. `src/Library/Machines/ClassicalMachine.jl`:

    2*H * Dt(ω) ~ τ_m / ω − τ_e − D*(ω−1)

The mechanical input is a **torque, divided by speed**. Ours is a **power**, flat.
The difference is `τ_m·(1/ω − 1) ≈ −Pm·Δω`: it acts exactly like a change in
damping, it is proportional to the machine's loading, and it is **identically zero
at ω = 1** — so no flat run, no fixpoint check and no steady-state identity can
see it. It is visible only in a transient, which is the one place a band gets
chosen carelessly.

**It is identified by its signature, not bounded by a tolerance** (M3's rule).
Two independent forms of the same claim ship as tests:

- **A closed form.** After `TripGenerator(:G1)` on a radial pair the survivor is
  alone — no coupling, constant mechanical input, first order in `ω` — so both
  sides have a closed-form settling speed, and they are *different* closed forms:
  ours `Δω = τ/D`, theirs the root near 1 of `D·ω·(ω−1) = τ`. On
  `two_machine_system()` that is −0.075000 against −0.081670, and each side lands
  on its own to three figures. An attribution, not merely a disagreement.
- **Linearity in loading.** With the pair kept COUPLED by a mechanical-power step
  (so the run exercises the `X_line = X − X′d,ᵢ − X′d,ⱼ` reduction rather than two
  isolated rotors), the residual falls by a decade for every decade of loading,
  over two decades, while the `Swing` residual does not move at all and stays at
  the solver floor.

**And that linearity is what proves the reduction exact.** If
`X_line = 0.25 − 0.100 − 0.075 = 0.075` were even slightly wrong there would be a
residual left over that does *not* vanish with loading, and the ratios would
flatten toward 1 as the torque term shrank beneath it. None survives at the 1e-12
floor. The reduction is confirmed by a measurement rather than by the algebra
alone — and since `X′d` reaches the comparison only through `machine_arrays`'
**inverse** weight, that one per-unit conversion is externally checked while `H`,
`D` and `Pm` are not (below).

## What step 4 measured, and the claim it stopped the step from making

**The band could not be `tolerance_band`, and the reason is not a fudge factor.**
M4 step 2's `3 · reltol · excursion` is the right derivation for two runs of the
*same* engine: one relative tolerance, one solver, one state set. Here the two
sides are an explicit Runge–Kutta (`Tsit5`, three states per machine, closed-form
coupling) against a stiff Rosenbrock (`Rodas5P`, two states per bus, a
complex-voltage current balance). They control *local* error on different
quantities and accumulate different *global* error over the horizon. Measured over
five decades of tolerance on the ring, the ratio of the gap to `tolerance_band`
runs **5.2 → 12.8 → 15.3 → 6.2 → 4.7** and does not settle. Choosing a factor to
cover that is fitting a constant to the very gap it is meant to judge.

So the band comes from the triangle inequality instead —
`|a − b| ≤ |a − truth| + |truth − b|` — with each side's error estimated by **its
own** convergence, `|run(reltol) − run(reltol/1000)|`. Neither term ever looks at
the other implementation, so "state the band before you see the gap" stops being a
discipline and becomes a property of the arithmetic. `oracle_band` is that, and
the cross gap comes out at **0.30–0.33 of it** at reltol 1e-3, 1e-5 and 1e-7
alike. Sitting below even `factor = 1` is itself informative: the two errors partly
cancel, so their sum overestimates their difference.

**The oracle is the less accurate of the two, and now that is a number.** D7 says
the oracle is a floor rather than a ceiling; the self-convergence terms say by how
much. `err_theirs / err_ours` is 3.5 at reltol 1e-3 and 18 at 1e-7 — at matched
tolerance PowerDynamics' run of this problem is between three and twenty times
further from the truth than ours.

**What the oracle CANNOT check, which is most of the D7 label list.** The case is
compiled from `NetworkModel` (D5), so both sides read the same `machine_arrays`,
`branch_arrays` and `_coupling`. Invert the weight in `machine_arrays` — `m.H / w`
for `m.H * w` — and both sides integrate `H = 1.6` instead of `10.0` and agree to
1e-12. The oracle is blind to everything upstream of the fork. That is the price
of not hand-maintaining a parallel model, it is the right price, and it means:

| checked by | what |
|---|---|
| **PowerDynamics, externally** | the coupling formula and its SIGN; the graph/edge mapping; `find_fixpoint`'s answer being an equilibrium of an independently formulated network; the event semantics (`TripLine`, `TripGenerator`) reaching both sides identically; the COI read-out's weighting; the integration itself |
| **PowerDynamics, via D14's signature** | `X′d`'s inverse per-unit weight — the one conversion the transient comparison does reach |
| **M1/M2 closed forms only** | the `H`, `D` and `Pm` conversions in `machine_arrays`; `K = E′ᵢE′ⱼ/X` as a *formula* (both sides are handed the same `K`) |
| **un-oracled, and stated** | the aggregate governor lag `Tg` (M3's, unchanged); the `ΔPm` governor state, which neither PowerDynamics tier can express and which `build_oracle` therefore REJECTS rather than silently dropping |

The last row is why `build_oracle` throws on a governed model. A silently
ungoverned oracle would read as a physics disagreement, which is the one thing
this package exists not to produce.

**Consequently the anti-vacuity mutation must be made in `swing_vertex!`.** A
mutation in the shared data path propagates to *both* sides and every check in
`reference/test/runtests.jl` goes green against a real bug. Scaling `D` is the
mutation to make: the equilibrium is at `ω = 0` either way, so the flat run still
passes and only the transient diverges — which is what proves the transient checks
are the ones doing the work.

**Run, and the pattern is the prediction rather than merely "it went red":** 64
pass / 18 fail, with the four testsets that integrate nothing (preconditions, the
flat run, the band derivation, the D7 label list) all fully green and every
transient comparison failing. The band testset staying green is worth a sentence
of its own — `oracle_band` is built from the *mutated* engine's own convergence,
so it does not widen to swallow the error it is supposed to expose, which is the
property that makes a self-derived band safe. Per-testset breakdown in
`m4-tasks.md` step 4.

**Two mechanics of PowerDynamics worth carrying forward.** `set_Sbase!` and
`set_fbase!` are process-global and are read at component *construction* time, so
`build_oracle` sets both from the model it was handed on every call; both repo
fixtures are 100 MVA / 50 Hz, so the test that this happens uses a 250 MVA / 60 Hz
fixture and **poisons the global to 50 Hz first**, or it would pass against a
builder that never set them at all. And `PiLine`'s `active` parameter is what a
`TripLine` maps onto — a scheduled parameter change on their side against a
scheduled parameter change on ours, which is the same mechanism rather than two
mechanisms that have to be argued equivalent.
