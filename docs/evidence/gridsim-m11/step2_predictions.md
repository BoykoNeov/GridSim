# M11 step 2 — predictions, written before any comparison ran (D8)

Written 2026-10-21, after the probes below and before our `dc_opf` and PowerModels' DC
OPF were run side by side on anything. Nothing here is adjusted after a gap was read;
anything a later run contradicts is recorded in `docs/plans/m11-context.md` ("What step 2
measured"), not edited in here.

## What was run first (one side at a time, never a comparison)

Scratch, under `W:\temp\claude\gridsim-m11-step2` (copied into `step2/` with this file):

1. **The source, pinned.** MATPOWER `data/case9.m` last changed at commit
   `31e3308e80f831e7310c2d45835501038665b5a3` (2017-10-31, "Update case9 gen voltages, Q
   injections and slack P…"); fetched 2026-10-21 at that SHA and at master
   (`80b6e16f760f58721ad31221c7287c28259cd4ad`, 2026-10-12) — byte-identical, sha256
   `ee50fc7bf9f6019c0f3a3bc94d20978cc667b08f695dc725d00dbd998b358623`. Not committed (D7).
2. **The typing is faithful.** The rows typed into the reference test (bus, gen, branch,
   gencost, comments dropped), handed to `PowerModels.parse_matpower(IOBuffer(…))`, give a
   dictionary `==` to `parse_file` of the downloaded file (`reader.jl`). The `IO` method
   exists in 0.21.7.
3. **Resolution in `reference/`'s own environment** (`resolve.jl`, a scratch copy of its
   `Project.toml` + `Manifest.toml`): PowerModels 0.21.7, Ipopt 1.16.0, **and JuMP 1.32.1 +
   HiGHS 1.26.1** — the last two because our `dc_opf` only runs with `GridSimDispatchExt`
   loaded, which needs both in the environment the test runs in (a deviation from the
   task line, which named only the first two). 300 → 321 packages; **nothing moved and
   nothing was removed** (GridSim, NetworkDynamics 1.3.0, OrdinaryDiffEq 7.8.1,
   PowerDynamics 5.0.0, PowerFlows 0.25.4, PowerSystems 5.12.4, NonlinearSolve 4.30.0,
   NonlinearSolveBase 2.48.0, SciMLBase 3.58.0, TimerOutputs 0.5.29 all held).
   `GridSimDispatchExt` loads beside PowerModels.
4. **Their side alone** (`theirs_probe.jl`; `R = 0` in the text, Ipopt `tol` =
   `constr_viol_tol` = `dual_inf_tol` = `compl_inf_tol` = τ, `bound_relax_factor = 0`):
   - solution keys: gen `pg`, branch `pf`/`pt` (reported by default — read, never
     recomputed), bus `va`;
   - the reader's angle bound: every branch at `angmin = −1.0472`, `angmax = 1.0472` (the
     ±60° D7 names); the largest branch angle difference in any solved fixture is
     0.116 rad;
   - their branches in file order with `(f_bus, t_bus)` = (1,4) (4,5) (5,6) (3,6) (6,7)
     (7,8) (8,2) (8,9) (9,4) — our order and our orientation, by bus number;
   - LOCALLY_SOLVED at τ = 1e-8, 1e-10, 1e-11 on every feasible fixture; at 1e-13
     SLOW_PROGRESS on the three binding ones (so the tight run is 1e-11);
   - **their own convergence** `|run(1e-8) − run(1e-11)|`: 2.5e-13 – 1.4e-12 pu on `pg`
     and `pf`, ≤ 9.1e-10 $/h on cost;
   - the infeasible fixture: LOCALLY_INFEASIBLE / INFEASIBLE_POINT at every τ.
5. **Our side alone** (`ours_probe.jl`; `margin = 0`, `regularization = 0`): HiGHS refuses a
   feasibility tolerance below 1e-10, so the tight run is 1e-10 against the working 1e-9.
   **Our own convergence is exactly 0** on every fixture (P, flow, cost): HiGHS's QP
   solver is active-set, so once it has the active set the answer is one linear solve,
   and the tolerance does not enter. `at_limit`: published none, L82 fixture `[:L82]`, L89
   fixture `[:L89]`, the 46 MVA fixture `[:L56]`; the 40 MVA one `:infeasible` with the
   certificate. The script's `using Printf` loads in this environment.

## How D9's margin is read here

D9 gives the optimiser limits pulled in by `δ` because the TOOLS THE ANSWER IS HANDED TO
refuse a breach strictly. An oracle comparison hands the answer to nothing. And on the
binding fixtures `δ` would dominate: L89 at 50 MVA, `δ = 1e-6` moves the limit by 5e-7
pu, against tolerance terms near 1e-12 — a band that "covers δ" would be blind to every
error smaller than the margin. **So our side runs at `margin = 0` against PowerModels'
unmargined ratings: the same problem on both sides, compared strictly.** The margin
itself stays checked in-house (step 1's identities use the margined rating).

## The comparison

Ours: `dc_opf(net; tol = 1e-9, regularization = 0, margin = 0)` on `case9(; costed = true)`
(the report script's grid, D10) and its rated variants. Theirs: `solve_opf(data,
DCPPowerModel, Ipopt)` at τ = 1e-8 on the typed text, `R = 0` on every branch (D2.5),
invented ratings written into the text in MVA. Channels: each machine's output (pu),
each branch's `from → to` flow (pu), each bus angle (rad; both references at bus 1,
angle 0), and the cost ($/h).

## The band — stated, and from each side's own convergence

The reference README's rule for two different solvers: each side's distance to the exact
answer bounded by its own convergence, the two summed (the triangle inequality); neither
term looks at the other side. Per channel `c`:

**`band_c = 2·(O_c + T_c) + ρ_c`**

- `O_c = |ours(1e-9) − ours(1e-10)|` and `T_c = |theirs(1e-8) − theirs(1e-11)|`, max over the
  channel, computed in the test on each fixture. The factor 2 covers the tight run's own
  error up to the size of the difference (it is not assumed exact).
- `ρ_c` is a round-off allowance, **the one underived number**: `1e-11` pu on outputs,
  flows and angles, `1e-11·|cost|` on cost (≈ 5e-8 $/h). It is there because `O_c` is
  exactly 0 (an active-set answer is exact to round-off) and an exact-zero band would
  fail on the last bit of two different factorisations. It is ≥ 7 orders below every gap
  this file expects the comparison to see (23.1's 1.4e-4 pu, the sabotages).

Expected: every fixture inside its band with room; the band is ~1e-11 pu (~1e-9 MW).

## Fixtures and what each is for

| Fixture | Our side | Their text | Expected |
|---|---|---|---|
| F1 published | `case9(; costed = true)` | as typed | nothing binds; cost 5216.0266 on both (23.2's free check) |
| F2 L82 at 100 MVA (invented) | rating replaced | L82's rateA/B/C = 100 | L82 binds on both; G2 at 100 MW |
| F3 L89 at 50 MVA (invented) | rating replaced | L89's = 50 | L89 binds, every unit moves |
| F4 L45, L56 at 46 MVA (invented) | both replaced | both = 46 | L56 binds (B5 fed from both sides) |
| F5 L45, L56 at 40 MVA (invented) | both replaced | both = 40 | ours `:infeasible` with HiGHS's certificate; theirs LOCALLY_INFEASIBLE — **reported side by side, never called agreement**: Ipopt's word is local, HiGHS's is a proof |

On F1–F4: the ±60° bound is present in their parsed data on every branch and **never
binding** (every solved branch angle difference < 1.0472 − 0.5 rad); their branch
`(f_bus, t_bus)` equals ours by bus number, branch by branch.

## 23.1 — the formula difference, kept as a fact

The same comparison with `R` LEFT IN their text (`x/(r²+x²)` against our `1/X`):

- **F1:** outputs agree within the strict band (nothing binds, so the dispatch never sees
  the network); every ring-line flow differs by ≈ **0.014 MW** (1.4e-4 pu, step 0's
  figure at this dispatch), the three generator lines by nothing beyond the band.
- **F3:** with L89 binding, `R` changes the line's sensitivities, so the **outputs** move
  too. Size not predicted; only that it is above the band.
- Printed, and asserted to EXCEED the strict band (on F1's ring flows and F3's outputs):
  the free check that the strict comparison is sharp enough to see the formula difference
  at all. Never used as a band.

## Sabotages, and which fixture sees each (written before running them)

Each run against the step-2 testset alone; every mutant runs with Ipopt's `max_wall_time`
(the oracle sets 120 s always) and HiGHS's `time_limit` added (step 1's lesson).

| Sabotage | F1 | F2 | F3 | F4 | F5 | 23.1 |
|---|---|---|---|---|---|---|
| **SA1** — a mistyped literal on OUR side only: L89's `x` 0.161 → 0.116 in `scripts/outage_screen.jl` | red (flows, angles; outputs not — nothing binds) | red (flows) | red (all) | red (all) | green (still infeasible: blind) | — |
| **SA2** — OUR side only: G2's `c1` 1.2 → 1.25 in the script | red (outputs, cost) | red (cost; G2 is pinned at its line, the other two may move) | red | red | green (blind) | — |
| **SB** — the invented rating written into THEIR text in pu (rating ÷ 100) where MVA is expected | green (no edit: blind) | red (L82 at 1 MW < G2's 10 MW minimum: theirs not solved) | red | red (0.46 MW feeds cannot meet 90 MW) | green (blind) | — |

SA1 and SA2 being red is what shows the oracle's input does not pass through our data
(Hurdle 23.2): a literal wrong on our side only is seen. SB being red is what shows the
invented ratings reach their model in the unit their reader expects.
