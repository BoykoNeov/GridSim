# M7 step 0 spike: do PowerDynamics' inverter components build, initialise and hold
# flat at the current reference manifest? And does the droop inverter (Kq = 0) equal
# Library.Swing with M = τ_p/Kp, D = 1/Kp under a NETWORK-side disturbance?
using PowerDynamics, PowerDynamics.Library, NetworkDynamics, OrdinaryDiffEq

set_Sbase!(100.0); set_fbase!(50.0)

const X = 0.2
const P = 0.5
line() = compile_line(MTKLine(Library.PiLine(; name=:pibranch, R=0.0, X=X,
                        G_src=0.0, B_src=0.0, G_dst=0.0, B_dst=0.0)); src=1, dst=2)

function slackbus()
    b = compile_bus(Library.SlackAlgebraic(; name=:slack); vidx=1)
    set_pfmodel!(b, pfSlack(V=1.0)); b
end

function run(nw, s0; T=3.0, tstep=0.5, dθ=0.1)
    # network-side disturbance: step the slack's voltage angle by dθ at tstep
    aff = ComponentAffect([], [:u_set_r, :u_set_i]) do u, p, ctx
        p[:u_set_r] = cos(dθ); p[:u_set_i] = sin(dθ)
    end
    set_callback!(nw[VIndex(1)], PresetTimeComponentCallback([tstep], aff))
    prob = ODEProblem(nw, uflat(s0), (0.0, T), copy(pflat(s0)))
    solve(prob, Rodas5P(); reltol=1e-10, abstol=1e-10, saveat=0.0:0.01:T)
end

Kp, τp = 0.05, 0.1
println("== (a) IdealDroopInverter, Kq = 0 ==")
droop = Library.IdealDroopInverter(; name=:droop, Kp=Kp, Kq=0.0, τ_p=τp, τ_q=τp)
b2 = compile_bus(MTKBus(droop); vidx=2)
set_pfmodel!(b2, pfPV(P=P, V=1.0))
set_initformula!(b2, @initformula(:droop₊Vset = sqrt(:busbar₊u_r^2 + :busbar₊u_i^2)))
nwA = Network([slackbus(), b2], [line()]; warn_order=false)
s0A = initialize_from_pf(nwA; verbose=false, subverbose=false)
println("  Pset = ", s0A.p.v[2, :droop₊Pset], "  Vset = ", s0A.p.v[2, :droop₊Vset],
        "  δ0 = ", s0A.v[2, :droop₊δ])
println("  flat-run residual |du| = ", maximum(abs, begin du = similar(uflat(s0A)); nwA(du, uflat(s0A), pflat(s0A), 0.0); du end))
solA = run(nwA, s0A)
println("  retcode ", solA.retcode)

println("== (b) Library.Swing, M = τp/Kp, D = 1/Kp ==")
mach = Library.Swing(; name=:mach, V=1.0, M=τp/Kp, D=1/Kp, Pm=P)
b2b = compile_bus(MTKBus(mach); vidx=2)
set_pfmodel!(b2b, pfPV(P=P, V=1.0))
nwB = Network([slackbus(), b2b], [line()]; warn_order=false)
s0B = initialize_from_pf(nwB; verbose=false, subverbose=false)
println("  θ0 = ", s0B.v[2, :mach₊θ], "  Pm = ", s0B.p.v[2, :mach₊Pm])
solB = run(nwB, s0B)
println("  retcode ", solB.retcode)

δA = solA(solA.t; idxs=VIndex(2, :droop₊δ)).u
θB = solB(solB.t; idxs=VIndex(2, :mach₊θ)).u
ωA = solA(solA.t; idxs=VIndex(2, :droop₊ω)).u
ωB = solB(solB.t; idxs=VIndex(2, :mach₊ω)).u
println("  angle swing (max - min) = ", maximum(δA) - minimum(δA))
println("  max |δ_droop − θ_swing| = ", maximum(abs.(δA .- θB)))
println("  max |ω_droop − ω_swing| = ", maximum(abs.(ωA .- ωB)))

println("== (a') anti-vacuity: Kq = 0.05 (voltage droops) ==")
droopq = Library.IdealDroopInverter(; name=:droopq, Kp=Kp, Kq=0.05, τ_p=τp, τ_q=τp)
b2q = compile_bus(MTKBus(droopq); vidx=2)
set_pfmodel!(b2q, pfPV(P=P, V=1.0))
set_initformula!(b2q, @initformula(:droopq₊Vset = sqrt(:busbar₊u_r^2 + :busbar₊u_i^2)))
nwQ = Network([slackbus(), b2q], [line()]; warn_order=false)
s0Q = initialize_from_pf(nwQ; verbose=false, subverbose=false)
solQ = run(nwQ, s0Q)
δQ = solQ(solQ.t; idxs=VIndex(2, :droopq₊δ)).u
println("  max |δ_droopKq − θ_swing| = ", maximum(abs.(δQ .- θB)))

println("== (c) SimpleGFL, PQ injection ==")
gfl = Library.ComposableInverter.SimpleGFL(; name=:gfl)
b2c = compile_bus(MTKBus(gfl); vidx=2)
set_pfmodel!(b2c, pfPQ(P=P, Q=0.0))
nwC = Network([slackbus(), b2c], [line()]; warn_order=false)
s0C = initialize_from_pf(nwC; verbose=false, subverbose=false)
println("  iset_d = ", s0C.p.v[2, :gfl₊iset_d], "  iset_q = ", s0C.p.v[2, :gfl₊iset_q])
du = similar(uflat(s0C)); nwC(du, uflat(s0C), pflat(s0C), 0.0)
println("  flat-run residual |du| = ", maximum(abs, du))
solC = run(nwC, s0C; dθ=0.05)
println("  retcode ", solC.retcode)
fC = solC(solC.t; idxs=VIndex(2, :gfl₊pll₊ω)).u
println("  PLL ω range after slack angle step: ", extrema(fC))
println("  state names: ", NetworkDynamics.sym(nwC[VIndex(2)]))
