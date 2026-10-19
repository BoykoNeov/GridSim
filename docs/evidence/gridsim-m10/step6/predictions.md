# M10 step 6 — predictions, written before each sabotage runs

Each sabotage is applied to a copy of the named file by `mutate.py`, the named testsets run,
and the file restored byte for byte. What each one should turn red is registered here FIRST;
results go in `mutate.out.txt`, and anything red or green that was not predicted is named
there and explained in `m10-context.md`.

## F — the screens' one fix (D12.1)

- **F1 — the fix reverted** (`_ac_outage_set` keeps every live piece's pickups and flags
  again). Red: "the mesh's G1: the AC restore is refused, and says nothing is capped" — on
  `!any(ar.capped)`, `ar.capped == dr.capped` and the nine `G1→X` pairs, both load models.
  Green: "every AC pair keeps pickups and flags exactly where the sequential mask does" — the
  pair screens moved nowhere on the report grids (`snapshot.out.txt`: every pair-screen file
  identical), so that testset guards the rule and cannot see this sabotage.

## R — the report (`scripts/double_outage_screen.jl`, runner `run_report.jl`)

Written after the claims and their test passed, before any R sabotage ran. One finding
came first and is NOT a sabotage: the first window render showed a "not restored" pair
reading "+0.0000 Hz pass". A sequential pair with no state after both had its first
loss's restored pieces judged at 0.0, and in AC (whose restored pieces keep an answered
outcome) that 0.0 was compared with both at once — claim q's "milder" counts were 58 and
60 on case9, now 28 and 25. The test had passed on the wrong numbers, because the counts
were read off the same rows. Fixed in `_sequential_side` (the pair's outcome is the piece's
verdict, no worst) and guarded by its own assertions; R2 puts the bug back.

- **R1 — the amber rule removed** (`pair_verdict` returns `:pass` where customers are cut
  off). Red: "the verdict per piece…" — the hand-built `:pass_load_lost` assertion only.
  Green: every claim (claim k: no pair here passes with load lost, so nothing moves).
- **R2 — the no-state bug back** (the pieces of a sequential pair with no state after both
  judged, its worst read off them). Red: "the verdict per piece…" (the no-state block) and
  claim q (case9 milder 28 → 58, 25 → 60). Green: claim p (DC's no-state pieces are
  `:restore_refused`/`:restored`, which DC never judges), claims k–o, the tie testset.
- **R3 — a pair's worst piece by signed minimum, not by size.** Red: claim n (L45+L67's
  rising piece, +0.1210 / +0.2247, is no longer the worst) and claim q (L45→L67 +0.1986,
  L67→L45 +0.2100). Green: claims k, l, m, o, p (their worst values sit on pairs with one
  judged piece), the tie testset.
- **R4 — "untouched by the second loss" ignored** (every piece of a sequential pair read as
  reached). Red: the tie testset only. Green: every claim — no report-grid pair has such a
  piece, which is why the tie testset exists.
- **R5 — the n/a rule removed for both at once** (every piece applicable). Red: the whole
  file, before any testset runs — the AC piece of a whole-grid line pair answers `:secure`
  with no Δf, and `piece_verdict` refuses it by name (D12.2's broken-contract guard).

## W — the window (`ui/src/double_outage_window.jl`, runner `run_window.jl`)

- **W1 — the sketch colours every bus by the FIRST piece.** Red: "the grid sketch colours
  each bus by its piece, by id" (L45+L56: B5 red instead of dark). L45+L67 alone would not
  see it: both its pieces pass. Green: the other four.
- **W2 — every cell coloured by the DC side whatever the view.** Red: "the row is the
  script's, every cell says what its row says" (the AC views). Green: the rest.
- **W3 — the sequential table reads the both-at-once rows.** Red: testset 1 (sequential
  cells are ordered rows), "a pair with no state after both" (G1→G2 is no longer not
  restored), "the controls…" (the row after switching to sequential). Green: the sketch
  testset, the render.
- **W4 — a pair with no state after both drawn as if screened** (`screened = true` in the
  sketch). Red: "a pair with no state after both draws no verdict" (its piece labels drawn,
  no banner). Green: the rest. (Replaced before any W run: the first draft, "bus colours
  ignore the outcome", is invisible by construction — a no-state pair's running pieces
  carry its outcome as their verdict, which is grey anyway.)
