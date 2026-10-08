import Pkg; Pkg.activate("W:/temp/claude/gridsim-m6-resolve/b")
using PowerSystems, PowerFlows
sys = System(100.0)
b1 = ACBus(; number=1, name="b1", available=true, bustype=ACBusTypes.REF, angle=0.0,
           magnitude=1.0, voltage_limits=(min=0.9, max=1.1), base_voltage=230.0)
b2 = ACBus(; number=2, name="b2", available=true, bustype=ACBusTypes.PQ, angle=0.0,
           magnitude=1.0, voltage_limits=(min=0.9, max=1.1), base_voltage=230.0)
add_components!(sys, [b1, b2])
add_component!(sys, Line(name="l12", available=true, active_power_flow=0.0,
    reactive_power_flow=0.0, arc=Arc(from=b1, to=b2), r=0.01, x=0.10,
    b=(from=0.0, to=0.0), rating=2.0, angle_limits=(min=-1.5, max=1.5)))
add_component!(sys, ThermalStandard(name="g1", available=true, status=true, bus=b1,
    active_power=0.5, reactive_power=0.0, rating=2.0,
    active_power_limits=(min=0.0, max=2.0), reactive_power_limits=(min=-1.0, max=1.0),
    ramp_limits=nothing, operation_cost=ThermalGenerationCost(nothing),
    base_power=100.0, time_limits=nothing, prime_mover_type=PrimeMovers.ST,
    fuel=ThermalFuels.COAL))
add_component!(sys, PowerLoad(name="d2", available=true, bus=b2, active_power=0.5,
    reactive_power=0.1, base_power=100.0, max_active_power=1.0, max_reactive_power=0.5))
res = solve_power_flow(ACPowerFlow(), sys)
println("SOLVED keys = ", collect(keys(res)))
println(res["bus_results"])
println(res["flow_results"])
dc = solve_power_flow(DCPowerFlow(), sys)
println("DC keys = ", collect(keys(dc)))
println(dc["bus_results"])
