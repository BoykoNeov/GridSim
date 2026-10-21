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

## Where do line limits bind? (`binding.jl`, 2026-10-21)

MATPOWER case9 shaped as ours (no line charging, G1–G3 held at their set-points), loads
scaled by `s`; Ipopt `tol = 1e-10`. "Binding" = a branch within 0.1 % of its rating at
its larger end.

| s | DC OPF $/h | binding | DC, no limits $/h | AC OPF (held V) $/h | binding |
|---|---|---|---|---|---|
| 1.0 | 5216.03 | none | 5216.03 | 5325.27 | none |
| 1.25 | 7323.21 | none | 7323.21 | 7537.91 | none |
| 1.5 | 9857.82 | none | 9857.82 | 10241.62 | none |
| 1.75 | 12819.84 | none | 12819.84 | LOCALLY_INFEASIBLE | — |
| 2.0 | 16230.15 | L82 | 16209.27 | LOCALLY_INFEASIBLE | — |
| 2.25 | 20303.01 | L82 | 20026.12 | LOCALLY_INFEASIBLE | — |
| 2.4 | 23106.66 | L14, L82 | 22546.17 | LOCALLY_INFEASIBLE | — |

**On case9 as published no line limit binds** — the DC network optimum IS M6's
network-free one (5216.03), so a network OPF checked there is vacuous. The first line to
bind under load growth is L82, G2's bridge (250 MVA against G2's 300 MW): a generator cap
in disguise, not a meshed-network effect. Held-V AC turns infeasible between 1.5 and 1.75.

At s = 1, each line rated in turn at 60 % of its unconstrained DC flow binds and moves
the dispatch (DC $/h): L14 5408.07, L45 5327.37, L56 5525.27, L36 5457.30, L67 5299.70,
L78 5442.40, L82 5629.05, L89 5612.91, L94 5428.46.

A solver-independent bound, from M6: the network-free dispatch handed to `ac_powerflow`
costs 5216.03 + 109.26 = 5325.29 $/h on this shape (`m6-tasks.md` step 7); the held-V
AC optimum, 5325.27, may not exceed it, and is 0.02 $/h below.
