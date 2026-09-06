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
    Load

One aggregate load at a bus — the M5 addition that lets a bus consume power
without carrying a rotating mass (`docs/plans/m5-context.md` D3).

**This does not replace M2a's "a load is a machine with negative `P0`".** A
negative-`P0` machine stays a machine and every M2/M3 scenario constructs
unchanged; `three_machine_ring()`'s −110 MW bus is still a machine. `Load` is for
buses that carry no rotating mass at all, which the classical tier cannot
represent (it needs a differential state per bus) and the detailed tier can (the
bus voltage is an algebraic unknown).

  - `id`   — unique name.
  - `bus`  — id of the bus it sits on (at most one load per bus; see below).
  - `P0`   — MW, active power **drawn** at nominal voltage. Positive = consuming,
             which is the opposite sign convention from `Machine.P0` and is the
             one every load flow uses. The model's balance guard accounts for it.
  - `Q0`   — MVAr, reactive power drawn at nominal voltage. May be negative
             (a capacitive bus).

ZIP coefficients (`m5-prestudy.md` §6), **carried and validated here, consumed by
plan step 6** — the same footing `Machine.Xd′` had in M2 (real data, on the right
base, with the milestone that reads it named):

  - `a_z`, `a_i`, `a_p` — constant-impedance / constant-current / constant-power
    shares, `P = P0·(a_z·V² + a_i·V + a_p)` and `Q` likewise. They must sum to 1,
    so the load draws exactly `P0` at `V = 1` whatever the split. The default is
    `a_z = 1` — pure constant impedance, the case with a closed form (it folds
    into the admittance) and the case PowerDynamics' `ZIPLoad` reduces to.

**The engine, not this type, rejects the shares it has not implemented.** Plan
step 1 solves only the constant-impedance term, so a load with `a_i` or `a_p`
non-zero is refused *by the engine* with the step named. Validating the data here
and refusing to integrate it there is the split this file already uses for `Xd′`:
data that is only sometimes read is exactly the data that gets set wrong and
noticed a milestone later.
"""
struct Load
    id::Symbol
    bus::Symbol
    P0::Float64       # MW   — drawn at V = 1 (positive = consuming)
    Q0::Float64       # MVAr — drawn at V = 1 (may be negative)
    a_z::Float64      # constant-impedance share
    a_i::Float64      # constant-current share
    a_p::Float64      # constant-power share

    # The ZIP shares are defaulted positional, the precedent M3 set for the
    # governor triple: every call site that does not care builds the
    # constant-impedance load, which is the one plan step 1 integrates.
    function Load(id::Symbol, bus::Symbol, P0::Real, Q0::Real,
                  a_z::Real = 1.0, a_i::Real = 0.0, a_p::Real = 0.0)
        # `P0 = 0` is legal (a purely reactive shunt is a real thing); negative is
        # not, because a load that generates is a machine and belongs in the other
        # collection where the balance guard and `coi_model` can see it.
        P0 ≥ 0 || throw(ArgumentError(
            "Load $id: P0 ($P0) must be ≥ 0 MW — a load draws power. A bus that " *
            "injects is a Machine (M2a's negative-P0 convention is unchanged)."))
        for (nm, a) in ((:a_z, a_z), (:a_i, a_i), (:a_p, a_p))
            a ≥ 0 || throw(ArgumentError(
                "Load $id: ZIP share $nm ($a) must be ≥ 0."))
        end
        # Summing to one is what makes `P0` mean "drawn at V = 1" regardless of the
        # split — without it the same `P0` would mean a different power for every
        # coefficient set, and the balance guard below would be comparing schedules
        # that are not commensurable.
        abs(a_z + a_i + a_p - 1.0) ≤ 1e-12 || throw(ArgumentError(
            "Load $id: ZIP shares must sum to 1 (got a_z + a_i + a_p = " *
            "$(a_z + a_i + a_p)). They are shares of P0, which is the power drawn " *
            "at V = 1; a sum ≠ 1 silently redefines what P0 means."))
        return new(id, bus, Float64(P0), Float64(Q0),
                   Float64(a_z), Float64(a_i), Float64(a_p))
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
  - a machine or load referring to a bus that does not exist;
  - a second load at a bus already carrying one (they are additive — merge them;
    the rejection keeps `load_at_bus` a plain vertex → index map, and a silently
    dropped load is the failure mode the parallel-circuit guard above exists for);
  - a disconnected network (each island has its own arbitrary angle reference and
    its own frequency, so a single aggregate read-out would be meaningless);
  - `Σ machines.P0 ≠ Σ loads.P0` — the network is lossless, so a net injection has
    **no** equilibrium at all and the steady-state solve would fail or drift.

**Three guards that used to live here have MOVED to `SwingEngine`** (M5 step 1,
`docs/plans/m5-context.md` D3), because each is a property of the classical tier
and not of the data: a bus with no machine, a bus with more than one, and the
`|P0ᵢ| ≤ Σⱼ K_ij` reachability check. The boundary stays loud — the engine refuses
such a model by name, with the tier named in the message — it just stops being a
property of the model. The third moved for a reason the tasks list did not
anticipate: `K_ij = E′ᵢE′ⱼ/X_ij` is not merely *inappropriate* on a model with
machine-free buses, it is **uncomputable**, since there is no `E′` at one end.

**What did NOT widen: there is no `Σ Q0` twin.** The active-power balance holds
because a pure series reactance is lossless in P. It absorbs `I²X` of reactive
power, so a Q-balance guard written by symmetry with the P one would reject every
valid model. (Derive the limit; do not assume the symmetry cancels.)
"""
struct NetworkModel
    S_base::Float64
    f0::Float64
    buses::Vector{Bus}
    branches::Vector{Branch}
    machines::Vector{Machine}      # sorted by bus (see `machines_at`)
    loads::Vector{Load}            # sorted by bus (see `load_at`)
    bus_index::Dict{Symbol,Int}    # bus id -> vertex index
    machines_at_bus::Vector{Vector{Int}}  # vertex -> indices into `machines` (may be empty)
    load_at_bus::Vector{Int}          # vertex -> index into `loads`, or 0 for none

    function NetworkModel(S_base::Real, f0::Real, buses::Vector{Bus},
                          branches::Vector{Branch}, machines::Vector{Machine},
                          loads::Vector{Load} = Load[])
        S_base > 0 || throw(ArgumentError("NetworkModel: S_base ($S_base) must be > 0 MVA."))
        f0 > 0 || throw(ArgumentError("NetworkModel: f0 ($f0) must be > 0 Hz."))
        isempty(buses) && throw(ArgumentError("NetworkModel: needs at least one bus."))

        _reject_duplicates(b -> b.id, buses, "bus")
        _reject_duplicates(b -> b.id, branches, "branch")
        _reject_duplicates(m -> m.id, machines, "machine")
        _reject_duplicates(l -> l.id, loads, "load")

        bus_index = Dict{Symbol,Int}(b.id => v for (v, b) in enumerate(buses))

        # --- machines grouped by bus; the COUNT is no longer this type's business --
        # A bus may now carry zero machines (a load or junction bus) or several. The
        # classical tier still cannot represent either, and `SwingEngine` still
        # refuses both, loudly and by name — the check moved, it did not go away
        # (m5-context.md D3).
        #
        # Machines are still stored SORTED BY BUS, and the sort is stable, so on any
        # model where every bus carries exactly one machine the order is bit-for-bit
        # what M2/M3 produced and machine index still equals vertex index. That
        # identity is what `branch_arrays` and `SwingEngine`'s `for i in 1:nb` rely
        # on, and it is why both now assert it rather than assume it.
        grouped = [Int[] for _ in 1:length(buses)]
        for (k, m) in pairs(machines)
            v = get(bus_index, m.bus, 0)
            v == 0 && throw(ArgumentError(
                "Machine $(m.id) sits on bus $(m.bus), which is not in the model."))
            push!(grouped[v], k)
        end
        ordered = Machine[machines[k] for v in 1:length(buses) for k in grouped[v]]
        # Re-index the groups against the SORTED vector: `grouped` holds positions in
        # the caller's vector, and every consumer wants positions in `net.machines`.
        # The sorted position of the j-th machine of bus v is its running count,
        # because `ordered` is exactly this walk flattened.
        machines_at = [Int[] for _ in 1:length(buses)]
        next_k = 0
        for v in 1:length(buses), _ in grouped[v]
            next_k += 1
            push!(machines_at[v], next_k)
        end

        # --- loads: at most one per bus (they are additive; merge them) ------------
        seen_load = zeros(Int, length(buses))
        for (k, l) in pairs(loads)
            v = get(bus_index, l.bus, 0)
            v == 0 && throw(ArgumentError(
                "Load $(l.id) sits on bus $(l.bus), which is not in the model."))
            seen_load[v] == 0 || throw(ArgumentError(
                "Bus $(buses[v].id) carries two loads ($(loads[seen_load[v]].id) and " *
                "$(l.id)). Loads at one bus are additive — merge them into one. " *
                "Rejecting keeps `load_at_bus` a plain vertex → index map; the ZIP shares " *
                "of a merged pair are the P0-weighted mean, which is a decision for " *
                "whoever writes the data, not for this constructor."))
            seen_load[v] = k
        end
        # Sorted by bus, like the machines, so `net.loads` order is a property of the
        # topology and not of the order the caller happened to list them in.
        ordered_loads = Load[loads[seen_load[v]] for v in 1:length(buses) if seen_load[v] != 0]
        load_at = zeros(Int, length(buses))
        for (k, l) in pairs(ordered_loads)
            load_at[bus_index[l.bus]] = k
        end

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

        # --- lossless network ⇒ scheduled generation must meet scheduled load ---
        # Widened for `Load`, whose sign convention is the opposite of a machine's:
        # a machine's `P0` is an INJECTION (negative = absorbing, M2a's load) and a
        # load's `P0` is a DRAW. On every M2/M3 model `loads` is empty and this is
        # arithmetically the guard it always was, to the bit.
        #
        # This is the SCHEDULE balance, at nominal voltage. It is not, and cannot be,
        # the balance the solved network actually settles at once loads depend on
        # voltage: the detailed tier's own power flow finds |V| ≠ 1 and a
        # constant-impedance load then draws P0·|V|², so the slack machine absorbs the
        # difference. That is why the detailed engine takes each machine's mechanical
        # power from the POWER FLOW rather than from `P0` (m5-prestudy.md §4).
        # Measured on the step-1 spike: a 0.8 pu load at |V| = 0.978 draws 0.765, and
        # the slack settles at 0.465 against a scheduled 0.5.
        ΣP = sum(m.P0 for m in ordered; init = 0.0) -
             sum(l.P0 for l in ordered_loads; init = 0.0)
        abs(ΣP) ≤ 1e-6 * S_base || throw(ArgumentError(
            "NetworkModel: Σ machines.P0 − Σ loads.P0 = $(ΣP) MW ≠ 0. The network is " *
            "lossless in P, so a net injection has no equilibrium at all — the " *
            "steady-state solve would fail or drift. (A machine's P0 is an injection; " *
            "a load's P0 is a draw. M2a's negative-P0 machine is still a machine.)"))

        # There is deliberately NO Σ Q0 guard — see the docstring. A series reactance
        # absorbs I²X of reactive power, so the P balance does not have a Q twin.

        return new(Float64(S_base), Float64(f0), buses, branches, ordered,
                   ordered_loads, bus_index, machines_at, load_at)
    end
end

"""
    NetworkModel(; S_base, f0, buses, branches, machines, loads = Load[])

Keyword form, so a model reads as its own documentation at a call site. Same
validation — the positional inner constructor is the only path, so no
`NetworkModel` can exist unvalidated regardless of how it was built (including a
future `from_powersystems`, D5).
"""
NetworkModel(; S_base, f0, buses, branches, machines, loads = Load[]) =
    NetworkModel(S_base, f0, buses, branches, machines, loads)

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
    machine_arrays(net::NetworkModel) -> (; bus, H, D, Pm, E, Xd, invR, headroom, Tg)

The machine parameters as contiguous `Vector{Float64}`s **indexed by machine**
(entry `k` belongs to `net.machines[k]`), all converted to the **system base** —
the struct-of-arrays view the engine integrates against (SPEC §4).

**Indexed by machine, not by vertex — and the difference used to be invisible.**
Until M5 every bus carried exactly one machine, so machine index and vertex index
were the same number and this docstring said "indexed by vertex". They are no
longer the same, because a bus may now carry no machine at all. The arrays stay
machine-indexed (the loop below always was), and the vertex each machine sits on
arrives as its own column:

  - `bus` — `Vector{Int}`, the **vertex index** of each machine's bus. On any
            model where every bus carries one machine this is exactly `1:nb`,
            which is what lets `SwingEngine` keep indexing by vertex after
            asserting that identity rather than silently reading the wrong
            machine's inertia.

The alternative — keeping the arrays vertex-indexed with holes — was rejected:
a machine-free bus would need a sentinel `H`, and `H` sits in a denominator.

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
    bus = Vector{Int}(undef, n)
    H  = Vector{Float64}(undef, n)
    D  = Vector{Float64}(undef, n)
    Pm = Vector{Float64}(undef, n)
    E  = Vector{Float64}(undef, n)
    Xd = Vector{Float64}(undef, n)
    invR     = Vector{Float64}(undef, n)
    headroom = Vector{Float64}(undef, n)
    Tg       = Vector{Float64}(undef, n)
    for (v, m) in pairs(net.machines)
        bus[v] = net.bus_index[m.bus]
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
    return (; bus, H, D, Pm, E, Xd, invR, headroom, Tg)
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
    # `K` needs an `E′` at BOTH ends, so this view exists only for a model where
    # every bus carries exactly one machine. Loud, by name — and note this is not a
    # taste judgement about tiers: on a machine-free bus `K` is uncomputable, and
    # `net.machines[i]` indexed by a VERTEX would quietly return some other bus's
    # machine. See `branch_topology` for the machine-free view.
    _assert_one_machine_per_bus(net, "branch_arrays")
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
    _assert_one_machine_per_bus(net::NetworkModel, who::AbstractString)

The classical tier's structural precondition, in the shape `reference/src/oracle.jl`
uses for its own (`_assert_radial`, `_assert_governor_free`): refused at build time,
by name, with the caller named in the message.

It lived in the `NetworkModel` constructor until M5 (`docs/plans/m5-context.md` D3).
It moved because it is a property of the *engine*, not of the data — but it moved
intact, so the boundary the M2 file header called "a loud error rather than a
quietly wrong answer" is still exactly that.
"""
function _assert_one_machine_per_bus(net::NetworkModel, who::AbstractString)
    for (v, ks) in pairs(net.machines_at_bus)
        isempty(ks) && throw(ArgumentError(
            "$who: bus $(net.buses[v].id) carries no machine. Every bus in the " *
            "classical tier needs a differential state; a passive bus is an algebraic " *
            "node, which is the detailed (DAE) tier. In the classical tier a load is a " *
            "machine with negative P0."))
        length(ks) == 1 || throw(ArgumentError(
            "$who: bus $(net.buses[v].id) carries $(length(ks)) machines " *
            "($(join([net.machines[k].id for k in ks], ", "))). The classical tier has " *
            "one differential state per bus; two machines on a bus needs the terminal " *
            "voltage as an unknown, which is the detailed (DAE) tier."))
    end
    return nothing
end

"""
    branch_topology(net::NetworkModel) -> (; src, dst, X)

The branches as contiguous arrays indexed by branch, in `net.branches` order —
**the part of `branch_arrays` that does not need a machine at either end**.

  - `src`, `dst` — `Vector{Int}` vertex indices of the endpoints
  - `X` — pu on `S_base`, the branch's own series reactance (as given)

This is what the detailed (DAE) tier reads, where a branch may join two buses
neither of which carries a machine. `branch_arrays` is the classical tier's view
and additionally carries `K`, which is why it has a precondition and this does not.
"""
function branch_topology(net::NetworkModel)
    n = length(net.branches)
    src = Vector{Int}(undef, n)
    dst = Vector{Int}(undef, n)
    X   = Vector{Float64}(undef, n)
    for (e, br) in pairs(net.branches)
        src[e] = net.bus_index[br.from]
        dst[e] = net.bus_index[br.to]
        X[e]   = br.X
    end
    return (; src, dst, X)
end

"""
    load_arrays(net::NetworkModel) -> (; bus, P, Q, a_z, a_i, a_p)

The loads as contiguous arrays **indexed by load**, converted to the system base —
the counterpart of `machine_arrays`, and for the same reason: one place where the
conversion happens.

  - `bus` — `Vector{Int}`, the vertex index of each load's bus
  - `P`, `Q` — pu on `S_base`, **drawn** at `V = 1` (positive `P` = consuming)
  - `a_z`, `a_i`, `a_p` — the ZIP shares, dimensionless and base-free

Loads carry no base of their own — unlike a machine, whose `H`, `D` and `Xd′` are
on its own `S_rated` — so the only conversion is `MW/S_base`. That asymmetry is
worth naming because the machine converter's weight is the thing that keeps going
wrong, and its absence here is correct rather than an omission.
"""
function load_arrays(net::NetworkModel)
    S_base = net.S_base
    n = length(net.loads)
    bus = Vector{Int}(undef, n)
    P   = Vector{Float64}(undef, n)
    Qd  = Vector{Float64}(undef, n)
    a_z = Vector{Float64}(undef, n)
    a_i = Vector{Float64}(undef, n)
    a_p = Vector{Float64}(undef, n)
    for (k, l) in pairs(net.loads)
        bus[k] = net.bus_index[l.bus]
        P[k]   = l.P0 / S_base
        Qd[k]  = l.Q0 / S_base
        a_z[k] = l.a_z
        a_i[k] = l.a_i
        a_p[k] = l.a_p
    end
    return (; bus, P, Q = Qd, a_z, a_i, a_p)
end

"""
    machine_at(net::NetworkModel, bus::Symbol) -> Machine

The machine on `bus`. Throws if the bus is not in the model. (Every bus carries
exactly one machine — see the tier note at the top of this file.)
"""
function machine_at(net::NetworkModel, bus::Symbol)
    v = get(net.bus_index, bus, 0)
    v == 0 && throw(ArgumentError("NetworkModel: no bus :$bus."))
    ks = net.machines_at_bus[v]
    # `net.machines[v]` — indexing the machine vector with a VERTEX — is what this
    # function used to do, and it was right only while the two indices coincided.
    isempty(ks) && throw(ArgumentError(
        "NetworkModel: bus :$bus carries no machine. Use `machines_at` for a bus " *
        "that may carry none."))
    length(ks) == 1 || throw(ArgumentError(
        "NetworkModel: bus :$bus carries $(length(ks)) machines. Use `machines_at`, " *
        "which returns all of them."))
    return net.machines[ks[1]]
end

"""
    machines_at(net::NetworkModel, bus::Symbol) -> Vector{Machine}

Every machine on `bus`, possibly none. The general form of `machine_at`, which is
the one-machine convenience and throws when that is not what the bus holds.
"""
function machines_at(net::NetworkModel, bus::Symbol)
    v = get(net.bus_index, bus, 0)
    v == 0 && throw(ArgumentError("NetworkModel: no bus :$bus."))
    return Machine[net.machines[k] for k in net.machines_at_bus[v]]
end

"""
    load_at(net::NetworkModel, bus::Symbol) -> Union{Load,Nothing}

The load on `bus`, or `nothing` if it carries none. Throws if the bus is not in
the model — a missing bus is a typo, an absent load is ordinary.
"""
function load_at(net::NetworkModel, bus::Symbol)
    v = get(net.bus_index, bus, 0)
    v == 0 && throw(ArgumentError("NetworkModel: no bus :$bus."))
    k = net.load_at_bus[v]
    return k == 0 ? nothing : net.loads[k]
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
    # SPEC §3.2's one working proof that reduced models are DERIVED views, so what
    # may be handed to it is not a matter of taste (m5-context.md D3). It refuses a
    # model this aggregation has no validated meaning for rather than quietly
    # aggregating over the machines and dropping the rest of the system on the floor:
    #
    #   - a machine-free bus or a two-machine bus — the same structural precondition
    #     `SwingEngine` takes, and for the same reason: `coi_model` compiles the
    #     classical tier's aggregate, so it inherits the classical tier's boundary;
    #   - a `Load` — folding a voltage-dependent load into an aggregate damping
    #     constant is a MODELLING CLAIM nobody has validated, and it would land
    #     inside the one derivation the repo points at to show reduced models are
    #     derived rather than hand-maintained. An aggregate view of the detailed tier
    #     is real work and is not this milestone's.
    _assert_one_machine_per_bus(net, "coi_model")
    isempty(net.loads) || throw(ArgumentError(
        "coi_model: the model carries $(length(net.loads)) Load(s) " *
        "($(join([l.id for l in net.loads], ", "))). Folding a voltage-dependent load " *
        "into the aggregate damping constant D is an unvalidated modelling claim, and " *
        "this function is SPEC §3.2's proof that reduced models are derived views. " *
        "Use the detailed tier, or express the load as a machine with negative P0 " *
        "(M2a's convention, which is unchanged)."))
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
