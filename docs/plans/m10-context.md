# M10 context — decisions, and what the steps actually measured

Companion to `m10-plan.md` (the how) and `m10-tasks.md` (the checklist). This file
is where a decision is argued once, with the measurement behind it, so nobody
re-litigates it from the code. Read it before disagreeing with the plan.

Convention carried from M2–M9: decisions are `D<n>`, numbered in the order they
were *taken*, not the order the steps run. A section headed "What step N measured"
is added underneath a decision when a step either confirms it or destroys its
stated reason.

---

## D0 — Why this milestone, and the hurdles it exists for (named BEFORE the plan)

M9's close left `docs/plans/README.md`'s hurdle list empty a fourth time. The topic
was the user's choice (2026-10-18), picked from the roadmap items M8 left unbuilt
(`SPEC.md` §9 item 8, "double outages"): **double-outage screening** — "what if
these two elements fail", asked of every pair. This section was written after a
step-0 measurement (D1) and before the plan.

**Why "M8, run on pairs" is not enough.** Brute force needs nothing new for a pair
that leaves the grid in one piece: rebuild without both and re-solve. Four things
stop that from being the whole answer, and each is a hurdle.

- **Hurdle 18 — A two-element shortcut that is exact on its own model, and a pair
  that cuts the grid decided from the graph.** Losing branches `k` and `l` together
  is a rank-two change to the DC susceptance matrix. The post-outage flow on `m` is
  `f_m + [PTDF_mk PTDF_ml] · M⁻¹ · [f_k; f_l]`, with
  `M = [1−PTDF_kk, −PTDF_kl; −PTDF_lk, 1−PTDF_ll]` in transfer terms. Exact in DC,
  as M8's single-outage factor was. Four measurable claims:
  1. **Exact against its own model.** Matches rebuild-and-re-solve DC flows to
     round-off on every connected pair. **Measured at step 0 (D1): the only
     fixture with connected line pairs is the mesh (19 of 21). case9 has none —
     every one of its 36 line pairs splits it.** So the exactness check runs on the
     mesh, and the sabotages are placed in the pair code, not in the shared
     builders (M8 Hurdle 13.1's reason).
  2. **Adding two single-outage factors is wrong, measurably.** The common shortcut
     `f_m + LODF_mk·f_k + LODF_ml·f_l` ignores that each loss changes where the
     other's flow goes. It is exact only when `PTDF_kl = PTDF_lk = 0`. Its error is
     measured on the mesh, never predicted in size, and a fixture where it is zero
     (two lines whose transfers do not cross) is the anti-vacuity control.
  3. **A cut pair is decided from the graph, never from `det M`.** A pair can cut
     the grid while neither line is a bridge (case9's ring: 15 of its 36 pairs).
     Then `det M = 0` in exact arithmetic and comes out as round-off in floating
     point, with either sign — M8 Hurdle 14 one dimension up. The pair is checked
     for connectivity on the graph with both removed. A near-cut fixture (a third
     path of large reactance) states its accuracy band, `~eps/|det M|` relative,
     **before** the run, and its scaling across two reactances is the signature.
  4. **Without a re-adjustment, the order of the two losses does not change where
     the grid settles — checked dynamically, because statically it cannot fail.**
     In the static screen it holds **by construction**: the DC flow is a function
     of the final topology and M8's pickup rule of the total loss, so "A then B"
     computed statically *is* "both at once". It is stated, not tested there. The
     question with content is whether the dynamic tier, which really does pass
     through the state after A, settles to the same place: **the swing tier, trip
     A, settle, trip B, settle, against both tripped at once**, on every pair kind
     and on a fixture where the first loss caps a governor (the place a path
     dependence would hide; the cap must be seen to bind, the positive control).
     **Forbidden:** computing a no-restore sequential pair by rebuilding the model
     with `P0 + pickup_A` and screening again. That silently returns frequency to
     target between the losses — a restore, with shares weighted by droop *and*
     damping, which is neither timing the user chose (reviewer, 2026-10-18). This
     is what makes Hurdle 21 need a rule at all.

- **Hurdle 19 — A grid cut in two keeps running as two grids.** M8 answered a
  split with no numbers. On case9 that would leave every line pair blank. Each
  piece left behind is one of three things, and **measured at step 0, case9's 36
  line pairs are: 9 leave two pieces that each hold a source and a load, 3 strand a
  load with no source, and 24 cut off a lone generator (one or two of them)**.
  Five measurable claims:
  1. **Each live piece settles at its own frequency, by M8's rule run inside it.**
     A piece's imbalance (its sources' schedule less its loads) is shared by the
     droop and damping of its own machines alone. One piece usually has a
     **surplus**, so its frequency rises while the other's falls. M8's pickup
     solve already handles a surplus (`_pickup_solve`, the `P_lost < 0` branch:
     no down-floor, as the swing tier has none), read before this was written.
  2. **The swing tier is the exact oracle, per piece.** Lossless, loads as
     negative-`P0` machines (the swing tier refuses `Load`, M8 step 4), lines
     tripped at the same instant (the swing tier's `TripLine` zeroes a coupling and
     re-solves nothing, so two at one instant are one event there). Each machine's
     settled `ω` equals its own piece's static `Δω`. **Every whole-grid quantity is
     replaced by its per-piece version or not used**: the centre-of-inertia average
     (across pieces a weighted mean of two unrelated numbers, `engines/swing.jl`
     header), a settling test on `coi_rocof` (M9's run helper stops on it — one
     piece still moving hides behind another at rest), and any `Σw`. Settling is
     judged per piece, on that piece's machines.
  3. **A piece with load and no source is load lost**, a named outcome carrying its
     MW, and the rest of the grid sees it as a load drop — frequency **rises**. Not
     an error and not a split. **Classifier rule:** a machine with `P0 < 0` counts as
     a load, not a source — that is how the swing-tier fixtures write loads, and
     without the rule a stranded "load" there would land in claim 4 instead. **What
     the swing tier can and cannot check here:** the rest of the grid's response to
     the stranded load, yes; the stranded piece itself, no — there it is a machine
     with its own damping, spinning to its own speed, excluded by name. This
     claim's only dynamic check of the dead piece is the detailed tier with real
     loads (Hurdle 20.3, step 4).
  4. **A piece with a source and no load is that source lost**, M8 D9 generalised:
     its generators leave, and the rest shares their schedule. **In the dynamic
     tiers this is carried out, not assumed:** opening the lines alone leaves the
     cut-off machine running on to its own large speed deviation, which is not
     "lost". So the simultaneous event trips that machine in the same instant, in
     both tiers. That is 24 of case9's 36 line pairs.
  5. **In AC each live piece needs its own shared reference**, its own losses, and
     its own reactive limits. M8 step 5's shared-reference solve assumes one
     connected grid; it is run per piece, and its degeneration — a piece that is
     the whole grid — is M8's own solve, bit for bit or to a stated band.

- **Hurdle 20 — "At the same instant" must be one event in the detailed tier.**
  The detailed tier re-solves the network's voltages after every event. **Measured
  at step 0 (D1)**, two `TripLine`s at one instant go through a network with only
  the first line out, and that intermediate network can be refused when the final
  one is fine: case9 default loads, L45 then L67 — the first re-solve refuses (B5
  at 0.898 pu), the second passes. Three measurable claims:
  1. **One event, one re-solve.** A simultaneous outage of any set of elements is
     applied as one event, and its re-solve sees only the final network. The
     L45+L67 case above is the positive control: refused today, run after.
  2. **A refused trip leaves nothing half-done.** **Found at step 0, predates
     M10:** `inject!(::DetailedEngine, ::TripLine)` opens the line, then throws
     from the re-solve — so a caller that catches the error is left with the line
     open, the event unlogged, and the voltages stale; the run then integrates on.
     The spike did exactly that and got a plausible-looking frequency. A refused
     event either changes nothing or leaves an engine that refuses to run on; which
     one is decided at the step, by measurement. **The out-of-step relay reaches the
     same `inject!(::TripLine)` from inside a solver callback** (`detailed.jl`, the
     relay affect), so the fix is tested on that path too, not only the direct call.
  3. **A dead piece is switched off, not solved.** With a load stranded, the re-solve
     tries to find its voltage: **measured, 1.8e9 pu on constant-power loads (and
     the integration aborts), 0.0 pu on constant-impedance ones (and it runs)**.
     Neither is an answer to a question anyone asked. A bus with no path to a
     source is de-energised by the graph — its loads off, its voltage out of the
     solve — on both load models.

- **Hurdle 21 — Fail, restore, fail again.** The second timing the user chose
  (D2). Hurdle 18.4 says the two timings settle the same unless something acts in
  between, so the rule in between is the whole content. The user chose **restore
  50 Hz** (D3). Four measurable claims:
  1. **The restored state is exact.** After the first loss, frequency is back on
     target in every live piece, every remaining governor carries its share of
     that piece's imbalance in proportion to its gain, capped at its headroom, the
     excess re-shared by walking the caps exactly as M8 step 4 walks them. No
     root-finder, no tolerance.
  2. **Restoring can be refused where settling cannot.** With damping, M8's settle
     always has an answer (Hurdle 15.4). Restoring puts frequency back at target,
     so damping carries nothing, and a loss larger than the piece's remaining
     headroom has no restored state. A named outcome, never silently replaced by
     the settled one.
  3. **The second loss is a single-outage screen of the restored grid** — the same
     numbers as M8's screens on a model rebuilt with the first element gone and the
     restored schedule. **Stated, not checked: it holds by construction** (it is the
     same code on the same model). The independent check on this hurdle is the
     **dynamic run**: the detailed tier initialised on the restored model, the
     second element tripped, its per-piece settled frequency against the screen's
     through M9's losses identity taken per piece. So that run is **not** on the
     cut-first list.
  4. **Order matters, and the two timings differ — measured, not predicted in
     sign.** A then B, B then A, and both at once are three answers. A restored
     state has less headroom, so the second loss can push frequency further than
     the simultaneous pair does; it can also leave the flows better placed. Which
     happens on the report grids is read from the table, and the claim is written
     after (M3 step 6's rule).

---

## D1 — Step 0 measured the pairs before the plan named anything

Two scripts, both on M8's report grids as `scripts/outage_screen.jl` builds them
(case9 without line charging, invented droop; the invented five-bus mesh):
`docs/evidence/gridsim-m10/step0_census.jl` and `step0_islands_spike.jl`, outputs
beside them (`*.out.txt`).

### Every pair of line outages, classified

What is left after removing both lines: one piece (`connected`), or several, each
tagged by what it holds — `S` a source, `L` a load, `S+L` both.

| Grid | Line pairs | Result |
|---|---|---|
| case9 | 36 | **all 36 split.** 9 `S+L \| S+L`; 3 `L \| S+L` (a load bus cut out of the ring); 3 `S \| S+L` from two ring lines (a ring bus cut out together with the generator hanging off it, no load); 18 `S \| S+L` from a bridge plus a ring line; 3 `S \| S \| S+L` from two bridges |
| mesh | 21 | 19 connected; 2 `S \| S+L` (AB+AC cuts off A, DE+BE cuts off E — each a lone generator, A's being the reference machine's) |

So the shortcut's exactness check can run on the mesh alone; every case9 line pair
is either a lone-generator loss under M8 D9 or a real split; and the mesh has **no**
real two-piece case. The reviewer's prediction, made from the topology before the
census ran, matched all six counts.

**Counting pairs of every kind** (lines and generators, D2): case9 has 12 elements,
66 unordered pairs; the mesh 10 elements, 45. Small enough to screen every pair;
nothing is filtered (D5).

### Two case9 lines at once in the detailed tier

Tripped as two back-to-back `TripLine` injects at `t = 1 s`, FBDF at reltol 1e-8, run
to 60 s. The script prints every refusal and **keeps going on purpose**, to see what a
refused trip leaves behind.

| Loads | Pair | First re-solve (one line out) | Second re-solve (both out) | Run |
|---|---|---|---|---|
| constant power | L45+L67 (two live pieces) | refused, B5 0.851 pu | refused, B5 0.866 pu | ran to 60 s on stale voltages: G3 +0.0016 pu, G1 −0.0010 pu, G1 not settled |
| constant power | L45+L56 (B5 stranded) | refused, B5 0.851 pu | refused, **B5 1.83e9 pu** | integration aborted at 1.0 s (`dt` below eps) |
| default | L45+L67 | refused, B5 0.898 pu | **passed** | ran: G3's piece +0.00459 pu (+0.23 Hz), G1/G2's −0.00117 pu (−0.058 Hz) |
| default | L45+L56 | refused, B5 0.898 pu | refused, **B5 0.0 pu** | ran: every machine +0.00457 pu (+0.23 Hz) — D5's 90 MW gone |

What that settles:

- **The two pieces really do go opposite ways** (default, L45+L67). For scale, M8's
  rule on the lossless DC model with constant-power loads predicts +0.00242 pu for
  G3's piece (13.7 MW surplus over G3's 56.7 pu of droop and damping) and −0.00119
  pu for the rest (115.5 pu). The detailed run on default loads is a different
  model (lossy, voltage-dependent loads) and is **not** a check of that number —
  the planned check is Hurdle 19.2's swing-tier run.
- **The intermediate network is the problem** (Hurdle 20.1): the default-load
  L45+L67 run is refused on its way to a network that passes.
- **A refused line trip is half-applied** (Hurdle 20.2). Read in the source
  afterwards: `inject!(::DetailedEngine, ::TripLine)` sets the line's status to
  open in both networks and drops it from `lines_online` *before* calling
  `_reinitialise_algebraic!`, which throws. M9's generator path returns the
  refusal instead and abandons the engine, so M9 was never exposed; a caller of
  `inject!` that catches is.
- **A stranded load bus is solved, not switched off** (Hurdle 20.3), with the two
  load models giving two different nonsenses.

---

## D2 — The user's four choices (2026-10-18)

Asked in plain words, with a recommendation on each.

1. **Timing: both kinds** — both elements at the same instant, *and* one, then a
   re-adjustment, then the other. (Recommended: same instant only. The user chose
   both; Hurdle 21 exists because of it.)
2. **Scope: lines and generators** — every pair: two lines, two generators, one of
   each. (Recommended.) On case9 a line pair is mostly a generator loss anyway.
3. **A grid cut in two: solve each piece**, each at its own frequency.
   (Recommended.) The alternative, "report a split", would have left all 36 case9
   line pairs without numbers.
4. **The re-adjustment between two failures: restore 50 Hz** — the remaining
   generators bring frequency back, each taking extra output in a fixed proportion.
   (Recommended over the cheapest re-dispatch, which only case9 has cost data for
   and which ignores lines, and over an overload-relieving re-dispatch, which needs
   the network optimal power flow that is still blocked.)

---

## D3 — What "restore 50 Hz" means here, made exact

The user was offered "each taking on extra output in a fixed proportion" without
the proportion named. The plan names it: **in proportion to each unit's governor
gain** — `1/R` on the system base from `machine_arrays` for a machine, `1/K_p` from
`_inverter_arrays` for a grid-forming inverter, the same two weights M8 D2's settle
reads, never rebuilt beside them. That is the participation a governor already
expresses, so restoring changes *how far* each unit moves and not *which* units
move. The alternatives — equal shares, shares by rating, by headroom — would each
be a new number with no source.

- **Damping takes no part.** Frequency ends on target, so `−Δω·D` is zero.
- **Caps:** a machine stops at its headroom (`Pmax − P0`) and the rest is re-shared
  among the uncapped — M8 step 4's bend walk, at `Δω = 0` instead of at the settled
  `Δω`. A grid-forming inverter has no cap (M8: `h = Inf`).
- **Per piece.** Each live piece restores its own frequency from its own units.
- **Refusal:** a piece whose remaining headroom is smaller than its imbalance has
  no restored state (Hurdle 21.2).
- **The floor — `Machine.Pmin` is honoured when given.** Restoring is a dispatch,
  and M6's dispatch treats `Pmin` as its constraint (`network_model.jl`: "the
  minimum is the dispatch's constraint"). So a surplus piece restores downward
  until a unit reaches its `Pmin`, the rest re-shared exactly as on the way up, and
  a piece that runs out of room downward is refused the same way. Where `Pmin` is
  `NaN` (not given — both report grids), there is no floor. **Said plainly: the
  settle has no floor at all** (neither dynamic tier has one, M8 step 4), so a
  piece with a large surplus can settle — and, without `Pmin`, restore — with a
  unit **below zero output**: a generator absorbing power. The report flags every
  such unit rather than leaving it to be noticed.
- **What the restored state is:** a new schedule. The second loss is screened on a
  model built with the first element gone and every unit's `P0` set to its restored
  output (Hurdle 21.3). Losses in AC are part of what the piece's units cover, by
  the same proportion — so the restored AC state needs the shared reference at
  `Δω = 0`, which is M8 step 5's solve with the frequency term fixed.

If the user objects to the proportion, this is the decision to reopen; nothing
before step 5 reads it.

---

## D4 — What a "pair" is, and when two are one

- **Simultaneous pairs are unordered**, of two distinct elements; **sequential
  pairs are ordered** (A then B is not B then A, Hurdle 21.4).
- **Elements are what M8 screens:** every branch, and every source M8's generator
  screen takes out.
- **Two names for one event collapse.** Under M8 D9 a bridge to a lone source *is*
  that source's outage, so on case9 "L14 and G1" is G1 lost once. Such a pair is
  reported as the single outage it is, by name, and never as a double. case9 has
  three such pairs (L14+G1, L82+G2, L36+G3), read from its topology; the mesh none
  (it has no bridge).
- **What makes a piece live:** a machine with `P0 ≥ 0` or a grid-forming inverter.
  A piece holding only grid-following inverters and loads has nothing to set its
  frequency — the detailed tier already refuses that state (M7 D5) — so its
  inverters are lost with it and its load is lost. The report grids have no
  inverters; this is stated so the classifier is written with it.
- **A piece's outcome is per piece.** A pair that splits the grid reports one
  outcome per live piece (M8's outcome kinds), plus the load lost and the sources
  cut off, each with MW.

---

## D5 — What M10 is not

- **No filtering or ranking of pairs.** Real tools screen only the pairs a cheap
  pass flags; at 66 and 45 pairs every pair is screened, and filtering is a
  scale question for the batched/GPU item that stays unbuilt.
- **Not more than two.** No N-3 and beyond.
- **No dip or rate verdict per pair.** M9's settled verdict is read per live piece
  (cheap, both screens). The detailed tier is run on pairs only as the oracle for
  Hurdles 19 and 20, not as a per-pair dip screen. Lifting this is a later choice.
- **No re-dispatch beyond restoring frequency.** Neither the cheapest re-dispatch
  nor an overload-relieving one (D2.4).
- **No secondary control in the dynamic tiers.** Restoring is static (D3). A
  dynamic run of a sequential pair starts from the restored model and trips the
  second element only.
- **Still unbuilt from M8 D5:** the map, batched/GPU runs, line charging, load
  shedding inside the screen.

---

## D6 — What a review of the committed plan changed (2026-10-18, same day)

The plan was committed (`c053b8b`) and then reviewed. Three checks as written would
have measured nothing or the wrong thing; each is fixed above, in place:

1. **Order-independence (18.4) and the restore identity (21.3) hold by construction
   in the static screen**, so a static test of either cannot fail. 18.4 moved to
   the swing tier (trip, settle, trip, settle); 21.3 is stated, and Hurdle 21's
   independent check is the dynamic run, which came off the cut-first list. The
   obvious way to compute a no-restore sequential pair — rebuild with the first
   pickups and screen again — is a hidden restore, and is forbidden.
2. **Whole-grid read-outs mean nothing across pieces.** M9's run helper settles on
   `coi_rocof`, and its losses identity divides by the whole grid's `Σw`; both are
   taken per piece. And a lone generator cut off by its lines spins on rather than
   being lost, so the dynamic event trips it in the same instant (19.4).
3. **The swing tier cannot see "load lost"**: its loads are machines. A `P0 < 0`
   machine now classifies as a load, the swing tier checks only the rest of the
   grid's response, and 19.3's own check is the detailed tier (step 4).

And three additions: the out-of-step relay's path into the half-applied trip is
tested with the fix (20.2); `Pmin` is honoured by the restore and the unbounded
downward settle is stated, with units below zero flagged (D3); a piece with only
grid-following inverters is not live (D4).

---

## D7 — What the pair code holds, and why M8's function is not touched (step 1)

Hurdle 18.1 asks for one solve per branch, reused across every pair the branch is in,
and M8 D4 refuses to form the PTDF (branches × buses, dense). Holding every per-branch
solve's **bus angles** would be that matrix under another name. So the pair code keeps
only what a pair reads: column `k` is every branch's flow per unit transfer across `k`
— a **branches × branches** table, built one column at a time against the single
sparse factorisation, each solve's angles dropped as in M8. It is the size of M8's own
outage table (`DCLineOutages.flow`, which D4 accepted as "the size of the question")
and far smaller than the pair table it feeds (pairs × branches).

**`dc_line_outages` is left exactly as it was.** The pair code has its own copy of the
per-branch loop (`_dc_transfer_factors`), so M8's gate holds **by construction** — not
as a test of a refactor. A refactor that solved many columns at once could move the
last bits; a copy cannot move M8 at all. The cost is two copies of ten lines, and a
test holds them together: `1 − P[k, k] === margin[k]` and M8's single-outage flows
rebuilt from the copy's columns `===` M8's own, on both report grids.

### What step 1 measured (2026-10-18)

`docs/evidence/gridsim-m10/step1_predictions.md` (written first) and
`step1_pairs.jl`; tests in `test/m10_double_outages.jl`.

- **Exact (18.1).** On the mesh's 19 connected pairs the pair factors equal
  rebuild-and-re-solve within 0.005–0.119 of M8's band (100·eps·max|f|).
- **The shortcut is wrong on every pair (18.2)** — all 19, by 9.8e11 to 2.5e13 times
  the band. The control, two triangles sharing one bus, gives the shortcut's exact
  case on all 9 cross pairs (the cross factors are round-off), and its 6 same-triangle
  pairs are cuts.
- **Cuts from the graph (18.3).** case9's 36 and the mesh's 2 (AB+AC, DE+BE) are
  exactly the rebuild refusals, 15 of case9's with neither line a bridge. `det M` at
  every cut is round-off, |det M| ≤ 2.6e-16, negative, −0.0, 0.0 and positive all
  present. With two bridges it is an exact zero; with a ring pair never.
- **Near-cut.** A weak A–D path of reactance Xw makes AB+AC connected; each line's own
  margin stays moderate (0.243, 0.486) while det M = 0.0486/Xw. The
  factors' error grows with it (2.8e-12, 3.6e-10, 3.3e-8 at Xw = 1e3, 1e5, 1e7), always
  0.005 of the stated `100·eps·scale/|det M|`.
- **Found, not planned: the rebuild is NOT the oracle at a near-cut whose reference
  sits on the nearly cut-off bus.** There every other angle is ~1.5·Xw rad and each
  flow is a difference of two such numbers, so the rebuild drifts 1.2e-11 / 1.0e-9 /
  1.2e-7 — four times the factors' own error. With the reference on the main grid it
  is exact (≤ 2.3e-16). M8 step 2's near-bridge happened to have its reference on the
  main grid, which is why it found the rebuild exact. The near-cut check therefore
  compares against the closed form (A–D carries G1's whole injection; the rest is the
  four-bus grid with that injection moved to D), and asserts both halves of the
  attribution.
- **Sabotages, all four run** (three planned + a bridge-only cut test): each is red in
  the testsets predicted. One more than predicted: replacing `M` by its diagonal also
  turns the cut check red, because `det M` at a cut is then `(1−P_kk)(1−P_ll)`, no
  longer round-off. A transposed `M` is invisible on the equal-reactance pairs and on
  the control, as registered, and caught by the unequal ones.

## D8 — How step 2 reads a piece (2026-10-18)

`dc_pair_outages` (`src/steadystate/double_outages.jl`) screens every pair of M8's rows —
branches in model order, then machines — so case9 has 66 pairs and the mesh 45. The
pieces come from the graph with the pair's branches removed, and each is one of four
kinds (D4): **live** (a source and a load: shares its own imbalance by M8's rule, with
the piece as the `alive` mask), **sources lost** (a source, no load), **load lost** (no
source; its grid-following inverters go with it), **empty**. A `P0 < 0` machine is a load,
never a source (D6.3).

**A live piece's imbalance is read from the base case**: the schedule of the machines the
pair took out of it, plus what it imported across the pair's branches (base DC flows).
So a whole-grid pair's imbalance is EXACTLY the lost schedule (`0.0` for two lines; a
test holds it with `===`), and a split charges each side with what crossed the cut. The
alternative — summing each piece's injections — gives the same number to round-off,
and would also share out whatever the reference absorbed from a schedule that balances
only to the model's guard (|ΣP| ≤ 1e-6·S_base). **The tests read it the other way**,
from the equipment list, so the check is not the screen's own arithmetic.

**Flows.** Whole grid: two lines reuse step 1's rank-two flows bit for bit (step 1's
loop was moved into `_dc_line_pairs(net, base, P)`, same operations, so step 1's tests
are its gate); otherwise the new injections are solved on the base factorisation, and
a line + machine pair then applies the line's single-outage factor to those flows.
Split: one fresh sparse factorisation of the network without the two branches, one
reference per piece (the model's slack where it lies in the piece, else the piece's
first bus). A dead piece carries exactly `0.0`; a live piece that did not settle `NaN`.

### What step 2 measured (2026-10-18)

`docs/evidence/gridsim-m10/step2_predictions.md` (written first, with a dated note added
after the first green run and before any sabotage), `step2_gaps.jl`,
`step2_settle_probe.jl`, `step2_mutate.py`, each with its `.out.txt`; tests in
`test/m10_double_outages.jl`.

- **Kinds, as predicted.** case9's 36 line pairs all split: 9 two live pieces, 3 load
  lost, 21 with one piece's sources lost, 3 with two. 9 of its 27 line + machine pairs
  split, 3 of them D4's collapse (L14+G1, L82+G2, L36+G3); the 3 machine pairs stay
  whole. The mesh splits on AB+AC and DE+BE only, each cutting off a lone generator.
- **One piece up, one down.** case9 L45+L67: G3's piece {B3, B5, B6} has a 13.72 MW
  surplus and rises by +0.0024197 pu; the rest falls by −0.0011878 pu. **The
  prediction file says 13.66 MW / +0.002409 / −0.001183 — an arithmetic slip copying
  D1, whose 13.7 MW was right**; the test computes the number from the schedule.
- **Brute force (each live piece rebuilt as its own model; imbalance from the equipment
  list, shares from `pickup_shares`, flows from `dc_powerflow`)**: every live piece on
  six fixtures — case9 75, mesh 45, swing case9 162, genmesh 65, the grid-forming
  triangle 5, the grid-following triangle 1. The counts were measured after the first
  run and are held exactly (`==`), so a screen that stopped producing live pieces
  cannot pass by checking none.
- **The collapsed pairs equal M8's single outage** to round-off: Δω 0 to 1.9e-16
  relative, pickups ≤ 1.1e-16, flows ≤ 9.3e-16 against a 3.7e-14 band. The four case9
  paths to "G1 and G2 gone" (L14+L82, L14+G2, L82+G1, G1+G2) agree to Δω 0 and flows
  ≤ 2.3e-15.
- **Swing tier, band 1e-7 stated first.** On 11 pairs over two fixtures, every
  surviving machine's speed is at most 5.5e-10 from its piece's Δω and every live bus's
  export change at most 2.0e-8 from its pickup (genmesh ≤ 7e-10; on swing case9 the
  export gap is the speed gap times the governor gain, ~54 on the system base). **The
  gap is the solver's, not unfinished settling**: tightening reltol 1e-10 → 1e-12 takes
  it from ~1e-10 to ~3e-13 at 300 s and later, while at 150 s it is 3e-9 at both
  tolerances (not yet settled), so reading at 300 s and 450 s is late enough.
- **Order (18.4), band 1e-7.** Trip, settle 300 s, trip, settle against both at once:
  ≤ 1.8e-10 on genmesh's four pairs, 1.3e-8 and 4.2e-8 on swing case9's two. The 4.2e-8
  (L67 then G1, the tightest margin of the step) was first written up as the solver's
  without being measured; **probed after the first push**: reltol 1e-10 → 1e-12 takes it
  to 1.1e-10 (speed 3.5e-10 → 7.1e-13), so it is the solver's, and the order of the two
  losses moves nothing. The cap is seen to bind: after G2 alone G3's governor sits
  9.1e-11 from its 0.05 pu headroom.
- **Found, not predicted — two:**
  - **The mesh's AB+AC is G1's outage in frequency and pickups, NOT in flows.** With only
    G1 lost, bus A stays in the mesh and carries a loop flow, in on one line and out on
    the other (0.395 pu off at the worst branch); losing both lines closes that path. D4's
    collapse is a BRIDGE to a lone machine, and this is two branches, neither a bridge.
    The test now asserts the loop flow (AB and AC equal and opposite in G1's outage).
  - **A whole grid can be dead.** genmesh's LB+LD takes both loads; nothing is left to
    serve, so the grid is `:sources_lost` with zero imbalance. "Every whole-grid pair is
    live" had been assumed and is false (asserted now, the only such pair).
- **Sabotages, all four run** (each red where the dated note says):
  - S1 (every surviving unit shares every piece): red on brute force, L45+L67, the
    paths and the swing check; green on the whole-grid pairs, the collapsed pairs and
    the order runs (all whole grids), as predicted. **One more than predicted**: the
    inverter corner goes red too (the grid-forming inverter in the dead corner shares
    the rest's loss) — inside the row's description, but not on its list.
  - S2 (a surplus treated as a shortfall): red on the whole-grid identity, L45+L67, brute
    force, load lost, the swing check and the order testset's static assertion. The
    note had also said the order RUNS would go red; they cannot, since they compare the
    swing tier with itself.
  - S3 (a stranded load's import left out): red on brute force, load lost and swing.
  - S4 (a `P0 < 0` machine counted as a source): red on the load-lost classification
    and the brute-force count only; the swing check stays green, because a stranded
    load-machine's own damping settles it where the screen puts it. Invisible to every
    check but those two, by construction.
- The M7 exported-surface walk calls `dc_pair_outages` on its inverter model and it
  returns (both inverter kinds); the new names are clear of `names(GLMakie)`.

## D9 — How step 3 solves a piece in AC, and why M8's solve was generalised, not copied (2026-10-18)

`ac_pair_outages` (`src/steadystate/double_outages.jl`) screens the same pairs and finds the
same pieces as `dc_pair_outages` (the element list and the piece classifier are one shared
helper each, `_pair_elements` and `_pair_piece_kind`). Then:

- **One Newton solve per live piece**, each with its own settled frequency, its own angle
  reference (the model's slack where it lies in the piece, else the piece's first bus — a
  gauge, M8 D8) and its own reactive limits. The pieces share no branch, so one joint solve
  would be the same equations; solved apart, one piece failing leaves the other's answer
  standing, which is what makes an outcome per piece mean anything. A dead piece is never
  solved.
- **A pair of lines that leaves the grid whole is M8's line screen on two lines**: the
  rebuilt model through `_ac_powerflow_outcome`, the slack taking the change in losses,
  `Δω = NaN` (as `OutageScreen`'s line rows). "A connected line pair is `ac_powerflow` on
  the rebuilt model" therefore holds by construction and is not tested as evidence. Every
  other live piece goes through the shared solve.
- **What a dead piece takes with it is read from the AC base**: a machine's schedule, or,
  for the slack's one source, its solved output, base losses included (M8 D8.1). On case9
  that is 100.18 MW for G1 against DC's 96.04.
- **Only a piece's own in-service branches get a flow or a rating check.** The outaged
  branches' two ends lie in pieces with independent angle references, so a "flow" computed
  across them would be meaningless and could be reported as an overload.
- The base is refused exactly as `ac_generator_outages` refuses it, by the same code
  (`_ac_screen_base`, taken out of it).

**M8's shared solve is generalised in place.** `_ac_shared_setup` / `_ac_generator_outcome`
became thin wrappers over `_ac_piece_setup` / `_ac_piece_solve`, which take a set of lost
machines, the piece's vertices and the pair's branches; `_ac_schedule` skips a set of
machines and `_ac_admittance` leaves out a set of branches. M8's call is the whole grid,
nothing out, one machine lost — the same arrays and the same operations. Step 1 copied
instead (D7), but there the copy was ten lines; here it would be ~250, and two copies of the
solve that decides every AC generator outcome is the larger risk. **The gate is M9's six
captures, byte for byte, before and after.** One consequence, caught before the sabotages
ran: a check comparing the pair screen against M8's single-machine screen cannot see a bug
in the shared setup, because both sides run it. Only checks that read the base solution and
the model directly can (the losses identity, below).

### What step 3 measured (2026-10-18)

`docs/evidence/gridsim-m10/step3_predictions.md` (written first, with a dated note added
after the first green run and before any sabotage), `step3_pairs.jl`, `step3_probe.jl`,
`step3_mutate.py`, each with its `.out.txt`; tests in `test/m10_double_outages.jl`.

- **The pairs that are one outage (D4) are M8's single AC outage within B = 1e-10**, on both
  load models: outcome, Δω, every pickup, |V| by bus id, both ends' P and Q by branch id, and
  M8's open bridge carrying at most B.
- **Four paths to "G1 and G2 gone" give one answer — but none of them solves.** On
  constant-power loads every path fails to converge from the screen's flat start. Probed
  (`step3_collapse_probe.jl`) by scaling the whole case down: G1+G2 converges up to 220 MW,
  its lowest voltage falling faster the closer the load gets (0.93, 0.86, 0.75, 0.675 pu at
  100, 150, 200, 220 MW), and not from 240 MW up — the shape of a voltage collapse, so most
  likely no solution exists at 315 MW, but that is not proven: every solve starts flat. The
  24 constant-power `:no_solution` pieces in the table carry the same caveat. On the
  default loads every path is `:voltage`, at one Δω (−0.0192033 pu, the four agreeing to
  ~1e-16) and the same out-of-band voltages. The cut-off empty buses sit exactly at their
  neighbour's voltage (B1 = B4, B2 = B8), M8 D9's premise seen in a failing case. Predicted to
  compare solutions; the check now compares the answer each carries, solved or not.
- **The mesh's AB+AC is not G1's outage in AC, even in frequency — predicted; the reason and
  the sign were wrong.** The prediction blamed the loop flow's own losses. In fact A is a
  parallel path, and keeping it LOWERS the total losses (0.0270 against 0.0341 pu on constant
  power). Which way Δω moves then depends on the load model: on constant power the pair
  settles 1.47e-3 pu lower; on the default loads it settles 5.74e-3 pu HIGHER, because its
  lower voltages cut the load draw (by 0.034 pu) more than its losses rise.
- **The losses identity holds on every live piece that solved**, both grids, both load
  models: Σ pickups = lost base output + Δ load draw + Δ internal losses − base export across
  the cut, the export read at that piece's own end of each cut line. Load draw moves on the
  default loads, losses on both.
- **Lossless, constant power: every piece's Δω and pickups are step 2's DC answer within B**,
  every pair of both grids. **Every bus held at 1 pu as well (M8's A0 rung): a tree piece's
  flows are DC's within B, a meshed piece's are not** (sin against linear). The mesh has no
  tree piece at all — any two of its seven lines leave a loop — which the first run's test
  had wrongly assumed; case9's ring-breaking pairs are all trees. The A0 helpers turn case9's
  three stranded loads into live pieces with nothing that responds: `:no_response` at both
  fidelities.
- **The table** (`step3_pairs.out.txt`). Live-piece outcomes: case9 constant power 26 secure,
  2 overload, 23 voltage, 24 no solution; case9 default loads 31, 2, 42, 0; the mesh 42/3 and
  43/2 secure/voltage. Pair classes: case9 47 `dc_blind` + 19 `agree` (constant power), 42 +
  24 (default); mesh 3 + 42, 2 + 43. **No pair is `:dc_missed` or `:dc_false_alarm`
  anywhere** — wherever AC solved in band, DC named the same overloads (L67, on L56+L82 and L56+G2, both load models).
- **Found, not predicted, on the default loads:** where voltage falls far, what the loads draw
  falls with it, enough to reverse the sign. L89+G1 loses a generator and AC settles slightly
  ABOVE 50 Hz (+4.5e-4 pu, voltages 0.67–0.76 pu); L56+L94's two pieces move in opposite
  directions at the two fidelities. Both are `:voltage`, so neither is offered as an answer.
- **For step 4** (its oracle needs a split with two live pieces, both `:secure`, one rising and
  one falling): on constant power only **L56+L78** and **L67+L89** qualify; L45+L67, the
  plan's positive control, is `:voltage` in G3's piece there (B5 0.884). On the default loads
  L45+L67, L45+L89, L56+L78, L56+L89 and L67+L89 qualify.
- **Sabotages, all four run**, each red where the dated note says:
  - S1 (the slack's base output taken as its schedule): red on the losses identity alone (82
    assertions). Green on the comparison with M8's screen, as the dated note says — both sides
    run the shared setup.
  - S2 (only the first lost machine skipped): red on the four paths, the identity and the
    lossless rung's machine pairs.
  - S3 (the pair's branches left in the admittance before it is cut to the piece): red almost
    everywhere — the comparison with M8, the four paths, the mesh, the identity, the A0 flows,
    the comparison of screens.
  - S4 (a later piece's pickups overwriting an earlier one's): red on the identity and the
    lossless rung's pickups only — the two-live-piece splits.
  - S5 (2026-10-19, added with the inverter testset, prediction written first: a grid-forming
    inverter's bus kept as its model vertex instead of its position in the piece): red on the
    inverter testset alone, green everywhere else. The losses identity does NOT see it — under
    S5 the {B, C} piece of AB+CA no longer solves, so the identity has nothing to check; the
    two explicit assertions on that piece (it solves, and the inverter picks up the load) are
    what go red. An identity that runs only where a solve succeeded is blind to a bug that
    stops the solve.
- **Not expressible in this design, recorded:** one reference for the whole grid across a split
  (each piece is its own problem; a piece with no reference has none to pose), and reactive
  limits read from the whole grid (a lost machine's limits could leak only onto a bus that
  keeps another source, and neither report grid has one).
- **Inverters.** The report grids carry none, so step 2's two inverter triangles are the only
  place the per-piece code's inverter half runs: kinds agree with DC, and the identity holds
  on every piece that solved, including a grid-forming inverter as a piece's only responder
  off the reference bus (AB+CA). M7's exported-surface walk calls `ac_pair_outages` on its
  inverter model — run directly before the suite (`step3_m7walk.jl`), it returns on both
  kinds. The five new names are clear of `names(GLMakie)`.

## D10 — How step 4 makes several elements one event (2026-10-19)

**The event.** `TripElements(; lines, sources)` (`src/events/events.jl`): branches by bus pair,
sources by id. In the detailed tier (`_trip_elements!`) every line opens and every source trips
in both networks, then the network is re-solved **once**. Before anything moves, the pieces of
the FINAL network are read from the graph and classified by the pair screens' own rule
(`_pair_piece_kind`, on what is still online — its `lost` mask now reaches the grid-forming
inverters, a no-op for the screens): every unit still online in a piece that is not live is
tripped in the same event (a cut-off generator is lost, Hurdle 19.4), and every bus of such a
piece is de-energised. An event that would leave no live piece is refused before anything
moves. Lines are logged as `:trip_line` under the branch's own names, sources as
`:trip_generator`, switched-off buses as `:deenergise`. The single `TripLine` and
`TripGenerator` keep their success behaviour exactly — no graph answer — which is what M9's
captures gate.

**Measured before it was built** (`docs/evidence/gridsim-m10/step4_spike.jl`, `.out.txt`): one
re-solve of the final network passes on the default loads for L45+L67 (live voltages
0.911–1.052 pu), L56+L78 and L67+L89, and on constant power for L56+L78. **On constant power
L45+L67 (B5 0.866) and L67+L89 (B9 0.8954) are refused at the trip instant** — step 3's AC
screen held `V_set` and called L67+L89 secure in both pieces; this tier holds field flux, the
gap M9 already met at case9's G1 and G2. So on constant power one two-piece pair is left for the
oracle (L56+L78), and the oracle carries the loads' draw so the default-load pairs serve too.

**A dead bus is grounded through its own load slot — a deviation from the plan's wording
("voltage out of the solve"), recorded here.** Taking the bus's voltage out of the solve would
mean a new parameter, and a switched equation, on every vertex kind in both networks. Leaving it
in with its load zeroed is not enough: a bus with no load and no line left (a tripped machine's,
a bare junction) has a Kirchhoff row reading `0 = 0`, and the solve is singular. Instead the
slot every vertex kind already carries is rewritten, in both networks, to `G = 1`,
`B = a_i = a_p = 0` (`_deenergise!`): a conductance to ground with no load behind it. In a
piece with no source the only solution is `V = 0` exactly — measured, on both load models,
where left alone B5 solved to 1.83e9 pu (constant power) and 0.0 (default). The load is off
because it sees no voltage. No right-hand side changed for it, and the voltage band skips a
de-energised bus (`_voltage_band_violations` with a mask, all-false everywhere else).

**Found on the way, fixed: a machine on a de-energised bus aborted the run** (case9, L36 alone:
G3 cut off, B3 grounded). The exciter reads `hypot(V_re, V_im)`; at exactly zero its value is
0 and its derivative 0/0, and the solver's automatic-differentiation Jacobian turned that into
NaN in G3's `Efd` row — with the regulator OFF, since `K_A = 0` times NaN is NaN.
`_exciter_vmag` returns 0 with a zero derivative there and is `hypot` everywhere else. Its test
is on the squared magnitude because of a second finding: the solver's dual numbers let the
derivative part settle a comparison the value leaves tied — `V_re == 0` came out false and
`|V_re| + |V_im| > 0` true at a zero value with a unit derivative (both were tried first;
each left the NaN where it was). `V_re² + V_im²` has value and derivative 0 there.

**A refused event changes nothing — chosen by measurement on the direct path.** Every event
writes, then re-solves, and the re-solve can refuse. `_refusable!` copies everything an event
can write first — both parameter vectors, the static solve's state, the integrator's state, the
two in-service sets (replaced, so even their hash layout is the old one), the COI weights, the
ladders' and relays' latches, the de-energised mask, the log's length — and puts it back on a
refusal or a throw. The integrator is not touched before the re-solve succeeds, so its cached
step still describes the restored state. The measurement: a run refused an event at t = 1 and
continued to 6 s is `isequal` to its twin that was never asked, every channel and every
parameter, on three refusals (default `TripLine` L45, constant-power `TripElements` L45+L67,
constant-power `TripGenerator` G1). `TripLine` and `TripGenerator` go through the same
`_refusable!` — both were half-applied before (D1 named the line's; the generator's wrote its
governor, weight and latches, which M9's dip screen never saw because it abandons the engine).

**The out-of-step relay's path cannot change nothing, and the run stops there — also by
measurement** (`step4_relay_probe.jl`, `.out.txt`; the governed ring of `m5_detailed.jl` with G1
ramped UP and L31 rated 85 MVA, so L12's trip leaves L31 at 105.8 MVA). Before the fix: the
refused trip left L12 open in both networks, unlogged, the relay's record "tripped" while still
armed, and a `solve!` continued from there collapsed its step size at 9.23 s. After it: the
engine is put back, and the relay's record too (`out_of_step.jl`'s affect restores its
`t_tripped`/`δ_tripped` if the trip throws). But the error leaves from inside the solver's
callback handling, with the integrator stopped mid-step at the root it found — and **with the
stop cleared by hand, the run goes on to 30 s with L12 in service and the relay never firing
again**: its one crossing is spent, so a continued run is silently a run without the protection
that tried to act. So a refusal on this path sets `halted`, and every later `solve!`/`inject!`
refuses with the reason (`_assert_running`).

**Found, not fixed: the detailed tier's `TripLine` never latched the relay on the line it opens**
(the swing tier's does, and `out_of_step.jl` states the rule). A relay that fired stays armed;
if its angle came back under the threshold and crossed again it would overwrite its own record
and call a no-op trip. Fixing it in `TripLine` changes a callback's condition, which can move a
step sequence the M5 criterion capture holds — not this step's to decide. `TripElements` latches
the relay on every line it opens.

**The swing tier's half is built**, though it is cut-first item 2: it was the single trips run
back to back (that tier re-solves nothing), plus the graph's answer, about thirty lines. Checked
bit for bit against step 2's hand-written event lists. A stranded load-machine (19.3) is tripped
there too, as load lost.

### What step 4 measured (2026-10-19)

`docs/evidence/gridsim-m10/step4_predictions.md` (written first, with two dated notes added after
the first test runs and before any sabotage), `step4_spike.jl`, `step4_relay_probe.jl`,
`step4_settle_probe.jl`, `step4_mutate.py`, each with its `.out.txt`; tests in
`test/m10_double_outages.jl`, run alone by `step4_run.jl`.

- **Gate: M9's seven captures byte-identical**, taken from a detached worktree at `6c11bba` and
  from a copy of the step-4 source (SHA-256, first 16 hex): swing `531810f77f33bf93`, criterion
  `e6be220ec6c23f7a`, ac `f47ff416ea9623bc`, screen `fc70979fd7be75e2`, dips `e4a4d7e3db92a053`,
  verdict `e74e7f9f1861be21`, oracle `a09bc2361763194c`. So the restore wrapped around
  `TripLine`/`TripGenerator`, the band mask, the exciter guard and the relay's `try` moved no
  bit of any recorded run.
- **The identity holds per piece on all ten pieces** (rtol 1e-6; the whole grid's Σw or losses
  fail it by more than 1e3 times its residual), every machine of a piece within 1e-10 of the
  others, 300 s and 400 s within 1e-10; one piece up and one down in all four two-piece
  splits. The dead piece's load (B5, 90 MW in the model) is seen as what the rest of the grid
  settles to: every machine rises, on both load models, and the identity closes on the rest.
- **FBDF collapses its step, isolated, where a bus is grounded** (`step4_settle_probe.jl`):
  constant-power L45+L56 at reltol 1e-10 (t = 367.66 s, or 228.73 s with the run split
  differently), default-load L45+L56 at 1e-9 and not at 1e-10; every state's weighted error
  ~1e-43 at the failure. Rodas5P at 1e-10 completes all six identity runs, so the testset
  uses it. Same signature as M5's isolated `Efd_max = 1.2` failure (conditioning, not a model
  boundary); the 19.4 run on FBDF completes.
- **A count in the test was wrong, not a number**: the identity testset first asserted 11
  pieces and 5 up/down splits; the list holds four two-piece splits and two dead-piece rests,
  10 and 4, which the run counted. Corrected before any sabotage (dated note).
- **Sabotages, all six run** (`step4_mutate.out.txt`), each red where predicted:
  - S1 (no restore): red on the twin bit-identity, the positive control's "the refused first
    trip left L45 in service", and the relay testset — nowhere else.
  - S2 (a re-solve after each line): red on the positive control, as predicted. **Also red,
    unpredicted but measured at step 0 (D1): every L45+L56 testset** — the dead piece, the
    refusals testset (which reuses that pair) and the identity, whose run then stopped at that
    case, so its predicted red on default-load L45+L67 was never reached there; the positive
    control is that same event and is red. L45 alone is refused on both load models (D1).
  - S3 (no de-energising): red on the dead piece and on 19.4, as predicted; also on the
    identity's L45+L56 case and the refusals testset, both that dead piece again.
  - S4 (a cut-off source left online): red on 19.4 alone; the dead piece green (B5 holds no
    source), as predicted.
  - S5 (the relay's record not put back): red on the relay testset alone.
  - S6 (no halt): red on the relay testset alone (its four "cannot go on" assertions).
- **Added after the step-4 commit, on review: the inverter half.** The report grids carry no
  inverter, so nothing above reached `TripElements`' inverter code. Step 2's corner triangle
  with a 10 MW load added at A: a grid-forming I3 tripped first, then AB+CA — {B, C} is load
  lost, B and C de-energised (exact 0.0), nothing else tripped; a grid-following I3 and AB+CA —
  I3 tripped in the same event, B and C de-energised, their voltages integrating to 5e-324 rather
  than an exact 0 (the test had asserted 0.0; it reads <= 1e-300, dated note). Sabotage S7
  (the `lost[q]` line deleted, a tripped grid-forming inverter read as a source): red on that
  testset alone, through the grid-forming case — {B, C} read as live, its re-solve refused —
  which stops the testset before the grid-following case. The 19.4 and dead-piece testsets
  moved to Rodas5P with the identity's, since they too ground a bus. Step-4 testset 180/180,
  run alone; the full core suite was not re-run for this test-only change (16525 at the commit
  before, +6).
