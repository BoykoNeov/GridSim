# Glossary — the project's words, in plain language

The plans, the code comments and the windows use a working vocabulary. This page says
what each word means in everyday terms, why it matters, and where in the repo it lives.
It is written for a reader who has not read the plans. Nothing here is a new claim: where
a number appears it is quoted from the place named beside it.

Order: the physics first, then the models, then the studies, then the project's own
working habits.

## The physics

**Frequency (50 Hz).** How fast the grid's alternating voltage cycles. Every spinning
generator on a connected grid turns in step with it. When generation and consumption
balance, it sits at 50 Hz (`f0`); when they do not, it moves. It is the grid's single
shared "are we in balance" gauge.

**Inertia (`H`, seconds).** The energy stored in the spinning mass of generators, written
as how many seconds that energy could supply the machine's rated power. More inertia
means frequency changes more slowly after a sudden loss. Wind and solar plants connected
through electronics have none unless they are built to imitate it.

**Rate of change of frequency (RoCoF, Hz/s).** How fast frequency is falling (or rising)
right after a disturbance. Set by the size of the loss divided by the inertia. Protection
equipment can disconnect things if it is too steep, which is why it is tracked separately
from how low the frequency eventually gets.

**Nadir / the dip.** The lowest point frequency reaches after a loss, before the
automatic response catches it.

**Settled value.** Where frequency comes to rest once the automatic response has done
all it will do. Usually a little below 50 Hz, because the response is proportional (see
droop) and needs a remaining error to keep acting.

**Centre of inertia (COI).** The inertia-weighted average of all the machines' speeds —
"the" system frequency when machines are swinging against each other. It stops meaning
anything once the grid has split in two (`docs/plans/m4-context.md` D5).

**Governor, droop (`R`).** The governor is a generator's automatic throttle. Droop is its
rule: for each bit that frequency falls, add a proportional bit of power. A 5 % droop
means a 5 % frequency fall would call for 100 % of the machine's rating.

**Headroom / up-reserve.** How much more power a generator can add before it reaches its
maximum (`Pmax` minus what it produces now). A governor can only give what headroom it
has; past that it is **capped**, and the rest of the shortfall is left to frequency.

**Damping (`D`).** Everything that makes consumption fall a little when frequency falls
(motors slow down). It is why a grid with every governor capped still settles somewhere
instead of falling forever.

**Load shedding.** Deliberately disconnecting blocks of customers when frequency falls
through set thresholds, to stop a collapse. The "defence plan" is the list of thresholds
and blocks (`src/protection/load_shedding.jl`).

**Rotor angle, synchronism, out-of-step.** Each generator's rotor sits at some angle
relative to the others; power flows from the leading ones to the lagging ones. If two
groups of machines pull too far apart they "slip" — lose synchronism — and the line
between them has to be opened. The relay that does that is the **out-of-step relay**
(`src/protection/out_of_step.jl`).

**Per-unit (pu).** Quantities written as a fraction of a base value (the system base
power `S_base`, the nominal voltage) so that numbers from different-sized equipment are
comparable. Inside the code everything is per-unit; megawatts and hertz appear only where
something is shown to a person.

**Bus.** A connection point in the network — a substation's busbar. Generators, loads
and lines all attach to buses.

**Voltage band.** The range a bus voltage must stay inside, here 0.9 to 1.1 pu. A
solution outside it is refused rather than reported.

**Reactive power (`Q`, MVAr).** The part of electrical power that sloshes back and forth
to hold voltage up rather than doing work. A generator has limits on how much it can
supply; when it hits one it can no longer hold its voltage.

**Line rating (MVA).** The most a line may carry. "Overload" means a flow above it.

**Losses.** Power turned to heat in line resistance. Small (a few percent) but someone
has to generate it.

**Inverter; grid-following (GFL) and grid-forming (GFM).** The electronics that connect
solar, wind and batteries. A grid-following inverter measures the grid's voltage and
injects current in step with it; it needs a grid to follow. A grid-forming one creates a
voltage of its own and behaves, mathematically, like a small generator.

**Phase-locked loop (PLL).** The circuit a grid-following inverter (or a frequency meter)
uses to track the grid's voltage angle. What it reports as "frequency" is an estimate,
and it jumps when the voltage angle jumps — a spike no rotor made (`docs/plans/README.md`,
hurdle 10).

## The models (the "fidelity tiers")

The project's organising idea: every question gets a cheap model that runs live and an
accurate one that runs offline, and **seeing where they disagree is the lesson**.

**Aggregate tier / frequency-response model.** The whole grid as one spinning mass with
one governor. Two numbers of state. Answers "how fast and how far does frequency fall".
Cannot see anything that happens *between* machines. Code: `src/engines/frequency_response.jl`.

**Swing tier / network tier / classical model.** Every machine separately, joined by
lines, each with its own rotor angle and speed; voltages are assumed constant. Sees
machines swinging against each other and a grid splitting. Code: `src/engines/swing.jl`.

**Detailed tier.** As the swing tier, plus voltage as something that is solved for at
every instant, the machines' internal magnetic state, voltage regulators, and inverters.
Sees voltage sag and collapse. Slower. Code: `src/engines/detailed.jl`.

**Canonical model (`NetworkModel`).** The one description of the grid (buses, lines,
machines, loads, inverters) every tier is built from. The aggregate model is *computed
from it* (`coi_model`), never kept as a second copy by hand.

**Real-time and playback.** Two ways to run a model. Real-time: stepped against the
clock, and you can trip things while it runs. Playback: solved in one go, then scrubbed
through with a slider.

**Power flow (DC and AC).** Not a simulation in time: the calculation of where the grid
*sits* — every bus voltage and every line flow — for a given pattern of generation and
consumption. "AC" is the full nonlinear calculation. "DC" is a fast linear shortcut that
ignores voltage and losses (the name is historical; nothing is direct current).

**Slack / reference bus.** In a power flow, the one generator that is not told its
output but picks up whatever is left over (the losses, mainly). A bookkeeping choice that
has real consequences, which is why the editor draws it.

**Load model: constant power, constant impedance ("default"), ZIP.** How consumption
reacts to voltage. Constant power: draws the same whatever the voltage. Constant
impedance: draws less as voltage sags (like a heater). ZIP: a mix. The repo's default is
constant impedance, and several results change sign between the two — which is why
reports show both.

## The studies

**Outage / contingency screening (N-1, N-2).** Remove each line and each generator in
turn (N-1), or each pair (N-2), and check whether what is left still works. `:secure`
means lines and voltages stay inside limits; it says nothing about frequency, which is
judged separately.

**Frequency verdict.** Pass or fail of an outage against frequency limits: the settled
value, the dip, and the rate of fall. The built-in limits are Continental Europe's design
values for a whole continent losing 3,000 MW — not a rule for a nine-bus test grid, and
every window that uses them says so.

**Dispatch; economic dispatch.** Deciding how much each generator produces. *Economic*
dispatch picks the cheapest combination that meets demand, ignoring the network.

**Optimal power flow (OPF), DC and AC.** The cheapest dispatch that the network can
actually carry: no line over its rating, and (in AC) every voltage inside its band.
"Binding" means a limit that the answer sits exactly on — the limit is what makes the
answer dearer.

**case9, the mesh, the ring, the two-area model.** The small test grids. *case9* is a
standard published nine-bus grid (MATPOWER's), used here **without line charging**, so
its limits are this repo's and not the published ones. *The mesh* is a five-bus grid
with loops. *The ring* is three machines in a triangle. *The two-area model* is Iberia
and the rest of Europe as two big machines joined by one tie.

**The Iberian case.** The 28 April 2025 blackout of Spain and Portugal, from ENTSO-E's
published report. The standing real-world test: what each tier reproduces and where it
stops (`docs/plans/entsoe-iberia-reproduction.md`).

## How the project works

**Oracle / outside check.** Somebody else's implementation of the same physics
(PowerDynamics, PowerFlows, PowerModels), kept in the separate `reference/` package and
used only to check ours — never to produce a result.

**Closed form.** An answer worked out by algebra, with no simulation. The strongest kind
of check, because it shares no code with what it checks.

**Band.** The tolerance inside which two numbers count as agreeing. The rule here: state
the band *before* looking at the gap.

**Sabotage / mutation / anti-vacuity control.** Deliberately breaking the code (or the
check's premise) to confirm a test goes red. A test that cannot fail proves nothing.

**Capture.** A full-precision dump of a set of results, taken before a change and again
after, and compared byte for byte. How "this change moved no existing number" is shown
rather than hoped. Scripts: `docs/evidence/gridsim-m9/harness/`.

**Hurdle.** The specific hard thing a milestone exists to get over, named before the
milestone is planned (`docs/plans/README.md`). A milestone with no named hurdle is just
a feature list.

**Plan trio.** The three files each milestone keeps: the plan (how), the context
(decisions and what was measured), the tasks (the checklist).

**Validation ledger.** The table of every mechanism in the repo and what checks it,
including the honest "nothing yet" rows (`docs/validation-ledger.md`).

**Refused.** The model declining to answer — a voltage outside its band, an event the
tier cannot represent — with a message naming the reason. A refusal is reported as an
outcome; it is never silently turned into a pass or a fail.
