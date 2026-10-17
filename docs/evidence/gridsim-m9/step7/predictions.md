# M9 step 7 — predictions, written before the report section ran (2026-10-17)

Step 7 adds section 4 to `scripts/outage_screen.jl`: per generator outage, on the two
lossy report grids and both load models, M8's line-and-voltage outcome (DC, AC) beside
the frequency verdict against `continental_europe_limits()` (settled 0.2 Hz, dip
0.8 Hz), with the rate of fall printed as values only. Entered at `6c9b960`.

## Decisions fixed BEFORE any run

1. **A pure append.** Sections 1–3, the fixtures, `screens()` and the header line are
   left byte for byte, so the old `screen` capture must be an exact byte prefix of the
   new one, and the other four captures identical. M8's claim (d) stays as printed and
   asserted: `:secure` still carries no frequency criterion (D2.5). It is revisited in
   section 4, the only place it is.
2. **One row builder** (`frequency_rows`), read by the printer and by the test.
3. **The rate is printed, not judged.** The preset has no sourced rate limit (D3), so
   the verdict's rate column is `:no_limit`; the report prints the worst surviving
   machine's windowed rate with the COI rate beside it, over both windows the sources
   name — 500 ms (NC DCC Art. 28(2)(k)) and 1 s (NC HVDC Art. 12) — and no pass/fail.
   D10's 1 Hz/s and 2.5 Hz/s were illustrations; a column would make them results.
4. **No combined "survives" column.** The plan says side by side; a combination needs a
   rule for `:refused_at_trip`, `:tolerance_dependent` and the rate's `:no_limit`, which
   is the user's to make, not a `printf`'s.
5. **Refusals print as their outcome's name**, never a dash.

## Predictions (from D8–D10, a different code path from the report's)

- **Settled, preset 0.2 Hz:** every generator outage fails at both fidelities except
  three — mesh constant-power G3 (DC passes 0.193, AC fails 0.200), case9 default G1
  (DC fails 0.401, AC passes 0.195), mesh default G3 (passes at both).
- **Dip, preset 0.8 Hz:** case9 G1 (both load models) and case9 constant-power G2
  `:refused_at_trip`; the mesh's G1 fails at both tolerances (≈11.26 Hz constant power,
  ≈8.91 Hz default); every other measured dip passes.
- **Rates** equal `step6/rates_table.txt` to its printed digits (worst machine and COI,
  500 ms and 1 s).
- **The row most likely to look like a bug:** mesh default G1 — the dynamic dip
  (≈8.91 Hz) is SHALLOWER than the AC screen's settled value (11.06 Hz). Load relief:
  the default loads draw less as voltage and frequency fall, and the dynamic tier sees
  it where the AC screen holds every `V_set` (D1). Not a bug, and the prose must say why.
- **Claim (d), revisited:** the mesh's G1 is `:secure` in both screens and fails the
  settled limit at both fidelities and the dip at both tolerances. A second way
  "secure" is not survival: case9 constant-power G2 is `:secure` in AC and the dynamic
  tier refuses it at the trip (B2 below the band) — no dip is measured at all.
- **No row** passes every judged part in both screens and both runs except mesh
  default G3.

## Outcomes

- **Every prediction held.** Settled: the three exceptions exactly as predicted (mesh
  constant-power G3 `:ac_only_fails` 0.1932 / 0.2002, case9 default G1 `:dc_only_fails`
  0.4012 / 0.1950, mesh default G3 `:both_pass`); nine `:both_fail`. Dip: the three
  refusals at the trip, the mesh's G1 failing at 11.260 / 8.905 Hz, every other
  measured dip passing. Every rate equals `step6/rates_table.txt` at its printed digits,
  both windows, worst machine and COI. Mesh default G1's dip (8.905 Hz) is shallower
  than AC's settled 11.059 Hz, as predicted.
- **Not predicted:** the dip is shallower than AC's settled value on a SECOND row, mesh
  default G3 (0.151 against 0.153 Hz) — the dynamic run never reaches the AC screen's
  settled value there at all. And under the preset the dip decides no verdict: the
  largest dip-to-settled ratio is 1.66 (case9 constant-power G3) against the limits'
  ratio of 4, so the dip can fail only where the settled value already does.
- **Caught by the step's own assertions, before any sabotage:** the first claims draft
  printed that ratio as 1.67 — DC's ratio (1.674), not the AC one the sentence names.
  The dip there (0.75150 Hz) also sits on a rounding boundary — the table's three places
  print 0.752, and 0.752 / 0.4515 reads 1.67 again — so the claim prints it to four.

### Sabotages, predicted before any ran (`mutate.py`, `mutate_all.sh`)

| | Sabotage | Predicted red |
|---|---|---|
| P1 | the COI dip in the worst-machine column | the column check; claim i (worst = COI everywhere); claim g's ratio |
| P2 | DC's settled verdict in the AC column | the column check only — the pair class is read separately, so the claims stay green |
| P3 | every rate read over 500 ms | the column check; claim i (500 ms / 1 s = 1) |
| P4 | a refusal printed as a pass | the printed-table check only |
| P5 | AC's settled deviation read from DC | the column check; claims f, g, h |

### Sabotages, outcomes (`results.txt`)

All five red; four exactly where predicted. P1 (COI dip in the worst-machine column) was
also red in claim h, not predicted: two of h's comparisons read the dip against AC's
settled value, and the COI dip is shallower than the worst machine's. P1 left claim f
green, as it should: on the mesh's G1 the worst machine and the COI dip agree to the
digit (a capped slide moves every machine together). The default-path check is green
under every sabotage by construction — both of its sides run the sabotaged copy; it
guards the cache, not the builder.

| | Red (testset: fails) |
|---|---|
| P1 | columns 9, claim g 1, claim h 2, claim i 3 |
| P2 | columns 2 |
| P3 | columns 21, claim i 2 |
| P4 | printed table 6 |
| P5 | columns 12, claim f 2, claim g 2, claim h 3 |

## The window (the user's choice, asked after the table: "build a window")

### Window sabotages, predicted before any ran (`mutate_window.py`)

| | Sabotage | Predicted red |
|---|---|---|
| W1 | the lost machine's trace drawn | the traces testset (its slot must be empty) |
| W2 | the settled-DC cell coloured by AC's verdict | the overview testset |
| W3 | a selection change does not clear the traces | the controls testset (a refusal leaves the previous run on screen) |
| W4 | the dip limit drawn at the settled limit | the limits testset |

### Window sabotages, outcomes (`results.txt`)

All four red, each exactly and only where predicted: W1 traces 1, W2 overview 2, W3
controls 2, W4 limits 1.

## Follow-up at review: the caveat, wherever the preset's numbers are used

The plan asks for the preset's caveat wherever its numbers are used. Section 4 and the
window printed it, but no test read it (deleting it left every check green), and section
5's claims, which rest on the same verdicts, did not repeat it. Section 5 now carries one
line pointing back to it. Section 4's heading and section 5 now print to a stream, so the
test reads what each printer actually prints. The window keeps its caveat `Label` and
checks it is placed in the figure's layout.

### Caveat sabotages, predicted before any ran

| | Sabotage | Predicted red |
|---|---|---|
| P6 | section 5's caveat lines deleted | the caveat testset only, 2 (both phrases, section 5's output) |
| P7 | section 4's "DESIGN VALUES" sentence reworded away | the caveat testset only, 1 (section 4's other phrase survives) |
| W5 | the caveat `Label` built in a figure of its own, never placed | the limits testset only, 1 (`in_layout`; its text is unchanged) |

### Caveat sabotages, outcomes (`results.txt`)

All three red, each exactly and only where predicted: P6 caveat testset 2, P7 caveat
testset 1, W5 limits testset 1. Clean runs green: the step-5 + step-7 testsets, and the
window's 177. The first window runs did not run at all: the scratch runner cut the
`in_layout` helper out of `ui/test/runtests.jl` by searching for `"\nend\n"`, and that file
has CRLF endings in the working copy. It was rerun after normalising the line endings.
