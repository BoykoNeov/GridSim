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
# GOVERNORS (M3 step 1 — this replaces M2's "there are none"). `Machine` now
# carries droop `R`, a net-injection ceiling `Pmax` and a governor lag `Tg`, and
# each machine gains a third state `ΔPm` in the engine. This does **not** move the
# fidelity tier: it is a *control* state on top of the same reduced classical
# network-swing model, not a new electrical representation.
#
#   - **Governor-free is still expressible, and is the default**: `R = Inf`,
#     `Pmax = P0` (zero headroom). The droop gain `1/R` is then `0` and `ΔPm`
#     starts at `0`, so `dΔPm/dt = −ΔPm/Tg` holds it at zero forever and the
#     machine behaves exactly as it did in M2. Every M2 model therefore still
#     describes a real system rather than an accidentally-governed one — which is
#     why the three new fields are *defaulted* positional arguments.
#   - **There is no down-regulation floor**, deliberately, exactly as in M1: only
#     the up-headroom saturates. A machine held above nominal frequency commands
#     unboundedly negative `ΔPm`. That is a known limit of the tier (it matters for
#     the over-frequency side of a two-area split), recorded rather than papered
#     over with a floor nobody has validated.
#
# What droop does **not** do, said here because the obvious assumption is wrong:
# it does not give the system an equilibrium after a generator trip. At settle
# `Δω = −ΔP/(1/R_eq + D)`, which is non-zero because part of the deficit is carried
# by load damping rather than by mechanical power — so the angles still drift
# forever and `find_fixpoint` still cannot be called on a post-trip state. Only
# secondary control (AGC) would settle them, and it is deliberately out of scope
# (docs/plans/m3-context.md D3).
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

Governor data (M3 step 1), all **optional** and defaulting to governor-free so
every M2 model still describes a real system:

  - `R`       — pu **on the machine's own base**, governor droop. The gain is
                `1/R`, so `R = Inf` (the default) means *no primary response*.
  - `Pmax`    — MW, the **net-injection ceiling**; up-reserve is `Pmax − P0`, and
                the default `Pmax = P0` is zero headroom.

                **On an aggregated area machine this is not a fleet nameplate.**
                Such a machine is generation *minus* load, so its `P0` is the
                area's net injection into the network (which is routinely
                negative — an importing area). `Pmax` there means
                `P0 + the area's up-reserve` and has to be set deliberately;
                putting an installed-capacity figure in it silently hands the area
                hundreds of GW of reserve (docs/plans/m3-context.md D4).
  - `Tg`      — s, the governor/turbine first-order lag. Validated (`> 0`, it is a
                denominator) even when `R = Inf` makes it unobservable.

See the GOVERNORS note at the top of this file for what droop does and — more
importantly — what it does not do.
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
    R::Float64         # pu    — governor droop, on the machine's own base (Inf = none)
    Pmax::Float64      # MW    — net-injection ceiling; headroom = Pmax - P0
    Tg::Float64        # s     — governor/turbine first-order lag

    # Reject a machine that is wrong on its face rather than letting it poison a
    # solve — the spirit of `GeneratingUnit`'s headroom guard. `H > 0` is strict
    # because it sits in a denominator (the swing equation divides by 2H), so a
    # zero is not a degenerate-but-valid machine, it is a division by zero. A
    # zero-inertia
    # converter is a real thing and M1's aggregate model supports it — but as a
    # *vertex* in a swing network it has no differential state, which is the
    # grid-forming/following tier, not this one.
    #
    # The three governor arguments are **defaulted, positional** rather than
    # keyword: every M2 call site keeps working untouched, and what it builds is
    # exactly the governor-free machine it always was (`1/R = 0`, zero headroom),
    # so the existing suite stays a valid oracle for the state-layout change.
    function Machine(id::Symbol, bus::Symbol, S_rated::Real, H::Real, D::Real,
                     Xd′::Real, E′::Real, P0::Real,
                     R::Real = Inf, Pmax::Real = P0, Tg::Real = 1.0)
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
        # `R` is a divisor (the gain is 1/R), so zero is not a degenerate-but-valid
        # droop setting, it is a division by zero. `Inf` is the sanctioned way to
        # say "no governor" and satisfies this guard.
        R > 0 || throw(ArgumentError(
            "Machine $id: R ($R) must be > 0 pu — droop is a divisor (the gain is 1/R). " *
            "Use R = Inf for a governor-free machine."))
        # `Tg` divides the governor lag, so it is guarded even when `R = Inf` makes
        # it unobservable — data that is only sometimes read is exactly the data
        # that gets set wrong and noticed a milestone later.
        Tg > 0 || throw(ArgumentError(
            "Machine $id: Tg ($Tg) must be > 0 s — it is the governor lag's denominator."))
        # Zero reserve is legal; negative is not. On an aggregated area machine
        # Pmax is P0 + the area's up-reserve, NOT a fleet nameplate (see the
        # docstring, and m3-context.md D4).
        Pmax ≥ P0 || throw(ArgumentError(
            "Machine $id: Pmax ($Pmax) must be ≥ P0 ($P0) — headroom < 0. On an aggregated " *
            "area machine Pmax means P0 + the area's up-reserve, not a fleet nameplate."))
        return new(id, bus, Float64(S_rated), Float64(H), Float64(D),
                   Float64(Xd′), Float64(E′), Float64(P0),
                   Float64(R), Float64(Pmax), Float64(Tg))
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
    machine_arrays(net::NetworkModel) -> (; H, D, Pm, E, Xd, invR, headroom, Tg)

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

Governor data (M3 step 1), on the same system base:

  - `invR`     — pu/pu, the droop **gain** `(1/Rᵢ)·(Sᵢ/S_base)`. It is the gain and
                 not the droop that converts and that sums: `sum(invR)` is exactly
                 M1's aggregate `1/R_eq` (`aggregates`, engines/frequency_response.jl),
                 which is the whole reason this is the only place the conversion
                 happens. A governor-free machine has `R = Inf`, and `1/Inf` is
                 `0.0` — zero gain, no `NaN`, nothing special-cased.
  - `headroom` — pu on `S_base`, up-reserve `(Pmaxᵢ − P0ᵢ)/S_base`; the ceiling at
                 which that machine's `ΔPm` saturates. **Per machine**, not pooled:
                 one area's reserve cannot answer another area's deficit except
                 through the network, which is the point of the tier.
  - `Tg`       — s, the governor lag, passed straight through (seconds are
                 base-independent, like `E`).

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
    invR     = Vector{Float64}(undef, n)
    headroom = Vector{Float64}(undef, n)
    Tg       = Vector{Float64}(undef, n)
    for (v, m) in pairs(net.machines)
        w = m.S_rated / S_base          # machine base -> system base, for powers
        H[v]  = m.H * w
        D[v]  = m.D * w
        Pm[v] = m.P0 / S_base
        E[v]  = m.E′
        Xd[v] = m.Xd′ / w               # impedance scales inversely
        # The GAIN converts with the power weight (same as H and D), not the droop
        # itself — writing `m.R * w` here would be the mirror-image of the `Xd′`
        # mistake above and would still look plausible.
        invR[v]     = (1.0 / m.R) * w
        headroom[v] = (m.Pmax - m.P0) / S_base
        Tg[v]       = m.Tg
    end
    return (; H, D, Pm, E, Xd, invR, headroom, Tg)
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

"""
    coi_model(net::NetworkModel) -> SystemModel

Compile the **center-of-inertia aggregate view** of `net` — the M1 `SystemModel`
that `FrequencyResponseEngine` runs on — *down from* the M2 network model. This is
what keeps SPEC §3.2 ("one canonical model; reduced models are compiled views")
true rather than aspirational: the aggregate model is never hand-maintained beside
the network one, and running the same disturbance through both is M2's
cross-fidelity validation (V4).

The mapping, machine by machine (in bus order):

| `SystemModel`        | from                       | note                          |
|:---------------------|:---------------------------|:------------------------------|
| `S_base`, `f0`       | passed through             |                               |
| `GeneratingUnit.id`  | `Machine.id`               |                               |
| `.S_rated`, `.H`     | **raw, machine base**      | `aggregates` applies the weight |
| `.P0`                | `Machine.P0` (MW)          | negative = load, carried as-is  |
| `.R`                 | `Machine.R` (machine base) | `aggregates` applies the weight |
| `.Pmax`              | `Machine.Pmax` (MW)        | headroom = `Pmax − P0`          |
| `SystemModel.D`      | `sum(machine_arrays(net).D)` | **pre-weighted, system base** |
| `SystemModel.Tg`     | droop-gain-weighted mean   | a choice with no oracle — below |

**The H/D asymmetry is deliberate and is the trap in this function.** `H` and
`S_rated` go through *raw* on the machine's own base, because `aggregates`
(engines/frequency_response.jl) applies `S_rated/S_base` itself. `SystemModel.D`
is *already* a system-base scalar in M1 and nothing re-weights it, so it must be
summed **after** conversion. Both halves therefore come through
`machine_arrays` — the same single converter the engine integrates against — so
`coi_model` cannot come to hold a different per-unit convention than
`SwingEngine`. Do not "fix" the inconsistency by weighting `H` here too; the test
suite asserts against that exact wrong conversion by name.

**`Tg` is the one field with no oracle, and that is said out loud rather than
hidden in a formula.** `SystemModel` carries *one* system-wide lag; the network
model carries one per machine. An aggregate of several first-order lags is only
exactly first-order when they are all equal, so any single number here is a
modelling choice. The choice made is the **droop-gain-weighted mean**
`Σ (invRᵢ·Tgᵢ) / Σ invRᵢ` — weighting by the gain because a machine that does not
respond should not get a say in how fast the aggregate responds — falling back to
`1.0` when no machine has droop at all (the weights are then all zero).

Nothing in the validation suite can distinguish this from another aggregation: the
droop settling value `Δω = −ΔP/(1/R_eq + D)` is **Tg-independent**, so it pins the
gain and not the lag. Treat the number as unvalidated until something measures the
*shape* of the aggregate response, not just where it lands.

For a governor-free network the fallback fires and this reduces exactly to M2's
`Tg = 1.0`, which was arbitrary for a stronger reason: the governor state was
identically zero, needing *both* `R_eq = Inf` (no droop command) and `ΔPm(0) = 0`
(M1's state is a deviation, so the governor starts at rest). `test/` asserts that
invariance by compiling a second model with `Tg = 100` and getting a bit-identical
trajectory — which remains true of a governor-free model and is no longer true in
general.

**What the cross-fidelity comparison now compares** (the open question in
m3-context.md, settled here). M2 hard-coded `R = Inf` / `Pmax = P0` so that the two
tiers differed by inter-machine dynamics *alone*. Compiling the real droop through
is the choice made instead, because the alternative breaks SPEC §3.2: a view that
deletes a property of the canonical model is not a compiled view of it, it is a
different model, and the first governed network would have been compared against
an aggregate with no primary response — a difference that would look like network
dynamics. So the comparison now differs by inter-machine dynamics *and* by the
aggregation of several governors into one lag. For every governor-free model —
which is every fixture M2 shipped — this is byte-identical to what M2 produced,
and the difference is exactly zero.

**Two consequences worth naming before they surprise someone.**

  - **Loads compile to units.** A load is a machine with negative `P0`, and it is a
    rotating mass, so it belongs in `H_sys` and in `D`. It therefore becomes a
    `GeneratingUnit` with negative `P0` and negative `Pmax`. One M1 read-out does
    not survive that: `tripped_mw` accumulates `unit.P0` as "generation lost", which
    is meaningless (and signed the other way) for a compiled load. Read `f`/`RoCoF`
    off a COI-compiled model, not `tripped_mw`. M1 is deliberately not changed for
    this — the channel is correct for the model M1 owns.
  - **The aggregate keeps the damping of a tripped machine.** M1's `D` is one
    system-wide constant that `aggregates` passes through unchanged, while the
    network model's damping is per-machine and leaves with the machine. So after a
    generator trip the two models settle at *different* frequencies
    (`Σ Pm_online / Σ_online D` against `Σ Pm_online / Σ_all D`), and on the shipped
    `three_machine_ring` that gap **dominates** the late divergence rather than the
    inter-machine swings the plan expected. Recorded as a finding in
    `docs/plans/m2-context.md`; `test/` asserts the gap as a derived number and uses
    separate fixtures (a tripped machine with `D = 0`) to isolate the swing content.
"""
function coi_model(net::NetworkModel)
    ma = machine_arrays(net)                 # the one per-unit converter (see above)
    units = Vector{GeneratingUnit}(undef, length(net.machines))
    for (v, m) in pairs(net.machines)
        # H, S_rated, R and Pmax raw on the machine base — `aggregates` applies the
        # weight to H and to 1/R itself, and reads headroom straight off Pmax − P0
        # in MW. A governor-free machine passes through as `R = Inf`, `Pmax = P0`,
        # which is exactly what M2 hard-coded here.
        units[v] = GeneratingUnit(m.id, m.S_rated, m.H, m.P0, m.R, m.Pmax)
    end
    # D pre-weighted onto the system base, because `SystemModel.D` is a system-base
    # scalar that nothing downstream re-weights. This is the asymmetry above.
    D_sys = sum(ma.D)
    # The one field with no oracle (see the docstring): several first-order governor
    # lags collapsed into one, weighted by droop gain so a machine that does not
    # respond does not vote on the response speed. `Σ invR == 0` is a fully
    # governor-free network, where the weights vanish and `Tg` is unobservable —
    # M2's arbitrary 1.0, reproduced exactly rather than by a 0/0.
    Σg = sum(ma.invR)
    Tg_sys = Σg > 0 ? sum(ma.invR[v] * ma.Tg[v] for v in eachindex(ma.Tg)) / Σg : 1.0
    return SystemModel(net.S_base, net.f0, D_sys, Tg_sys, units)
end
