:- module nadir.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module float, int, string, list, bool, maybe, pair.
:- use_module nadir_core.
:- use_module nadir_core.astro.
:- use_module nadir_core.access.
:- use_module nadir_core.platform.
:- use_module nadir_core.scheduler.
:- use_module nadir_core.isl.
:- use_module nadir_core.ground.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.propagator.
:- import_module nadir_core.access.target.
:- import_module nadir_core.platform.slew.
:- import_module nadir_core.platform.power.
:- import_module nadir_core.platform.storage.
:- import_module nadir_core.scheduler.types.
:- import_module nadir_core.scheduler.optimizer.
:- import_module nadir_core.isl.topology.
:- import_module nadir_core.isl.contact_graph.
:- import_module nadir_core.isl.routing.
:- import_module nadir_core.ground.stations.
:- import_module nadir_core.ground.passes.
:- import_module nadir_core.ground.downlink.
:- import_module nadir_core.io_tle.
:- import_module nadir_core.io_target.
:- import_module nadir_core.io_czml.
:- import_module nadir_core.io_geojson.
:- import_module nadir_core.sim.

main(!IO) :-
    io.command_line_arguments(Args, !IO),
    (
        Args = [],
        print_banner(!IO),
        print_usage(!IO)
    ;
        Args = [Cmd | SubArgs],
        ( if (Cmd = "help" ; Cmd = "--help" ; Cmd = "-h") then
            print_banner(!IO),
            print_usage(!IO)
          else if (Cmd = "version" ; Cmd = "--version" ; Cmd = "-v") then
            print_version(!IO)
          else if Cmd = "propagate" then
            handle_propagate(SubArgs, !IO)
          else if Cmd = "access" then
            handle_access(SubArgs, !IO)
          else if Cmd = "schedule" then
            handle_schedule(SubArgs, !IO)
          else if Cmd = "route" then
            handle_route(SubArgs, !IO)
          else if Cmd = "simulate" then
            handle_simulate(SubArgs, !IO)
          else
            io.format("Unknown command '%s'. Run 'nadir help' for usage.\n", [s(Cmd)], !IO)
        )
    ).

:- pred print_banner(io::di, io::uo) is det.
print_banner(!IO) :-
    io.write_string("================================================================================\n", !IO),
    io.write_string("       NADIR : Autonomous Earth Observation Constellation Mission Engine        \n", !IO),
    io.write_string("================================================================================\n", !IO).

:- pred print_version(io::di, io::uo) is det.
print_version(!IO) :-
    io.write_string("nadir version 1.0.0 (Apple Silicon aarch64 / Mercury 22.01.9)\n", !IO),
    io.write_string("Architecture: Pure Functional Core + Native C Acceleration Fastpaths\n", !IO),
    io.write_string("Astrodynamics: WGS-84 Geodesy, J2 Secular Dynamics, Cowell RK4, Halley Kepler\n", !IO).

:- pred print_usage(io::di, io::uo) is det.
print_usage(!IO) :-
    io.write_string("Usage: nadir <command> [options]\n\n", !IO),
    io.write_string("Available Commands:\n", !IO),
    io.write_string("  simulate     Execute discrete-event constellation mission simulation\n", !IO),
    io.write_string("               Options: --demo (runs 12-sat Walker-Delta operational demo)\n", !IO),
    io.write_string("                        --duration <sec> (simulation horizon, default: 1800)\n\n", !IO),
    io.write_string("  propagate    Propagate satellite orbit track over time\n", !IO),
    io.write_string("               Options: --alt <km> (orbital altitude, default: 500)\n", !IO),
    io.write_string("                        --inc <deg> (inclination, default: 97.4 SSO)\n", !IO),
    io.write_string("                        --duration <sec> (duration, default: 5400)\n\n", !IO),
    io.write_string("  access       Evaluate ground target visibility and access windows\n", !IO),
    io.write_string("               Options: --lat <deg> --lon <deg> (target coordinates)\n\n", !IO),
    io.write_string("  schedule     Run constraint satisfaction mission scheduling optimizer\n", !IO),
    io.write_string("               Options: --requests <count> (generate sample request workload)\n\n", !IO),
    io.write_string("  route        Compute Dijkstra shortest optical ISL path across laser mesh\n", !IO),
    io.write_string("               Options: --src <sat_id> --dst <sat_id>\n\n", !IO),
    io.write_string("  version      Print engine build and architecture information\n", !IO),
    io.write_string("  help         Display this help manual\n", !IO).

:- pred handle_simulate(list(string)::in, io::di, io::uo) is det.
handle_simulate(Args, !IO) :-
    Duration = parse_duration_flag(Args, 1800.0),
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    io.format("Initializing constellation mission simulation (Duration: %0.0fs)...\n",
              [f(Duration)], !IO),

    Walker = walker_delta(12, 3, 1, 550000.0, deg_to_rad(53.0)),
    Nodes  = generate_constellation_nodes(Walker),

    Tgt1 = observation_target("T01", "Suez Canal Maritime Corridor",
                              geodetic(deg_to_rad(30.5852), deg_to_rad(32.2654), 10.0),
                              0, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Tgt2 = observation_target("T02", "Strait of Malacca Chokepoint",
                              geodetic(deg_to_rad(4.2105), deg_to_rad(100.5518), 5.0),
                              0, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Tgt3 = observation_target("T03", "Panama Canal Locks",
                              geodetic(deg_to_rad(9.1012), deg_to_rad(-79.6953), 15.0),
                              1, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Targets = [Tgt1, Tgt2, Tgt3],

    Req1 = task_request("REQ_001", "T01", 0, 15.0, 100.0, add_seconds(Epoch0, Duration)),
    Req2 = task_request("REQ_002", "T02", 0, 20.0, 95.0, add_seconds(Epoch0, Duration)),
    Req3 = task_request("REQ_003", "T03", 1, 15.0, 70.0, add_seconds(Epoch0, Duration)),
    Requests = [Req1, Req2, Req3],

    GroundNet = standard_polar_and_equatorial_network,
    Config = mission_config("NADIR 12-Sat Walker Operational Run",
                            Epoch0, Duration, 30.0, Nodes, Targets, Requests, GroundNet),

    SimResult = run_mission_simulation(Config),
    Summary = format_simulation_summary(SimResult),
    io.write_string(Summary, !IO),
    io.nl(!IO).

:- pred handle_propagate(list(string)::in, io::di, io::uo) is det.
handle_propagate(Args, !IO) :-
    AltKm = parse_float_flag(Args, "--alt", 500.0),
    IncDeg = parse_float_flag(Args, "--inc", 97.4),
    Duration = parse_duration_flag(Args, 5400.0),
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    A = wgs84_a + (AltKm * 1000.0),
    Kep = keplerian_elements(A, 0.001, deg_to_rad(IncDeg), 0.0, 0.0, 0.0),
    Period = orbital_period(A),
    Track = propagate_orbit_track(Kep, Epoch0, 60.0, Duration, 200),
    io.format("Orbit Semi-Major Axis: %0.1f km | Inclination: %0.2f deg | Period: %0.1f min\n",
        [f(A / 1000.0), f(IncDeg), f(Period / 60.0)], !IO),
    io.format("Propagated %d ephemeris points over %0.0f seconds horizon.\n",
        [i(list.length(Track)), f(Duration)], !IO),
    ( if Track = [P1, P2 | _] then
        io.format("Sample Point 1: %s\n", [s(format_ephemeris_point(P1))], !IO),
        io.format("Sample Point 2: %s\n", [s(format_ephemeris_point(P2))], !IO)
      else
        true
    ).

:- pred handle_access(list(string)::in, io::di, io::uo) is det.
handle_access(Args, !IO) :-
    LatDeg = parse_float_flag(Args, "--lat", 30.5852),
    LonDeg = parse_float_flag(Args, "--lon", 32.2654),
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    Tgt = observation_target("TGT_USER", "Custom Coordinate Target",
                             geodetic(deg_to_rad(LatDeg), deg_to_rad(LonDeg), 0.0),
                             0, deg_to_rad(15.0), deg_to_rad(35.0), deg_to_rad(10.0)),
    Kep = keplerian_elements(wgs84_a + 500000.0, 0.001, deg_to_rad(97.4), 0.0, 0.0, 0.0),
    Track = propagate_orbit_track(Kep, Epoch0, 30.0, 5400.0, 200),
    Windows = compute_target_access_windows("SAT_01", Tgt, Track),
    io.format("Evaluated target at [%0.4f, %0.4f]. Identified %d access windows.\n",
        [f(LatDeg), f(LonDeg), i(list.length(Windows))], !IO),
    list.foldl((pred(W::in, IO_in::di, IO_out::uo) is det :-
        io.format("  Access Window: %s\n", [s(format_access_window(W))], IO_in, IO_out)
    ), Windows, !IO).

:- pred handle_schedule(list(string)::in, io::di, io::uo) is det.
handle_schedule(_Args, !IO) :-
    Epoch0 = datetime(2026, 6, 21, 12, 0, 0.0),
    _Tgt1 = observation_target("T01", "Amazon Basin", geodetic(deg_to_rad(-3.4), deg_to_rad(-62.2), 0.0),
                               0, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    _Tgt2 = observation_target("T02", "Sahara Desert", geodetic(deg_to_rad(23.4), deg_to_rad(12.5), 0.0),
                               1, deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0)),
    Req1 = task_request("REQ_01", "T01", 0, 15.0, 100.0, add_seconds(Epoch0, 3600.0)),
    Req2 = task_request("REQ_02", "T02", 1, 20.0, 80.0, add_seconds(Epoch0, 3600.0)),
    W1 = target_access_window("T01", "SAT_01", Epoch0, 100.0, Epoch0, 200.0, 100.0, 1.2, 0.15, 0.8),
    W2 = target_access_window("T02", "SAT_01", Epoch0, 300.0, Epoch0, 450.0, 150.0, 1.1, 0.20, 0.7),
    Schedule = solve_constellation_schedule(default_agile_adcs, default_power_specs,
                                            default_storage_specs, [Req1, Req2], [W1, W2]),
    io.format("Mission Scheduler Result: %d observations scheduled.\n",
        [i(list.length(Schedule ^ cs_observations))], !IO),
    list.foldl((pred(Obs::in, IO_in::di, IO_out::uo) is det :-
        io.format("  Scheduled Obs: %s\n", [s(format_scheduled_observation(Obs))], IO_in, IO_out)
    ), Schedule ^ cs_observations, !IO).

:- pred handle_route(list(string)::in, io::di, io::uo) is det.
handle_route(_Args, !IO) :-
    Walker = walker_delta(48, 4, 1, 550000.0, deg_to_rad(53.0)),
    Nodes = generate_constellation_nodes(Walker),
    SatStates = list.map((func(N) = (N ^ sat_id - kepler_to_rv(N ^ sat_keplerian))), Nodes),
    ContactGraph = build_instantaneous_contact_graph(0.0, SatStates, 5000000.0),
    SrcSat = "SAT_P00_S00",
    DstSat = "SAT_P00_S02",
    Route = find_shortest_isl_route(ContactGraph, SrcSat, DstSat),
    ( if Route ^ ir_is_routable = yes then
        Hops = list.length(Route ^ ir_hop_path) - 1,
        PathStr = string.join_list(" -> ", Route ^ ir_hop_path),
        io.format("ISL Route Found (%d hops, Latency: %0.2f ms):\n  Path: %s\n",
            [i(Hops), f(Route ^ ir_total_delay_sec * 1000.0), s(PathStr)], !IO)
      else
        io.format("Destination satellite %s was not reachable across ISL mesh.\n", [s(DstSat)], !IO)
    ).

:- func parse_duration_flag(list(string), float) = float.
parse_duration_flag(Args, Default) = Duration :-
    Duration = parse_float_flag(Args, "--duration", Default).

:- func parse_float_flag(list(string), string, float) = float.
parse_float_flag([], _Flag, Default) = Default.
parse_float_flag([Head | Rest], Flag, Default) = Val :-
    ( if Head = Flag then
        ( if Rest = [ValStr | _], string.to_float(ValStr, Parsed) then
            Val = Parsed
          else
            Val = Default
        )
      else
        Val = parse_float_flag(Rest, Flag, Default)
    ).
