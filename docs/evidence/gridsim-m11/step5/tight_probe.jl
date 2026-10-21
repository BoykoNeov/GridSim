using GridSim, Printf
function tight(h)
    ms = [Machine(:G1, :A, 300.0, 5.0, 0.0, 0.25, 1.05, 150.0, 0.05, 150.0 + h, 0.5; V_set = 1.05),
          Machine(:G2, :C, 150.0, 4.0, 0.0, 0.25, 1.04, 60.0, Inf, 100.0, 0.4; V_set = 1.04),
          Machine(:G3, :E, 120.0, 3.5, 0.0, 0.25, 1.02, 40.0, Inf, 45.0, 0.6; V_set = 1.02)]
    br = [Branch(id, f, t, x, 500.0; R = 0.1x) for (id, f, t, x) in
          ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15),
           (:BD, :B, :D, 0.25), (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10), (:BE, :B, :E, 0.20))]
    ls = [Load(:LB, :B, 130.0, 30.0, 0, 0, 1), Load(:LD, :D, 120.0, 25.0, 0, 0, 1)]
    NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms, ls; slack = :A)
end
net = tight(61.0); base = ac_powerflow(net)
@printf("base: G1 output %.4f MW, schedule 150, shift %.4f MW\n", base.Pgen[1]*100, base.Pgen[1]*100 - 150)
for h in (61.0, 62.0, 63.0, 64.0, 64.2, 64.5, 65.0, 66.0)
    a = ac_generator_outages(tight(h))
    k = 2
    out = a.outcome[k] === :reserve_exhausted ? "" : @sprintf(" G1 out after %.4f MW", (a.base.Pgen[1] + a.pickup[k][1]) * 100)
    @printf("h %5.1f: DC %s, AC %s%s\n", h, dc_generator_outages(tight(h)).outcome[k], a.outcome[k], out)
end
# where the AC need lands: lo/hi bisection on h
lo, hi = 61.0, 70.0
let; global lo, hi; for _ in 1:40
    m = (lo + hi) / 2
    ac_generator_outages(tight(m)).outcome[2] === :reserve_exhausted ? (lo = m) : (hi = m)
end
end
@printf("AC settles from h = %.4f MW of schedule reserve (real reserve %.4f MW)\n", hi, hi - (base.Pgen[1]*100 - 150))
