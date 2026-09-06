# GridSimReference — the external oracle (docs/plans/m4-tasks.md step 4).
#
# A THIRD package, mirroring `ui/`: it depends on `GridSim` and on
# `PowerDynamics`, and never the reverse. Core keeps its six dependencies and its
# dependency-closure test (`test/runtests.jl`, "core dependency closure") keeps
# passing — with a new clause saying core must not reach PowerDynamics either.
# Dependency direction is the enforcement mechanism this repo already uses for the
# no-Makie invariant (docs/SPEC.md §3.1); D3 gives the oracle the same shape.
#
# WHAT THIS IS FOR. Until now every check in GridSim has been ours against ours:
# a closed form we derived, or one of our tiers against another of our tiers. That
# leaves one class of error undetectable — the one where the simple model and the
# detailed model are both wrong in the same way, because the same hands wrote
# both. m4-context.md D2 names it exactly: with two in-house tiers and no outside
# implementation, "the simple model drops swings" and "our model has a bug" look
# identical. This package is what tells them apart.
#
# THE CASE IS COMPILED FROM `NetworkModel`, NEVER TYPED BESIDE IT (D5). SPEC §3.2
# says reduced models are derived views, never parallel hand-maintained copies. A
# PowerDynamics system written out next to `two_machine_system()` would be exactly
# the forked parallel data that invariant forbids, and it would drift silently —
# the worst possible property in an oracle, because a drifted oracle agrees with
# nothing and says so in a way that looks like a physics finding.
#
# THE COST OF THAT CHOICE, STATED ONCE, BECAUSE IT BOUNDS WHAT THE ORACLE CAN
# CATCH. Compiling from the canonical model means both sides read the same
# `machine_arrays` / `branch_arrays` / `_coupling`. Anything wrong *in those* is
# handed identically to both and the comparison goes green against a real bug. So
# the oracle checks everything DOWNSTREAM of the per-unit conversion — the
# coupling formula's use, the graph mapping, the sign conventions, the fixpoint,
# the integration — and nothing upstream of it. The conversions themselves stay
# checked by M1/M2's closed forms, with ONE exception the transient comparison
# does reach externally (`X′d`'s inverse weight; see `docs/plans/m4-context.md`).
# The anti-vacuity mutation must therefore live in `swing_vertex!`, never in the
# shared data path.
#
# TWO TIERS, ANSWERING TWO DIFFERENT QUESTIONS (D13, m4-context.md).
#
#   `:swing`     — PowerDynamics' `Library.Swing`. Equation for equation our
#                  `swing_vertex!`, including the constant-voltage-magnitude-AT-
#                  THE-BUS representation. Any gap is an implementation
#                  difference, so the band is derived from solver tolerance
#                  alone and it is the bug-detector. Valid on ANY topology.
#
#   `:classical` — PowerDynamics' `Library.ClassicalMachine`: `E′` behind `X′d`
#                  on an algebraic terminal bus. A genuinely different electrical
#                  formulation, valid only on a radial pair (enforced below), and
#                  it does NOT reduce to ours exactly: its mechanical input is a
#                  TORQUE (`τ_m/ω`) where ours is a POWER. That residual is
#                  proportional to the machine's loading and is identified by
#                  that signature, never bounded by a tolerance.
#
# GLOBAL MUTABLE STATE, THE ONE HAZARD IN USING THIS LIBRARY. PowerDynamics reads
# `set_Sbase!` / `set_fbase!` at COMPONENT CONSTRUCTION time and bakes the values
# in. They are process-global. `build_oracle` therefore sets both from the model
# it was handed, on every call, immediately before building anything — a model
# carries its own bases, and a stale global would silently build the previous
# model's per-unit system.
module GridSimReference

using GridSim
using PowerDynamics
using PowerDynamics: Library
using NetworkDynamics
using OrdinaryDiffEq

export OracleCase, build_oracle, oracle_solve, oracle_band, reduced_line_reactance
export set_mechanical_power!

include("oracle.jl")

end # module
