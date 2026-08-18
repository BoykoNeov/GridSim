# M2 — Multi-machine classical (swing) model · Plan

Living document for the Milestone 2 implementation batch. Source of truth for the
*what/why* is `docs/SPEC.md` §9 (roadmap step 2) and the invariants in §3–4; this
is the *how*. Companion files: `m2-context.md` (where things live, decisions, and
the dependency spike that pinned them), `m2-tasks.md` (checklist).

M1 is complete (see the `m1-*` trio). M2 is the first **network-aware** tier: the
grid stops being one lumped rotating mass and becomes several machines that can
swing *against each other*.

## Goal

A real-time-steppable engine in which each machine carries its own rotor angle and
speed, coupled through an explicit network. Trip a generator or a line *while it
runs* and watch the machines swing against one another — the inter-machine
dynamics that M1's center-of-inertia model averages away.

The center-of-inertia model is not discarded: it becomes a **compiled view derived
from** the network model (`coi_model`), and running both through the same
disturbance is M2's headline validation — they track early and diverge later, and
the divergence is the lesson.

## Fidelity tier — say what this is and what it is not

M2 is the **reduced classical** tier:

- Each machine is a constant voltage `E′` behind its transient reactance `X′d`;
  the state is `(δ, ω)` per machine.
- Network coupling is algebraic *in closed form* — no bus voltages are carried as
  unknowns. That keeps the whole system a **pure ODE** (`Tsit5` still applies).
- The moment bus voltages become algebraic variables it is a
  differential-**algebraic** system, which is a solver batch, not a physics batch.
  That is deliberately the *next* tier (roadmap step 3, the full-electromechanical
  playback overlay) — not this one.

Naming the tier is the point: M2 is an intentional approximation with a stated
boundary, not a shortcut.

## Approach (incremental; each step commits and leaves tests green)

1. **Dependency bump first, in isolation — DONE.** `NetworkDynamics` v1.1.0 and
   `Graphs` v1.14.0 added; `Pkg` wrote their `[compat]` entries itself, matching
   the house convention (floor = version resolved at add time). The M1 suite was
   run **before** the add as a baseline and again after, and is **273/273 green in
   both of the two resolutions that exist in the wild** — see the *Dependency bump*
   section of `m2-context.md` for why there are two. The "no Makie in the core
   dependency closure" test gained the new deps as explicit positive controls and a
   wider negative (a transitive plotting dep would violate SPEC §3.1 without
   containing the string "Makie").
2. **Canonical network model** — `src/model/network_model.jl`: `Bus`, `Branch`,
   `Machine`, `NetworkModel`, plus `two_machine_system()` and
   `three_machine_ring()` examples. Engineering units at the boundary, per-unit
   inside (SPEC §6). Numeric arrays kept separate from topology/metadata (SPEC §4,
   the struct-of-arrays habit). Concrete field types only.
3. **The swing engine** — `src/engines/swing.jl`: the NetworkDynamics vertex model
   (one machine) and edge model (one branch), assembly into a `Network`, and
   `SwingEngine <: SimulationEngine` implementing `init!` / `step!` /
   `current_state` / `state_series` / `timestep` / `inject!`.
   **This is the first real test of the `SimulationEngine` contract.** M1 had one
   engine, so `src/engines/interface.jl` has never had to hold a second one.
   Confirm explicitly that `SwingEngine` needs **no changes** to `interface.jl` —
   and if it does, that is a *finding about the abstraction*, to be recorded as
   one, not a detail to be patched in passing.
4. **Steady-state initialization** via `find_fixpoint`, with the flat-start and
   injection assertions from *Validation* below wired in as tests **in the same
   step** — not after. A model initialised off-equilibrium rings from `t = 0` and
   produces a plausible oscillation that is pure artifact.
5. **Events.** Reuse `TripGenerator` (same event type, new engine method) and add
   `TripLine(from, to)`. Both are realised by **zeroing coupling parameters, never
   by resizing the state vector** (see Pitfalls).
6. **Derive the COI view** — `coi_model(net::NetworkModel) -> SystemModel`, so M1's
   `FrequencyResponseEngine` runs on a model *compiled down from* M2's rather than
   a hand-maintained parallel copy (SPEC §3.2). The cross-fidelity comparison test
   (V4) falls out of this for free.
7. **UI** — extend the window with per-machine rotor angle / speed traces and the
   COI overlay. Verified offscreen first, as in M1.

## Validation (assert in `test/`)

Every one of these was exercised in the dependency spike before being written
down; the numbers in `m2-context.md` are measured, not predicted.

- **V1 — flat start.** At `t = 0`, `max|du| < 1e-10`, and a 2 s pre-disturbance
  window stays flat. This is an *acceptance criterion*, not a nicety.
- **V2 — injections reproduce, i.e. the sign convention is right.** At the
  fixpoint, each machine's *computed electrical* power equals its *specified*
  mechanical power to `1e-8`. A sign flip in the coupling still oscillates, still
  settles, still has a nadir — this is the test that catches it.
- **V3 — closed-form swing frequency (two machines, one line).** Linearising the
  relative angle `Δδ = δ₁ − δ₂` about `δ₀ = asin(P/K)` gives
  `d²Δδ/dt² = −ω₀·K·cos δ₀·(1/(2H₁) + 1/(2H₂))·Δδ`, so
  `f_osc = sqrt(ω₀·K·cos δ₀·(1/(2H₁)+1/(2H₂))) / 2π`.
  Derived from *our own* per-unit equations, not a remembered formula — the
  `2H/ω₀` convention is exactly where remembered formulas go wrong.
- **V4 — cross-fidelity against the derived COI model.** Same trip, both engines.
  Assert **both** halves: the COI frequencies agree early (they must track), and
  they diverge later (they must not be identical). Asserting only the agreement
  lets the test pass vacuously if `coi_model` ever returns something trivial.
- **V5 — no dense network matrix.** Needs care, because under D3 the engine never
  assembles *any* admittance matrix, so "assert it isn't dense" is a checkbox that
  cannot fail — the same vacuous-test trap V4 is written to avoid. The honest
  version is a **structural** claim with teeth: assert the engine's construction
  path allocates nothing that scales as machines², and state in the code comment
  that SPEC §4's rule is satisfied *by construction* (coupling lives on graph
  edges) rather than by a runtime check. If that assertion cannot be made to bite,
  drop V5 and say so here — a test that cannot fail is worse than an absent one,
  because it reads as coverage.

## Pitfalls / carried-forward review notes

- **Flat start is load-bearing.** M1's state was *deviations* from equilibrium, so
  it started at the origin by construction and could not get this wrong. M2 carries
  absolute angles and must be placed on a real operating point. Getting it wrong
  produces a plausible-looking oscillation that is pure initialization artifact —
  the same failure mode already recorded in the Iberia notes as "numbers that look
  like results and are not".
- **Rotational symmetry: angles are only defined up to a common offset.** Shift
  every `δ` by the same constant and it is still an equilibrium, so `find_fixpoint`
  picks an arbitrary gauge. **Test angle *differences*, never absolute angles.**
- **Tripping must not resize the state vector.** Zero the machine's coupling (its
  incident branch parameters and its mechanical power) and leave `(δ, ω)` in the
  state. Resizing mid-integration forces an integrator re-init and throws away the
  continuous-state-carries-through property that made M1's live injection clean.
  The tripped machine's `(δ, ω)` keeps integrating harmlessly and is excluded from
  the COI read-out.
- **Re-earn the shared-mutable-parameter pattern.** M1's `eng.params ===
  eng.integrator.p` identity is what lets an event change the system without
  disturbing the continuous state. NetworkDynamics' parameter object is not ours —
  the spike verified that `pflat(NWParameter(integrator)) === integrator.p`, so the
  pattern survives, but it is *inherited*, not assumed. Parameter changes still
  need `derivative_discontinuity!` **and** `auto_dt_reset!`.
- **Per-machine `ω` is not M1's `Δω`.** Each machine has its own per-unit speed
  deviation; the system frequency is the inertia-weighted mean
  `ω_coi = Σ Hᵢ·ωᵢ / Σ Hᵢ`. Conflating the two is an easy and silent error.
- **No hand-rolled power flow.** SPEC §8 forbids re-deriving math the ecosystem
  has. `find_fixpoint` (NetworkDynamics, NonlinearSolve underneath) supplies the
  steady state. Writing the ~40-line textbook swing right-hand side is *not* a
  violation of that rule — §8 is about integrators and power-flow/dynamics math,
  not about a local model equation.

## Out of scope for M2

`PowerSystems.jl` as the canonical data model (roadmap step 4, not here — adopting
it now makes M2 half a data-modelling batch and buries the payoff) · AC power flow ·
the differential-algebraic / bus-voltage tier · the full-electromechanical (PSID)
playback overlay (roadmap step 3) · load buses with constant-impedance loads and
network reduction (a natural M2b, deliberately not M2a) · markets/OPF · maps.

## Carried over from M1, still open

- **Unbounded trajectory growth in the core.** The engine appends to its
  trajectory vectors on every step forever. The UI is insulated (it draws from its
  own fixed-size buffers), but the core-side ring buffer / decimated history is
  still owed. M2 adds a second engine with the same shape — **fix the pattern once,
  in a shared place, rather than duplicating the leak.**
- Report Figure 3-67 as a layout target — still open, still ticks no acceptance
  criterion.
