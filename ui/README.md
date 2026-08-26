# GridSimUI

The UI layer for [GridSim](../), kept as a **separate Julia package/environment**
so the core never acquires a UI/plotting dependency (see `../docs/SPEC.md` §3.1).
The dependency points one way only: `GridSimUI` → `GridSim`, never the reverse.
The core's own test suite asserts the other half — no Makie anywhere in its
dependency closure.

Built on `GLMakie` (native window). There are **two windows, one per fidelity
tier**, and which one you get is decided by the model you hand `launch`:

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
julia --project=ui -e 'import Pkg; Pkg.develop(path="."); Pkg.add("GLMakie")'
```

(Run from the repository root. `ui/Manifest.toml` is gitignored.)

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

102 tests, all offscreen. They drive the actual widgets (setting `b.clicks[]` runs
the same handler a real click runs), so the click → queue → `inject!` path, the
pause/stop/speed wiring, the rolling buffer, and the offscreen render are all
covered — for both windows, including that the two engines really do reject each
other's events. Physics and wall-clock pacing are asserted in the core suite and
are deliberately not duplicated here.

One thing to know when adding a test: greying a button out happens on the
**render** path, which is throttled to ~30 fps, and a flat-out run of a few
simulated seconds can finish inside a single frame interval. Force a frame
(`win.refresh!(; force = true)`) before asserting on a label, exactly as the live
window would on its next tick.
