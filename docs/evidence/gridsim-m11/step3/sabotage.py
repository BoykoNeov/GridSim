# M11 step 3 sabotages: exact string replacements in ext/GridSimOPFExt.jl (each must match the
# stated number of times), plus Ipopt's 120 s CPU limit on every mutant (step 1's lesson).
#   python sabotage.py NAME   (applies to the repo file; restore from sab/GridSimOPFExt.jl.orig)
import sys
P = r"W:\Claude_projects\GridSim\ext\GridSimOPFExt.jl"
LIMIT = ('    JuMP.set_attribute(model, "max_iter", max_iter)\n',
         '    JuMP.set_attribute(model, "max_iter", max_iter)\n    JuMP.set_attribute(model, "max_cpu_time", 120.0)\n', 1)
LOADPOLY = "(prob.load_az[k] * Vv^2 + prob.load_ai[k] * Vv + prob.load_ap[k])"
S = {
  # SA1: every branch's R dropped from the optimiser's copy: y = 1/(jX), g = 0, b = -1/X.
  "SA1": [("f, t, g, b = prob.src[e], prob.dst[e], prob.g[e], prob.b[e]",
           "f, t, g, b = prob.src[e], prob.dst[e], 0.0, (prob.g[e]^2 + prob.b[e]^2) / prob.b[e]", 1)],
  # SA2: ONE ring line's R dropped (L94, the ninth branch).
  "SA2": [("f, t, g, b = prob.src[e], prob.dst[e], prob.g[e], prob.b[e]",
           "f, t, g, b = prob.src[e], prob.dst[e], (e == 9 ? 0.0 : prob.g[e]), (e == 9 ? (prob.g[e]^2 + prob.b[e]^2) / prob.b[e] : prob.b[e])", 1)],
  # SB: the rating at the sending end only.
  "SB": [("            JuMP.@constraint(model, Pt[e]^2 + Qt[e]^2 <= prob.limit[e]^2)\n", "", 1)],
  # SC: the held voltages left free (a variable in the band at every bus).
  "SC": [("for v in 1:n if !held[v])", "for v in 1:n)", 1),
         ("V(v) = held[v] ? prob.V_set[v] : Vfree[v]", "V(v) = Vfree[v]", 1)],
  # SD: every load read as constant power in the optimiser's draw.
  "SD": [(LOADPOLY, "1.0", 2)],
}
name = sys.argv[1]
s = open(P, encoding="utf-8").read()
for a, b, k in [LIMIT] + S[name]:
    assert s.count(a) == k, (name, a, s.count(a))
    s = s.replace(a, b)
open(P, "w", encoding="utf-8", newline="\n").write(s)
print("applied", name)
