# Minimal aggregate domain model for Milestone 1 (see docs/SPEC.md §7.3).
#
# This is deliberately tiny (~5 fields/unit). It is NOT the long-term data model
# — at the network-aware tiers we adopt PowerSystems.jl as the source of truth.
# The seam is designed so a future `from_powersystems(sys)` adapter can populate
# a `SystemModel`. Do not grow this into a parallel hand-maintained data model.
#
# Conventions (docs/SPEC.md §6):
#   - Engineering units at the data boundary (MVA, MW, Hz, seconds).
#   - Per-unit conversion (on S_base) happens inside the engine, not here.
#   - Concrete-typed fields only — abstractly-typed fields are Julia's biggest
#     performance cliff (docs/SPEC.md §4 "Type stability").

"""
    GeneratingUnit

One aggregate generating unit. All powers in engineering units (MVA / MW);
inertia `H` is on the unit's own base.
"""
struct GeneratingUnit
    id::Symbol
    S_rated::Float64   # MVA — rated power
    H::Float64         # s   — inertia constant (on this unit's own base)
    P0::Float64        # MW  — initial output
    R::Float64         # pu  — governor droop (on unit base)
    Pmax::Float64      # MW  — max output; headroom = Pmax - P0
end

"""
    SystemModel

A small single-frequency (center-of-inertia) system: a set of online units plus
system-wide constants. The canonical source of truth for M1.
"""
struct SystemModel
    S_base::Float64               # MVA — system power base
    f0::Float64                   # Hz  — nominal frequency
    D::Float64                    # pu/pu — load damping (typical 1–2)
    Tg::Float64                   # s   — aggregate governor/turbine lag
    units::Vector{GeneratingUnit}
end

"""
    example_system() -> SystemModel

A small, well-conditioned 4-unit example for experiments and tests. Numbers are
illustrative; the point is to be able to trip a unit and watch frequency dip.
"""
function example_system()
    units = [
        GeneratingUnit(:G1, 200.0, 4.0, 150.0, 0.05, 200.0),
        GeneratingUnit(:G2, 150.0, 3.5, 110.0, 0.05, 150.0),
        GeneratingUnit(:G3, 100.0, 3.0,  70.0, 0.05, 100.0),
        GeneratingUnit(:G4, 100.0, 2.5,  60.0, 0.05, 100.0),
    ]
    return SystemModel(550.0, 50.0, 1.5, 8.0, units)
end
