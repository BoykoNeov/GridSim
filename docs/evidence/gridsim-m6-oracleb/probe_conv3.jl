import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows, Logging
const PSY = PowerSystems
global_logger(ConsoleLogger(stderr, Logging.Warn))

mkbus(n, name, t; V = 1.0, ang = 0.0) =
    ACBus(; number = n, name = name, available = true, bustype = t, angle = ang,
          magnitude = V, voltage_limits = (min = 0.5, max = 1.5), base_voltage = 230.0)
mkline(name, b1, b2; r, x) =
    Line(name = name, available = true, active_power_flow = 0.0, reactive_power_flow = 0.0,
         arc = Arc(from = b1, to = b2), r = r, x = x, b = (from = 0.0, to = 0.0),
         rating = 50.0, angle_limits = (min = -1.5, max = 1.5))
mkgen(name, bus; P, Q = 0.0, base = 100.0, qmin = -10.0, qmax = 10.0) =
    ThermalStandard(name = name, available = true, status = true, bus = bus,
        active_power = P, reactive_power = Q, rating = 50.0,
        active_power_limits = (min = -50.0, max = 50.0),
        reactive_power_limits = (min = qmin, max = qmax),
        ramp_limits = nothing, operation_cost = ThermalGenerationCost(nothing),
        base_power = base, time_limits = nothing,
        prime_mover_type = PrimeMovers.ST, fuel = ThermalFuels.COAL)
pload(name, bus; P, Q) = PowerLoad(name = name, available = true, bus = bus,
    active_power = P, reactive_power = Q, base_power = 100.0,
    max_active_power = 50.0, max_reactive_power = 50.0)
zload(name, bus; P, Q) = StandardLoad(name = name, available = true, bus = bus,
    base_power = 100.0,
    constant_active_power = 0.0, constant_reactive_power = 0.0,
    impedance_active_power = P, impedance_reactive_power = Q,
    current_active_power = 0.0, current_reactive_power = 0.0,
    max_constant_active_power = 50.0, max_constant_reactive_power = 50.0,
    max_impedance_active_power = 50.0, max_impedance_reactive_power = 50.0,
    max_current_active_power = 50.0, max_current_reactive_power = 50.0)

function twobus(; r, Pg = 0.5, load, Vref = 1.0, qmax = 10.0, refang = 0.0)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF; V = Vref, ang = refang)
    b = mkbus(2, "b2", ACBusTypes.PQ)
    add_components!(s, [a, b]); add_component!(s, mkline("l12", a, b; r = r, x = 0.10))
    add_component!(s, mkgen("g1", a; P = Pg, qmax = qmax, qmin = -qmax))
    add_component!(s, load(b)); return s
end

println("== Q6: DC — susceptance formula and losses ==")
for r in (0.0, 0.02, 0.05)
    s = twobus(; r = r, load = b -> pload("d2", b; P = 0.5, Q = 0.1))
    dc = solve_power_flow(DCPowerFlow(), s)
    br = dc["1"]["bus_results"]; fr = dc["1"]["flow_results"]
    println("r=", r, "  θ2=", br.θ[2], "  P_from_to=", fr.P_from_to[1],
            "  cols(flow)=", names(fr))
end

println("\n== Q5b: does the AC SOLVE honour constant-impedance loads? ==")
for (tag, ld) in (("PowerLoad(const P)", b -> pload("d2", b; P = 0.5, Q = 0.1)),
                  ("StandardLoad(const Z)", b -> zload("d2", b; P = 0.5, Q = 0.1)))
    s = twobus(; r = 0.0, load = ld)
    ac = solve_power_flow(ACPowerFlow(), s)
    br = ac["bus_results"]
    println(tag, ": Vm2=", br.Vm[2], "  P_load2=", br.P_load[2], "  Q_load2=", br.Q_load[2])
    println("     P_load/V^2 = ", br.P_load[2] / br.Vm[2]^2)
end

println("\n== Q7: reactive limits — off by default, and what ON does ==")
# PV bus at b2 with a tight Q limit, load at b3
function threebus(; qmax, check)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF); b = mkbus(2, "b2", ACBusTypes.PV, V = 1.05)
    c = mkbus(3, "b3", ACBusTypes.PQ)
    add_components!(s, [a, b, c])
    add_component!(s, mkline("l12", a, b; r = 0.0, x = 0.10))
    add_component!(s, mkline("l23", b, c; r = 0.0, x = 0.10))
    add_component!(s, mkgen("g1", a; P = 0.2))
    add_component!(s, mkgen("g2", b; P = 0.8, qmax = qmax, qmin = -qmax))
    add_component!(s, pload("d3", c; P = 1.0, Q = 0.6))
    ac = solve_power_flow(ACPowerFlow(check_reactive_power_limits = check), s)
    return ac["bus_results"]
end
for check in (false, true), qmax in (10.0, 0.25)
    br = threebus(; qmax = qmax, check = check)
    println("check=", check, " qmax=", qmax, " -> Vm2=", br.Vm[2],
            " Q_gen2=", br.Q_gen[2], " Vm3=", br.Vm[3])
end

println("\n== Q10: is the REF bus angle honoured? ==")
for ang in (0.0, 0.3)
    s = twobus(; r = 0.0, load = b -> pload("d2", b; P = 0.5, Q = 0.1), refang = ang)
    br = solve_power_flow(ACPowerFlow(), s)["bus_results"]
    println("ref angle set to ", ang, " -> θ1=", br.θ[1], " θ2=", br.θ[2])
end

println("\n== Q8: solver settings / tolerance ==")
println("solver_settings default = ", ACPowerFlow().solver_settings)
