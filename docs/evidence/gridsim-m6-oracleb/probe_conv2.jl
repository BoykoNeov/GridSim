import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows
const PSY = PowerSystems

mkbus(n, name, t; V = 1.0, ang = 0.0) =
    ACBus(; number = n, name = name, available = true, bustype = t, angle = ang,
          magnitude = V, voltage_limits = (min = 0.5, max = 1.5), base_voltage = 230.0)
mkline(name, b1, b2; r, x) =
    Line(name = name, available = true, active_power_flow = 0.0, reactive_power_flow = 0.0,
         arc = Arc(from = b1, to = b2), r = r, x = x, b = (from = 0.0, to = 0.0),
         rating = 5.0, angle_limits = (min = -1.5, max = 1.5))
mkgen(name, bus; P, Q = 0.0, base, qmin = -10.0, qmax = 10.0) =
    ThermalStandard(name = name, available = true, status = true, bus = bus,
        active_power = P, reactive_power = Q, rating = 10.0,
        active_power_limits = (min = 0.0, max = 10.0),
        reactive_power_limits = (min = qmin, max = qmax),
        ramp_limits = nothing, operation_cost = ThermalGenerationCost(nothing),
        base_power = base, time_limits = nothing,
        prime_mover_type = PrimeMovers.ST, fuel = ThermalFuels.COAL)

println("== Q2b: constructor unit interpretation, read under each setting ==")
sys = System(100.0)
b1 = mkbus(1, "b1", ACBusTypes.REF); b2 = mkbus(2, "b2", ACBusTypes.PQ)
add_components!(sys, [b1, b2]); add_component!(sys, mkline("l12", b1, b2; r = 0.0, x = 0.10))
g = mkgen("g1", b1; P = 0.4, base = 250.0); add_component!(sys, g)
for u in ("DEVICE_BASE", "SYSTEM_BASE", "NATURAL_UNITS")
    set_units_base_system!(sys, u)
    println("  read under ", u, " -> ", get_active_power(g))
end
set_units_base_system!(sys, "SYSTEM_BASE")

println("\n== Q5: StandardLoad (ZIP) support ==")
println("StandardLoad fields = ", fieldnames(StandardLoad))

println("\n== Q6/Q9: two-bus AC + DC, r=0 and r=0.02 ==")
function twobus(; r, Pg = 0.5, Pd = 0.5, Qd = 0.1, Vref = 1.0, load = :power, qmax = 10.0)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF; V = Vref)
    b = mkbus(2, "b2", ACBusTypes.PQ)
    add_components!(s, [a, b])
    add_component!(s, mkline("l12", a, b; r = r, x = 0.10))
    add_component!(s, mkgen("g1", a; P = Pg, base = 100.0, qmax = qmax, qmin = -qmax))
    if load == :power
        add_component!(s, PowerLoad(name = "d2", available = true, bus = b,
            active_power = Pd, reactive_power = Qd, base_power = 100.0,
            max_active_power = 5.0, max_reactive_power = 5.0))
    else
        add_component!(s, StandardLoad(name = "d2", available = true, bus = b,
            base_power = 100.0,
            constant_active_power = 0.0, constant_reactive_power = 0.0,
            impedance_active_power = Pd, impedance_reactive_power = Qd,
            current_active_power = 0.0, current_reactive_power = 0.0,
            max_constant_active_power = 5.0, max_constant_reactive_power = 5.0,
            max_impedance_active_power = 5.0, max_impedance_reactive_power = 5.0,
            max_current_active_power = 5.0, max_current_reactive_power = 5.0))
    end
    return s
end
for r in (0.0, 0.02)
    s = twobus(; r = r)
    ac = solve_power_flow(ACPowerFlow(), s)
    dc = solve_power_flow(DCPowerFlow(), s)
    println("--- r = ", r, " ---")
    println("AC keys = ", collect(keys(ac)))
    println("AC bus_results:"); show(stdout, ac["bus_results"]); println()
    println("AC flow_results:"); show(stdout, ac["flow_results"]); println()
    println("DC keys = ", collect(keys(dc)))
    println("DC bus_results:"); show(stdout, dc["bus_results"]); println()
    println("DC flow_results:"); show(stdout, dc["flow_results"]); println()
end
