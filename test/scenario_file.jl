# The scenario file (`src/model/scenario_file.jl`): a `NetworkModel` round-tripped
# through TOML with the editor's map layout beside it. What is asserted is the
# round trip being exact, the reader going through the ordinary constructors, and
# the writer being unable to silently drop a machine field.

@testset "scenario file: every fixture round-trips bit for bit" begin
    dir = mktempdir()
    for (k, build) in enumerate((two_machine_system, three_machine_ring,
                                 load_bus_system, regulator_bus_system))
        net = build()
        path = joinpath(dir, "fixture_$k.toml")
        @test write_scenario(path, net; name = "fixture $k") == path
        back = read_scenario(path)
        @test back.name == "fixture $k"
        @test back.layout === nothing
        # Immutable structs of Symbols and Float64s compare field for field, so
        # this is the whole record, defaults included — not a sample of it.
        @test back.net.S_base == net.S_base && back.net.f0 == net.f0
        @test back.net.buses == net.buses
        @test back.net.branches == net.branches
        @test back.net.machines == net.machines
        @test back.net.loads == net.loads
    end
end

@testset "scenario file: the writer cannot drop a machine field" begin
    # The field list is named once and the writer walks it. If `Machine` grows a
    # field this test goes red before a file silently stops carrying it.
    @test Set(fieldnames(GridSim.Machine)) ==
          Set((:id, :bus, GridSim._MACHINE_FIELDS...))
    # And the on-disk spelling is ASCII: no key needs quoting in a hand-written file.
    @test all(isascii, values(GridSim._FILE_KEYS))
    @test GridSim._FILE_KEYS[:Xd′] == "Xd_p"
end

@testset "scenario file: Inf survives the file, as TOML's own spelling" begin
    dir = mktempdir()
    path = joinpath(dir, "inf.toml")
    net = three_machine_ring()          # R = Inf, Td0′ = Inf, Efd_max = Inf, Efd_min = -Inf
    write_scenario(path, net)
    text = read(path, String)
    @test occursin("R = +inf", text)
    @test occursin("Efd_min = -inf", text)
    back = read_scenario(path).net
    @test all(m.R == Inf for m in back.machines)
    @test all(m.Efd_min == -Inf for m in back.machines)
end

@testset "scenario file: the layout is a separate return, never a bus field" begin
    dir = mktempdir()
    path = joinpath(dir, "layout.toml")
    net = three_machine_ring()
    layout = Layout(:B1 => (0.0, 1.0), :B2 => (-0.87, -0.5), :B3 => (0.87, -0.5))
    write_scenario(path, net; layout = layout)
    back = read_scenario(path)
    @test back.layout == layout
    @test !(:x in fieldnames(GridSim.Bus))       # SPEC §3.5, structurally
    @test back.net.buses == net.buses

    # A position for a bus the model does not have is an error on BOTH sides.
    bad = Layout(:B9 => (0.0, 0.0))
    @test occursin("B9", argerr_msg(() -> write_scenario(path, net; layout = bad)))
    # Inserted right under the `[layout]` header — appended at the END of the file
    # it would land in the last machine record and be ignored there (it was).
    text = read(path, String)
    @test occursin("[layout]\n", text)
    write(path, replace(text, "[layout]\n" => "[layout]\nB9 = [1.0, 2.0]\n"))
    @test occursin("B9", argerr_msg(() -> read_scenario(path)))

    # Partial layouts are fine: the editor fills in what is missing.
    write_scenario(path, net; layout = Layout(:B1 => (1.0, 1.0)))
    @test read_scenario(path).layout == Layout(:B1 => (1.0, 1.0))
end

@testset "scenario file: a hand-written file defaults the way the constructor does" begin
    dir = mktempdir()
    path = joinpath(dir, "minimal.toml")
    # This IS a pre-M6 file, written out by hand rather than read off disk on
    # purpose (`m6-tasks.md` step 5): the only genuine pre-M6 file the repo had was
    # `docs/scenarios/three-machine-ring.toml`, and step 5 rewrites it through the
    # writer, so a test that read it would stop testing anything the moment it did.
    # It carries the eight classical machine numbers and NOTHING else — no branch
    # `R`, no governor, no detailed reactances, no regulator, no voltage schedule,
    # no reactive limits — plus the one key that is now required.
    write(path, """
        S_base = 100.0
        f0 = 50.0
        slack = "B1"
        [[buses]]
        id = "B1"
        V_base = 400.0
        [[buses]]
        id = "B2"
        V_base = 400.0
        [[branches]]
        id = "L12"
        from = "B1"
        to = "B2"
        X = 0.25
        rating = 500.0
        [[machines]]
        id = "G1"
        bus = "B1"
        S_rated = 250.0
        H = 4.0
        D = 2.0
        Xd_p = 0.25
        E_p = 1.05
        P0 = 60.0
        [[machines]]
        id = "G2"
        bus = "B2"
        S_rated = 400.0
        H = 5.0
        D = 2.0
        Xd_p = 0.30
        E_p = 1.02
        P0 = -60.0
        """)
    back = read_scenario(path)
    @test back.name == ""
    @test back.layout === nothing
    @test back.net.machines == two_machine_system().machines
    @test back.net.branches == two_machine_system().branches
    @test back.net.slack === :B1

    # ...and every default written down HERE as well, not only as "equal to the
    # fixture". D8's whole claim is that each absence has a physical reading, and a
    # comparison against another constructor call would pass just as happily if both
    # sides drifted together — which is the silent reinterpretation of old files the
    # decision exists to prevent. Exact `==`: these are defaults, not computations.
    @test all(br.R == 0.0 for br in back.net.branches)             # a lossless line
    for m in back.net.machines
        @test m.R == Inf                                           # no governor
        @test m.Pmax == m.P0 && m.Tg == 1.0                        # ...so no headroom
        @test m.Xd == m.Xd′ && m.Xq == m.Xd′ && m.Xq′ == m.Xd′     # classical: one X
        @test m.Td0′ == Inf && m.Tq0′ == Inf                       # frozen flux
        @test m.Ra == 0.0
        @test m.K_A == 0.0 && m.T_E == Inf                         # no regulator
        @test m.Efd_min == -Inf && m.Efd_max == Inf                # unlimited field
        @test m.V_set == 1.0                                       # a 1.0 pu schedule
        @test m.Q_min == -Inf && m.Q_max == Inf                    # no reactive limits
    end
end

@testset "scenario file: a file with no slack is refused, and says which buses it could be" begin
    dir = mktempdir()
    path = joinpath(dir, "no_slack.toml")
    net = two_machine_system()
    write_scenario(path, net)
    text = read(path, String)
    @test occursin("slack = \"B1\"\n", text)          # the writer emits it, always
    write(path, replace(text, "slack = \"B1\"\n" => ""))

    msg = argerr_msg(() -> read_scenario(path))
    # Refused, not defaulted — D8's one exception.
    @test occursin("no top-level `slack`", msg)
    # Naming EVERY bus, the way `NetworkModel`'s own slack message does. That a
    # power flow needs a machine at the reference bus is `ac_powerflow`'s rule, and
    # the reader does not teach it: the machine buses appear as a hint in their own
    # sentence, and a bus with no machine is still offered.
    @test occursin("B1", msg) && occursin("B2", msg)
    @test occursin("any bus may be the reference", msg)
    # And the reason, so a hand-editor is not left guessing why this one field alone
    # will not default.
    @test occursin("dispatch", msg)

    # A slack naming a bus that is not there is the CONSTRUCTOR's refusal, not a
    # second one here (M5 D5, one validated path).
    write(path, replace(text, "slack = \"B1\"\n" => "slack = \"B9\"\n"))
    @test occursin("NetworkModel", argerr_msg(() -> read_scenario(path)))

    # The degenerate file — no slack and no buses — has nothing to name and says so
    # rather than offering an empty list.
    empty_path = joinpath(dir, "empty.toml")
    write(empty_path, "S_base = 100.0\nf0 = 50.0\n")
    @test occursin("no buses either", argerr_msg(() -> read_scenario(empty_path)))
end

@testset "scenario file: an invalid file fails where an invalid model does" begin
    dir = mktempdir()
    path = joinpath(dir, "bad.toml")
    net = two_machine_system()
    write_scenario(path, net)
    text = read(path, String)
    # Break the schedule balance in the file: the MODEL's guard is what fires,
    # with the model's own message, because the reader has no second validator.
    # (`Pmax` moves with `P0`, or the headroom guard fires first — it did.)
    @test occursin("P0 = -60.0\n", text) && occursin("Pmax = -60.0\n", text)
    write(path, replace(text, "P0 = -60.0\n" => "P0 = -50.0\n",
                              "Pmax = -60.0\n" => "Pmax = -50.0\n"))
    @test occursin("≠ 0", argerr_msg(() -> read_scenario(path)))
    # A missing field is named with the record it belongs to.
    write(path, replace(text, "S_rated = 400.0\n" => ""))
    msg = argerr_msg(() -> read_scenario(path))
    @test occursin("machine G2", msg) && occursin("S_rated", msg)
    # And a file that is not there says so rather than raising a system error.
    @test occursin("no file", argerr_msg(() -> read_scenario(joinpath(dir, "nope.toml"))))
end
