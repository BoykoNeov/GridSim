import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-oracleb/env")
using PowerSystems, PowerFlows, Logging
global_logger(ConsoleLogger(stderr, Logging.Warn))
mkbus(n, name, t; V = 1.0) = ACBus(; number = n, name = name, available = true,
    bustype = t, angle = 0.0, magnitude = V,
    voltage_limits = (min = 0.5, max = 1.5), base_voltage = 230.0)
mkline(name, b1, b2; r, x) = Line(name = name, available = true, active_power_flow = 0.0,
    reactive_power_flow = 0.0, arc = Arc(from = b1, to = b2), r = r, x = x,
    b = (from = 0.0, to = 0.0), rating = 50.0, angle_limits = (min = -1.5, max = 1.5))
mkgen(name, bus; P, base = 100.0, q = 10.0) = ThermalStandard(name = name,
    available = true, status = true, bus = bus, active_power = P, reactive_power = 0.0,
    rating = 50.0, active_power_limits = (min = -50.0, max = 50.0),
    reactive_power_limits = (min = -q, max = q), ramp_limits = nothing,
    operation_cost = ThermalGenerationCost(nothing), base_power = base,
    time_limits = nothing, prime_mover_type = PrimeMovers.ST, fuel = ThermalFuels.COAL)
pload(name, bus; P, Q) = PowerLoad(name = name, available = true, bus = bus,
    active_power = P, reactive_power = Q, base_power = 100.0,
    max_active_power = 50.0, max_reactive_power = 50.0)

# Arc direction reversed: line declared 2->1, load at 2, gen at 1.
function s2(; arc_rev, tol = nothing, twogens = false)
    s = System(100.0)
    a = mkbus(1, "b1", ACBusTypes.REF); b = mkbus(2, "b2", ACBusTypes.PQ)
    add_components!(s, [a, b])
    add_component!(s, arc_rev ? mkline("l", b, a; r = 0.01, x = 0.10) :
                                mkline("l", a, b; r = 0.01, x = 0.10))
    if twogens
        add_component!(s, mkgen("g1a", a; P = 0.3)); add_component!(s, mkgen("g1b", a; P = 0.2))
    else
        add_component!(s, mkgen("g1", a; P = 0.5))
    end
    add_component!(s, pload("d2", b; P = 0.5, Q = 0.1))
    pf = tol === nothing ? ACPowerFlow() : ACPowerFlow(solver_settings = Dict(:tol => tol))
    return solve_power_flow(pf, s)
end
for rev in (false, true)
    r = s2(; arc_rev = rev)
    println("arc_rev=", rev, "  flow row: ", r["flow_results"].bus_from[1], "->",
            r["flow_results"].bus_to[1], "  P_from_to=", r["flow_results"].P_from_to[1],
            "  P_to_from=", r["flow_results"].P_to_from[1],
            "  P_losses=", r["flow_results"].P_losses[1],
            "  Vm2=", r["bus_results"].Vm[2])
end
println("\n-- tolerance --")
for tol in (nothing, 1e-12)
    r = s2(; arc_rev = false, tol = tol)
    println("tol=", tol, " Vm2=", repr(r["bus_results"].Vm[2]), " θ2=", repr(r["bus_results"].θ[2]))
end
println("\n-- two machines on one bus --")
r = s2(; arc_rev = false, twogens = true)
println("P_gen1=", r["bus_results"].P_gen[1], " Q_gen1=", r["bus_results"].Q_gen[1],
        " Vm2=", repr(r["bus_results"].Vm[2]))
r1 = s2(; arc_rev = false)
println("one machine: P_gen1=", r1["bus_results"].P_gen[1], " Vm2=", repr(r1["bus_results"].Vm[2]))
