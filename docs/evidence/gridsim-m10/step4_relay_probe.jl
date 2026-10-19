# M10 step 4, Hurdle 20.2 on the out-of-step relay's path. The relay's affect calls the
# engine's own `inject!(::TripLine)` from inside a solver callback; what is left behind
# when that trip's re-solve is REFUSED, and can the run go on? A refusal is forced by a
# branch rating set between L31's flow at the start and its flow once L12 is out
# (m5_detailed.jl's relay fixture: `governed_ring`, relay on B1–B2 — but G1 ramped UP: ramped
# down, as m5_detailed.jl does, every flow falls after the trip and no rating can refuse it).
# Run before and after the fix; the output says which.
using GridSim
import NetworkDynamics

ring(r31) = let g = governed_ring()
    NetworkModel(g.S_base, g.f0, g.buses,
                 [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0),
                  Branch(:L31, :B3, :B1, 0.25, r31)], g.machines)
end
de(net; kw...) = init!(DetailedEngine, net; dt = 0.01,
                       ramp = [:G1 => GenerationRamp(2.0 / 3.0, 1.0, 3.0)],
                       reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000,
                       out_of_step = [(:B1, :B2) => OutOfStepTrip(0.20; label = :oos)], kw...)
# Sending-end |S| per branch, MVA — what the re-solve's rating check reads.
function mva(eng)
    bt, u = branch_topology(eng.model), eng.integrator.u
    V = [complex(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]]) for v in eachindex(eng.Vre_idx)]
    st = [eng.params[eng.status_pidx[e]] for e in eachindex(eng.model.branches)]
    return GridSim._branch_flows(eng.model, bt, V, st) .* eng.model.S_base
end

net = ring(500.0)
eng = de(net)
println("t = 0      |S| MVA: ", round.(mva(eng); digits = 2))
solve!(eng, (0.0, 30.0))
lg = out_of_step_log(out_of_step_relay(eng, :B1, :B2))
println("relay fired at t = ", lg.t, "; after the run |S| MVA: ", round.(mva(eng); digits = 2))
eng2 = de(net)
solve!(eng2, (0.0, lg.t + 1e-3))
post = mva(eng2)
println("just after the trip |S| MVA: ", round.(post; digits = 2))

r31 = 0.5 * (mva(de(net))[3] + post[3])
println("\n== L31 rated at $r31 MVA (between its start and post-trip flows)")
eng3 = de(ring(r31))
err = try solve!(eng3, (0.0, 30.0)); nothing catch e; e end
println("solve! threw: ", err === nothing ? "nothing" : first(sprint(showerror, err), 160))
lg3 = out_of_step_log(out_of_step_relay(eng3, :B1, :B2))
println("integrator t = ", eng3.integrator.t, "; L12 online: ", is_online(eng3, :B1, :B2),
        "; L12 status param: ", eng3.params[eng3.status_pidx[1]], " / static ",
        eng3.p_static[eng3.sstatus_pidx[1]], "; n_events = ", n_events(eng3))
println("relay log: tripped = ", lg3.tripped, ", t = ", lg3.t, ", armed = ", lg3.armed)
halted = isdefined(eng3, :halted) ? eng3.halted : "(no halt field: before the fix)"
println("halted: ", isempty(halted) ? "no" : first(halted, 80))
# THE MEASUREMENT THAT DECIDES THE HALT: past the refusal, with any halt cleared by hand,
# can the run go on — and to what?
isdefined(eng3, :halted) && (eng3.halted = "")
cont = try solve!(eng3, (eng3.integrator.t, 30.0)); "ran to $(eng3.integrator.t)" catch e
    first(sprint(showerror, e), 200) end
println("continuing solve! (halt cleared by hand): ", cont)
lg3 = out_of_step_log(out_of_step_relay(eng3, :B1, :B2))
println("after: L12 online: ", is_online(eng3, :B1, :B2), "; n_events = ", n_events(eng3),
        "; relay tripped = ", lg3.tripped, ", t = ", lg3.t)
