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
# `Load`): editing a field REBUILDS the record through its constructor, so a value
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

An editable scenario: the four record collections of a `NetworkModel`, the map
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
    layout::Layout
    # `(kind, id)` with kind one of :bus, :machine, :load, :branch — or nothing.
    selection::Union{Nothing,Tuple{Symbol,Symbol}}
end

ScenarioEditor(; S_base::Real = 100.0, f0::Real = 50.0, name::AbstractString = "") =
    ScenarioEditor(Float64(S_base), Float64(f0), String(name),
                   Bus[], Branch[], Machine[], Load[], Layout(), nothing)

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
    layout === nothing || merge!(ed.layout, layout)
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
    throw(ArgumentError("editor: no element kind $kind (bus, machine, load, branch)."))

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

all_ids(ed::ScenarioEditor) = Symbol[x.id for c in (ed.buses, ed.branches, ed.machines, ed.loads)
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
machines, its load and its branches — because none of them can exist without it.
The selection is cleared if it named anything removed.
"""
function remove!(ed::ScenarioEditor, kind::Symbol, id::Symbol)
    element(ed, kind, id)                  # throws if absent
    if kind === :bus
        filter!(m -> m.bus !== id, ed.machines)
        filter!(l -> l.bus !== id, ed.loads)
        filter!(br -> br.from !== id && br.to !== id, ed.branches)
        delete!(ed.layout, id)
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

Rename an element. Renaming a bus rewrites every machine, load and branch that
refers to it, so the model stays connected.
"""
function rename!(ed::ScenarioEditor, kind::Symbol, id::Symbol, new_id::Symbol)
    new_id === id && return ed
    element(ed, kind, id)
    _assert_fresh(ed, new_id)
    String(new_id) == "" && throw(ArgumentError("editor: an id cannot be empty."))
    if kind === :bus
        ed.layout[new_id] = ed.layout[id]; delete!(ed.layout, id)
        for (k, m) in pairs(ed.machines)
            m.bus === id && (ed.machines[k] = _with(m, :bus, new_id))
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

# ---- editing a field ---------------------------------------------------------------

# Rebuild an immutable record with one field changed, THROUGH ITS CONSTRUCTOR, so
# the constructor's validation runs on the new value. `Machine`'s detailed and
# regulator parameters are keyword-only there, hence the split.
function _with(m::Machine, f::Symbol, v)
    g(n) = n === f ? v : getfield(m, n)
    return Machine(g(:id), g(:bus), g(:S_rated), g(:H), g(:D), g(:Xd′), g(:E′), g(:P0),
                   g(:R), g(:Pmax), g(:Tg);
                   Xd = g(:Xd), Xq = g(:Xq), Xq′ = g(:Xq′), Td0′ = g(:Td0′),
                   Tq0′ = g(:Tq0′), Ra = g(:Ra), K_A = g(:K_A), T_E = g(:T_E),
                   Efd_min = g(:Efd_min), Efd_max = g(:Efd_max))
end
function _with(x::Union{Bus,Branch,Load}, f::Symbol, v)
    T = typeof(x)
    return T((n === f ? v : getfield(x, n) for n in fieldnames(T))...)
end

"""
    editable_fields(kind) -> Tuple of Symbols

The numeric fields the property panel offers for each kind. For a machine that is
the classical and governor set; the detailed-tier and regulator parameters are
carried by the file and by [`set_field!`](@ref), not by the panel — nineteen
text boxes do not fit beside a map.
"""
editable_fields(kind::Symbol) =
    kind === :bus ? (:V_base,) :
    kind === :machine ? (:S_rated, :H, :D, :Xd′, :E′, :P0, :R, :Pmax, :Tg) :
    kind === :load ? (:P0, :Q0) :
    kind === :branch ? (:X, :rating) :
    throw(ArgumentError("editor: no element kind $kind."))

"""
    set_field!(ed, kind, id, field, value)

Change one numeric field of an element. `:id` goes through [`rename!`](@ref), and
`:bus`/`:from`/`:to` are refused — re-attaching is a delete and an add, so the
map cannot show a machine at one bus while the model has it at another.
"""
function set_field!(ed::ScenarioEditor, kind::Symbol, id::Symbol, field::Symbol, value)
    field === :id && return rename!(ed, kind, id, Symbol(value))
    field in (:bus, :from, :to) && throw(ArgumentError(
        "editor: `$field` is not editable in place — delete the element and add it " *
        "where it belongs."))
    c = _collection(ed, kind)
    k = _index(ed, kind, id)
    k === nothing && throw(ArgumentError("editor: no $kind $id."))
    field in fieldnames(typeof(c[k])) || throw(ArgumentError(
        "editor: a $kind has no field `$field`."))
    c[k] = _with(c[k], field, value)
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
                 copy(ed.machines), copy(ed.loads))

"""
    power_balance(ed) -> Float64

Σ machines.P0 − Σ loads.P0, in MW — the number the model's balance guard checks,
shown live so an unbalanced draft says by how much.
"""
power_balance(ed::ScenarioEditor) =
    sum(m.P0 for m in ed.machines; init = 0.0) - sum(l.P0 for l in ed.loads; init = 0.0)

"""
    validation(ed) -> (; ok, message)

Whether [`build_model`](@ref) succeeds, and either a one-line summary or the
constructor's own message.
"""
function validation(ed::ScenarioEditor)
    try
        net = build_model(ed)
        return (; ok = true,
                  message = @sprintf("valid — %d buses, %d lines, %d machines, %d loads; Σ P = %+.1f MW",
                                     length(net.buses), length(net.branches),
                                     length(net.machines), length(net.loads),
                                     power_balance(ed)))
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
    sc = read_scenario(path)
    ed.S_base = sc.net.S_base; ed.f0 = sc.net.f0; ed.name = sc.name
    empty!(ed.buses); append!(ed.buses, sc.net.buses)
    empty!(ed.branches); append!(ed.branches, sc.net.branches)
    empty!(ed.machines); append!(ed.machines, sc.net.machines)
    empty!(ed.loads); append!(ed.loads, sc.net.loads)
    empty!(ed.layout); sc.layout === nothing || merge!(ed.layout, sc.layout)
    ed.selection = nothing
    _place_missing!(ed)
    return ed
end
