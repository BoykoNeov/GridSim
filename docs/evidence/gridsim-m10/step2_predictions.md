# M10 step 2 — predictions, written before any of it ran

Step 2 screens every pair of elements — two lines, two generators, one of each — in
DC, a split grid piece by piece (Hurdles 18.4, 19.1–19.4). Everything below was
written before the code, the swing runs or the sabotages ran. What came out is in
`m10-context.md`, "What step 2 measured".

## The design these predictions are about

- Elements are M8's rows: every branch in model order, then every machine. Pairs are
  unordered, lexicographic: case9 12 elements → 66 pairs, the mesh 10 → 45.
- Pieces come from the graph with the pair's branches removed. A piece is **live**
  when it holds a machine with `P0 ≥ 0` that is not lost, or a grid-forming inverter
  (D4). Live with a load → shared by its own units; live with no load → its sources
  lost; not live with anything in it → load lost (its grid-following inverters with
  it); nothing at all → empty. A `P0 < 0` machine is a load (D6.3).
- **A live piece's imbalance is read from the base case:** what the pair took out of
  it (lost machines' schedule) plus what it imported across the removed branches
  (base DC flows). So a pair that leaves the grid whole has imbalance exactly the lost
  schedule — exactly `0.0` for two lines, exactly M8's `P_lost` sum for two machines.
- **The tests read the imbalance a different way:** from the equipment list (each
  piece's surviving machines' and inverters' `P0` less its loads). The two agree to
  the base solve's round-off, never by construction.
- Flows of a split pair: one fresh sparse factorisation of the network without the
  two branches, one reference per piece (the model's slack where it lies in the
  piece, else the piece's first bus). The brute-force oracle builds each live piece
  as its own `NetworkModel` and calls `dc_powerflow` — a different assembly.

## Bands, stated now

- **Static, per piece (brute force):** flows `100·eps·max|f|` (M8 step 2's band);
  imbalance against the equipment-list reading `100·eps·Σ|P|`; pickups against
  `pickup_shares` on the piece model (a balancing dummy machine with no droop and
  no damping as the loss) `1e-14` relative, M8 step 4's closed-form tolerance.
- **The pairs that are one event (D4):** L14+G1, L82+G2, L36+G3 against M8's single
  G1/G2/G3 outage — **within a band, not bit for bit**: the screen sizes the rest's
  loss from the flow on the bridge, M8 from `r.P[k]`; they differ by the base solve's
  round-off. Band `100·eps·max|f|` on flows, `1e-12` relative on `Δω` and pickups.
- **Different paths to one event** (case9): L14+G2, L82+G1, L14+L82 and G1+G2 — all
  G1 and G2 gone — the same `Δω`, pickups and flows within the band above. And the
  mesh's AB+AC against M8's G1 (the one pair where the reference's own piece dies).
- **The swing tier (19.2):** every surviving machine's `ω` against its piece's `Δω`,
  and every live bus's change in electrical export against its machine's pickup,
  **1e-7**, M8 step 4's band (it measured 1.5e-10). Read at 300 s and 450 s; both
  must hold (settled, not passing through). Lost machines, machines in a dead piece
  and dead buses' exports are excluded by name. Branch flows are never compared
  (sin against linear, by design).
- **Order (18.4), swing tier:** trip A, settle to 300 s, trip B, read at 600 s and
  750 s, against both at once read at 300 s and 450 s: every machine's `ω` and every
  bus's export change, **1e-7**. The cap must be seen to bind after A: `ΔPm` of G3
  within `1e-9` of its 0.05 pu headroom (M8 step 4's check).

## Numbers predicted before running

- case9 L45+L67 (D1's arithmetic): G3's piece {B3, B5, B6} has a 13.66 MW surplus over
  56.7 pu of droop and damping, `Δω = +0.002409` pu; the rest a 13.66 MW shortfall
  over 115.5 pu, `Δω = −0.001183` pu. (On the report grid; the swing fixture's
  load-machines and fillers also respond, so its numbers are smaller and are not
  predicted.)
- Kinds on case9's 66 pairs: 36 line pairs all split (9 two live pieces, 3 load lost,
  24 with sources lost — 21 one piece, 3 two pieces); of 27 line+generator pairs, 9
  have a bridge and split (3 of them collapse to a single outage), 18 stay whole; the
  3 generator pairs stay whole.
- The mesh's 45: 21 line pairs (19 whole, 2 split with sources lost: A, E), 21
  line+generator and 3 generator pairs, all whole.

## Sabotages, and where each should go red

| # | Sabotage | Red | Green (and why) |
|---|---|---|---|
| S1 | every surviving unit of the grid shares each live piece's imbalance (the piece mask dropped: a unit in another piece, dead or live, shares too) | brute force on case9's two-live splits and on every pair with a cut-off machine; swing L45+L67, L14+L82, L45+L94; mesh AB+AC (G1, cut off, shares); the "different paths" check through L14+L82, L14+G2, L82+G1 | every pair where nothing outside the one live piece survives: whole-grid pairs and the three collapsed pairs (their cut-off machine is the lost one) — **predicted green there** |
| S2 | a surplus treated as a shortfall (negative imbalance's sign flipped) | brute force L45+L67 (G3's piece); swing L45+L67; swing L45+L56 (the rest rises) | every whole-grid pair (all deficits or zero); the collapsed pairs |
| S3 | a stranded load's import across the cut left out of its neighbour's imbalance | brute force and swing on L45+L56 (rest should rise, stays at 0); the three case9 load-lost pairs | pairs with no load-lost piece |
| S4 | a `P0 < 0` machine counted as a source (and still a load) | **only the explicit classification check** on the swing fixture's L45+L56 ({B5} must be load lost) | the swing check: {B5} becomes a "live" piece of one load-machine, shared by its own damping, `Δω = −0.9/D` — which is exactly the speed the stranded rotor spins to in the swing tier, so the two AGREE and the swing check cannot see it; the brute force likewise; everything on the report grids (their loads are `Load`s). Invisible to every check but the named one, by construction — recorded rather than hidden |

## Added 2026-10-18, after the first green run and BEFORE any sabotage ran

The rows above are left as written. Two of them went stale when the tests changed
between the first run and the sabotages, and are corrected here so the sabotage results
are read against what the tests now are:

- **S4 should now also go red on the brute-force count.** The placeholder floor
  (`>= length(net.branches)`) became an exact measured count (`== n`). Under S4 every
  pair that strands one of the swing fixture's load-machines gains a "live" piece (the
  machine alone, settling on its own damping), so swing case9's 162 goes up. The swing
  and per-piece checks are still expected to agree with it, as the row says.
- **S2's green column is wrong for genmesh and the swing fixture.** A whole-grid pair
  that loses a load-machine (G2+LD, for one, which the order test asserts) has a
  SURPLUS, not "a deficit or zero". S2 should go red there too: on the whole-grid
  `imbalance === lost schedule` identity, on the brute force, and on the G2+LD swing and
  order runs.

Also measured wrong before any sabotage (both now asserted in the tests as found):

- The mesh's AB+AC is G1's single outage in frequency and pickups but **not in flows**:
  with only G1 lost, bus A stays in the mesh and carries a loop flow (0.395 pu off at the
  worst branch); losing both lines closes that path.
- A whole grid can be **not live**: genmesh's LB+LD takes both loads, so its generators
  are `:sources_lost`. "Every whole-grid pair is live" was assumed above and is false.
