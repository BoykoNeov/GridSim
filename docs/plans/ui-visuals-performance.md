# UI visuals and performance — what was done, what was measured, what is left

**Status:** first batch done 2026-09-05 (172 / 172 UI tests green, core suite
untouched — no core file changed). The remaining items below are written so a
less capable model can execute them one at a time: each has the files to touch,
the exact measurement to take first, the acceptance criterion, and the trap.

Cross-cutting rather than a milestone: nothing here changes physics, the engine
interface, or a recorded number. Read `docs/SPEC.md` §3 ("render state ≠
simulation state") before touching any of it — every item stays on the render
side of that line.

---

## 1. What the first batch measured (the baseline, so nobody re-measures it)

All on the dev machine: Windows 11, 16 cores, Julia 1.12.6, GLMakie 0.13.13.
Scripts are in `M:\claud_projects\temp\gridsim-perf\` (`bench.jl`, `bench2.jl`,
`bench3.jl`, `bench4.jl`) — a temp folder, not the repo; copy what you need.

**The engines are not the bottleneck and nothing in `src/` was worth touching.**

| what | cost |
|---|---|
| `step!(SwingEngine)` on `three_machine_ring`, dt 0.02 | 1.4 µs, 427 B (the raw integrator step is 1.2 µs and 0 B; the rest is `current_state`'s two fresh vectors) |
| `step!(FrequencyResponseEngine)` | 0.3 µs, 104 B |
| `run_realtime!` flat out, ring, 60 s of simulation | 8 ms wall — 7,460× real time |
| `solve!` ring, 20 s, saveat 0.02 | 15 ms |

**The UI was the cost, in two places.**

*Cold start* (what a user waits for): `using GridSimUI` 10.4 s, then the FIRST
network `smoke_render` **76.5 s**, first aggregate 23.9 s, first playback 4.9 s.
About two minutes before the first multi-machine window. Fixed by
`ui/src/precompile.jl` (a PrecompileTools workload that builds and renders every
window once at package precompile time): now 13.3 s / **6.2 s** / 1.8 s / 1.2 s.

*Repaint* (what the live window costs per frame at ~30 fps), network window,
30 s rolling window, seven traces:

| piece | before | after |
|---|---|---|
| set the read-out `Label` text (seven lines) | 700–900 µs, **575 KB** — regardless of `tellheight`, fixed sizes, or whether the text changed | values-only label, rewritten at 10 Hz |
| `xlims!` on the moving window (two linked axes, upper tick labels hidden) | 820 µs, 102 KB | unchanged |
| `notify` all seven trace observables (1,502 points each) | 13.5 µs, 2.9 KB | unchanged |
| `refresh!(force = true)` in total | 967 µs, 585 KB | 894 µs, 325 KB |
| steady state, real throttle | — | ~220 KB per frame, ~6.6 MB/s |
| `GLMakie.render_frame` alone (no readback) | 0.7 ms | — |
| `Makie.colorbuffer` (render + readback, PNG path only) | 6.9 ms | — |

Tick styles were tried for the moving window and none helps: `LinearTicks(6)`
954 µs, `MultiplesTicks` 2,956 µs, an explicit tick vector per frame 1,164 µs.
The cost is Makie re-laying-out the tick labels and grid, not choosing the ticks.

**One more measured fact, not yet acted on (item 3 below):** with GLMakie loaded,
`sleep(0.002)` on this Windows machine returns after ~14.7 ms (204 iterations in
3 s). Julia's sleep resolution here is the ~15 ms Windows timer tick.

## 2. What the first batch changed

- `ui/src/theme.jl` (new) — `GRIDSIM_THEME`, the named colours, the monospace
  font from Makie's own assets, `readout_block!` / `readout_text`,
  `section_label!`. Applied by `themed(build)` = `with_theme` in each builder.
- `ui/src/precompile.jl` (new) — the workload; `GRIDSIM_UI_PRECOMPILE=0` skips it.
- All three windows: builders renamed `_build_*_impl` behind a one-line themed
  wrapper with the old name; read-outs split into static keys + live values (the
  returned `readout` observable is their composite); values rewritten at
  `READOUT_INTERVAL = 0.1` s; buttons fill the control column; section headings;
  mono event/shed lists.
- Playback window: legends moved out of the axis into the read-out column (the
  shipped generator-trip render had the legend lying across both curves and the
  cursor dot); the asymmetric-events heading wraps instead of running off the
  figure.
- Network window: legend top-left (a generator trip takes the data to the
  bottom-right, where it was); column 340 px; shed rows at 11 pt so the Iberian
  plan's widest row does not wrap.
- `ui/Project.toml`: `PrecompileTools` added. `Pkg.add` dropped every comment in
  the file; restored by hand, and the file now says so.
- All three checked-in figures regenerated; the root README gained a gallery.

## 3. Remaining items, in the order to do them

### 3.1 Pacing cadence on Windows (core, `src/orchestration/realtime_loop.jl`)

**Why.** `_pace` does `sleep(remaining - 1e-3)`. With a 15 ms timer tick, a
20 ms step at `rtf = 1` sleeps ~30 ms, then the loop is late, then it sprints
until caught up (re-anchoring only after `max_lag = 0.25` s). The *average* rate
is right (README: 4.01× against 4.0×) but delivery is bursty at the 15 ms
level. At 30 fps that is invisible; it becomes visible if anything ever plots at
higher rates or drives audio/hardware from the loop.

**Measure first.** Headless, `rtf = 1`, `dt = 0.02`, 10 s: record `time()` at
every publish (an `on(state)` handler pushing to a vector), then the
inter-publish intervals. Report median, p95, max. Do it with GLMakie loaded and
without (the timer resolution may differ).

**If p95 > 25 ms:** on Windows, request a 1 ms timer for the life of the loop —
`ccall((:timeBeginPeriod, "winmm"), Cuint, (Cuint,), 1)` before the `while`, and
`timeEndPeriod(1)` in a `finally`. Guard with `Sys.iswindows()`. Re-measure.
Do NOT replace the sleep with a yielding spin: that burns a core for up to 15 ms
of every 20 ms step, on the same thread GLMakie renders on.

**Accept when:** p95 inter-publish interval < 25 ms at `rtf = 1`, and the
existing core pacing tests still pass. Record the numbers in this file.

**Trap:** timing tests are flaky; do not add a tight-tolerance assertion to the
suite. Assert loosely (median within 3 ms) or record the measurement here and in
`ui/README.md` without a test.

### 3.2 The moving-window tick cost (UI, `window.jl`, `network_window.jl`)

**Why.** After the read-out split, `xlims!` on the scrolling window is the
largest per-frame allocation (~100 KB, ~800 µs). It is Makie re-laying-out tick
labels and gridlines every frame because the limits move every frame.

**The option to try — a relative time axis.** Keep the x limits *fixed* at
`(-w, 0)` and plot `t - t_now` instead of `t`: the traces scroll, the ticks
read "seconds ago" and never change, and the per-frame cost drops to the trace
re-upload that is already paid (13.5 µs for seven traces). The absolute time
stays in the read-out. Implementation: `RollingTrace` keeps absolute `t`; on
each repaint the plotted observable is rebuilt as `Point2f(t - t_now, y)` (one
pass over ≤ 1,502 points per trace — measure; it should be ~µs). The x label
becomes "time before now (s)".

**Decide with the user first**, not alone: a relative axis is a real change in
what the window shows (event markers and shed markers also have to move with
it), and the M1/M2 plan trios describe an absolute axis. Offer it as a choice
with the measured saving. If declined, close this item with "measured, declined".

**Accept when:** forced repaint allocation < 150 KB (bench: `refresh!(; force =
true)` 300× on a window after a 45 s flat-out run), all UI tests green, the
three figures regenerated and looked at — event markers still sit on the
events.

### 3.3 Trace decimation for long rolling windows (UI, `window.jl`)

**Why.** `RollingTrace` capacity is `window_seconds / dt`. At the shipped 30–60 s
that is ≤ 3,000 points per trace and costs nothing. At `window_seconds = 600`
it is 30,000 points × 7 traces uploaded per frame, and at 3,600 s, 180,000.
Nobody has run that yet; the failure is a window that gets slower the longer
you ask it to remember.

**Measure first.** `_build_network_window(three_machine_ring(); window_seconds
= 600.0)`, run 600 s flat out, then time `refresh!(force = true)` +
`GLMakie.render_frame(screen)` 50×. Record ms per frame.

**If > 5 ms:** cap the *plotted* points at ~4,000 per trace with min/max
bucketing (each bucket of consecutive samples contributes its min and its max,
so peaks survive — the nadir must never be decimated away; this is the same
argument as the recorder's "never a ring buffer" note in
`src/engines/recorder.jl`). The buffer keeps every sample; only the observable
handed to `lines!` is bucketed. Re-measure.

**Accept when:** 600 s window renders in < 5 ms per frame; a test asserts the
plotted extremes equal the buffer's extremes after a trip (the bug worth
catching is a decimation that drops the dip).

### 3.4 Precompile coverage of the on-screen path (UI, `precompile.jl`)

**Why.** The workload renders offscreen. `launch` displays a *visible* screen,
which may specialise different methods. Unmeasured.

**Measure first.** Fresh session, `using GridSimUI`, then `@time
launch(three_machine_ring())` and note when the first frame appears (a
`screen.render_tick` listener, or just a stopwatch). Compare with
`smoke_render`'s 6.2 s.

**If it is materially slower (> 10 s):** add to the workload a
`display(fig; visible = false)` of one built window followed by `close(screen)`,
the way GLMakie's own `precompiles.jl` does (`display(plot(x); visible =
false)`). Keep it inside the same `try`/`finally` so cleanup still runs.

**Accept when:** first visible window ≤ 1.5× the offscreen time. Update the
table in `ui/README.md` "Startup".

### 3.5 Render settings for `launch` (UI, all three `launch`/`playback` methods)

**Why.** `GLMakie.activate!` accepts `framerate`, `render_on_demand`, `vsync`.
The defaults are probably fine; nobody has measured idle CPU of a paused window
or the effect of `vsync`.

**Measure first.** Open the network window, pause, watch the process's CPU for
30 s (Task Manager or `Get-Process julia | select CPU` twice). Then running at
`rtf = 1`. Record both.

**If a paused window burns > 2 % of a core:** `render_on_demand = true`
(should already be the default) and check nothing notifies observables while
paused — `refresh!` returns early when nothing has been published, but `hbar`
and `nadir_line` are rewritten every forced frame.

**Accept when:** paused ≤ 2 % of a core, running ≤ 15 %. Record the numbers.

### 3.6 Tests the first batch owes (UI, `ui/test/runtests.jl`)

Cheap, and each pins something this batch changed by hand:

- **The read-out clock.** Build the network window, force a frame, capture
  `win.readout[]`; publish a state with a different `t` within 100 ms and call
  `win.refresh!()` (not forced) — `readout` must be *unchanged*; force, and it
  must change. Pins the 10 Hz split so a later "simplification" that rewrites
  every frame is caught.
- **`readout_text` matches the labels.** For each window, split `win.readout[]`
  into rows and assert each row starts with the corresponding line of the keys
  label's text and ends with the values label's line (`in_layout` gives the
  labels; `readout_block!` returns them — thread them out through the window's
  return tuple if needed).
- **Both playback legends are in the layout** (`in_layout(win.fig.layout,
  legend)` — return them from the builder as `legends`), since a legend built
  and never placed passes every other check.
- **Nothing off the figure.** For each rendered figure, assert every `Label`'s
  `layoutobservables.computedbbox[]` lies inside `fig.scene.viewport[]` — the
  overflow the playback events heading had is exactly this, and it is not
  caught by any current test.

### 3.7 Housekeeping

- `ui/README.md` "Tests" still says 172; update when 3.6 lands.
- After ANY change to `theme.jl`, regenerate all three figures
  (`julia --project=ui ui/scripts/playback_overlay.jl` and
  `julia --project=ui ui/scripts/figure_3_67.jl`) and look at them — "render
  before claiming" is the standing rule, and the theme is global to the pictures.
- The `PrecompileTools` compat is `"1"`; leave it.

## 4. Things considered and not done, with the reason

- **Fewer or different ticks on the moving window** — measured, no help (§1).
- **`tellheight = false` / fixed-size Labels to dodge the layout cascade** —
  measured, the cost is glyph layout itself, not the cascade (§1).
- **Core allocation in `current_state`** (240 B per step from two fresh vectors)
  — at 50–500 states/s it is < 120 KB/s; the UI allocates fifty times that.
  Not worth an API change.
- **A dark theme** — no demand, and every figure in the docs is light.
- **`Point2d` traces for long runs** — Float32 time at `t = 3,600` s resolves
  to 0.24 ms, ten times finer than `dt`. Not a problem before 3.3 is.
