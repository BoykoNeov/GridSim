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

## Steps 3–4 — the swing engine (DONE), and the three things they settled

Landed as three commits, deliberately in this order.

### The trajectory recorder went first, alone

`src/engines/recorder.jl` — a shared, fixed-capacity `TrajectoryRecorder` that
**decimates** when it fills (halve the buffer, halve the sampling rate from then
on) rather than dropping the oldest sample. A ring buffer is the obvious choice
and the wrong one here: the initial rate of change and the frequency nadir both
happen in the first seconds after a disturbance, so keeping "the most recent
N samples" would discard exactly the headline numbers and retain a flat settled
tail. Decimation keeps the whole run at progressively coarser resolution with the
start never lost.

It landed on its **own commit, with M1's engine retrofitted onto it and no new
engine alongside**. The reasoning is about oracles, not tidiness: M1 has hundreds
of tests that exercise trajectories and `SwingEngine` had none, so M1's suite was
the only thing in the repo capable of finding a bug in the recorder — and it could
only do so if nothing else changed in the same commit. Bundled with the new engine,
a failure would have been ambiguous between "recorder wrong" and "swing model
wrong", and the wrong one would have been debugged first.

Two rules the design turns from incidental into binding:

  - **Time is a mandatory channel.** Decimation changes the effective sample
    interval mid-run, so anything that finite-differences the series, or plots it
    against an implied step, breaks silently after the first halving. The
    constructor prepends `:t` itself and *refuses* to be handed one, which makes
    "a recorder without a time base" unrepresentable rather than merely discouraged.
    (`windowed_rocof` already divided by the actual elapsed time rather than the
    nominal window, so it was decimation-safe by habit before it had to be.)
  - **Running summaries are tracked outside the buffer.** `minimum(series.f)` is
    the lowest *retained* sample, not the lowest that occurred. Pinned by a test
    that runs the same scenario at capacity 64 and at 200 000: the reported nadir is
    identical, while the small buffer's retained minimum sits strictly above it.

Retention invariant: sample `n` is kept iff `(n-1) % keep_every == 0`, with the
keeper test **re-applied after a halving** — doubling the stride can disqualify the
very sample that triggered it, which is where odd capacities break if you push
blindly. Swept over capacities 2/3/4/5/8/9 × 200 pushes.

### FINDING — the `SimulationEngine` contract held, with one strain worth naming

M1 had a single engine, so `src/engines/interface.jl` had never been asked to hold
a second. It needed **no changes**, and that is asserted in `test/` rather than
claimed here: every verb resolves on `SwingEngine`, and `init!` dispatches on the
engine *type* exactly as M1's does (the construction chicken-and-egg — a struct
parametric on types that only exist once the integrator does — resolves the same
way).

The one place it strains is **`state_series`**. M1 returns a fixed set of aggregate
channels; `SwingEngine` returns one channel per machine angle, one per machine
speed, plus the aggregate — a shape that depends on the model. Both satisfy what
`interface.jl` actually states ("a NamedTuple of named, equal-length series"), and
both lead with `:t`, so a consumer that reads channels **by name** works against
either. A consumer that assumes a *particular* set of channels does not. This is
recorded as a property of the abstraction rather than patched: the UI currently
calls `state_series` and `current_state` by name, so step 7 is where it has to be
handled honestly instead of by widening the interface now on speculation.

### FINDING — graph edge order is not branch order, and V2 cannot catch it

`Graphs.SimpleGraph` iterates its edges in sorted `(src, dst)` order, **not** in
the order branches were added, and NetworkDynamics indexes edge parameters by
position in that list. On `three_machine_ring` the branches `[L12, L23, L31]` map
to graph edges `[1, 3, 2]`, so the natural-looking "branch *k* ↦ edge *k*" would
hand two of the three lines the wrong coupling.

What makes this worth a finding rather than a footnote is that **the planned
validation could not have caught it**. V2 recomputes each machine's electrical
power and checks it against the specified mechanical power — but `find_fixpoint`
converges happily on whatever self-consistent *wrong* network it is given, and
power recomputed from the same wrong couplings still balances. V1 passes too: a
wrong network still has a flat start. The mis-assignment would have survived every
acceptance criterion and shown up only as an oscillation frequency nobody had a
prediction for.

Two defences, because the structural one alone leaves nothing to test:

  - **Structural:** edge parameters are filled in a single pass over the graph's
    own edge list, looking each branch up by its (unordered) bus pair. There is no
    positional correspondence, hence no index that could be permuted.
  - **Asserted:** `branch_to_edge` (kept as the reverse map `TripLine` will need at
    step 5) is tested to be a permutation, and each edge is tested to hold the
    coupling of the branch joining its two buses. The ring's three couplings are
    all distinct, so the assertion bites; on a system with equal couplings it
    would not, which is itself a reason to keep the ring in the test set.

Edge *orientation*, by contrast, is harmless: `K` is symmetric and `K·sin` is
antisymmetric, so flipping an edge's ends flips the sign of a quantity that
`AntiSymmetric` was going to flip anyway.

### After a GENERATOR trip there is no equilibrium — stated so nobody "fixes" it

`NetworkModel` enforces `Σ P0 = 0` at construction, but losing a machine
deliberately breaks it, and the classical tier has no governors to make up the loss.
So afterwards there is **no fixpoint at all**: speed falls until damping balances the shortfall
(`ω_coi → ΣPm_remaining / ΣD`, matched to 1e-4 in `test/`), and because that limit
is non-zero every angle then grows without bound at a common rate. Angle
*differences* still settle. Two consequences worth carrying: never call
`find_fixpoint` on a post-trip state, and never assert on an absolute angle. A
**line** trip is the other case and does settle — see the step 5 section below.

The gauge point is separate and equally load-bearing — shifting every `δ` by the
same constant is still an equilibrium, so the fixpoint solver returns an arbitrary
offset (on the ring it lands near 2.1 rad, nowhere near zero). The test asserts the
**symmetry itself** — displace all angles by 0.7 rad and the residual is still zero
— rather than asserting wherever this particular solver run happened to land.

### V1 / V2 / V3, measured

  - **V1 flat start** — residual `6e-18` (two machines) and `2e-17` (ring) at
    `t = 0`; a 2 s pre-disturbance window does not move.
  - **V2 injections** — reproduce to `2e-16`, recomputed from the model's own
    couplings rather than from what the engine handed the solver. This is the
    sign-convention test: a flipped coupling still oscillates, still settles, and
    still has a nadir.
  - **V3 closed-form swing frequency** — the running engine measures
    **1.5909869 Hz** against the pinned prediction **1.5911075 Hz**, excited by a
    10 mrad angle displacement (not a trip — a trip removes the equilibrium the
    oscillation would be about) and averaged over every cycle in a 12 s window by
    interpolated zero crossings. The `1.2e-4 Hz` gap is the damping: the closed form
    is the *undamped* natural frequency, so the measurement must come out slightly
    low, and the test asserts the sign and bounds the size of that offset instead of
    widening the tolerance until it passes. Three wrong versions of the formula —
    dropping `cos δ₀`, using total system inertia, using one machine's inertia —
    are all asserted to land outside the tolerance; dropping `cos δ₀` is the near
    miss at `8e-3 Hz`, which is why the tolerance is `5e-4` rather than something
    comfortable.

### Smaller things these steps settled

  - **`ω₀` rides in the parameter vector, not in a closure.** Capturing it would
    make every model its own anonymous function type and force a recompile per
    system; as a parameter, all models share one compiled `Network` type.
  - **No `isoutofdomain` guard was copied from M1.** M1 has one to absorb overshoot
    above a bounded quantity. Nothing here is bounded — post-trip drift is intended
    — so a copied state guard would fire on correct behaviour and collapse the step
    size.
  - **Flat state positions come from NetworkDynamics' symbolic indexing**
    (`NetworkDynamics.SII`), resolved once at construction, so the engine never
    assumes a memory layout. A test round-trips them against a symbolic read, so an
    upstream layout change reports itself instead of quietly corrupting the physics.
  - **The shared-mutable-parameter pattern is inherited, and asserted.**
    `eng.params === eng.integrator.p` holds, as the spike predicted, so an event
    changes the system without disturbing the continuous state.
  - **`system_inertia` and `is_online` are reused verbatim** for the new engine —
    the same physical quantities under the same names, so the UI reads both engines
    through one API. `machine_ids` is the new per-machine counterpart, and both new
    exported names were checked clear against GLMakie before being added.

## Step 5 — events (DONE), and the two things it settled

`TripGenerator` shipped with the engine in step 3. Step 5 added `TripLine` and,
more importantly, the test that distinguishes calling the integrator-boundary
verbs from not calling them — the item the M1 lesson left owed.

`TripLine` names a branch by its **bus pair, in either order**, not by branch id.
That is not a style choice: the pair is what uniquely identifies a branch in this
tier, and the parallel-circuit guard in `network_model.jl` already justifies its own
existence partly on "`TripLine` could not name one of two circuits." A convenience
constructor taking a branch id was considered and dropped — a second way to name a
line is a choice the UI would then have to make, and it would pull a `NetworkModel`
dependency into an events file that has none.

`lines_online` is a tracked set, not `K != 0` read back. A **generator** trip also
zeroes the coupling of every branch at its bus, and those lines are still in
service — they simply have nothing left to carry. Inferring the one from the other
would report a healthy line as tripped the moment its neighbour's machine died.

### A line trip HAS an equilibrium — the sharper validation

This is the headline of step 5 and the reason it is worth more than the generator
trip as a test. Losing a machine breaks `Σ Pm = 0` and nothing settles (previous
section). Losing a **line** changes no `Pm` at all, so the surviving network still
has a steady state: every machine returns to `ω = 0` and the angle differences move
to a new equilibrium in which the remaining branches carry what the lost one used
to. Cutting one line of the ring leaves the radial path B1–B2–B3, whose steady
state is a chain of `asin`s that can be written down:

    δ₁ − δ₂ = asin(Pm₁ / K₁₂)              = 0.185998944 rad
    δ₂ − δ₃ = asin((Pm₁ + Pm₂) / K₂₃)      = 0.259628411 rad

Both couplings are read from `branch_arrays`, i.e. through the code path the engine
integrates against — the D8 finding is what a copied number costs. **Measured: both
to `1e-13`** after 240 s of simulated time, with every `|ω| < 1e-15`.

Two wrong versions are asserted to fall outside: charging L23 with machine 2's own
injection instead of the cumulative flow misses by `0.19 rad`, and using the wrong
branch's coupling for the L12 leg misses by `1.8e-3` — the near one, and what makes
a loose tolerance a real risk. The bound is `1e-9`, four orders below the near miss
and four above the measurement.

**Why 240 s and not 20.** The settling is far slower than the swing period. The
angle error is still `1.2e-2` at 20 s, `1.2e-3` at 40 s, `9.7e-5` at 60 s and only
reaches `1e-13` around 240 s. Running to 60 s and asserting `atol = 1e-4` would
have looked like a solver-tolerance allowance and been recorded as one; it is not.
That was checked directly rather than assumed — the same run at `reltol` `1e-3` and
at `1e-10` gives the *same* `-9.731e-5` error at 60 s, so the gap is settling
physics, not integration error. (The `reltol`/`abstol` pass-through written to
measure that was then removed: no test needed it once the answer was known, and
unused API on speculation is what this repo avoids.)

### FINDING — the two integrator-boundary calls are not separably observable

`inject!` calls `derivative_discontinuity!` (drop the FSAL solver's now-stale cached
derivative) and `auto_dt_reset!` (re-estimate the step size for the new dynamics).
The owed test was one that fails if they are not called. Measured, by running the
trip path with each call switched off:

| `derivative_discontinuity!` | `auto_dt_reset!` | first-step error vs the true derivative |
| --- | --- | --- |
| on  | on  | −0.01 % |
| off | on  | −0.01 % |
| on  | off | −0.01 % |
| off | off | **−9.7 %** |

Either call alone suppresses the entire bias, because `auto_dt_reset!` re-evaluates
the RHS as a side effect of re-estimating the step. So the effect test bites on
*omitting both* and cannot separate them. Recorded rather than papered over: the
test asserts what is measurable (realized first-step rate matches the analytically
evaluated RHS to `rtol = 2e-3`, against a `9.7 %` failure — a factor of ~50), and
**both calls stay in `inject!`**, because leaning on `auto_dt_reset!` to also refresh
the derivative cache is depending on an undocumented side effect of a package that
has already moved once under this repo's feet. What the test deliberately does not
do is assert on `integrator.dt`: that is an OrdinaryDiffEq internal whose read-back
semantics a minor bump can move, and a test that passes on a version's internal
bookkeeping passes for the wrong reason.

The test runs over **both** trip paths, `TripGenerator` and `TripLine`, which is
what the checklist item meant by "both".

### A line trip can split the grid, and the aggregate then lies

Cutting the only line of the two-machine system leaves two islands. This tier does
not refuse that — it is a real event, and the one the Iberian scenario is about —
but the single COI read-out stops meaning anything. Each machine runs until its own
damping absorbs its own injection (`ωᵢ → Pmᵢ/Dᵢ`): **+12 % and −7.5 %** on that
system, verified to `1e-7`. The aggregate is their inertia-weighted mean, **−1 %**,
which is neither island's frequency and is not zero either — it would be zero only
if the two machines happened to share an `H/D` ratio. The test asserts the derived
value and asserts it is *far* from both islands, because an assertion of "≈ 0"
would read as "nothing happened."

This is the same reason `NetworkModel` refuses to be *constructed* disconnected, now
showing up as a runtime consequence instead of a construction guard. It is also
step 6's problem in advance: `coi_model` compiles an aggregate view, and this is the
disturbance for which the aggregate view is meaningless.

### A second, independent bite on the edge-ordering hazard

At the instant a line opens, the machines at **its two ends** jump by `∓P/2H` while
every other machine's acceleration is exactly zero. Zero the wrong edge and the
untouched machine moves. Measured on the ring: `+2.65e-2` and `−1.27e-2` at the two
ends of L31, `1.9e-17` at machine 2. This is a genuinely new assertion rather than a
restatement of step 3's, because it tests the mapping *through a live event* rather
than at construction — and V2 still cannot catch it, for the reason recorded above.

### No new dependency surface

Step 5 adds no package and no new upstream name in `src/` — `derivative_discontinuity!`
and `auto_dt_reset!` were already reached for and already swept across both
resolutions in steps 3–4. The one new named reach is `integrator.f` in `test/`, to
evaluate the RHS analytically at the trip instant. So the two-resolution sweep from
step 3 still covers this step, and it was not re-run; the dev machine remains on the
fresh resolve (`SciMLBase` 3.49.1 / `OrdinaryDiffEq` 7.6.0), which is what a clean
clone gets.

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
- ~~**Where does the trajectory-buffer fix live?**~~ **RESOLVED —
  `src/engines/recorder.jl`**, decimating rather than a ring buffer, landed on its
  own commit with M1 retrofitted onto it before the second engine was written. See
  the steps 3–4 section above for why it went first and alone, and for the two
  rules it makes binding.
- ~~**Does the two-machine closed form survive the real `NetworkModel`?**~~
  **HALF-RESOLVED.** It survives, but only after the coupling itself was corrected
  (the finding above) — which is exactly the "one more layer where a convention can
  go wrong" this question was written to catch, and it did go wrong. The prediction
  is now re-derived through the real `machine_arrays`/`branch_arrays` and pinned in
  `test/`: `K = 4.284 pu`, `δ₀ = 0.140518 rad`, **`f_osc = 1.5911075 Hz`**. **Now
  FULLY RESOLVED**: the running engine measures `1.5909869 Hz`, the shortfall being
  the damping the undamped closed form omits (V3 above).
- ~~**The trajectory-buffer decision stops being deferrable at step 3.**~~ **DONE —
  it was step 3's opening commit**, exactly as this note demanded.
- **How does the UI consume two different `state_series` shapes?** Newly open, from
  the conformance finding above. The window currently reads `state_series` and
  `current_state` by name against M1's fixed channels; M2's are per-machine and
  model-dependent. Step 7 has to resolve this by reading channels by name, not by
  widening the engine interface now on speculation.
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
