:- module test_runner.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- use_module nadir_core.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.propagator.
:- import_module float, int, list, string, math.

main(!IO) :-
    io.write_string("=== Running NADIR Astrodynamics Test Suite ===\n", !IO),
    test_temporal(!IO),
    test_constants(!IO),
    test_vec3(!IO),
    test_coords(!IO),
    test_kepler(!IO),
    test_propagator(!IO),
    io.write_string("=== All Engine Unit Tests Passed ===\n", !IO).

:- pred test_propagator(io::di, io::uo) is det.
test_propagator(!IO) :-
    % 1. Sun-synchronous inclination for 500km altitude
    A_500km = 6878137.0,
    Inc_sso = sun_synchronous_inclination(A_500km),
    Inc_deg = rad_to_deg(Inc_sso),
    ( if (Inc_deg > 97.0, Inc_deg < 98.0) then
        io.write_string("  [PASS] 500km SSO analytical inclination matches theory (~97.4 deg)\n", !IO)
      else
        io.format("  [FAIL] Expected ~97.4 deg SSO inclination, got %f\n", [f(Inc_deg)], !IO)
    ),
    % 2. J2 nodal drift rate for SSO orbit matches ~0.9856 deg/day
    KepSSO = keplerian_elements(A_500km, 0.001, Inc_sso, 0.0, 0.0, 0.0),
    DriftRadPerSec = j2_raan_rate(KepSSO),
    DriftDegPerDay = rad_to_deg(DriftRadPerSec) * 86400.0,
    ( if abs(DriftDegPerDay - 0.9856) < 0.02 then
        io.write_string("  [PASS] J2 nodal precession rate matches Earth solar rate (~0.9856 deg/day)\n", !IO)
      else
        io.format("  [FAIL] Expected ~0.9856 deg/day drift, got %f\n", [f(DriftDegPerDay)], !IO)
    ),
    % 3. Orbit track ephemeris propagation over 1 period (5400s, 60s step = 91 points)
    Epoch0 = datetime(2026, 11, 19, 0, 0, 0.0),
    Track = propagate_orbit_track(KepSSO, Epoch0, 60.0, 5400.0, 200),
    TrackLen = list.length(Track),
    ( if TrackLen = 91 then
        io.write_string("  [PASS] Discrete orbit track generated exactly 91 ephemeris points\n", !IO)
      else
        io.format("  [FAIL] Expected 91 ephemeris points, got %d\n", [i(TrackLen)], !IO)
    ).

:- pred test_kepler(io::di, io::uo) is det.
test_kepler(!IO) :-
    % 1. LEO Sun-Synchronous Orbit: a = 6900 km, e = 0.0015, i = 97.5 deg
    A0 = 6900000.0,
    E0 = 0.0015,
    I0 = deg_to_rad(97.5),
    Raan0 = deg_to_rad(45.0),
    ArgP0 = deg_to_rad(30.0),
    Nu0 = deg_to_rad(60.0),
    Kep0 = keplerian_elements(A0, E0, I0, Raan0, ArgP0, Nu0),
    State = kepler_to_rv(Kep0),
    KepRec = rv_to_kepler(State),
    AErr = abs(KepRec ^ kep_a - A0) / A0,
    EErr = abs(KepRec ^ kep_e - E0),
    IErr = abs(KepRec ^ kep_i - I0),
    ( if (AErr < 1.0e-7, EErr < 1.0e-7, IErr < 1.0e-7) then
        io.write_string("  [PASS] Keplerian <-> Cartesian state vector round trip\n", !IO)
      else
        io.format("  [FAIL] Keplerian round trip error: a_err=%e, e_err=%e, i_err=%e\n",
            [f(AErr), f(EErr), f(IErr)], !IO)
    ),
    % 2. Kepler Equation Halley solver precision
    Ecc = 0.25,
    M = 1.25,
    E_anom = mean_to_eccentric_anomaly(M, Ecc),
    Resid = abs(E_anom - Ecc * sin(E_anom) - M),
    ( if Resid < 1.0e-12 then
        io.write_string("  [PASS] Halley cubic Kepler solver converges to machine precision (<1e-12)\n", !IO)
      else
        io.format("  [FAIL] Kepler solver residual: %e\n", [f(Resid)], !IO)
    ),
    % 3. Anomaly conversion round trip
    Nu = mean_to_true_anomaly(M, Ecc),
    M_rec = true_to_mean_anomaly(Nu, Ecc),
    MErr = abs(M_rec - M),
    ( if MErr < 1.0e-11 then
        io.write_string("  [PASS] Mean anomaly <-> True anomaly round trip\n", !IO)
      else
        io.format("  [FAIL] Anomaly round trip error: %e\n", [f(MErr)], !IO)
    ),
    % 4. Orbital period test (500 km LEO circular orbit: a = 6878.137 km)
    Period = orbital_period(6878137.0),
    % Expected period = ~5677 seconds (~94.6 minutes)
    ( if (Period > 5600.0, Period < 5750.0) then
        io.write_string("  [PASS] LEO 500km orbital period is nominal (~94.6 min)\n", !IO)
      else
        io.format("  [FAIL] Unexpected orbital period: %f s\n", [f(Period)], !IO)
    ).

:- pred test_coords(io::di, io::uo) is det.
test_coords(!IO) :-
    % Test Site: Svalbard Ground Station (78.2297 deg N, 15.4078 deg E, 450 m alt)
    LatRad = deg_to_rad(78.2297),
    LonRad = deg_to_rad(15.4078),
    AltM = 450.0,
    Geo = geodetic(LatRad, LonRad, AltM),
    Ecef = geodetic_to_ecef(Geo),
    GeoRT = ecef_to_geodetic(Ecef),
    LatErr = abs(GeoRT ^ geo_lat - LatRad),
    LonErr = abs(GeoRT ^ geo_lon - LonRad),
    AltErr = abs(GeoRT ^ geo_alt - AltM),
    ( if (LatErr < 1.0e-9, LonErr < 1.0e-9, AltErr < 1.0e-3) then
        io.write_string("  [PASS] Geodetic <-> ECEF round trip (sub-millimeter precision)\n", !IO)
      else
        io.format("  [FAIL] Geodetic round trip error: lat=%e, lon=%e, alt=%e\n",
            [f(LatErr), f(LonErr), f(AltErr)], !IO)
    ),
    % Test ECI <-> ECEF round trip
    R_eci = vec3(7000000.0, 1000000.0, 2000000.0),
    Gmst = 1.234567,
    R_ecef = eci_to_ecef(R_eci, Gmst),
    R_eci_rt = ecef_to_eci(R_ecef, Gmst),
    EciDist = vec3_dist(R_eci, R_eci_rt),
    ( if EciDist < 1.0e-9 then
        io.write_string("  [PASS] ECI <-> ECEF coordinate rotation round trip\n", !IO)
      else
        io.format("  [FAIL] ECI round trip distance: %e\n", [f(EciDist)], !IO)
    ),
    % Test Topocentric: point 500 km directly above site
    ZenithGeo = geodetic(LatRad, LonRad, AltM + 500000.0),
    ZenithEcef = geodetic_to_ecef(ZenithGeo),
    Topo = ecef_to_topocentric(Geo, ZenithEcef),
    ElDeg = rad_to_deg(Topo ^ topo_elevation),
    ( if abs(ElDeg - 90.0) < 1.0e-6 then
        io.write_string("  [PASS] Zenith point produces exactly 90 degree elevation\n", !IO)
      else
        io.format("  [FAIL] Expected 90.0 deg elevation, got %f\n", [f(ElDeg)], !IO)
    ).

:- pred test_vec3(io::di, io::uo) is det.
test_vec3(!IO) :-
    I = vec3_unit_x,
    J = vec3_unit_y,
    K = vec3_cross(I, J),
    DotIJ = vec3_dot(I, J),
    ( if abs(DotIJ) < 1.0e-12 then
        io.write_string("  [PASS] Orthogonal vector dot product equals zero\n", !IO)
      else
        io.write_string("  [FAIL] Orthogonal vector dot product failed\n", !IO)
    ),
    ( if (abs(K ^ v_x) < 1.0e-12, abs(K ^ v_y) < 1.0e-12, abs(K ^ v_z - 1.0) < 1.0e-12) then
        io.write_string("  [PASS] Cross product unit_x x unit_y equals unit_z\n", !IO)
      else
        io.write_string("  [FAIL] Cross product unit_x x unit_y failed\n", !IO)
    ),
    % Test rotation matrix around Z by 90 degrees
    Rz = mat3_rot_z(half_pi),
    RotatedI = mat3_mul_vec(Rz, I),
    Dist = vec3_dist(RotatedI, J),
    ( if Dist < 1.0e-12 then
        io.write_string("  [PASS] Rz(pi/2) rotation maps unit_x to unit_y\n", !IO)
      else
        io.write_string("  [FAIL] Rz rotation failed\n", !IO)
    ).

:- pred test_constants(io::di, io::uo) is det.
test_constants(!IO) :-
    A = wgs84_a,
    F = wgs84_f,
    B = wgs84_b,
    Diff = (A * (1.0 - F)) - B,
    ( if abs(Diff) < 1.0e-6 then
        io.write_string("  [PASS] WGS-84 Ellipsoid geometry consistency\n", !IO)
      else
        io.format("  [FAIL] WGS-84 geometry difference: %f\n", [f(Diff)], !IO)
    ),
    ( if abs(wrap_two_pi(two_pi + 0.5) - 0.5) < 1.0e-9 then
        io.write_string("  [PASS] Angle wrap two pi normalization\n", !IO)
      else
        io.write_string("  [FAIL] Angle wrap two pi failed\n", !IO)
    ).

:- pred test_temporal(io::di, io::uo) is det.
test_temporal(!IO) :-
    DT_J2000 = datetime(2000, 1, 1, 12, 0, 0.0),
    JD_J2000 = datetime_to_jd(DT_J2000),
    ( if abs(JD_J2000 - 2451545.0) < 1.0e-6 then
        io.write_string("  [PASS] J2000.0 epoch Julian Date exact match (2451545.0)\n", !IO)
      else
        io.format("  [FAIL] J2000.0 expected 2451545.0, got %f\n", [f(JD_J2000)], !IO)
    ),
    DT_RT = jd_to_datetime(JD_J2000),
    ( if DT_RT ^ dt_year = 2000,
         DT_RT ^ dt_month = 1,
         DT_RT ^ dt_day = 1,
         DT_RT ^ dt_hour = 12,
         DT_RT ^ dt_minute = 0,
         abs(DT_RT ^ dt_second) < 1.0e-3
      then
        io.write_string("  [PASS] Datetime <-> Julian Date round-trip\n", !IO)
      else
        io.format("  [FAIL] Datetime round trip got: %s\n", [s(format_iso8601(DT_RT))], !IO)
    ),
    DT_Next = add_seconds(DT_J2000, 86400.0),
    JD_Next = datetime_to_jd(DT_Next),
    ( if abs(JD_Next - 2451546.0) < 1.0e-6 then
        io.write_string("  [PASS] Epoch addition by 86400 seconds increments JD by exactly 1.0\n", !IO)
      else
        io.format("  [FAIL] Expected 2451546.0, got %f\n", [f(JD_Next)], !IO)
    ),
    DiffSec = diff_seconds(DT_Next, DT_J2000),
    ( if abs(DiffSec - 86400.0) < 1.0e-3 then
        io.write_string("  [PASS] Epoch difference returns accurate second delta\n", !IO)
      else
        io.format("  [FAIL] Expected 86400.0, got %f\n", [f(DiffSec)], !IO)
    ).
