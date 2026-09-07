# M6 — the steady-state ladder. Step 1: the fields the ladder needs, added without
# moving a number (docs/plans/m6-plan.md, m6-tasks.md step 1, m6-context.md D3/D4).
#
# THE GATE OF THIS STEP IS AN INVARIANT, NOT A FEATURE, and it is TWO claims:
#
#   (a) every existing test still passes — checked by the rest of this suite;
#   (b) M5's recorded criterion numbers are BIT-IDENTICAL — which the suite cannot
#       check, because M5 asserts them with tolerances and a float can move
#       underneath a passing test. (b) is checked by printing the values at full
#       precision before and after the change and diffing them; the harness and both
#       captures live outside the repo and the result is recorded in `m6-tasks.md`.
#
# WHAT THIS FILE CHECKS is the other half: that the three new pieces of data exist,
# validate, survive every path that carries a model, and are read by NOTHING that
# integrates — so that (a) and (b) are true for a reason rather than by luck.

@testset "M6 step 1 — the fields the ladder needs" begin

# ── Branch.R ────────────────────────────────────────────────────────────────────
@testset "Branch gains R, and every old call site builds the identical object" begin
    plain = Branch(:L1, :A, :B, 0.25, 500.0)
    @test plain.R === 0.0
    # The default is what makes step 1's gate checkable at all: a five-positional
    # call is bit-for-bit the branch it was before the field existed.
    @test plain == Branch(:L1, :A, :B, 0.25, 500.0; R = 0.0)

    lossy = Branch(:L1, :A, :B, 0.25, 500.0; R = 0.02)
    @test lossy.R === 0.02
    @test lossy != plain                       # …and it is a different object

    # `R` is KEYWORD-only: there is no six-positional method, so no existing call
    # can accidentally have supplied it.
    @test_throws MethodError Branch(:L1, :A, :B, 0.25, 500.0, 0.02)

    # `R ≥ 0`, unlike `X > 0`: zero resistance is the ordinary case, not a
    # degenerate one. A negative resistance generates power in the line.
    msg = argerr_msg(() -> Branch(:L1, :A, :B, 0.25, 500.0; R = -0.01))
    @test occursin("R (-0.01)", msg)
    @test occursin("≥ 0", msg)
    # The message disambiguates the two `R`s in this repo, because the scenario
    # file gives them the same key in two different tables.
    @test occursin("governor droop", msg)
end

# ── Machine.V_set / Q_min / Q_max ───────────────────────────────────────────────
@testset "Machine gains the power flow's terminal schedule, defaulted to today" begin
    m = Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0)
    # V_set DEFAULTS TO 1.0 AND NOT TO E′, deliberately. `E′` is the internal
    # voltage behind X′d (or behind Ra + jXq at the detailed tier); `V_set` is the
    # magnitude AT THE BUS. M5 step 8 measured what it costs to let one number serve
    # two denominations — a pre-event tier offset larger than the disturbance it was
    # drawn to show — so the two are separate numbers from the start.
    @test m.V_set === 1.0
    @test m.E′ === 1.05                        # …and they are NOT equal on this machine
    @test m.Q_min === -Inf
    @test m.Q_max === Inf

    # Keyword-only, like every M5 field, so no positional call site moves.
    m2 = Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0;
                 V_set = 1.02, Q_min = -0.4, Q_max = 0.6)
    @test (m2.V_set, m2.Q_min, m2.Q_max) === (1.02, -0.4, 0.6)

    # A voltage MAGNITUDE of zero is a collapsed bus written in as data — which is
    # exactly the spurious basin D6 says the residual cannot tell from the truth.
    @test occursin("collapsed bus",
                   argerr_msg(() -> Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0;
                                            V_set = 0.0)))
    # The limits take Efd_max ≥ Efd_min's form exactly.
    @test occursin("Q_max",
                   argerr_msg(() -> Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0;
                                            Q_min = 0.5, Q_max = 0.2)))
    # Equality is legal: a machine pinned to one reactive output is a real dispatch.
    @test Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0;
                  Q_min = 0.3, Q_max = 0.3).Q_max === 0.3

    # Every fixture in the repo carries the defaults, which is the same claim as
    # "no number moves" said about the data rather than about a run.
    for net in (two_machine_system(), three_machine_ring(), load_bus_system(),
                detailed_pair(), governed_ring())
        @test all(mm -> mm.V_set === 1.0 && mm.Q_min === -Inf && mm.Q_max === Inf,
                  net.machines)
        @test all(br -> br.R === 0.0, net.branches)
    end
end

# ── NetworkModel.slack ──────────────────────────────────────────────────────────
@testset "NetworkModel gains a declared slack BUS, defaulted to the old machine" begin
    net = load_bus_system()
    # The default is `machines[1].bus` AFTER the bus sort — not `buses[1].id`, which
    # since M5 can be a bus carrying no machine at all. On this fixture they happen
    # to coincide; the identity that matters is the one with the machine vector.
    @test net.slack === net.machines[1].bus
    @test net.slack === :B1

    # Declared explicitly, and validated to name a real bus.
    b2 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B2)
    @test b2.slack === :B2
    msg = argerr_msg(() -> NetworkModel(net.S_base, net.f0, net.buses, net.branches,
                                        net.machines, net.loads; slack = :NOPE))
    @test occursin("slack = :NOPE", msg)
    @test occursin("B1", msg) && occursin("B2", msg) && occursin("B3", msg)  # names them

    # THE MODEL DOES NOT REQUIRE THE SLACK TO CARRY A MACHINE. That is a property of
    # the tier that solves, not of the data (m6-context.md D3, and M5 D3's precedent
    # of moving three such guards out of here into `SwingEngine`). `B3` is the load
    # bus, and this must construct.
    b3 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B3)
    @test b3.slack === :B3

    # The keyword form carries it too — there is one validated path, so it must.
    kw = NetworkModel(; S_base = net.S_base, f0 = net.f0, buses = net.buses,
                        branches = net.branches, machines = net.machines,
                        loads = net.loads, slack = :B2)
    @test kw.slack === :B2
end

# ── bus roles, derived ──────────────────────────────────────────────────────────
@testset "bus roles are DERIVED from the slack and what is attached" begin
    net = load_bus_system()                      # B1, B2 carry machines; B3 a load
    @test bus_roles(net) == [:slack, :generator, :load]
    @test bus_role(net, :B1) === :slack
    @test bus_role(net, :B2) === :generator
    @test bus_role(net, :B3) === :load
    # The two forms are one answer, not two.
    @test bus_roles(net) == [bus_role(net, b.id) for b in net.buses]

    # Moving the slack moves exactly one role and derives the rest again — nothing
    # is stored, so nothing can fall out of step.
    b2 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B2)
    @test bus_roles(b2) == [:generator, :slack, :load]
    # The slack wins over what is attached, INCLUDING on a machine-free bus: a
    # declared reference is a dispatch choice and outranks the derivation.
    b3 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B3)
    @test bus_roles(b3) == [:generator, :generator, :slack]

    @test occursin("no bus :NOPE", argerr_msg(() -> bus_role(net, :NOPE)))
end

# ── the five readers of Branch.X, each stated ───────────────────────────────────
@testset "the five readers of Branch.X are DELIBERATELY unchanged by R" begin
    # `Branch.X` is read in five places (m6-plan.md step 1): `branch_arrays`,
    # `SwingEngine`'s edge model, `DetailedEngine`'s static and dynamic edge models,
    # and `branch_power`. Adding `R` beside it is a five-site decision, and on all
    # five the decision is THE SAME: unchanged. Every one of them is lossless by
    # construction — the classical coupling is `E′E′/X` and the detailed edge current
    # is `(Vf − Vt)/(jX)` — so wiring `R` into them is a physics change, which
    # belongs in the step whose gate is not "no number moves".
    #
    # "Deliberately unchanged" is asserted rather than asserted-about: the two views
    # that expose branch data return values that do not depend on `R` at all.
    lossless = load_bus_system()
    lossy = NetworkModel(lossless.S_base, lossless.f0, lossless.buses,
                         [Branch(br.id, br.from, br.to, br.X, br.rating; R = 0.03)
                          for br in lossless.branches],
                         lossless.machines, lossless.loads)
    a, b = branch_topology(lossless), branch_topology(lossy)
    @test a.src == b.src && a.dst == b.dst
    @test all(a.X .=== b.X)                    # `===` on floats: bit equality, not ≈

    ring = three_machine_ring()
    ring_R = NetworkModel(ring.S_base, ring.f0, ring.buses,
                          [Branch(br.id, br.from, br.to, br.X, br.rating; R = 0.03)
                           for br in ring.branches], ring.machines, ring.loads)
    ba, bb = branch_arrays(ring), branch_arrays(ring_R)
    @test all(ba.X .=== bb.X) && all(ba.K .=== bb.K)

    # AND THE ANTI-VACUITY HALF, which is what stops the paragraph above from being
    # a way of saying "nothing reads the field". A model whose branches are lossy is
    # REFUSED by every tier, by name — because a tier that ignored it would silently
    # simulate a lossless network where the data says a lossy one (M5's `Load` ZIP
    # shares, exactly). So setting `R` DOES change what the repo does; what it does
    # not change is any number a run produces, because there is no such run.
    m = argerr_msg(() -> SwingEngine(ring_R; dt = 0.01))
    @test occursin("SwingEngine", m) && occursin("R = 0.03", m) && occursin("L12", m)
    m = argerr_msg(() -> init!(DetailedEngine, lossy; dt = 0.01))
    @test occursin("DetailedEngine", m) && occursin("R = 0.03", m)
    # The guard names the step that lifts it, so a boundary is never read as a bug.
    @test occursin("power flow", m)
end

# ── the promotion: DetailedEngine's private slack now reads the model's ─────────
@testset "DetailedEngine's slack default follows the model's declared bus" begin
    net = load_bus_system()
    # The default is bit-identical to the old `ids[1]`: `NetworkModel` defaults its
    # slack to `machines[1].bus`, so the machine there IS `net.machines[1]`.
    @test machines_at(net, net.slack)[1].id === net.machines[1].id
    eng = init!(DetailedEngine, net; dt = 0.01)
    @test eng.slack === :G1

    # Declaring a different reference bus moves the engine's default with it — the
    # whole point of the promotion (m6-context.md D3).
    b2 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B2)
    @test init!(DetailedEngine, b2; dt = 0.01).slack === :G2

    # THE KEYWORD STILL NAMES A MACHINE, and still outranks the model. Repurposing
    # it to mean a bus would silently reinterpret every existing call site that
    # passes one (`scripts/iberia_two_area.jl` passes `slack = :CE`).
    @test init!(DetailedEngine, b2; dt = 0.01, slack = :G1).slack === :G1
    @test occursin("is not a machine in this model",
                   argerr_msg(() -> init!(DetailedEngine, net; dt = 0.01, slack = :B1)))

    # A declared slack bus carrying no machine is refused HERE, not by the model —
    # the guard is a property of the tier, and it names why.
    b3 = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                      net.loads; slack = :B3)
    msg = argerr_msg(() -> init!(DetailedEngine, b3; dt = 0.01))
    @test occursin("slack bus :B3 carries no machine", msg)
    @test occursin("no rotor angle to pin", msg)
    # …and it is refused only as a DEFAULT: name a machine and the same model runs.
    @test init!(DetailedEngine, b3; dt = 0.01, slack = :G2).slack === :G2
end

# ── the file carries all of it ──────────────────────────────────────────────────
@testset "the scenario file round-trips every new field" begin
    dir = mktempdir()
    path = joinpath(dir, "m6.toml")
    base = load_bus_system()
    net = NetworkModel(base.S_base, base.f0, base.buses,
                       [Branch(br.id, br.from, br.to, br.X, br.rating;
                               R = 0.01 * e) for (e, br) in pairs(base.branches)],
                       [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0;
                                V_set = 1.0 + 0.01 * k, Q_min = -0.5 - k, Q_max = 0.6 + k)
                        for (k, m) in pairs(base.machines)],
                       base.loads; slack = :B2)
    write_scenario(path, net)
    back = read_scenario(path).net
    @test back.branches == net.branches        # R included — struct equality is by field
    @test back.machines == net.machines        # V_set, Q_min, Q_max included
    @test back.slack === :B2

    # The writer emits the new keys explicitly, so a file written after this step
    # leans on no default (the file's own standing rule).
    text = read(path, String)
    @test occursin("slack = \"B2\"", text)
    @test occursin("V_set", text) && occursin("Q_min", text) && occursin("Q_max", text)
    @test occursin("R = 0.01", text)

    # READ-SIDE DEFAULTS (m6-context.md D8): a pre-M6 file says none of this, and
    # each absence must land on the value the absence physically meant — a lossless
    # line, an unlimited machine at a 1.0 pu schedule. The slack's absence has NO
    # such value, which is why D8 makes it the one exception; turning this default
    # into a rejection with a message naming the candidate buses is step 5's box,
    # and until then it defaults so a mid-milestone repo can still read its own files.
    old = replace(text, r"(?m)^slack = .*\n" => "")
    old = replace(old, r"(?m)^ *(R|V_set|Q_min|Q_max) = .*\n" => "")
    write(path, old)
    pre = read_scenario(path).net
    @test all(br -> br.R === 0.0, pre.branches)
    @test all(m -> m.V_set === 1.0 && m.Q_min === -Inf && m.Q_max === Inf, pre.machines)
    @test pre.slack === pre.machines[1].bus
end

end # M6 step 1

# ════════════════════════════════════════════════════════════════════════════════
# M6 step 2 — the linear ("DC") power flow (docs/plans/m6-plan.md, m6-tasks.md).
#
# Two fixtures live here rather than in `src/`, and deliberately: both exist to make
# an ALGEBRAIC prediction checkable, so their numbers are chosen by the check and
# not by any physical scenario. Nothing outside this file needs them.
#
# `_dc_split_case` is the three-bus case whose whole point is that the two paths
# between the ends have DIFFERENT reactances — 0.2 direct against 0.1 + 0.3 = 0.4
# round — so the 2 : 1 split the current divider predicts cannot be a coincidence
# of symmetry. `three_machine_ring` would not do: its three branches are all 0.25,
# and on a symmetric ring a sign or an orientation bug can leave the magnitudes
# untouched. Its middle bus carries neither machine nor load, which makes it a pure
# junction and makes the divider EXACT rather than approximate.

# One injection at `B1`, the matching withdrawal at `B3`, `B2` a bare junction.
# `X13` is a keyword so the positive control can move exactly one reactance and
# nothing else about the model.
function _dc_split_case(; X13 = 0.2, P_MW = 90.0)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    branches = [
        Branch(:L12, :B1, :B2, 0.1, 500.0),
        Branch(:L23, :B2, :B3, 0.3, 500.0),
        Branch(:L13, :B1, :B3, X13, 500.0),
    ]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, P_MW)]
    loads = [Load(:D3, :B3, P_MW, 0.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
end

# A five-bus radial, whose only job is to be a case where the susceptance matrix is
# genuinely sparse: `n + 2m = 13` stored entries out of `n^2 = 25`. On the three-bus
# ring — a complete graph — `n + 2m` is 9 out of 9, so the count is satisfied by a
# DENSE matrix and proves nothing about the rule it is there to check.
function _dc_radial_case()
    buses = [Bus(Symbol("R", k), 400.0) for k in 1:5]
    branches = [Branch(Symbol("L", k), Symbol("R", k), Symbol("R", k + 1), 0.1 * k, 500.0)
                for k in 1:4]
    machines = [Machine(:G1, :R1, 300.0, 4.0, 2.0, 0.30, 1.05, 120.0)]
    loads = [Load(:D4, :R4, 50.0, 0.0), Load(:D5, :R5, 70.0, 0.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :R1)
end

@testset "M6 step 2 — the linear (DC) power flow" begin

# ── the injection vector ────────────────────────────────────────────────────────
@testset "bus_injections: machines minus load, in pu, in vertex order" begin
    net = _dc_split_case()
    P = bus_injections(net)
    @test P == [0.9, 0.0, -0.9]        # 90 MW on a 100 MVA base, and a bare junction
    @test length(P) == length(net.buses)
    # The Σ-balance guard means this is true of every constructible model, which is
    # also why step 2 has NO slack-pickup check: it would assert 0 == 0. Losses get
    # a home in step 3, where the slack picks up a number that is not zero.
    @test sum(P) == 0.0
    @test sum(bus_injections(three_machine_ring())) == 0.0

    # The conversion is `machine_arrays` and `load_arrays`, never a second copy of
    # it: a machine on a different S_rated must not move the injection, because P0
    # is in MW and is never on the machine base. (That weight is the thing which
    # keeps going wrong — M2 and M5 both paid for it.)
    wide = NetworkModel(100.0, 50.0, net.buses, net.branches,
                        [Machine(:G1, :B1, 900.0, 4.0, 2.0, 0.30, 1.05, 90.0)],
                        net.loads; slack = :B1)
    @test bus_injections(wide) == P

    # A ZIP load and its shares do NOT appear: at |V| = 1, which is the whole DC
    # approximation, constant-impedance, constant-current and constant-power all
    # draw P0. That is exact here, not a simplification of it.
    zip = NetworkModel(100.0, 50.0, net.buses, net.branches, net.machines,
                       [Load(:D3, :B3, 90.0, 0.0, 0.0, 0.0, 1.0)];   # a_z, a_i, a_p
                       slack = :B1)
    @test bus_injections(zip) == P
end

# ── the matrix, and the rule this repo has never had to obey in its own code ─────
@testset "the susceptance matrix is sparse structurally, not merely by type" begin
    for net in (three_machine_ring(), _dc_split_case(), _dc_radial_case())
        B = GridSim._dc_susceptance(net)
        n, m = length(net.buses), length(net.branches)
        @test B isa SparseArrays.SparseMatrixCSC{Float64,Int}
        # THE STRUCTURAL CHECK. `n` diagonal entries (every bus carries a branch, or
        # the model is disconnected and rejected) plus `2m` off-diagonal ones with
        # no cancellation, because `Branch` rejects a self-loop and `NetworkModel`
        # rejects a parallel circuit — so every off-diagonal is a single −1/X.
        @test SparseArrays.nnz(B) == n + 2m
        @test B == B'                              # symmetric by construction
        # Singular: angles are relative, so the all-ones vector is in the null
        # space. This is WHY the solve deletes a row and a column rather than
        # factorising B, and it is the property a wrong diagonal would break.
        @test maximum(abs, B * ones(n)) < 1e-12
        # Off-diagonals are −1/X, diagonals the positive sum at the bus.
        for br in net.branches
            i, j = net.bus_index[br.from], net.bus_index[br.to]
            @test B[i, j] == -inv(br.X)
            @test B[j, i] == -inv(br.X)
        end
        @test all(k -> B[k, k] > 0, 1:n)
    end

    # …and on a case where the count can tell dense from sparse. The three-bus ring
    # is a COMPLETE graph, so its 9 stored entries are all 9 of them: the count
    # passes there against a dense matrix and is only evidence on this one.
    radial = _dc_radial_case()
    B = GridSim._dc_susceptance(radial)
    n = length(radial.buses)
    @test SparseArrays.nnz(B) == 13
    @test SparseArrays.nnz(B) < n^2            # 13 < 25 — genuinely sparse
end

# ── two buses: a closed form, and it is a single division ───────────────────────
@testset "two-bus closed form" begin
    net = two_machine_system()                 # +60 MW at B1, −60 at B2, X = 0.25
    sol = dc_powerflow(net)

    @test sol.slack === :B1                    # the declared default of the model
    @test sol.θ[1] === 0.0                     # the reference angle, exactly

    # θ₂ = −P₂ / b = −0.6 / 4. With one unknown the "solve" is one division, so
    # this is EXACT and asserted as such — if a solver change ever makes it
    # inexact, that is a fact worth seeing rather than absorbing into a tolerance.
    @test sol.θ[2] == -0.6 / 4.0
    @test bus_angle(sol, :B2) == sol.θ[2]

    # The flow is the injection: one branch, nowhere else for it to go.
    @test branch_power(sol, :B1, :B2) ≈ 0.6
    @test branch_power(sol, :B1, :B2) == -branch_power(sol, :B2, :B1)
    @test branch_power(sol) == sol.flow
    @test branch_power(sol) !== sol.flow       # a copy, not the live vector
end

# ── three buses: the split is a ratio of reactances, written down ───────────────
#
# `B2` carries nothing, so all 0.9 pu leaving `B1` must reach `B3`, dividing between
# the direct branch and the two-branch path in inverse proportion to their
# reactances: direct : path = (X12 + X23) : X13 = 0.4 : 0.2 = 2 : 1.
@testset "three-bus split is the reactance ratio" begin
    net = _dc_split_case()
    sol = dc_powerflow(net)

    direct = branch_power(sol, :B1, :B3)
    path   = branch_power(sol, :B1, :B2)
    @test direct + path ≈ 0.9                  # everything injected leaves B1
    @test path ≈ branch_power(sol, :B2, :B3)   # …and nothing is lost at the junction

    X12, X23, X13 = 0.1, 0.3, 0.2
    @test direct / path ≈ (X12 + X23) / X13
    @test direct ≈ 0.9 * (X12 + X23) / (X12 + X23 + X13)
    @test path   ≈ 0.9 * X13 / (X12 + X23 + X13)

    # The angle drop is the same over both paths — which is the divider, stated as
    # the loop equation it comes from rather than as a second number.
    @test bus_angle(sol, :B1) - bus_angle(sol, :B3) ≈ direct * X13
    @test bus_angle(sol, :B1) - bus_angle(sol, :B3) ≈ path * (X12 + X23)
end

# ── the positive control: move one reactance, and the split moves as predicted ──
@testset "positive control — the split follows the reactance it is a ratio of" begin
    base = dc_powerflow(_dc_split_case(X13 = 0.2))
    d0 = branch_power(base, :B1, :B3)
    p0 = branch_power(base, :B1, :B2)
    @test d0 > p0                              # the cheap path carries more

    # Double the direct reactance to 0.4 and the two paths are equal: the split must
    # become exactly 50/50, and the DIRECTION of the move is down.
    even = dc_powerflow(_dc_split_case(X13 = 0.4))
    @test branch_power(even, :B1, :B3) ≈ 0.45
    @test branch_power(even, :B1, :B2) ≈ 0.45
    @test branch_power(even, :B1, :B3) < d0    # …and it moved the right way
    @test branch_power(even, :B1, :B2) > p0

    # Make it the expensive path and the ordering reverses: 0.8 against 0.4 is 1 : 2.
    flipped = dc_powerflow(_dc_split_case(X13 = 0.8))
    @test branch_power(flipped, :B1, :B3) ≈ 0.9 * 0.4 / 1.2
    @test branch_power(flipped, :B1, :B3) < branch_power(flipped, :B1, :B2)
end

# ── a radial, where conservation alone fixes every flow ─────────────────────────
#
# On a TREE there is exactly one path between any two buses, so each branch flow is
# determined by the injections downstream of it and by nothing else — not by the
# reactances, not by the slack. That makes this the sharpest closed form in the
# step: the answer is written down from the load list, and it must survive both a
# change of slack and a change of every reactance.
#
# It is also the case with a NON-CONTIGUOUS `keep`. Solving at the interior bus R3
# deletes row and column 3, so the reduced system covers buses [1, 2, 4, 5] and the
# solution has to be scattered back around the hole. That index step is invisible to
# every fixture whose slack sits at an end, and an off-by-one in it is the shape M4
# step 3 caught only with `===`.
@testset "radial — conservation fixes every flow, and the slack sits inside it" begin
    net = _dc_radial_case()                    # R1 injects 120 MW; R4 draws 50, R5 draws 70
    at_end = dc_powerflow(net)

    # Downstream of L1 and L2 sit both loads; downstream of L3 sit both; downstream
    # of L4 sits only R5. In pu on 100 MVA:
    for sol in (at_end,)
        @test branch_power(sol, :R1, :R2) ≈ 1.2
        @test branch_power(sol, :R2, :R3) ≈ 1.2
        @test branch_power(sol, :R3, :R4) ≈ 1.2
        @test branch_power(sol, :R4, :R5) ≈ 0.7
    end

    # The interior slack: `keep` becomes [1, 2, 4, 5], with a hole at 3.
    inside = dc_powerflow(NetworkModel(100.0, 50.0, net.buses, net.branches,
                                       net.machines, net.loads; slack = :R3))
    @test inside.θ[3] === 0.0
    @test inside.flow ≈ at_end.flow            # a tree does not care where the slack is
    @test inside.θ ≈ at_end.θ .- at_end.θ[3]   # …and the angles differ by that offset alone

    # The flows do not care about the reactances either — only the angles do. Scaling
    # every reactance by 3 leaves the flows and multiplies the angle spread by 3,
    # which separates "the solve is right" from "the fixture happens to be uniform".
    stretched = dc_powerflow(
        NetworkModel(100.0, 50.0, net.buses,
                     [Branch(br.id, br.from, br.to, 3 * br.X, br.rating) for br in net.branches],
                     net.machines, net.loads; slack = :R3))
    @test stretched.flow ≈ inside.flow
    @test stretched.θ ≈ 3 .* inside.θ
    @test !(stretched.θ ≈ inside.θ)            # not vacuous: the angles genuinely moved
end

# ── superposition: the property only a LINEAR model has ─────────────────────────
#
# The real discriminator of this step. A nonlinear solve gets the two-bus closed
# form and the reactance ratio right too; only a linear one adds.
#
# THE CONSTRUCTOR SHAPES THIS TEST. `NetworkModel` rejects a model whose scheduled
# injections do not balance, so the two summands cannot be arbitrary halves of the
# whole — each must sum to zero ON ITS OWN. Hence two separate generator/load pairs
# on one shared topology, and a third model carrying both.
@testset "superposition — two injections solved apart sum to the pair together" begin
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    branches = [
        Branch(:L12, :B1, :B2, 0.1, 500.0),
        Branch(:L23, :B2, :B3, 0.3, 500.0),
        Branch(:L13, :B1, :B3, 0.2, 500.0),
    ]
    build(machines, loads) =
        NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)

    G1(P) = Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, P)
    G2(P) = Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03, P)

    a = build([G1(90.0)],            [Load(:D3, :B3, 90.0,  0.0)])
    b = build([G2(60.0)],            [Load(:D3, :B3, 60.0,  0.0)])
    c = build([G1(90.0), G2(60.0)],  [Load(:D3, :B3, 150.0, 0.0)])

    sa, sb, sc = dc_powerflow(a), dc_powerflow(b), dc_powerflow(c)
    @test sa.P .+ sb.P ≈ sc.P                  # the inputs add, which is the premise
    @test sa.θ .+ sb.θ ≈ sc.θ                  # …and so do the answers
    @test sa.flow .+ sb.flow ≈ sc.flow
    # Not vacuous: the three solutions are genuinely different from one another.
    @test !(sa.θ ≈ sb.θ) && !(sa.θ ≈ sc.θ)

    # The three models do NOT agree on bus roles — B2 is a load bus in `a` and a
    # generator bus in `b` and `c` — and the answers add anyway. That is the DC
    # approximation stated as a test: at |V| = 1 with no reactive power, every
    # non-slack bus holds the same thing, and only step 3 makes the roles matter.
    @test bus_role(a, :B2) === :load
    @test bus_role(b, :B2) === :generator
    @test bus_roles(c) == [:slack, :generator, :load]
end

# ── the approximation and its own boundary ──────────────────────────────────────
@testset "R is ignored by design, and the solve does NOT refuse a lossy model" begin
    lossless = _dc_split_case()
    lossy = NetworkModel(100.0, 50.0, lossless.buses,
                         [Branch(br.id, br.from, br.to, br.X, br.rating; R = 0.05)
                          for br in lossless.branches],
                         lossless.machines, lossless.loads; slack = :B1)

    # Every ENGINE refuses this model by name, because a lossy model run at a
    # lossless tier is a different network than its data describes…
    # …and it refuses it for THIS reason, not for some other property of the
    # fixture: asserting only `ArgumentError` here would pass against a model
    # rejected for its bare junction bus.
    @test occursin("series resistance",
                   argerr_msg(() -> init!(DetailedEngine, lossy)))
    # …but the DC power flow is not a tier, it is an APPROXIMATION that states it
    # drops R. Refusing here would refuse exactly the cases step 3 exists for.
    @test dc_powerflow(lossy).θ == dc_powerflow(lossless).θ
    @test dc_powerflow(lossy).flow == dc_powerflow(lossless).flow
end

# ── the slack is a choice, and the angles are stated against it ─────────────────
@testset "the slack pins the reference angle and nothing else" begin
    net = _dc_split_case()
    at_b1 = dc_powerflow(net)
    at_b3 = dc_powerflow(NetworkModel(100.0, 50.0, net.buses, net.branches,
                                      net.machines, net.loads; slack = :B3))

    @test at_b3.slack === :B3
    @test at_b3.θ[3] === 0.0
    @test at_b1.θ != at_b3.θ                   # the angles are stated against it…
    # …but every DIFFERENCE, and therefore every flow, is unchanged: for the ANGLES
    # the slack is a gauge choice. It is not one for the pickup — that is a dispatch
    # choice (M5 D13) — which is why this says "difference" and not "everything".
    @test at_b1.θ .- at_b1.θ[3] ≈ at_b3.θ
    @test at_b1.flow ≈ at_b3.flow
    # The slack may carry no machine at all: the model allows it, and here it is a
    # bare junction. "The slack bus carries a machine" is an ENGINE guard (D3).
    at_junction = dc_powerflow(NetworkModel(100.0, 50.0, net.buses, net.branches,
                                            net.machines, net.loads; slack = :B2))
    @test at_junction.θ[2] === 0.0
    @test at_junction.flow ≈ at_b1.flow
end

# ── the degenerate case, and what the reads do with a name that is not there ────
@testset "one bus, and the rejections" begin
    # A single bus with no branches: the susceptance matrix is 0×0 once the slack
    # row goes, so `n + 2m` does NOT describe it — there are no branches to make the
    # diagonal structurally present. The answer is the reference angle alone.
    solo = NetworkModel(100.0, 50.0, [Bus(:B1, 400.0)], Branch[],
                        [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0)])
    sol = dc_powerflow(solo)
    @test sol.θ == [0.0]
    @test isempty(sol.flow)
    @test SparseArrays.nnz(GridSim._dc_susceptance(solo)) == 0

    ring = dc_powerflow(three_machine_ring())
    @test occursin("no bus :B9", argerr_msg(() -> bus_angle(ring, :B9)))
    @test occursin("no branch", argerr_msg(() -> branch_power(ring, :B1, :B9)))
end

end # M6 step 2
