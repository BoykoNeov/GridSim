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
integrator API we depend on at those versions. (The real add behaved differently;
see below. The spike's copy had no `Manifest.toml`, which turned out to be the
whole explanation.)

## The dependency bump — what actually happened (step 1, DONE)

`Pkg.add(["NetworkDynamics","Graphs"])` against the real repo, and **`Pkg` wrote
the `[compat]` entries itself** (`Graphs = "1.14.0"`, `NetworkDynamics = "1.1.0"`)
— floor = version resolved at add time, exactly the convention M1's deps follow.
Nothing had to be hand-edited.

**The spike's version prediction did not hold, and the reason matters.** The real
repo already had a `Manifest.toml` pinning `OrdinaryDiffEq` 7.0.1, and Pkg
preferred the minimal change: it added the new packages and left the solver where
it was. The spike's copy had no manifest, so it resolved fresh and took the
newest compatible everything.

So **two resolutions exist in the wild**, and since `Manifest.toml` is gitignored,
a fresh clone gets the second one:

| | `OrdinaryDiffEq` | `SciMLBase` | M1 suite |
|---|---|---|---|
| existing manifest (this machine, incremental) | 7.0.1 | 3.30.1 | **273/273** |
| fresh resolve (what a clone gets) | 7.6.0 | 3.49.1 | **273/273** |

Both were run, not assumed, and a **baseline run before the add** (also 273/273)
makes the "after" numbers mean something. `derivative_discontinuity!` and
`successful_retcode` — the two SciMLBase internals M1 reaches for by name, and
precisely the kind of thing a minor-version move relocates — were checked to
resolve under *both*.

The lesson worth keeping: with a gitignored manifest, "what version does this
resolve to" has **two** answers, and the developer machine is systematically the
stale one. Test the fresh resolve, because that is what everyone else gets.

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

## Step 2 — the canonical network model (DONE), and the finding it produced

`src/model/network_model.jl`: `Bus`, `Branch`, `Machine`, `NetworkModel`, the
derived struct-of-arrays views `machine_arrays` / `branch_arrays`, and the two
example systems. 350 core tests green (was 273 entering M2), on the fresh resolve
as well as the incremental one — which are now the *same* resolution
(`OrdinaryDiffEq` 7.6.0 / `SciMLBase` 3.49.1 in both), so the two-answers hazard
from step 1 is currently dormant rather than gone.

### FINDING — "E′ behind X′d" is not realisable on a meshed network under D2 + D3

The plan (and the SPEC's fidelity-tier line) describes M2 as *"each machine is a
constant voltage `E′` behind its transient reactance `X′d`"*. Written naively,
that becomes a per-branch coupling

    K_ij = E′ᵢ·E′ⱼ / (X′dᵢ + X_ij + X′dⱼ)

and the first implementation did exactly that. **It is wrong on any topology where
a machine has more than one line.** A machine with two branches would have its one
internal reactance counted once per incident branch — one rotor, two internal
reactances, which is not a network that exists. It happens to be exact for
`two_machine_system` (both machines have branch degree 1) and wrong for
`three_machine_ring` (every machine has degree 2).

Doing it correctly means eliminating the terminal buses so a machine's `X′d` is
*shared* across all its ties — Kron reduction, which is precisely the network
reduction D3 rules out (it builds an admittance matrix) and precisely what M2b
owns. So under **D2** (pure ODE) and **D3** (no admittance matrix) there is no
exact meshed "E′ behind X′d" at all.

**Resolution (D8): M2a puts `E′` at the bus and does not fold `X′d` in —
`K_ij = E′ᵢ·E′ⱼ / X_ij`, the standard network-swing form.** This is exact on every
topology instead of exact on one. `Machine.Xd′` stays in the model as carried,
validated data: it is real machine data, it maps onto PowerSystems, and M2b's
terminal-bus elimination is what consumes it. `test/` pins this with a regression
check — multiplying every `X′d` by ten must not move any coupling by one bit.

Why this had to be caught *here* rather than by a downstream test: nothing
downstream can see it. `find_fixpoint` converges on any self-consistent coupling;
V2's injection check passes; V4 still tracks-then-diverges. It is the exact shape
already recorded in the Iberia notes as *numbers that look like results and are
not* — and `branch_arrays(net).K` is the literal value step 3 hands to
NetworkDynamics.

### Decision — parallel circuits are rejected, not supported

Two branches between the same pair of buses were legal on ids alone, but
`Graphs.SimpleGraph` **silently drops** the second edge — the second circuit's
coupling would vanish with no error — and step 5's `TripLine(from, to)` could not
name one of two circuits. Supporting them needs either a multigraph or merging
into one equivalent reactance; both are M2b decisions. The constructor rejects the
second branch on a pair with a message that says so.

### Other things step 2 settled

- **Machines are stored in bus order.** The constructor reorders whatever it is
  handed, so one index `v` addresses the vertex, its bus and its machine
  everywhere — the ordering step 3's `Network` will use. Tested by feeding the
  machines in reverse.
- **No governors in `Machine`** (no `R`, no `Pmax`): the classical tier holds
  mechanical power constant. This decides step 6 in advance — `coi_model` compiles
  to a *governor-free* `SystemModel` (`R = Inf`, `Pmax = P0`), which is what makes
  V4 honest: the two models then differ by inter-machine dynamics alone rather
  than by one of them having primary response the other lacks.
- **Loads are machines with negative `P0`.** No load type in M2a.
- **Constructor guards, all tested:** duplicate ids · unknown bus references ·
  a bus with no machine or with two (the tier boundary, made a loud error) ·
  parallel circuits · a disconnected network · `Σ P0 ≠ 0` (a lossless network with
  net injection has *no* equilibrium, so the steady-state solve would fail or
  drift) · `|P0ᵢ| > Σⱼ K_ij` (since `P = Σ K·sin Δδ`, an injection beyond the
  incident coupling cannot be delivered at any angle — necessary, not sufficient).
- **The per-unit split is the model layer's main hazard, and it is now in one
  place.** Machine data is per-unit on the machine's own base, network data on the
  system base — standard utility practice, and exactly where a conversion goes
  missing. `machine_arrays`/`branch_arrays` are the only converters. The example
  machines are deliberately rated *away* from `S_base` (250/400 MVA on a 100 MVA
  base) so a missing or inverted conversion changes the answer instead of hiding
  behind a weight of 1, and the tests assert against the wrong conversions by name.
- **Export names cleared against `GLMakie` before writing any of it** — the M1
  collision hazard. All 14 checked (including `SwingEngine`, `TripLine`,
  `coi_model` for later steps) are clear.

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

**D8 — `E′` at the bus; `X′d` carried, not folded into the coupling.** Forced by
D2 + D3, and the subject of the step-2 finding above. `K_ij = E′ᵢE′ⱼ/X_ij`.

**D7 — Trip by zeroing coupling, never by resizing the state.** Keeps the
integrator's continuous state intact across an event, which is the property that
made M1's live injection clean. The tripped machine's angle and speed keep
integrating harmlessly and are excluded from the aggregate read-out.

## Open questions to resolve during M2

- ~~Does the M1 suite still pass at `OrdinaryDiffEq` 7.6.0 / `SciMLBase` 3.49.1?~~
  **RESOLVED — yes, 273/273, in both resolutions.** See the bump section above.
- **Where does the trajectory-buffer fix live?** M2 introduces a second engine
  with the same unbounded-growth shape as M1's. It wants to be one shared
  recording facility, not two leaks — but designing that is a small refactor of
  working M1 code and should be decided, not drifted into.
- ~~**Does the two-machine closed form survive the real `NetworkModel`?**~~
  **HALF-RESOLVED.** It survives, but only after the coupling itself was corrected
  (the finding above) — which is exactly the "one more layer where a convention can
  go wrong" this question was written to catch, and it did go wrong. The prediction
  is now re-derived through the real `machine_arrays`/`branch_arrays` and pinned in
  `test/`: `K = 4.284 pu`, `δ₀ = 0.140518 rad`, **`f_osc = 1.5911075 Hz`**. The
  remaining half is step 4: the *running engine* has to measure that number.
- **The trajectory-buffer decision stops being deferrable at step 3.** M2's engine
  is where the second copy of M1's unbounded-growth pattern gets written, so step 3
  opens with deciding where the shared recording facility lives — not with writing
  the engine.
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
