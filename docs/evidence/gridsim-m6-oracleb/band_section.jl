
# ============================================================================
# THE ACCURACY CEILING THE ORACLE ITSELF HAS, AND HOW THE BAND IS DERIVED FROM IT
# ============================================================================
#
# **`PowerFlows` stores its admittance matrix in SINGLE precision.**
# `PowerNetworkMatrices/src/definitions.jl` line 1 reads
# `const YBUS_ELTYPE = ComplexF32` — a compile-time constant with no setting
# behind it. One `grep` confirms it; the path is here so the next reader does not
# have to re-derive it from a residual mismatch, which is how this was found.
#
# What that costs, measured on the three-bus radial fixture: their Newton reports a
# final ∞-norm residual of **4.4e-16** and it is telling the truth — about the
# Float32-rounded network. Evaluated in double precision against an admittance
# matrix built by hand from the branch list, the same answer leaves a mismatch of
# **3.8e-8 pu**, and its `θ₃` sits **7.6e-9 rad** away from ours, whose mismatch on
# the same independent check is 4.4e-16. Their Y differs from the exact one by up
# to 6.4e-7 in absolute terms, which is single-precision resolution on an entry of
# 16.67 — the whole of the discrepancy, and none of it convergence: their answer
# stops moving once `tol` passes 1e-10 and never improves again.
#
# **THIS IS M4's D7 ARRIVING A SECOND TIME BY A DIFFERENT MECHANISM.** There,
# PowerDynamics was measured at 3.5–18x further from the truth than us, through
# integration error. Here PowerFlows is roughly SEVEN ORDERS further, through a
# fixed-width admittance. Both say the same thing and it is worth saying twice: the
# oracle is a **floor, not a ceiling**. A 4e-9 agreement between two independently
# written solvers on a lossy meshed case is still a strong check — it is simply not
# a 1e-12 check, and the reason is known in advance here rather than discovered as
# a mystery in the test output.
#
# **Which is why the band cannot be `convergence_band`'s two terms.** Both sides'
# self-convergence is ~1e-15 on these cases; a band built from them alone would be
# four orders below the true gap and every channel would go red for a reason that
# is not a bug. The third term is [`float32_admittance_twin`](@ref): our own solver
# run on the network whose admittances have been rounded to the grid theirs lives
# on. It measures **their** implementation's error using **our** code, and it never
# looks at their answer — so "state the band before you see the gap" stays a
# property of the arithmetic rather than a discipline someone has to keep.

"""
    float32_admittance_twin(net::NetworkModel) -> NetworkModel

`net` with every branch impedance replaced by the one whose **admittance** lands
on the single-precision grid — the grid `PowerFlows` stores its `Ybus` on.

Solving this twin with our own solver and subtracting gives the error their
`ComplexF32` admittance costs, computed entirely on our side of the comparison.

**It is a BOUND, not an estimate, and deliberately so.** The twin rounds every
entry in one operation; their assembly rounds each entry independently and the
errors partly cancel. Measured on the three-bus radial: the twin predicts 6.44e-9
in `Vm` where the actual gap is 3.86e-9. Over-prediction is the property a band
wants — but it is also why [`powerflow_band`](@ref) takes `factor = 1` and not
M4's 3. M4's factor covered an *unmodelled* difference between two integrators;
here the dominant term is modelled and already conservative, and a factor picked
on top of it would be fitted to the very gap it judges.

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
    powerflow_band(net; channel, factor = 1, abstol = 1e-12, tol = 1e-12,
                   check_limits = true, dc = false)

The agreement band for one channel of the AC (or DC) comparison on `net`, and the
three terms it is made of.

Returns `(; band, ours, quantization, theirs)`. The band is the triangle
inequality `|a - b| <= |a - truth| + |truth - b|` with `|truth - b|` split into the
two things that actually put `b` away from the truth:

  - `ours`         — our solver's own convergence, `|ours(abstol) - ours(abstol/1000)|`;
  - `quantization` — **their** single-precision admittance, measured on **our**
    side as `|ours(net) - ours(float32_admittance_twin(net))|`. This is the term
    that dominates, by four orders, and the header says why;
  - `theirs`       — their solver's own convergence, `|theirs(tol) - theirs(1000*tol)|`.

Every term is a property of one side alone. None of them looks at the cross gap,
so the band is stated before the gap is seen by construction rather than by
discipline — and a mutation to the shared physics moves both of our runs together,
so the band does **not** widen to swallow the error it exists to expose. That last
property is what made M4's band safe under its anti-vacuity mutation, and it is
the reason to keep the shape.

`channel` picks the quantity: `s -> s.Vm`, `s -> s.θ`, `s -> s.flow`. **One band
per channel** — M4 measured what an aggregate band costs on a per-machine read.
The DC channel takes `dc = true` and gets its own band for its own reason: their
DC path runs through an iterative refinement with a separate tolerance, which is a
different mechanism from the Ybus quantization even though it lands at a similar
size.
"""
function powerflow_band(net::GridSim.NetworkModel; channel, factor::Real = 1,
                        abstol::Real = 1.0e-12, tol::Real = _PF_TOL,
                        check_limits::Bool = true, dc::Bool = false)
    factor > 0 || throw(ArgumentError("powerflow_band: factor must be > 0, got $factor."))
    gap(x, y) = maximum(abs, channel(x) .- channel(y))
    twin = float32_admittance_twin(net)
    if dc
        ours_c = GridSim.dc_powerflow(net)
        ours_f = GridSim.dc_powerflow(net)          # linear: one factorisation, no tolerance
        ours_t = GridSim.dc_powerflow(twin)
        theirs_c = oracle_dc_powerflow(net)
        theirs_f = theirs_c                          # their DC takes no tolerance argument
    else
        ours_c = GridSim.ac_powerflow(net; abstol = abstol)
        ours_f = GridSim.ac_powerflow(net; abstol = abstol / 1000)
        ours_t = GridSim.ac_powerflow(twin; abstol = abstol)
        theirs_c = oracle_powerflow(net; tol = tol, check_limits = check_limits)
        theirs_f = oracle_powerflow(net; tol = tol * 1000, check_limits = check_limits)
    end
    ours_term  = gap(ours_c, ours_f)
    quant_term = gap(ours_c, ours_t)
    their_term = gap(theirs_c, theirs_f)
    band = Float64(factor) * (ours_term + quant_term + their_term)
    band > 0 || throw(ArgumentError(
        "powerflow_band: the derived band is $band. Nothing moved on this channel — " *
        "not our convergence, not the single-precision twin, not theirs — which " *
        "means every entry is fixed by a constraint rather than solved (a slack " *
        "angle pinned to zero, a generator magnitude held at V_set). Compare those " *
        "with `==`; a band derived from a convergence that never happened is not a " *
        "band."))
    return (; band, ours = ours_term, quantization = quant_term, theirs = their_term)
end
