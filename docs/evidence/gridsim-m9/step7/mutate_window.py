# M9 step 7 window sabotages, applied IN PLACE to ui/src/frequency_screen_window.jl;
# mutate_window.sh keeps a backup and restores it after every run.
#   python mutate_window.py <name>
import sys
P = r"W:/Claude_projects/GridSim/ui/src/frequency_screen_window.jl"
M = {
    "W1": ("                j == k && continue                   # the machine lost is never drawn\n", ""),
    "W2": ('''     r -> _fs_judged(r.settled_dc)),''', '''     r -> _fs_judged(r.settled_ac)),'''),
    "W3": ("        foreach(o -> o[] = Point2f[], mach); foreach(o -> o[] = Point2f[], mach_z)\n        coi[] = Point2f[]; coi_z[] = Point2f[]\n", ""),
    "W4": ("lim_lines = (; settled = f0 - lim.settled, dip = f0 - lim.dip)",
           "lim_lines = (; settled = f0 - lim.settled, dip = f0 - lim.settled)"),
}
old, new = M[sys.argv[1]]
s = open(P, encoding="utf-8", newline="").read()
assert s.count(old) == 1, sys.argv[1]
open(P, "w", encoding="utf-8", newline="").write(s.replace(old, new))
