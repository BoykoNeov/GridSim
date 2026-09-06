# Plans — the index

One trio per milestone: `mN-plan.md` (the how), `mN-context.md` (decisions, what
was measured, what surprised), `mN-tasks.md` (the living checklist, ticked in place
with what each step found). Read the tasks file first to see where a milestone
stands; read the context file before re-litigating a decision.

| Milestone | Delivers | Status | Trio |
|---|---|---|---|
| M1 | Aggregate (centre-of-inertia) frequency + RoCoF, real-time, generator trip, closed-form checks, aggregate window | Done | `m1-*.md` |
| M2 | Canonical `NetworkModel`; multi-machine classical swing engine on NetworkDynamics; bounded recorder; `TripLine`; `coi_model` as the compiled aggregate view; multi-machine window | Done | `m2-*.md` |
| M3 | Governor droop as a third state; per-machine load-shedding ladders; out-of-step tie relay; scheduled generation ramps; the two-area Iberian case with its sweep; Figure 3-67 | Done | `m3-*.md` |
| M4 | Run-then-playback (`solve!`); the cross-run divergence read; a scrubbable overlay window; PowerDynamics as an external oracle in `reference/`; dependency housekeeping | **Done** — 1873 core / 172 UI / 82 reference, all three re-resolved from scratch | `m4-*.md` |
| M5 | The detailed machine tier: algebraic bus voltages (a DAE), flux dynamics, a voltage regulator, power-flow initialisation, and the Iberian criterion the tier exists for | **In progress** — steps 0b, 1 and 2 done (the suite split; the algebraic network, power flow and flat run; then the two-axis machine and its frozen-flux degeneration against `SwingEngine` — 2251 core / 172 UI / 82 reference); steps 3–8 open | `m5-*.md` (physics worked ahead in `m5-prestudy.md`) |

Cross-cutting:

- `entsoe-iberia-reproduction.md` — the real test case: what each tier reproduces,
  where it stops, and the record of how a tuned parameter once became a quoted
  result (§7.3). Read §2 before treating any Iberian number as validation.
- `../validation-ledger.md` — every mechanism in the repo and what checks it. The
  D7 bookkeeping from `m4-context.md`, started ahead of M4 step 4 so the un-oracled
  items are visible now.
- `../scenarios/iberia-2025-04-28.md` — extracted report figures with page cites.
- `ui-visuals-performance.md` — the UI's look and cost: what was measured (the
  engines step in ~1 µs; the UI paid two minutes of cold start and 585 KB per
  repaint), what the first batch fixed (precompile workload, shared theme,
  two-label read-outs), and the remaining items written for a less capable
  model to execute one at a time.

## The scientific hurdles, in dependency order

Named here once so the next milestone is chosen against them rather than against
the roadmap's numbering (M3 was already taken out of order, for a stated reason).

1. **Reading a divergence without putting error into it.** Two runs land on two
   grids; the recorder decimates; the engines keep no interpolant after a step
   closes. *Resolved by construction in M4 step 2*: one shared `saveat` grid, and a
   read that refuses anything else. **Closed** — the tests were executed on merge
   and all four numbers reconstructed in a Julia-less session held first time
   (`m4-tasks.md` step 2).
2. **An external check on the swing tier that is not a tautology.** PowerDynamics'
   classical machine puts `E′` behind `X′d`; ours puts it at the bus, which is only
   the same thing on a radial pair. The band and the convention questions to answer
   *before* the comparison runs are worked in `m5-prestudy.md` §7. **Resolved in M4
   step 4** — and not by that section's premise: `Library.Swing` is the component
   that matches, it needs no reduction, so the meshed ring went through after all,
   and a fourth convention question nobody had listed turned up instead
   (`m4-context.md` D13/D14).
3. **The Iberian ceiling.** A constant-voltage two-area model reproduces the
   separation or the 5 GW export swing, never both (`entsoe-iberia-reproduction.md`
   §7.3 d). Closing it needs voltage as a state — the whole reason M5 exists — and
   `m5-prestudy.md` §1 turns that into one measurable exit criterion.
4. **Initialising a detailed tier without inventing a disturbance.** A
   mis-initialised machine opens with a transient nobody injected, and no overlay
   catches it. The closed-form back-substitution and the flat-run test are in
   `m5-prestudy.md` §4.
5. **The degeneration oracle, stated correctly.** The classical limit of a two-axis
   machine is *frozen* flux (`T′do, T′qo → ∞` with `X′d = X′q`), not constant field
   voltage. `m5-prestudy.md` §3 derives it and names what that oracle cannot check
   and what checks that instead.
6. **Which network formulation keeps the tier steppable.** Algebraic bus voltages
   (a DAE with a mass matrix) against dynamic RL branches. `m5-prestudy.md` §5
   works both and reverses the M4 plan's default, with the measurement that
   decides.

Hurdles 1 and 2 are closed. **M5 owns 3, 4, 5 and 6**, and its trio says which step
each lands in: 6 is decided up front (`m5-context.md` D1, the algebraic network)
with its cost measured in step 1; 4 is step 1's flat run; 5 is split across steps 2
and 4, because the frozen-flux limit provably cannot check the flux equations it
switches off; and 3 is the milestone's purpose, step 7.

## Structure notes

- **`test/runtests.jl` was one 5,000-line file** with one outer `@testset`. **Split
  in M5 step 0b** (2026-09-06) into `test/helpers.jl` plus eight files, `include`d
  inside the one outer testset, at an unchanged 1873 core tests. Adding a file means
  knowing the three things the split rests on:
  - **Helpers live in `test/helpers.jl`, `include`d at top level.** `include`
    evaluates its file at *module* scope, never in the local scope of the block the
    call sits in — so a helper left inside the outer testset is invisible to every
    file included from it. That was this note's original trap, and it is real.
  - **`@testset` nesting is dynamic, not lexical** (`Test` keeps a task-local
    stack), which is why testsets in included files still report as one tree.
  - **The include order is execution order, not milestone order.** M3 inserted its
    steps 1–5 ahead of M2's own tail, so M2 and M3 each occupy two files; keeping
    the order was chosen over grouping by milestone, and each file's header says so.

  A **hoisted helper becomes a global**, so its name is checked against
  `names(GridSim)`/`names(Test)`/`names(Base)` for the same reason exports are
  checked against GLMakie's below — inside the testset it was a local, and a local
  shadows silently.
- **Exports are checked against GLMakie's** (`intersect(names(GridSim),
  names(GLMakie))` must stay empty) every time a name is added — the collision cost
  a round in M1. M4 step 2's three names were added in a session without Julia,
  and the check was **executed on merge** — it passes (`m4-tasks.md` step 2).
- **`Manifest.toml` is gitignored on purpose** (a package, not an app), which is
  why `[sources]` entries matter: without one the `ui/` → core link lives only in
  a file that is not in the repo. Added and **verified by re-resolve** in M4
  step 5; `ui/`'s Julia floor moved 1.10 → 1.11 because Pkg 1.10 was measured to
  ignore `[sources]` silently (`m4-context.md` D15).
