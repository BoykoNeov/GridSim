# The scenario editor — place and edit grid elements on a map

**Status:** built 2026-09-07 in one batch, outside the milestone sequence
(M5 steps 6–8 stay open and untouched). Core: `src/model/scenario_file.jl`
(+54 tests). UI: `ui/src/editor.jl`, `ui/src/editor_window.jl` (+109 tests).
No physics, no engine, no recorded number changed.

Cross-cutting rather than a milestone, like `ui-visuals-performance.md`: the
editor produces the `NetworkModel` the windows and engines already consume, and
nothing downstream knows it exists.

## What it is

A fourth window (`editor`, `editor_render`) with no engine in it. A canvas
(a Makie `Axis`, optionally over a PNG "map"), six tools — select/move, bus,
machine, load, branch, delete — a property panel for the selected element, a bar
with the scenario's name and bases, a file box with **save file** / **open file**,
**fit view**, and **run ▶**, which builds the model through the ordinary
constructor and calls `launch` on it, the same call a REPL makes.

```
julia --project=ui -e "using GridSimUI, GridSim; wait_for_close(editor(three_machine_ring()))"
```

## Decisions

**D1 — Positions are not a field of `Bus`.** SPEC §3.5: render state and
simulation state are never one object. The map coordinate lives in a `Layout`
(`Dict{Symbol,Tuple{Float64,Float64}}`) beside the model, is written to the file's
own `[layout]` table, and comes back from `read_scenario` as a separate return.
A test asserts `Bus` has no `x`. The cost — the editor has to carry two things —
is the whole point: the physics cannot read a position it was never given.

**D2 — The file is TOML, a stdlib.** No dependency added. TOML has `inf`/`-inf`,
which the machine record needs (`R = Inf` is "no governor", `Td0′ = Inf` is frozen
flux, `Efd_max = Inf` is an unlimited exciter); JSON has no spelling for any of
them. The prime is not a bare-key character in TOML, so on disk `Xd′` is `Xd_p`,
decided in one place (`_file_key`). The writer records **every** machine field,
defaults included, so a file does not change meaning when a default does; a test
compares `fieldnames(Machine)` against the writer's list so a new field cannot be
silently dropped.

**D3 — The reader is not a second validator.** It goes through `Bus`, `Branch`,
`Machine`, `Load` and `NetworkModel` and nothing else, so a file cannot build a
model the constructors would refuse, and it fails with the constructor's message
(m5-context.md D5, one validated path). What the reader adds is the *record* in
the message — "machine G2 has no `S_rated`" — because a TOML file is edited by
hand and "KeyError" does not say which of forty machines.

**D4 — Editing a field rebuilds the record through its constructor.** The
editor's state is the core's own immutable records. `set_field!` reconstructs
one with a value changed, so `H = 0` is refused at the keystroke, with the
constructor's own words, and the old record is untouched. Nothing is ever
half-applied.

**D5 — A draft that is invalid cannot be saved.** Follows from D2/D3: the file
holds `NetworkModel`s. The status line shows the running Σ P so the number to
fix is always in view. This is the editor's real limitation (below).

**D6 — Every mouse action lands in a data-coordinate function** the window also
returns (`canvas_press!`, `canvas_drag!`, `canvas_release!`), and the tests drive
those — the same choice the real-time windows made with `b.clicks[]`. One test
pushes a real `MouseButtonEvent` through the scene (with `Makie.shift_project`
for the pixel) to prove the callbacks are wired to those functions. The Axis's
own left-drag rectangle zoom is switched off; right-drag pans, the wheel zooms.

**D7 — The property panel is rebuilt per selection.** A Makie `Textbox` has no
`visible`, and a machine has nine editable numbers where a branch has two. The
boxes are read on **apply** from `displayed_string`, not `stored_string`, so a
user need not press Enter in each of nine boxes. Nine is the classical + governor
set; the detailed-tier and regulator parameters are carried by the file and by
`set_field!`, not the panel — nineteen boxes do not fit beside a map.

**D8 — "Map" is a PNG, not tiles.** `background = "iberia.png"`,
`extent = (x0, x1, y0, y1)`, and the buses sit on it in those coordinates, which
are what the `[layout]` table records. GeoMakie/Tyler are roadmap item 8; an
image is enough to place a bus on a country and costs no dependency.

**D9 — The runner is a parameter.** `_build_editor_window(ed; runner = launch)`.
The tests hand in a stub and assert it received the constructor's model, or that
an invalid draft never reached it — without opening a live window in a test.

## What the build found

- **The first render clipped the file and run controls off the frame.** With
  nine machine fields the control column already reached the bottom of a 900-px
  window. Moved the scenario bar under the canvas (width the canvas has to
  spare) and tightened the panel rows to 28 px. Render before claiming.
- **"load" is a tool AND a file action.** The file buttons became **save file**
  / **open file**; a button that says only "load" two rows under a tool called
  "load" is a trap.
- **A refused line left its first bus armed.** After "already connected" the
  branch tool's pending bus stayed set, so the next click would have started a
  line nobody began. The test caught it; the refusal now clears it.
- **The mouse-event path works offscreen.** `Makie.shift_project` + a
  `MouseButtonEvent` on `events(fig.scene)` reaches the handler and places a bus
  within 0.01 of the projected point, so the wiring is asserted rather than
  assumed.
- **A Makie `Textbox` intermittently draws its text squashed against the box's
  bottom edge** — a different subset of boxes on every frame, offscreen and on
  screen alike, on GLMakie 0.13.13 / Makie 0.24.14. Reproduced in a bare figure
  with nine `Textbox`es and no GridSim code, so it is upstream and not this
  window's:

  ```julia
  using GLMakie; GLMakie.activate!(visible = false)
  fig = Figure(size = (500, 600)); gl = fig[1, 1] = GridLayout()
  for (i, v) in enumerate(["300", "4", "2", "0.3", "1.05", "80", "Inf", "80", "1"])
      Label(gl[i, 1], "f$i")
      Textbox(gl[i, 2]; stored_string = v, width = 150, height = 28, fontsize = 13,
              tellwidth = false)
  end
  Makie.colorbuffer(fig); save("plain.png", fig)   # one of the nine is squashed
  ```

  Cosmetic: the value in the box is intact (the tests read it), and a click
  into the box redraws it. Not chased further here; worth an upstream issue.

## Limitations, stated

- **No invalid save.** D5. A half-drawn scenario with Σ P ≠ 0 cannot be written;
  balance it first. A "draft" format that bypasses the constructor was considered
  and rejected — it would be a second, unvalidated path into the model.
- **Nine fields in the panel**, D7. Detailed-tier parameters via the file.
- **One process, one window at a time for `run`.** `run ▶` opens the
  multi-machine window on the swing tier (`launch(net)`), which requires exactly
  one machine per bus and no loads; a model the swing engine refuses says so in
  the status line, verbatim. The detailed tier has no real-time window yet
  (m5-context.md D2), so a load-bus scenario can be saved and used from a script
  but not run from the button.
- **No undo.** Delete asks nothing. Save often.

## Files

- `src/model/scenario_file.jl` — `write_scenario`, `read_scenario`, `Layout`.
- `test/scenario_file.jl` — round trips, the field-list guard, Inf, layouts,
  a hand-written file, invalid files.
- `ui/src/editor.jl` — `ScenarioEditor` and its operations (no Makie).
- `ui/src/editor_window.jl` — the window, `editor`, `editor_render`.
- `ui/test/editor_tests.jl` — state and window tests.
- `docs/scenarios/three-machine-ring.toml` — an example file, written by the
  writer, with a layout.
- `docs/images/fig-editor-three-machine-ring.png` — the window, rendered.
