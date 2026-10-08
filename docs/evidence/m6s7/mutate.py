import subprocess, sys, shutil
R = r"W:\Claude_projects\GridSim"
ED = R + r"\src\steadystate\economic_dispatch.jl"
EXT = R + r"\ext\GridSimDispatchExt.jl"
M = {
 "M1_linear_sign":   (ED,  "a1   = Float64[m.cost_c1 * S for m in ms]", "a1   = Float64[-m.cost_c1 * S for m in ms]"),
 "M2_swap_c2_c1":    (ED,  "a2   = Float64[m.cost_c2 * S^2 for m in ms],\n              a1   = Float64[m.cost_c1 * S for m in ms]",
                           "a2   = Float64[m.cost_c1 * S^2 for m in ms],\n              a1   = Float64[m.cost_c2 * S for m in ms]"),
 "M3_max_ignored":   (EXT, "prob.pmin[k] <= p[k = 1:n] <= prob.pmax[k]", "p[k = 1:n] >= prob.pmin[k]"),
 "M4_min_ignored":   (EXT, "prob.pmin[k] <= p[k = 1:n] <= prob.pmax[k]", "p[k = 1:n] <= prob.pmax[k]"),
 "M5_perunit_c2":    (ED,  "a2   = Float64[m.cost_c2 * S^2 for m in ms]", "a2   = Float64[m.cost_c2 * S for m in ms]"),
 "M6_load_wrong":    (ED,  "demand = sum(l.P0 for l in net.loads; init = 0.0) / S", "demand = sum(l.Q0 for l in net.loads; init = 0.0) / S"),
}
names = sys.argv[1:] or list(M)
for name in names:
    f, a, b = M[name]
    src = open(f, encoding="utf-8", newline="").read()
    s2 = src.replace("\r\n", "\n")
    assert s2.count(a) == 1, (name, s2.count(a))
    crlf = "\r\n" in src
    mut = s2.replace(a, b)
    if crlf: mut = mut.replace("\n", "\r\n")
    shutil.copy(f, f + ".bak")
    try:
        open(f, "w", encoding="utf-8", newline="").write(mut)
        out = subprocess.run(["julia", r"--project=W:\temp\claude\m6s7\env", r"W:\temp\claude\m6s7\run_ed_tests.jl"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        log = out.stdout + out.stderr
        open(rf"W:\temp\claude\m6s7\mut-{name}.txt", "w", encoding="utf-8").write(log)
        print(f"== {name}: exit {out.returncode}")
    finally:
        shutil.move(f + ".bak", f)
