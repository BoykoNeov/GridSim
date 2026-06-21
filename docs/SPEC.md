# GridSim — Development Handoff & Specification

> Hand this document to Claude Code as the project brief. It encodes durable
> architecture decisions (sections 1–6) and a concrete, buildable first
> milestone (section 7). The decisions in sections 1–4 are **constraints**, not
> suggestions — they exist so the project can grow for years without repainting
> itself into a corner. Read section 8 (non-goals) before writing any code.

---

## 1. Vision

A power-grid simulator that starts as a tiny, correct frequency-response model
and grows — over a multi-year horizon — toward a full energy-system simulator:
generators, transmission, dynamics, protection, renewables, markets, and
eventually national-scale grids.

Two framing facts that shape every decision:

- **Single user.** No multi-user, no remote access, no auth. This is a personal
  instrument, not a service. It rules out a client/server split (see §3).
- **Learning through experimentation, not through reimplementation.** The point
  is to *understand power systems by running experiments and watching results* —
  not to hand-write numerical solvers. Stand on the mature Julia ecosystem;
  build only the parts that don't exist (the interaction/orchestration layer and
  any reduced models nobody packaged).

## 2. The organizing principle: fidelity tiers + a mode router

The simulator is **not** one model. Every physical phenomenon is represented at
multiple fidelities, and the execution mode is chosen by what the wall-clock
budget can afford for a given fidelity and system size:

- **Real-time injection** — cheap/approximate models stepped in wall-clock time,
  perturbed live (trip a line, lose a generator) while running.
- **Run-then-playback** — full-fidelity models solved offline, then scrubbed /
  animated in the UI.

The boundary between the two **slides with system size**. A model that runs in
real time on a 5-unit system becomes playback-only at national scale.

This is the mechanism that lets the project grow indefinitely in a principled
way: each new physics is added at (at least) two fidelities — a fast surrogate
and an accurate sibling — behind one common engine interface.

## 3. Architecture & invariants

### 3.1 Headless core, single process

"Headless" means **the core is a library with zero UI dependency**, fully
drivable from the REPL / a script / a notebook. It does **not** mean a separate
process behind a socket. Everything runs in **one Julia process**.

- The UI depends on the core. **The core never imports the UI / plotting
  packages.** Swappability is enforced by dependency direction, not by a network
  boundary.
- The live loop reads simulation state and pushes perturbation events
  **in-process**, with zero serialization in the hot path. This is *why* there is
  no process boundary — a socket here would tax exactly the loop that must stay
  tight.
- `Observables.jl` is a standalone package (Makie depends on it, not the reverse),
  so the orchestration layer may use Observables for live state **without**
  pulling Makie into the core.
- Serialization is for **persistence only** (save/load a grid to disk), not for
  the core↔UI runtime seam.

### 3.2 One canonical model; reduced models are compiled views

There is a single source of truth for the grid. Reduced/surrogate models are
**derived from it** (projected/compiled down), never forked into parallel
hand-maintained data.

- Canonical model: `PowerSystems.jl` (NREL-Sienna) is the long-term home — it is
  a mature, serializable, well-maintained data model with PSS/E import and the
  rest of the Sienna stack built on it.
- **For Milestone 1 only**, do *not* adopt the full PowerSystems data model. A
  single-frequency aggregate model needs ~5 fields per unit. Use a minimal domain
  struct now (§7.3) and design the seam so it can later be populated *from* a
  PowerSystems `System`. Premature unification is a trap; introduce PowerSystems
  when the model first needs buses/branches (the network-aware tiers).

### 3.3 The `SimulationEngine` interface (the durable abstraction)

The orchestration layer talks to every fidelity/mode through one interface.
Real-time engines implement `step!`/`inject!`; playback engines implement
`solve!`/`state_series`. The UI is mode-agnostic.

```julia
abstract type SimulationEngine end

# --- lifecycle ---
init!(engine::SimulationEngine, model; t0=0.0, dt)        # build problem/integrator
step!(engine::SimulationEngine, dt)                       # advance by dt (real-time engines)
solve!(engine::SimulationEngine, tspan; perturbations=[]) # solve a horizon (playback engines)

# --- state access (mode-agnostic) ---
current_state(engine::SimulationEngine)   # named state at "now"
state_series(engine::SimulationEngine)    # full trajectory (after solve!, for playback)

# --- live perturbation (real-time engines) ---
inject!(engine::SimulationEngine, event::PerturbationEvent)  # queued, applied at next step boundary
```

### 3.4 Layer model

```
┌──────────────────────────────────────────────┐
│  UI — GLMakie (network canvas, controls, plots)│  depends ↓ on core
├───────────────  headless seam  ───────────────┤  (core has no UI dependency)
│  Orchestration — sim state (Observables),      │  ← the part you author
│  event queue, step / re-solve controller,      │
│  wall-clock pacing                             │
├────────────────────────────────────────────────┤
│  Compute regimes — PowerFlows.jl (steady),     │
│  PowerSimulations.jl (markets/OPF),            │  ← existing Julia packages
│  DiffEq + PowerDynamics/PSID (dynamics)        │
├────────────────────────────────────────────────┤
│  Data model — PowerSystems.jl (source of truth)│
└────────────────────────────────────────────────┘
```

The orchestration band is the project's core IP — the bespoke part. Everything
else is built on existing packages.

### 3.5 Render state ≠ simulation state

The physics model is the source of truth. UI/render state (positions, selection,
camera, colors) is **derived** from it and lives separately. Never make a render
entity and a simulation entity the same object.

## 4. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Julia (≥ 1.10) | Native numerics; no FFI tax. |
| Canonical data | `PowerSystems.jl` | Adopt at network-aware tiers, not M1. |
| Steady-state | `PowerFlows.jl` | DC / AC power flow. |
| Markets / OPF | `PowerSimulations.jl`, `JuMP` + HiGHS/Ipopt | Later tiers. |
| Dynamics (real-time tier) | `NetworkDynamics.jl` + `PowerDynamics.jl` | Modular, equation-based; thin over DiffEq → integrator is steppable for live injection. Swing model is a ready node type. |
| Dynamics (playback tier) | `PowerSimulationsDynamics.jl` (PSID) | Full electromechanical, batch-shaped API (perturbations defined at `Simulation` construction). |
| Integration | `DifferentialEquations.jl` | Use the **integrator interface** (`init`, `step!`, callbacks) for real-time engines. |
| Live state | `Observables.jl` | Standalone; safe in core. |
| UI / viz | `GLMakie` (native), `WGLMakie` (web later), `GeoMakie`/`Tyler.jl` (maps, national scale) | Great for plots + simple controls; the node-graph editor is built on a Makie canvas later. |
| Test systems | `PowerSystemCaseBuilder.jl` | IEEE 14/30/118/300-bus, etc. |

### Forward-looking constraints (cheap now, expensive to retrofit)

- **Sparse from day one.** When network solves appear, never build a dense
  admittance (Y-bus) matrix, even on toy systems. Use `SparseArrays`.
- **Struct-of-arrays for numeric parameters.** Keep numeric arrays (that may go to
  GPU or batched/ensemble runs) contiguous and separate from topology/metadata.
  Not needed at M1's size, but establish the habit. GPU's first payoff is
  *batched* work (N-1 contingency, Monte-Carlo, 8760-hour series), not single
  small solves.
- **Type stability.** Concrete-typed struct fields. Abstractly-typed fields are
  the single biggest Julia performance cliff.

## 5. Repository layout (proposed)

A core package with no UI dependency, plus a thin UI package that depends on it.

```
GridSim/
├── Project.toml                 # core package — does NOT depend on Makie
├── src/
│   ├── GridSim.jl               # module root, exports
│   ├── model/                   # domain model (M1: SystemModel; later: PowerSystems adapter)
│   ├── engines/                 # SimulationEngine + concrete engines
│   │   ├── interface.jl         # the abstract SimulationEngine API (§3.3)
│   │   └── frequency_response.jl# M1 engine (§7)
│   ├── events/                  # PerturbationEvent types + queue
│   └── orchestration/           # real-time loop, wall-clock pacing, live state container
├── test/                        # validation: closed-form checks, later cross-fidelity
├── scripts/                     # REPL-driven experiments (the headless win)
└── ui/                          # separate package/module: `using GridSim`, `using GLMakie`
    └── ...                      # core never imports anything from here
```

## 6. Conventions

- **Per-unit internally.** Document the system base `S_base` (MVA) and nominal
  frequency `f0` (Hz). Convert to engineering units only at the UI boundary.
- **Validation-first.** Every engine ships with a reference check (closed-form or
  cross-fidelity). This is also the primary learning mechanism (§7.6).
- **Integrator, not `solve()`, for real-time engines.** Drive
  `DifferentialEquations.jl` via `init(prob, solver)` then `step!(integrator, dt, true)`
  so the loop can interleave UI events and redraws. Perturbations mutate
  `integrator.p` (and re-init algebraic state for the network tiers; M1 needs no
  re-init — see §7.4).
- **Solver:** the M1 frequency model is non-stiff (`Tsit5` is fine). Keep the
  solver swappable on the engine so stiff tiers can use `Rodas5`/`FBDF` later.
- **TTFX:** keep a long-lived REPL/UI session alive (it amortizes compile latency);
  add `PrecompileTools.jl` later if startup matters.

---

## 7. MILESTONE 1 — Real-time system frequency & RoCoF after generator loss

**Goal:** A real-time-steppable engine that simulates aggregate system frequency,
lets the user trip a generator *while it runs*, and shows frequency, RoCoF
(rate of change of frequency), and nadir live. This is the cheapest dynamics
rung (center-of-inertia / aggregate-inertia), chosen because it is the easy case
for live injection (parameter change + continuous state, no algebraic re-init).

### 7.1 What the user should be able to do

1. Define a small system of generating units (3–6 aggregate units).
2. Start the simulation; watch `f(t)` plot live, paced to wall-clock time.
3. Trip a generator mid-run (button / click); watch frequency dip, with a live
   RoCoF readout and nadir tracking.
4. See that **less online inertia → steeper RoCoF and deeper nadir** — the
   low-inertia/renewables lesson, made visible.

### 7.2 Model — center-of-inertia (COI) aggregate frequency response

All quantities per-unit on `S_base` unless noted. `f0` = nominal frequency (Hz).

**Per online unit `i`** (set `U`):
- `S_i`  — rated power (MVA)
- `H_i`  — inertia constant (s, on the unit's own base)
- `P_i`  — current output (MW)
- `R_i`  — governor droop (pu, on unit base)
- `Pmax_i` — max output (MW) → headroom `Pmax_i − P_i`

**Aggregates (recomputed whenever `U` changes):**
- Inertia on system base:  `H_sys = (Σ_{i∈U} H_i·S_i) / S_base`   [s]
- Equivalent droop:        `1/R_eq = Σ_{i∈U} (1/R_i)·(S_i/S_base)`
- Load damping:            `D` (pu power per pu frequency; typical 1–2)
- Governor/turbine lag:    `T_g` (s)

**States** (pu on system base):
- `Δω` — frequency deviation; actual frequency `f = f0·(1 + Δω)`
- `ΔPm` — aggregate governor/turbine mechanical-power deviation

**ODEs:**
```
dΔω/dt  = ( ΔPm − D·Δω + ΔP_dist ) / (2·H_sys)
dΔPm/dt = ( −Δω / R_eq − ΔPm ) / T_g           # clamp ΔPm to aggregate headroom
```
`ΔP_dist` is the persistent power imbalance (pu); it is 0 until a disturbance.

**Optional (add after the base works): secondary control / AGC** — an integral
term `dζ/dt = Δω; ΔP_agc = −Ki·ζ` added to the `dΔω/dt` numerator, which restores
`f` to nominal. Without it, frequency settles at a non-zero deviation.

### 7.3 Minimal data model (M1 only)

```julia
struct GeneratingUnit
    id::Symbol
    S_rated::Float64   # MVA
    H::Float64         # s (own base)
    P0::Float64        # MW, initial output
    R::Float64         # pu droop
    Pmax::Float64      # MW
end

struct SystemModel
    S_base::Float64    # MVA
    f0::Float64        # Hz
    D::Float64         # load damping, pu/pu
    Tg::Float64        # s, aggregate governor/turbine lag
    units::Vector{GeneratingUnit}
end
```
Provide a constructor/helper that builds a small example system. Design `SystemModel`
so a future `from_powersystems(sys::PowerSystems.System)` adapter can produce one.

### 7.4 Engine & the trip event

Implement `FrequencyResponseEngine <: SimulationEngine`:

- `init!` builds an `ODEProblem` from the aggregates and `init`s a
  `DifferentialEquations.jl` integrator (`Tsit5`), with the aggregates stored in a
  **mutable** parameter object `p` (so events can change them).
- `step!(engine, dt)` calls `step!(integrator, dt, true)` and records `(t, f, RoCoF)`.
- `current_state` returns `(t, f, Δω, RoCoF, ΔPm)` where `RoCoF = f0·dΔω/dt`.
- `inject!(engine, ::TripGenerator)` enqueues the event; the orchestration loop
  drains it at a step boundary and the engine then:
  1. removes unit `k` from the online set,
  2. recomputes `H_sys` and `R_eq`,
  3. adds the deficit: `ΔP_dist −= P_k / S_base`.
  The state `(Δω, ΔPm)` is **continuous** across the event — only the parameters
  `p` change. (No algebraic re-initialization needed; that's why this is M1.)

```julia
abstract type PerturbationEvent end
struct TripGenerator <: PerturbationEvent; id::Symbol; end
struct StepLoad      <: PerturbationEvent; ΔP_pu::Float64; end   # nice-to-have
```

### 7.5 Real-time orchestration loop

```julia
# pseudocode — lives in src/orchestration/, NO Makie import here
function run_realtime!(engine, state_obs; rtf = 1.0)   # rtf = real-time factor
    dt = 0.02
    while running[]
        for e in drain!(event_queue);  inject!(engine, e);  end
        step!(engine, dt)
        state_obs[] = current_state(engine)            # Observable → UI redraws
        sleep_to_pace(dt / rtf)                        # maintain wall-clock pacing
    end
end
```

### 7.6 Validation (also the learning payoff)

- **Closed form:** at the instant of a trip (`Δω=0, ΔPm=0`), initial RoCoF must
  match `RoCoF0 = f0 · ΔP_dist / (2·H_sys) = −f0·(P_k/S_base)/(2·H_sys)`. Assert in tests.
- **Settling (no AGC):** `Δω_ss = ΔP_dist / (D + 1/R_eq)`. Assert.
- **Cross-fidelity (later milestone, not blocking M1):** run the *same* trip in
  PSID full electromechanical playback and overlay. The point where the aggregate
  model and PSID diverge is the lesson — it shows what the COI approximation drops
  (inter-machine swings, voltage coupling, IBR behavior).

### 7.7 UI (separate `ui/` package, `using GLMakie`)

- Live line plot of `f(t)` (Hz) using an `Observable`; horizontal reference at `f0`.
- Live numeric readouts: current `f`, current RoCoF (Hz/s), running nadir.
- A control per unit (button/toggle) to trip it; a global play/pause and a
  real-time-factor slider.
- (Nice-to-have) a small bar/indicator showing online `H_sys` so the user sees
  inertia drop when a unit trips.

### 7.8 Acceptance criteria

- [ ] Core (`model` + `engines` + `orchestration`) runs headless from a script and
      produces a frequency trajectory with **no Makie dependency**.
- [ ] Real-time loop plots `f(t)` live in GLMakie, paced to wall-clock.
- [ ] Tripping a generator mid-run produces the expected dip; RoCoF and nadir update live.
- [ ] Initial RoCoF matches the closed-form value within tolerance (unit test).
- [ ] Settling deviation matches the closed-form value within tolerance (unit test).
- [ ] Fewer/less-inertia units online ⇒ visibly steeper RoCoF and deeper nadir.

---

## 8. Non-goals / do NOT do (yet)

- **No client/server or IPC.** Single process. A socket between core and UI is wrong here.
- **No full PowerSystems.jl data model for M1.** Use the minimal `SystemModel` (§7.3).
- **No hand-rolled solvers where the ecosystem has them.** Build the *loop and
  router*, not the integrators or power-flow/dynamics math.
- **No conflating render and simulation state.**
- **No dense matrices** anywhere a network solve appears (use sparse).
- **Don't over-build the engine zoo now.** Implement only `FrequencyResponseEngine`
  for M1; the interface (§3.3) is the contract future engines will satisfy.

## 9. Roadmap after M1 (for context — don't build ahead)

1. **M1 (this doc):** aggregate frequency / RoCoF, real-time, generator trip.
2. Multi-machine **classical/swing** model (rotor angles) on `NetworkDynamics`/
   `PowerDynamics`, still real-time on small systems.
3. **Run-then-playback** path: same scenarios in PSID full electromechanical;
   overlay vs the surrogate (cross-fidelity validation as a UI feature).
4. **Steady-state** ladder: DC power flow → AC power flow (Newton) → AC-OPF
   (adopt `PowerFlows.jl`; introduce `PowerSystems.jl` as canonical model here).
5. Protection, then **markets/OPF** (`PowerSimulations.jl`, `JuMP`).
6. Renewables / low-inertia studies (the M1 lesson, scaled up).
7. National scale: geographic map (`GeoMakie`/`Tyler.jl` or web `maplibre`+`deck.gl`),
   batched/GPU contingency & time-series.
