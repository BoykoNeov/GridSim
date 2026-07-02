# GridSim

A power-grid simulator in Julia that starts as a tiny, correct frequency-response
model and grows toward a full energy-system simulator — generators, transmission,
dynamics, protection, renewables, and markets — at multiple fidelities behind one
engine interface.

It is a **personal instrument for learning power systems by experiment**: stand on
the mature Julia ecosystem (`DifferentialEquations.jl`, the NREL-Sienna stack) and
build only the bespoke part — the orchestration layer that steps models in
wall-clock time, injects live perturbations, and routes between fidelity tiers.

> **Status: Milestone 1 engine landed.** The repository structure, domain model,
> perturbation events, and the `SimulationEngine` interface are in place, and the
> first engine — the real-time aggregate (center-of-inertia) frequency-response
> model — is implemented and validated (closed-form RoCoF/settling checks). The
> real-time orchestration loop and UI are next. See [`docs/SPEC.md`](docs/SPEC.md)
> and [`docs/plans/`](docs/plans/).

## Design in one breath

- **Headless core, single process.** The core (`src/`) is a library with *zero* UI
  dependency, drivable from the REPL / a script. The UI (`ui/`) depends on the
  core, never the reverse. No client/server, no sockets.
- **Fidelity tiers + a mode router.** Every phenomenon gets a fast surrogate (run
  in real time) and an accurate sibling (run offline, then played back). Which mode
  you get slides with system size.
- **One canonical model.** Reduced models are compiled views of it, not forks.
- **Validation-first.** Every engine ships a closed-form or cross-fidelity check —
  which is also the point: *seeing where the cheap model diverges from the accurate
  one is the lesson.*

## Milestone 1

Simulate aggregate system frequency, trip a generator *while it runs*, and watch
frequency, RoCoF (rate of change of frequency), and nadir live — making the
low-inertia lesson visible (*less online inertia → steeper RoCoF, deeper nadir*).
Full spec: [`docs/SPEC.md` §7](docs/SPEC.md).

## Getting started

Requires Julia ≥ 1.10 (install via [juliaup](https://github.com/JuliaLang/juliaup)).

```julia
# from the repo root
julia --project=. -e 'import Pkg; Pkg.instantiate(); using GridSim; println(GridSim.example_system())'

# run the tests
julia --project=. -e 'import Pkg; Pkg.test()'
```

## Repository layout

```
GridSim/
├── Project.toml          # core package — does NOT depend on Makie
├── src/
│   ├── GridSim.jl        # module root, exports
│   ├── model/            # minimal aggregate domain model (M1)
│   ├── engines/          # SimulationEngine interface + concrete engines
│   ├── events/           # perturbation event types
│   └── orchestration/    # real-time loop, pacing, live state (no UI import)
├── test/                 # validation: closed-form checks, later cross-fidelity
├── scripts/              # REPL-driven experiments (the headless win)
├── ui/                   # separate package: `using GridSim`, `using GLMakie`
└── docs/                 # SPEC.md (full brief) + plans/
```

## License

[BNCL-1.0](LICENSE) (Boyko Non-Commercial License v1.0) © 2026 Boyko Neov
