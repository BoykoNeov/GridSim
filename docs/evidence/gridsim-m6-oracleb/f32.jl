using GridSim, GridSimReference, Printf, Logging
global_logger(ConsoleLogger(stderr, Logging.Error))
base() = ([Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)])
mk(brs) = ((b, m, l) = base(); NetworkModel(100.0, 50.0, b, brs, m, l; slack = :B1))
# The Float32 twin: each branch's impedance replaced by the one whose ADMITTANCE
# lands on the single-precision grid, which is where their Ybus lives.
f32(br) = (z = 1 / ComplexF32(1 / complex(br.R, br.X));
           Branch(br.id, br.from, br.to, imag(z), br.rating; R = real(z)))
brs = [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)]
exact = mk(brs)
twin  = mk([f32(b) for b in brs])
a = ac_powerflow(exact; abstol = 1e-14)
t = ac_powerflow(twin;  abstol = 1e-14)
o = oracle_powerflow(exact; tol = 1e-12)
@printf("ours(exact)  Vm3=%.17g  θ3=%.17g\n", a.Vm[3], a.θ[3])
@printf("ours(f32twin)Vm3=%.17g  θ3=%.17g\n", t.Vm[3], t.θ[3])
@printf("theirs       Vm3=%.17g  θ3=%.17g\n", o.Vm[3], o.θ[3])
@printf("\n|ours-theirs|      Vm=%.3e  θ=%.3e\n",
        maximum(abs, a.Vm .- o.Vm), maximum(abs, a.θ .- o.θ))
@printf("|ours-f32twin|     Vm=%.3e  θ=%.3e   <- our-side prediction of their error\n",
        maximum(abs, a.Vm .- t.Vm), maximum(abs, a.θ .- t.θ))
@printf("|f32twin-theirs|   Vm=%.3e  θ=%.3e   <- what is LEFT once F32 is accounted for\n",
        maximum(abs, t.Vm .- o.Vm), maximum(abs, t.θ .- o.θ))
