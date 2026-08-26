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

## `iberia_two_area.jl`

The same event on the **two-area** tier (`SwingEngine`), which is what adds the one
mechanism the script above has no state for: a rotor angle and a nonlinear tie whose
transfer peaks at 90°, falls while the angle keeps growing, and reverses past 180°.
That reversal is the report's export swing, and it is why the aggregate model
recovers where reality collapsed.

**The result is the sweep, not the trace.** This is Milestone 3 step 6, and it exists
to replace a throwaway probe whose tie strength had been tuned until the peninsula
lost synchronism, so that three of its quoted numbers were artefacts of the tuning
(`docs/plans/entsoe-iberia-reproduction.md` §7.3, `docs/plans/m3-context.md` D10).
Five sections:

1. **Reference check** — the inter-area mode against its closed form, derived through
   `machine_arrays`/`branch_arrays` and with the residual *identified* (it tracks
   swing amplitude) rather than merely bounded.
2. **The cascade magnitude, re-derived from Table 3-1** and printed as arithmetic, not
   quoted. 5,187 MW over 4.100 s. The two figures previously in circulation for this
   one quantity differ by 1.87× and both appear below as labelled cells.
3. **One cell** of the grid, labelled as one cell in its own output.
4. **The sweep** — tie strength × cascade magnitude × ramp duration × remote inertia ×
   pre-event tie flow × defence plan, regenerable in under a minute.
5. **What survives the grid and what does not**, including one conclusion of §7.3 that
   is overturned, one that survives against the reasoning that predicted it would not,
   and one that turns out to depend on a quantity the report never states.

Read `docs/plans/entsoe-iberia-reproduction.md` §7.6 before treating any of it as
validation: voltage magnitude is constant behind a reactance here, so angle
instability is in scope and the final voltage collapse to blackout is not.
