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

**The picture of one cell** is `ui/scripts/figure_3_67.jl` (M3 step 7), which
`include`s this file so the model and the twelve shed stages live in exactly one
place, and renders `docs/images/fig-3-67-two-area.png`. It lives under `ui/`
rather than here for this directory's own reason: it imports Makie, and nothing
in `scripts/` may.

## `low_inertia.jl`

M7 step 7's study: **what changes when the generation has no rotor.** M1's four units
(`example_system()`, field for field) on a seven-bus network in two layouts (a meshed
`:ring` and a `:chain`), displaced step by step by grid-following and by grid-forming
inverters at **matched dispatch** — every row of a sweep starts from the same operating
point — with a unit tripped at every step on the detailed tier. Two events (the user's
choice, `docs/plans/m7-context.md` D16): G1, the largest unit (38 % of the generation),
and G4, the smallest. Default (constant-impedance) loads. Four sections:

1. **Positive control** — zero share, constant-power loads: the network's
   instantaneous centre-of-inertia RoCoF at t⁺ against M1's own engine on the same trip,
   to ~1e-12 on both layouts.
2. **The sweeps** — per share: inertia online, RoCoF₀ by formula and by network, the
   500 ms windowed RoCoF from the centre of inertia and from PLL meters at every bus, the
   load relief and grid-following power change at t⁺ that account for the gap between
   the two RoCoF₀ columns exactly, nadir (`≤` when the frequency is still falling at the
   end — never reported as a nadir), voltage, governor reserve, grid-forming loading
   against rating, and synchronism; or the wall a refused cell hit.
3. **Anti-vacuity** — the grid-forming sweeps with τ_p → 0.001 s (virtual inertia ≈ 0).
4. **What the tables say** — five claims, written after both layouts' tables and each
   asserted in `test/m7_low_inertia.jl`. Three drafted before the tables did not survive
   them.

Read D16's "What the study measured" before quoting a number. The grid-forming rows run
with **no current limit** (D8) and most of them above their rating; the PLL column
includes the trip's own phase-jump spike, which no rotor felt.

## `outage_screen.jl`

M8 step 6's report: **every single outage, at both fidelities, side by side.** Each
line and each generator of two grids is taken out one at a time and screened with
the linear (DC) power flow — the shortcut real screening tools start from — and with
the full nonlinear (AC) one, and every place the two disagree gets a reason printed
beside it. The grids are case9 **without line charging** (the model has no shunts),
with **invented** droop and damping because published case9 has none, and M8 step 5's
invented five-bus mesh. Both run on constant-power and on the default
constant-impedance loads. Three sections:

1. **The one decision step 6 took** (`docs/plans/m8-context.md` D9, the user's
   choice): a line whose loss cuts off a generator sitting alone is screened as that
   generator's outage. Checked on the numbers — the line carries nothing in the
   generator's outage, and the bus it cuts off sits at its neighbour's voltage.
2. **The tables** — per outage: both verdicts, the class of disagreement, the most
   loaded branch against its rating at each fidelity, the settled frequency after a
   generator is lost, and why.
3. **What the tables say** — five claims, written after the tables and each asserted
   in `test/m8_outage_screen.jl`.

Read claim (d) before quoting a "secure": the screen judges line loading and voltage
only. It has no frequency criterion, and one "secure" row settles 10.9 Hz low.

## `double_outage_screen.jl`

M10 step 6's report: **every pair of elements of the same two grids** — two lines, two
generators, one of each — lost at once, and lost one after the other with 50 Hz restored
in between (each remaining generator taking extra output in proportion to its governor
gain). A pair that cuts the grid is answered **piece by piece**: each part with a
generator and a load settles at its own frequency; a part with no generator is load lost
(customers in the dark); a part with no load is its generators lost. Every running part's
settled frequency is judged against the Continental Europe preset's 0.2 Hz, with the
preset's caveat printed beside it. The linear (DC) screen is printed once — it reads no
load model — beside the full (AC) one on both load models. Four sections:

1. **Both at once** — per pair, every part left, its frequency and verdict at the three
   fidelities, and what the dead parts took with them.
2. **One loss, then 50 Hz restored** — what the second loss starts from: restored,
   refused (not enough headroom), or a restored state outside the voltage band.
3. **One after the other** — per ordered pair, the worst part's frequency and verdict, and
   whether the order made it milder, worse or no different than both at once.
4. **What the tables say** — eight claims (k–r), written after the tables and each
   asserted in `test/m10_report.jl`.

It includes `outage_screen.jl` into a submodule for its grids, so the two reports read the
same models. The window `double_outages()` in `ui/` draws it.

## `network_dispatch.jl`

M11 step 5's report: **the cheapest dispatch of case9 subject to the network.** For case9
(no line charging, MATPOWER's costs) and its binding fixtures — three INVENTED line ratings
(L82 at 100 MVA, G2's own line; L89 at 50 MVA and L94 at 60 MVA, ring lines) and the loads at
1.5× and 1.75× — on constant-power and on the default loads: M6's network-free dispatch, the
same dispatch handed to the AC flow, the DC network optimum and the AC one (generator
voltages held), with cost, outputs and what binds. Three sections:

1. **The dispatch, four ways** — and where the AC flow refuses M6's dispatch, why.
2. **Every AC optimum handed to the detailed tier** — a flat run from its own power flow,
   seven of the eleven sitting on a limit; the drift, the mechanical-power gap, and the
   reference machine's up-reserve as the engine holds it (from what it produces,
   `docs/plans/m11-context.md` D12) against the schedule's.
3. **What the tables say** — six claims (s–x), written after the tables and each asserted in
   `test/m11_report.jl`.

**It needs the solvers**, which are optional extensions of GridSim, so run it in an
environment that carries JuMP, HiGHS and Ipopt beside GridSim:

```julia
julia --project=ui scripts/network_dispatch.jl          # or --project=reference
```

Read claim w before quoting an AC cost on the default loads: there the sagging voltages
serve less load, and the difference is load not served, not generation saved. Every load
limit (B9's floor at 1.5×, no AC answer at 1.75×) is case9's without line charging; the
published case9 has it, and PowerModels solves it at 1.75×. It includes `outage_screen.jl`
into a submodule for its grid. The window `network_dispatch()` in `ui/` draws it.
