# M10 step 6 — the report's evidence

`report.out.txt` is `scripts/double_outage_screen.jl`'s printout as it was at M10 step 6
(2026-10-19): a dated record, not the current output.

**Superseded in part at M11 step 5 (2026-10-22).** The reference bus's machine's governor
up-reserve is now measured from what it produces in the AC base, not from its schedule
(`docs/plans/m11-context.md` D12, the user's choice). Its AC pair screens moved where that
machine caps: the mesh's G2+G3 (both at once, and the two orders, which now equal it), case9
on the default loads in the eight ordered pairs that leave G1 alone, and claim q's counts
and largest move. The diff of the printout is
`docs/evidence/gridsim-m11/step5/report10.diff.txt`; the current claims are the script's.
