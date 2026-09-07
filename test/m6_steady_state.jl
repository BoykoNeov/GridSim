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
