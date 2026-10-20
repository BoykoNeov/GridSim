# M11 step 0 — does an outside network-OPF checker resolve? (measured 2026-10-21)

Julia 1.12.6. Scratch under `W:\temp\claude\gridsim-m11-resolve` (regenerable; not kept).

**M6's "PowerModels does not resolve against our stack at any version" no longer holds.**
M6 (2026-09-23) measured 0.8.0–0.21.6, whose resolver log ended at its `NLsolve`
requirement. PowerModels **0.21.7** allows `NLsolve = "4, 5"`, and NLsolve 5.0.1
co-resolves with our `NonlinearSolve`.

`probe.jl` — PowerModels + Ipopt added to four fresh environments:

| Environment | Result |
|---|---|
| alone | resolves, 79 packages (PowerModels 0.21.7, Ipopt 1.16.0, JuMP 1.32.1, NLsolve 5.0.1) |
| GridSim core (dev) | resolves, 220 |
| GridSim core + GridSimReference (dev) | resolves, 319 |
| GridSim core + JuMP + HiGHS (the test target) | resolves, 223 |

`versions.jl` — **nothing of ours moved**: NonlinearSolve 4.32.0 / NonlinearSolveBase
2.55.0 / SciMLBase 3.58.0 / OrdinaryDiffEq 7.8.1 / NetworkDynamics 1.3.0 as in the root
manifest; the reference set (NonlinearSolve 4.30.0, NonlinearSolveBase 2.48.0,
PowerDynamics 5.0.0, PowerSystems 5.12.4, PowerFlows 0.25.4, TimerOutputs 0.5.29) as in
the reference manifest. PowerModels' Julia floor is 1.10 — ours does not move.

`usable.jl` — **usable, not only resolvable**, on MATPOWER `data/case9.m` (fetched
2026-10-21 from https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case9.m;
its `gencost` rows are the ones `test/m6_economic_dispatch.jl` typed), Ipopt defaults:

| Case | Status | Cost $/h | Pg MW (G1, G2, G3) |
|---|---|---|---|
| AC OPF, case9 as published | LOCALLY_SOLVED | 5296.6862 | 89.799, 134.321, 94.187 |
| DC OPF, case9 as published | LOCALLY_SOLVED | 5216.0266 | 86.564, 134.378, 94.058 |
| AC OPF, line charging removed, generator voltages free | LOCALLY_SOLVED | 5310.0704 | 90.100, 134.442, 94.313 |
| AC OPF, line charging removed, G1–G3 held at 1.04 / 1.025 / 1.025 (our `case9`'s set-points) | LOCALLY_SOLVED | 5325.2661 | 90.721, 134.411, 94.332 |

These are PowerModels' answers, measured — not checked here against a MATPOWER-stored
solution. The last row is the one shaped like `scripts/outage_screen.jl`'s `case9` (no
line charging, PV voltages held; Q ±300 MVAr, band 0.9–1.1, the same ratings).

PowerModels' own bundled `test/data/matpower/case9.m` is a DIFFERENT case (250 MW of
load; AC cost 347.70) — do not take it for MATPOWER's.
