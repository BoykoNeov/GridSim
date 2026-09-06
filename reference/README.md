# GridSimReference

The **external oracle** for [GridSim](../), kept as a separate Julia
package/environment so the core never acquires a `PowerDynamics` dependency — the
same structural treatment `ui/` gets for Makie (`../docs/SPEC.md` §3.1, and
`../docs/plans/m4-context.md` D3). The dependency points one way only:
`GridSimReference` → `GridSim` → `PowerDynamics`, never the reverse, and the
core's own suite asserts the other half.

**It is a checker, not a tier.** Nothing in the UI can run a PowerDynamics model.
Promoting it to something the mode router offers is a small change and would be
the wrong one today: it would put a symbolic component library in the hot path,
and it would cost the root `Pkg.test()` about fifty extra packages to resolve.

## Why this package exists

Every check in M1–M3 is ours against ours: a closed form we derived, or one of our
tiers against another of our tiers. That leaves one class of error undetectable —
the one where the simple model and the detailed model are wrong in the same way,
because the same hands wrote both. Then "the simple model drops swings" and "our
model has a bug" look identical, which is the failure `m4-context.md` D2 names.
This package is what tells them apart.

## The two tiers, and what each is for

The case is **compiled** from `NetworkModel` (`build_oracle`), never typed out
beside a fixture — a hand-written PowerDynamics system would be the forked
parallel model `SPEC.md` §3.2 forbids, and it would drift silently, which is the
worst possible property in an oracle.

- **`:swing`** — PowerDynamics' `Library.Swing`, which is our `swing_vertex!`
  equation for equation, constant-voltage-magnitude-at-the-bus included. Any gap
  is an implementation difference, so this is the bug-detector. Valid on any
  topology, including the meshed ring.
- **`:classical`** — `Library.ClassicalMachine`: `E′` behind `X′d` on an algebraic
  terminal bus. A genuinely different electrical formulation, valid **only on a
  radial pair** (enforced with a thrown error, not a comment), and it does not
  reduce to ours exactly — its mechanical input is a *torque* where ours is a
  *power*. That residual is proportional to the machine's loading and is
  identified by that signature rather than bounded by a tolerance.

`oracle_solve` returns the trajectory in the shape `state_series(::SwingEngine)`
returns, so `divergence` (M4 step 2) applies across the two sides with no adapter
and no resampling. Both runs must be handed the **same explicit `saveat` grid**;
nothing anywhere resamples, on purpose.

## The band

`oracle_band`, not `tolerance_band`. Two different solvers on different state sets
do not agree to `3·reltol·excursion` — measured over five decades that ratio runs
between 4.7 and 15.3 and never settles, and picking a factor to cover it would be
fitting a constant to the gap it is meant to judge. The band comes from the
triangle inequality instead: each side's own convergence,
`|run(reltol) − run(reltol/1000)|`, summed. **Neither term ever looks at the other
implementation**, so "state the band before you see the gap" is arithmetic rather
than discipline.

## What this oracle cannot check

Both sides read the same `machine_arrays` / `branch_arrays` / `_coupling`, because
the case is compiled from the canonical model. Invert a per-unit weight there and
both sides integrate the same wrong number and agree to 1e-12. The full
what-checks-what table is in `../docs/plans/m4-context.md` §What step 4 measured;
the short version is that the coupling formula, the graph mapping, the fixpoint,
the event semantics and the integration are externally checked, while the `H`, `D`
and `Pm` conversions stay checked by M1/M2's closed forms alone.

The practical consequence: an anti-vacuity mutation for this suite belongs in
`swing_vertex!`, never in the shared data path.

## Running it

```
julia --project=reference -e 'import Pkg; Pkg.test()'
```

The first run precompiles the ModelingToolkit stack and takes several minutes.
Do not run it at the same time as the root or `ui/` suites — concurrent Julia work
in the shared package depot has crashed it before.

`Pkg.add` rewrites `Project.toml` and drops its comments, including the
`[sources]` note. After any Pkg operation here, `git diff reference/Project.toml`
and put them back.
