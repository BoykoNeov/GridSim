pf_radial() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)

# 2. MESHED, lossless, MIXED ZIP shares. Meshed because a radial fixes every flow
#    by conservation alone and cannot see a wrong off-diagonal; mixed shares
#    because with `a_i = 0` a constant-current term dropped entirely is invisible.
pf_meshed() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0),
     Branch(:L13, :B1, :B3, 0.30, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.5, 0.3, 0.2)]; slack = :B1)

# 3. LOSSY. The only fixture in the repo on which `Branch.R` reaches a residual
#    equation and produces a number anyone can check.
pf_lossy() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0; R = 0.010),
     Branch(:L23, :B2, :B3, 0.15, 400.0; R = 0.020),
     Branch(:L13, :B1, :B3, 0.30, 400.0; R = 0.030)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.5, 0.3, 0.2)]; slack = :B1)

# 4. OFF-BASE: `S_base = 250` and no machine rated at it. With every machine on the
#    system base the rebase PowerSystems performs is the identity and a wrong one
#    cannot be seen — the independence claimed in `powerflow_oracle.jl`'s header
#    table is untestable without this fixture.
pf_offbase() = NetworkModel(250.0, 60.0,
    [Bus(:B1, 345.0), Bus(:B2, 345.0), Bus(:B3, 345.0)],
    [Branch(:L12, :B1, :B2, 0.08, 900.0; R = 0.008),
     Branch(:L23, :B2, :B3, 0.12, 900.0; R = 0.012),
     Branch(:L13, :B1, :B3, 0.25, 900.0; R = 0.025)],
    [Machine(:G1, :B1, 400.0, 5.0, 1.0, 0.2, 1.05, 150.0; V_set = 1.02),
     Machine(:G2, :B2, 150.0, 4.0, 1.0, 0.2, 1.03, 120.0; V_set = 1.01)],
    [Load(:D3, :B3, 270.0, 70.0, 0.4, 0.2, 0.4)]; slack = :B1)

# 5. A BINDING reactive limit at B2. `Q_max` is set below what the unlimited solve
#    asks for, so the bus must give up its voltage and hold the limit instead.
#    Tuned on OUR side alone before anything was compared: the first draft pulled
#    B3 down to 0.819 pu and `ac_powerflow`'s own voltage band refused it — the
#    guard doing its job, and cheaper to find here than in a suite run.
pf_qlimit(; Q_max = 0.10) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.10, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 20.0; V_set = 1.00),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 70.0; V_set = 1.05,
             Q_min = -Q_max, Q_max = Q_max)],
    [Load(:D3, :B3, 90.0, 25.0, 0.0, 0.0, 1.0)]; slack = :B1)

