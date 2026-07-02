# Perturbation events for live injection (see docs/SPEC.md §3.3, §7.4).
#
# Events are queued by the orchestration loop and drained at a step boundary;
# the engine applies them between integrator steps (no algebraic re-init at M1).

"""
    PerturbationEvent

Abstract supertype for every live disturbance the user can inject while a
real-time engine runs. Concrete engines dispatch `inject!` on these.
"""
abstract type PerturbationEvent end

"""
    TripGenerator(id)

Take unit `id` offline. The engine removes it from the online set, recomputes the
aggregates (`H_sys`, `R_eq`, `headroom`), and adds the lost generation as a
persistent imbalance `ΔP_dist`. `Δω` carries through the event; `ΔPm` carries
through too *unless* the shrunken headroom now sits below it, in which case it is
re-init'd down to the new ceiling at the event boundary (see `inject!`).
"""
struct TripGenerator <: PerturbationEvent
    id::Symbol
end

"""
    StepLoad(ΔP_pu)

Apply a persistent step change in **load** of `ΔP_pu` (pu on `S_base`): positive
adds load (frequency drops), negative sheds it. Nice-to-have beyond the core trip
scenario.
"""
struct StepLoad <: PerturbationEvent
    ΔP_pu::Float64
end
