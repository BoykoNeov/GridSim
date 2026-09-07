# M6 — Tasks

The checklist. Companion to `m6-plan.md` (the how) and `m6-context.md` (the
decisions and, as steps run, the measurements behind them). Living document: each
step ticks its own boxes and records what it found, **including what it found that
the plan did not anticipate** — which in M2, M3, M4 and M5 was every round's most
valuable line.

Status: **steps 0–3 done, step 4's oracle A done; oracle B and steps 5–6 open.** Entered at `181fe4e` with
**2835 core / 382 UI / 986 reference**, all three measured on freshly resolved
manifests at M5's close. At step 2's close: **2996 core**; at step 3's close
**3175 core**; at oracle A's close **3284 core**, UI and `reference/` unchanged
throughout.

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

Done 2026-09-07. Entered at **2835 core / 382 UI / 986 reference**; leaves
**2899 core** (2835 unchanged + 64 new in `test/m6_steady_state.jl`).

- [x] `Branch` gains `R::Float64`, defaulted to `0.0`, documented in pu on the
      **system** base like `X` is. **Keyword-only**, so all ~50 five-positional call
      sites — including `reference/test/runtests.jl`'s two branch rebuilds — build a
      bit-identical object, and `@test_throws MethodError` on a six-positional call
      pins that there was never a positional form to have supplied it by accident.
      `R ≥ 0` and not `> 0`: unlike `X`, which is a coupling denominator, zero is the
      ordinary case. The rejection message says "governor droop" out loud, because
      **`Machine.R` is a droop and `Branch.R` is a resistance** and the scenario file
      gives them the same key in two different tables.
- [x] `Branch`'s docstring states what is still absent — line charging (`B`) and
      transformer taps — so incompleteness cannot be read as a modelling choice (D4).
- [x] `Machine` gains `V_set`, `Q_min`, `Q_max`, keyword-only, with defaults that
      reproduce today's behaviour exactly. **`V_set` defaults to `1.0`, NOT to
      `E′`** — `E′` is the internal voltage behind `X′d` (behind `Ra + jXq` at the
      detailed tier) and `V_set` is the magnitude at the terminal. M5 step 8 measured
      what one number serving two denominations costs (a pre-event tier offset larger
      than the disturbance it was drawn to show), so the two are separate numbers
      from the first line. `Q_min`/`Q_max` take `Efd_min`/`Efd_max`'s form exactly,
      `Inf` included, and every fixture in the repo is asserted to carry the defaults.
- [x] `NetworkModel` gains `slack::Symbol`, validated to name a real bus. The
      private field in `DetailedEngine` now reads the model's (D3) — **but as a
      lookup, not a rename, because D3's "promotion" was not literally true.** See
      D3's "What step 1 measured": the engine's slack is a MACHINE and the model's is
      a BUS, so the keyword stays a machine and only the default moved, and the
      model's default derives from `machines[1].bus` (not `buses[1].id`) which is
      what makes it bit-identical to the old `ids[1]`.
- [x] Bus roles derived, not stored — `bus_roles(net)` / `bus_role(net, bus)`, both
      checked clear against `names(GLMakie)` before export. Rejection cases tested: a
      slack naming a missing bus (rejected by the model, with the message naming
      every bus it could have been), a bus that is not in the model (`bus_role`), and
      **a declared slack carrying no machine, which the MODEL accepts and the ENGINE
      refuses** — M5 D3's precedent, and the thing that keeps a half-built editor
      draft constructible.
- [x] **Gate — the invariant, and it is TWO claims, not one:** (a) **the full core
      suite passes with every one of the 2835 pre-existing tests green** (2899 total,
      exit 0, no failures); and (b) **M5's criterion numbers are bit-identical**.
      (b) was checked the only way it can be — a harness
      (`W:\temp\claude\gridsim-m6\criterion_snapshot.jl`) that prints the slip
      boundary, the classical / frozen / flux-only / criterion cells and all 14 swept
      cells at shortest-round-trip precision, **captured at HEAD before the first
      edit** (the numbers stop existing the moment the tree changes) and diffed after.
      Captures: `criterion-HEAD.txt` / `criterion-STEP1.txt`. **Both captures are bit-identical** — 169 printed values, same MD5 (`c79b7c07d039b66efdeff10e45e88305`), the only textual difference being three precompilation lines the second run emitted. So the criterion cell's `over = 1.0295274854320615`, the frozen control's `0.9613881912556272` against a derived ceiling of `5287.640840616782`, the 5,500 MW boundary and all 14 swept cells are unchanged **to the bit**, not merely within M5's tolerances.
- [x] **The field has five readers, so check five.** `Branch.X` is read by
      `branch_arrays`, `SwingEngine`'s edge model, both `DetailedEngine` edge models
      and `branch_power`. **All five are stated as DELIBERATELY UNCHANGED**, and the
      statement is executed rather than asserted about: the same model with and
      without `R` gives `branch_topology`/`branch_arrays` outputs equal under `===`,
      i.e. bit equality rather than `≈`.
- [x] **Anti-vacuity mutation — re-scoped, because the planned one could not pass.**
      Every one of those five readers is lossless *by construction*, so there is no
      number for a non-zero `R` to move, and making one would be a physics change
      inside the step whose gate forbids it. What `R ≠ 0` does instead is make every
      tier **refuse the model by name** (`_assert_lossless_branches`, wired into
      `SwingEngine`, `DetailedEngine` and `reference/`'s `build_oracle`) — M5's
      `Load`-ZIP-shares shape exactly. So the field is demonstrably not inert, and the
      **numerical** mutation moves to step 3's losses identity, where a resistance
      that fails to reach the residual equations is red. Recorded in D4.
- [x] No `Pkg` operation was needed — `NonlinearSolve` and `SparseArrays` become
      direct dependencies in step 2, not here, so there is no `Project.toml` to diff.

### What this step found that the plan did not anticipate

**F1 — the step could not be confined to the model file, and a guard is the
reason.** `test/scenario_file.jl` asserts `fieldnames(Machine) == (:id, :bus,
_MACHINE_FIELDS...)`; growing `Machine` turns it red until the writer grows too.
That is the guard doing precisely its stated job, so the file work for the three
machine fields is step 1's, and `Branch.R` plus the top-level `slack` key went in
beside it rather than leaving a window in which the file silently drops a field.
What is still step 5's is the **decision** in D8 — the slack's read-side default
becoming a rejection, its message, and the pre-M6 round-trip test.

**F2 — two UI integration sites the plan named neither of.** `ui/src/editor.jl`
rebuilt `Bus`/`Branch`/`Load` by splatting `fieldnames` into the positional
constructor, which a keyword-only `Branch.R` breaks outright; `Branch` now has its
own rebuild method, as `Machine` already did. And the editor had to start
**carrying** the slack through open / save / rename / delete, because otherwise
opening a file with a declared slack and saving it re-defaults it silently — D8's
failure mode arriving through the UI rather than through the reader.

**F3 — a guard's stated reason went stale even though its arithmetic did not.**
`NetworkModel`'s Σ-balance guard justified itself with "the network is lossless in
P". With `Branch.R` in the model that reason is conditional. The guard still
*works* — it is the schedule balance at nominal voltage, where no branch quantity
appears at all — so it is annotated in place rather than changed, with a pointer to
where a lossy model's balance actually gets checked (step 3's slack-pickup
identity). Same habit that turned step 0's one owed SPEC annotation into six.

**F4 — owed to step 5, named now so it is not discovered.**
`docs/scenarios/three-machine-ring.toml` is a genuine pre-M6 file with no slack
key, and it is the file `ui/README.md` tells a reader to open. It reads correctly
today on the read-side default; when step 5 turns that default into a rejection,
the file **and the documented entry point** break unless step 5 updates both.

---

## Step 2 — the linear (DC) power flow

Done 2026-09-07. Entered at **2899 core**; leaves **2996 core** (+97 in
`test/m6_steady_state.jl`). UI and `reference/` unchanged in count.

- [x] `src/steadystate/` created; `dc_powerflow(net)` assembles `B` and solves
      `B·θ = P` with the slack row and column deleted (which pins `θ_slack = 0` and
      makes the remaining block symmetric positive definite, so the sparse
      factorisation cannot meet the singularity that `B·1 = 0` guarantees).
      **Not an engine and deliberately not in the mode router**: a steady state is a
      function of a model, nothing here steps in time, and every `SimulationEngine`
      verb would be meaningless on it.
- [x] **Sparse structurally, and checked as such:** `_dc_susceptance` returns a
      `SparseMatrixCSC{Float64,Int}` and its stored-entry count is exactly `n + 2m`
      — `n` diagonals (an unbranched bus makes the model disconnected, which
      `NetworkModel` rejects) plus `2m` off-diagonals that cannot cancel or
      accumulate, because `Branch` rejects a self-loop and `NetworkModel` rejects a
      parallel circuit. Assembled through `sparse(I, J, V, n, n)` so the duplicate
      diagonal entries sum and each branch contributes its two terms without the
      caller tracking bus degree. Also checked symmetric and singular
      (`max|B·1| < 1e-12`), the property a wrong diagonal breaks.
- [x] **…and checked on a case where the count can tell dense from sparse.** The
      three-bus ring is a COMPLETE graph, so its `n + 2m` is 9 stored entries out of
      9 — the count passes there against a dense matrix and is no evidence at all.
      A five-bus radial was added for that one line: 13 of 25.
- [x] Two-bus closed form, and it is asserted **exactly** (`==`, not `≈`): with one
      unknown the solve is a single division, `θ₂ = −0.6/4`, so a tolerance here
      would only hide a solver change.
- [x] Three-bus ring: the split between the two parallel paths is a ratio of
      reactances, written down and asserted — `direct : path = (X12+X23) : X13`, and
      separately as the loop equation it comes from (the angle drop is the same over
      both paths). The fixture uses **unequal** reactances (0.2 against 0.1 + 0.3)
      and a middle bus carrying neither machine nor load, so the divider is exact
      and the 2 : 1 answer is not a coincidence of symmetry.
- [x] **Superposition** — two injections solved separately sum to the pair solved
      together, on three models sharing one topology.
- [x] **A radial, where conservation alone fixes every flow** — not on the plan's
      list, added because the *reduction* had no check of its own — the `keep`
      vector and the scatter of the reduced answer back around the deleted slack
      row, which every one of the first four sabotages walked straight past. On a tree each branch flow is fixed by the injections downstream
      of it and by nothing else, so the answer is written down from the load list
      and must survive both a change of slack and a scaling of every reactance. It
      is also the only fixture with a **non-contiguous `keep`**: solving at the
      interior bus `R3` leaves the reduced system on buses [1, 2, 4, 5], with a hole
      the scatter has to step over.
- [x] Anti-vacuity mutation (the one the plan listed): one reactance perturbed, the
      split moves in the predicted direction and to the predicted value — 0.2 → 0.4
      gives exactly 50/50, 0.2 → 0.8 reverses the ordering to 1 : 2.
- [x] **Five IMPLEMENTATION sabotages executed, and their blindness map recorded.**
      See "what this step found" below: the plan's listed mutation is a positive
      control, not an anti-vacuity check, and running real sabotages is what
      produced this step's finding.
- [x] `SparseArrays` added by `Pkg.add` — "**No packages added to or removed from
      Manifest**", which is step 0's zero-new-packages measurement confirmed rather
      than assumed. `Project.toml` diffed after: nothing dropped (the root file
      carries no comments), but the compat bound `Pkg` wrote had to be corrected —
      see F5.
- [x] Exports checked against `names(GLMakie)`: `intersect(names(GridSim),
      names(GLMakie))` is still `Symbol[]` with `DCPowerFlow`, `dc_powerflow`,
      `bus_angle` and `bus_injections` added. **`branch_power` is deliberately NOT a
      new export** — the DC solve adds a method to the generic both dynamic tiers
      already answer to (M5 step 7's one-name rule), so the same physical quantity
      does not acquire a third name.

### What this step found that the plan did not anticipate

**F5 — `Pkg.add` on a versioned stdlib raises the Julia floor silently, and this
was MEASURED rather than reasoned.** `Pkg` wrote `SparseArrays = "1.12.0"`, a caret
bound meaning `≥ 1.12.0, < 2`. The claim that this breaks the declared `julia =
"1.10"` floor was checked on the 1.10 toolchain rather than recalled — M4 step 5 is
the precedent for not trusting the obvious reading of a compat bound, since the
Printf argument that "obviously" explained that round was simply wrong:

  - `julia +1.10 -e 'pkgversion(SparseArrays)'` → **1.10.0** on Julia 1.10.12;
  - a throwaway project declaring exactly that bound, resolved on 1.10:
    **`ERROR: empty intersection between SparseArrays@1.10.0 and project
    compatibility 1.12.0-1`**;
  - the same file with `SparseArrays = "1"` resolves.

So the line `Pkg` wrote would have moved the effective floor to Julia 1.12 while
`julia = "1.10"` two lines below went on saying otherwise. Corrected to `"1"`, which
is how `LinearAlgebra` is already treated. This is M4 step 5's lesson from the other
direction: there the surprise was that compat on an **unversioned** stdlib is inert;
here it is that compat on a **versioned** one is anything but.

**F6 — the step's own showpiece check is blind to every implementation bug.**
Five sabotages were applied to the source and the whole M6 file re-run against
each: (M1) the off-diagonal sign flipped, (M2) the branch orientation reversed in
the flow read, (M3) load added rather than subtracted in `bus_injections`, (M4) one
diagonal term scaled by 0.9, (M5) the reduced solution scattered back in reverse
order. All five go red somewhere — but not in the same place, and the map is the
finding:

| check | M1 sign | M2 orientation | M3 load sign | M4 diagonal | M5 scatter |
|---|---|---|---|---|---|
| `bus_injections` | — | — | **red** | — | — |
| sparsity / symmetry / `B·1 = 0` | **red** | — | — | **red** | — |
| two-bus closed form | — | **red** | — | — | — |
| three-bus split | **red** | **red** | **red** | **red** | **red** |
| positive control (reactance moved) | **red** | **red** | **red** | **red** | **red** |
| radial, conservation + interior slack | **red** | **red** | **red** | **red** | **red** |
| slack moved, flows unchanged | **red** | — | **red** | **red** | **red** |
| **superposition** | — | — | — | — | — |
| `R` ignored / one bus | — | — | — | — | — |

The radial row is **measured, not assumed**: the case was added after M1–M4 had
already been run, so all four were re-run against the suite containing it rather
than left as an abstention in the table. It is red under every one — which is a
statement about the fixture's strength and not a reason it was added. It was added
because the *reduction* had no check of its own, and M5 (the reversed scatter) was
run both without it — caught by three other checks — and with it, caught by four.
"Something else happens to catch it" is not the same claim as "a check covers it".

**A limit of this mutation set, recorded so step 3 does not inherit it.** M4 scales
one diagonal term by 0.9, which leaves `B` structurally identical and is therefore
caught by the cheapest check present (`max|B·1| < 1e-12`). The realistic assembly
bug is a *dropped* contribution or a diagonal summing the wrong branches, and no
mutation here is of that class. Step 3's mutations should include one that changes
the sparsity pattern, not only the values in it.

**Superposition catches nothing.** The plan called it "a property only a linear
model has, so it is a real discriminator rather than a restatement" — and that is
true of the *class* of model and false of the *implementation*. Every one of these
four sabotages produces a different linear map, and a wrong linear map is still
linear, so `f(a) + f(b) = f(a+b)` holds exactly as well for the broken solve as for
the right one. It is a real check of the tier's character and it is worth keeping,
but it is not what makes this step safe, and calling it the discriminator would
have left the step resting on the one test that cannot fail.

Two smaller blindnesses fell out of the same run, both of them instances of the
same warning — that a two-bus case is too symmetric to be evidence:

  - **The two-bus closed form misses three of the four.** Deleting the slack row and
    column on a two-bus network leaves a 1 × 1 matrix that contains *only* a
    diagonal entry, so a flipped off-diagonal is not merely hard to see there, it is
    structurally absent (M1). `two_machine_system` carries no `Load` at all — its
    second machine has a negative `P0` — so the load-sign sabotage cannot reach it
    (M3). And the surviving diagonal comes from the branch's `to` end, which M4 did
    not touch.
  - **The `R`-ignored and one-bus testsets are blind to all four**, correctly: both
    compare a mutated solve against another mutated solve, or against nothing. They
    check a boundary and a degenerate case, not a number.

What actually carries the step is the **three-bus split with unequal reactances**
and the positive control built on it — the only two checks red under all five. That
is an argument for the fixture, not against the others: a case whose answer is
fixed by algebra, on a topology with no symmetry to hide behind, is what a mutation
cannot get past. The radial was added for the one thing none of the five originally
targeted, the index arithmetic of the reduction itself; M5 exists because that gap
was noticed by asking *which check covers this line*, not by a failing test.

**F7 — the `ui/` manifest went stale the moment a core dependency changed, and
this time it said so immediately.** Adding `SparseArrays` to the root package made
`using GridSim` fail inside `ui/` with "Package GridSim does not have SparseArrays
in its dependencies", fixed by `Pkg.resolve()` there. The gitignored-manifest trap
has now caught this repo four times; the difference here is that it failed on the
first load rather than several steps later, because the export check was run in the
`ui/` environment as the standing rule requires. The check that exists for name
collisions found a dependency-graph problem, which is an argument for running it
where it lives rather than approximating it in the core environment.

---

## Step 3 — the nonlinear (AC) power flow (D6, D10, D11, D12)

Done 2026-09-07. Entered at **2996 core**; leaves **3175 core** (+179 in
`test/m6_steady_state.jl`). **UI 382 and `reference/` 986 — both RUN, exit 0, not
assumed** (see F12: this step edits `src/engines/detailed.jl`, which `reference/`
drives, so an unchanged count here is a measurement or it is nothing).

- [x] Residual equations written (polar form, real and reactive balance per bus),
      handed to `NonlinearSolve`. Ours are the equations; theirs is the solver (D2).
      `src/steadystate/ac_powerflow.jl` — **not an engine and not in the mode
      router**, for the same reason `dc_powerflow` is not.
- [x] Generator buses hold `P` and `V_set`; load buses hold `P` and `Q`; the slack
      holds `|V|` and angle and picks up the losses. **`Y` is sparse and checked
      structurally** (`nnz == n + 2m`, symmetric, `Y·1 = 0`), the second place
      `CLAUDE.md`'s never-a-dense-Y-bus rule binds our own code — and it is checked
      on the five-bus radial where 13 of 25 can tell sparse from dense, because the
      ring's 9-of-9 proves nothing (step 2's lesson, applied rather than repeated).
- [x] **The band discriminator inherited from `_check_power_flow`, not
      re-derived** — and "inherited" means the check itself, not the constant: the
      function was **split into three named checks** and both callers compose them
      (D10). The AC path runs band, ratings, residual. So does `_check_power_flow`
      now, which is the order its own docstring has claimed since M5 while the code
      ran the residual first — see F8.
- [x] **…and the band REJECTS, on a case built for it.** A load bus drawing
      `1.0 + j0.6` pu of constant power through `0.25` pu sags to the closed-form
      upper root of `V⁴ + V²(2QX − 1) + X²|S|² = 0` — and **the refusal's own
      reported magnitude is parsed out of the message and checked against that
      root**, because "outside the band" alone passed against a real sabotage that
      pushed the voltage out of the *other* side (F11). The rating check is
      likewise made to fire, on the lossy fixture with its ratings cut to 5 MVA.
- [x] Reactive-limit switching: a generator bus that hits `Q_max` becomes a load
      bus at its limit. **Bind-only, with the missing half refused by name** — see
      D12 and F9.
- [x] **Positive control for the limits:** limits set so wide they cannot bind
      reproduce the unlimited answer **exactly** (`==` on magnitudes, angles and
      both generation vectors). That is a constraint on the LOOP — the first solve
      is the unlimited solve and a round with no violation exits without re-solving
      — not only on the test (D12).
- [x] **Discriminating case for the limits, twice over.** A two-bus case whose
      answer is closed form (`Q_gen = (V₂² − V₁V₂cos θ)/X + Q_L` with
      `sin θ = −P_L X/(V₁V₂)`), so the binding value is written down before the
      solve; and a three-bus case with **two** candidate generator buses where
      algebra names one — a bus held at 1.05 above 1.0 neighbours with a lagging
      load on it must inject reactive power, so a ceiling of zero cannot be met —
      and the check is "this bus bound and that one did not", not "something bound".
- [x] **Positive control for the whole step: the band was stated before the gap
      was seen, and the fixture was then proved load-bearing.** Ratio of successive
      gaps predicted 8 from the truncation order, band [7.5, 8.5] written into the
      test file first. Measured **8.020 / 8.005 / 8.001** at λ = 0.4 → 0.05, with
      the smallest gap 1.06e-07 — three orders above the solve tolerance, checked
      *before* the ratios are formed (M4's rule: a number under the solver's own
      tolerance is not a result). Then the same check on the same topology with a
      **scaled reactive load** gives **4.220 / 4.106 / 4.052**, and both bands are
      asserted, non-overlapping. Without that second run the 8 would be a number
      any smooth solve produces; with it, it is a statement about which
      approximation is leading.
- [x] A losses check with `R ≠ 0`: the slack's pickup equals the summed branch
      losses. **Both sides are recomputed in the test from different data** — the
      left from the model's schedule plus the ZIP draw at the solved magnitudes
      with only the slack's own output from the solve, the right from `Branch.R`,
      `Branch.X` and the solved voltages. Neither touches the admittance matrix the
      residual was built on, which is what stops it being `ΣP_network = Σlosses` —
      an identity that holds for **any** `Y`, right or wrong, and is step 2's
      superposition finding in reactive form. **The bound is derived, not tuned:**
      `n · residual`, because the identity sums `n` bus equations each satisfied
      only to that.
- [x] Anti-vacuity mutation: the plan's named one (a sign flipped in the reactive
      residual) is **S3** below and goes red in four testsets. It was run as one of
      **six**, and the set includes the class step 2's F6 said it owed this step —
      a mutation that changes the **sparsity pattern** rather than a value in it.
      The blindness map is F10, and running it changed the suite twice.
- [x] `NonlinearSolve` added by `Pkg.add` — "**No packages added to or removed from
      Manifest**", step 0's zero-new-packages measurement confirmed a second time.
      `Project.toml` diffed after: nothing dropped, and the compat bound `Pkg` wrote
      (`"4.29.2"`) is correct as written — unlike step 2's `SparseArrays` case,
      `NonlinearSolve` is an ordinary package and a caret bound on it says nothing
      about the Julia floor (F5's lesson, applied and found not to bite here).
- [x] Exports checked against `names(GLMakie)` **in the `ui/` environment** (F7's
      rule): `intersect` still `Symbol[]` with `ACPowerFlow`, `ac_powerflow`,
      `bus_voltage`, `bus_generation`, `branch_reactive` and `branch_loss` added.
      **`bus_angle` and `branch_power` are deliberately NOT re-exported** — the AC
      solve adds methods to generics that already exist (M5 step 7's one-name rule).

### What this step found that the plan did not anticipate

**F8 — the check order the plan asked for was already the documented intent, and
the code had been contradicting it since M5.** `_check_power_flow`'s docstring
lists the band first and says of the residual "Listed third deliberately: it is
necessary and conspicuously not sufficient" — above a function that tested the
residual first and returned before ever reaching the band. Nothing was wrong with
the *answers* (every check must pass), only with which failure a doubly-bad solve
reports. Reading the function before changing it is what turned "add an ordering"
into "implement an ordering that was already written down", and the split into
three named checks (D10) is what let both callers have it without a second copy of
the discriminator.

**F9 — the back-off guard has no fixture, and that is why it is a function.**
Bind-only switching has exactly one state it must refuse: a bus on its limit that
ends up on the wrong side of its setpoint. Attempts to reach it from a model failed
in an instructive way — a floor set above what a bus wants makes it over-inject and
its voltage rises, which is the *correct* side and not the pathology. So the guard
is `_ac_assert_no_backoff`, exercised directly with a hand-built argument list
exactly as M5 exercises `_check_power_flow` with a hand-built collapsed voltage
vector, and checked to pass on both sensible sides so it is not simply always-on. A
guard for a pathology is the guard no fixture reaches by accident.

**F10 — six implementation sabotages, and TWO of them found a check reading its
answer from the source it was checking.** Each sabotage was applied to
`src/steadystate/ac_powerflow.jl` and the whole M6 suite re-run. All six go red —
but not before two checks were fixed, and the fixes are the finding:

  - **S1** off-diagonal sign flipped in `_ac_admittance`
  - **S2** one branch's off-diagonal pair never emitted — a **dropped
    contribution**, which changes the sparsity pattern rather than a value in it.
    This is the class step 2's F6 recorded as owed
  - **S3** sign flipped in the reactive residual (the plan's named mutation)
  - **S4** `_zip_scale` loses a power of `|V|` — the load model wrong everywhere
    except at `|V| = 1`, which is exactly where the cheap checks look
  - **S5** the reactive limit compared against the wrong bound
  - **S6** a branch's far end read in the near end's orientation

| check | S1 sign | S2 dropped | S3 Q-sign | S4 ZIP | S5 bound | S6 far end |
|---|---|---|---|---|---|---|
| admittance: sparsity / symmetry / `Y·1 = 0` / **is the DC `B`** | **red** | **red** | — | — | — | — |
| what is held and what is solved | — | — | — | — | **red** | **red** |
| two-bus closed form (θ and `Q_gen`) | **red** | **red** | — | **red** | **red** | — |
| small-angle rate control | **red** | **red** | — | — | **red** | — |
| losses identity (`R ≠ 0`) | **red** | **red** | — | **red** | — | **red** |
| **the ZIP scale IS the polynomial** | — | — | — | **red** | — | — |
| limits: wide ones cannot bind (`==`) | — | **red** | — | — | **red** | — |
| limits: algebra says it MUST bind | **red** | **red** | **red** | — | **red** | — |
| limits: EXACTLY that bus, of two | **red** | — | **red** | — | **red** | — |
| limits: back-off refused | — | **red** | — | — | **red** | — |
| **the `\|V\|` band REJECTS** | **red** | **red** | **red** | **red** | — | — |
| the rating check REJECTS | **red** | **red** | — | — | — | — |
| the three checks, split not copied | — | — | — | — | — | — |
| the refusals, each by name | — | — | — | — | — | — |
| two machines on a bus sum | **red** | **red** | — | — | **red** | — |
| superposition FAILS here | **red** | — | — | — | **red** | — |
| `R` is READ here | **red** | **red** | **red** | — | — | **red** |

**The two rows in bold arrived because the run demanded them, and the first
version of this table is the argument for running mutations at all:**

  - **S4 was caught by exactly ONE check** — the two-bus closed form. Not by the
    losses identity, and the reason is that the losses test computed the load's
    draw by calling `GridSim._zip_scale`, *the very function the sabotage broke*.
    A check that reads its answer from the source it is checking is not a check.
    The test now writes the ZIP draw out as the textbook polynomial
    `a_z|V|² + a_i|V| + a_p`, and a new testset pins `_zip_scale` against that
    polynomial directly. S4 went from 1 red to 4. **The general rule this yields,
    and it is not confined to loads: no check of a model may evaluate that model
    through the function under test** (D11).
  - **S3 was NOT caught by the band case**, the one fixture with a genuine PQ load
    bus. With the reactive sign flipped, the bus *injects* 0.6 pu instead of drawing
    it and floats far ABOVE 1.1 — so the band still fired, the message still said
    "outside", and the test passed **against the bug it sat closest to**. "Outside"
    is not a check; the side is. The refusal's own reported magnitude is now parsed
    out of the message and compared to the closed-form root of the PV curve, which
    is a number on a side. S3 went from 3 red to 4, and the band case became one of
    the four strongest checks in the file.

**Two structural notes, both the same shape as step 2's.**

  - **No single check carries this step.** Step 2's three-bus split went red under
    all five of its sabotages; here the best any one check manages is **four of
    six**, and it takes a *pair* to cover the set — the two-bus closed form (S1,
    S2, S4, S5) with "`R` is READ here" (S1, S2, S3, S6), which is to say a
    fixture with no losses together with one whose entire content is losses. That
    is a property of the tier, not a weakness of the fixtures: the AC solve has
    four largely independent surfaces (the matrix, the reactive side, the load
    model, the limit logic) and no one case exercises all of them.
  - **Two testsets are red under nothing, correctly.** "The three checks are the M5
    ones, split rather than copied" and "the refusals, each by name" both run
    before or beside any solved number — one unit-tests the extracted guards with
    hand-built inputs, the other tests rejections that happen before the solver is
    reached. Neither is evidence about the solve, and neither pretends to be.

**A limit of THIS mutation set, recorded so step 4 does not inherit it.** S5's
breadth (9 testsets) is partly an artifact: with `Q_min` defaulting to `-Inf`, a
swapped comparison is *always* true, so every generator bus switches to an
infinite limit and every case turns pathological at once. A mutation that breaks
everything says less than one that changes an answer subtly — S3, S4 and S6 are
the informative ones here. Step 4's mutations should prefer sabotages that leave
the solve well-posed.

**F12 — step 1's criterion harness is BLIND to the path this step changed, and
saying "unchanged" about a suite nobody ran is the M4 step 5 failure.** Two claims
in this step's first draft were arguments rather than measurements, and both were
checked afterwards:

  - **"UI and `reference/` unchanged in count."** This step edits
    `src/engines/detailed.jl` twice, and `reference/` compiles its oracle from
    `NetworkModel` and drives the detailed tier — it is the suite most likely to
    notice. Both were then run: **382 UI, 986 reference, exit 0 each**. The counts
    were right; they were not evidence until they were run. `m4-context.md` D15 is
    the precedent — same counts, measured against a manifest nobody had checked.
  - **`_zip_k`'s docstring claims the constant-impedance path is "bitwise the
    arithmetic M5 measured".** Step 1 built the tool for exactly this claim
    (`criterion_snapshot.jl` plus `criterion-STEP1.txt`), and re-running it gives
    the **same MD5** (`c79b7c07d039b66efdeff10e45e88305`) — so the
    `_check_power_flow` split moved nothing. **But that capture cannot see the
    change the docstring is actually about:** `scripts/iberia_two_area.jl` builds
    **no `Load` at all** — its consumers are negative-`P0` machines — so it never
    reaches `_load_current`, let alone `_zip_k`. A harness whose whole purpose is
    "no number moved" is only as wide as the models it runs, and step 1's is
    narrower than its name suggests.

    So a second capture was built for the path in question: `DetailedEngine` over
    5 s on `load_bus_system` at four ZIP corners — the mixed 0.2 / 0.3 / 0.5 case
    where `_zip_k` runs on every load-current evaluation, the two single-share
    corners, and the default that must not reach `_zip_k` at all — with every
    channel printed at shortest-round-trip precision. Captured with the
    pre-extraction body restored in place (so nothing but the extraction differs)
    and again at HEAD: **72 lines, same MD5** (`363e1b7…`). The docstring's word
    is now a measurement.

**F11 — `Pgen` is read back, not copied, and that decides two `==` vs `≈` calls.**
The reported generation at a bus is `P_network + P_load` from the solved answer
rather than the schedule copied through, so a non-slack machine's output matches
its schedule only to the residual (4e-16). Copying would have made "the machine
produces its schedule" vacuous. Related and separate: the lossless `Y` is **not**
bitwise the DC `B` — `inv(complex(0.0, X))` is one ulp off `-1/X` for some
reactances and exact for others (measured; the real part is exactly zero
throughout), so that cross-check is bounded in ulps of the largest susceptance
rather than asserted with `==`.

---

## Step 4 — the two oracles (D5, hurdle 8)

### Oracle A — the flat run (ours, no dependency) — **DONE (2026-09-07)**

- [x] A solved power flow back-substituted into machine states and fed to
      `DetailedEngine` as its initial condition. `init!` gains one keyword,
      `powerflow = nothing`; everything after the solve — the back-substitution, the
      `Vref` derivation, the `Efd` limit check and both residual checks — is the
      **same code on either path**, and `_read_static` now returns the terminal
      current so that the two paths cannot come to hold two back-substitutions.
      The current comes from the flow's own `S` (`I = conj(S/V)`, `Ẽ = V + (Ra+jXq)I`,
      `δ = arg Ẽ`) and **never** from `Machine.E′` — routing it through
      `_machine_injection` would have made the flat run re-test the solve it exists
      to cross-examine.
- [x] **The run is flat** — 1.5e-13 worst over **50 s** on five fixtures, at two
      tolerances, plus a third pass at `dtmax = 0.1` because the solver crosses the
      horizon in **five accepted steps** if left alone (M5 step 1's rule). 50 s and
      not 10 because `detailed_pair`'s slowest mode is `Td0′ = 8 s`.
- [x] **Anti-vacuity — and the plan's single sentence does not survive contact.**
      "Perturb the solved solution and confirm the run is not flat" cannot be done: a
      perturbed voltage violates the algebraic block, so `init!` throws and there is
      no run. Split into (a) a bent solution is refused at build time, and (b) `Pm`
      overwritten with the schedule moves the run by 6.6 rad. Only (b) is the
      anti-vacuity check.
- [x] The failure mode named in the test: this check is what makes the repo's two
      steady-state sources agree without either being declared correct (D5) — and
      **they really are two sources**: measured 2.4e-2 to 2.5e-2 pu apart in voltage,
      6.3e-3 rad apart in angle, 5.0e-2 pu apart in the slack's dispatch.
- [x] **The mutation set was run, and it found the hole (D13).** Ten mutations across
      two fixtures. Every bug in the flow's *equations* is caught by the
      dynamic-network residual or the `|V|` band. Every bug in the flow's
      *generation schedule* was **blind** — flat to 8.6e-14 with the scheduled `P`
      scaled by 1.1, flat to 5.1e-13 with `V_set` misread by 2 % — because `Pm` and
      `Vref` are derived from the solved voltages, so a wrong schedule is still a
      fixpoint. Closed by `_assert_seed_is_this_dispatch`, in `src/` and not in a
      test; all four then refuse by name, at the right bus.
- [x] **Two of the ten mutations were no-ops on the fixture they were first run
      against, and the first reading of the table was wrong because of it.**
      `load_bus_system`'s machines have `Xq = Xd′ = Xq′` and `Tq0′ = Inf`, so
      "swap `Xq` for `Xd′`" is arithmetically the identity and "take `δ` from the bus
      angle" costs nothing with the flux equations frozen. A mutation that does not
      mutate looks exactly like a check that does not check. Both fixtures now run.
- [x] **Both refusals this oracle was designed around were already there (D14).** The
      lossy-branch and multi-machine guards written into `_seed_from_powerflow` are
      dead code — `_assert_detailed_tier` refuses both models first — and one of the
      two messages was *false*. Deleted; the test that found it is kept, asserting
      the tier's guards fire on both paths.
- [x] **A third piece of dead code, in the same batch**: the seeded branch also wrote
      the AC answer into `u_static` with a comment claiming an event re-seeds from it.
      `_reinitialise_algebraic!` overwrites every entry it reads. Deleted, and the
      stale `p_static[sPset]` left with the *true* reason (`_PF_HOLD` never reads
      `Pset`) — now a measurement, because a **seeded engine runs across a line trip**
      in the suite.
- [x] **The binding reactive limit is exercised on the seeded path** — step 3's
      `_ac_two_bus(Q_max = 0.25)`, the one branch of the new dispatch guard that no
      sweep fixture could reach.
- [x] The cost recorded rather than hidden: **oracle A can never see a lossy branch**,
      so the resistive half of `ac_powerflow` is now a *requirement* on oracle B
      rather than a nice-to-have — written as **boxes** in oracle B's list, not as
      prose here (M3 step 7's rule: an item carried without a criterion is the one
      that gets dropped).

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
- [ ] **A LOSSY case (`R > 0`), which oracle A structurally cannot reach** (D14).
      With `R = 0` our loss channel is zero and `flow + flow_rev` vanishes, so the
      resistive half of `ac_powerflow` — the only thing `Branch.R` was added for —
      has no internal check at all. Written as a box rather than left in oracle A's
      prose, because an item carried without a criterion is the one that gets
      dropped (M3 step 7, learned on Figure 3-67).
- [ ] **A case with a BINDING reactive limit**, which oracle A is blind to for the
      reason D13 names: a bus wrongly switched to a limit holds a `Q` nobody
      scheduled and its magnitude becomes an unknown, so neither of the seeded
      path's dispatch comparisons applies and the run is flat anyway. Only an
      external solve on the same case can say the wrong bus was limited.
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

- [~] `docs/validation-ledger.md` gains a steady-state section, every row labelled,
      `un-oracled` rows stated out loud. **Opened at step 2** with the step 1 and
      step 2 rows; step 3's AC rows added, including the two `un-oracled` rows that
      step 4's two oracles close. Not ticked: step 4's oracle sections are owed.
- [~] `docs/plans/README.md` M6 row updated as steps land. Updated at steps 1-3;
      stays open until the milestone closes.
- [x] `docs/SPEC.md` §9 item 5 annotated (step 0's second open box) — the refused
      half struck through in place, with the reason and D1's measurement pointed at.
- [x] `docs/SPEC.md` §8's "no hand-rolled power-flow math" line annotated with D2's
      reading, so the split between equations and solver is documented where a
      reader meets the rule rather than only where it was argued. Done at step 0;
      step 2 is the first code the annotation actually describes.
- [ ] Re-resolve all three environments from deleted manifests at the end and
      **measure** the counts there — the gitignored-manifest trap has caught this
      repo three times (`m4-context.md` D15, the 2026-08-18 stale dev manifest, and
      `ui/`'s silently ignored `[sources]`).
- [~] `git diff` every `Project.toml` after every `Pkg` operation and put the
      dropped comments back. Done for step 2's `SparseArrays` add: nothing was
      dropped (the root file carries no comments), but the **compat bound had to be
      corrected** — see step 2's F5, where `Pkg`'s `"1.12.0"` would have raised the
      package's Julia floor from 1.10 to 1.12 in silence. Done again for step 3's
      `NonlinearSolve` add: nothing dropped, and the bound `Pkg` wrote is right this
      time — F5 bites only on a **versioned stdlib**, and `NonlinearSolve` is an
      ordinary package whose caret bound says nothing about the Julia floor.
