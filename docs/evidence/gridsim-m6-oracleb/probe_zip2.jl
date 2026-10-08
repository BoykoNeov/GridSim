import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
mkbus(n, name, t; V = 1.0) = ACBus(; number = n, name = name, available = true,
    bustype = t, angle = 0.0, magnitude = V, voltage_limits = (min = 0.3, max = 1.7),
    base_voltage = 230.0)
function run(az, ai, ap; P = 2.0, Q = 0.8)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF); b = mkbus(2, "b2", ACBusTypes.PQ)
    add_components!(s, [a, b])
    add_component!(s, Line(name = "l", available = true, active_power_flow = 0.0,
        reactive_power_flow = 0.0, arc = Arc(from = a, to = b), r = 0.0, x = 0.10,
        b = (from = 0.0, to = 0.0), rating = 50.0, angle_limits = (min = -1.5, max = 1.5)))
    add_component!(s, ThermalStandard(name = "g1", available = true, status = true,
        bus = a, active_power = P, reactive_power = 0.0, rating = 50.0,
        active_power_limits = (min = -50.0, max = 50.0),
        reactive_power_limits = (min = -50.0, max = 50.0), ramp_limits = nothing,
        operation_cost = ThermalGenerationCost(nothing), base_power = 100.0,
        time_limits = nothing, prime_mover_type = PrimeMovers.ST, fuel = ThermalFuels.COAL))
    add_component!(s, StandardLoad(name = "d", available = true, bus = b, base_power = 100.0,
        constant_active_power = ap * P, constant_reactive_power = ap * Q,
        impedance_active_power = az * P, impedance_reactive_power = az * Q,
        current_active_power = ai * P, current_reactive_power = ai * Q,
        max_constant_active_power = 50.0, max_constant_reactive_power = 50.0,
        max_impedance_active_power = 50.0, max_impedance_reactive_power = 50.0,
        max_current_active_power = 50.0, max_current_reactive_power = 50.0))
    r = solve_power_flow(ACPowerFlow(solver_settings = Dict(:tol => 1e-12)), s)
    br = r["bus_results"]; V = br.Vm[2]
    Pdel = r["flow_results"].P_to_from[1] |> x -> -x
    println("az=$az ai=$ai ap=$ap  V2=", round(V, digits = 8),
            "  P_delivered=", round(Pdel, digits = 6),
            "  200*(az*V^2+ai*V+ap)=", round(200 * (az * V^2 + ai * V + ap), digits = 6))
end
run(1.0, 0.0, 0.0); run(0.0, 1.0, 0.0); run(0.0, 0.0, 1.0); run(0.5, 0.3, 0.2)
