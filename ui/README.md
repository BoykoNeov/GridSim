# GridSimUI

The UI layer for [GridSim](../), kept as a **separate Julia package/environment**
so the core never acquires a UI/plotting dependency (see `../docs/SPEC.md` §3.1).
The dependency points one way only: `GridSimUI` → `GridSim`, never the reverse.

Built on `GLMakie` (native window) for M1: a live `f(t)` plot, numeric readouts
(frequency, RoCoF, running nadir), per-unit trip controls, and a play/pause +
real-time-factor control. Implemented in the M1 UI batch — see
[`../docs/SPEC.md` §7.7](../docs/SPEC.md) and [`../docs/plans/`](../docs/plans/).

Set up (when the UI batch starts):

```julia
julia --project=ui -e 'import Pkg; Pkg.develop(path="."); Pkg.add("GLMakie")'
```
