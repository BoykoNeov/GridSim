# scripts/

REPL-driven experiments against the headless core — the payoff of the no-UI-in-core
design (`docs/SPEC.md` §3.1). A script here should `using GridSim`, build a system,
run an engine, and print/assert results, with **no** Makie import.

Run one with the project environment active:

```julia
julia --project=. scripts/<name>.jl
```

The first such script (a headless generator-trip experiment producing a frequency
trajectory) lands with Milestone 1.
