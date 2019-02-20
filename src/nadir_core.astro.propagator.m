:- module nadir_core.astro.propagator.
:- interface.

:- import_module float, string, list.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.temporal.

:- type orbit_ephemeris_point
    --->    orbit_ephemeris_point(
                oep_epoch   :: datetime,
                oep_dt_sec  :: float,
                oep_eci_pos :: vec3,
                oep_eci_vel :: vec3,
                oep_ecef_pos:: vec3,
                oep_geo_pos :: geodetic
            ).

% J2 Secular Drift Rates (rad / s)
:- func j2_raan_rate(keplerian_elements) = float.
:- func j2_arg_perigee_rate(keplerian_elements) = float.
:- func j2_perturbed_mean_motion(keplerian_elements) = float.

% Orbit propagation
:- func propagate_j2(keplerian_elements, float) = keplerian_elements.
:- func propagate_j2_state(keplerian_elements, float) = orbit_state.
:- func propagate_orbit_track(keplerian_elements, datetime, float, float, int) = list(orbit_ephemeris_point).

% Sun-synchronous orbit inclination synthesis
% Calculates the exact inclination in radians for a circular orbit of semi-major axis A to be sun-synchronous
:- func sun_synchronous_inclination(float) = float.

% Formatting
:- func format_ephemeris_point(orbit_ephemeris_point) = string.

:- implementation.

:- import_module math, int.
:- import_module nadir_core.astro.constants.

% J2 Nodal Precession Rate: d(Omega)/dt = -1.5 * J2 * (Re/p)^2 * n * cos(i)
j2_raan_rate(keplerian_elements(A, E_val, Inc, _, _, _)) = RaanDot :-
    P = A * (1.0 - (E_val * E_val)),
    N = mean_motion(A),
    Re_over_p = earth_radius_equatorial / P,
    RaanDot = -1.5 * earth_j2 * (Re_over_p * Re_over_p) * N * cos(Inc).

% J2 Apsidal Rotation Rate: d(omega)/dt = 0.75 * J2 * (Re/p)^2 * n * (5*cos^2(i) - 1)
j2_arg_perigee_rate(keplerian_elements(A, E_val, Inc, _, _, _)) = ArgPDot :-
    P = A * (1.0 - (E_val * E_val)),
    N = mean_motion(A),
    Re_over_p = earth_radius_equatorial / P,
    CosI = cos(Inc),
    ArgPDot = 0.75 * earth_j2 * (Re_over_p * Re_over_p) * N * (5.0 * CosI * CosI - 1.0).

% Perturbed Mean Motion under J2
j2_perturbed_mean_motion(keplerian_elements(A, E_val, Inc, _, _, _)) = N_bar :-
    P = A * (1.0 - (E_val * E_val)),
    N0 = mean_motion(A),
    Re_over_p = earth_radius_equatorial / P,
    CosI = cos(Inc),
    Eta = sqrt(1.0 - (E_val * E_val)),
    Correction = 0.75 * earth_j2 * (Re_over_p * Re_over_p) * Eta * (3.0 * CosI * CosI - 1.0),
    N_bar = N0 * (1.0 + Correction).

% Circular Sun-Synchronous Orbit inclination solver
% Requires d(Omega)/dt = 1.99106e-7 rad/s (360 deg / 365.2422 days)
sun_synchronous_inclination(A) = Inc :-
    % Target rate in rad / s
    OmegaDotTarget = 1.991063853e-7,
    N = mean_motion(A),
    Re_over_a = earth_radius_equatorial / A,
    Factor = -1.5 * earth_j2 * (Re_over_a * Re_over_a) * N,
    CosInc = OmegaDotTarget / Factor,
    ( if CosInc < -1.0 then Inc = math.pi
      else if CosInc > 1.0 then Inc = 0.0
      else Inc = acos(CosInc)
    ).

propagate_j2(Kep0, Dt_sec) = Kep_t :-
    Kep0 = keplerian_elements(A, E_val, Inc, Raan0, ArgP0, Nu0),
    RaanRate = j2_raan_rate(Kep0),
    ArgPRate = j2_arg_perigee_rate(Kep0),
    N_bar    = j2_perturbed_mean_motion(Kep0),
    M0       = true_to_mean_anomaly(Nu0, E_val),
    % Update secular variables
    Raan_t   = wrap_two_pi(Raan0 + (RaanRate * Dt_sec)),
    ArgP_t   = wrap_two_pi(ArgP0 + (ArgPRate * Dt_sec)),
    M_t      = wrap_two_pi(M0 + (N_bar * Dt_sec)),
    Nu_t     = mean_to_true_anomaly(M_t, E_val),
    Kep_t    = keplerian_elements(A, E_val, Inc, Raan_t, ArgP_t, Nu_t).

propagate_j2_state(Kep0, Dt_sec) = kepler_to_rv(propagate_j2(Kep0, Dt_sec)).

propagate_orbit_track(Kep0, Epoch0, StepSec, TotalDuration, MaxSteps) = Points :-
    Points = step_orbit_track(Kep0, Epoch0, 0.0, StepSec, TotalDuration, MaxSteps, []).

:- func step_orbit_track(keplerian_elements, datetime, float, float, float, int, list(orbit_ephemeris_point)) = list(orbit_ephemeris_point).
step_orbit_track(Kep0, Epoch0, CurrDt, StepSec, TotalDuration, MaxSteps, Acc) = Result :-
    ( if (CurrDt > TotalDuration ; list.length(Acc) >= MaxSteps) then
        Result = list.reverse(Acc)
      else
        CurrEpoch = add_seconds(Epoch0, CurrDt),
        Gmst = datetime_to_gmst(CurrEpoch),
        OrbitSt = propagate_j2_state(Kep0, CurrDt),
        R_eci = OrbitSt ^ os_pos,
        V_eci = OrbitSt ^ os_vel,
        R_ecef = eci_to_ecef(R_eci, Gmst),
        GeoPos = ecef_to_geodetic(R_ecef),
        Point = orbit_ephemeris_point(CurrEpoch, CurrDt, R_eci, V_eci, R_ecef, GeoPos),
        NextDt = CurrDt + StepSec,
        Result = step_orbit_track(Kep0, Epoch0, NextDt, StepSec, TotalDuration, MaxSteps, [Point | Acc])
    ).

format_ephemeris_point(Point) = Str :-
    string.format("t=+%0.1fs [%s] PosECI: %s Geo: %s",
        [f(Point ^ oep_dt_sec),
         s(format_iso8601(Point ^ oep_epoch)),
         s(format_vec3(Point ^ oep_eci_pos)),
         s(format_geodetic_deg(Point ^ oep_geo_pos))], Str).
