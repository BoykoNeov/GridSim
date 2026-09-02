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
| M4 | Run-then-playback (`solve!`); the cross-run divergence read; a scrubbable overlay window; PowerDynamics as an external oracle in `reference/`; dependency housekeeping | Step 1 done; step 2 written, unexecuted; 3–5 open | `m4-*.md` |
| M5 | The detailed machine tier: flux dynamics, a voltage regulator, voltage as a real unknown, power-flow initialisation | Pre-study only | `m5-prestudy.md` |

Cross-cutting:

- `entsoe-iberia-reproduction.md` — the real test case: what each tier reproduces,
  where it stops, and the record of how a tuned parameter once became a quoted
  result (§7.3). Read §2 before treating any Iberian number as validation.
- `../validation-ledger.md` — every mechanism in the repo and what checks it. The
  D7 bookkeeping from `m4-context.md`, started ahead of M4 step 4 so the un-oracled
  items are visible now.
- `../scenarios/iberia-2025-04-28.md` — extracted report figures with page cites.

## The scientific hurdles, in dependency order

Named here once so the next milestone is chosen against them rather than against
the roadmap's numbering (M3 was already taken out of order, for a stated reason).

1. **Reading a divergence without putting error into it.** Two runs land on two
   grids; the recorder decimates; the engines keep no interpolant after a step
   closes. *Resolved by construction in M4 step 2*: one shared `saveat` grid, and a
   read that refuses anything else. What remains is executing the tests
   (`m4-tasks.md` step 2).
2. **An external check on the swing tier that is not a tautology.** PowerDynamics'
   classical machine puts `E′` behind `X′d`; ours puts it at the bus, which is only
   the same thing on a radial pair. The band and the convention questions to answer
   *before* the comparison runs are worked in `m5-prestudy.md` §7.
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

## Structure notes

- **`test/runtests.jl` is one 5,000-line file** with one outer `@testset`. It
  works, and it is the right shape for `Pkg.test()`; it is not the right shape for
  reading. The split is mechanical but not blind: helpers (`ratio_ring`,
  `lockstep_coi`, `pb_both`, `overlay_pair`, …) are defined *between* testsets
  inside the outer testset's local scope, so a file `include`d from there would not
  see them. The split therefore means moving every helper to `test/helpers.jl`,
  `include`d at top level before the outer testset, then one file per milestone in
  the same order. Do it on a machine that can run the suite; do not do it blind.
- **Exports are checked against GLMakie's** (`intersect(names(GridSim),
  names(GLMakie))` must stay empty) every time a name is added — the collision cost
  a round in M1. M4 step 2's three names were added in a session without Julia;
  the check is owed (`m4-tasks.md` step 2).
- **`Manifest.toml` is gitignored on purpose** (a package, not an app), which is
  why `[sources]` entries matter: without one the `ui/` → core link lives only in
  a file that is not in the repo. Added in M4 step 5, pending a re-resolve.
