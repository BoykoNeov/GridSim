# scripts/

REPL-driven experiments against the headless core — the payoff of the no-UI-in-core
design (`docs/SPEC.md` §3.1). A script here should `using GridSim`, build a system,
run an engine, and print/assert results, with **no** Makie import.

Run one with the project environment active:

```julia
julia --project=. scripts/<name>.jl
```

## `iberia_2025_04_28.jl`

Replays the 28 April 2025 Iberian blackout event sequence through
`FrequencyResponseEngine` and prints its frequency waypoints against the ones
reported by ENTSO-E. This is Milestone 1's headless proof (`docs/SPEC.md` §7.8
criterion 1), using a real scenario instead of the synthetic `example_system`.

Read `docs/plans/entsoe-iberia-reproduction.md` §2 before treating its output as
validation — the centre-of-inertia model is faithful only up to ~12:33:19.6.
