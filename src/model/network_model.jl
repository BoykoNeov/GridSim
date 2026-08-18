# Canonical network domain model for Milestone 2 (docs/plans/m2-plan.md §2).
#
# `SystemModel` (model/system_model.jl) cannot express M2: it has no buses, no
# branches, no transient reactance and no internal voltage. So M2 gets its own
# canonical type — and to keep SPEC §3.2 ("one canonical model; reduced models are
# compiled views") true rather than aspirational, the aggregate center-of-inertia
# model is *derived* from this one (`coi_model`, M2 step 6), never hand-maintained
# beside it.
#
# THE TIER, STATED (m2-plan.md "Fidelity tier"):
#   Reduced classical, network-swing form. Each machine is a constant-magnitude
#   voltage source `E′` **at its bus**, whose angle is the rotor angle; its state
#   is (δ, ω). Network coupling is algebraic in closed form — no bus voltage is
#   carried as an unknown — so the whole system stays a pure ODE. The moment bus
#   voltages become algebraic variables it is a DAE, which is deliberately the
#   *next* tier. (The plan says "E′ behind X′d"; point 2 below is why that exact
#   phrasing is not achievable here and what M2a does instead.)
#
#   Two consequences are baked into the types below and are worth saying out loud,
#   because each is an approximation with a boundary rather than an oversight:
#
#   1. **Every bus carries exactly one machine.** A bus without a machine is an
#      algebraic node (no differential state), i.e. the DAE tier. A bus with two
#      machines is not representable without a terminal-voltage unknown either.
#      The constructor rejects both, so the tier boundary is a loud error rather
#      than a quietly wrong answer. Load buses are the natural M2b.
#   2. **M2a puts `E′` at the bus and does NOT fold `X′d` into the coupling**:
#      `K_ij = E′ᵢ·E′ⱼ / X_ij`, the standard network-swing form. This is a
#      *correction* to the M2 plan's phrasing ("constant voltage E′ behind X′d"),
#      recorded as a finding in m2-context.md rather than patched in passing:
#
#        Folding the end reactances in — `E′ᵢE′ⱼ/(X′dᵢ + X_ij + X′dⱼ)` — is exact
#        only when a machine sits on exactly ONE branch. A machine with two lines
#        would have its single internal reactance counted once per incident
#        branch: one rotor, two internal reactances, which is not any network.
#        Doing it exactly means eliminating the terminal buses (Kron reduction) so
#        that a machine's `X′d` is shared across all its ties — and that reduction
#        is precisely what builds an admittance matrix (D3 forbids it here) and is
#        precisely M2b. Under D2 (pure ODE) + D3 (no admittance matrix) there is
#        no exact meshed "E′ behind X′d", so M2a takes the model that IS exact on
#        every topology instead of one that is exact only on a radial pair.
#
#      `Machine.Xd′` is therefore **carried but unused by M2a's dynamics** — it is
#      real machine data, it maps to PowerSystems, and M2b's terminal-bus
#      elimination is what consumes it. Do not fold it into `_coupling`.
#
# LOADS: there is no load type in M2a. A load is a machine with negative `P0`
# (this is how the three-machine ring's −110 MW bus works). Constant-impedance
# loads and the reduction they require are M2b.
#
# GOVERNORS: there are none. `Machine` deliberately carries no droop `R` and no
# `Pmax`, because the classical tier holds mechanical power constant. The COI view
# compiled from this model (step 6) therefore compiles to a *governor-free*
# `SystemModel` (`R = Inf`, `Pmax = P0`) — which is what makes the cross-fidelity
# comparison honest: the two models then differ by inter-machine dynamics alone,
# not by one of them having primary response the other lacks.
#
# Conventions (docs/SPEC.md §6, and standard utility practice):
#   - Powers and voltages at the data boundary are ENGINEERING units (MVA, MW, kV).
#   - Machine impedances/inertia/damping are per-unit on the MACHINE's own base
#     (`S_rated`); branch reactances are per-unit on the SYSTEM base (`S_base`).
#     That split is not sloppiness — it is how machine and network data are
#     actually published — and it is exactly where a per-unit conversion goes
#     missing. `machine_arrays` / `branch_arrays` below are the single place the
#     conversion to system base happens; nothing else should do it by hand.
#   - Concrete-typed fields only (SPEC §4 "Type stability").
#
# STRUCT-OF-ARRAYS (SPEC §4): the canonical model is an array-of-structs, because
# that is what is readable and what maps onto PowerSystems concepts. The
# contiguous numeric arrays the engine actually integrates against are *derived*
# (`machine_arrays`, `branch_arrays`) rather than stored — so the habit is
# established without creating a second copy of the model to keep in sync.
#
# POWERSYSTEMS MAPPING (D5 — PowerSystems.jl is roadmap step 4, not now): the
# field semantics are chosen to map, so `from_powersystems(sys)` can later be a
# sibling constructor of `NetworkModel` rather than a rewrite:
#   Bus     ↔ PSY.ACBus            (`V_base` ↔ `base_voltage`, kV)
#   Branch  ↔ PSY.Line             (`X` pu on system base, `rating` MVA)
#   Machine ↔ PSY.DynamicGenerator{BaseMachine, ...}
#             (`S_rated` ↔ `base_power`, `Xd′` ↔ `Xd_p`, `E′` ↔ `eq_p`,
#              `H`/`D` ↔ the `SingleMass` shaft, `P0` ↔ the static injector's
#              `active_power` × base)

"""
    Bus

One electrical bus (node). Metadata only — the classical tier carries no bus
voltage as an unknown (see the tier note at the top of this file).

  - `id`     — unique name.
  - `V_base` — kV, nominal line-to-line voltage. Carried for the UI boundary and
               for a future PowerSystems adapter; the per-unit dynamics never
               read it.
"""
struct Bus
    id::Symbol
    V_base::Float64   # kV — nominal voltage

    function Bus(id::Symbol, V_base::Real)
        V_base > 0 || throw(ArgumentError(
            "Bus $id: V_base ($V_base) must be > 0 kV."))
        return new(id, Float64(V_base))
    end
end

"""
    Machine

One synchronous machine in the reduced classical (network-swing) representation:
a constant-magnitude voltage `E′` at its bus whose angle is the rotor angle, with
state `(δ, ω)`.

  - `id`      — unique name.
  - `bus`     — id of the bus it sits on (exactly one machine per bus; see the
                tier note above).
  - `S_rated` — MVA, the machine's own base.
  - `H`       — s, inertia constant **on the machine's own base**.
  - `D`       — pu/pu, damping **on the machine's own base**.
  - `Xd′`     — pu **on the machine's own base**, transient reactance. **Carried,
                not used by M2a's dynamics** — see point 2 of the tier note at the
                top of this file for why the coupling cannot fold it in, and M2b
                (terminal-bus elimination) for what will consume it.
  - `E′`      — pu, internal voltage magnitude (on the bus's voltage base).
  - `P0`      — MW, mechanical power. **Negative means the machine absorbs**,
                which is how M2a represents a load.

Governor droop and `Pmax` are deliberately absent — the classical tier holds
mechanical power constant. See the GOVERNORS note at the top of this file.
"""
struct Machine
    id::Symbol
    bus::Symbol
    S_rated::Float64   # MVA — the machine's own base
    H::Float64         # s     — inertia constant, on the machine's own base
    D::Float64         # pu/pu — damping, on the machine's own base
    Xd′::Float64       # pu    — transient reactance, on the machine's own base
    E′::Float64        # pu    — internal voltage magnitude
    P0::Float64        # MW    — mechanical power (negative = load)

    # Reject a machine that is wrong on its face rather than letting it poison a
    # solve — the spirit of `GeneratingUnit`'s headroom guard. `H > 0` is strict
    # because it sits in a denominator (the swing equation divides by 2H), so a
    # zero is not a degenerate-but-valid machine, it is a division by zero. A
    # zero-inertia
    # converter is a real thing and M1's aggregate model supports it — but as a
    # *vertex* in a swing network it has no differential state, which is the
    # grid-forming/following tier, not this one.
    function Machine(id::Symbol, bus::Symbol, S_rated::Real, H::Real, D::Real,
                     Xd′::Real, E′::Real, P0::Real)
        S_rated > 0 || throw(ArgumentError(
            "Machine $id: S_rated ($S_rated) must be > 0 MVA."))
        H > 0 || throw(ArgumentError(
            "Machine $id: H ($H) must be > 0 s — the swing equation divides by 2H. " *
            "A zero-inertia unit is not a classical-tier vertex."))
        D ≥ 0 || throw(ArgumentError(
            "Machine $id: D ($D) must be ≥ 0 — negative damping is anti-physical here."))
        Xd′ > 0 || throw(ArgumentError(
            "Machine $id: Xd′ ($Xd′) must be > 0 pu. (M2a's coupling does not read it — " *
            "it is validated anyway so the data is sound when M2b's network reduction does.)"))
        E′ > 0 || throw(ArgumentError(
            "Machine $id: E′ ($E′) must be > 0 pu."))
        return new(id, bus, Float64(S_rated), Float64(H), Float64(D),
                   Float64(Xd′), Float64(E′), Float64(P0))
    end
end

"""
    Branch

One transmission branch (line or transformer), modelled as a pure series
reactance — the classical tier neglects resistance and shunt charging, which is
what makes the network lossless and the power balance `Σ P0 = 0` exact.

  - `id`     — unique name.
  - `from`, `to` — bus ids (undirected; the sign convention lives in the engine).
  - `X`      — pu **on the system base**, series reactance.
  - `rating` — MVA, thermal rating. Carried for the UI boundary; the dynamics do
               not read it (there is no overload protection until M2b).
"""
struct Branch
    id::Symbol
    from::Symbol
    to::Symbol
    X::Float64        # pu on the SYSTEM base — series reactance
    rating::Float64   # MVA — thermal rating (metadata for now)

    function Branch(id::Symbol, from::Symbol, to::Symbol, X::Real, rating::Real)
        from === to && throw(ArgumentError(
            "Branch $id: from and to are both $from — a self-loop is not a branch."))
        X > 0 || throw(ArgumentError(
            "Branch $id: X ($X) must be > 0 pu — it is the coupling denominator."))
        rating > 0 || throw(ArgumentError(
            "Branch $id: rating ($rating) must be > 0 MVA."))
        return new(id, from, to, Float64(X), Float64(rating))
    end
end

"""
    NetworkModel(S_base, f0, buses, branches, machines)

The canonical M2 network: buses, the branches between them, and the machines on
them, plus the system-wide bases.

  - `S_base` — MVA, system power base.
  - `f0`     — Hz, nominal frequency.
  - `buses`, `branches`, `machines` — topology and metadata.
  - `bus_index` — bus id → **vertex index**, built at construction.

**Machines are stored in bus order**: `machines[v]` is the machine on `buses[v]`.
The constructor reorders the machines it is given to enforce this, so a single
index `v` addresses the vertex, its bus and its machine everywhere — which is the
ordering the network the engine compiles will use. Do not assume the order you
passed in survives; look machines up through `bus_index` or `machine_at`.

The constructor rejects models that are wrong on their face:

  - duplicate bus / branch / machine ids;
  - a machine or branch referring to a bus that does not exist;
  - a second branch between a pair of buses already joined (parallel circuits —
    see the guard's own comment for why rejecting beats silently dropping one);
  - a bus with no machine, or with more than one (the tier boundary — see the
    file header);
  - a disconnected network (each island has its own arbitrary angle reference and
    its own frequency, so a single aggregate read-out would be meaningless);
  - `Σ P0 ≠ 0` — the network is lossless, so a net injection has **no**
    equilibrium at all and the steady-state solve would fail or drift;
  - `|P0ᵢ| > Σⱼ K_ij` for some machine, where `K_ij = E′ᵢE′ⱼ/X_ij` — since
    `Pᵢ = Σⱼ K_ij·sin(δᵢ−δⱼ)`, a
    machine asked to push more than its incident couplings can carry has no
    steady state. Necessary, **not** sufficient: passing this check does not
    prove an equilibrium exists, it only rules out one that provably cannot.
"""
struct NetworkModel
    S_base::Float64
    f0::Float64
    buses::Vector{Bus}
    branches::Vector{Branch}
    machines::Vector{Machine}      # stored in bus order: machines[v] is on buses[v]
    bus_index::Dict{Symbol,Int}    # bus id -> vertex index

    function NetworkModel(S_base::Real, f0::Real, buses::Vector{Bus},
                          branches::Vector{Branch}, machines::Vector{Machine})
        S_base > 0 || throw(ArgumentError("NetworkModel: S_base ($S_base) must be > 0 MVA."))
        f0 > 0 || throw(ArgumentError("NetworkModel: f0 ($f0) must be > 0 Hz."))
        isempty(buses) && throw(ArgumentError("NetworkModel: needs at least one bus."))

        _reject_duplicates(b -> b.id, buses, "bus")
        _reject_duplicates(b -> b.id, branches, "branch")
        _reject_duplicates(m -> m.id, machines, "machine")

        bus_index = Dict{Symbol,Int}(b.id => v for (v, b) in enumerate(buses))

        # --- one machine per bus: the tier boundary, enforced ---
        at_bus = zeros(Int, length(buses))          # vertex -> index into `machines`
        for (k, m) in pairs(machines)
            v = get(bus_index, m.bus, 0)
            v == 0 && throw(ArgumentError(
                "Machine $(m.id) sits on bus $(m.bus), which is not in the model."))
            at_bus[v] == 0 || throw(ArgumentError(
                "Bus $(buses[v].id) carries two machines ($(machines[at_bus[v]].id) and " *
                "$(m.id)). The classical tier has one differential state per bus; two " *
                "machines on a bus needs the terminal voltage as an unknown (the DAE tier)."))
            at_bus[v] = k
        end
        for (v, k) in pairs(at_bus)
            k == 0 && throw(ArgumentError(
                "Bus $(buses[v].id) carries no machine. Every bus in the classical tier " *
                "needs a differential state; a passive bus is an algebraic node (the DAE " *
                "tier), and a load is a machine with negative P0."))
        end
        ordered = Machine[machines[k] for k in at_bus]   # bus order, by construction

        # --- branch endpoints exist, at most one branch per pair, one island ---
        # Parallel circuits are rejected rather than supported, and the reason is
        # concrete: the graph the engine builds is a `Graphs.SimpleGraph`, which
        # silently *drops* a second edge between the same pair — the second
        # circuit's coupling would vanish with no error. `TripLine(from, to)`
        # (step 5) could not name one of two circuits either. Supporting them
        # means either a multigraph or merging them into one effective reactance;
        # both are M2b decisions, and a loud rejection now is cheaper than a
        # silently missing circuit later.
        g = Graphs.SimpleGraph(length(buses))
        for br in branches
            haskey(bus_index, br.from) || throw(ArgumentError(
                "Branch $(br.id): bus $(br.from) is not in the model."))
            haskey(bus_index, br.to) || throw(ArgumentError(
                "Branch $(br.id): bus $(br.to) is not in the model."))
            Graphs.add_edge!(g, bus_index[br.from], bus_index[br.to]) || throw(ArgumentError(
                "Branch $(br.id) is a second circuit between $(br.from) and $(br.to). " *
                "M2a carries at most one branch per bus pair — the graph the engine " *
                "builds would silently drop the second, and TripLine could not name " *
                "one of the two. Merge them into one equivalent reactance."))
        end
        Graphs.is_connected(g) || throw(ArgumentError(
            "NetworkModel: the network is not connected. Each island has its own angle " *
            "reference and its own frequency, so one aggregate read-out would be " *
            "meaningless. Split it into separate models, or add the missing branch."))

        # --- lossless network ⇒ the injections must sum to zero ---
        ΣP = sum(m.P0 for m in ordered)
        abs(ΣP) ≤ 1e-6 * S_base || throw(ArgumentError(
            "NetworkModel: Σ P0 = $(ΣP) MW ≠ 0. The classical network is lossless, so a " *
            "net injection has no equilibrium at all — the steady-state solve would fail " *
            "or drift. (A load is a machine with negative P0.)"))

        # --- each machine's injection is within reach of its incident couplings ---
        # Necessary, not sufficient (see the docstring). Computed from the same
        # coupling formula the engine integrates against, so the two cannot drift.
        reach = zeros(Float64, length(buses))
        for br in branches
            i, j = bus_index[br.from], bus_index[br.to]
            K = _coupling(ordered[i], ordered[j], br)
            reach[i] += K
            reach[j] += K
        end
        for (v, m) in pairs(ordered)
            P_pu = abs(m.P0) / S_base
            P_pu ≤ reach[v] || throw(ArgumentError(
                "Machine $(m.id): |P0| = $(abs(m.P0)) MW ($(P_pu) pu) exceeds the total " *
                "coupling of its incident branches ($(reach[v]) pu). Since " *
                "P = Σ K·sin(Δδ), no steady state exists. Strengthen the network, lower " *
                "the injection, or raise E′."))
        end

        return new(Float64(S_base), Float64(f0), buses, branches, ordered, bus_index)
    end
end

"""
    NetworkModel(; S_base, f0, buses, branches, machines)

Keyword form, so a model reads as its own documentation at a call site. Same
validation — the positional inner constructor is the only path, so no
`NetworkModel` can exist unvalidated regardless of how it was built (including a
future `from_powersystems`, D5).
"""
NetworkModel(; S_base, f0, buses, branches, machines) =
    NetworkModel(S_base, f0, buses, branches, machines)

# Duplicate-id rejection, shared by the three collections so the message reads the
# same in each. `key` extracts the id.
function _reject_duplicates(key, items, what::AbstractString)
    seen = Set{Symbol}()
    for it in items
        k = key(it)
        k in seen && throw(ArgumentError("NetworkModel: duplicate $what id :$k."))
        push!(seen, k)
    end
    return nothing
end

"""
    _coupling(mi::Machine, mj::Machine, br::Branch) -> Float64

Synchronising coupling of one branch, pu on the system base:

    K_ij = E′ᵢ·E′ⱼ / X_ij

`Branch.X` is already per-unit on the system base (that is how network data is
published), so there is no conversion here — and `Machine.Xd′`, which *is* on the
machine's own base, is deliberately **not** folded in. See point 2 of the tier
note at the top of this file: folding it per-branch double-counts the internal
reactance of any machine with more than one line, and folding it correctly means
the terminal-bus elimination that D3 forbids and M2b owns.

This is the single source of truth for the coupling — the constructor's
feasibility guard, `branch_arrays`, the engine and the closed-form test all come
through here, so none of them can hold a different convention.
"""
@inline _coupling(mi::Machine, mj::Machine, br::Branch) = mi.E′ * mj.E′ / br.X

"""
    machine_arrays(net::NetworkModel) -> (; H, D, Pm, E, Xd)

The machine parameters as contiguous `Vector{Float64}`s **indexed by vertex**
(entry `v` belongs to `net.buses[v]`), all converted to the **system base** — the
struct-of-arrays view the engine integrates against (SPEC §4).

  - `H`  — s, inertia on `S_base`  (`Hᵢ · S_ratedᵢ/S_base`)
  - `D`  — pu/pu, damping on `S_base` (same weight)
  - `Pm` — pu, mechanical power (`P0ᵢ/S_base`); negative = load
  - `E`  — pu, internal voltage magnitude (base-independent, passed through)
  - `Xd` — pu, transient reactance on `S_base` (`X′dᵢ · S_base/S_ratedᵢ`; note
           the **inverse** weight — impedance scales the other way from power,
           which is the sign of this conversion going wrong). **M2a's dynamics do
           not read this** — it is here, on the right base, for M2b. Folding it
           into the coupling is the mistake point 2 of the tier note describes.

Derived on call, never stored: one canonical model, compiled views (SPEC §3.2).
"""
function machine_arrays(net::NetworkModel)
    S_base = net.S_base
    n = length(net.machines)
    H  = Vector{Float64}(undef, n)
    D  = Vector{Float64}(undef, n)
    Pm = Vector{Float64}(undef, n)
    E  = Vector{Float64}(undef, n)
    Xd = Vector{Float64}(undef, n)
    for (v, m) in pairs(net.machines)
        w = m.S_rated / S_base          # machine base -> system base, for powers
        H[v]  = m.H * w
        D[v]  = m.D * w
        Pm[v] = m.P0 / S_base
        E[v]  = m.E′
        Xd[v] = m.Xd′ / w               # impedance scales inversely
    end
    return (; H, D, Pm, E, Xd)
end

"""
    branch_arrays(net::NetworkModel) -> (; src, dst, X, K)

The branch parameters as contiguous arrays indexed by branch, in `net.branches`
order. `src`/`dst` are **vertex indices** (not bus ids), so they can be handed
straight to a graph.

  - `src`, `dst` — `Vector{Int}` vertex indices of the endpoints
  - `X` — pu on `S_base`, the branch's own series reactance (as given)
  - `K` — pu on `S_base`, the synchronising coupling `E′ᵢ·E′ⱼ / X_ij`, i.e. the
          branch's transferable power `P_ij = K·sin(δᵢ−δⱼ)`. This is the quantity
          a `TripLine` zeroes (M2 step 5).

`K` deliberately does **not** fold in the machines' transient reactances; that is
exact on every topology, whereas folding them in is exact only on a radial pair.
See point 2 of the tier note at the top of this file.
"""
function branch_arrays(net::NetworkModel)
    S_base = net.S_base
    n = length(net.branches)
    src = Vector{Int}(undef, n)
    dst = Vector{Int}(undef, n)
    X   = Vector{Float64}(undef, n)
    K   = Vector{Float64}(undef, n)
    for (e, br) in pairs(net.branches)
        i, j = net.bus_index[br.from], net.bus_index[br.to]
        src[e] = i
        dst[e] = j
        X[e]   = br.X
        K[e]   = _coupling(net.machines[i], net.machines[j], br)
    end
    return (; src, dst, X, K)
end

"""
    machine_at(net::NetworkModel, bus::Symbol) -> Machine

The machine on `bus`. Throws if the bus is not in the model. (Every bus carries
exactly one machine — see the tier note at the top of this file.)
"""
function machine_at(net::NetworkModel, bus::Symbol)
    v = get(net.bus_index, bus, 0)
    v == 0 && throw(ArgumentError("NetworkModel: no bus :$bus."))
    return net.machines[v]
end

"""
    two_machine_system() -> NetworkModel

Two machines, one tie — **the case with a closed form**, and the only topology on
which folding `X′d` into the coupling would even have been exact (both machines
have branch degree 1). Linearising the relative angle about the equilibrium gives
an inter-machine oscillation near 1.59 Hz; `test/` re-derives that number through
`branch_arrays`, i.e. against the real code path, not against a hand-written
coupling (m2-context.md, open questions).

The two machines are deliberately rated **away** from `S_base` (250 and 400 MVA
against a 100 MVA base) and away from each other, so a missing or inverted
per-unit conversion changes the answer instead of hiding behind a weight of 1.
The tie is a longish 0.25 pu, which puts the mode in the 1–2 Hz band real
inter-area oscillations live in rather than somewhere unrecognisable.
"""
function two_machine_system()
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    machines = [
        #       id    bus   S_rated    H    D    Xd′    E′     P0
        Machine(:G1, :B1,    250.0,  4.0, 2.0,  0.25,  1.05,  60.0),
        Machine(:G2, :B2,    400.0,  5.0, 2.0,  0.30,  1.02, -60.0),
    ]
    branches = [Branch(:L12, :B1, :B2, 0.25, 500.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines)
end

"""
    three_machine_ring() -> NetworkModel

Three machines in a ring — **the case without a closed form**, and the shape the
dependency spike settled `find_fixpoint` on (m2-context.md). Injections are
+80 / +30 / −110 MW: two generators and a load, summing to zero as a lossless
network requires.

The ring is the interesting topology because it is meshed: power reaches every
machine two ways, so the steady state is a genuine solve rather than a chain of
`asin`s, and the machines have somewhere to swing against each other. That same
meshing is what rules out folding `X′d` into the coupling — every machine here
has branch degree 2 (see point 2 of the tier note at the top of this file).
"""
function three_machine_ring()
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    machines = [
        #       id    bus   S_rated    H    D    Xd′    E′      P0
        Machine(:G1, :B1,    300.0,  4.0, 2.0,  0.30,  1.05,   80.0),
        Machine(:G2, :B2,    200.0,  3.0, 2.0,  0.20,  1.03,   30.0),
        Machine(:G3, :B3,    500.0,  5.0, 2.0,  0.50,  1.04, -110.0),
    ]
    branches = [
        Branch(:L12, :B1, :B2, 0.25, 500.0),
        Branch(:L23, :B2, :B3, 0.25, 500.0),
        Branch(:L31, :B3, :B1, 0.25, 500.0),
    ]
    return NetworkModel(100.0, 50.0, buses, branches, machines)
end
