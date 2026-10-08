import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
mkbus(n, name, t; V = 1.0) = ACBus(; number = n, name = name, available = true,
    bustype = t, angle = 0.0, magnitude = V, voltage_limits = (min = 0.3, max = 1.7),
    base_voltage = 230.0)
mkline(name, b1, b2; r, x) = Line(name = name, available = true, active_power_flow = 0.0,
    reactive_power_flow = 0.0, arc = Arc(from = b1, to = b2), r = r, x = x,
    b = (from = 0.0, to = 0.0), rating = 50.0, angle_limits = (min = -1.5, max = 1.5))
mkgen(name, bus; P) = ThermalStandard(name = name, available = true, status = true,
    bus = bus, active_power = P, reactive_power = 0.0, rating = 50.0,
    active_power_limits = (min = -50.0, max = 50.0), reactive_power_limits = (min = -50.0, max = 50.0),
    ramp_limits = nothing, operation_cost = ThermalGenerationCost(nothing),
    base_power = 100.0, time_limits = nothing, prime_mover_type = PrimeMovers.ST,
    fuel = ThermalFuels.COAL)

# A HEAVILY loaded two-bus case: V lands far from 1.0, so const-P and const-Z differ a lot.
function case(kind; P = 2.0, Q = 0.8)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF); b = mkbus(2, "b2", ACBusTypes.PQ)
    add_components!(s, [a, b]); add_component!(s, mkline("l", a, b; r = 0.0, x = 0.10))
    add_component!(s, mkgen("g1", a; P = P))
    if kind === :P
        add_component!(s, PowerLoad(name = "d", available = true, bus = b,
            active_power = P, reactive_power = Q, base_power = 100.0,
            max_active_power = 50.0, max_reactive_power = 50.0))
    else
        add_component!(s, StandardLoad(name = "d", available = true, bus = b,
            base_power = 100.0,
            constant_active_power = kind === :Z ? 0.0 : P,
            constant_reactive_power = kind === :Z ? 0.0 : Q,
            impedance_active_power = kind === :Z ? P : 0.0,
            impedance_reactive_power = kind === :Z ? Q : 0.0,
            current_active_power = 0.0, current_reactive_power = 0.0,
            max_constant_active_power = 50.0, max_constant_reactive_power = 50.0,
            max_impedance_active_power = 50.0, max_impedance_reactive_power = 50.0,
            max_current_active_power = 50.0, max_current_reactive_power = 50.0))
    end
    r = solve_power_flow(ACPowerFlow(solver_settings = Dict(:tol => 1e-12)), s)
    return r
end
for kind in (:P, :Z, :Pstd)
    r = case(kind)
    br = r["bus_results"]; fr = r["flow_results"]
    println("--- ", kind, " ---")
    println("  Vm = ", br.Vm, "  θ = ", br.θ)
    println("  P_gen = ", br.P_gen, "  Q_gen = ", br.Q_gen)
    println("  P_load = ", br.P_load, " Q_load = ", br.Q_load, " P_net = ", br.P_net)
    println("  flow P_from_to = ", fr.P_from_to[1], "  Q_from_to = ", fr.Q_from_to[1])
end
