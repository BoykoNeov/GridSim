# M10 step 3 sabotages: apply one mutation to the source, run the focused M10 tests,
# record the summary, restore the original. Usage: python step3_mutate.py [names]
# (no names: all four). Predictions (which testsets go red) are in step3_predictions.md,
# written first, with a dated correction added before any of these ran.
# Bytes in, bytes out: `write_text` on Windows would turn the files' LF into CRLF.
import pathlib, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
SD = pathlib.Path(r"W:\Claude_projects\GridSim\src\steadystate")
SCREEN, PAIRS = SD / "screening.jl", SD / "double_outages.jl"
OUT = pathlib.Path(r"W:\temp\claude\gridsim-m10s3\mutations")   # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
orig = {p: p.read_bytes().decode("utf-8") for p in (SCREEN, PAIRS)}
MUT = {
 # S1: the slack machine's base output taken as its schedule (the base losses dropped).
 "S1_slack_schedule": [(SCREEN,
   "    lost_at_slack || loc[v_slack] == 0 || (Pbase[loc[v_slack]] = base.Pgen[v_slack])\n",
   "")],
 # S2: only the first lost machine left out of the schedule.
 "S2_first_lost_only": [(SCREEN,
   "    full = _ac_schedule(net; skip_machine = lost)\n",
   "    full = _ac_schedule(net; skip_machine = isempty(lost) ? 0 : lost[1])\n")],
 # S3: the pair's branches left in the admittance before it is cut to the piece.
 "S3_cut_branch_in_Y": [(SCREEN,
   "Y = _ac_admittance(net, out)[vs, vs]",
   "Y = _ac_admittance(net)[vs, vs]")],
 # S4: each piece's pickup vector written whole, a later piece zeroing an earlier one's.
 "S4_pickups_overwritten": [(PAIRS,
   "            for q in eachindex(r.ids)\n                st.alive[q] || continue\n"
   "                pk[q] = o.pickup[q]\n                cp[q] = o.capped[q]\n            end\n",
   "            pk .= o.pickup\n            cp .= o.capped\n")],
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
               r'W:\Claude_projects\GridSim\docs\evidence\gridsim-m10\step1_run.jl > ' + str(log) + ' 2>&1')
        subprocess.run(["cmd", "/c", cmd])
        print("==", name)
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        i = max((j for j, l in enumerate(lines) if l.startswith("Test Summary")), default=None)
        print("\n".join(lines[i:] if i is not None else lines[-15:]))
finally:
    for p, t in orig.items():
        p.write_bytes(t.encode("utf-8"))
print("restored:", all(p.read_bytes().decode("utf-8") == t for p, t in orig.items()))
