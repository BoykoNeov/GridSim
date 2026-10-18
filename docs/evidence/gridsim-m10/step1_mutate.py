# M10 step 1 sabotages: apply one mutation to double_outages.jl, run the focused M10
# tests, record the summary, restore the original. Usage: python step1_mutate.py
# Bytes in, bytes out: `write_text` on Windows would turn the file's LF into CRLF.
import pathlib, subprocess
SRC = pathlib.Path(r"W:\Claude_projects\GridSim\src\steadystate\double_outages.jl")
OUT = pathlib.Path(r"W:\temp\claude\m10s1")   # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
orig = SRC.read_bytes().decode("utf-8")
MUT = {
 "S1_transposed": [("a, c = 1.0 - P[k, k], -P[k, l]", "a, c = 1.0 - P[k, k], -P[l, k]"),
                   ("d, e = -P[l, k], 1.0 - P[l, l]", "d, e = -P[k, l], 1.0 - P[l, l]")],
 "S2_diagonal":   [("a, c = 1.0 - P[k, k], -P[k, l]", "a, c = 1.0 - P[k, k], 0.0"),
                   ("d, e = -P[l, k], 1.0 - P[l, l]", "d, e = 0.0, 1.0 - P[l, l]")],
 "S3_wrong_col":  [("post[j] = f[j] + P[j, k] * xk + P[j, l] * xl", "post[j] = f[j] + P[j, k] * xk + P[j, k] * xl")],
 "S4_bridge_cut": [("splits = _pair_cut_mask(net, pairs)", "splits = (br = _bridge_mask(net); [br[k] || br[l] for (k, l) in pairs])")],
}
try:
    for name, reps in MUT.items():
        txt = orig
        for a, b in reps:
            assert txt.count(a) == 1, (name, a)
            txt = txt.replace(a, b)
        SRC.write_bytes(txt.encode("utf-8"))
        log = OUT / f"mut_{name}.txt"
        cmd = (r'start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv '
               r'W:\Claude_projects\GridSim\docs\evidence\gridsim-m10\step1_run.jl > ' + str(log) + ' 2>&1')
        subprocess.run(["cmd", "/c", cmd])
        print("==", name)
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        i = max((j for j, l in enumerate(lines) if l.startswith("Test Summary")), default=None)
        print("\n".join(lines[i:] if i is not None else lines[-15:]))
finally:
    SRC.write_bytes(orig.encode("utf-8"))
print("restored:", SRC.read_bytes().decode("utf-8") == orig)
