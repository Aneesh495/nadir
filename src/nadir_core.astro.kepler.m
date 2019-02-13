:- module nadir_core.astro.kepler.
:- interface.

:- import_module float, string.
:- import_module nadir_core.astro.vec3.

:- type keplerian_elements
    --->    keplerian_elements(
                kep_a     :: float, % Semi-major axis in meters
                kep_e     :: float, % Eccentricity [0, 1)
                kep_i     :: float, % Inclination in radians [0, pi]
                kep_raan  :: float, % Right Ascension of Ascending Node in radians [0, 2*pi]
                kep_arg_p :: float, % Argument of Perigee in radians [0, 2*pi]
                kep_nu    :: float  % True Anomaly in radians [0, 2*pi]
            ).

:- type orbit_state
    --->    orbit_state(
                os_pos :: vec3, % Position in ECI frame (m)
                os_vel :: vec3  % Velocity in ECI frame (m/s)
            ).

% State conversion functions
:- func rv_to_kepler(orbit_state) = keplerian_elements.
:- func kepler_to_rv(keplerian_elements) = orbit_state.

% Anomaly conversion and Kepler equation solvers
:- func mean_to_eccentric_anomaly(float, float) = float.
:- func eccentric_to_true_anomaly(float, float) = float.
:- func true_to_eccentric_anomaly(float, float) = float.
:- func eccentric_to_mean_anomaly(float, float) = float.
:- func mean_to_true_anomaly(float, float) = float.
:- func true_to_mean_anomaly(float, float) = float.

% Orbital dynamics metrics
:- func orbital_period(float) = float.
:- func mean_motion(float) = float.

% Formatting
:- func format_keplerian(keplerian_elements) = string.

:- implementation.

:- import_module math, list, int.
:- import_module nadir_core.astro.constants.

orbital_period(A) = Period :-
    Period = two_pi * sqrt((A * A * A) / earth_mu).

mean_motion(A) = sqrt(earth_mu / (A * A * A)).

% Kepler Equation Solver via Newton-Raphson with Halley cubic acceleration
mean_to_eccentric_anomaly(M0, E_ecc) = E_out :-
    M = wrap_two_pi(M0),
    % Initial guess (Prussing & Conway)
    ( if E_ecc < 0.8 then
        E_init = M
      else
        E_init = math.pi
    ),
    E_out = iterate_kepler(M, E_ecc, E_init, 0).

:- func iterate_kepler(float, float, float, int) = float.
iterate_kepler(M, Ecc, E_curr, Iter) = E_next :-
    F = E_curr - Ecc * sin(E_curr) - M,
    ( if (abs(F) < 1.0e-13 ; Iter > 50) then
        E_next = E_curr
      else
        F_prime = 1.0 - Ecc * cos(E_curr),
        F_double_prime = Ecc * sin(E_curr),
        % Halley correction step
        Delta = -F / (F_prime - (F * F_double_prime) / (2.0 * F_prime)),
        E_next = iterate_kepler(M, Ecc, E_curr + Delta, Iter + 1)
    ).

eccentric_to_true_anomaly(E_anom, Ecc) = Nu :-
    SinE = sin(E_anom),
    CosE = cos(E_anom),
    Fac = sqrt(1.0 - (Ecc * Ecc)),
    Nu_raw = atan2(Fac * SinE, CosE - Ecc),
    Nu = wrap_two_pi(Nu_raw).

true_to_eccentric_anomaly(Nu, Ecc) = E_anom :-
    SinNu = sin(Nu),
    CosNu = cos(Nu),
    Fac = sqrt(1.0 - (Ecc * Ecc)),
    E_raw = atan2(Fac * SinNu, Ecc + CosNu),
    E_anom = wrap_two_pi(E_raw).

eccentric_to_mean_anomaly(E_anom, Ecc) = wrap_two_pi(E_anom - Ecc * sin(E_anom)).

mean_to_true_anomaly(M, Ecc) = eccentric_to_true_anomaly(mean_to_eccentric_anomaly(M, Ecc), Ecc).

true_to_mean_anomaly(Nu, Ecc) = eccentric_to_mean_anomaly(true_to_eccentric_anomaly(Nu, Ecc), Ecc).

% State Vector (r, v) to Classical Keplerian Elements
rv_to_kepler(orbit_state(R, V)) = keplerian_elements(A, E_val, Inc, Raan, ArgP, Nu) :-
    R_mag = vec3_norm(R),
    V_mag = vec3_norm(V),
    H = vec3_cross(R, V),
    H_mag = vec3_norm(H),
    % Node vector: n = k x h = (-hy, hx, 0)
    N = vec3(-H ^ v_y, H ^ v_x, 0.0),
    N_mag = vec3_norm(N),
    % Eccentricity vector: e = ((v^2 - mu/r)r - (r.v)v) / mu
    R_dot_V = vec3_dot(R, V),
    V2_sub = (V_mag * V_mag) - (earth_mu / R_mag),
    Term1 = vec3_scale(V2_sub, R),
    Term2 = vec3_scale(R_dot_V, V),
    E_vec = vec3_scale(1.0 / earth_mu, vec3_sub(Term1, Term2)),
    E_val0 = vec3_norm(E_vec),
    % Cap eccentricity for near-circular orbits
    ( if E_val0 < 1.0e-11 then E_val = 0.0 else E_val = E_val0 ),
    % Specific mechanical energy
    Energy = (0.5 * V_mag * V_mag) - (earth_mu / R_mag),
    A = -earth_mu / (2.0 * Energy),
    % Inclination
    Inc0 = acos(H ^ v_z / H_mag),
    Inc = wrap_two_pi(Inc0),
    % RAAN
    ( if N_mag > 1.0e-11 then
        Raan0 = acos(N ^ v_x / N_mag),
        ( if N ^ v_y < 0.0 then Raan = two_pi - Raan0 else Raan = Raan0 )
      else
        Raan = 0.0
    ),
    % Argument of Perigee
    ( if (N_mag > 1.0e-11, E_val > 1.0e-11) then
        ArgP0 = acos(vec3_dot(N, E_vec) / (N_mag * E_val)),
        ( if E_vec ^ v_z < 0.0 then ArgP = two_pi - ArgP0 else ArgP = ArgP0 )
      else
        ArgP = 0.0
    ),
    % True Anomaly
    ( if E_val > 1.0e-11 then
        Nu0 = acos(vec3_dot(E_vec, R) / (E_val * R_mag)),
        ( if R_dot_V < 0.0 then Nu = two_pi - Nu0 else Nu = Nu0 )
      else if N_mag > 1.0e-11 then
        % Circular inclined orbit: argument of latitude u = nu + arg_p
        U0 = acos(vec3_dot(N, R) / (N_mag * R_mag)),
        ( if R ^ v_z < 0.0 then Nu = two_pi - U0 else Nu = U0 )
      else
        % Circular equatorial orbit: true longitude
        Lon0 = acos(R ^ v_x / R_mag),
        ( if R ^ v_y < 0.0 then Nu = two_pi - Lon0 else Nu = Lon0 )
    ).

% Classical Keplerian Elements to State Vector (r, v)
kepler_to_rv(keplerian_elements(A, E_val, Inc, Raan, ArgP, Nu)) = orbit_state(R_eci, V_eci) :-
    P = A * (1.0 - (E_val * E_val)),
    CosNu = cos(Nu),
    SinNu = sin(Nu),
    R_mag = P / (1.0 + E_val * CosNu),
    % Perifocal position and velocity vectors
    R_pqw = vec3(R_mag * CosNu, R_mag * SinNu, 0.0),
    V_fac = sqrt(earth_mu / P),
    V_pqw = vec3(V_fac * (-SinNu), V_fac * (E_val + CosNu), 0.0),
    % Rotation matrix from Perifocal to ECI: R_z(-Raan) * R_x(-Inc) * R_z(-ArgP)
    R_raan = mat3_rot_z(-Raan),
    R_inc  = mat3_rot_x(-Inc),
    R_argp = mat3_rot_z(-ArgP),
    PqwToEci = mat3_mul(R_raan, mat3_mul(R_inc, R_argp)),
    R_eci = mat3_mul_vec(PqwToEci, R_pqw),
    V_eci = mat3_mul_vec(PqwToEci, V_pqw).

format_keplerian(keplerian_elements(A, E_val, Inc, Raan, ArgP, Nu)) = Str :-
    string.format("a: %0.1f km, e: %0.6f, i: %0.2f deg, RAAN: %0.2f deg, w: %0.2f deg, nu: %0.2f deg",
        [f(A / 1000.0), f(E_val), f(rad_to_deg(Inc)), f(rad_to_deg(Raan)),
         f(rad_to_deg(ArgP)), f(rad_to_deg(Nu))], Str).
