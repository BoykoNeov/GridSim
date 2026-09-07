# M6 — Tasks

The checklist. Companion to `m6-plan.md` (the how) and `m6-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate** — which in M2, M3, M4 and M5 was every round's most
valuable line.

Status: **step 0 (planning) done; steps 1–6 open.** Entered at `181fe4e` with
**2835 core / 382 UI / 986 reference**, all three measured on freshly resolved
manifests at M5's close.

**Read before ticking anything.** A box is ticked when its check passes *with its
positive control and with its anti-vacuity mutation executed* — not when the code
runs. Five planned M3 checks would each have passed against the very bug they
targeted; M4 step 4's round-winning check was not on the plan's list at all; M5
step 8's mutation found its own check's premise wrong.

---

## Step 0 — planning (this batch, 2026-09-07)

- [x] The milestone chosen, and the fact that the repo's own selection criterion
      had run out recorded rather than glossed (D0). All six scientific hurdles
      closed at M5's end; three new ones named.
- [x] **The dependency measurement taken before any plan prose committed to it**
      (D1). `PowerSystems` 5.12.3 + `PowerFlows` 0.25.2 resolve alongside our exact
      stack — 258 packages against 184, nothing of ours moved — and are *usable*,
      not merely resolvable: a two-bus case solved by both the AC and DC entry
      points. Probes kept in `W:\temp\claude\gridsim-m6-resolve\`.
      **Hurdle 9 closed**, in the direction that removes the excuse.
- [x] `NonlinearSolve` 4.29.2 and `SparseArrays` 1.12.0 confirmed already present
      transitively — both become direct dependencies at zero new packages (D2).
- [x] Plan trio written (`m6-plan.md`, `m6-context.md`, `m6-tasks.md`). **No
      pre-study**, and the plan says why: the physics is textbook, the unknown is
      repo integration.
- [x] The two architectural questions put to the user with the measurement in
      hand, and answered: **keep `NetworkModel` canonical** with `PowerFlows` as
      the second oracle (D1), and **two rungs committed with the third gated**
      (D7).
- [x] `docs/plans/README.md`: M6 row added, hurdles 7/8/9 appended to the hurdle
      list with 9 marked closed, and the scenario editor's line updated to say it
      is now owned by M6 rather than cross-cutting.
- [x] `docs/SPEC.md` annotated in place — **six edits, not the one the plan
      owed**, because the refusal in D1 contradicted more of the spec than §9 did.
      §9 item 5's parenthesis struck in half; §8's rule given the equations/solver
      split it never stated; the tech-stack table's *Canonical data* and
      *Steady-state* rows rewritten; **§3.2's "PowerSystems is the long-term home"
      superseded** with the note that the section's actual invariant (one canonical
      model) is what the decision protects rather than breaks; and §3.4's layer
      diagram given a note that its bottom two bands have moved outward into
      `reference/`. A refusal recorded only in a plan file leaves five places in
      the spec still saying the opposite.

---

## Step 1 — the fields the ladder needs, added without moving a number (D3, D4)

- [ ] `Branch` gains `R::Float64`, defaulted to `0.0`, documented in pu on the
      **system** base like `X` is.
- [ ] `Branch`'s docstring states what is still absent — line charging and taps —
      so incompleteness cannot be read as a modelling choice (D4).
- [ ] `Machine` gains `V_set`, `Q_min`, `Q_max`, with defaults that reproduce
      today's behaviour exactly.
- [ ] `NetworkModel` gains `slack::Symbol`, validated to name a real bus. The
      private field in `DetailedEngine` now reads the model's (D3).
- [ ] Bus roles derived, not stored — a helper that returns the role of each bus
      from the slack plus what is attached, with the rejection cases tested
      (a slack naming a missing bus; more than one machine at a bus for the tiers
      that forbid it).
- [ ] **Gate — the invariant, and it is TWO claims, not one:** (a) the full core
      suite passes at **2835 unchanged**, and (b) M5's criterion numbers are
      bit-identical. **Only (a) is checked by the suite going green.** M5's
      criterion numbers (the 1.03× `P_max`, the 14-of-14 walk) are asserted with
      tolerances, so the underlying float can move and the test still passes. (b)
      therefore means *printing the values and comparing them*, not inferring them
      from a green run.
- [ ] **The field has five readers, so check five.** `Branch.X` is read by
      `branch_arrays`, `SwingEngine`'s edge model, both `DetailedEngine` edge
      models (static and dynamic) and `_branch_flows`. Adding `R` beside it means
      each is inspected and each is stated as either updated or deliberately
      unchanged — the same logic that turned step 0's one owed SPEC annotation into
      six.
- [ ] **Anti-vacuity mutation:** set one branch's `R` non-zero in an isolated
      fixture and show a number moves. Without this the gate above passes trivially
      if nothing reads the field.
- [ ] `git diff Project.toml` after any `Pkg` operation, and the comments put back.

---

## Step 2 — the linear (DC) power flow

- [ ] `src/steadystate/` created; the DC solve assembles `B` and solves `B·θ = P`.
- [ ] **Sparse structurally, and checked as such:** the assembled matrix is a
      `SparseMatrixCSC` and its stored-entry count equals what the branch list
      predicts. First matrix this repo builds itself; first place the "no dense
      Y-bus" rule binds our own code (D2).
- [ ] Two-bus closed form.
- [ ] Three-bus ring: the split between the two parallel paths is a ratio of
      reactances, written down and asserted.
- [ ] **Superposition** — two injections solved separately sum to the pair solved
      together. A property only a linear model has, so it is a real discriminator
      rather than a restatement.
- [ ] Anti-vacuity mutation: perturb one reactance and show the split moves in the
      direction and by the amount the ratio predicts.

---

## Step 3 — the nonlinear (AC) power flow (D6)

- [ ] Residual equations written (polar form, real and reactive balance per bus),
      handed to `NonlinearSolve`. Ours are the equations; theirs is the solver (D2).
- [ ] Generator buses hold `P` and `|V|`; load buses hold `P` and `Q`; the slack
      holds `|V|` and angle and picks up the losses.
- [ ] **The band discriminator inherited from `_check_power_flow`, not
      re-derived** — checks ordered band, then ratings, then residual last (D6).
- [ ] Reactive-limit switching: a generator bus that hits `Q_max` becomes a load
      bus at its limit.
- [ ] **Positive control for the limits:** limits set so wide they cannot bind must
      reproduce the unlimited answer *exactly*.
- [ ] **Discriminating case for the limits:** a case where algebra says a specific
      bus must bind, which must report exactly that bus.
- [ ] **Positive control for the whole step:** with every `R = 0` and generator
      voltages at 1.0, the AC angles approach step 2's linear answer as loading
      falls, at the rate the small-angle approximation predicts. A comparison
      between two of *our* solves, so it catches what both oracles might absorb.
      **This states a RATE, so it needs its band stated before the comparison
      runs** — step 4's rule applies here too, and for the same reason: this is a
      two-sided numerical comparison, and a band chosen after the gap is seen is
      not a check. The band comes from the truncation order of the small-angle
      approximation, not from either solve's own convergence.
- [ ] A losses check with `R ≠ 0`: the slack's pickup equals the summed branch
      losses, which is an identity and not a tolerance.
- [ ] Anti-vacuity mutation: flip a sign in the reactive residual and confirm at
      least one named check goes red. If none does, the checks are not testing what
      they claim.

---

## Step 4 — the two oracles (D5, hurdle 8)

### Oracle A — the flat run (ours, no dependency)

- [ ] A solved power flow back-substituted into machine states and fed to
      `DetailedEngine` as its initial condition.
- [ ] **The run is flat** — every state within the solver's tolerance of its start,
      over a run long enough that a slow mode would show (M5's `T′do = 8 s` lesson:
      too short a window turns "no movement" into "the last sample").
- [ ] **Anti-vacuity:** perturb the solved solution slightly and confirm the same
      run is *not* flat. A flat-run test passes trivially against a model that
      cannot move.
- [ ] The failure mode named in the test: this check is what makes the repo's two
      steady-state sources agree without either being declared correct (D5).

### Oracle B — `PowerFlows.jl` in `reference/`

- [ ] `to_powersystems(net)` compiles the case from `NetworkModel` — **compiled,
      never typed beside it** (the M4 rule).
- [ ] **Conventions answered from their source BEFORE the comparison runs**
      (M4 D13/D14): per-unit bases and whether they are process-global; the sign
      convention on loads; where a shunt is booked; which bus is the angle
      reference; whether their DC solve carries losses.
- [ ] **The band is stated before the gap is seen.** Written into the test file
      with its justification, then the comparison runs.
- [ ] Bus voltage magnitudes, angles and branch flows compared on at least two
      cases: one radial, one meshed.
- [ ] Their DC solve compared against ours as a separate channel with its own band
      — a per-channel band, not the aggregate's (M4's lesson).
- [ ] Anti-vacuity: sabotage a value on **our** side and confirm the comparison
      goes red. The sabotage goes in the equations, not in a shared conversion both
      sides read (M4 step 4's rule).
- [ ] `reference/Project.toml` gains the two packages, its comment block restored
      after `Pkg.add` rewrites it.

---

## Step 5 — the editor and the scenario file fold in (D8)

- [ ] `scenario_file.jl`: the new fields written explicitly; the field list, the
      key ranking and the reader all updated in the one place each is decided.
- [ ] **Read-side defaults (D8)**, with a round-trip test that reads a *pre-M6*
      file and asserts each default lands where it should. This is the only thing
      between "a default" and "a silent reinterpretation of every old file".
- [ ] The slack written as a **top-level** key with its own `_KEY_RANK` entry — it
      is a model field, not a machine or bus record, so it does not ride along with
      either.
- [ ] **A file with no slack is REJECTED**, with a message naming the buses it
      could be. This is D8's one exception and the reason for it is in D8: every
      other new field has a value that is physically what its absence meant, and
      the slack has none. Inventing one would record a dispatch choice as though
      the file had said so (M5 D13).
- [ ] Editor: line resistance, generator voltage setpoint and reactive limits
      editable **through the constructors** (M5 D5 — one validated path).
- [ ] Editor: the slack bus selectable, and shown on the map as such.
- [ ] Editor: a **solve** action — the map colours by voltage, branches carry flow
      arrows, the slack's pickup appears in the read-out.
- [ ] A refused solve leaves the editor usable and says why (the scenario editor's
      own lesson: a refused line once left a bus armed).
- [ ] **Render before claiming.** Offscreen render inspected, not assumed — the
      standing rule since M1, and the one that changed step 8's design twice in M5.
- [ ] Exports checked against `names(GLMakie)`.

---

## Step 6 — the optimisation rung: the gate (D7)

- [ ] The four criteria in D7 evaluated **in writing**, each with its answer.
- [ ] If the gate opens: the rung is planned as its own step with its own oracle
      before any code.
- [ ] If it does not: written into `docs/plans/README.md` as owed, **with the
      criterion that failed named**. An item that keeps being carried is missing a
      criterion, not missing work (M3 step 7, Figure 3-67).

---

## Housekeeping owed by this milestone

- [ ] `docs/validation-ledger.md` gains a steady-state section, every row labelled,
      `un-oracled` rows stated out loud.
- [ ] `docs/plans/README.md` M6 row updated as steps land.
- [ ] `docs/SPEC.md` §9 item 5 annotated (step 0's second open box).
- [ ] `docs/SPEC.md` §8's "no hand-rolled power-flow math" line annotated with D2's
      reading, so the split between equations and solver is documented where a
      reader meets the rule rather than only where it was argued.
- [ ] Re-resolve all three environments from deleted manifests at the end and
      **measure** the counts there — the gitignored-manifest trap has caught this
      repo three times (`m4-context.md` D15, the 2026-08-18 stale dev manifest, and
      `ui/`'s silently ignored `[sources]`).
- [ ] `git diff` every `Project.toml` after every `Pkg` operation and put the
      dropped comments back.
