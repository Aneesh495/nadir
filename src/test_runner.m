:- module test_runner.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- use_module nadir_core.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.temporal.
:- import_module float, int, list, string, math.

main(!IO) :-
    io.write_string("=== Running NADIR Astrodynamics Test Suite ===\n", !IO),
    test_temporal(!IO),
    test_constants(!IO),
    io.write_string("=== All Engine Unit Tests Passed ===\n", !IO).

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
