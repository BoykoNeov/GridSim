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

"""
    TripLine(from, to)

Take the branch between buses `from` and `to` out of service. Named by its **bus
pair**, in either order, rather than by branch id: the pair is what identifies a
branch uniquely in this tier (`NetworkModel` rejects parallel circuits precisely
so that it does — see the guard in `model/network_model.jl`), and it is the pair
the engine's own bookkeeping is keyed by.

Realised by zeroing that branch's coupling `K`, never by resizing the state — the
same discipline as `TripGenerator`, and for the same reason.

Unlike a generator trip, a line trip leaves `Σ Pm` **unchanged**, so the remaining
network still has an equilibrium: the machines settle back to `ω = 0` and the
angle differences move to a new steady state that the surviving branches must
carry. The exception is a trip that **splits the network**, which is a physically
real event this tier does not refuse: each island then has its own frequency, and
the single aggregate read-out is no longer meaningful for either (the same reason
`NetworkModel` refuses to be *constructed* disconnected).
"""
struct TripLine <: PerturbationEvent
    from::Symbol
    to::Symbol

    function TripLine(from::Symbol, to::Symbol)
        from === to && throw(ArgumentError(
            "TripLine: from and to are both $from — no branch joins a bus to itself."))
        return new(from, to)
    end
end

"""
    TripElements(; lines = [], sources = [])

Take several elements out of service **at one instant, as one event** (M10 step 4,
`docs/plans/m10-context.md` Hurdle 20): branches named by bus pair, as `TripLine`
names one, and sources (machines, inverters) by id, as `TripGenerator` does.

Two `TripLine`s injected back to back are NOT this in the detailed tier: that engine
re-solves the network after each one, so it passes through a network with only the
first element out — which it can refuse when the final network is fine (measured,
M10 step 0: case9, default loads, L45 then L67). This event re-solves once, on the
final network.

It also answers the question a split leaves, from the graph, where a single trip does
not (`m10-context.md` D4, D10): every piece left with no live source is
**de-energised** — its buses' loads off and their voltage held at zero — and every
source in a piece left with no load is **lost with it**, tripped in the same instant.
Each is logged as what it is (`:trip_generator`, `:deenergise`).
"""
struct TripElements <: PerturbationEvent
    lines::Vector{Tuple{Symbol,Symbol}}
    sources::Vector{Symbol}

    function TripElements(; lines = Tuple{Symbol,Symbol}[], sources = Symbol[])
        ls = Tuple{Symbol,Symbol}[(Symbol(a), Symbol(b)) for (a, b) in lines]
        ss = Symbol[Symbol(s) for s in sources]
        isempty(ls) && isempty(ss) && throw(ArgumentError(
            "TripElements: no lines and no sources — an event that takes nothing out."))
        for (a, b) in ls
            a === b && throw(ArgumentError(
                "TripElements: the line $(a)–$(b) joins a bus to itself; no branch does."))
        end
        keys = [a < b ? (a, b) : (b, a) for (a, b) in ls]
        allunique(keys) || throw(ArgumentError(
            "TripElements: a line is named twice (in either order) — one event takes an " *
            "element out once."))
        allunique(ss) || throw(ArgumentError(
            "TripElements: a source is named twice — one event takes an element out once."))
        return new(ls, ss)
    end
end
