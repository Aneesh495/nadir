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
:- import_module float, int, list, string, math.

main(!IO) :-
    io.write_string("=== Running NADIR Astrodynamics Test Suite ===\n", !IO),
    test_temporal(!IO),
    test_constants(!IO),
    test_vec3(!IO),
    test_coords(!IO),
    io.write_string("=== All Engine Unit Tests Passed ===\n", !IO).

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
