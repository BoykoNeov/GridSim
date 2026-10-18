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
