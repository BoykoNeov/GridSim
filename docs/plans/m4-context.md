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

Four probes, all in throwaway projects under `M:\claud_projects\temp\`, never
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

No. Raising GridSim's own bounds (`SciMLBase = "3.30.1, 4"`,
`OrdinaryDiffEq = "7, 8"`, `NetworkDynamics = "1"`, `Graphs = "1"`) **still fails,
identically** — because SciMLBase's newest registered version is 3.49.2, so
widening upward cannot reach a version PSID accepts. PSID needs to go *down*, not
us up.

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
