# M4 — Tasks

The checklist. Companion to `m4-plan.md` (the how) and `m4-context.md` (the
decisions and the measurements behind them). Living document: each step ticks its
own boxes and records what it found, including what it found that the plan did
not anticipate.

Status: **planned, nothing built.** Entering at `ab3a87f`, 1719 core / 102 UI
tests green, working tree clean.

## Step 0 — planning (this batch)

- [x] Dependency probes run in `M:\claud_projects\temp\`, never against the repo
      (`m4-context.md` §The dependency probes, five probes).
- [x] PSID established as unusable **by measurement**, not by argument.
- [x] PowerDynamics established as resolving against the repo's pinned stack with
      nothing moved, and its component library enumerated.
- [x] Plan trio written (`m4-plan.md`, `m4-context.md`, `m4-tasks.md`).
- [ ] `docs/SPEC.md` §7.6 and §9 item 4 still name PSID. **Deliberately not
      edited yet** — the SPEC gets amended when the oracle harness exists in step
      4 and the role is filled in fact rather than in plan. Do not let this become
      a carried item: it ticks in step 4 or it is explicitly re-deferred with a
      criterion.

## Step 1 — `solve!`, the contract's unexecuted half

- [ ] `solve!(eng::SwingEngine, tspan; perturbations=[], saveat=…)` — the first
      method of `solve!` in the repo's history.
- [ ] `solve!(eng::FrequencyResponseEngine, tspan; …)` — the second, so the
      overlay pair of step 3 has two playback-capable engines.
- [ ] Scheduled perturbations compiled to a `PresetTimeCallback`; **state-triggered
      protection left exactly as the constructor already builds it** (D4).
- [ ] `interface.jl`'s "supplied up front rather than injected live" docstring
      **corrected**, not inherited — it is false for M3's protection.
- [ ] Agreement check: same scenario via `run_realtime!` and via `solve!`, equal
      to solver tolerance.
- [ ] **Run at two tolerances.** A number below the solver's own tolerance is not
      a result until it survives the tolerance changing (M3's standing rule).
- [ ] Positive control: a scenario where the two paths *should* differ (a
      perturbation at a time the real-time grid cannot represent) and does.
- [ ] Anti-vacuity control, **executed**: mutate the scheduled-event compilation
      so a trip lands one step late; the agreement check must fail. Revert; green.
- [ ] Every new long-running test self-terminates on a fixed step count.

## Step 2 — resampling and divergence in `postprocess.jl`

- [ ] Resample two series onto one grid via the solver's interpolant, or a shared
      `saveat` fixed before the solve. **Never** straight-line between recorded
      samples — the recorder decimates, so that error lands in the answer.
- [ ] Divergence read compares **inertia-weighted average to inertia-weighted
      average**, never a per-machine quantity against an aggregate.
- [ ] Lives in `src/analysis/postprocess.jl`, so it is tested headless rather
      than existing only inside a window.
- [ ] Anti-vacuity control, **executed**: same series twice must read ~0.
- [ ] Positive control: two genuinely different runs must read clearly non-zero —
      without it, "reads ~0" cannot distinguish "identical" from "always ~0".
- [ ] Second anti-vacuity control, **executed**: swap the interpolant for
      straight-line resampling on decimated samples; a check must fail.

## Step 3 — the playback window: scrub, overlay, divergence

- [ ] Time slider scrubs a solved series; cursor moves on the plot.
- [ ] Both curves drawn (centre-of-inertia tier vs network swing tier) with the
      divergence read-out from step 2.
- [ ] `smoke_render` offscreen **first**, then the live window. Render before
      claiming (M2/M3 standing rule).
- [ ] The window's own text states that this pair shows **one of the three
      lessons** SPEC §7.6 names (inter-machine swings) and not the other two. A
      read-out that implies otherwise promotes a number it cannot support.
- [ ] UI test count moves; both `ui/` and core suites green.

## Step 4 — `reference/`: PowerDynamics as an external oracle

- [ ] New package `reference/`, depending on `GridSim` and `PowerDynamics`,
      never the reverse — same structural enforcement as `ui/`.
- [ ] **`NetworkModel → PowerDynamics` builder** (D5). This is the step's real
      work; a hand-typed PowerDynamics case beside `two_machine_system()` is the
      forked parallel model SPEC §3.2 forbids, and it would drift silently, which
      is the worst possible property in an oracle.
- [ ] Core's dependency-closure test still passes, and gains a clause: core must
      not reach PowerDynamics either.
- [ ] Two-machine case run through PowerDynamics with `Library.ClassicalMachine`
      — **our fidelity, someone else's implementation**.
- [ ] Divergence read from step 2 applied across the two. Disagreement here is a
      bug in *our* engine, not a lesson about fidelity — record which it turned
      out to be.
- [ ] Anti-vacuity control, **executed**: perturb one coefficient in our swing
      vertex equations; the external agreement check must fail.
- [ ] Every mechanism now carries a label saying what checks it (D7). Write the
      list — PowerDynamics-checked, alternatively-oracled, or explicitly
      un-oracled. Un-oracled is allowed; unmarked is not.
- [ ] `docs/SPEC.md` §7.6 / §9 item 4 amended: the role is "an external
      full-fidelity reference", the package is PowerDynamics, and the reason PSID
      is not it is one sentence with a pointer to `m4-context.md`.

## Step 5 — the dependency housekeeping, in its right place at last

- [ ] **Both dependency resolutions tested**, not just the developer machine's —
      the box M3 left open at `m3-tasks.md:795` for "whichever later step does
      change a dependency". Step 4 changes one. Delete `Manifest.toml`, re-resolve
      fresh, run all three suites.
- [ ] `[sources]` entry in `ui/Project.toml` so the dev link to core survives a
      fresh clone — the fix M3 identified and declined as out of scope.
- [ ] `reference/Project.toml` carries `[sources]` **from birth**, not added
      later — the gitignored-manifest trap has cost this repo time twice.
- [ ] Tick the M3 box in `m3-tasks.md` with a pointer here, rather than leaving a
      third milestone's reader to wonder whether it was forgotten.

## Known hazards to check off explicitly

- [ ] **Resampling error contaminates the measured quantity.** Interpolant or
      shared `saveat`; never straight-line between decimated samples.
- [ ] **Gauge-arbitrary comparison.** Inertia-weighted average on both sides.
- [ ] **An overlay that validates nothing.** Same-series-twice ~0 *and* a
      different-runs positive control; mutations run, not described.
- [ ] **The one-lesson-of-three trap.** The M4 pair shows inter-machine swings
      only; voltage coupling and inverter behaviour need M5's tier.
- [ ] **Playback and real-time must stay the same system.** If protection is
      ever pre-baked into `perturbations=`, every comparison in this milestone is
      measuring the wrong thing.
- [ ] **Every long-running test self-terminates** on a fixed step count, never on
      a condition. Re-check per step.
- [ ] **The oracle must not become a ceiling** (D7). Exceeding PowerDynamics'
      scope is allowed; exceeding it while still speaking as if checked is not.

## Carried into M5 (not this milestone's work)

Recorded so it is not re-derived. Detail in `m4-plan.md` §Why the detailed tier
is M5.

- The detailed machine tier: two-axis machine with flux dynamics, a voltage
  regulator, and transmission branches carrying voltage as a real unknown.
- The **power flow solve and initialisation** it requires — roadmap item 5's
  territory arriving early, to be scoped deliberately (two-area, sparse, no
  `PowerFlows.jl`).
- The **flat-run test**: no disturbance at all, every state constant for the
  whole horizon. This is what catches a bad initialisation; no overlay will.
- The **degeneration oracle, all three conditions together**: constant field
  voltage, equal transient reactances on both axes, no damper winding. Shrinking
  a time constant alone is *not* the classical limit and would pass against a
  wrong flux equation.
- **Dynamic RL branches, not the algebraic constraint** — or, if reversed, an
  explicit account of what happens to `isoutofdomain` and the step-rejecting
  protection, which do not survive unchanged.
- **"Better than PowerDynamics" needs a named axis and a measurement** —
  accuracy against a closed form, cost per simulated second, or real-time
  steppability — on the same case at the same tolerance.
