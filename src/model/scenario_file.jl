# A `NetworkModel` on disk, and the map positions that go with it.
#
# The scenario editor (`ui/src/editor_window.jl`) needs two things a session can
# put down and pick up again: the model, and where each bus sits on the map. They
# are written into ONE file and kept as TWO things — the model is simulation state
# and the positions are render state, and docs/SPEC.md §3.5 says never to make one
# object of the two. So `read_scenario` hands back a `NetworkModel` and a separate
# `Layout`, and a `Bus` still has no coordinate: the physics cannot read a position
# it was never given, and a file with no `[layout]` table is still a valid model.
#
# TOML, not a custom format and not JSON: it is a Julia stdlib (no dependency
# added), it is readable in a diff, and its float grammar has `inf`/`-inf`, which
# the machine record needs — `R = Inf` is "no governor", `Td0′ = Inf` is frozen
# flux, `Efd_max = Inf` is an unlimited exciter. JSON has no spelling for any of
# those, and a sentinel would put a magic number where the type has a meaning.
#
# The writer records EVERY machine field, defaults included, so a file does not
# change meaning when a default does. The reader goes through the same
# constructors everything else does, so a file cannot build a model the
# constructors would refuse (m5-context.md D5 — one validated path).

using TOML: TOML

"""
    Layout

Map coordinates per bus, `bus id => (x, y)`. Render state, kept out of `Bus` on
purpose (file header). Units are whatever the map uses — a plain canvas or the
extents of a background image — and nothing in the core reads them.
"""
const Layout = Dict{Symbol,Tuple{Float64,Float64}}

# Every machine field the file carries, in the order they are written. Named once
# so the writer and the reader cannot disagree about the list.
const _MACHINE_FIELDS = (:S_rated, :H, :D, :Xd′, :E′, :P0, :R, :Pmax, :Tg,
                         :Xd, :Xq, :Xq′, :Td0′, :Tq0′, :Ra,
                         :K_A, :T_E, :Efd_min, :Efd_max,
                         :V_set, :Q_min, :Q_max)

# The prime (`′`) is not a bare-key character in TOML: a file would have to spell
# `"Xd′" = 0.3` with quotes, and the first hand-written file did not (it was the
# first thing the reader's test tripped on). So on disk the prime is `_p`:
# `Xd_p`, `E_p`, `Xq_p`, `Td0_p`, `Tq0_p`. `_file_key` is the only place the
# spelling is decided, and the reader maps back through the same table.
_file_key(f::Symbol) = replace(String(f), "′" => "_p")
const _FILE_KEYS = Dict{Symbol,String}(f => _file_key(f) for f in _MACHINE_FIELDS)

# The order keys are written in. `TOML.print` sorts keys through `by`, at every
# level, so one rank table covers the top level and each record.
const _KEY_RANK = Dict{String,Int}(
    "name" => 1, "S_base" => 2, "f0" => 3, "slack" => 4, "layout" => 5,
    "buses" => 6, "branches" => 7, "machines" => 8, "loads" => 9,
    "id" => 11, "bus" => 12, "from" => 13, "to" => 14, "V_base" => 15,
    "X" => 16, "rating" => 17, "Q0" => 30, "a_z" => 31, "a_i" => 32, "a_p" => 33)
# `slack` is a TOP-LEVEL key with its own rank, not a bus or machine record field:
# it is a field of `NetworkModel`, so it does not ride along with either
# (`m6-context.md` D8). `Branch.R` needs no rank of its own — the machine record's
# `R` (a governor droop) already claims the string, and the two share the ordering
# harmlessly because they never appear in the same table.
for (i, f) in enumerate(_MACHINE_FIELDS)
    _KEY_RANK[_file_key(f)] = 40 + i
end
# Ties (every bus in `[layout]`, say) fall back to the name, so a file diffs
# stably rather than in `Dict` order.
_key_rank(k) = (get(_KEY_RANK, String(k), 1000), String(k))

"""
    write_scenario(path, net::NetworkModel; layout = nothing, name = "") -> path

Write `net` to a TOML file at `path`, with the optional map `layout` (see
[`Layout`](@ref)) in its own `[layout]` table and an optional human `name`.
Every key of `layout` must be a bus of `net`; a bus without a position is fine
(the editor gives it one), a position without a bus is an error.
"""
function write_scenario(path::AbstractString, net::NetworkModel;
                        layout::Union{Nothing,AbstractDict} = nothing,
                        name::AbstractString = "")
    doc = Dict{String,Any}()
    isempty(name) || (doc["name"] = String(name))
    doc["S_base"] = net.S_base
    doc["f0"] = net.f0
    doc["slack"] = String(net.slack)
    doc["buses"] = [Dict{String,Any}("id" => String(b.id), "V_base" => b.V_base)
                    for b in net.buses]
    doc["branches"] = [Dict{String,Any}("id" => String(br.id), "from" => String(br.from),
                                        "to" => String(br.to), "X" => br.X,
                                        "rating" => br.rating, "R" => br.R)
                       for br in net.branches]
    doc["machines"] = [begin
                           d = Dict{String,Any}("id" => String(m.id), "bus" => String(m.bus))
                           for f in _MACHINE_FIELDS
                               d[_FILE_KEYS[f]] = getfield(m, f)
                           end
                           d
                       end for m in net.machines]
    doc["loads"] = [Dict{String,Any}("id" => String(l.id), "bus" => String(l.bus),
                                     "P0" => l.P0, "Q0" => l.Q0,
                                     "a_z" => l.a_z, "a_i" => l.a_i, "a_p" => l.a_p)
                    for l in net.loads]
    if layout !== nothing
        tbl = Dict{String,Any}()
        for (id, xy) in layout
            haskey(net.bus_index, Symbol(id)) || throw(ArgumentError(
                "write_scenario: layout names bus $id, which is not in the model."))
            tbl[String(id)] = [Float64(xy[1]), Float64(xy[2])]
        end
        doc["layout"] = tbl
    end
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        TOML.print(io, doc; sorted = true, by = _key_rank)
    end
    return path
end

# One record's field, with the file's own line named when it is missing or of the
# wrong shape — a TOML file is edited by hand, and "KeyError: S_rated" is not a
# message that says which of forty machines lacks it.
function _field(rec::AbstractDict, key::AbstractString, ::Type{T}, what::AbstractString;
                default = nothing) where {T}
    if !haskey(rec, key)
        default === nothing && throw(ArgumentError(
            "read_scenario: $what has no `$key`."))
        return default
    end
    v = rec[key]
    if T === Float64
        v isa Real || throw(ArgumentError(
            "read_scenario: $what: `$key` must be a number, got $(repr(v))."))
        return Float64(v)
    end
    v isa T || throw(ArgumentError(
        "read_scenario: $what: `$key` must be a $T, got $(repr(v))."))
    return v
end

"""
    read_scenario(path) -> (; net, layout, name)

Read a file written by [`write_scenario`](@ref) (or by hand in the same shape).
`net` is a `NetworkModel` built through the ordinary constructors, so an invalid
file fails exactly where an invalid model does. `layout` is a [`Layout`](@ref), or
`nothing` when the file has no `[layout]` table; `name` is `""` when absent.

Machine fields beyond the classical eight are optional and default the way the
`Machine` constructor defaults them (no governor, frozen flux, no regulator, a
1.0 pu voltage schedule and no reactive limits), so a hand-written file need only
say what it means. `[[branches]].R` and the top-level `slack` default the same way
(a lossless line; the bus of the first machine) — `m6-context.md` D8. Primed names are spelled with
`_p` in the file (`Xd_p`, `E_p`, …), because TOML has no prime in a bare key.
"""
function read_scenario(path::AbstractString)
    isfile(path) || throw(ArgumentError("read_scenario: no file at $path."))
    doc = TOML.parsefile(path)
    name = String(get(doc, "name", ""))
    S_base = _field(doc, "S_base", Float64, "the file")
    f0 = _field(doc, "f0", Float64, "the file")
    # M6 step 1 — read-side default, and it is DELIBERATELY still a default at this
    # step. `m6-context.md` D8 decides that a file with no slack must eventually be
    # REJECTED, because the slack is the one new field whose absence has no physical
    # meaning; that rejection, its message and its round-trip test are step 5's box.
    # Defaulting here in the meantime is what keeps a pre-M6 file readable while the
    # milestone is mid-flight, and it is why the writer above already emits the key:
    # nothing written after this step leans on the default.
    slack_str = _field(doc, "slack", String, "the file"; default = "")
    slack = isempty(slack_str) ? nothing : Symbol(slack_str)

    buses = Bus[]
    for (i, rec) in enumerate(get(doc, "buses", Any[]))
        what = "bus #$i"
        id = Symbol(_field(rec, "id", String, what))
        push!(buses, Bus(id, _field(rec, "V_base", Float64, "bus $id")))
    end
    branches = Branch[]
    for (i, rec) in enumerate(get(doc, "branches", Any[]))
        id = Symbol(_field(rec, "id", String, "branch #$i"))
        w = "branch $id"
        push!(branches, Branch(id, Symbol(_field(rec, "from", String, w)),
                               Symbol(_field(rec, "to", String, w)),
                               _field(rec, "X", Float64, w),
                               _field(rec, "rating", Float64, w);
                               R = _field(rec, "R", Float64, w; default = 0.0)))
    end
    machines = Machine[]
    for (i, rec) in enumerate(get(doc, "machines", Any[]))
        id = Symbol(_field(rec, "id", String, "machine #$i"))
        w = "machine $id"
        bus = Symbol(_field(rec, "bus", String, w))
        req(f) = _field(rec, _FILE_KEYS[f], Float64, w)
        opt(f, d) = _field(rec, _FILE_KEYS[f], Float64, w; default = d)
        Xd′ = req(:Xd′); P0 = req(:P0)
        push!(machines, Machine(id, bus, req(:S_rated), req(:H), req(:D), Xd′,
                                req(:E′), P0,
                                opt(:R, Inf), opt(:Pmax, P0), opt(:Tg, 1.0);
                                Xd = opt(:Xd, Xd′), Xq = opt(:Xq, Xd′),
                                Xq′ = opt(:Xq′, Xd′),
                                Td0′ = opt(:Td0′, Inf), Tq0′ = opt(:Tq0′, Inf),
                                Ra = opt(:Ra, 0.0),
                                K_A = opt(:K_A, 0.0), T_E = opt(:T_E, Inf),
                                Efd_min = opt(:Efd_min, -Inf),
                                Efd_max = opt(:Efd_max, Inf),
                                V_set = opt(:V_set, 1.0),
                                Q_min = opt(:Q_min, -Inf),
                                Q_max = opt(:Q_max, Inf)))
    end
    loads = Load[]
    for (i, rec) in enumerate(get(doc, "loads", Any[]))
        id = Symbol(_field(rec, "id", String, "load #$i"))
        w = "load $id"
        push!(loads, Load(id, Symbol(_field(rec, "bus", String, w)),
                          _field(rec, "P0", Float64, w), _field(rec, "Q0", Float64, w),
                          _field(rec, "a_z", Float64, w; default = 1.0),
                          _field(rec, "a_i", Float64, w; default = 0.0),
                          _field(rec, "a_p", Float64, w; default = 0.0)))
    end
    net = NetworkModel(S_base, f0, buses, branches, machines, loads; slack = slack)

    layout = nothing
    if haskey(doc, "layout")
        tbl = doc["layout"]
        tbl isa AbstractDict || throw(ArgumentError(
            "read_scenario: `layout` must be a table of `bus = [x, y]`."))
        layout = Layout()
        for (k, v) in tbl
            id = Symbol(k)
            haskey(net.bus_index, id) || throw(ArgumentError(
                "read_scenario: layout names bus $id, which is not in the model."))
            (v isa AbstractVector && length(v) == 2 && all(x -> x isa Real, v)) ||
                throw(ArgumentError(
                    "read_scenario: layout entry for $id must be `[x, y]`, got $(repr(v))."))
            layout[id] = (Float64(v[1]), Float64(v[2]))
        end
    end
    return (; net, layout, name)
end
