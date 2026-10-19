# M10 step 5 — predictions (written before the tests ran and before any sabotage)

Hurdle 21: fail, restore 50 Hz, fail again (`m10-context.md` D3, D11). Written 2026-10-19
after a DC trial run (`dc_restore` / `dc_sequential_outages` printed on both report grids,
and the line-first control computed) and while the first AC trial was still running —
**its output not read**. What the DC trial already showed is marked *(seen)*; everything
else is a prediction.

## Bands, stated first

- **DC, restore exactness.** A restored piece's model balances from the equipment list:
  `|Σ P0′ − Σ loads| ≤ |Σ P0 − Σ loads|` of the original model `+ 1e-9` MW (the report grids
  balance to round-off). Shares of every uncapped, unfloored unit with a governor: `pickup/g`
  equal across the piece, rtol `1e-12`. A capped machine's restored `P0` is `Pmax` **to the
  bit** (`===`), a floored one's `Pmin` to the bit, a capped inverter's its rating limit to
  the bit. Restored DC flows against `dc_powerflow` on the restored model, by branch id:
  `100·eps·max|f|` (M8 step 2's band).
- **DC, line first, nothing to restore (the free control).** When the first element is a
  line that leaves the grid whole, its imbalance is exactly `0.0`, the restore moves nothing,
  and A-then-B must be both-at-once: every live piece's `Δω`, every pickup and every flow
  within `100·eps·scale`, `scale` the largest |flow| or |Δω| involved. *(seen: worst gap
  1.09e-14 on the mesh's 63 such pairs, 4.2e-15 on case9's 66.)*
- **AC, the restore's losses identity**, per restored piece, every term read off the base
  solution, the restored solution and the model (step 3's helper, at `Δω = 0`):
  `Σ pickups = lost base output + Δ load draw + Δ internal losses − base export across the cut`,
  within step 3's residual bound.
- **AC, `ac_powerflow` gives the restored state back** (D11.5): on every restored piece whose
  base the screen accepts, `|V|` and `Pgen` bus by bus (by id) within `B = 1e-10` (step 3's
  `_M10_B`, solution against solution). Two Newton solves of the same equations at abstol
  1e-12. **Where it could fail:** a bus the restore's shared solve holds at a reactive limit
  that `ac_powerflow` treats differently (the slack's limits). Predicted: no such bus on the
  report grids (their limits are ±300 MVAr, far from binding).

## Numbers predicted from the data

- **mesh, G2 lost (60 MW):** gains on the system base G1 60, G3 20 → 45 : 15, but G3's
  headroom is 5 MW → G3 restored to **45 MW exactly (its `Pmax`)**, G1 to 150 + 55 = **205**.
  *(seen)*
- **mesh, G1 lost (150 MW):** headroom left 40 + 5 = 45 MW → **`:restore_refused`**, while
  `dc_generator_outages` answers G1 (`:shared`, damping carries the rest). The nine ordered
  pairs starting with G1 are `:not_restored`. *(seen: 9)*
- **mesh, G3 lost (40 MW):** G1 : G2 = 60 : 37.5 → 24.615 / 15.385 MW, nothing capped. *(seen)*
- **case9:** every single loss restores, nothing capped (headroom 154–185 MW against at most
  115 MW). The three bridges L14, L82, L36 restore exactly like G1, G2, G3. *(seen)* The three
  ordered pairs (bridge, its own machine) are `:already_lost`. *(seen: 3)*
- **The tie fixture** (two triangles A–B–C and D–E–F joined only by C–D, 40 MW flowing
  left to right; left G1 at A 80 MW g 40, G3 at C 30 MW g 20 `Pmin` 20; right G2 at D 50 MW
  g 30, G4 at F 40 MW g 20 `Pmax` 45): losing C–D leaves two live pieces. **Left** has a
  40 MW surplus: by gain G1 −26.7, G3 −13.3, but G3's room to its floor is 10 MW → **G3 at
  20 MW exactly, G1 −30 → 50 MW**. **Right** is 40 MW short: G2 +24, G4 +16, but G4's
  headroom is 5 → **G4 at 45 exactly, G2 +35 → 85 MW**. Each piece's restored model balances.
- **An inverter at its rating** (the corner triangle with a second machine and a 30 MVA
  grid-forming inverter whose gain is 15 on the system base): losing G1 (40 MW) shares
  G2 : I3 = 20 : 15 → I3 would take 17.1 MW but has 10 MW to its rating → **I3 at 30 MW
  exactly**, G2 +30. The rebuilt model is accepted (no throw).
- **Below zero (D3):** genmesh with G1 at 180 MW and G3 at 10 MW: losing the load-machine LB
  (130 MW) gives a surplus shared by gain 60 : 37.5 : 20 → G3 down by 22.1 MW to **−12.1 MW,
  flagged** in `below_zero`; in its restored model G3 has `P0 < 0`. With `Pmin = 0` on G3 it
  is floored at exactly 0 instead and nothing is flagged.

## The order table — registered before it is read

- **Invisible on case9 by construction:** every machine has the same `D/(1/R)`, so a restore
  sharing by damping as well as gain gives case9 the same shares. No cap binds on case9, so for
  machine pairs both orders reach the same final DC dispatch and differ only in `Δω`.
- **The mesh is where order can show in flows** (its `D/(1/R)` differ, G2's loss caps G3,
  G1's refuses).
- **AC convention, not physics:** a restore after a line shares the change in losses by gain;
  a second-loss line that leaves the piece whole is M8's line path (slack takes the losses,
  `Δω = NaN`). Some AC differences between orders will be this.
- No claim about which order is worse is written before the table is printed
  (`step5_pairs.jl` → `step5_pairs.out.txt`).

## Sabotages, and where each is predicted red

- **S1 — the restore shares by damping as well as gain** (`_restore_solve` handed `g + d` in
  DC; the AC restore keeps the damping): red on the mesh's exactness (G3 lost: G1 : G2 becomes
  63 : 40.5 instead of 60 : 37.5) and on the AC identity's neighbours only if the proportion is
  checked there. **Green on case9 and on the tie fixture by construction** (equal `D/(1/R)`).
- **S2 — the cap ignored** (`up = Inf` for every unit): red on the mesh's G2 (G3 not at 45,
  the restored model not balanced once `P0` is clamped back to `Pmax`), the tie fixture's right
  piece, and the inverter fixture.
- **S3 — `Pmin` ignored**: red on the tie fixture's left piece and the below-zero fixture's
  `Pmin = 0` variant; green on both report grids (no `Pmin`).
- **S4 — the restore run on the whole grid across a split** (every unit not lost shares each
  piece's imbalance): red on the tie fixture, and **also on case9's three bridges** — the
  cut-off generator is not "lost", so it would share the main piece's imbalance. Green on the
  mesh (no single element splits it).

## Dated note — 2026-10-19, after the first test runs and the order table, BEFORE any sabotage

What changed since the file above was written, in the order it happened:

- **The first AC trial found the restored model refused** (`NetworkModel`'s schedule balance:
  the mesh's restored schedule 6.26 MW out). Fixed before any test ran: in AC the slack's one
  source carries the balancing schedule (`m10-context.md` D11.5, corrected there). After the
  fix `ac_powerflow` gave every restored state back within 8.4e-14 in |V| and 6.7e-13 in Pgen,
  inside the stated B = 1e-10. The prediction "no restored piece's base refused on the report
  grids" held; but the restored state ITSELF is `:voltage` after case9's G1 (and its bridge
  L14) and after L94 on both load models, and after L45 on constant power — so every pair starting
  there is `:not_restored` (43 constant power, 32 default).
- **First test run: 2383 passed, 2 errored** — both `@test a ≈ b rtol = … && c`, the macro
  error memory already names. Split; no number changed.
- **The order table was read, then explained by a probe** (`step5_offset_probe.jl`): the two
  orders differ by exactly what the first loss alone would settle to. That claim and its counts
  went into the order testset AFTER both outputs were read.

Sabotage predictions, per testset of step 5 (exact = 21.1, split, refused = 21.2, Pmin,
line-first, AC identity, order = 21.4, names; the dynamic testset is predicted separately when
it is written):

- **S1 (damping shares):** red on *exact* (the mesh's and genmesh's proportions, the inverter
  fixture's I3, a load-machine with damping and no governor taking a share), *refused* (the
  bowtie's damped, governor-free machines answer instead of `:no_response` → `:restore_refused`),
  *Pmin* (low-G3's 130 · 20/117.5), and **order** — restoring by gain plus damping IS settling's
  proportion, so the mesh's two orders reach the same DC dispatch (36, not 22) and its AC gap
  becomes the law to the solver (`worst > 1e-5` fails). Green: *split* (the tie's equal D·R),
  *line-first* (nothing restored), *AC identity* (accounting holds whatever the shares).
- **S2 (caps ignored):** red on *exact* (mesh G2, genmesh G2, the tie, the inverter fixture —
  the clamped `P0` unbalances the schedule and `NetworkModel` throws), *split*, *refused* (the
  mesh's G1 restores), *Pmin* (low-G3's sequential G2-then-LB: G1 no longer capped), *AC*
  (mesh G2: the restored model holds G3 at 45, the restore had 55 — `ac_powerflow` no longer
  gives it back), *order* (mesh counts). Green: *line-first*.
- **S3 (Pmin ignored):** red on *exact* (the tie, low-G3 with `Pmin = 0`), *split*, *Pmin*.
  Green everywhere else (no report grid has a `Pmin`).
- **S4 (whole-grid restore across a split, DC only):** red on *exact* (case9's three bridges and
  the tie: the cut-off or other piece's units share, the rebuilt piece does not balance),
  *split*, *order* (case9's DC sequential screen meets L14). Green: *refused*, *Pmin*,
  *line-first* (its first lines leave the grid whole), *AC* (AC poses each piece alone).

**Added with the dynamic testset (still before any sabotage ran).** S1–S4 cannot reach the
dynamic testset: its cases are case9's (equal D·R), none caps, none has a `Pmin`, and S4 is
DC-only — predicted green there for all four. The dynamic check compares two answers that both
start from the restored model, so it does not check the restore itself (the static testsets
do); it checks the second loss's answer from the restored state. So one more sabotage, aimed at
it:

- **S5 (the second loss restored instead of settled):** red on the **dynamic** testset (the
  screen says Δω = 0 in every piece the second loss touched; the run settles away from it),
  **line-first** (A-then-B no longer both at once), **order** (the counts and the law), and the
  *split* testset's "left piece settles below target" (`left.Δω < 0`) and *Pmin*'s
  below-zero-after-the-settle pair. Green: *exact*, *refused*, *AC identity* (restores only).
