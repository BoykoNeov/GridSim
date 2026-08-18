# GridSimUI

The UI layer for [GridSim](../), kept as a **separate Julia package/environment**
so the core never acquires a UI/plotting dependency (see `../docs/SPEC.md` §3.1).
The dependency points one way only: `GridSimUI` → `GridSim`, never the reverse.
The core's own test suite asserts the other half — no Makie anywhere in its
dependency closure.

Built on `GLMakie` (native window): a live `f(t)` plot with a reference line at
`f0` and a dotted line at the running nadir, a `RoCoF(t)` trace beneath it,
numeric readouts (time, frequency, RoCoF, nadir, `H_sys`), one trip button per
unit, play/pause, a speed slider, and an inertia bar with a ghost of the
pre-disturbance value so the drop on a trip is visible rather than remembered.

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

## Tests

```
julia --project=ui -e 'import Pkg; Pkg.test()'
```

29 tests, all offscreen. They drive the actual widgets (setting `b.clicks[]` runs
the same handler a real click runs), so the click → queue → `inject!` path, the
pause/stop/speed wiring, the rolling buffer, and the offscreen render are all
covered. Physics and wall-clock pacing are asserted in the core suite and are
deliberately not duplicated here.
