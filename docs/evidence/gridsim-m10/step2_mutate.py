# M10 step 2 sabotages: apply one mutation to double_outages.jl, run the focused M10
# tests, record the summary, restore the original. Usage: python step2_mutate.py [names]
# (no names: all four; e.g. `S4_negative_is_source` runs that one alone).
# Predictions (which testsets go red) are in step2_predictions.md, written first.
# Bytes in, bytes out: `write_text` on Windows would turn the file's LF into CRLF.
import pathlib, subprocess, sys
# The logs carry Unicode (Pkg prints a check mark); the Windows console code page does not.
sys.stdout.reconfigure(encoding="utf-8")
SRC = pathlib.Path(r"W:\Claude_projects\GridSim\src\steadystate\double_outages.jl")
OUT = pathlib.Path(r"W:\temp\claude\m10s2")   # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
orig = SRC.read_bytes().decode("utf-8")
MUT = {
 # S1: every surviving unit of the grid shares each live piece's imbalance.
 "S1_whole_grid_shares": [("alive[q] = piece[r.bus[q]] == c && !(q <= nm && lost[q])",
                           "alive[q] = !(q <= nm && lost[q])")],
 # S2: a surplus treated as a shortfall.
 "S2_surplus_sign": [("        pk = zeros(Float64, length(r.ids))\n",
                      "        imb .= abs.(imb)\n        pk = zeros(Float64, length(r.ids))\n")],
 # S3: a stranded load's import across the cut left out of its neighbour's balance
 # (only where the far piece has a load and no source).
 "S3_stranded_load_kept": [("            ps == pd && continue\n",
   "            ps == pd && continue\n"
   "            dl(c) = !any(k -> piece[r.bus[k]] == c && r.P[k] >= 0.0 && !lost[k], 1:nm) &&\n"
   "                    (any(q -> piece[la.bus[q]] == c, eachindex(la.bus)) ||\n"
   "                     any(k -> piece[r.bus[k]] == c && r.P[k] < 0.0 && !lost[k], 1:nm))\n"
   "            (dl(ps) || dl(pd)) && continue\n")],
 # S4: a P0 < 0 machine counted as a source (still a load too).
 "S4_negative_is_source": [("                    has_load = true\n                    load -= r.P[k]\n",
                            "                    has_load = true\n                    has_src = true\n                    load -= r.P[k]\n")],
}
try:
    for name, reps in MUT.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
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
