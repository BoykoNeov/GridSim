# M9 step 7 sabotages: each edits a COPY of scripts/outage_screen.jl (the tree is never
# touched); mutate_all.sh points the step-5 + step-7 testsets at the copy.
#   python mutate.py <name> <copy>
import sys
P = sys.argv[2]
M = {
    # P1: the COI dip in the worst-machine column
    "P1": ("Δf_dip = v.Δf_dip[nb + k],", "Δf_dip = dips.Δf_coi[k],"),
    # P2: DC's settled verdict shown in the AC column
    "P2": ("settled_ac = v.settled_ac[nb + k],", "settled_ac = v.settled_dc[nb + k],"),
    # P3: the rate window ignored — every column read over 500 ms
    "P3": ("rates = [generator_rates(dips; window = w) for w in RATE_WINDOWS]",
           "rates = [generator_rates(dips; window = 0.5) for w in RATE_WINDOWS]"),
    # P4: a refusal printed as a pass
    "P4": ('              "$(r.dyn) ($(r.reason))"', '              "pass"'),
    # P5: AC's settled deviation read from DC
    "P5": ("Δf_ac = v.Δf_ac[nb + k],", "Δf_ac = v.Δf_dc[nb + k],"),
    # P6: section 5's caveat lines deleted
    "P6": (""" Every verdict below is judged against the preset and carries section 4's caveat: its
 numbers are DESIGN VALUES for a whole synchronous area after a 3,000 MW incident, and
 not a pass/fail rule for one outage on a small grid.

""", ""),
    # P7: section 4's caveat sentence reworded away
    "P7": ("THESE ARE DESIGN VALUES for a whole", "THESE ARE the limits for a whole"),
}
old, new = M[sys.argv[1]]
s = open(P, encoding="utf-8", newline="").read()
assert s.count(old) == 1, sys.argv[1]
open(P, "w", encoding="utf-8", newline="").write(s.replace(old, new))
