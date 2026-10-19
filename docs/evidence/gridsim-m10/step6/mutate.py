# M10 step 6 sabotages: apply one mutation, run the runner it names, record the summary,
# restore the original bytes. Usage: python mutate.py [names] (no names: all).
# Predictions (which testsets go red) are in predictions.md, written before each ran.
# Bytes in, bytes out: `write_text` on Windows would turn the files' LF into CRLF.
import pathlib, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(r"W:\Claude_projects\GridSim")
EV = ROOT / r"docs\evidence\gridsim-m10\step6"
PAIRS = ROOT / r"src\steadystate\double_outages.jl"
OUT = pathlib.Path(r"W:\temp\claude\m10-step6\mutations")      # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
TESTENV = ROOT / r"docs\evidence\gridsim-m9\harness\testenv"
WIN = ROOT / r"ui\src\double_outage_window.jl"
SCRIPT = ROOT / r"scripts\double_outage_screen.jl"
RUNNERS = {
    "core": f'julia --project={TESTENV} {EV / "run_tests.jl"}',
    "report": f'julia --project={TESTENV} {EV / "run_report.jl"}',
    "window": f'set GRIDSIM_UI_PRECOMPILE=0&& start /belownormal /b /wait julia --project={ROOT / "ui"} {EV / "run_window.jl"}',
}
# name -> (runner, [(file, old, new), ...])
MUT = {
 # F1: the refused-piece fix reverted: every live piece keeps its pickups and flags.
 "F1_fix_reverted": ("core", [(PAIRS,
   "        if o.solution !== nothing || !isnan(Δω)\n",
   "        if true\n")]),
 # R1: the amber rule removed.
 "R1_amber_removed": ("report", [(SCRIPT,
   "    return any(p -> p.kind === :load_lost, pieces) ? :pass_load_lost : :pass\n",
   "    return :pass\n")]),
 # R2: the no-state bug back: a sequential pair with no state after both judged on its
 # first loss's restored pieces, its worst read off them.
 "R2_no_state_judged": ("report", [(SCRIPT,
   "     worst = outcome === :screened ? worst_Δf(pieces) : NaN,\n",
   "     worst = worst_Δf(pieces),\n"),
  (SCRIPT, "        return _side([piece_side(pc, fid, true, false, net; verdict = s.outcome[p])\n",
   "        return _side([piece_side(pc, fid, true, false, net)\n")]),
 # R3: a pair's worst piece by signed minimum, not by size.
 "R3_worst_by_sign": ("report", [(SCRIPT,
   "    return isempty(xs) ? NaN : xs[argmax(abs.(xs))]\n",
   "    return isempty(xs) ? NaN : minimum(xs)\n")]),
 # R4: "untouched by the second loss" ignored.
 "R4_untouched_ignored": ("report", [(SCRIPT,
   "    return _side([piece_side(pc, fid, applicable, !touched[k], net)\n",
   "    return _side([piece_side(pc, fid, applicable, false, net)\n")]),
 # R5: the n/a rule removed for both at once.
 "R5_na_removed": ("report", [(SCRIPT,
   "        applicable = dc.splits[p] || i > m || j > m\n",
   "        applicable = true\n")]),
 # W1: the sketch colours every bus by the FIRST piece.
 "W1_first_piece": ("window", [(WIN,
   "            k = get(piece_of, bs.id, 0)\n",
   "            k = 1\n")]),
 # W2: every cell coloured (and written) from the DC side whatever the view.
 "W2_dc_cells": ("window", [(WIN,
   "            side = getfield(r, choice.view[])\n            R[i, j] = r\n",
   "            side = getfield(r, :dc)\n            R[i, j] = r\n")]),
 # W3: the sequential table reads the both-at-once rows.
 "W3_seq_reads_both": ("window", [(WIN,
   "    rows = timing === :both ? rep.both : rep.seq\n    timing === :both && return only(",
   "    rows = rep.both\n    return only(")]),
 # R6 (D13): ac_lines loses the voltage mark.
 "R6_no_voltage_mark": ("report", [(SCRIPT, "    v && return :voltage\n", "")]),
 # W6 (D13): the window drops the marker from its cells.
 "W6_no_cell_mark": ("window", [(WIN, "    isempty(m) || (t *= \" \" * m)\n", "")]),
 # W5 (added after review): the mouse handler no longer reaches the table.
 "W5_mouse_unwired": ("window", [(WIN,
   "        matrix_press!(p[1], p[2])\n        return Consume(true)\n",
   "        return Consume(true)\n")]),
 # W4: a pair with no state after both drawn as if screened.
 "W4_no_state_drawn": ("window", [(WIN,
   "        screened = side.outcome === :screened\n",
   "        screened = true\n")]),
}
files = {p for _, reps in MUT.values() for p, _, _ in reps}
orig = {p: p.read_bytes().decode("utf-8") for p in files}
try:
    for name, (runner, reps) in MUT.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        txt = dict(orig)
        for p, a, b in reps:
            assert txt[p].count(a) == 1, (name, a)
            txt[p] = txt[p].replace(a, b)
        for p, t in txt.items():
            p.write_bytes(t.encode("utf-8"))
        log = OUT / f"mut_{name}.txt"
        run = RUNNERS[runner]
        cmd = (run if run.startswith("set ") else "start /belownormal /b /wait " + run) + \
              " > " + str(log) + " 2>&1"
        subprocess.run(["cmd", "/c", cmd])
        print("==", name)
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        i = min((j for j, l in enumerate(lines) if l.startswith("Test Summary")), default=None)
        print("\n".join(lines[i:] if i is not None else lines[-15:]))
        for p, t in orig.items():
            p.write_bytes(t.encode("utf-8"))
finally:
    for p, t in orig.items():
        p.write_bytes(t.encode("utf-8"))
print("restored:", all(p.read_bytes().decode("utf-8") == t for p, t in orig.items()))
