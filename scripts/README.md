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
`FrequencyResponseEngine`. This is Milestone 1's headless proof (`docs/SPEC.md`
§7.8 criterion 1), using a real scenario instead of the synthetic
`example_system`. Five sections:

1. **Frequency waypoints** against the ones ENTSO-E reported.
2. **Defence plan** — which load-shedding stages fired, at instants *root-found*
   by a per-stage `ContinuousCallback` (so they print to the millisecond and can
   be set against the report's own annotations), and how much each shed.
3. **Cumulative tripped generation** at the report's checkpoints — a lower bound
   by construction, since the last cluster is a floor the report states as such.
4. **RoCoF**, 500 ms windowed vs instantaneous. These are different quantities;
   only the windowed one is comparable to the report.
5. **Inertia sensitivity** over the report's published 2.21–2.71 s band.

Read `docs/plans/entsoe-iberia-reproduction.md` §2 before treating any of this as
validation — the centre-of-inertia model is faithful only up to ~12:33:19.6, and
**the model recovers where reality collapsed**. That gap is the missing
loss-of-synchronism export swing, and it is not to be closed by tuning.

Three of the printed sections look like results and are not; each says so in its
own output. The script's claims are asserted in `test/runtests.jl`, which
includes this file as a module so the scenario data lives in exactly one place.
