# M2 — Context

Where things live, what was decided and why, and what the dependency spike
actually measured. Companion to `m2-plan.md` (the how) and `m2-tasks.md` (the
checklist).

## Environment

Unchanged from M1 (`m1-context.md` §Environment). Julia is on PATH via juliaup;
the machine currently runs **Julia 1.12.6** while the package `[compat]` floor
stays at 1.10. `Manifest.toml` is gitignored — this is a package, not a pinned
app — so resolved versions below are what *this* machine resolved, not a lock.

## State of the repo entering M2

M1 complete and committed: `FrequencyResponseEngine` (center-of-inertia frequency
and RoCoF), the real-time orchestration loop, the load-shedding ladder, the
post-processing reads, the ENTSO-E Iberian validation scenario, and the live
GLMakie window. 273 core tests and 33 UI tests green at `bb644f4`.

Core (`src/`) deps: `CommonSolve`, `Observables`, `OrdinaryDiffEq`, `SciMLBase`.
No Makie, enforced by a dependency-closure test with a positive control.

## The dependency spike (run before this plan was written)

Run in a throwaway project under `M:\claud_projects\temp\m2-spike`, never against
the repo. The plan's shape depended on the answers, so they were **measured, not
reasoned about**.

### Does it resolve?

| Package | Version | Note |
|---|---|---|
| `NetworkDynamics` | 1.1.0 | resolves against GridSim's existing `[compat]` |
| `Graphs` | 1.14.0 | |
| `PowerDynamics` | 5.0.0 | resolves, but see the weight below |

Adding NetworkDynamics to a copy of GridSim's `Project.toml` succeeded and moved
`OrdinaryDiffEq` 7.0.1 → 7.6.0 and `SciMLBase` 3.30.1 → 3.49.1 — **upgrades within
the existing bounds, not a downgrade**, and the spike exercised the whole
integrator API we depend on at those versions.

### The three gate criteria — all pass

Measured on a two-machine, one-line swing model built directly on NetworkDynamics:

```
flat start   : max|du| = 0.000e+00                                   PASS
steppable    : t after one 0.02 step = 0.0200                        PASS
swing freq   : closed form 2.0121 Hz, measured 2.0121 Hz             PASS
param mutate : Δδ 0.3047 -> 0.6435 (expected -> 0.6435)              PASS
p aliasing   : pflat(NWParameter(integ)) === integ.p : true          PASS
```

- **Steppable integrator.** `init(ODEProblem(nw, u0, tspan, p0), Tsit5())` then
  `step!(integ, dt, true)` works exactly as M1's engine already does — the
  integrator interface, not `solve()` (SPEC §6).
- **Live parameter mutation.** `NWParameter(integrator)` is an indexable view onto
  `integrator.p`; halving a line's coupling mid-run moved the relative angle to the
  new equilibrium `asin(P/K′)` to 4 decimal places. The pattern needs
  `auto_dt_reset!` **and** `derivative_discontinuity!`, same as M1's `inject!`.
- **Parameter aliasing survives.** `pflat(NWParameter(integ)) === integ.p` is
  `true`, so M1's shared-mutable-parameter identity carries over to M2 rather than
  having to be re-engineered.

A first run of the mutation check reported FAIL at `Δδ = 0.8713`. That was the
*check* being wrong, not the library: with zero damping the system orbits the new
equilibrium forever instead of settling. Re-run with damping it lands on 0.6435.
Recorded because "the test was wrong" is a conclusion that has to be earned, not
assumed.

### Steady state without a hand-rolled power flow

`find_fixpoint` (NetworkDynamics, NonlinearSolve underneath) was checked on a
**3-machine ring** with injections `[+0.8, +0.3, −1.1]`, i.e. a case with no
closed form to lean on:

```
find_fixpoint: max|du| = 1.388e-17                                   PASS
  angles (rad): [0.37808, 0.29359, 0.05699]
  bus 1: Pm=+0.8000  Pe=+0.8000
  bus 2: Pm=+0.3000  Pe=+0.3000
  bus 3: Pm=-1.1000  Pe=-1.1000
  injection check: PASS
```

Two things this settles. First, the swing model's **rotational symmetry** (shift
every angle by a constant and it is still an equilibrium) does *not* defeat the
solver — it picks a gauge and converges. Second, the injection check is exactly
the sign-convention test M2 needs: each machine's computed *electrical* power
equals its specified *mechanical* power. That check is cheap and it catches the
one bug that otherwise hides behind a plausible-looking oscillation.

## Key decisions (and why)

**D1 — Build on `NetworkDynamics`, alone. Not hand-rolled, not `PowerDynamics`.**
All three gate criteria pass, so the SPEC §4 tech-stack row holds up. But take
NetworkDynamics *without* PowerDynamics: ND alone added 7 packages to a GridSim-
shaped environment, whereas PowerDynamics pulls ModelingToolkit, Symbolics and
DataFrames — 123 packages, ~305 s of precompilation — to supply a component
library M2's single machine type does not need. Revisit when the component zoo is
actually wanted.

**D2 — Reduced classical tier: a pure ODE, not a differential-algebraic system.**
Constant voltage behind transient reactance, no bus voltages as unknowns. The DAE
version is the *next* tier and is what the full-electromechanical playback engine
does, which is precisely the roadmap-step-3 overlay. Fixing the tier boundary now
is what keeps M2 a physics batch instead of a solver batch.

**D3 — Sparse by construction; no admittance matrix is assembled at all.**
NetworkDynamics' graph *is* the sparse structure — coupling lives on edges, so
SPEC §4's "never build a dense Y-bus" is satisfied structurally rather than by
discipline. If network reduction ever lands (M2b), the full admittance stays
sparse and canonical and the reduced coupling is a derived compiled view.

**D4 — A new `NetworkModel`; `SystemModel` stays, and is *derived*.**
`SystemModel` cannot express M2 (no buses, no branches, no transient reactance, no
internal voltage), so M2 needs its own type. But hand-writing both would create
exactly the parallel hand-maintained model SPEC §3.2 forbids. So
`coi_model(net) -> SystemModel` compiles the aggregate view *down from* the
network model. This fixes the invariant and hands over the cross-fidelity
validation in the same move — same trip, both engines, tracking early and
diverging later, with no need for the heavy engine to see the lesson.

**D5 — No `PowerSystems.jl` yet.** SPEC §3.2 says "introduce it when the model
first needs buses and branches", which is arguably now; SPEC §9 puts it at roadmap
step 4. Take the roadmap's answer. Adopting it here turns M2 into half a
data-modelling batch and buries the physics payoff. Mitigation: choose
`NetworkModel`'s field semantics so they map onto PowerSystems concepts, and build
it through a function so `from_powersystems` can later be a sibling constructor.

**D6 — Steady state from `find_fixpoint`, not from a hand-rolled power flow.**
SPEC §8 forbids re-deriving math the ecosystem already has. Verified above.

**D7 — Trip by zeroing coupling, never by resizing the state.** Keeps the
integrator's continuous state intact across an event, which is the property that
made M1's live injection clean. The tripped machine's angle and speed keep
integrating harmlessly and are excluded from the aggregate read-out.

## Open questions to resolve during M2

- **Does the M1 suite still pass at `OrdinaryDiffEq` 7.6.0 / `SciMLBase` 3.49.1?**
  Unknown until step 1 runs. This is why the dependency bump is its own commit,
  before any M2 code.
- **Where does the trajectory-buffer fix live?** M2 introduces a second engine
  with the same unbounded-growth shape as M1's. It wants to be one shared
  recording facility, not two leaks — but designing that is a small refactor of
  working M1 code and should be decided, not drifted into.
- **Does the two-machine closed form survive the real `NetworkModel`?** The spike
  hard-coded its coupling `K`. Once `K` is computed from `E′` and reactances there
  is one more layer where a per-unit convention can go wrong; V3 must be re-derived
  against the real code path, not copied from the spike.
- **How much UI does M2 need?** Per-machine traces are clearly in scope; a network
  canvas with node positions is a different (and much larger) piece of work, and
  SPEC §3.5's render-state-is-not-simulation-state rule bites the moment it starts.

## Reference

- Spike scripts: `M:\claud_projects\temp\m2-spike\spike.jl` (two-machine gates)
  and `spike3.jl` (three-machine fixpoint). Temp, regenerable, not in the repo.
- NetworkDynamics docs worth reading before step 3: `mathematical_model.md`,
  `network_construction.md`, `initialization.md`, and the `cascading_failure.jl`
  example — the last one is the template for tripping a line by zeroing its
  coupling inside a callback.
