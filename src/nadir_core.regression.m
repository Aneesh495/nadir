:- module nadir_core.regression.
:- interface.

:- import_module io.

% Run astrodynamics regression suite in pure Mercury
:- pred run_regression_suite(io::di, io::uo) is det.

:- implementation.

:- import_module float, int, string, math, bool.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.propagator.
:- use_module nadir_core.access.
:- import_module nadir_core.access.occultation.

run_regression_suite(!IO) :-
    io.write_string("=== Running NADIR Astrodynamics Mercury Regression Suite ===\n", !IO),

    % Test 1: North Pole Bowring Geodetic Singularity (P -> 0, Z = b)
    B = wgs84_b,
    NorthPoleECEF = vec3(0.0, 0.0, B),
    NorthGeo = ecef_to_geodetic(NorthPoleECEF),
    LatNorth = NorthGeo ^ geo_lat,
    AltNorth = NorthGeo ^ geo_alt,
    ( if abs(LatNorth - half_pi) < 1.0e-7, abs(AltNorth) < 1.0e-3 then
        io.write_string("  [PASS] Regression: Bowring North Pole singularity resolves to lat=pi/2, alt=0m\n", !IO)
      else
        io.write_string("  [FAIL] Regression: Bowring North Pole singularity failed\n", !IO)
    ),

    % Test 2: South Pole Bowring Geodetic Singularity (P -> 0, Z = -b)
    SouthPoleECEF = vec3(0.0, 0.0, -B),
    SouthGeo = ecef_to_geodetic(SouthPoleECEF),
    LatSouth = SouthGeo ^ geo_lat,
    AltSouth = SouthGeo ^ geo_alt,
    ( if abs(LatSouth - (-half_pi)) < 1.0e-7, abs(AltSouth) < 1.0e-3 then
        io.write_string("  [PASS] Regression: Bowring South Pole singularity resolves to lat=-pi/2, alt=0m\n", !IO)
      else
        io.write_string("  [FAIL] Regression: Bowring South Pole singularity failed\n", !IO)
    ),

    % Test 3: Retrograde Orbit J2 Precession Sign Reversal
    % For prograde (i < 90 deg), cos(i) > 0 so dOmega/dt < 0 (westward regression)
    % For retrograde (i > 90 deg), cos(i) < 0 so dOmega/dt > 0 (eastward progression)
    SemiMajor = 7000000.0,
    ProgradeKep = keplerian_elements(SemiMajor, 0.001, (80.0 * astro_pi) / 180.0, 0.0, 0.0, 0.0),
    RetrogradeKep = keplerian_elements(SemiMajor, 0.001, (100.0 * astro_pi) / 180.0, 0.0, 0.0, 0.0),
    RatePrograde = j2_raan_rate(ProgradeKep),
    RateRetrograde = j2_raan_rate(RetrogradeKep),
    ( if RatePrograde < 0.0, RateRetrograde > 0.0 then
        io.write_string("  [PASS] Regression: J2 nodal precession sign reverses across 90 deg inclination\n", !IO)
      else
        io.write_string("  [FAIL] Regression: J2 nodal precession sign reversal failed\n", !IO)
    ),

    % Test 4: Geostationary Orbital Period exact match with Sidereal Day
    % A_geo = 42164140.0 meters gives T = 86164.1 seconds (approx 23h 56m 4s)
    GeoSemiMajor = 42164140.0,
    GeoPeriod = orbital_period(GeoSemiMajor),
    ( if abs(GeoPeriod - 86164.1) < 1.0 then
        io.write_string("  [PASS] Regression: Geostationary orbit period matches Earth sidereal day (~86164s)\n", !IO)
      else
        io.write_string("  [FAIL] Regression: Geostationary orbit period failed\n", !IO)
    ),

    % Test 5: Antipodal Line-of-Sight Occultation
    % Two satellites on opposite sides of Earth at 7000km altitude must be occulted
    SatA = vec3(7000000.0, 0.0, 0.0),
    SatB = vec3(-7000000.0, 0.0, 0.0),
    MinAlt = 100000.0,
    LinkAvail = is_link_available(SatA, SatB, MinAlt),
    ( if LinkAvail = no then
        io.write_string("  [PASS] Regression: Antipodal constellation crosslink is occulted by Earth\n", !IO)
      else
        io.write_string("  [FAIL] Regression: Antipodal occultation test failed\n", !IO)
    ),

    % Test 6: Direct Zenith Topocentric Elevation
    % A satellite directly radial to a surface station has elevation = 90 deg
    EquatorSite = geodetic(0.0, 0.0, 0.0),
    OverheadSatECEF = vec3(7000000.0, 0.0, 0.0),
    Topo = ecef_to_topocentric(EquatorSite, OverheadSatECEF),
    Elev = Topo ^ topo_elevation,
    ( if abs(Elev - half_pi) < 1.0e-7 then
        io.write_string("  [PASS] Regression: Direct radial zenith satellite produces 90 degree elevation\n", !IO)
      else
        io.write_string("  [FAIL] Regression: Direct radial zenith elevation test failed\n", !IO)
    ).
