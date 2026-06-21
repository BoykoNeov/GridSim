# PLACEHOLDER — implemented in the M1 code batch (NOT scaffolded).
#
# The real-time orchestration loop (docs/SPEC.md §7.5): drain the event queue,
# step the engine, publish state to an Observable, pace to wall-clock time.
#
# INVARIANT: this file must NEVER import Makie or any UI/plotting package. It may
# use Observables.jl (a standalone package; Makie depends on it, not the reverse)
# to publish live state that the UI subscribes to. See docs/SPEC.md §3.1.
#
# Outline:
#   function run_realtime!(engine, state_obs; rtf = 1.0)
#       dt = 0.02
#       while running[]
#           for e in drain!(event_queue);  inject!(engine, e);  end
#           step!(engine, dt)
#           state_obs[] = current_state(engine)   # Observable -> UI redraws
#           sleep_to_pace(dt / rtf)               # maintain wall-clock pacing
#       end
#   end
