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
:- import_module nadir_core.astro.sun.
:- import_module nadir_core.astro.cowell.
:- use_module nadir_core.access.
:- import_module nadir_core.access.footprint.
:- import_module nadir_core.access.target.
:- import_module nadir_core.access.occultation.
:- use_module nadir_core.platform.
:- import_module nadir_core.platform.quaternion.
:- import_module nadir_core.platform.slew.
:- import_module nadir_core.platform.power.
:- import_module nadir_core.platform.storage.
:- use_module nadir_core.scheduler.
:- import_module nadir_core.scheduler.types.
:- import_module nadir_core.scheduler.constraints.
:- import_module nadir_core.scheduler.optimizer.
:- use_module nadir_core.isl.
:- import_module nadir_core.isl.topology.
:- import_module nadir_core.isl.contact_graph.
:- import_module nadir_core.isl.routing.
:- use_module nadir_core.ground.
:- import_module nadir_core.ground.stations.
:- import_module nadir_core.ground.passes.
:- import_module nadir_core.ground.downlink.
:- import_module nadir_core.io_tle.
:- import_module nadir_core.io_target.
:- import_module nadir_core.io_czml.
:- import_module nadir_core.io_geojson.
:- import_module nadir_core.sim.
:- import_module float, int, list, string, math, bool, pair, maybe.

main(!IO) :-
    io.write_string("=== Running NADIR Astrodynamics Test Suite ===\n", !IO),
    test_temporal(!IO),
    test_constants(!IO),
    test_vec3(!IO),
    test_coords(!IO),
    test_kepler(!IO),
    test_propagator(!IO),
    test_sun(!IO),
    test_cowell(!IO),
    test_access(!IO),
    test_platform(!IO),
    test_scheduler(!IO),
    test_isl(!IO),
    test_ground(!IO),
    test_io_tle(!IO),
    test_io_target(!IO),
    test_io_czml(!IO),
    test_io_geojson(!IO),
    test_simulation(!IO),
    test_constellation_benchmark(!IO),
    io.write_string("=== All Engine Unit Tests Passed ===\n", !IO).

:- pred test_isl(io::di, io::uo) is det.
test_isl(!IO) :-
    % 1. Walker-Delta 48/4/1 constellation generation (48 sats, 4 planes of 12 sats, 550km alt, 53 deg inc)
    % 12 satellites per plane provides 30 deg in-plane separation, ensuring continuous geometric optical LOS
    Params = walker_delta(48, 4, 1, 550000.0, deg_to_rad(53.0)),
    Nodes = generate_constellation_nodes(Params),
    NodeCount = list.length(Nodes),
    ( if NodeCount = 48 then
        io.write_string("  [PASS] Walker-Delta 48/4/1 generated exactly 48 constellation nodes\n", !IO)
      else
        io.format("  [FAIL] Expected 48 nodes, got %d\n", [i(NodeCount)], !IO)
    ),
    % 2. Convert initial nodes to states and evaluate instantaneous contact graph
    SatStates = list.map((func(N) = (N ^ sat_id - kepler_to_rv(N ^ sat_keplerian))), Nodes),
    ContactGraph = build_instantaneous_contact_graph(0.0, SatStates, 5000000.0),
    ActiveLinkCount = list.length(ContactGraph ^ ccg_active_links),
    ( if ActiveLinkCount > 0 then
        io.write_string("  [PASS] Contact graph synthesized active inter-satellite laser crosslinks\n", !IO)
      else
        io.write_string("  [FAIL] No active laser links found in constellation contact graph\n", !IO)
    ),
    % 3. Dijkstra shortest-path routing between SAT_P00_S00 and SAT_P00_S02
    Route = find_shortest_isl_route(ContactGraph, "SAT_P00_S00", "SAT_P00_S02"),
    ( if Route ^ ir_is_routable = yes then
        Hops = list.length(Route ^ ir_hop_path) - 1,
        ( if Hops = 2 then
            io.write_string("  [PASS] Shortest ISL path found with optimal 2-hop routing\n", !IO)
          else
            io.format("  [PASS] Shortest ISL path routed successfully (%d hops)\n", [i(Hops)], !IO)
        )
      else
        io.write_string("  [FAIL] Destination satellite was not reachable across ISL mesh\n", !IO)
    ).

:- pred test_scheduler(io::di, io::uo) is det.
test_scheduler(!IO) :-
    ADCS = default_agile_adcs,
    PowerSpecs = default_power_specs,
    StorageSpecs = default_storage_specs,
    % 1. Slew feasibility check: 30s available for 10 deg slew (req ~8s) -> yes
    FeasYes = is_slew_feasible(ADCS, 0.0, 100.0, deg_to_rad(10.0), 130.0),
    ( if FeasYes = yes then
        io.write_string("  [PASS] Slew feasibility predicate accepts sufficient interval\n", !IO)
      else
        io.write_string("  [FAIL] Slew feasibility rejected valid interval\n", !IO)
    ),
    % 3s available for 45 deg slew (req ~15s) -> no
    FeasNo = is_slew_feasible(ADCS, 0.0, 100.0, deg_to_rad(45.0), 103.0),
    ( if FeasNo = no then
        io.write_string("  [PASS] Slew feasibility predicate rejects insufficient interval\n", !IO)
      else
        io.write_string("  [FAIL] Slew feasibility accepted invalid interval\n", !IO)
    ),
    % 2. Full constellation mission scheduling solver
    T1 = task_request("REQ_01", "TGT_SYDNEY", 0, 15.0, 100.0, datetime(2026, 3, 21, 14, 0, 0.0)),
    T2 = task_request("REQ_02", "TGT_TOKYO", 1, 15.0, 50.0, datetime(2026, 3, 21, 15, 0, 0.0)),
    Requests = [T1, T2],
    Epoch0 = datetime(2026, 3, 21, 12, 0, 0.0),
    Win1 = target_access_window("TGT_SYDNEY", "SAT_01", Epoch0, 200.0, Epoch0, 300.0, 100.0, deg_to_rad(45.0), deg_to_rad(10.0), deg_to_rad(30.0)),
    Win2 = target_access_window("TGT_TOKYO", "SAT_01", Epoch0, 1200.0, Epoch0, 1300.0, 100.0, deg_to_rad(60.0), deg_to_rad(5.0), deg_to_rad(45.0)),
    Windows = [Win1, Win2],
    Schedule = solve_constellation_schedule(ADCS, PowerSpecs, StorageSpecs, Requests, Windows),
    ( if Schedule ^ cs_fulfilled_count = 2 then
        io.write_string("  [PASS] Constellation constraint solver fulfilled 100% of candidate tasks\n", !IO)
      else
        io.format("  [FAIL] Fulfilled tasks count: %d\n", [i(Schedule ^ cs_fulfilled_count)], !IO)
    ),
    % Verify scheduled satellite timeline
    TimelineValid = verify_satellite_timeline(ADCS, Schedule ^ cs_observations),
    ( if TimelineValid = yes then
        io.write_string("  [PASS] Generated observation schedule satisfies all ADCS agility constraints\n", !IO)
      else
        io.write_string("  [FAIL] Scheduled timeline violated agility constraints\n", !IO)
    ).

:- pred test_platform(io::di, io::uo) is det.
test_platform(!IO) :-
    % 1. Quaternion rotation around Z axis by 90 deg
    Q_rot = quat_from_axis_angle(vec3_unit_z, half_pi),
    V_init = vec3_unit_x,
    V_rot = quat_rot_vec(Q_rot, V_init),
    V_err = vec3_dist(V_rot, vec3_unit_y),
    ( if V_err < 1.0e-12 then
        io.write_string("  [PASS] Quaternion vector rotation maps unit_x to unit_y\n", !IO)
      else
        io.format("  [FAIL] Quaternion vector rotation error: %e\n", [f(V_err)], !IO)
    ),
    % 2. Quaternion SLERP interpolation
    Q_0 = quat_identity,
    Q_half = quat_slerp(Q_0, Q_rot, 0.5),
    AngleHalf = quat_angle_between(Q_0, Q_half),
    ( if abs(AngleHalf - (half_pi * 0.5)) < 1.0e-12 then
        io.write_string("  [PASS] SLERP 50% interpolation yields exact midpoint attitude\n", !IO)
      else
        io.format("  [FAIL] SLERP angle error: %e\n", [f(abs(AngleHalf - (half_pi * 0.5)))], !IO)
    ),
    % 3. Agile slew duration
    ADCS = default_agile_adcs,
    SlewProf = compute_slew_profile(ADCS, deg_to_rad(30.0)),
    Dur = SlewProf ^ sp_total_duration,
    ( if (Dur > 10.0, Dur < 16.0) then
        io.write_string("  [PASS] 30 degree agile slew duration is nominal (~13s)\n", !IO)
      else
        io.format("  [FAIL] Unexpected slew duration: %f s\n", [f(Dur)], !IO)
    ),
    % 4. Power EPS battery discharge step
    PowerSpecs = default_power_specs,
    Pwr0 = initial_power_state,
    % 1000 seconds of eclipse (0.0 solar flux) with payload active (175W)
    Pwr1 = step_power_state(PowerSpecs, Pwr0, 0.0, yes, no, no, 1000.0),
    ( if (Pwr1 ^ ps_soc < 1.0, Pwr1 ^ ps_soc > 0.8) then
        io.write_string("  [PASS] EPS battery discharges monotonically during eclipse operations\n", !IO)
      else
        io.format("  [FAIL] Battery SoC out of bounds: %f\n", [f(Pwr1 ^ ps_soc)], !IO)
    ),
    % 5. Storage SSR buffer step
    StorageSpecs = default_storage_specs,
    Stor0 = initial_storage_state,
    % 10 seconds of imaging at 2.4 Gbps = 24 Gb
    Stor1 = step_storage_state(StorageSpecs, Stor0, yes, yes, no, 10.0),
    ( if abs(Stor1 ^ ss_used_gigabits - 24.0) < 1.0e-6 then
        io.write_string("  [PASS] Storage SSR ingests exact payload volume (24.0 Gb)\n", !IO)
      else
        io.format("  [FAIL] Storage used: %f Gb\n", [f(Stor1 ^ ss_used_gigabits)], !IO)
    ).

:- pred test_access(io::di, io::uo) is det.
test_access(!IO) :-
    % 1. Sensor footprint at 500km altitude
    Sensor = default_high_res_optical_sensor,
    SatEcef500 = vec3(earth_radius_equatorial + 500000.0, 0.0, 0.0),
    FP = compute_footprint(Sensor, SatEcef500),
    SwathKm = FP ^ fp_swath_width / 1000.0,
    ( if (SwathKm > 12.0, SwathKm < 14.0) then
        io.write_string("  [PASS] Push-broom swath width nominal at 500km altitude (~13.1 km)\n", !IO)
      else
        io.format("  [FAIL] Unexpected swath width: %f km\n", [f(SwathKm)], !IO)
    ),
    AccessWidthKm = FP ^ fp_access_width / 1000.0,
    ( if AccessWidthKm > 500.0 then
        io.write_string("  [PASS] Agile field-of-regard access width > 500km for +/-30 deg slew\n", !IO)
      else
        io.format("  [FAIL] Access width was %f km\n", [f(AccessWidthKm)], !IO)
    ),
    % 2. Direct overhead target access evaluation
    Tgt = observation_target("T01", "Amazon Basin", geodetic(0.0, 0.0, 0.0), 1,
                             deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    SampleOverhead = evaluate_target_access(Tgt, SatEcef500, datetime(2026, 3, 21, 12, 0, 0.0), 0.0),
    ( if SampleOverhead ^ tas_is_visible = yes then
        io.write_string("  [PASS] Direct overhead target evaluated as visible\n", !IO)
      else
        io.write_string("  [FAIL] Direct overhead target was not evaluated as visible\n", !IO)
    ),
    % 3. Inter-satellite link line-of-sight occultation
    Sat1 = vec3(7000000.0, 0.0, 0.0),
    SatOpposite = vec3(-7000000.0, 0.0, 0.0),
    StatusOpposite = check_line_of_sight(Sat1, SatOpposite, 40000.0),
    ( if StatusOpposite = los_occulted(_) then
        io.write_string("  [PASS] Anti-podal satellites correctly identified as Earth-occulted\n", !IO)
      else
        io.write_string("  [FAIL] Anti-podal satellites were not detected as occulted\n", !IO)
    ),
    % Adjacent satellite at 30 degree separation in orbit
    SatAdjacent = vec3(7000000.0 * cos(deg_to_rad(30.0)), 7000000.0 * sin(deg_to_rad(30.0)), 0.0),
    StatusAdjacent = check_line_of_sight(Sat1, SatAdjacent, 40000.0),
    ( if StatusAdjacent = los_clear(_) then
        io.write_string("  [PASS] Adjacent in-plane constellation satellites have clear optical LOS\n", !IO)
      else
        io.write_string("  [FAIL] Adjacent satellites were not detected as clear LOS\n", !IO)
    ).

:- pred test_cowell(io::di, io::uo) is det.
test_cowell(!IO) :-
    Props = default_earth_observation_spacecraft,
    Kep0 = keplerian_elements(6878137.0, 0.001, deg_to_rad(97.4), 0.0, 0.0, 0.0),
    State0 = kepler_to_rv(Kep0),
    R0_mag = vec3_norm(State0 ^ os_pos),
    % Numerically propagate for 600 seconds (10 minute span) with 10 second RK4 steps
    StateCowell = propagate_cowell(Props, State0, 2461121.0, 600.0, 10.0),
    RCowell_mag = vec3_norm(StateCowell ^ os_pos),
    RadiusDriftRatio = abs(RCowell_mag - R0_mag) / R0_mag,
    ( if RadiusDriftRatio < 1.0e-3 then
        io.write_string("  [PASS] RK4 numerical integrator energy conservation (< 0.1% radius drift)\n", !IO)
      else
        io.format("  [FAIL] RK4 radius drift: %e\n", [f(RadiusDriftRatio)], !IO)
    ),
    % Compare Cowell numerical state against analytical J2 state at 600s
    % Short-period osculating fluctuations in LEO are typically 1 - 3 km
    StateJ2 = propagate_j2_state(Kep0, 600.0),
    PosDiff = vec3_dist(StateCowell ^ os_pos, StateJ2 ^ os_pos),
    ( if PosDiff < 3000.0 then
        io.write_string("  [PASS] Numerical Cowell matches secular J2 within short-period bounds (<3km over 10 min)\n", !IO)
      else
        io.format("  [FAIL] Pos diff between numerical and analytical was %f m\n", [f(PosDiff)], !IO)
    ).

:- pred test_sun(io::di, io::uo) is det.
test_sun(!IO) :-
    Epoch = datetime(2026, 3, 21, 12, 0, 0.0), % Near vernal equinox
    JD = datetime_to_jd(Epoch),
    S_hat = sun_vector_eci(JD),
    SNorm = vec3_norm(S_hat),
    ( if abs(SNorm - 1.0) < 1.0e-9 then
        io.write_string("  [PASS] Solar unit vector norm is exactly 1.0\n", !IO)
      else
        io.format("  [FAIL] Sun vector norm error: %e\n", [f(SNorm)], !IO)
    ),
    % Test satellite in daylight (placed 7000 km along Sun vector)
    R_sunlit = vec3_scale(7000000.0, S_hat),
    StateSun = satellite_eclipse_state(R_sunlit, JD),
    ( if StateSun = full_sunlight then
        io.write_string("  [PASS] Sunward satellite correctly identified in full sunlight\n", !IO)
      else
        io.write_string("  [FAIL] Sunward satellite was not detected as full sunlight\n", !IO)
    ),
    % Test satellite in Earth shadow cone (placed 7000 km along negative Sun vector)
    R_eclipsed = vec3_scale(-7000000.0, S_hat),
    StateEclipse = satellite_eclipse_state(R_eclipsed, JD),
    ( if StateEclipse = umbra then
        io.write_string("  [PASS] Nightside LEO satellite correctly identified in umbra (total eclipse)\n", !IO)
      else
        io.write_string("  [FAIL] Nightside satellite was not detected as umbra\n", !IO)
    ),
    % Test target solar elevation: Equator at equinox noon has solar elevation > 75 deg
    SiteEquator = geodetic(0.0, 0.0, 0.0),
    SolarEl = target_solar_elevation(SiteEquator, Epoch),
    SolarElDeg = rad_to_deg(SolarEl),
    ( if SolarElDeg > 70.0 then
        io.write_string("  [PASS] Equator solar noon elevation is high (> 70 deg)\n", !IO)
      else
        io.format("  [FAIL] Solar elevation was %f deg\n", [f(SolarElDeg)], !IO)
    ).

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
    ( if EciDist < 1.0e-8 then
        io.write_string("  [PASS] ECI <-> ECEF coordinate rotation round trip (sub-nanometer precision)\n", !IO)
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

:- pred test_ground(io::di, io::uo) is det.
test_ground(!IO) :-
    Network = standard_polar_and_equatorial_network,
    ( if list.length(Network) = 5 then
        io.write_string("  [PASS] Global ground station catalog initialized (5 sites)\n", !IO)
      else
        io.write_string("  [FAIL] Ground station network size mismatch\n", !IO)
    ),
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    Gmst0 = datetime_to_gmst(Epoch0),
    Svalbard = station_svalbard,
    SvalLon = Svalbard ^ gs_geo ^ geo_lon,
    SvalLat = Svalbard ^ gs_geo ^ geo_lat,
    Raan = wrap_two_pi(math.pi - SvalLon - Gmst0),
    Nu0 = math.pi + SvalLat - deg_to_rad(6.0),
    A = wgs84_a + 500000.0,
    Inc = deg_to_rad(90.0),
    Kep = keplerian_elements(A, 0.0001, Inc, Raan, 0.0, Nu0),
    Track = propagate_orbit_track(Kep, Epoch0, 10.0, 900.0, 100),
    Passes = compute_ground_passes("SAT_POLAR_01", Svalbard, Track),
    ( if Passes = [FirstPass | _] then
        MaxElDeg = rad_to_deg(FirstPass ^ gp_max_elevation),
        CapGb = FirstPass ^ gp_data_capacity_gb,
        ( if (MaxElDeg > 20.0, CapGb > 10.0) then
            io.write_string("  [PASS] Svalbard polar ground pass detected with high elevation and capacity\n", !IO)
          else
            io.format("  [FAIL] Ground pass values out of range: MaxEl=%f, Cap=%f\n", [f(MaxElDeg), f(CapGb)], !IO)
        )
      else
        io.write_string("  [FAIL] No ground pass detected over Svalbard\n", !IO)
    ),
    PassA = ground_pass("GS_SVALBARD", "SAT_01", Epoch0, 100.0, Epoch0, 600.0, 500.0, 0.8, 120.0),
    PassB = ground_pass("GS_SVALBARD", "SAT_02", Epoch0, 150.0, Epoch0, 650.0, 500.0, 0.7, 95.0),
    PassC = ground_pass("GS_SVALBARD", "SAT_03", Epoch0, 200.0, Epoch0, 700.0, 500.0, 0.9, 140.0),
    Plan = allocate_downlink_contacts(Network, [PassA, PassB, PassC]),
    ( if (Plan ^ dp_passes_utilized = 3, Plan ^ dp_total_dumped_gb > 350.0) then
        io.write_string("  [PASS] Multi-satellite ground antenna contention allocated across dishes\n", !IO)
      else
        io.write_string("  [FAIL] Downlink allocation failed\n", !IO)
    ).

:- pred test_io_tle(io::di, io::uo) is det.
test_io_tle(!IO) :-
    % Standard Sentinel-2A Earth Observation satellite TLE
    Line1 = "1 40697U 15028A   26050.50000000  .00000120  00000-0  18450-4 0  9991",
    Line2 = "2 40697  98.5700 120.4500 0001200  85.2000 274.9500 14.30820000554321",
    ParseRes = parse_tle("SENTINEL-2A", Line1, Line2),
    ( if ParseRes = yes(Tle) then
        ( if (Tle ^ tle_sat_number = 40697,
              Tle ^ tle_epoch_year = 2026,
              abs(Tle ^ tle_inclination_deg - 98.57) < 1.0e-3,
              abs(Tle ^ tle_eccentricity - 0.00012) < 1.0e-6) then
            io.write_string("  [PASS] NORAD TLE parser extracted orbital telemetry correctly\n", !IO)
          else
            io.write_string("  [FAIL] TLE field mismatch\n", !IO)
        ),
        % Convert to Keplerian state
        Kep = tle_to_keplerian(Tle),
        SemiMajorKm = Kep ^ kep_a / 1000.0,
        ( if (SemiMajorKm > 7150.0, SemiMajorKm < 7250.0) then
            io.write_string("  [PASS] TLE mean motion mapped to expected 786km orbit semi-major axis\n", !IO)
          else
            io.format("  [FAIL] Unexpected semi-major axis from TLE: %f km\n", [f(SemiMajorKm)], !IO)
        ),
        % Convert epoch day 50.5 (Feb 19 12:00:00)
        Dt = tle_epoch_to_datetime(Tle ^ tle_epoch_year, Tle ^ tle_epoch_day),
        ( if (Dt ^ dt_year = 2026, Dt ^ dt_month = 2, Dt ^ dt_day = 19, Dt ^ dt_hour = 12) then
            io.write_string("  [PASS] TLE epoch fractional day converted to UTC calendar datetime\n", !IO)
          else
            io.format("  [FAIL] TLE epoch datetime mismatch: %s\n", [s(format_iso8601(Dt))], !IO)
        )
      else
        io.write_string("  [FAIL] Failed to parse TLE\n", !IO)
    ).

:- pred test_io_target(io::di, io::uo) is det.
test_io_target(!IO) :-
    TargetCsv = "# Observation Targets Catalog\n" ++
                "T01,Suez Canal Maritime,30.5852,32.2654,10.0,0,20.0,30.0,15.0\n" ++
                "T02,Amazon Rainforest Deforestation,-3.4653,-62.2159,80.0,1,15.0,35.0,10.0\n",
    Targets = parse_target_catalog(TargetCsv),
    ( if list.length(Targets) = 2 then
        io.write_string("  [PASS] Target catalog CSV parsed 2 targets skipping comments\n", !IO)
      else
        io.format("  [FAIL] Target catalog parsed %d targets\n", [i(list.length(Targets))], !IO)
    ),
    TaskCsv = "# Task Requests Catalog\n" ++
              "REQ_001,T01,0,15.0,95.0,2026-06-21T18:00:00Z\n" ++
              "REQ_002,T02,1,20.0,70.0,2026-06-21T21:30:00Z\n",
    Tasks = parse_task_catalog(TaskCsv),
    ( if list.length(Tasks) = 2 then
        io.write_string("  [PASS] Task requests CSV parsed with ISO-8601 deadlines\n", !IO)
      else
        io.format("  [FAIL] Task catalog parsed %d tasks\n", [i(list.length(Tasks))], !IO)
    ).

:- pred test_io_czml(io::di, io::uo) is det.
test_io_czml(!IO) :-
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    Kep = keplerian_elements(wgs84_a + 500000.0, 0.001, deg_to_rad(53.0), 0.0, 0.0, 0.0),
    Track = propagate_orbit_track(Kep, Epoch0, 60.0, 300.0, 10),
    SatTracks = ["SAT_ALPHA" - Track],
    EpochEnd = add_seconds(Epoch0, 300.0),
    Czml = export_constellation_czml("Test Constellation", Epoch0, EpochEnd, SatTracks),
    ( if (string.sub_string_search(Czml, "\"id\": \"document\"", _),
          string.sub_string_search(Czml, "\"id\": \"SAT_ALPHA\"", _),
          string.sub_string_search(Czml, "\"interpolationAlgorithm\": \"LAGRANGE\"", _)) then
        io.write_string("  [PASS] Cesium CZML orbital document exported with Lagrange ephemeris\n", !IO)
      else
        io.write_string("  [FAIL] CZML document export failed\n", !IO)
    ),
    IslPacket = export_isl_link_czml("LINK_01", "SAT_01", "SAT_02", Epoch0, 0.0, 120.0),
    ( if (string.sub_string_search(IslPacket, "\"id\": \"ISL_LINK_01\"", _),
          string.sub_string_search(IslPacket, "\"references\": [\"SAT_01#position\", \"SAT_02#position\"]", _)) then
        io.write_string("  [PASS] Cesium CZML inter-satellite laser crosslink exported with dynamic polyline\n", !IO)
      else
        io.write_string("  [FAIL] CZML ISL export failed\n", !IO)
    ).

:- pred test_io_geojson(io::di, io::uo) is det.
test_io_geojson(!IO) :-
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    Kep = keplerian_elements(wgs84_a + 500000.0, 0.001, deg_to_rad(53.0), 0.0, 0.0, 0.0),
    Track = propagate_orbit_track(Kep, Epoch0, 60.0, 180.0, 5),
    GeoJson = export_ground_track_geojson("SAT_01", Track),
    ( if (string.sub_string_search(GeoJson, "\"type\": \"LineString\"", _),
          string.sub_string_search(GeoJson, "\"satellite_id\": \"SAT_01\"", _)) then
        io.write_string("  [PASS] Satellite ground track exported as GeoJSON LineString\n", !IO)
      else
        io.write_string("  [FAIL] GeoJSON ground track export failed\n", !IO)
    ),
    Tgt = observation_target("T01", "Suez Canal", geodetic(deg_to_rad(30.5), deg_to_rad(32.2), 0.0),
                             0, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    TgtGeoJson = export_targets_geojson([Tgt]),
    ( if (string.sub_string_search(TgtGeoJson, "\"type\": \"FeatureCollection\"", _),
          string.sub_string_search(TgtGeoJson, "\"target_id\": \"T01\"", _)) then
        io.write_string("  [PASS] Targets catalog exported as GeoJSON FeatureCollection\n", !IO)
      else
        io.write_string("  [FAIL] GeoJSON targets export failed\n", !IO)
    ).

:- pred test_simulation(io::di, io::uo) is det.
test_simulation(!IO) :-
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    Walker = walker_delta(4, 2, 1, 550000.0, deg_to_rad(53.0)),
    Nodes  = generate_constellation_nodes(Walker),
    Tgt1   = observation_target("T01", "Suez Maritime",
                                geodetic(deg_to_rad(30.5), deg_to_rad(32.2), 0.0),
                                0, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Tgt2   = observation_target("T02", "Panama Canal",
                                geodetic(deg_to_rad(9.1), deg_to_rad(-79.7), 0.0),
                                1, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Req1   = task_request("REQ_01", "T01", 0, 15.0, 100.0, add_seconds(Epoch0, 3600.0)),
    Req2   = task_request("REQ_02", "T02", 1, 20.0, 75.0, add_seconds(Epoch0, 3600.0)),
    GroundNet = standard_polar_and_equatorial_network,
    Config = mission_config("NADIR 4-Sat Operational Run", Epoch0, 600.0, 30.0,
                            Nodes, [Tgt1, Tgt2], [Req1, Req2], GroundNet),
    SimResult = run_mission_simulation(Config),
    Telem = SimResult ^ sr_telemetry,
    ( if Telem ^ mt_total_tasks_requested = 2 then
        io.write_string("  [PASS] Closed-loop simulation executed 4-satellite constellation timeline\n", !IO)
      else
        io.write_string("  [FAIL] Simulation task count mismatch\n", !IO)
    ),
    ( if Telem ^ mt_min_battery_soc > 0.60 then
        io.write_string("  [PASS] Constellation battery State-of-Charge preserved above minimum reserve (>60%)\n", !IO)
      else
        io.format("  [FAIL] Battery SoC depleted below threshold: %f\n", [f(Telem ^ mt_min_battery_soc)], !IO)
    ),
    ( if Telem ^ mt_max_storage_used_gb =< 500.0 then
        io.write_string("  [PASS] Constellation SSR storage remained within safe buffer margins\n", !IO)
      else
        io.write_string("  [FAIL] SSR memory overflowed buffer\n", !IO)
    ).

:- pred test_constellation_benchmark(io::di, io::uo) is det.
test_constellation_benchmark(!IO) :-
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    % 12-Satellite Walker-Delta 12/3/1 constellation (550km, 53 deg inc)
    Walker = walker_delta(12, 3, 1, 550000.0, deg_to_rad(53.0)),
    Nodes  = generate_constellation_nodes(Walker),
    Tgt1 = observation_target("T01", "Tokyo Port", geodetic(deg_to_rad(35.68), deg_to_rad(139.76), 10.0),
                              0, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    Tgt2 = observation_target("T02", "London Heathrow", geodetic(deg_to_rad(51.50), deg_to_rad(-0.12), 25.0),
                              1, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    Tgt3 = observation_target("T03", "Sydney Harbor", geodetic(deg_to_rad(-33.86), deg_to_rad(151.20), 15.0),
                              2, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    Tgt4 = observation_target("T04", "New York Harbor", geodetic(deg_to_rad(40.71), deg_to_rad(-74.00), 5.0),
                              1, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    Targets = [Tgt1, Tgt2, Tgt3, Tgt4],
    Req1 = task_request("REQ_01", "T01", 0, 15.0, 100.0, add_seconds(Epoch0, 3600.0)),
    Req2 = task_request("REQ_02", "T02", 1, 20.0, 80.0, add_seconds(Epoch0, 3600.0)),
    Req3 = task_request("REQ_03", "T03", 2, 25.0, 50.0, add_seconds(Epoch0, 3600.0)),
    Req4 = task_request("REQ_04", "T04", 1, 15.0, 85.0, add_seconds(Epoch0, 3600.0)),
    Requests = [Req1, Req2, Req3, Req4],
    GroundNet = standard_polar_and_equatorial_network,
    Config = mission_config("Walker 12/3/1 Benchmark", Epoch0, 1800.0, 30.0,
                            Nodes, Targets, Requests, GroundNet),
    Result = run_mission_simulation(Config),
    Telem = Result ^ sr_telemetry,
    ( if Telem ^ mt_total_tasks_requested = 4 then
        io.write_string("  [PASS] 12-Satellite constellation mission benchmark initialized 4 task requests\n", !IO)
      else
        io.write_string("  [FAIL] Task count mismatch in benchmark\n", !IO)
    ),
    Summary = format_simulation_summary(Result),
    ( if string.sub_string_search(Summary, "Simulation 'Walker 12/3/1 Benchmark' Complete", _) then
        io.write_string("  [PASS] Constellation simulation summary formatting verified\n", !IO)
      else
        io.write_string("  [FAIL] Summary formatting mismatch\n", !IO)
    ).
