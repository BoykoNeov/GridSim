# Next steps — work packages, written to be picked up cold

Written 2026-11-13, after a review of the whole repo (design, pictures, known defects).
Each package below is self-contained: what and why in plain words, the files, what to
measure first, when it is done, and the trap. They are written so a less capable model can
do one at a time without re-deriving the project. Words you do not know are in
[`../glossary.md`](../glossary.md).

**The house rules every package inherits** (from `CLAUDE.md` and the plan trios):

1. Take the captures *before* the first edit to `src/` and again after, and compare them
   byte for byte (`docs/evidence/gridsim-m9/harness/README.md`). Never edit `src/` while
   a capture or a suite is running — each Julia launch loads the working tree.
2. Write the prediction (which numbers move, which do not, and the tolerance) before
   running the check. Then run a deliberate break and see the test go red.
3. A UI change is not done until its figure has been rendered offscreen **and looked
   at**. Tests have passed on windows whose labels lay on top of each other.
4. `Pkg.add` deletes every comment in the `Project.toml` it touches. `git diff` it and
   put them back.
5. Run every suite at below-normal priority, from a script file, never `julia -e` inside
   the `cmd` wrapper (`docs/evidence/gridsim-m9/harness/suites.sh`).

Sections: **A** — small, safe, do in any order. **B** — pictures. **C** — one physics
defect of the same family as the one fixed on 2026-11-13. **D** — candidates for the next
milestone; these need the owner's choice first and must not be started without it.

---

## A. Small and safe

### A1. The remaining UI performance items

Already written up, each with its measurement and its acceptance line:
`ui-visuals-performance.md` §3.1–3.6 (bursty pacing on Windows, the scrolling axis's tick
cost, long rolling windows, precompiling the on-screen path, idle CPU, four owed tests).
Nothing there has gone stale except its file paths: the measurement scripts it names under
`M:\claud_projects\temp\` no longer exist — rewrite the few lines each needs.

### A2. One table component instead of three

**What.** The frequency-screen, double-outage and network-dispatch windows each draw a
coloured table by hand (rectangles and text in an `Axis`), each with its own click
handler, selection box and font-size rule.

**Do.** Add `ui/src/table.jl` with one function,
`cell_table!(ax; rows, columns, text, colour, selected) -> (; press!, selected_box)`,
and move the three windows onto it one at a time. Keep every name the tests read
(`plots.cell_text`, `plots.cell_colour`, `matrix_press!`, `table_press!`).

**Done when.** The three windows' tests pass unchanged, and the three figures, re-rendered,
differ from the committed ones by nothing a reader would notice (look at them).

**Trap.** The double-outage table selects a *cell*, the other two a *row*. Make that a
parameter; do not make two components.

### A3. Fonts and sizes the theme does not yet own

`ui/src/theme.jl` sets the look, but the four report windows still pass literal
`fontsize = 10.5`, `11`, `11.5`, `12` in about sixty places. Name four sizes in the theme
(`FS_CELL`, `FS_NOTE`, `FS_READOUT`, `FS_HEADING`), replace the literals, re-render every
figure, look. No behaviour change.

### A4. The caveat paragraphs

Every report window carries a grey paragraph of caveats, 80–120 words in 11-point type.
They are correct and nobody will read them at that size. For each window: keep the one
sentence a reader must not miss in the window (bold, one line), and move the rest behind
an **about this picture** button that swaps the read-out for the full text. The full text
must stay reachable and stay tested (`in_layout` checks exist for each caveat — keep them
green by keeping the label, toggling `visible`).

**Ask the owner first** which sentence is the one to keep for each window; that is a
judgement about what matters, not a refactor.

---

## B. Pictures

### B1. A live map in the multi-machine window  ← the largest visual gain available

**Why.** The window a user opens first on a network (`launch(three_machine_ring())`) shows
frequency and angle *curves* and nothing that looks like a grid. A line trip changes one
curve's wobble; on a map it would be a line going dark and the flows re-routing. The three
report windows already draw a grid; the live one does not.

**What exists to build on.**
- `ui/src/grid_map.jl` (2026-11-13): `line_label_placement`, `free_directions`,
  `grid_centre` — where names and attachments go so nothing overlaps. Use them; do not
  write a fourth placement rule.
- `ui/src/double_outage_window.jl`, `draw_grid!`: the smallest complete sketch.
- The scenario editor already holds positions (`[layout]` in a scenario file; the `Layout`
  alias in core). Positions are render state and never go into a `Bus` (SPEC §3.5).

**Do, in this order, one commit each.**
1. `map_positions(net; layout = nothing)` in `grid_map.jl`: the given layout if there is
   one, else buses on a circle in model order. Test: every bus has a position, no two
   coincide.
2. A third panel in `_build_network_window_impl` (right column, above the controls or in
   place of the inertia bar — render both and choose): buses, lines, generator markers.
   Static first. Render `smoke_render(three_machine_ring())` and look.
3. Make it live, on the existing ~30 fps repaint and nothing faster:
   - a tripped line drawn dashed red (the engine's event log already says which);
   - a tripped machine greyed;
   - each bus coloured by its machine's frequency deviation on a **fixed** diverging
     scale (±0.5 Hz), so two windows are comparable — an auto-scaled colour would make a
     2 mHz wobble look like a blackout (the same mistake as auto-scaled axes, already
     recorded for this window in `ui/README.md`).
   - line thickness by flow. The swing tier's flow on a line is `K·sin(δa − δb)`; core has
     a reader (`branch_power`) — find it and use it, do not recompute it in the UI.
4. The editor's **run ▶** hands its positions through (`launch(net; layout = …)`).
5. Regenerate `docs/images/fig-3-67-two-area.png` and the README's network figure.

**Measure first.** Repaint cost before and after, the way `ui-visuals-performance.md` §1
did (`refresh!(; force = true)` 300×). **Done when** the map adds < 200 µs per repaint on
the ring and the window's existing tests pass.

**Traps.** Colour observables updated per frame allocate; update one `Vector{RGBf}`
observable, not one per bus. The repaint must stay throttled — do not hang the map on the
state observable directly (that fires at the simulation rate).

### B2. A start window instead of a console menu

`GridSim.bat` opens a black console with a numbered list (`ui/scripts/start.jl`). Make it a
window: nine tiles, each a thumbnail (the committed figure in `docs/images/`), a title and
one plain sentence; click opens that window; closing it returns to the start window. Keep
the console menu as the fallback when a window cannot be created.

**Trap.** The start window must not hold a Julia task that blocks the opened window's
event loop: open the chosen window, `wait_for_close` it from the script's loop, then show
the start window again — the shape `start.jl` already has.

### B3. A dark theme

Not requested; every committed figure is light. Only worth doing after A3, when the sizes
and colours live in one file. Then it is a second `Theme` and a keyword on each `*_render`.

### B4. The editor's canvas

Two things seen in `docs/images/fig-editor-solved.png`: the canvas shows axis numbers and
"map x / map y" although the units mean nothing without a background image — hide the
decorations unless `background` is given; and the property panel's empty text boxes show
clipped glyph fragments. The second is the upstream Makie text-box glitch recorded in
`scenario-editor.md` — **do not chase it again**; check instead whether a newer GLMakie has
fixed it, and if so bump the compat as its own commit with all three suites re-run.

---

## C. The same defect, one tier over: the voltage regulator's limits

**Background.** On 2026-11-13 the detailed tier's governor was made to stop *exactly* at
its power ceiling (a solver callback that finds the instant it arrives and lands it there;
`_governor_cap_callbacks` in `src/engines/detailed.jl`). Before that, it overshot the
ceiling by one solver step and stayed above it.

**What is left.** The voltage regulator's output limits (`Efd_min`, `Efd_max`) are bounded
the old way, by the derivative alone, and overshoot by ~3e-8 pu — small, measured, and
asserted as a number in `test/m5_detailed.jl`. And the two simpler tiers (aggregate,
swing) bound their governors with a step-rejecting guard (`isoutofdomain`) that
`detailed.jl`'s long comment shows is "inside its margin by 3× on a constant nobody
chose".

**Do.** (1) The exciter: the same callback, two directions (ceiling and floor). The
captures will move at the 1e-8 level wherever a regulator limits — predict which
(`regulator_bus_system(; Efd_max = …)` runs in M5's tests) before running. (2) The swing
and aggregate tiers: replace the guard with the callback **only if the owner agrees** —
it moves M1–M4 numbers at round-off level and every one of their captures.

**Done when.** The isolated failure recorded in `detailed.jl` (Rodas5P at reltol 1e-9,
`Efd_max = 1.2`: the step size collapses at the crossing) completes, and the overshoot
asserted in `test/m5_detailed.jl` is at round-off instead of 3.4e-8.

---

## D. Candidates for the next milestone — the owner chooses; each names its hurdle first

The hurdle list in `README.md` is empty again after M11. These are the candidates the
review found, with the hard thing each would have to get over. They are ordered by how
much of what already exists they make more true, not by size.

### D1. Line charging and transformers — make case9 the published case9

**Why first.** The most repeated caveat in the repo is "case9 here has no line charging,
so these limits are this case9's, not MATPOWER's". It is on two windows, in three reports
and in M11's oracle (which has to switch charging *off* on the other side to compare).
Lines here are a series impedance only; a real line also has capacitance to ground, which
props voltage up when lightly loaded, and transformers have tap ratios.

**The hurdle it would name.** A shunt at every line end changes every tier at once — the
two power flows, both OPFs, the screens, and the detailed tier's network equations — and
the gate is the repo's usual one: with charging zero, every existing number byte-identical.
The outside checks then get *stronger*: PowerModels and PowerFlows can be compared on the
case as published, with nothing switched off.

### D2. Read a standard case file — grids bigger than nine buses

**Why.** Every grid is typed in by hand; the largest has nine buses. "Sparse from day one"
(SPEC §6) has never been exercised at a size where it matters, and no screen has met a
grid where N-2 is too many pairs to enumerate without care.

**The hurdle.** A MATPOWER-format reader whose output is checked row for row against the
existing hand-typed case9, then the IEEE 39-bus system: where does each tier stop being
real-time, and is that where the mode router (SPEC §2) says it should be? Needs D1 first —
a 39-bus case without line charging does not solve inside the voltage band.

**Licence note.** MATPOWER's case *files* are not under its BSD licence
(`m11-context.md` D7). Read them at run time from a path the user gives; do not commit them.

### D3. A dispatch that survives every single outage

**Why.** M8 screens outages of a given dispatch; M11 finds the cheapest dispatch. Nothing
joins them: the cheapest dispatch is, in general, not secure. The joined problem — cheapest
dispatch such that losing any one line overloads nothing — is what a grid operator
actually solves.

**The hurdle.** In DC it is M11's problem with one extra row per (line, outage) pair, built
from M8's outage factors, which are already checked exact. The check that needs no
optimiser already exists: hand the answer to `outage_screen` and every outage must come
back secure. What is hard is the size (rows grow as lines²) and saying honestly what "the
price of security" is on a grid whose ratings are invented.

### D4. A day, not an instant

**Why.** The vision (SPEC §1) says "energy-system simulator … renewables … markets".
Everything built so far is one instant or the seconds after it. Nothing varies over a day:
no demand curve, no solar profile, no storage, no generator that must stay on once started.

**The hurdle.** Time-coupled constraints (storage energy, ramp rates, minimum up-time) make
it a different kind of optimisation from M6's and M11's, and it needs data that is
*sourced* — the repo has already been bitten once by a tuned number becoming a quoted
result (`entsoe-iberia-reproduction.md` §7.3).

### D5. A geographic map

SPEC §9 item 8. Worth doing only after B1 (a live schematic map) and D2 (a grid big enough
to need geography). Named here so it is not forgotten, not because it is next.

**Recommendation.** D1, then D2. They are the two that turn the existing nine windows from
"correct on a toy we had to modify" into "correct on the published case, and on a grid
with some size to it", and every later candidate is easier and more honest after them.

---

## Carried forward, still owed (from the hurdle list)

Not packages yet — nobody has named what is hard about them:

- Hurdle 12's untested clause (the grid-following existence limit sits behind the voltage
  band, so neither side of the comparison ever starts near it).
- The low-inertia study's aggregate-tier overlay (`coi_model` refuses a `Load`).
- A sourced area-wide rate-of-fall limit (none is published; the rate is shown, not judged).
- From M10: the amber "customers cut off" colour is never reached on the shipped grids; a
  refused piece's no-flags rule is guarded but never exercised by data.
