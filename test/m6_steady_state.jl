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

# ════════════════════════════════════════════════════════════════════════════════
# M6 step 3 — the nonlinear ("AC") power flow (docs/plans/m6-plan.md, m6-tasks.md).
#
# The fixtures here, like step 2's, exist to make an ALGEBRAIC prediction checkable
# and their numbers are chosen by the check rather than by any scenario.
#
# TWO OF THEM CARRY CONSTANT-POWER LOADS (`a_p = 1`) WHERE THE REPO'S DEFAULT IS
# CONSTANT IMPEDANCE, and that is not incidental. A `Load` in this repo is a ZIP
# load; the AC solve therefore holds a ZIP *schedule* at a load bus rather than a
# constant complex power, which is what makes step 4's flat run against the DAE tier
# meaningful (m6-context.md D11). Where a check's prediction is the textbook
# power-flow one — a voltage sag that does not relieve itself, an angle that follows
# the DC answer with only the sine truncation between them — the fixture says
# `a_p = 1` so the model is the textbook one and the prediction is about the SOLVER
# rather than about the load model.

# Two buses, the slack holding 1.0 and a generator bus holding 1.05 with a load on
# it. Everything about this case has a closed form (see the testset), which is the
# only reason a two-bus fixture appears at all after step 2's finding that two buses
# are structurally blind: here the point IS the closed form.
function _ac_two_bus(; V_set = 1.05, Q_min = -Inf, Q_max = Inf,
                       X = 0.2, P_L = 50.0, Q_L = 20.0)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    branches = [Branch(:L12, :B1, :B2, X, 500.0)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, P_L),
                Machine(:G2, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0;
                        V_set = V_set, Q_min = Q_min, Q_max = Q_max)]
    loads = [Load(:D2, :B2, P_L, Q_L, 0.0, 0.0, 1.0)]   # constant power
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
end

# The three-bus case the small-angle rate control runs on, scaled by `λ`. Lossless,
# every machine at `V_set = 1.0`, and the one load bus drawing NO reactive power —
# the three conditions the O(λ³) derivation in that testset depends on.
function _ac_rate_case(λ)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.10, 500.0),
                Branch(:L23, :B2, :B3, 0.30, 500.0),
                Branch(:L13, :B1, :B3, 0.20, 500.0)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 60.0 * λ),
                Machine(:G2, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 30.0 * λ)]
    loads = [Load(:D3, :B3, 90.0 * λ, 0.0, 0.0, 0.0, 1.0)]   # constant power, Q = 0
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
end

# The lossy case: step 2's split fixture with resistance on every branch, which is
# the only fixture in the repo where `Branch.R` reaches an equation at all.
function _ac_lossy_case(; R = 0.02)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.10, 500.0; R = R),
                Branch(:L23, :B2, :B3, 0.30, 500.0; R = 3R),
                Branch(:L13, :B1, :B3, 0.20, 500.0; R = 2R)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 90.0)]
    loads = [Load(:D3, :B3, 90.0, 30.0, 0.0, 0.0, 1.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
end

@testset "M6 step 3 — the nonlinear (AC) power flow" begin

# ── the admittance matrix ───────────────────────────────────────────────────────
@testset "the admittance matrix is sparse structurally, and IS the DC one when R = 0" begin
    for net in (three_machine_ring(), _dc_split_case(), _dc_radial_case(), _ac_lossy_case())
        Y = GridSim._ac_admittance(net)
        n, m = length(net.buses), length(net.branches)
        @test Y isa SparseArrays.SparseMatrixCSC{ComplexF64,Int}
        # `n + 2m` for the same three reasons as step 2: no unbranched bus (the model
        # rejects a disconnected network), no self-loop, no parallel circuit — so no
        # off-diagonal is ever a sum and no diagonal is ever structurally absent.
        @test SparseArrays.nnz(Y) == n + 2m
        @test Y == transpose(Y)                     # symmetric, not Hermitian
        # No shunt terms anywhere: with nothing to ground, a uniform voltage draws
        # no current. This is the exact statement `B·1 = 0` is at the DC tier.
        @test maximum(abs, Y * ones(n)) < 1e-12
    end
    # The radial is the one whose count can tell sparse from dense: 13 of 25. On the
    # three-bus ring — a complete graph — `n + 2m` is 9 out of 9 and proves nothing.
    @test SparseArrays.nnz(GridSim._ac_admittance(_dc_radial_case())) == 13
    @test length(_dc_radial_case().buses)^2 == 25

    # A LOSSLESS `Y` IS THE DC `B`. `y = 1/(jX) = −j/X`, so the imaginary part of
    # every entry is the negative of the DC susceptance entry. This is the only check
    # in the file that ties the two assemblies together, and it catches a sign or an
    # orientation slip in either of them.
    #
    # IT IS NOT BITWISE, AND THE REASON IS THE COMPLEX RECIPROCAL RATHER THAN THE
    # MODEL — measured, because `==` was tried first and failed here. Julia computes
    # `inv(complex(0.0, X))` through a scaled division, which returns exactly `-1/X`
    # for some `X` (0.25, 0.3) and one ulp off it for others (0.1, 0.2, 0.4). The
    # real part IS exactly zero in every case, so the two assemblies disagree only in
    # the last bit of a susceptance and only through that reciprocal. The bound is
    # therefore stated in ulps of the largest entry rather than as a tolerance:
    # measured worst case 3.55e-15 against a bound of 1.3e-14.
    for net in (three_machine_ring(), _dc_split_case(), _dc_radial_case())
        Y = GridSim._ac_admittance(net)
        B = GridSim._dc_susceptance(net)
        @test maximum(abs, imag.(Y) + B) <= 4 * eps() * maximum(abs, B)
        @test maximum(abs, real.(Y)) == 0.0         # lossless: no conductance at all
    end
    # ...and it is NOT the DC one once a branch has resistance.
    @test maximum(abs, real.(GridSim._ac_admittance(_ac_lossy_case()))) > 0.0
end

# ── the shape of a solution ─────────────────────────────────────────────────────
@testset "what is held and what is solved" begin
    net = three_machine_ring()          # a machine on every bus, all at V_set = 1.0
    sol = ac_powerflow(net)
    @test sol isa ACPowerFlow
    @test sol.slack === net.slack
    @test sol.buses == Symbol[b.id for b in net.buses]
    @test sol.roles == [:slack, :generator, :generator]
    @test isempty(sol.limited)
    # every bus is a generator bus here, so every magnitude is HELD and exactly its
    # setpoint — not approximately, held
    @test sol.Vm == [1.0, 1.0, 1.0]
    @test sol.θ[1] == 0.0                                    # the slack pins the reference
    @test sol.residual < 1e-10
    # The non-slack machines produce their schedule and the slack produces what is
    # left — and `Pgen` is READ BACK from the solved network (`P_network + P_load`)
    # rather than copied from the schedule, which is why this is `≈` and not `==`.
    # Copying would make the check vacuous; reading it back makes it a check on the
    # solve, at the price of carrying the residual (measured: 4e-16 here).
    ma = machine_arrays(net)
    for v in 2:3
        @test sol.Pgen[v] ≈ ma.Pm[v] atol = 1e-12
    end
    # lossless network, so even the slack's pickup is its schedule to solver precision
    @test sol.Pgen[1] ≈ ma.Pm[1] atol = 1e-12
    @test bus_voltage(sol, :B2) == sol.Vm[2]
    @test bus_angle(sol, :B2) == sol.θ[2]
    @test bus_generation(sol, :B2).P == sol.Pgen[2]
    @test bus_generation(sol, :B2).Q == sol.Qgen[2]
    @test_throws ArgumentError bus_voltage(sol, :nope)
    @test_throws ArgumentError bus_angle(sol, :nope)
    @test_throws ArgumentError bus_generation(sol, :nope)
    @test_throws ArgumentError branch_power(sol, :B1, :nope)

    # A lossless branch delivers what it is given, so the two ends are negatives and
    # the loss is zero. That is the DC contract, recovered here as a special case
    # rather than assumed.
    for br in net.branches
        @test branch_power(sol, br.from, br.to) ≈ -branch_power(sol, br.to, br.from) atol = 1e-12
        @test branch_loss(sol, br.from, br.to) ≈ 0.0 atol = 1e-12
    end
    @test branch_loss(sol) == sol.loss
    @test branch_power(sol) == sol.flow
    @test branch_reactive(sol) == sol.qflow
    # a series reactance ABSORBS reactive power, so both ends send Q into it
    @test branch_reactive(sol, :B1, :B2) + branch_reactive(sol, :B2, :B1) > 0.0
end

# ── the two-bus closed form ─────────────────────────────────────────────────────
@testset "two buses: the angle and the generator's reactive output are closed form" begin
    # Slack at V₁ = 1.0, a generator bus at V₂ = 1.05 whose machine is scheduled at
    # zero and whose load draws P_L + jQ_L (constant power, so the draw does not move
    # with the voltage). With a lossless branch the injection at bus 2 is
    #
    #     P₂ = V₁V₂ sin θ / X          Q₂ = (V₂² − V₁V₂ cos θ) / X
    #
    # and P₂ is known — it is `−P_L`. So θ and then the machine's reactive output
    # Q_gen = Q₂ + Q_L are both written down before the solver runs.
    X, P_L, Q_L, V1, V2 = 0.2, 0.5, 0.2, 1.0, 1.05
    θ_pred = asin(-P_L * X / (V1 * V2))
    Q2_pred = (V2^2 - V1 * V2 * cos(θ_pred)) / X
    Qgen_pred = Q2_pred + Q_L

    net = _ac_two_bus()
    sol = ac_powerflow(net)
    @test sol.roles == [:slack, :generator]
    @test sol.Vm == [1.0, 1.05]
    @test sol.θ[2] ≈ θ_pred atol = 1e-12
    @test bus_generation(sol, :B2).Q ≈ Qgen_pred atol = 1e-12
    @test bus_generation(sol, :B2).P ≈ 0.0 atol = 1e-12   # its schedule
    # and the slack picks up the whole load, because nothing is lost on the way
    @test bus_generation(sol, :B1).P ≈ P_L atol = 1e-12
end

# ── the small-angle rate control (the band is stated BEFORE the gap is seen) ─────
@testset "positive control — the AC angles approach the DC ones at the predicted rate" begin
    # THE BAND, WRITTEN DOWN BEFORE ANY NUMBER IS LOOKED AT, and derived from the
    # truncation order rather than from either solve's convergence (m6-tasks.md).
    #
    # The DC approximation makes three errors against the AC one: it linearises
    # `sin θ ≈ θ`, it holds every magnitude at 1, and it drops Q. On `_ac_rate_case`
    # the second and third are made second-order on purpose — every machine sits at
    # `V_set = 1.0` and the single load bus draws no reactive power, so its magnitude
    # can only deviate through the branches' own `I²X` absorption, which is O(λ²).
    # With θ = O(λ), the sine truncation is O(λ³) and the magnitude term enters the
    # real-power balance as O(λ)·O(λ²) = O(λ³) as well. So
    #
    #     gap(λ) = max|θ_ac − θ_dc| = C·λ³ + O(λ⁵)
    #
    # and HALVING λ must divide the gap by 8. The band is on that ratio, and it is
    # the next order — a relative O(λ²) correction, which is ~1% at λ = 0.4 — that
    # sets its width. Anything outside says the leading error is not cubic, which is
    # a statement about the physics of the fixture, not about a tolerance.
    RATE_LO, RATE_HI = 7.5, 8.5

    λs = [0.4, 0.2, 0.1, 0.05]
    gaps = Float64[]
    for λ in λs
        net = _ac_rate_case(λ)
        ac = ac_powerflow(net)
        dc = dc_powerflow(net)
        push!(gaps, maximum(abs, ac.θ .- dc.θ))
        # the DC answer really is exactly linear in the loading, which is what makes
        # the comparison a statement about the AC solve alone
        @test dc.θ ≈ λ .* dc_powerflow(_ac_rate_case(1.0)).θ rtol = 1e-12
    end
    # THE FLOOR CHECK, and it comes first: a ratio computed from numbers at the
    # solver's own tolerance is arithmetic on noise (M4's lesson). The solve runs at
    # `abstol = 1e-12`, so the smallest gap must clear it by orders.
    @test minimum(gaps) > 1e-10
    ratios = gaps[1:end-1] ./ gaps[2:end]
    @test all(r -> RATE_LO <= r <= RATE_HI, ratios)
    # ...and the gap shrinks monotonically, which a ratio band alone does not say
    @test issorted(gaps; rev = true)

    # THE FIXTURE'S ZERO REACTIVE LOAD IS LOAD-BEARING, AND HERE IS THE MEASUREMENT
    # RATHER THAN THE ARGUMENT. The derivation above gets its cube from the load
    # bus's magnitude deviating only at O(λ²) — which is true because nothing draws
    # reactive power there. Give the same load a `Q₀` that scales with λ and the
    # magnitude deviates at O(λ) instead, the DC assumption `|V| = 1` becomes the
    # leading error, and the rate drops to SQUARE. So the identical check run on an
    # almost identical fixture must land in a DIFFERENT band — which is what makes
    # the 8 above a statement about the physics and not a number that any smooth
    # solve would produce.
    RATE_Q_LO, RATE_Q_HI = 3.5, 4.5
    gapsQ = Float64[]
    for λ in λs
        buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
        branches = [Branch(:L12, :B1, :B2, 0.10, 500.0),
                    Branch(:L23, :B2, :B3, 0.30, 500.0),
                    Branch(:L13, :B1, :B3, 0.20, 500.0)]
        machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 60.0 * λ),
                    Machine(:G2, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 30.0 * λ)]
        loads = [Load(:D3, :B3, 90.0 * λ, 40.0 * λ, 0.0, 0.0, 1.0)]   # …and now Q ≠ 0
        net = NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
        push!(gapsQ, maximum(abs, ac_powerflow(net).θ .- dc_powerflow(net).θ))
    end
    ratiosQ = gapsQ[1:end-1] ./ gapsQ[2:end]
    @test all(r -> RATE_Q_LO <= r <= RATE_Q_HI, ratiosQ)
    @test all(r -> r < RATE_LO, ratiosQ)          # and the two bands do not overlap
end

# ── losses, where R finally reaches an equation ─────────────────────────────────
@testset "losses: the slack's pickup IS the summed branch losses" begin
    net = _ac_lossy_case()
    sol = ac_powerflow(net)
    v_slack = net.bus_index[net.slack]
    @test any(>(0.0), sol.loss)                       # the case is genuinely lossy

    # BOTH SIDES ARE RECOMPUTED HERE FROM DIFFERENT DATA, which is the whole point.
    # The left comes from the model's SCHEDULE (machines) and the ZIP draw at the
    # solved magnitudes, with only the slack's own output taken from the solve. The
    # right comes from `Branch.R`, `Branch.X` and the solved voltages. Neither
    # touches the admittance matrix the residual was built on — so, unlike the
    # identity `ΣP_network = Σlosses` (which holds for ANY Y, right or wrong, and is
    # step 2's superposition finding in reactive form), a dropped or mis-assembled
    # `Y` entry breaks this.
    ma = machine_arrays(net)
    sched = zeros(length(net.buses))
    for k in eachindex(ma.bus)
        sched[ma.bus[k]] += ma.Pm[k]
    end
    for v in eachindex(net.buses)
        v == v_slack && continue
        @test sol.Pgen[v] ≈ sched[v] atol = 1e-12     # a non-slack machine holds its schedule
    end
    gen = sum(v -> v == v_slack ? sol.Pgen[v] : sched[v], eachindex(net.buses))

    # THE ZIP DRAW IS WRITTEN OUT HERE AS THE TEXTBOOK POLYNOMIAL, NOT READ FROM
    # `_zip_scale`. Calling the solver's own scaling function would make this side
    # of the identity a restatement of the other: a load model wrong by a whole
    # power of |V| passed every check in this file except one, precisely because
    # the checks kept reading it from the source they were checking. (Measured —
    # sabotage S4 in `m6-tasks.md`.)
    la = load_arrays(net)
    drawn = 0.0
    for k in eachindex(la.bus)
        v = la.bus[k]
        a_z = 1.0 - la.a_i[k] - la.a_p[k]
        drawn += la.P[k] * (a_z * sol.Vm[v]^2 + la.a_i[k] * sol.Vm[v] + la.a_p[k])
    end

    losses = 0.0
    for br in net.branches
        f, t = net.bus_index[br.from], net.bus_index[br.to]
        Vf = sol.Vm[f] * cis(sol.θ[f])
        Vt = sol.Vm[t] * cis(sol.θ[t])
        I = (Vf - Vt) / complex(br.R, br.X)
        losses += abs2(I) * br.R
    end

    # THE BOUND IS DERIVED, NOT TUNED: each bus equation is satisfied only to the
    # residual the solver achieved, and the identity sums them, so the mismatch is
    # bounded by the number of buses times that residual. Stated this way it says
    # something even when the solve is loose.
    @test abs((gen - drawn) - losses) <= length(net.buses) * max(sol.residual, eps())
    @test losses ≈ sum(sol.loss) atol = 1e-12
    # and the loss really is what the two ends of each branch disagree by
    for (e, br) in pairs(net.branches)
        @test sol.loss[e] ≈ branch_power(sol, br.from, br.to) +
                            branch_power(sol, br.to, br.from) atol = 1e-12
        @test branch_loss(sol, br.from, br.to) == branch_loss(sol, br.to, br.from)  # no direction
    end
    # A LOSSY BRANCH IS THE ONE PLACE THE DC CONTRACT BREAKS, and the difference is
    # not a rounding: the two ends differ by a real number.
    @test branch_power(sol, :B1, :B3) != -branch_power(sol, :B3, :B1)
end

@testset "the ZIP scale IS the textbook polynomial, and the sharing is not cosmetic" begin
    # `_zip_scale` is `|V|² · k(|V|)` with `k` shared bit-for-bit with the DAE tier's
    # `_load_current`. That sharing is the whole point (step 4's flat run), but it
    # also means nothing in this file may check the load model BY CALLING IT. So the
    # model is pinned here against the polynomial it is supposed to be —
    # `a_z|V|² + a_i|V| + a_p` — written out independently.
    for (a_i, a_p) in ((0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (0.3, 0.5), (0.5, 0.25))
        a_z = 1.0 - a_i - a_p
        for Vm in (0.85, 0.95, 1.0, 1.05, 1.2)
            @test GridSim._zip_scale(Vm, a_i, a_p) ≈ a_z * Vm^2 + a_i * Vm + a_p atol = 1e-14
        end
        # `P₀` means "drawn at |V| = 1" for EVERY split — exactly, not nearly, which
        # is what the grouping `1 + a_i(1/V − 1) + a_p(1/V² − 1)` buys over the
        # algebraically equal polynomial.
        @test GridSim._zip_scale(1.0, a_i, a_p) == 1.0
    end
    # ...and the constant-impedance default is `|V|²` with no division taken at all,
    # which is what keeps the DAE tier's hot path bitwise what M5 measured.
    @test GridSim._zip_scale(0.7, 0.0, 0.0) === 0.7 * 0.7
    @test GridSim._zip_k(0.8, 0.0, 0.0) == 1.0
end

# ── reactive limits ─────────────────────────────────────────────────────────────
@testset "reactive limits: wide ones cannot bind, and reproduce the answer EXACTLY" begin
    open_  = ac_powerflow(_ac_two_bus())                                # no limits at all
    wide   = ac_powerflow(_ac_two_bus(Q_min = -50.0, Q_max = 50.0))     # limits, unreachable
    # EXACT, not approximate — and it is a claim about the CODE, not only the test:
    # the first solve is the unlimited solve, and a round in which nothing switches
    # exits without re-solving, so there is no second Newton run to perturb the
    # answer in the last bits.
    @test wide.Vm == open_.Vm
    @test wide.θ == open_.θ
    @test wide.Pgen == open_.Pgen
    @test wide.Qgen == open_.Qgen
    @test isempty(wide.limited)
    @test wide.roles == open_.roles
end

@testset "reactive limits: a case where algebra says the limit MUST bind" begin
    # The unlimited answer's reactive output is the closed form above — 0.4864 pu.
    # So a ceiling of 0.25 is known to bind BEFORE the solve, and a bus held at its
    # ceiling must (a) report exactly that ceiling, (b) stop holding its setpoint,
    # and (c) sag BELOW it, because the reason it was capped is that holding 1.05
    # took more reactive power than it has.
    X, P_L, Q_L, V1, V2 = 0.2, 0.5, 0.2, 1.0, 1.05
    Qgen_unlimited = (V2^2 - V1 * V2 * cos(asin(-P_L * X / (V1 * V2)))) / X + Q_L
    @test Qgen_unlimited > 0.25                       # the premise of the case, checked

    sol = ac_powerflow(_ac_two_bus(Q_max = 0.25))
    @test sol.limited == [:B2]
    @test sol.roles == [:slack, :load]
    @test bus_generation(sol, :B2).Q ≈ 0.25 atol = 1e-9
    @test bus_voltage(sol, :B2) < 1.05
    # the ACTIVE schedule is untouched by a reactive limit (read back from the
    # network, so to the residual — see the note in "what is held and what is solved")
    @test bus_generation(sol, :B2).P ≈ 0.0 atol = 1e-12
    # and a floor set above what the bus wants binds the other way: it is forced to
    # inject MORE reactive power than the setpoint needs, so its voltage rises
    up = ac_powerflow(_ac_two_bus(V_set = 1.0, Q_min = 0.6))
    @test up.limited == [:B2]
    @test bus_generation(up, :B2).Q ≈ 0.6 atol = 1e-9
    @test bus_voltage(up, :B2) > 1.0
end

@testset "reactive limits: EXACTLY the bus algebra names, on a case with two candidates" begin
    # Two generator buses, one load. B3 is held ABOVE its neighbours (1.05 against
    # 1.0) with a lagging load sitting on it, so it must inject strictly positive
    # reactive power — a ceiling of ZERO therefore cannot be met and must bind. B2
    # is given a ceiling it cannot reach. The check is not "something bound", it is
    # "this bus bound and that one did not".
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.10, 500.0),
                Branch(:L23, :B2, :B3, 0.30, 500.0),
                Branch(:L13, :B1, :B3, 0.20, 500.0)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 60.0),
                Machine(:G2, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 30.0;
                        V_set = 1.0, Q_max = 20.0),
                Machine(:G3, :B3, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0;
                        V_set = 1.05, Q_max = 0.0)]
    loads = [Load(:D3, :B3, 90.0, 30.0, 0.0, 0.0, 1.0)]
    net = NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)

    unlimited = ac_powerflow(NetworkModel(100.0, 50.0, buses, branches,
        [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 60.0),
         Machine(:G2, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 30.0; V_set = 1.0),
         Machine(:G3, :B3, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0; V_set = 1.05)],
        loads; slack = :B1))
    # the premise: B3 wants positive Q (so a zero ceiling binds) and B2 wants far
    # less than 20 pu (so its ceiling does not)
    @test bus_generation(unlimited, :B3).Q > 0.0
    @test bus_generation(unlimited, :B2).Q < 20.0

    sol = ac_powerflow(net)
    @test sol.limited == [:B3]
    @test sol.roles == [:slack, :generator, :load]
    @test bus_voltage(sol, :B2) == 1.0                # still held, exactly
    @test bus_voltage(sol, :B3) < 1.05                # let go, and it sagged
    @test bus_generation(sol, :B3).Q ≈ 0.0 atol = 1e-9
end

@testset "reactive limits: back-off is refused by name, not answered wrongly" begin
    # Bind-only switching cannot un-limit a bus, so a bus held at `Q_max` whose
    # magnitude ends up ABOVE its setpoint is a case this solver has no answer for.
    # The guard is unit-tested with a hand-built argument list, the way M5 unit-tests
    # `_check_power_flow` against a hand-built collapsed voltage vector — a guard for
    # a pathology is exactly the guard no fixture reaches by accident.
    net = _ac_two_bus(Q_max = 0.25)
    msg = try
        GridSim._ac_assert_no_backoff(net, [2], [true], [0.0, 0.25], [1.0, 1.10], [1.0, 1.05])
        "NO ERROR THROWN"
    catch e
        e.msg
    end
    @test occursin("B2", msg)
    @test occursin("Back-off is not implemented", msg)
    # ...and the same guard passes the physically sensible side, so it is not
    # simply always-on
    @test GridSim._ac_assert_no_backoff(net, [2], [true], [0.0, 0.25],
                                        [1.0, 1.00], [1.0, 1.05]) === nothing
    # a floor binds the other way round, and the sensible side is then ABOVE
    @test GridSim._ac_assert_no_backoff(net, [2], [false], [0.0, 0.60],
                                        [1.0, 1.02], [1.0, 1.0]) === nothing
    @test_throws ErrorException GridSim._ac_assert_no_backoff(
        net, [2], [false], [0.0, 0.60], [1.0, 0.98], [1.0, 1.0])
    # and the real solves above go through it without tripping it
    @test isempty(ac_powerflow(_ac_two_bus()).limited)
end

# ── the checks that make a converged answer a result ────────────────────────────
@testset "the |V| band REJECTS, and it is the inherited discriminator" begin
    # A load bus drawing 1.0 + j0.6 pu of CONSTANT power through a 0.25 pu reactance
    # sags to the upper root of `V⁴ + V²(2QX − 1) + X²|S|² = 0`, which is 0.737 pu —
    # comfortably below the nose of the curve, so it is a real solution and not a
    # non-existent one. The solve converges; the answer is a
    # real operating point of a network nobody would run; the band is what refuses
    # it. This is the case without which the discriminator is decorative — every
    # other fixture in this file lands comfortably inside [0.9, 1.1].
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.25, 5000.0)]
    machines = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 100.0)]
    loads = [Load(:D2, :B2, 100.0, 60.0, 0.0, 0.0, 1.0)]
    sag = NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
    msg = try
        ac_powerflow(sag)
        "NO ERROR THROWN"
    catch e
        e.msg
    end
    @test occursin("outside", msg)
    @test occursin("TIGHTER residual", msg)          # the reason, not just the rule
    @test occursin("B2", msg)
    # "OUTSIDE" IS NOT ENOUGH, AND THAT IS MEASURED RATHER THAN SUSPECTED: with the
    # reactive residual's sign flipped (sabotage S3) this bus INJECTS 0.6 pu instead
    # of drawing it, floats far ABOVE 1.1, and the band still fires — so the test
    # passed against the bug it was closest to. The magnitude the refusal reports is
    # therefore read out of the message and checked against the closed-form upper
    # root of `V⁴ + V²(2QX − 1) + X²|S|² = 0`, which is a number, on a side.
    V_root = sqrt(((1 - 2 * 0.6 * 0.25) +
                   sqrt((1 - 2 * 0.6 * 0.25)^2 - 4 * 0.25^2 * (1.0^2 + 0.6^2))) / 2)
    @test 0.73 < V_root < 0.74                       # the prediction, before the read
    hit = match(r"\|V\| = ([0-9.eE+-]+) pu", msg)
    @test hit !== nothing
    @test parse(Float64, hit[1]) ≈ V_root atol = 1e-9
    # the SAME network at a tenth of the loading is inside the band and solves
    light = NetworkModel(100.0, 50.0, buses, branches,
                         [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 10.0)],
                         [Load(:D2, :B2, 10.0, 6.0, 0.0, 0.0, 1.0)]; slack = :B1)
    @test ac_powerflow(light) isa ACPowerFlow
end

@testset "the rating check REJECTS, and it reads the heavier end of a lossy branch" begin
    net = _ac_lossy_case()
    @test ac_powerflow(net) isa ACPowerFlow          # it passes at the real ratings
    tight = NetworkModel(net.S_base, net.f0, net.buses,
                         [Branch(br.id, br.from, br.to, br.X, 5.0; R = br.R)
                          for br in net.branches],
                         net.machines, net.loads; slack = net.slack)
    msg = try
        ac_powerflow(tight)
        "NO ERROR THROWN"
    catch e
        e.msg
    end
    @test occursin("against a rating", msg)
end

@testset "the three checks are the M5 ones, split rather than copied" begin
    # M6 step 3 broke `_check_power_flow` into three named pieces so the AC path
    # could run them in the order the M5 docstring already CLAIMED (band, ratings,
    # residual) rather than the order it executed (residual first). The composition
    # must still behave exactly as M5's suite asserts — that is checked over in
    # `test/m5_detailed.jl`; what is checked here is that the pieces exist and are
    # the same ones.
    net = three_machine_ring()
    @test GridSim._check_voltage_band(net, [1.0, 1.0, 1.0], "unit") === nothing
    @test_throws ErrorException GridSim._check_voltage_band(net, [1.0, 0.5, 1.0], "unit")
    @test GridSim._check_branch_ratings(net, zeros(3), "unit") === nothing
    @test_throws ErrorException GridSim._check_branch_ratings(net, fill(100.0, 3), "unit")
    @test GridSim._check_residual(0.0, "unit") === nothing
    @test_throws ErrorException GridSim._check_residual(1.0, "unit")
    # the composition still refuses a collapsed voltage with a perfect residual
    @test_throws ErrorException GridSim._check_power_flow(
        net, ComplexF64[0.389 + 0im, 0.203 + 0im, 0.131 + 0im], zeros(3), 0.0, "unit")
end

# ── what it refuses ─────────────────────────────────────────────────────────────
@testset "the refusals, each by name" begin
    # A slack bus with no machine: NetworkModel accepts it (a half-built editor draft
    # must stay constructible — M5 D3), and the tier that has to put a voltage source
    # there refuses it. Exactly the pattern step 1 established.
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
    machines = [Machine(:G1, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 50.0)]
    loads = [Load(:D1, :B1, 50.0, 10.0)]
    net = NetworkModel(100.0, 50.0, buses, branches, machines, loads; slack = :B1)
    @test bus_role(net, :B1) === :slack               # the model is happy
    err = try; ac_powerflow(net); "NO ERROR"; catch e; e.msg; end
    @test occursin("carries no machine", err)
    @test occursin("B1", err)

    # Two machines on one bus asking for different terminal voltages is a
    # contradiction in the data, not a tie-break.
    two = [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 25.0; V_set = 1.0),
           Machine(:G2, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 25.0; V_set = 1.02)]
    clash = NetworkModel(100.0, 50.0, buses, branches, two,
                         [Load(:D2, :B2, 50.0, 10.0)]; slack = :B1)
    err2 = try; ac_powerflow(clash); "NO ERROR"; catch e; sprint(showerror, e); end
    @test occursin("different", err2)
    @test occursin("V_set", err2)

    # A solve given one iteration cannot have converged, and says so rather than
    # returning where it got to.
    err3 = try
        ac_powerflow(_ac_two_bus(); maxiters = 1)
        "NO ERROR"
    catch e
        sprint(showerror, e)
    end
    @test occursin("does not converge", err3) || occursin("MaxIters", err3)
end

# ── machines on one bus ─────────────────────────────────────────────────────────
@testset "two machines on a bus sum — in P and in both reactive limits" begin
    # `NetworkModel` has expressed more than one machine per bus since M5 step 1 and
    # no engine reads it. The power flow does, so it is checked rather than shipped:
    # splitting a machine in two must change nothing at all.
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    branches = [Branch(:L12, :B1, :B2, 0.2, 500.0)]
    loads = [Load(:D2, :B2, 90.0, 20.0, 0.0, 0.0, 1.0)]
    one = NetworkModel(100.0, 50.0, buses, branches,
        [Machine(:G0, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0),
         Machine(:G1, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 90.0; V_set = 1.02, Q_max = 0.5)],
        loads; slack = :B1)
    split = NetworkModel(100.0, 50.0, buses, branches,
        [Machine(:G0, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0),
         Machine(:G1a, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 45.0; V_set = 1.02, Q_max = 0.25),
         Machine(:G1b, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 45.0; V_set = 1.02, Q_max = 0.25)],
        loads; slack = :B1)
    a, b = ac_powerflow(one), ac_powerflow(split)
    # 45 + 45 and 0.25 + 0.25 are exact in binary, so the two schedules are the same
    # floats and the two answers are the same bits. `≈` here would hide a summation
    # that is merely close.
    @test b.Vm == a.Vm
    @test b.θ == a.θ
    @test b.Pgen == a.Pgen
    @test b.Qgen == a.Qgen
    @test b.limited == a.limited
    # ...and the summed ceiling is what binds, on a case where it does
    tight_one = NetworkModel(100.0, 50.0, buses, branches,
        [Machine(:G0, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0),
         Machine(:G1, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 90.0; V_set = 1.02, Q_max = 0.1)],
        loads; slack = :B1)
    tight_split = NetworkModel(100.0, 50.0, buses, branches,
        [Machine(:G0, :B1, 300.0, 4.0, 2.0, 0.30, 1.05, 0.0),
         Machine(:G1a, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 45.0; V_set = 1.02, Q_max = 0.05),
         Machine(:G1b, :B2, 300.0, 4.0, 2.0, 0.30, 1.05, 45.0; V_set = 1.02, Q_max = 0.05)],
        loads; slack = :B1)
    ta, tb = ac_powerflow(tight_one), ac_powerflow(tight_split)
    @test ta.limited == [:B2]
    @test tb.limited == [:B2]
    @test tb.Vm == ta.Vm
    @test tb.Qgen == ta.Qgen
end

# ── the tier's character ────────────────────────────────────────────────────────
@testset "superposition FAILS here, which is the point" begin
    # Step 2's finding was that superposition catches none of the DC solve's
    # implementation bugs, because a wrong linear map is still linear. The mirror of
    # that statement is worth one testset: the AC solve must NOT superpose, and by a
    # margin far larger than the solver's tolerance. It is the one check that
    # distinguishes the two tiers by their character rather than by their numbers.
    a = ac_powerflow(_ac_rate_case(0.5))
    b = ac_powerflow(_ac_rate_case(1.0))
    # linear would mean θ(2λ) = 2·θ(λ) exactly; the gap is the nonlinearity
    @test maximum(abs, b.θ .- 2 .* a.θ) > 1e-6
    # while the DC solve at the same two loadings superposes to the bit
    da = dc_powerflow(_ac_rate_case(0.5))
    db = dc_powerflow(_ac_rate_case(1.0))
    @test maximum(abs, db.θ .- 2 .* da.θ) < 1e-14
end

@testset "R is READ here, unlike at the DC tier" begin
    # The DC solve ignores `Branch.R` by design and says so. The AC solve is the step
    # `Branch.R` was added for, and this is the check that it actually arrives: the
    # same model with and without resistance must give DIFFERENT answers.
    lossless = _ac_lossy_case(R = 0.0)
    lossy    = _ac_lossy_case(R = 0.02)
    @test dc_powerflow(lossless).θ == dc_powerflow(lossy).θ          # DC: identical
    a, b = ac_powerflow(lossless), ac_powerflow(lossy)
    @test a.θ != b.θ                                                  # AC: not
    @test all(iszero, a.loss)
    @test sum(b.loss) > 1e-4
    # and the slack picks up more when the network loses more
    @test b.Pgen[1] > a.Pgen[1]
end

end   # M6 step 3

# ════════════════════════════════════════════════════════════════════════════════
# M6 step 4, ORACLE A — the power flow back-substituted, and the run that follows
# (docs/plans/m6-plan.md step 4, m6-context.md D5, hurdle 8)
# ════════════════════════════════════════════════════════════════════════════════
#
# THE CHECK. `ac_powerflow` and `DetailedEngine`'s own fixpoint solve answer two
# different questions: the flow fixes terminal conditions (P and |V| at a generator)
# and solves for reactive output; the fixpoint fixes the machine's internal state
# and solves for terminal conditions. The unknowns and the givens swap places (D5).
# Feed the flow's answer into the engine and the run must do NOTHING. Neither solve
# is declared correct — they are made to agree, or one of them is wrong.
#
# AND THEY REALLY ARE DIFFERENT ANSWERS, which is what stops this being a check of a
# thing against itself: on `load_bus_system` the two solves put the bus voltages
# 2.4e-2 to 2.5e-2 pu apart and the rotor-angle differences 6.3e-3 rad apart
# (asserted below). Both are flat.
#
# WHAT THE FLAT RUN IS WORTH, measured by mutation rather than asserted. The full
# table is in `m6-tasks.md` step 4; the two structural facts it establishes are:
#
#   1. A bug in the flow's EQUATIONS is caught — the back-substituted state then
#      fails Kirchhoff on the network the engine integrates, and `init!` refuses at
#      build time with a number.
#   2. A bug in the flow's GENERATION SCHEDULE was BLIND. `Pm` and `Vref` are
#      DERIVED from the solved voltages, so a solution for a schedule nobody asked
#      for back-substitutes into a perfectly good fixpoint and the run is flat at
#      the wrong operating point. Scaling the scheduled P by 1.1 left the run flat
#      to 8.6e-14; misreading `V_set` by 2 % left it flat to 5.1e-13.
#
#      That is what `_assert_seed_is_this_dispatch` exists for, and it is the reason
#      the guard lives in `src/` and not in this file: every seeded `init!` needs
#      it, not only the ones a test writes.
#
#   A LOAD schedule bug, by contrast, was always caught — loads appear in the
#   dynamic network's own algebraic equations, so a wrong load makes the seeded
#   voltages fail Kirchhoff. Generation does not appear there at all. The asymmetry
#   is the mechanism, not a coincidence.
#
# AND NO SINGLE FIXTURE CATCHES THE SET, which is why the sweep below runs four.
# `load_bus_system` is the only one with a `Load`, so it is the only one where the
# load-schedule mutations bite at all; its machines are at the frozen-flux defaults
# (Tq0' = Inf, Xq = Xd'), so a mutation that takes the rotor angle from the bus
# voltage instead of from the internal phasor left it flat to 2.5e-13 — with the
# flux equations frozen, a wrong rotor frame costs nothing. `detailed_pair` catches
# that one (residual 0.68) and has no load at all.

# `load_bus_system` with resistance on one branch. The detailed tier's edge model is
# I = ΔV/(jX) and carries none — and the tier's OWN guard refuses such a model before
# the seeding is reached, which is the finding this fixture ended up recording.
function _seed_lossy_case(; R = 0.02)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    machines = [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0),
                Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.04, 40.0)]
    loads = [Load(:L3, :B3, 110.0, 30.0, 1.0, 0.0, 0.0)]
    branches = [Branch(:L12, :B1, :B2, 0.25, 500.0; R = R),
                Branch(:L23, :B2, :B3, 0.25, 500.0),
                Branch(:L31, :B3, :B1, 0.25, 500.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines, loads)
end

# Two machines on one bus: legal in the model, solvable by the power flow (which sums
# the schedules per bus), unusable by the seeding (one reactive output, and nothing
# says how two machines split it) — and refused by the detailed tier outright, on
# BOTH paths, which is what makes the seeding's assumption safe without a guard.
function _seed_two_on_one_bus()
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0)]
    machines = [Machine(:G1a, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  40.0),
                Machine(:G1b, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  20.0),
                Machine(:G2,  :B2, 400.0, 5.0, 2.0, 0.30, 1.04, -60.0)]
    return NetworkModel(100.0, 50.0, buses, [Branch(:L12, :B1, :B2, 0.25, 500.0)],
                        machines)
end

# A solved answer with one field moved — the only way to hand `init!` a state that
# is not a steady state, since every legitimate route to an `ACPowerFlow` produces
# one that is. Every field is carried through explicitly rather than by a copy-with,
# so a field added to the struct later makes this fail loudly instead of silently
# carrying a stale value (`scenario_file.jl`'s rule, one tier along).
function _seed_bend(sol; Vm = sol.Vm, θ = sol.θ, Pgen = sol.Pgen, Qgen = sol.Qgen,
                    Pload = sol.Pload, Qload = sol.Qload)
    return GridSim.ACPowerFlow(sol.slack, sol.buses, Vm, θ, Pgen, Qgen, Pload, Qload,
                               sol.roles, sol.limited, sol.branches, sol.from, sol.to,
                               sol.flow, sol.flow_rev, sol.qflow, sol.qflow_rev,
                               sol.loss, sol.residual)
end

# Worst drift of any recorded channel from its own first sample.
function _worst_drift(ser)
    worst, chan = 0.0, :none
    for ch in keys(ser)
        ch === :t && continue
        v = getproperty(ser, ch)
        d = maximum(abs, v .- v[1])
        d > worst && ((worst, chan) = (d, ch))
    end
    return worst, chan
end

@testset "M6 step 4 — oracle A: the power flow as the initial condition" begin

# ── the flat run ────────────────────────────────────────────────────────────────
@testset "the seeded run is flat, per state, at two tolerances and forced to step" begin
    # 50 s, not M5's 10: the slowest mode in `detailed_pair` is Td0' = 8 s, and M5's
    # own lesson is that too short a window turns "no movement" into "the last
    # sample". 50 s is six of them.
    #
    # THE THIRD PASS IS NOT A THIRD TOLERANCE. Left to choose its own steps, Rodas5P
    # crosses this horizon in FIVE accepted steps (measured), so 1001 samples are
    # almost all interpolation inside a handful of enormous ones — and what is really
    # being asserted is that an implicit solver parks on an equilibrium, which it
    # does even for equations that are wrong in ways that cancel there. `dtmax`
    # forces real steps. M5 step 1 established this shape; it is reused, not
    # re-argued.
    for (name, net) in (("load_bus",      load_bus_system()),
                        ("load_bus ZIP",  load_bus_system(a_z = 0.4, a_i = 0.35, a_p = 0.25)),
                        ("detailed_pair", detailed_pair()),
                        ("three_ring",    three_machine_ring()))
        sol = ac_powerflow(net)
        for (rtol, atol, T, dtmax, min_steps) in ((1e-3, 1e-6,  50.0, Inf, 0),
                                                  (1e-8, 1e-11, 50.0, Inf, 0),
                                                  (1e-3, 1e-6,  20.0, 0.1, 150))
            eng = init!(DetailedEngine, net; powerflow = sol,
                        reltol = rtol, abstol = atol, dtmax = dtmax)
            ser = solve!(eng, (0.0, T); saveat = 0.05)
            @test length(ser.t) > 100
            @test eng.integrator.stats.naccept >= min_steps
            # 1e-10 is far below every measured value (worst seen: 7.7e-13, on the
            # ZIP case) and far above machine precision — a real gate rather than
            # either a rubber stamp or a flake. Asserted PER STATE and never on
            # `f_coi` alone: a wrong internal state can leave frequency flat while a
            # voltage rings, which is why M5 wrote this channel by channel.
            worst, chan = _worst_drift(ser)
            @test worst < 1e-10
            worst < 1e-10 || @info "seeded flat run drifted" name rtol worst chan
        end
    end
    # …and the lazy pass really is lazy, which is what the comment above rests on.
    let net = three_machine_ring()
        eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net))
        solve!(eng, (0.0, 50.0); saveat = 0.05)
        @test eng.integrator.stats.naccept < 20
    end
end

@testset "the two solves land in DIFFERENT places — this is not a self-comparison" begin
    # If the seeded state and the fixpoint state were the same point, the flat run
    # would be re-testing the fixpoint against itself and every mutation above would
    # be blind for an uninteresting reason. They are not the same point: the flow
    # holds |V| = V_set at the generators and the fixpoint holds |E| = Machine.E',
    # and those pin different things.
    net = load_bus_system()
    a = init!(DetailedEngine, net; powerflow = ac_powerflow(net))   # seeded
    b = init!(DetailedEngine, net)                                  # fixpoint
    ua, ub = a.integrator.u, b.integrator.u
    gapV = maximum(abs(hypot(ua[a.Vre_idx[v]], ua[a.Vim_idx[v]]) -
                       hypot(ub[b.Vre_idx[v]], ub[b.Vim_idx[v]]))
                   for v in eachindex(net.buses))
    @test gapV > 1e-2                       # measured: 2.35e-2 … 2.52e-2
    # Rotor angles compared as DIFFERENCES from the first machine — an individual δ
    # is gauge-arbitrary, and the two paths do not even share a gauge (the fixpoint
    # pins the slack MACHINE's angle at zero, the flow pins the slack BUS's).
    gapδ = maximum(abs((ua[a.δ_idx[k]] - ua[a.δ_idx[1]]) -
                       (ub[b.δ_idx[k]] - ub[b.δ_idx[1]]))
                   for k in eachindex(a.ids))
    @test gapδ > 1e-3                       # measured: 6.29e-3
    # And the slack machine's dispatch differs, because the two operating points
    # draw different power through a voltage-dependent load.
    @test abs(a.params[a.Pm_pidx[1]] - b.params[b.Pm_pidx[1]]) > 1e-3   # measured 5.0e-2
end

@testset "the internal voltage the flow implies is NOT Machine.E' — recorded" begin
    # The companion number to the flat run, and M5 step 8's shape one tier along:
    # `Machine.E'` is the magnitude of the q-axis source at the FIXPOINT's operating
    # point. The flow's operating point has its own, |Ẽ| = |V + (Ra + jXq)·I|, and
    # the seeded path uses that. The gap is real and is not an error.
    for (net, want) in ((load_bus_system(), 2e-2), (detailed_pair(), 1e-2))
        sol = ac_powerflow(net)
        ma = machine_arrays(net)
        V, _, _, I, _ = GridSim._seed_from_powerflow(net, sol, ma)
        gap = maximum(abs(abs(V[ma.bus[k]] + complex(ma.Ra[k], ma.Xq[k]) * I[k]) - ma.E[k])
                      for k in eachindex(ma.bus))
        @test gap > want          # measured: 2.66e-2 (load_bus), 4.95e-2 (detailed_pair)
    end
end

@testset "the flow's own branch power and the engine's agree at R = 0" begin
    # Two code paths over the same solved voltages: `ac_powerflow` builds
    # y = inv(complex(R, X)) and forms V·conj(y·ΔV); `_branch_flows` divides by im*X
    # directly. Narrow — both read the same V and the same X — but it is the one
    # place the two files' orientation and the 1/(jX) rotation are compared.
    # Measured: EXACTLY zero on this build, asserted at 1e-14 because bit-equality of
    # two different complex divisions is not a promise Julia makes.
    for net in (load_bus_system(), three_machine_ring(), detailed_pair())
        sol = ac_powerflow(net)
        ma, bt = machine_arrays(net), branch_topology(net)
        V, _, _, _, _ = GridSim._seed_from_powerflow(net, sol, ma)
        fl = GridSim._branch_flows(net, bt, V, ones(Float64, length(net.branches)))
        for e in eachindex(net.branches)
            @test abs(hypot(sol.flow[e], sol.qflow[e]) - fl[e]) < 1e-14
        end
        # …and the cost of the R = 0 restriction, stated as an assertion rather than
        # left in a comment: on every fixture oracle A can run, the loss channel is
        # zero. NOT `iszero` — measured at −5.6e-17 on one branch, because it is
        # `real(Sf) + real(St)` of two separately-rounded products and not a term
        # that is structurally absent. The lossy case is oracle B's.
        @test maximum(abs, sol.loss) < 1e-15
    end
end

# ── anti-vacuity, in the two halves the plan's single sentence does not survive ──
@testset "anti-vacuity 1: a bent solution is REFUSED at build time, not run" begin
    # The plan says "perturb the solved solution and confirm the run is not flat".
    # It cannot: a perturbed voltage violates the ALGEBRAIC block, so there is no run
    # to be non-flat — `init!` throws. That is a guard test and worth having, and the
    # non-flat run needs a different perturbation (the next testset).
    net = load_bus_system()
    sol = ac_powerflow(net)
    θ = copy(sol.θ); θ[2] += 1e-3          # a non-slack bus, so no schedule moves
    msg = try
        init!(DetailedEngine, net; powerflow = _seed_bend(sol; θ = θ))
        "NO ERROR THROWN"
    catch e
        sprint(showerror, e)
    end
    @test occursin("not a fixpoint of the", msg)
    @test occursin("BACK-SUBSTITUTION", msg)
end

@testset "anti-vacuity 2: the run CAN move — the flat assertion is not free" begin
    # M5's own positive control, on the seeded path: take `Pm` from the schedule
    # instead of from the solve. This is the real failure the back-substitution
    # exists to prevent, and here it is sharper than at M5 — the flow's slack pickup
    # is 0.604 pu against a schedule of 0.700, so the gap is the whole point of
    # deriving `Pm` rather than reading it.
    net = load_bus_system()
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net))
    ma = machine_arrays(net)
    for k in eachindex(eng.Pm_pidx)
        eng.params[eng.Pm_pidx[k]] = ma.Pm[k]
    end
    ser = solve!(eng, (0.0, 20.0); saveat = 0.05)
    worst, _ = _worst_drift(ser)
    @test worst > 1.0
    @test maximum(abs, ser.f_coi .- ser.f_coi[1]) > 1e-2
end

# ── the refusals ────────────────────────────────────────────────────────────────
@testset "the two refusals oracle A thought it needed are UNREACHABLE" begin
    # BOTH guards were written into `_seed_from_powerflow` first, and both turned out
    # to be dead code: `_assert_detailed_tier` refuses these models outright, before
    # `init!` ever reaches the seeding. Recorded as a testset rather than deleted,
    # because the fact that this tier cannot express either model is what makes the
    # seeded path's assumptions safe — and because one of the two messages that was
    # written here was FALSE (it said the fixpoint path handles a multi-machine bus;
    # the fixpoint path refuses it too, which the assertion below pins).

    # A resistive branch. The AC flow's admittance is 1/(R + jX) and this tier's edge
    # is ΔV/(jX), so a seeded state on such a model genuinely would not be a fixpoint
    # — but the tier's own guard fires first, and its message already points at M6.
    msg = argerr_msg(() -> init!(DetailedEngine, _seed_lossy_case();
                                 powerflow = ac_powerflow(_seed_lossy_case())))
    @test occursin("L12", msg)
    @test occursin("series resistance R = 0.02", msg)
    @test occursin("use the M6 power flow, which does read it", msg)
    # It fires on the FIXPOINT path too, which is what makes it the tier's guard and
    # not the seeded path's — the seeded path never sees such a model at all.
    @test occursin("series resistance", argerr_msg(() -> init!(DetailedEngine, _seed_lossy_case())))
    # …and the same model with R = 0 goes through both ways, so the refusal is about
    # the resistance and not about the fixture.
    let ok = _seed_lossy_case(R = 0.0)
        @test init!(DetailedEngine, ok; powerflow = ac_powerflow(ok)) isa DetailedEngine
    end

    # Two machines on one bus. `ac_powerflow` solves such a model happily — it sums
    # the schedules per bus — and the seeded path could not use the answer, because
    # the bus's one reactive output does not say how two machines split it. Moot: the
    # tier refuses the model, on both paths.
    let two = _seed_two_on_one_bus()
        @test ac_powerflow(two) isa ACPowerFlow          # the flow is fine with it
        m2 = argerr_msg(() -> init!(DetailedEngine, two; powerflow = ac_powerflow(two)))
        @test occursin("bus B1 carries 2 machines", m2)
        @test occursin("state count is fixed at compile time", m2)
        # THE CLAIM THAT WOULD HAVE BEEN FALSE, pinned: the fixpoint path does NOT
        # handle this model either.
        @test occursin("bus B1 carries 2 machines", argerr_msg(() -> init!(DetailedEngine, two)))
    end
end

@testset "a DCPowerFlow, or anything else, is named rather than reaching a field" begin
    net = load_bus_system()
    msg = argerr_msg(() -> init!(DetailedEngine, net; powerflow = dc_powerflow(net)))
    @test occursin("must be an ACPowerFlow", msg)
    @test occursin("DCPowerFlow", msg)         # the specific wrong argument, named
    @test occursin("must be an ACPowerFlow",
                   argerr_msg(() -> init!(DetailedEngine, net; powerflow = 1.0)))
end

# ── the dispatch guard: what closed the two blind mutations ─────────────────────
@testset "the solution must be THIS model's dispatch, and all four comparisons fire" begin
    net = load_bus_system()
    sol = ac_powerflow(net)
    seed(s) = argerr_msg(() -> init!(DetailedEngine, net; powerflow = s))

    Pg = copy(sol.Pgen);  Pg[2] += 0.1         # B2 is a non-slack generator bus
    @test occursin("the scheduled P", seed(_seed_bend(sol; Pgen = Pg)))

    Vm = copy(sol.Vm);    Vm[2] += 0.01
    @test occursin("the terminal voltage setpoint", seed(_seed_bend(sol; Vm = Vm)))

    Pl = copy(sol.Pload); Pl[3] *= 1.1         # B3 carries the load
    @test occursin("the load's P draw", seed(_seed_bend(sol; Pload = Pl)))

    Qg = copy(sol.Qgen);  Qg[3] += 0.05        # B3 carries no machine
    @test occursin("the reactive generation", seed(_seed_bend(sol; Qgen = Qg)))

    # Every message says WHY the check exists, because the failure it prevents is
    # invisible: the run would have been flat.
    @test occursin("would be flat", seed(_seed_bend(sol; Pgen = Pg)))

    # The slack's own P is NOT compared — it is the pickup, free by definition and
    # not an input to the solve at all. Pinned so that a later "tighten this" does
    # not add a comparison that must fail. It is not silently accepted either: the
    # bent value reaches the back-substitution and the fixpoint check refuses it.
    Ps = copy(sol.Pgen); Ps[1] += 0.1
    bent = try
        init!(DetailedEngine, net; powerflow = _seed_bend(sol; Pgen = Ps))
        ErrorException("NO ERROR THROWN")
    catch e
        e
    end
    @test occursin("not a fixpoint of the", sprint(showerror, bent))
end

@testset "the id check is WEAK in this repo, and the dispatch check is what catches it" begin
    # `two_machine_system` and `detailed_pair` have the same bus ids, the same branch
    # id and the same slack — so a "is this solution for this model" check written on
    # ids alone passes on a solution for a completely different case. Recorded
    # because it is the sort of thing a reader would assume works.
    a, b = two_machine_system(), detailed_pair()
    @test [x.id for x in a.buses] == [x.id for x in b.buses]
    @test [x.id for x in a.branches] == [x.id for x in b.branches]
    @test a.slack === b.slack
    # It is the DISPATCH comparison that refuses it: G2 is scheduled at −0.6 pu in
    # one and −0.4 in the other.
    msg = argerr_msg(() -> init!(DetailedEngine, b; powerflow = ac_powerflow(a)))
    @test occursin("was not solved for this model's dispatch", msg)
    @test occursin("the scheduled P", msg)
end

@testset "`powerflow = nothing` is the old path, untouched" begin
    # Step 4 changed `_read_static`'s return and moved one `_machine_injection` call.
    # The fixpoint path must be the same engine it was — asserted here as the flat
    # run it has always passed, and by the whole of `m5_detailed.jl` besides.
    eng = init!(DetailedEngine, load_bus_system())
    ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
    worst, _ = _worst_drift(ser)
    @test worst < 1e-10
end

end   # M6 step 4 — oracle A
