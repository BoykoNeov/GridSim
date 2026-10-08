# ============================================================================
# THE ACCURACY CEILING THE ORACLE ITSELF HAS, AND WHAT THE BAND CAN THEREFORE BE
# ============================================================================
#
# **`PowerFlows` stores its admittance matrix in SINGLE precision.**
# `PowerNetworkMatrices/src/definitions.jl` line 1 reads
# `const YBUS_ELTYPE = ComplexF32` — a compile-time constant with no setting
# behind it. One `grep` confirms it; the path is here so the next reader does not
# have to re-derive it from a residual mismatch, which is how this was found.
#
# **It is the admittance and nothing else.** `PowerFlows/src/PowerFlowData.jl`
# declares every injection, withdrawal, magnitude and angle matrix as
# `Matrix{Float64}` — checked, because "their data is single precision" and "their
# ADMITTANCE is single precision" are different claims and only the second is true.
#
# What it costs, measured on the three-bus radial fixture: their Newton reports a
# final ∞-norm residual of **4.4e-16** and it is telling the truth — about the
# Float32-rounded network. Evaluated in double precision against an admittance
# matrix built by hand from the branch list, the same answer leaves a mismatch of
# **3.8e-8 pu**, where ours on the same independent check leaves **4.4e-16**. Their
# Y differs from the exact one by up to 6.4e-7 in absolute terms, which is
# single-precision resolution on an entry of 16.67. None of it is convergence:
# their answer stops moving once `tol` passes 1e-10 and never improves again.
#
# **THIS IS M4's D7 ARRIVING A SECOND TIME BY A DIFFERENT MECHANISM.** There,
# PowerDynamics was measured at 3.5–18x further from the truth than us, through
# integration error. Here PowerFlows is roughly SEVEN ORDERS further, through a
# fixed-width admittance. Both say the same thing and it is worth saying twice: the
# oracle is a **floor, not a ceiling**.
#
# **WHY THE BAND IS A PRECISION STATEMENT AND NOT A SENSITIVITY CALCULATION.**
# The obvious move is to predict their error: perturb our branch admittances onto
# the single-precision grid, re-solve with our own code, and use the difference.
# Two versions of that were built and measured, and **neither is a bound**:
#
#   * one twin with every branch rounded at once under-predicts on meshed cases
#     (it realises ONE rounding pattern where their assembly rounds each entry
#     independently);
#   * the first-order sum over single-branch perturbations covers three fixtures
#     and is **saturated at 2.94x on the off-base one**.
#
# The reason no factor rescues either is structural, and it is worth stating
# because it decides the shape of everything below. Our model has no shunts, so
# `Y_vv = −Σ_u Y_vu` holds by construction. **Their rounded diagonal breaks that
# identity**: rounding the assembled sum leaves an implicit shunt at every bus,
# which is a perturbation our model *cannot express at all*. It is not a term with
# an unknown coefficient waiting for a factor — it is a different kind of object,
# and multiplying a branch-sensitivity sum by 3 or by 4 to cover it would be
# fitting a constant to the very gap it is meant to judge. M4 refused that move for
# the `tolerance_band` ratio that ran 5.2 → 15.3 and did not settle; the same
# refusal applies here.
#
# So the agreement band says only what can be said without a model of their error:
# **their admittance is stored to single-precision RELATIVE accuracy, so no channel
# derived from it can agree with a double-precision solve more closely than that
# relative accuracy times the channel's own magnitude.** One sentence, no factor,
# stated before any gap was seen — and the measured ratios go in `m6-tasks.md`
# rather than into a threshold, so a fixture that lands above 1.0 reads as a
# finding rather than as a broken band.
#
# **The sharp check is elsewhere, and it needs no band at all**: evaluate each
# side's answer in an independently built double-precision admittance and report
# the mismatch. That is a fact about each side alone. See the suite's
# "each side's answer in an independent admittance" testset — it is what carries
# this round, and the banded comparisons are secondary to it.

"""
    float32_admittance_twin(net::NetworkModel) -> NetworkModel

`net` with every branch impedance replaced by the one whose **admittance** lands
on the single-precision grid — the grid `PowerFlows` stores its `Ybus` on.

**This is how the mechanism was identified and confirmed, and it is deliberately
NOT how the band is derived.** Solving this twin with our own solver moves the
answer the same way and by a comparable amount as theirs moves — which is what
turned "their answer is mysteriously 4e-9 off" into "their admittance is
`ComplexF32`". As a *predictor* it is not a bound: it realises one rounding
pattern where their assembly rounds each entry independently, and it cannot
represent the implicit shunt their rounded diagonal leaves behind. The header
above says why no factor fixes that, and [`powerflow_band`](@ref) does not use
this function.

`R` is clamped at zero and only where rounding pushed a zero resistance slightly
negative: `Branch` requires `R >= 0`, and a lossless branch must stay lossless
rather than fail construction. A resistance that comes back negative by more than
rounding could be is refused, so the clamp can never quietly hide one.
"""
function float32_admittance_twin(net::GridSim.NetworkModel)
    branches = map(net.branches) do br
        z = 1 / ComplexF32(1 / complex(br.R, br.X))
        R = Float64(real(z))
        if R < 0
            abs(R) < 1.0e-9 || throw(ErrorException(
                "float32_admittance_twin: branch $(br.id) came back with R = $R after " *
                "the single-precision round trip. Rounding a non-negative resistance " *
                "can only push it negative by the width of the grid; this is far " *
                "larger, so it is not a rounding artefact to clamp away."))
            R = 0.0
        end
        GridSim.Branch(br.id, br.from, br.to, Float64(imag(z)), br.rating; R = R)
    end
    return GridSim.NetworkModel(net.S_base, net.f0, net.buses, branches,
                                net.machines, net.loads; slack = net.slack)
end

"""
    powerflow_band(net; channel, abstol = 1e-12, tol = 1e-12,
                   check_limits = true, dc = false)

The agreement band for one channel of the AC (or DC) comparison on `net`, and the
three terms it is made of.

Returns `(; band, ours, theirs, precision)`:

  - `ours`      — our solver's own convergence, `|ours(abstol) - ours(abstol/1000)|`;
  - `theirs`    — their solver's own convergence, `|theirs(tol) - theirs(1000*tol)|`;
  - `precision` — `eps(Float32) * maximum(abs, channel(ours))`: their admittance is
    stored to single-precision relative accuracy, so nothing derived from it can
    agree with a double-precision solve more closely than that relative accuracy
    times the channel's own size. The header says why this is a *statement about
    their storage* rather than a prediction of their error, and why every attempt
    at the latter was refused.

`band = ours + theirs + precision`, with **no factor**. Each term is a property of
one side alone and none looks at the cross gap, so "state the band before you see
the gap" is a property of the arithmetic rather than a discipline anyone keeps.

`channel` picks the quantity: `s -> s.Vm`, `s -> s.θ`, `s -> s.flow`. **One band
per channel** — M4 measured what an aggregate band costs on a per-machine read.

**`Pgen` and `Qgen` are NOT channels for this.** At a generator bus our `Pgen` is
the schedule exactly — not a solved quantity, so a convergence term for it is
meaningless — and at the slack theirs passes through `post_processing.jl`'s
redistribution loop, whose own `ISAPPROX_ZERO_TOLERANCE` is `1e-6` and has nothing
to do with admittance precision. Generation is checked by identity instead (the
schedule on our side, the loss pickup at the slack), which is what those numbers
actually assert.

`dc = true` bands the linear solve. It gets its own band for its own reason: their
DC path runs through `PowerNetworkMatrices.solve_w_refinement`, an iterative
refinement with a separate tolerance, which is a different mechanism from the
Ybus quantization even where it lands at a similar size.
"""
function powerflow_band(net::GridSim.NetworkModel; channel,
                        abstol::Real = 1.0e-12, tol::Real = _PF_TOL,
                        check_limits::Bool = true, dc::Bool = false)
    gap(x, y) = maximum(abs, channel(x) .- channel(y))
    if dc
        ours_c = GridSim.dc_powerflow(net)
        ours_f = ours_c                              # linear: one factorisation, no tolerance
        theirs_c = oracle_dc_powerflow(net)
        theirs_f = theirs_c                          # their DC takes no tolerance argument
    else
        ours_c = GridSim.ac_powerflow(net; abstol = abstol)
        ours_f = GridSim.ac_powerflow(net; abstol = abstol / 1000)
        theirs_c = oracle_powerflow(net; tol = tol, check_limits = check_limits)
        theirs_f = oracle_powerflow(net; tol = tol * 1000, check_limits = check_limits)
    end
    ours_term  = gap(ours_c, ours_f)
    their_term = gap(theirs_c, theirs_f)
    scale = maximum(abs, channel(ours_c))
    prec_term = eps(Float32) * scale
    band = ours_term + their_term + prec_term
    band > 0 || throw(ArgumentError(
        "powerflow_band: the derived band is $band, because the channel is " *
        "identically zero and neither side moved. A band derived from nothing is " *
        "not a band; compare an identically-zero channel with `==`."))
    return (; band, ours = ours_term, theirs = their_term, precision = prec_term)
end

"""
    independent_mismatch(net::NetworkModel, sol) -> Float64

The largest power-flow mismatch `sol` leaves, evaluated against an admittance
matrix **built here, by hand, in double precision** — four lines of
`y = 1/(R + jX)` scattered into a dense matrix, reading `Branch` directly.

This is the round's sharp instrument and it needs no band, because it is a
statement about ONE answer rather than about the gap between two. It is also the
only check here that touches neither `_ac_admittance` nor `PowerNetworkMatrices`:
handing either side its own admittance back would be the mistake step 3 shipped
twice, where a check read its answer from the source it was checking.

Buses whose injection is not scheduled are skipped and named as such: the slack's
real and reactive injection and a generator bus's reactive injection are outputs
of the solve, so there is no scheduled value to difference against. Every other
equation the solve claims to have satisfied is evaluated.

The hand-built matrix is an *instrument*, not a second model of the network — it
computes no solution, it only evaluates one — so SPEC §3.2's ban on parallel
hand-maintained copies is not in play.
"""
function independent_mismatch(net::GridSim.NetworkModel, sol)
    n = length(net.buses)
    Y = zeros(ComplexF64, n, n)
    for br in net.branches
        f = net.bus_index[br.from]; t = net.bus_index[br.to]
        y = 1 / complex(br.R, br.X)
        Y[f, f] += y; Y[t, t] += y; Y[f, t] -= y; Y[t, f] -= y
    end
    V = sol.Vm .* cis.(sol.θ)
    S = V .* conj.(Y * V)

    # The scheduled injection at each bus, assembled from the model rather than
    # from `_ac_schedule`: machines' P0 minus the load's ZIP draw at the solved
    # magnitude, written out here in the expanded form on purpose (D11's `_zip_k`
    # grouping is the thing under test elsewhere, and a check must not evaluate the
    # model it is checking — `m6-tasks.md` step 3, F10).
    v_slack = net.bus_index[net.slack]
    worst = 0.0
    for v in 1:n
        v == v_slack && continue
        Pgen = sum((m.P0 for m in net.machines if net.bus_index[m.bus] == v); init = 0.0) /
               net.S_base
        k = net.load_at_bus[v]
        Vm = sol.Vm[v]
        Pl, Ql = 0.0, 0.0
        if k != 0
            l = net.loads[k]
            zip = l.a_z * Vm^2 + l.a_i * Vm + l.a_p
            Pl = l.P0 / net.S_base * zip
            Ql = l.Q0 / net.S_base * zip
        end
        worst = max(worst, abs(real(S[v]) - (Pgen - Pl)))
        # The reactive equation exists only where Q is scheduled, i.e. at a bus with
        # no machine holding a voltage.
        isempty(net.machines_at_bus[v]) && (worst = max(worst, abs(imag(S[v]) + Ql)))
    end
    return worst
end
