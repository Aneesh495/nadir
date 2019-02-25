:- module nadir_core.astro.cowell.
:- interface.

:- import_module float.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.kepler.

:- type spacecraft_physical_properties
    --->    spacecraft_physical_properties(
                sc_mass           :: float, % Spacecraft dry + wet mass in kg
                sc_drag_area      :: float, % Cross-sectional drag area in m^2
                sc_drag_coeff     :: float, % Drag coefficient Cd (~2.2 for LEO)
                sc_srp_area       :: float, % Solar radiation pressure area in m^2
                sc_reflectivity   :: float  % Reflectivity coefficient Cr (~1.2 - 1.8)
            ).

% Total instantaneous orbital acceleration (m/s^2) in ECI frame
:- func cowell_total_acceleration(spacecraft_physical_properties, vec3, vec3, float) = vec3.

% Single RK4 step for orbit state: state at t + dt
:- func rk4_step(spacecraft_physical_properties, orbit_state, float, float) = orbit_state.

% Multi-step numerical trajectory propagation
:- func propagate_cowell(spacecraft_physical_properties, orbit_state, float, float, float) = orbit_state.

% Standard cubesat / microsat physical configuration
:- func default_earth_observation_spacecraft = spacecraft_physical_properties.

:- implementation.

:- import_module math.
:- import_module nadir_core.astro.constants.

default_earth_observation_spacecraft =
    spacecraft_physical_properties(120.0, 0.45, 2.2, 0.8, 1.3).

% Atmosphere density model (Harris-Priester / US Standard Atmosphere exponential approximation)
:- func atmospheric_density(float) = float.
atmospheric_density(Altitude_m) = Density :-
    H_km = Altitude_m / 1000.0,
    ( if H_km < 100.0 then
        Density = 5.297e-7 * exp(-H_km / 7.2)
      else if H_km < 200.0 then
        Density = 2.789e-10 * exp(-(H_km - 100.0) / 10.0)
      else if H_km < 300.0 then
        Density = 2.418e-11 * exp(-(H_km - 200.0) / 15.0)
      else if H_km < 400.0 then
        Density = 2.803e-12 * exp(-(H_km - 300.0) / 20.0)
      else if H_km < 500.0 then
        Density = 3.725e-13 * exp(-(H_km - 400.0) / 25.0)
      else if H_km < 600.0 then
        Density = 6.967e-14 * exp(-(H_km - 500.0) / 30.0)
      else if H_km < 700.0 then
        Density = 1.454e-14 * exp(-(H_km - 600.0) / 35.0)
      else if H_km < 800.0 then
        Density = 3.614e-15 * exp(-(H_km - 700.0) / 40.0)
      else
        Density = 1.170e-15 * exp(-(H_km - 800.0) / 50.0)
    ).

cowell_total_acceleration(Props, R_eci, V_eci, _Epoch_jd) = TotalAcc :-
    R_mag = vec3_norm(R_eci),
    % 1. Two-body central Newtonian gravity: a_0 = -mu * r / r^3
    Mu_over_r3 = earth_mu / (R_mag * R_mag * R_mag),
    A_central = vec3_scale(-Mu_over_r3, R_eci),
    % 2. J2 zonal harmonic acceleration
    Re = earth_radius_equatorial,
    Z = R_eci ^ v_z,
    Z_over_r = Z / R_mag,
    Z_over_r_sq = Z_over_r * Z_over_r,
    R_sq = R_mag * R_mag,
    R_5 = R_mag * R_sq * R_sq,
    J2_fac = -1.5 * earth_j2 * earth_mu * (Re * Re) / R_5,
    A_j2_x = J2_fac * (R_eci ^ v_x) * (1.0 - 5.0 * Z_over_r_sq),
    A_j2_y = J2_fac * (R_eci ^ v_y) * (1.0 - 5.0 * Z_over_r_sq),
    A_j2_z = J2_fac * Z * (3.0 - 5.0 * Z_over_r_sq),
    A_j2 = vec3(A_j2_x, A_j2_y, A_j2_z),
    % 3. Atmospheric drag acceleration: a_drag = -0.5 * (Cd * A / m) * rho * v_rel * v_rel_vec
    % Co-rotating atmosphere velocity: v_atm = omega x r
    Omega_vec = vec3(0.0, 0.0, earth_omega),
    V_atm = vec3_cross(Omega_vec, R_eci),
    V_rel = vec3_sub(V_eci, V_atm),
    V_rel_mag = vec3_norm(V_rel),
    Alt_m = R_mag - earth_radius_equatorial,
    Rho = atmospheric_density(Alt_m),
    Mass = Props ^ sc_mass,
    Area = Props ^ sc_drag_area,
    Cd = Props ^ sc_drag_coeff,
    ( if (Alt_m < 850000.0, Mass > 0.0) then
        DragScalar = -0.5 * (Cd * Area / Mass) * Rho * V_rel_mag,
        A_drag = vec3_scale(DragScalar, V_rel)
      else
        A_drag = vec3_zero
    ),
    TotalAcc = vec3_add(A_central, vec3_add(A_j2, A_drag)).

% 4th-order Runge-Kutta numerical integration step
rk4_step(Props, orbit_state(R0, V0), T_jd, Dt) = orbit_state(R_final, V_final) :-
    % k1
    K1_v = cowell_total_acceleration(Props, R0, V0, T_jd),
    K1_r = V0,
    % k2
    Dt_half = Dt * 0.5,
    R1 = vec3_add(R0, vec3_scale(Dt_half, K1_r)),
    V1 = vec3_add(V0, vec3_scale(Dt_half, K1_v)),
    K2_v = cowell_total_acceleration(Props, R1, V1, T_jd),
    K2_r = V1,
    % k3
    R2 = vec3_add(R0, vec3_scale(Dt_half, K2_r)),
    V2 = vec3_add(V0, vec3_scale(Dt_half, K2_v)),
    K3_v = cowell_total_acceleration(Props, R2, V2, T_jd),
    K3_r = V2,
    % k4
    R3 = vec3_add(R0, vec3_scale(Dt, K3_r)),
    V3 = vec3_add(V0, vec3_scale(Dt, K3_v)),
    K4_v = cowell_total_acceleration(Props, R3, V3, T_jd),
    K4_r = V3,
    % Combine Runge-Kutta increments
    % delta_r = (dt / 6) * (k1_r + 2*k2_r + 2*k3_r + k4_r)
    Sum_r = vec3_add(K1_r,
            vec3_add(vec3_scale(2.0, K2_r),
            vec3_add(vec3_scale(2.0, K3_r), K4_r))),
    Delta_r = vec3_scale(Dt / 6.0, Sum_r),
    R_final = vec3_add(R0, Delta_r),
    Sum_v = vec3_add(K1_v,
            vec3_add(vec3_scale(2.0, K2_v),
            vec3_add(vec3_scale(2.0, K3_v), K4_v))),
    Delta_v = vec3_scale(Dt / 6.0, Sum_v),
    V_final = vec3_add(V0, Delta_v).

propagate_cowell(Props, State0, T0_jd, TotalDt, StepDt) = FinalState :-
    FinalState = step_cowell_loop(Props, State0, T0_jd, 0.0, TotalDt, StepDt).

:- func step_cowell_loop(spacecraft_physical_properties, orbit_state, float, float, float, float) = orbit_state.
step_cowell_loop(Props, CurrState, T0_jd, CurrDt, TotalDt, StepDt) = OutState :-
    ( if CurrDt >= TotalDt then
        OutState = CurrState
      else
        RemDt = TotalDt - CurrDt,
        ( if RemDt < StepDt then H = RemDt else H = StepDt ),
        NextState = rk4_step(Props, CurrState, T0_jd + (CurrDt / 86400.0), H),
        OutState = step_cowell_loop(Props, NextState, T0_jd, CurrDt + H, TotalDt, StepDt)
    ).
