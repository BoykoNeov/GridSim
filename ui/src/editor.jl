# The scenario editor's STATE and OPERATIONS — everything the canvas does to a
# model, with no Makie in it.
#
# The window (`editor_window.jl`) is a view over this: every mouse click and every
# "apply" ends in one of the functions below, and the tests drive these functions
# directly for the same reason the real-time windows' tests set `b.clicks[]` —
# what is asserted is the path a user's action takes, not a simulation of the
# mouse. Nothing here is exported from the core, because none of it is physics.
#
# The model side is the core's own immutable records (`Bus`, `Branch`, `Machine`,
# `Load`, and since M7 step 8 `Inverter`): editing a field REBUILDS the record through its constructor, so a value
# the constructor refuses (`H = 0`, a self-loop, a negative load) is refused at the
# keystroke and never reaches the canvas, with the constructor's own message. The
# map side is a `Layout` — bus id to `(x, y)` — kept beside the records and never
# inside them (docs/SPEC.md §3.5; `src/model/scenario_file.jl`).
#
# WHAT A DRAFT CANNOT DO: be saved while invalid. The file format holds
# `NetworkModel`s only (one validated path, m5-context.md D5), so an unbalanced
# draft is refused by `save!` with the balance named. The status line shows the
# running Σ P so the number to fix is always in view.

"""
    ScenarioEditor

An editable scenario: the record collections of a `NetworkModel` (buses, branches,
machines, loads and — M7 step 8 — inverters), the map
[`Layout`](@ref), and the selection. Build one empty (`ScenarioEditor()`) or from
a model (`ScenarioEditor(net; layout)`); turn it back into a model with
[`build_model`](@ref).
"""
mutable struct ScenarioEditor
    S_base::Float64
    f0::Float64
    name::String
    buses::Vector{Bus}
    branches::Vector{Branch}
    machines::Vector{Machine}
    loads::Vector{Load}
    # M7 step 8. Held in INSERTION order, like the machines; the model sorts both by
    # bus, which is why `effective_slack` walks the buses rather than this vector.
    inverters::Vector{Inverter}
    layout::Layout
    # `(kind, id)` with kind one of :bus, :machine, :load, :branch, :inverter — or nothing.
    selection::Union{Nothing,Tuple{Symbol,Symbol}}
    # M6 step 1 — the declared reference bus, CARRIED so that opening a file and
    # saving it again cannot silently re-default it. `nothing` means "let
    # `NetworkModel` derive it", which is what a draft with no buses yet needs.
    # Selecting one on the map, and drawing it there, is step 5.
    slack::Union{Nothing,Symbol}
end

ScenarioEditor(; S_base::Real = 100.0, f0::Real = 50.0, name::AbstractString = "") =
    ScenarioEditor(Float64(S_base), Float64(f0), String(name),
                   Bus[], Branch[], Machine[], Load[], Inverter[], Layout(), nothing,
                   nothing)

"""
    ScenarioEditor(net::NetworkModel; layout = nothing, name = "")

Open a model for editing. Buses the `layout` does not place (or all of them,
when it is `nothing`) go on a circle, in bus order — deterministic, so a file
saved without positions draws the same way every time it is opened.
"""
function ScenarioEditor(net::NetworkModel; layout = nothing, name::AbstractString = "")
    ed = ScenarioEditor(; S_base = net.S_base, f0 = net.f0, name = name)
    append!(ed.buses, net.buses)
    append!(ed.branches, net.branches)
    append!(ed.machines, net.machines)
    append!(ed.loads, net.loads)
    append!(ed.inverters, net.inverters)
    layout === nothing || merge!(ed.layout, layout)
    ed.slack = net.slack
    _place_missing!(ed)
    return ed
end

# Circle placement for buses without a position: radius 1 (or the span of the
# placed ones, so a new bus lands near the existing picture rather than inside it).
function _place_missing!(ed::ScenarioEditor)
    missing_ids = [b.id for b in ed.buses if !haskey(ed.layout, b.id)]
    isempty(missing_ids) && return ed
    n = length(ed.buses)
    r = 1.0
    if !isempty(ed.layout)
        xs = [xy[1] for xy in values(ed.layout)]; ys = [xy[2] for xy in values(ed.layout)]
        r = max(1.0, 0.6 * max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys)))
    end
    for (k, b) in enumerate(ed.buses)
        b.id in missing_ids || continue
        θ = π / 2 - 2π * (k - 1) / n         # first bus at the top, clockwise
        # Rounded so a file does not carry `6.1e-17` for zero.
        ed.layout[b.id] = (round(r * cos(θ); digits = 6), round(r * sin(θ); digits = 6))
    end
    return ed
end

# ---- lookups -----------------------------------------------------------------

_collection(ed::ScenarioEditor, kind::Symbol) =
    kind === :bus ? ed.buses : kind === :machine ? ed.machines :
    kind === :load ? ed.loads : kind === :branch ? ed.branches :
    kind === :inverter ? ed.inverters :
    throw(ArgumentError("editor: no element kind $kind (bus, machine, load, branch, inverter)."))

_index(ed::ScenarioEditor, kind::Symbol, id::Symbol) =
    findfirst(x -> x.id === id, _collection(ed, kind))

"""
    element(ed, kind, id)

The record `(kind, id)` names, or an `ArgumentError` naming what is missing.
"""
function element(ed::ScenarioEditor, kind::Symbol, id::Symbol)
    k = _index(ed, kind, id)
    k === nothing && throw(ArgumentError("editor: no $kind $id."))
    return _collection(ed, kind)[k]
end

all_ids(ed::ScenarioEditor) = Symbol[x.id for c in (ed.buses, ed.branches, ed.machines, ed.loads,
                                                     ed.inverters)
                                     for x in c]

"""
    fresh_id(ed, prefix) -> Symbol

The lowest-numbered `prefixN` not used by any element of any kind. Ids are
unique across kinds, not just within one, so a bus and a machine can never
share a name the status line would then fail to distinguish.
"""
function fresh_id(ed::ScenarioEditor, prefix::AbstractString)
    used = Set(all_ids(ed))
    k = 1
    while Symbol(prefix, k) in used
        k += 1
    end
    return Symbol(prefix, k)
end

function _assert_fresh(ed::ScenarioEditor, id::Symbol)
    id in all_ids(ed) && throw(ArgumentError("editor: id $id is already in use."))
    return id
end

_assert_bus(ed::ScenarioEditor, bus::Symbol) =
    _index(ed, :bus, bus) === nothing ?
        throw(ArgumentError("editor: no bus $bus.")) : bus

# ---- adding -------------------------------------------------------------------

"""
    add_bus!(ed, x, y; id = fresh_id(ed, "B"), V_base = 400.0) -> id

Place a bus on the map at `(x, y)`.
"""
function add_bus!(ed::ScenarioEditor, x::Real, y::Real;
                  id::Symbol = fresh_id(ed, "B"), V_base::Real = 400.0)
    _assert_fresh(ed, id)
    push!(ed.buses, Bus(id, V_base))
    ed.layout[id] = (Float64(x), Float64(y))
    return id
end

"""
    add_machine!(ed, bus; id = fresh_id(ed, "G"), S_rated = 100, H = 4, D = 2,
                 Xd′ = 0.3, E′ = 1.05, P0 = 0, kwargs...) -> id

Attach a machine to `bus`. The defaults are a plausible classical machine with
no governor, frozen flux and no regulator — every other `Machine` keyword passes
through, so the detailed-tier parameters can be set here too.
"""
function add_machine!(ed::ScenarioEditor, bus::Symbol;
                      id::Symbol = fresh_id(ed, "G"),
                      S_rated::Real = 100.0, H::Real = 4.0, D::Real = 2.0,
                      Xd′::Real = 0.3, E′::Real = 1.05, P0::Real = 0.0,
                      R::Real = Inf, Pmax::Real = P0, Tg::Real = 1.0, kwargs...)
    _assert_fresh(ed, id); _assert_bus(ed, bus)
    push!(ed.machines, Machine(id, bus, S_rated, H, D, Xd′, E′, P0, R, Pmax, Tg; kwargs...))
    return id
end

"""
    add_load!(ed, bus; id = fresh_id(ed, "L"), P0 = 0, Q0 = 0, kwargs...) -> id

Attach a load to `bus`. One load per bus — the model merges nothing, so a second
one is refused here, before the canvas can draw it.
"""
function add_load!(ed::ScenarioEditor, bus::Symbol;
                   id::Symbol = fresh_id(ed, "L"), P0::Real = 0.0, Q0::Real = 0.0,
                   kwargs...)
    _assert_fresh(ed, id); _assert_bus(ed, bus)
    any(l -> l.bus === bus, ed.loads) && throw(ArgumentError(
        "editor: bus $bus already carries a load — loads at one bus are additive, " *
        "so edit that one."))
    push!(ed.loads, Load(id, bus, P0, Q0, values(kwargs)...))
    return id
end

"""
    add_inverter!(ed, bus; id = fresh_id(ed, "I"), mode = :grid_forming,
                  S_rated = 100, P0 = 0, kwargs...) -> id

Attach an inverter to `bus` (M7 step 8). Grid-forming by default — it holds a voltage,
so a draft of inverters alone can still have a reference bus; switch it with
`set_field!(ed, :inverter, id, :mode, :grid_following)`. Every other `Inverter`
keyword passes through. A bus may carry several sources, as the model allows; which
combinations a tier runs is the engine's business (the detailed tier refuses two on
one bus, by name, when it is asked to run them).
"""
function add_inverter!(ed::ScenarioEditor, bus::Symbol;
                       id::Symbol = fresh_id(ed, "I"), mode::Symbol = :grid_forming,
                       S_rated::Real = 100.0, P0::Real = 0.0, kwargs...)
    _assert_fresh(ed, id); _assert_bus(ed, bus)
    push!(ed.inverters, Inverter(id, bus, mode, S_rated, P0; kwargs...))
    return id
end

"""
    add_branch!(ed, from, to; id = fresh_id(ed, "T"), X = 0.25, rating = 500.0) -> id

Connect two buses. A second branch between the same pair is refused: the engine's
graph would silently drop it (see `NetworkModel`), so the editor never shows one.
"""
function add_branch!(ed::ScenarioEditor, from::Symbol, to::Symbol;
                     id::Symbol = fresh_id(ed, "T"), X::Real = 0.25, rating::Real = 500.0)
    _assert_fresh(ed, id); _assert_bus(ed, from); _assert_bus(ed, to)
    any(br -> Set((br.from, br.to)) == Set((from, to)), ed.branches) && throw(ArgumentError(
        "editor: $from and $to are already connected — parallel circuits are not " *
        "representable (merge them into one reactance)."))
    push!(ed.branches, Branch(id, from, to, X, rating))
    return id
end

# ---- moving, removing, renaming --------------------------------------------------

"""
    move_bus!(ed, id, x, y)

Move a bus on the map. Its machines and loads are drawn relative to it, so they
come along; the model does not change at all.
"""
function move_bus!(ed::ScenarioEditor, id::Symbol, x::Real, y::Real)
    _assert_bus(ed, id)
    ed.layout[id] = (Float64(x), Float64(y))
    return ed
end

"""
    remove!(ed, kind, id)

Delete an element. Removing a bus removes everything attached to it — its
machines, inverters, load and branches — because none of them can exist without it.
The selection is cleared if it named anything removed.
"""
function remove!(ed::ScenarioEditor, kind::Symbol, id::Symbol)
    element(ed, kind, id)                  # throws if absent
    if kind === :bus
        filter!(m -> m.bus !== id, ed.machines)
        filter!(i -> i.bus !== id, ed.inverters)
        filter!(l -> l.bus !== id, ed.loads)
        filter!(br -> br.from !== id && br.to !== id, ed.branches)
        delete!(ed.layout, id)
        # M6 step 1 — a declared slack that has just been deleted would make
        # `build_model` throw on a bus the editor no longer shows. Fall back to
        # "let the model derive it", the same thing a fresh draft carries.
        ed.slack === id && (ed.slack = nothing)
    end
    filter!(x -> x.id !== id, _collection(ed, kind))
    sel = ed.selection
    if sel !== nothing && _index(ed, sel[1], sel[2]) === nothing
        ed.selection = nothing
    end
    return ed
end

"""
    rename!(ed, kind, id, new_id)

Rename an element. Renaming a bus rewrites every machine, inverter, load and branch
that refers to it, so the model stays connected.
"""
function rename!(ed::ScenarioEditor, kind::Symbol, id::Symbol, new_id::Symbol)
    new_id === id && return ed
    element(ed, kind, id)
    _assert_fresh(ed, new_id)
    String(new_id) == "" && throw(ArgumentError("editor: an id cannot be empty."))
    if kind === :bus
        ed.layout[new_id] = ed.layout[id]; delete!(ed.layout, id)
        ed.slack === id && (ed.slack = new_id)   # M6 step 1 — follows the rename
        for (k, m) in pairs(ed.machines)
            m.bus === id && (ed.machines[k] = _with(m, :bus, new_id))
        end
        for (k, i) in pairs(ed.inverters)
            i.bus === id && (ed.inverters[k] = _with(i, :bus, new_id))
        end
        for (k, l) in pairs(ed.loads)
            l.bus === id && (ed.loads[k] = _with(l, :bus, new_id))
        end
        for (k, br) in pairs(ed.branches)
            br.from === id && (ed.branches[k] = _with(br, :from, new_id))
            br.to === id && (ed.branches[k] = _with(ed.branches[k], :to, new_id))
        end
    end
    c = _collection(ed, kind)
    k = _index(ed, kind, id)
    c[k] = _with(c[k], :id, new_id)
    ed.selection == (kind, id) && (ed.selection = (kind, new_id))
    return ed
end

# ---- the reference bus ---------------------------------------------------------

"""
    set_slack!(ed, bus) -> ed

Declare `bus` the reference (slack) bus. `nothing` gives the declaration back up
and lets `NetworkModel` derive one — what a fresh draft carries.

The slack is a **dispatch** choice, not a gauge one (m5-context.md D13), which is
why the scenario file refuses to invent it (m6-context.md D8) and why the editor
lets a user say it rather than discovering it after a save.
"""
function set_slack!(ed::ScenarioEditor, bus::Union{Nothing,Symbol})
    bus === nothing && (ed.slack = nothing; return ed)
    _assert_bus(ed, bus)
    ed.slack = bus
    return ed
end

"""
    effective_slack(ed) -> Symbol or nothing

The bus a model built from this draft would use as its reference — the declared
one, or the one `NetworkModel` would derive: the first bus carrying a machine, in
bus order; with no machine, the first bus carrying a **grid-forming** inverter, in
bus order (M7 — never a grid-following one, which follows a voltage and cannot set
one); otherwise the first bus. `nothing` only when the draft has no buses at all.

The derivation is spelled out here rather than obtained from [`build_model`](@ref)
because the map has to draw the reference on a draft the constructor would still
refuse — an unbalanced one, say. That makes it a second copy of a rule, so a test
asserts the two agree on every draft it can build; the map is not allowed to point
at a bus the model would not use.
"""
function effective_slack(ed::ScenarioEditor)
    ed.slack === nothing || return ed.slack
    isempty(ed.buses) && return nothing
    for b in ed.buses
        any(m -> m.bus === b.id, ed.machines) && return b.id
    end
    # BUS order, not `ed.inverters`' insertion order: the model sorts its inverters by
    # bus before it picks, so walking the vector here would point the map at a bus the
    # model does not use whenever inverters were added out of order.
    for b in ed.buses
        any(i -> i.bus === b.id && i.mode === :grid_forming, ed.inverters) && return b.id
    end
    return ed.buses[1].id
end

# ---- editing a field ---------------------------------------------------------------

# Rebuild an immutable record with fields changed, THROUGH ITS CONSTRUCTOR, so the
# constructor's validation runs on the new values. `Machine`'s detailed and
# regulator parameters are keyword-only there, hence the split.
#
# `changes` is a NamedTuple and is applied in ONE rebuild (M7 step 8). An inverter's
# rating guard ties `S_rated`, `P0` and `Q0` together, so lowering the rating and the
# dispatch is valid as a pair and refused as either half alone — a panel that applied
# its boxes one field at a time would refuse it, or worse, keep the half it had done.
#
# The machine case delegates to core's `_machine_with`, which walks every field. The
# hand-listed rebuild it replaced (M6 step 7) would have DROPPED a machine's cost
# and minimum on its next edit: the editor does not show those fields, so nothing
# on screen would have said they were gone.
_with(x, f::Symbol, v) = _with(x, NamedTuple{(f,)}((v,)))
_with(m::Machine, ch::NamedTuple) = _machine_with(m; ch...)
# M7 step 8 — core's field-walking helper, for `_machine_with`'s reason: the panel
# shows one mode's fields, and the other mode's must survive an edit or a mode switch.
_with(i::Inverter, ch::NamedTuple) = _inverter_with(i; ch...)
# `Branch.R` is keyword-only on the constructor (M6 step 1), so the generic
# splat-every-field rebuild below cannot build one: `fieldnames` would hand `R` to
# a five-positional method. Its own method, for the same reason `Machine` has one.
function _with(b::Branch, ch::NamedTuple)
    g(n) = haskey(ch, n) ? ch[n] : getfield(b, n)
    return Branch(g(:id), g(:from), g(:to), g(:X), g(:rating); R = g(:R))
end
function _with(x::Union{Bus,Load}, ch::NamedTuple)
    T = typeof(x)
    return T((haskey(ch, n) ? ch[n] : getfield(x, n) for n in fieldnames(T))...)
end

"""
    editable_fields(kind) -> Tuple of Symbols
    editable_fields(element) -> Tuple of Symbols

The numeric fields the property panel offers for each kind: for a machine, the
classical and governor set plus the three the steady-state solve reads (`V_set`,
`Q_min`, `Q_max`); for a branch, its reactance, rating and series resistance.

The **detailed-tier** parameters (`Xd`, `Xq`, `Xq′`, `Td0′`, `Tq0′`, `Ra`) and the
**regulator's** (`K_A`, `T_E`, `Efd_min`, `Efd_max`) are still carried by the file
and by [`set_field!`](@ref) and not by the panel — twenty-two text boxes do not fit
beside a map, and a tier with no real-time window of its own (m5-context.md D2) is
not what a map is for. The three that were added are the ones a solve on this map
actually consults, and `R` is the one a lossy flow does.

An **inverter's** fields depend on its mode (M7 step 8), so the inverter is asked by
ELEMENT, not by kind: a grid-forming one shows its droop (`V_set`, `X_c`, `K_p`, `τ_p`,
`K_q`, `τ_q`), a grid-following one its schedule `Q0` and its PLL (`K_pll_p`,
`K_pll_i`, `τ_pll`) — each the set the other mode leaves unread (`Inverter`'s
docstring). The hidden half is carried, not dropped: the rebuild walks every field.
`Q0` is hidden for grid-forming because nothing reads it there (D11), though the
rating guard still checks it, and its message names it.
"""
editable_fields(kind::Symbol) =
    kind === :bus ? (:V_base,) :
    kind === :machine ? (:S_rated, :H, :D, :Xd′, :E′, :P0, :R, :Pmax, :Tg,
                         :V_set, :Q_min, :Q_max) :
    kind === :load ? (:P0, :Q0) :
    kind === :branch ? (:X, :rating, :R) :
    kind === :inverter ? throw(ArgumentError(
        "editor: an inverter's fields depend on its mode — ask with the element.")) :
    throw(ArgumentError("editor: no element kind $kind."))
editable_fields(::Bus) = editable_fields(:bus)
editable_fields(::Machine) = editable_fields(:machine)
editable_fields(::Load) = editable_fields(:load)
editable_fields(::Branch) = editable_fields(:branch)
editable_fields(i::Inverter) =
    i.mode === :grid_forming ? (:S_rated, :P0, :V_set, :X_c, :K_p, :τ_p, :K_q, :τ_q) :
                               (:S_rated, :P0, :Q0, :K_pll_p, :K_pll_i, :τ_pll)

"""
    set_field!(ed, kind, id, field, value)

Change one field of an element. `:id` goes through [`rename!`](@ref), and
`:bus`/`:from`/`:to` are refused — re-attaching is a delete and an add, so the
map cannot show a machine at one bus while the model has it at another. An
inverter's `:mode` is set here too (`:grid_forming` / `:grid_following`).
"""
function set_field!(ed::ScenarioEditor, kind::Symbol, id::Symbol, field::Symbol, value)
    field === :id && return rename!(ed, kind, id, Symbol(value))
    return set_fields!(ed, kind, id, NamedTuple{(field,)}((value,)))
end

"""
    set_fields!(ed, kind, id, changes::NamedTuple)

Change several fields of one element in ONE rebuild through its constructor (M7
step 8) — what the panel's **apply** does. Either every change lands or none does:
the constructor sees the new record whole, so a change that is valid only as a whole
(an inverter's rating lowered together with its dispatch) is accepted, and a refused
one leaves the old record exactly as it was.
"""
function set_fields!(ed::ScenarioEditor, kind::Symbol, id::Symbol, changes::NamedTuple)
    for f in keys(changes)
        f === :id && throw(ArgumentError(
            "editor: `id` is changed by `rename!`, not with other fields."))
        f in (:bus, :from, :to) && throw(ArgumentError(
            "editor: `$f` is not editable in place — delete the element and add it " *
            "where it belongs."))
    end
    c = _collection(ed, kind)
    k = _index(ed, kind, id)
    k === nothing && throw(ArgumentError("editor: no $kind $id."))
    for f in keys(changes)
        f in fieldnames(typeof(c[k])) || throw(ArgumentError(
            "editor: a $kind has no field `$f`."))
    end
    c[k] = _with(c[k], changes)
    return ed
end

# ---- the model ----------------------------------------------------------------------

"""
    build_model(ed) -> NetworkModel

The scenario as a model, through the ordinary constructor — so what the canvas
shows and what the engines run are one thing, or the constructor says why not.
"""
build_model(ed::ScenarioEditor) =
    NetworkModel(ed.S_base, ed.f0, copy(ed.buses), copy(ed.branches),
                 copy(ed.machines), copy(ed.loads); slack = ed.slack,
                 inverters = copy(ed.inverters))

"""
    power_balance(ed) -> Float64

Σ machines.P0 + Σ inverters.P0 − Σ loads.P0, in MW — the number the model's
balance guard checks, shown live so an unbalanced draft says by how much. An
inverter injects with a machine's sign (M7).
"""
power_balance(ed::ScenarioEditor) =
    sum(m.P0 for m in ed.machines; init = 0.0) +
    sum(i.P0 for i in ed.inverters; init = 0.0) - sum(l.P0 for l in ed.loads; init = 0.0)

"""
    validation(ed) -> (; ok, message)

Whether [`build_model`](@ref) succeeds, and either a one-line summary or the
constructor's own message.
"""
function validation(ed::ScenarioEditor)
    try
        net = build_model(ed)
        return (; ok = true,
                  message = @sprintf("valid — %d buses, %d lines, %d machines, %d loads, %d inverters; Σ P = %+.1f MW",
                                     length(net.buses), length(net.branches),
                                     length(net.machines), length(net.loads),
                                     length(net.inverters), power_balance(ed)))
    catch err
        err isa ArgumentError || rethrow()
        return (; ok = false, message = "invalid — " * err.msg)
    end
end

"""
    save!(ed, path) -> path

Write the scenario, layout included, through `write_scenario`. A draft the model
constructor refuses cannot be written (file header), so the error is the
constructor's.
"""
save!(ed::ScenarioEditor, path::AbstractString) =
    write_scenario(path, build_model(ed); layout = ed.layout, name = ed.name)

"""
    load!(ed, path) -> ed

Replace the editor's contents with a scenario file's. Buses the file does not
place go on the circle.
"""
function load!(ed::ScenarioEditor, path::AbstractString)
    # Read whole BEFORE anything is overwritten, so a refused open (a file the reader
    # or the model constructor refuses) leaves the editor as it was.
    sc = read_scenario(path)
    ed.S_base = sc.net.S_base; ed.f0 = sc.net.f0; ed.name = sc.name
    empty!(ed.buses); append!(ed.buses, sc.net.buses)
    empty!(ed.branches); append!(ed.branches, sc.net.branches)
    empty!(ed.machines); append!(ed.machines, sc.net.machines)
    empty!(ed.loads); append!(ed.loads, sc.net.loads)
    empty!(ed.inverters); append!(ed.inverters, sc.net.inverters)
    empty!(ed.layout); sc.layout === nothing || merge!(ed.layout, sc.layout)
    ed.slack = sc.net.slack        # M6 step 1 — carried, so save-after-open keeps it
    ed.selection = nothing
    _place_missing!(ed)
    return ed
end
