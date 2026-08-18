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

- Each machine is a constant-magnitude voltage `E′` **at its bus**, whose angle is
  the rotor angle; the state is `(δ, ω)` per machine. Branch coupling is
  `K_ij = E′ᵢ·E′ⱼ / X_ij`.
  **Corrected during step 2** (D8; write-up in `m2-context.md`): this bullet used
  to read "`E′` *behind* `X′d`", which cannot be realised on a meshed network under
  the two decisions below — folding the end reactances into each branch
  double-counts the internal reactance of any machine with more than one line, and
  folding them in correctly is the terminal-bus elimination that would build an
  admittance matrix. `Machine.Xd′` is carried and validated for M2b, not used by
  M2a's dynamics.
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
2. **Canonical network model — DONE.** `src/model/network_model.jl`: `Bus`,
   `Branch`, `Machine`, `NetworkModel`, the derived struct-of-arrays views
   `machine_arrays`/`branch_arrays`, `two_machine_system()` and
   `three_machine_ring()`. 350/350 core tests green. The batch's finding is the
   coupling correction (D8) described in the tier section above; the per-unit split
   (machine data on the machine's base, network data on the system base) is
   confined to the two array functions, and the example machines are rated away
   from `S_base` so a missing conversion changes the answer instead of hiding
   behind a weight of 1.
3. **The swing engine — DONE.** `src/engines/swing.jl`. Step 3 opened, as planned,
   with the shared trajectory recorder on its own commit (see "Carried over from
   M1" below). **The contract held: `interface.jl` needed no changes**, and that is
   asserted in `test/` rather than asserted here. The one strain is `state_series`,
   whose channel set now differs per engine — recorded as a finding in
   `m2-context.md` and left for step 7, not papered over by widening the interface
   on speculation. The batch also produced a hazard the plan had not named: graph
   edge order is not branch order, and **V2 provably cannot catch the resulting
   mis-mapping**, so it needed a structural defence *and* its own assertion.
4. **Steady-state initialization — DONE.** `find_fixpoint`, with V1/V2 in the same
   commit as the engine (it cannot be smoke-tested without a start state) and V3 in
   the next one. Measured: V1 residual `6e-18`/`2e-17`, V2 to `2e-16`, V3 the
   running engine at **1.5909869 Hz** against the pinned **1.5911075 Hz** — the gap
   being the damping the undamped closed form omits, whose sign and size the test
   asserts rather than absorbing into a loose tolerance.
5. **Events — DONE.** `TripGenerator` shipped with the engine in step 3;
   `TripLine(from, to)` lands here. Both are realised by **zeroing coupling
   parameters, never by resizing the state vector** (see Pitfalls). The headline is
   that a *line* trip, unlike a generator trip, leaves `Σ Pm = 0` intact and so has
   an equilibrium — on the ring a closed-form chain of `asin`s, hit to `1e-13`. Two
   findings recorded in `m2-context.md`: the two integrator-boundary calls are not
   separably observable (either alone suppresses the whole 9.7 % first-step bias, so
   the test asserts omitting both), and a line trip that splits the grid leaves the
   single aggregate read-out meaningless — +12 % / −7.5 % islands reported as −1 %.
6. **Derive the COI view — DONE.** `coi_model(net::NetworkModel) -> SystemModel` in
   `src/model/network_model.jl`, so M1's `FrequencyResponseEngine` runs on a model
   *compiled down from* M2's rather than a hand-maintained parallel copy (SPEC §3.2).
   The mapping's one trap is an asymmetry — `H`/`S_rated` pass through raw because
   `aggregates` weights them itself, while `D` is summed *after* conversion because
   `SystemModel.D` is already a system-base scalar — and both halves are asserted
   against the wrong conversion by name. The batch's finding is that **the plan's
   description of V4's divergence was wrong**: on the shipped ring the late gap is
   dominated by M1's damping constant not shrinking when a machine trips, not by
   inter-machine swings. V4 therefore runs three cases (below) instead of one, and
   the swing content is isolated on a fixture built for it: **4.4 µHz reaching the
   aggregate out of a 3.9 mHz machine-to-machine spread.**
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
- **V3 — closed-form swing frequency (two machines, one line).** With
  `K = E′₁E′₂/X` (D8), linearising the relative angle `Δδ = δ₁ − δ₂` about
  `δ₀ = asin(P/K)` gives
  `d²Δδ/dt² = −ω₀·K·cos δ₀·(1/(2H₁) + 1/(2H₂))·Δδ`, so
  `f_osc = sqrt(ω₀·K·cos δ₀·(1/(2H₁)+1/(2H₂))) / 2π`.
  Derived from *our own* per-unit equations, not a remembered formula — the
  `2H/ω₀` convention is exactly where remembered formulas go wrong. Step 2 pinned
  the prediction `two_machine_system` implies, computed through the real
  `machine_arrays`/`branch_arrays`: `K = 4.284 pu`, `δ₀ = 0.140518 rad`,
  **`f_osc = 1.5911075 Hz`**. Step 4's job is to make the running engine hit it.
- **V4 — cross-fidelity against the derived COI model. DONE, in three cases.** One
  case cannot separate the two independent reasons the models differ, which is what
  the step-6 finding is about. Both engines are driven through the same trip in one
  **lockstep loop** over the live `current_state` reads — not over `state_series`,
  whose channel sets differ per engine and whose recorders decimate.
  - **V4a, exactness.** The swing model's COI obeys `2ΣH·dω_coi/dt = ΣPm − ΣDᵢωᵢ`
    exactly (lossless branches ⇒ the network terms cancel), which is *literally*
    M1's equation when the tripped machine has `D = 0` and the survivors share
    `D/H`. On a fixture built that way the two agree to **7.1e-15 Hz over 60 s**.
    This is the sharpest test of the mapping: a missing weight on `D` throws the
    settling frequency out by 20/6.
  - **V4b, the swing content, isolated.** Same fixture with the survivors' `D/H`
    unequal: identical at `t = 0` and at `t = ∞`, differing only in the transient.
    **4.4325e-6 Hz peak at 0.26 s** against a **3.9 mHz** machine-to-machine spread
    — a factor of ~900 averaged away, and the *ratio* is what is asserted.
  - **V4c, the shipped ring.** Tracks early (3.0e-4 Hz at 0.1 s), diverges late
    (0.857 Hz), ratio ~2800 — and the late gap is asserted as a **derived** number
    (`ΣPm_online/Σ_online D` against `ΣPm_online/Σ_all D`), not as a band.
  Asserting only the agreement would let the test pass vacuously if `coi_model` ever
  returned something trivial; V4a's exactness is instead guarded by asserting the
  disturbance is real (frequency falls to 47.4 Hz, machines genuinely spread apart).
- **V5 — no dense network matrix. DONE, as counts.** Under D3 the engine assembles
  no admittance matrix at all, so "assert it isn't dense" is a checkbox that cannot
  fail — the same vacuous-test trap V4 is written to avoid. The version with teeth
  is a count: `length(params) == 4n + m`, `length(integrator.u) == 2n`,
  `sum(length, incident) == 2m`, nothing two-dimensional in any field, and the
  engine's entire array storage measured at n = 4/10/40 → **69 / 171 / 681
  elements, exactly 17n + 1**, asserted linear by equal slopes. The positive control
  is a number rather than a claim: at n = 40 the whole engine holds 681 elements
  while one dense Y-bus alone would be 1600. The first three assertions also cover
  NetworkDynamics' own flat arrays, which the engine shares; the interior of the
  compiled `Network` is out of reach, and there D3 holds by construction.
  **`Base.summarysize` scaling was measured as an alternative and dropped** on the
  licence this bullet used to give: the compiled network's fixed per-machine
  overhead is ~2.4 kB, so a dense n×n does not overtake it until n ≈ 300 and the
  bound would have passed without discriminating.

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

- ~~**Unbounded trajectory growth in the core.**~~ **CLOSED at the head of step 3**
  (`src/engines/recorder.jl`), on its own commit with M1 retrofitted onto it and no
  new engine alongside — M1's suite is the only thing in the repo that can find a
  bug in the recorder, and it can only do so if nothing else changed. Decimating,
  not a ring buffer: the nadir and the initial slope live at the *start* of a run.
  See the checklist entry in `m2-tasks.md` for the two rules this makes binding
  (time is a mandatory channel; running summaries are tracked outside the buffer).
- Report Figure 3-67 as a layout target — still open, still ticks no acceptance
  criterion.
