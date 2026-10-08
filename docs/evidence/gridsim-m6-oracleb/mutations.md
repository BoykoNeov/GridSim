# Oracle B — the anti-vacuity mutation set

Each mutation is applied to **our** side only, in `src/`, and the suite is run.
The rule the repo keeps: a mutation must go where the two sides FORK, never into a
view both read (M4 step 4). `to_powersystems` reads the raw `Machine` / `Branch` /
`Load` structs, so the fork is at `machine_arrays` / `load_arrays` too — those move
our side alone here, unlike in `oracle.jl` where both sides read them.

| # | file | mutation | must be caught by |
|---|------|----------|-------------------|
| M1 | `ac_powerflow.jl` `_ac_admittance` | `y = 1/(R + im*X)` -> `1/(R - im*X)` (sign of the reactance) | every AC channel + `independent_mismatch` |
| M2 | `ac_powerflow.jl` `_ac_admittance` | drop the off-diagonal `-y` at `[t,f]` only (asymmetric Y) | meshed/lossy channels + mismatch |
| M3 | `ac_powerflow.jl` `_zip_scale` | `a_z*V^2 + a_i*V + a_p` -> `a_z*V^2 + a_i*V^2 + a_p` (current share squared) | mixed-share fixtures only — the reason a mixed-share fixture ships |
| M4 | `ac_powerflow.jl` `_ac_flows` | swap `sin`/`cos` in the reactive term | `qflow` channel + the losses identity |
| M5 | `ac_powerflow.jl` `_ac_residual!` | drop the ZIP scaling from the reactive equation | `Vm` + mismatch |
| M6 | `network_model.jl` `machine_arrays` | `Pm = P0/S_base` -> `P0/S_rated` | off-base fixture ONLY (identity on the others) |
| M7 | `network_model.jl` `load_arrays` | `P = P0/S_base` -> `P0*S_base` | every fixture |
| M8 | `ac_powerflow.jl` limit switching | `>` -> `>=` on the `Q_max` test, or swap `Q_min`/`Q_max` | the binding-limit testset |

**M6 is the one the plan's fixture list exists for.** With every machine rated at
the system base the two conversions are the identity and the mutation is a no-op —
exactly the shape oracle A hit when two of ten mutations did nothing on the fixture
they were first run against.
