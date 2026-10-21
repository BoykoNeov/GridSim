# M11 step 5 — predictions, written before the after-captures

Two parts: the reference machine's up-reserve fix (m11-context.md D12, the user's choice),
predicted against the eleven gate captures before they are re-taken; then the report's
numbers (added below before the report's test first runs).

## Part A — the up-reserve fix (D12)

The change: the reference bus's machine's governor cap is `max(0, Pmax − P_out)/S_base`,
`P_out` its terminal output in the solve the run or screen starts from, instead of
`(Pmax − P0)/S_base`. Every other machine's arithmetic is untouched.

**Where the cap is read.** In the dynamic tiers the cap is a parameter read only in the
saturation test (`ΔPm ≥ headroom && dΔPm > 0`); in the settle it is `min(x·g, h)` and the
bend list. So a number can move ONLY where the reference's governor reaches its cap, or
where M10's restore reads the reference's room (up to its cap, down to `Pmin`).

**A1. Byte-identical** (the cap never binds on the reference, or nothing changed):
- `swing`, `criterion`, `oracle` — lossless (the swing tier's correction runs only after
  its lossy reference-bus solve; the oracle is lossless throughout).
- `ac`, `screen` (M8's screens), `report8` — M8's generator outages lose one unit; on
  case9 the reference (G1, ~150 MW of up-reserve) takes a share of at most ~60 MW, on the
  mesh the reference (G1, 70 MW) at most ~45 MW. And when G1 is the lost unit its own cap
  is not read. So no settle caps the reference.
- `dips`, `verdict` (M9's detailed-tier single outages) — the same single outages.

**A2. May move in the last digits**: none expected. On a lossless, load-free model the
detailed tier's reference output is its schedule to round-off, so its cap moves by an ulp
— read only if it binds, and no lossless capture drives the reference to its cap. If one
does move by round-off, that is this prediction failing, and is recorded as such.

**A3. Expected to move** (the reference's cap binds, or the restore reads its room):
- `snap`, `report10` (M10's pair and sequential screens, AC side only — the DC side is
  lossless and untouched): the pairs that lose both non-reference units, case9's G2+G3
  (~219 MW against G1's ~150 MW) and the mesh's G2+G3 (100 MW against 70), and any ordered
  pair whose restore leans on the reference. Direction on constant-power loads: the
  reference produces MORE than its schedule (it carries the losses), so it has LESS
  up-reserve — the settled frequency deeper, a restore more often refused. On the default
  loads the base output is the schedule plus losses plus the (negative) load-draw shift, so
  the sign is the case's own; measured, not predicted.
- `dynamic` (M10's detailed-tier runs): only those whose reference governor reaches its cap.

Every DC column of every capture: byte-identical.
