# M10 step 5 sabotages: apply one mutation to the source, run step 5's testset alone
# (step5_run.jl), record the summary, restore the original. Usage: python step5_mutate.py
# [names] (no names: all four). Predictions (which testsets go red) are in
# step5_predictions.md, written before any of these ran.
# Bytes in, bytes out: `write_text` on Windows would turn the files' LF into CRLF.
import pathlib, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
PAIRS = pathlib.Path(r"W:\Claude_projects\GridSim\src\steadystate\double_outages.jl")
OUT = pathlib.Path(r"W:\temp\claude\gridsim-m10-step5\mutations")   # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
orig = {PAIRS: PAIRS.read_bytes().decode("utf-8")}
MUT = {
 # S1: the restore shares by damping as well as gain (DC: the walk handed g + d; AC: the
 # damping kept in the shared solve).
 "S1_damping_shares": [(PAIRS,
   "status, _, pq, cq, fq = _restore_solve(r.g, restore, alive, imb[c])",
   "status, _, pq, cq, fq = _restore_solve(r.g .+ r.d, restore, alive, imb[c])"),
  (PAIRS, "r = merge(r0, (; g, d = d0, h = lim.up))", "r = merge(r0, (; g, d = r0.d, h = lim.up))")],
 # S2: the restore's ceilings ignored.
 "S2_cap_ignored": [(PAIRS,
   "    up = copy(r.h)\n    down = fill(Inf, length(r.ids))\n",
   "    up = fill(Inf, length(r.ids))\n    down = fill(Inf, length(r.ids))\n")],
 # S3: Pmin ignored.
 "S3_pmin_ignored": [(PAIRS,
   "        isnan(mc.Pmin) || (down[k] = max(0.0, mc.P0 - mc.Pmin) / net.S_base)\n", "")],
 # S4: the restore run on the whole grid across a split (DC; the AC restore poses each
 # piece alone, so a whole-grid restore is not expressible there).
 "S4_whole_grid_restore": [(PAIRS,
   "                alive[q] = piece[r.bus[q]] == c && !(q <= nm && lost[q])\n",
   "                alive[q] = (restore !== nothing || piece[r.bus[q]] == c) && !(q <= nm && lost[q])\n")],
 # S5 (added with the dynamic testset, prediction written first): the second loss restored
 # instead of settled, in both sequential screens.
 "S5_second_loss_restored": [(PAIRS,
   "        _, ps2, pk2, cp2, fw2 = _dc_outage_set(cx, out2, lost2)\n",
   "        _, ps2, pk2, cp2, fw2 = _dc_outage_set(cx, out2, lost2; restore = _restore_limits(R, cx.r))\n"),
  (PAIRS, "        _, ps2, pk2, cp2 = _ac_outage_set(cx, out2, lost2)\n",
   "        _, ps2, pk2, cp2 = _ac_outage_set(cx, out2, lost2; restore = _restore_limits(R, cx.r))\n")],
}
try:
    for name, reps in MUT.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        txt = dict(orig)
        for p, a, b in reps:
            assert txt[p].count(a) == 1, (name, a)
            txt[p] = txt[p].replace(a, b)
        for p, t in txt.items():
            p.write_bytes(t.encode("utf-8"))
        log = OUT / f"mut_{name}.txt"
        cmd = (r'start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv '
               r'W:\Claude_projects\GridSim\docs\evidence\gridsim-m10\step5_run.jl > ' + str(log) + ' 2>&1')
        subprocess.run(["cmd", "/c", cmd])
        print("==", name)
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        i = max((j for j, l in enumerate(lines) if l.startswith("Test Summary")), default=None)
        print("\n".join(lines[i:] if i is not None else lines[-15:]))
finally:
    for p, t in orig.items():
        p.write_bytes(t.encode("utf-8"))
print("restored:", all(p.read_bytes().decode("utf-8") == t for p, t in orig.items()))
