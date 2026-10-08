# M7 step 7 — sabotages of the source trip, each with its PREDICTION written before the run.
import subprocess, shutil, sys
R = r"W:\Claude_projects\GridSim"
D = "src/engines/detailed.jl"
muts = {
 # predicted RED: the tripped bus draws -V/(jX′d) — "exports NOTHING" in the closed-form
 # loop (G1, G2) and the dead machine's injection in the machine testset.
 "T7-1 the E = 0 shortcut instead of a status": [(D,
   "        p[eng.mstat_pidx[k]]   = 0.0\n        ps[eng.smstat_pidx[k]] = 0.0\n",
   "        u[eng.E′q_idx[k]] = 0.0\n        u[eng.E′d_idx[k]] = 0.0\n")],
 # predicted RED: the closed form (H_post) and Σw, machine cases.
 "T7-2 a machine's weight not removed": [(D,
   "        eng.w[k] = 0.0\n", "")],
 # predicted RED: the new dynamic-KCL check throws on every machine trip.
 "T7-3 the static network's machine status not zeroed": [(D,
   "        ps[eng.smstat_pidx[k]] = 0.0\n", "")],
 # predicted RED: the dynamic-KCL check throws on the grid-following trip.
 "T7-4 grid-following setpoint zeroed on the dynamic side only": [(D,
   "        ps[h.sid_pidx[f]] = 0.0\n        ps[h.siq_pidx[f]] = 0.0\n", "")],
 # predicted RED, and ONLY through the dead rotor's own speed channel (plus the
 # parameter read-back, which does not count): no current flows and the weight is zero.
 "T7-5 Pm left on a tripped machine": [(D,
   "        p[eng.Pm_pidx[k]]      = 0.0\n", "")],
 # predicted RED: the idle inverter's droop speed settles at K_p·P_set, not zero.
 "T7-6 grid-forming setpoint left in place": [(D,
   "        p[g.Pset_pidx[j]]   = 0.0\n", "")],
 # predicted RED: the dynamic-KCL check (static zeroed, dynamic still injecting).
 "T7-7 grid-forming status ignored by the dynamic vertex": [(D,
   "    Ire, Iim, P, Q = istat * Ire, istat * Iim, istat * P, istat * Q\n", "")],
 # predicted RED: the relay test.
 "T7-8 relays at the tripped bus not disarmed": [(D,
   "    for r in eng.relays\n        (r.from === bus || r.to === bus) && disarm!(r)\n    end\n    eng.Σw = isempty",
   "    eng.Σw = isempty")],
 # predicted RED: the snapshot comparison ("nothing was changed").
 "T7-9 the last-source guard after the unit is taken out": [(D,
   "    id in eng.online || return nothing\n    # Refused BEFORE",
   "    id in eng.online || return nothing\n    delete!(eng.online, id)\n    # Refused BEFORE")],
}
only = sys.argv[1:]
for name, edits in muts.items():
    if only and not any(name.startswith(o) for o in only):
        continue
    files = sorted({f for f, _, _ in edits})
    for f in files:
        shutil.copy(R + "\\" + f, R + "\\" + f + ".bak")
    try:
        for f, a, b in edits:
            p = R + "\\" + f
            s = open(p, encoding="utf-8").read()
            assert s.count(a) == 1, (name, a[:60], s.count(a))
            open(p, "w", encoding="utf-8", newline="\n").write(s.replace(a, b))
        out = subprocess.run(["julia", "--project=W:/temp/claude/m7/testenv",
                              "W:/temp/claude/m7/step7/run_trip.jl"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        txt = out.stdout + out.stderr
        red = ("Fail" in txt) or ("Error" in txt)
        print("==", name, "| red" if red else "| GREEN (vacuous!)", flush=True)
        for l in txt.splitlines():
            if "Test Summary" in l or ("M7 step 7" in l and ("Fail" in l or "Error" in l)):
                print("   ", l.strip()[:150], flush=True)
        seen = 0
        lines = txt.splitlines()
        for i, l in enumerate(lines):
            if ("Test Failed" in l or "Error During Test" in l) and seen < 8:
                ctx = " | ".join(x.strip() for x in lines[i:i + 3])
                print("      ", ctx[:230], flush=True)
                seen += 1
    finally:
        for f in files:
            shutil.move(R + "\\" + f + ".bak", R + "\\" + f)
