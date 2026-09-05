# GridSimUI

The UI layer for [GridSim](../), kept as a **separate Julia package/environment**
so the core never acquires a UI/plotting dependency (see `../docs/SPEC.md` §3.1).
The dependency points one way only: `GridSimUI` → `GridSim`, never the reverse.
The core's own test suite asserts the other half — no Makie anywhere in its
dependency closure.

Built on `GLMakie` (native window). There are **three**: two real-time windows,
one per fidelity tier, chosen by the model you hand `launch` — and a third for the
other *execution mode*, the playback overlay, which has its own verb (see below).

The two real-time windows:

- **`SystemModel` → the aggregate window.** A live `f(t)` plot with a reference
  line at `f0` and a dotted line at the running nadir, a `RoCoF(t)` trace beneath
  it, numeric readouts (time, frequency, RoCoF, nadir, `H_sys`), one trip button
  per unit, play/pause, a speed slider, and an inertia bar with a ghost of the
  pre-disturbance value so the drop on a trip is visible rather than remembered.
- **`NetworkModel` → the multi-machine window.** One frequency trace per machine
  with the centre-of-inertia aggregate overlaid on the same axis, a second panel
  of rotor angles *relative to that aggregate*, dashed markers and a written list
  wherever a perturbation was applied, two groups of buttons — trip a machine,
  trip a line — and, on a model whose protection is armed, the shed annotation
  described below.

They are siblings rather than one window with a switch, because the two engines
do not accept the same events: `TripLine` has no method on the aggregate view (a
`SystemModel` has no branches) and `StepLoad` has none on the swing engine (a
classical-tier load is a machine, and there is no aggregate imbalance to move).
The set of buttons a window can offer is a property of the engine, so it is
settled by dispatch on the model type.

Two things about the multi-machine panels are worth knowing before reading one:

- **Everything on the frequency axis is Hz.** A machine's speed is a per-unit
  deviation internally and is converted at this boundary, so the aggregate really
  is an overlay of the same quantity rather than a second thing in the same box.
- **Angles are drawn against the aggregate, never raw.** The steady-state solver
  fixes the overall angle arbitrarily, so an absolute rotor angle is not a
  plottable number, and after a generator trip every angle grows without bound.
  A tripped machine is still drawn — it visibly walks off the top of the frame —
  but it scales nothing: the axis and the machine-to-machine read-outs are over
  the machines still online, because the difference between a dead rotor coasting
  at nominal and a system sinking at 2.7 % is not a spread.

## Setup

```
julia --project=ui -e 'import Pkg; Pkg.instantiate()'
```

(Run from the repository root. `ui/Manifest.toml` is gitignored, which is why
this has to resolve from scratch on a fresh clone.)

The link back to the core package lives in `ui/Project.toml`'s `[sources]`
section, so there is **no `Pkg.develop(path = "..")` to run by hand** — verified
on Julia 1.12.6 with the manifest deleted. That section is honoured from Pkg 1.11
onwards; on an older Julia you need the develop call, and `ui/Project.toml` still
declares a `julia = "1.10"` floor that has not been reconciled with it (M4 step 5
owns that).

## Run the window

```
julia --project=ui -e "using GridSimUI; wait_for_close(launch())"
```

`wait_for_close` is what keeps the process alive — without it the shell exits the
instant the window opens and takes the window with it. Closing the window stops
the simulation loop.

`launch` takes the model and the usual knobs, e.g. a slow-motion run of a system
with an armed load-shedding ladder:

```julia
using GridSimUI, GridSim
wait_for_close(launch(example_system(); rtf = 0.25, window_seconds = 30.0))
```

Hand it a network model instead and you get the multi-machine window:

```julia
using GridSimUI, GridSim
wait_for_close(launch(three_machine_ring(); rtf = 0.5))
```

The window takes a few seconds to appear (GLFW window creation and shader
compilation); the simulation clock is starved for that stretch and then paces
accurately — measured 4.01× against 4.0× asked, on screen.

## Startup

The package precompiles a workload (`src/precompile.jl`): every window is built
offscreen once, driven through the real loop, and rendered, at *package
precompile time* rather than at first use. Measured on 2026-09-05 (Julia 1.12.6,
GLMakie 0.13.13), a cold session from `using GridSimUI` to the first frame:

| | before | after |
|---|---|---|
| `using GridSimUI` | 10.4 s | 13.3 s |
| first multi-machine window (`smoke_render(three_machine_ring())`) | 76.5 s | 6.2 s |
| first aggregate window (`smoke_render()`) | 23.9 s | 1.8 s |
| first playback overlay (`playback_render()`) | 4.9 s | 1.2 s |

The price is paid once: precompiling `GridSimUI` takes about two minutes and
needs an OpenGL context. On a machine without one (a headless CI runner), set
`GRIDSIM_UI_PRECOMPILE=0` to skip the workload — the package still loads and
compiles at first use as before. A failure inside the workload is caught and
reported as a warning, never fatal.

## The look

`src/theme.jl` is the one place the three windows' appearance is decided —
fonts, colours, widget shapes, legend placement — applied by wrapping each
builder in `with_theme`, so it never leaks into a caller's own Makie session.
Two of its rules are about cost, not taste, and are worth knowing before
editing a read-out:

- **Every numeric read-out is two labels, not one.** A static column of names
  written once, and a column of values that is rewritten — and rewritten at
  10 Hz, on its own clock, while the traces still take every published state
  and repaint at ~30 fps. Setting a Makie `Label`'s text re-runs the glyph
  layout for the whole string: measured at ~700 µs and ~480 KB for the old
  seven-line network read-out, which was 85 % of a repaint's allocation. Now a
  forced repaint allocates ~325 KB instead of ~585 KB, and the steady-state
  window path about 220 KB per frame. What remains is mostly the moving time
  window recomputing its ticks (~100 KB per frame); see
  `docs/plans/ui-visuals-performance.md` for the options that were measured.
- **Numbers are drawn in DejaVu Sans Mono, shipped inside Makie's own assets.**
  `@sprintf("%8.3f")` only aligns into columns in a fixed-width face, and a
  system font name would make the picture depend on the machine.

The `readout` observable each window returns is the composite of those two
columns — exactly the rows the labels draw, joined — so a test that searches it
is reading what the picture says.

## Render a frame without a screen

```julia
using GridSimUI
smoke_render(; path = "trip.png", trips = [(2.0, :G1)], duration = 20.0)
```

Builds the *same* window offscreen, drives it through a scripted trip timeline
flat out, and saves a PNG. Trips go through the `EventQueue` and the real
orchestration loop — the identical path a button click takes — so this exercises
the live wiring rather than bypassing it. It is how the window is checked in a
headless session and in CI.

Pass `ylims_f = (lo, hi)` / `ylims_rocof = (lo, hi)` to pin the axes whenever two
renders are meant to be *compared*. The live window sizes its axes to the run
(expand-only), which is right on screen but makes two separate pictures fill
their own frames — a dip four times steeper then draws exactly like a shallow
one.

The network method takes a timeline of **events** rather than of unit ids,
because this engine accepts two kinds and naming the type is how you say which.
Mixing them in one run is the point — a line trip the system survives, followed
by the generator loss it does not:

```julia
using GridSimUI, GridSim
smoke_render(three_machine_ring(); path = "swing.png", duration = 20.0,
             events = Tuple{Float64,PerturbationEvent}[
                 (2.0, TripLine(:B1, :B2)),
                 (8.0, TripGenerator(:G1))])
```

Its axis pins are `ylims_f` and `ylims_δ`.

## The shed annotation (report Figure 3-67)

Hand the network window an armed low-frequency shedding ladder and the frequency
panel annotates itself: a faint dotted line at every **armed** stage's threshold,
a marker wherever a stage actually **fired**, and the ladder's log written out
beside the plot in MW.

```julia
using GridSimUI, GridSim
stages = [LoadShedStage(49.8, 0.01; label = :s_49_8),
          LoadShedStage(49.6, 0.01; label = :s_49_6),
          LoadShedStage(49.4, 0.01; label = :s_49_4)]
smoke_render(two_machine_system(); path = "shed.png", dt = 0.02, duration = 12.0,
             shed = [:G1 => stages],                       # bound to ONE machine
             ramp = [:G1 => GenerationRamp(-0.1, 0.0, 2.0)])   # −10 MW over 2 s
```

That one runs as written. The real thing — the twelve-stage Iberian defence plan
on the two-area model — is `ui/scripts/figure_3_67.jl`, below.

Three things about it are deliberate:

- **The markers come from the ladder's log, never from the plotted trace.** Both
  coordinates are then exact — the log's instant is root-found rather than
  sampled on the `dt` grid, and a downward crossing means the frequency *is* the
  threshold at that instant. Sampling the buffer instead would land within one
  step of the same place and look identical, which is why the test asserts the
  coordinates and not the marker count.
- **The two logs are drawn together and never merged.** Dashed *vertical* lines
  are the event log — what a user, or an out-of-step relay, injected. The markers
  are the ladder's. A shed is not an injected event: nobody chose it, and its
  instant is more precise than an event stamp could carry.
- **Thresholds are drawn per armed ladder**, so a model with no protection grows
  no lines, and a two-area model with one plan draws that plan's thresholds and
  not some global table's.

`show_coi = false` drops the centre-of-inertia overlay **and** the `f_COI` /
nadir rows from the read-out. Reach for it whenever the model's machines are
areas that can separate: an inertia-weighted mean over two areas losing
synchronism is not a frequency, and leaving it in the read-out while removing it
from the plot would just move the meaningless number somewhere more prominent.

`shed`, `ramp` and `out_of_step` are forwarded to the engine untouched, so the
window can be opened on a fully armed system rather than only on a bare one.

## The playback overlay — a solved run, scrubbed rather than watched

The third window is not a third fidelity tier; it is the other **execution mode**.
The two windows above show a run as it happens. This one is handed a run that has
already finished — two solved trajectories of one scenario, on one output grid —
and lets you move a cursor through it.

```
julia --project=ui -e "using GridSimUI, GridSim; wait_for_close(playback())"
```

It has its own verb rather than a third `launch` method, because both execution
modes run on the same `NetworkModel`: the model type cannot say which you wanted.
The core draws the same line the same way — `run_realtime!` against `solve!`.

What you get: the network swing tier's centre-of-inertia frequency against the
aggregate tier compiled down from the same model (`coi_model`), the gap between
them on a log panel beneath, a time slider, and the whole-run divergence read from
`analysis/postprocess.jl` — largest gap and when, RMS, and the instant they part
company.

Four things about it are deliberate:

- **It cannot run.** The window is handed *series*, not a model: no event queue, no
  control block, no repaint throttle, no engine. It is incapable of influencing the
  numbers it draws, which is `docs/SPEC.md` §3's "render state is not simulation
  state" in its strongest available form.
- **The slider indexes samples, not time.** Nothing here is interpolated. A slider
  over time would need a value between two recorded samples, and both ways of
  producing one are ways this project has already rejected — there is no
  interpolant left after a solve, and straight-lining between decimated samples was
  measured at 33.7× the agreement band. Every number the read-out shows is a
  recorded sample verbatim.
- **The agreement band is derived and displayed, and there is no control for it.**
  "When did they part company" is only an answer if the band was stated before the
  gap was seen. It comes from `tolerance_band` on the solve's own `reltol` and is
  shown with its derivation. Exploring the tolerance means solving again, which
  re-derives the band with it — never a slider.
- **The two tiers need not receive the same events, and the picture says which.**
  The aggregate view has no branches, so a line trip is not an event it can be
  given at all. `perturbations` and `aggregate_perturbations` are separate
  arguments the caller writes out; when they differ, the event list says so in red
  and marks each row the aggregate never saw.

The default scenario is a line trip, and that choice is the point:

```julia
using GridSimUI, GridSim
# The shipped default: the swing tier rings, the aggregate tier is handed nothing.
playback_render(; path = "swings.png")
# The contrast: a disturbance both tiers accept, whose much larger gap is NOT swings.
playback_render(; path = "damping.png", horizon = 60.0,
                perturbations = [1.0 => TripGenerator(:G1)])
```

`TripLine(:B3, :B1)` opens one side of the ring: the machines swing against each
other, the centre-of-inertia frequency rings by about 1 mHz and decays, and the
aggregate tier sits at exactly 50 Hz. The whole gap is then residual inter-machine
swing content — the one lesson of the three `docs/SPEC.md` §7.6 names that this
pair can support.

A generator trip is the instructive counter-example, and it is deliberately *not*
the default. Both tiers accept it, and the gap reaches 0.857 Hz — roughly 800×
larger, and not the lesson: the aggregate keeps the tripped machine's damping in
its denominator, so the two settle at different levels. It arrives and stays,
where a swing decays. Both figures are checked in for that contrast:

```
julia --project=ui ui/scripts/playback_overlay.jl
```

writes `docs/images/fig-m4-playback-line-trip.png` and
`docs/images/fig-m4-playback-generator-trip.png`.

`playback_render` places the cursor at the instant of largest disagreement by
default, since a saved frame has no reader to drag the slider. Its axis pins are
`ylims_f` and `ylims_gap`.

**Point it at a single synchronous area.** Across an area split the
inertia-weighted mean is not a system frequency, and then *both* curves are
meaningless rather than just one — there is nothing to suppress, so the caller has
to not do it. The figure's caption says so.

## Figure 3-67, checked in

```
julia --project=ui ui/scripts/figure_3_67.jl
```

Writes `docs/images/fig-3-67-two-area.png` — the 28 April 2025 Iberian separation
on the two-area tier, with the real ES + PT defence plan armed and annotated. It
is one cell of the sweep in `scripts/iberia_two_area.jl`, which is the script that
owns the model and the data; this one only adds the window. **Read that file's
header before quoting anything off the picture**: the defence plan arrests the
frequency fall and does not save the tie, the tie in this cell is unprotected, and
voltage collapse is out of scope on this tier at any point of the figure.

## Tests

```
julia --project=ui -e 'import Pkg; Pkg.test()'
```

172 tests, all offscreen. They drive the actual widgets (setting `b.clicks[]` runs
the same handler a real click runs), so the click → queue → `inject!` path, the
pause/stop/speed wiring, the rolling buffer, and the offscreen render are all
covered — for both real-time windows, including that the two engines really do
reject each other's events. Physics and wall-clock pacing are asserted in the core
suite and are deliberately not duplicated here.

The playback window is tested differently, for the reason it *is* different:
nothing in it is running, so there is no queue to push into and no loop to drive.
What replaces the click path is **exactness**. Every number it shows is a recorded
sample verbatim, so its checks are `===` rather than `atol` — an off-by-one index
is the bug this window can really have, and a tolerance-based assertion passes
against it (adjacent samples differ by ~1e-6 Hz). For the same reason, checks that
a caption or a read-out is *in the picture* go through the figure's layout, not
through the observable that feeds it: a `Label` with the right text that was never
added to the window passes every text assertion you can write about it.

One thing to know when adding a test to either real-time window: greying a button
out happens on the
**render** path, which is throttled to ~30 fps, and a flat-out run of a few
simulated seconds can finish inside a single frame interval — and the numeric
read-out is rewritten on a slower clock still (10 Hz). Force a frame
(`win.refresh!(; force = true)`) before asserting on a label or on `readout`,
exactly as the live window would on its next tick.
