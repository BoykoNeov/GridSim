import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows
const PSY = PowerSystems

println("== Q1: units base ==")
sys = System(100.0)
println("default units base = ", get_units_base(sys))

function mkbus(n, name, t; V = 1.0)
    ACBus(; number = n, name = name, available = true, bustype = t, angle = 0.0,
          magnitude = V, voltage_limits = (min = 0.5, max = 1.5), base_voltage = 230.0)
end
function mkline(name, b1, b2; r, x)
    Line(name = name, available = true, active_power_flow = 0.0, reactive_power_flow = 0.0,
         arc = Arc(from = b1, to = b2), r = r, x = x, b = (from = 0.0, to = 0.0),
         rating = 5.0, angle_limits = (min = -1.5, max = 1.5))
end
function mkgen(name, bus; P, Q = 0.0, base, qmin = -10.0, qmax = 10.0)
    ThermalStandard(name = name, available = true, status = true, bus = bus,
        active_power = P, reactive_power = Q, rating = 10.0,
        active_power_limits = (min = 0.0, max = 10.0),
        reactive_power_limits = (min = qmin, max = qmax),
        ramp_limits = nothing, operation_cost = ThermalGenerationCost(nothing),
        base_power = base, time_limits = nothing,
        prime_mover_type = PrimeMovers.ST, fuel = ThermalFuels.COAL)
end

println("\n== Q2: device base vs system base conversion ==")
# generator rated 250 MVA on a 100 MVA system, 0.4 pu on ITS OWN base = 100 MW = 1.0 pu sys
sys2 = System(100.0)
b1 = mkbus(1, "b1", ACBusTypes.REF); b2 = mkbus(2, "b2", ACBusTypes.PQ)
add_components!(sys2, [b1, b2])
add_component!(sys2, mkline("l12", b1, b2; r = 0.0, x = 0.10))
g = mkgen("g1", b1; P = 0.4, base = 250.0)
add_component!(sys2, g)
add_component!(sys2, PowerLoad(name = "d2", available = true, bus = b2,
    active_power = 0.5, reactive_power = 0.1, base_power = 100.0,
    max_active_power = 5.0, max_reactive_power = 5.0))
println("DEVICE_BASE get_active_power(g) = ", get_active_power(g))
set_units_base_system!(sys2, "SYSTEM_BASE")
println("SYSTEM_BASE get_active_power(g) = ", get_active_power(g))
set_units_base_system!(sys2, "NATURAL_UNITS")
println("NATURAL_UNITS get_active_power(g) = ", get_active_power(g))
set_units_base_system!(sys2, "DEVICE_BASE")

println("\n== Q3: line r/x base ==")
ln = get_component(Line, sys2, "l12")
for u in ("DEVICE_BASE", "SYSTEM_BASE", "NATURAL_UNITS")
    set_units_base_system!(sys2, u)
    println(u, " line x = ", get_x(ln), "  r = ", get_r(ln))
end
set_units_base_system!(sys2, "SYSTEM_BASE")

println("\n== Q4: ACPowerFlow keywords / defaults ==")
println("ACPowerFlow fieldnames = ", fieldnames(typeof(ACPowerFlow())))
println("ACPowerFlow() = ", ACPowerFlow())
println("DCPowerFlow() = ", DCPowerFlow())
try
    println("methods(solve_power_flow):"); show(stdout, methods(solve_power_flow)); println()
catch e; println("no solve_power_flow: ", e); end
