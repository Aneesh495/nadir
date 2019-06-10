:- module bench_runner.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module float, int, string, list, math, pair.
:- use_module nadir_core.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.propagator.
:- import_module nadir_core.c_fastpath.
:- use_module nadir_core.isl.
:- import_module nadir_core.isl.topology.
:- import_module nadir_core.isl.contact_graph.

main(!IO) :-
    io.write_string("================================================================================\n", !IO),
    io.write_string("                       NADIR Astrodynamics Engine Benchmarks                    \n", !IO),
    io.write_string("================================================================================\n", !IO),
    io.write_string("  Benchmark Target                  Iterations    Time (ms)     Throughput      \n", !IO),
    io.write_string("--------------------------------------------------------------------------------\n", !IO),
    run_dot_benchmark(1000000, !IO),
    run_c_dot_benchmark(1000000, !IO),
    run_geodetic_benchmark(200000, !IO),
    run_c_geodetic_benchmark(200000, !IO),
    run_kepler_benchmark(50000, !IO),
    run_isl_graph_benchmark(100, !IO),
    io.write_string("================================================================================\n", !IO).

:- pred run_dot_benchmark(int::in, io::di, io::uo) is det.
run_dot_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    V1 = vec3(1.23, 4.56, 7.89),
    V2 = vec3(9.87, 6.54, 3.21),
    _Res = loop_dot_pure(N, V1, V2, 0.0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    Mops = (float(N) / ElapsedMs) / 1000.0,
    io.format("  Pure Mercury Vector Dot           %9d     %7.2f ms    %7.2f Mops/s\n",
        [i(N), f(ElapsedMs), f(Mops)], !IO).

:- func loop_dot_pure(int, vec3, vec3, float) = float.
loop_dot_pure(Count, V1, V2, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        D = vec3_dot(V1, V2),
        Res = loop_dot_pure(Count - 1, V1, V2, Acc + D)
    ).

:- pred run_c_dot_benchmark(int::in, io::di, io::uo) is det.
run_c_dot_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    _Res = loop_dot_c(N, 1.23, 4.56, 7.89, 9.87, 6.54, 3.21, 0.0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    Mops = (float(N) / ElapsedMs) / 1000.0,
    io.format("  C FFI Fastpath Vector Dot         %9d     %7.2f ms    %7.2f Mops/s\n",
        [i(N), f(ElapsedMs), f(Mops)], !IO).

:- func loop_dot_c(int, float, float, float, float, float, float, float) = float.
loop_dot_c(Count, X1, Y1, Z1, X2, Y2, Z2, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        D = fast_dot3(X1, Y1, Z1, X2, Y2, Z2),
        Res = loop_dot_c(Count - 1, X1, Y1, Z1, X2, Y2, Z2, Acc + D)
    ).

:- pred run_geodetic_benchmark(int::in, io::di, io::uo) is det.
run_geodetic_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    Geo0 = geodetic(deg_to_rad(37.7749), deg_to_rad(-122.4194), 150.0),
    _Res = loop_geodetic_pure(N, Geo0, 0.0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    Kops = (float(N) / ElapsedMs),
    io.format("  Pure Mercury Geodetic <-> ECEF    %9d     %7.2f ms    %7.2f Kops/s\n",
        [i(N), f(ElapsedMs), f(Kops)], !IO).

:- func loop_geodetic_pure(int, geodetic, float) = float.
loop_geodetic_pure(Count, Geo, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        Ecef = geodetic_to_ecef(Geo),
        GeoBack = ecef_to_geodetic(Ecef),
        Res = loop_geodetic_pure(Count - 1, Geo, Acc + GeoBack ^ geo_lat)
    ).

:- pred run_c_geodetic_benchmark(int::in, io::di, io::uo) is det.
run_c_geodetic_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    Ecef = vec3(4500000.0, 2000000.0, 4000000.0),
    _Res = loop_geodetic_c(N, Ecef, 0.0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    Kops = (float(N) / ElapsedMs),
    io.format("  C FFI Bowring Geodetic Fastpath   %9d     %7.2f ms    %7.2f Kops/s\n",
        [i(N), f(ElapsedMs), f(Kops)], !IO).

:- func loop_geodetic_c(int, vec3, float) = float.
loop_geodetic_c(Count, Ecef, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        Geo = fast_bowring_geodetic(Ecef),
        Res = loop_geodetic_c(Count - 1, Ecef, Acc + Geo ^ geo_lat)
    ).

:- pred run_kepler_benchmark(int::in, io::di, io::uo) is det.
run_kepler_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    Kep0 = keplerian_elements(wgs84_a + 500000.0, 0.001, deg_to_rad(53.0), 0.0, 0.0, 0.0),
    _Res = loop_kepler(N, Kep0, 0.0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    Kops = (float(N) / ElapsedMs),
    io.format("  Analytical Kepler J2 Propagation  %9d     %7.2f ms    %7.2f Kops/s\n",
        [i(N), f(ElapsedMs), f(Kops)], !IO).

:- func loop_kepler(int, keplerian_elements, float) = float.
loop_kepler(Count, Kep, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        Dt = float(Count) * 10.0,
        State = propagate_j2_state(Kep, Dt),
        Res = loop_kepler(Count - 1, Kep, Acc + (State ^ os_pos ^ v_x))
    ).

:- pred run_isl_graph_benchmark(int::in, io::di, io::uo) is det.
run_isl_graph_benchmark(N, !IO) :-
    T_start = fast_monotime_ns,
    Walker = walker_delta(24, 4, 1, 550000.0, deg_to_rad(53.0)),
    Nodes = generate_constellation_nodes(Walker),
    States = list.map((func(Node) = (Node ^ sat_id - kepler_to_rv(Node ^ sat_keplerian))), Nodes),
    _Res = loop_isl_graph(N, States, 0),
    T_end = fast_monotime_ns,
    ElapsedMs = (T_end - T_start) / 1.0e6,
    OpsPerSec = (float(N) / ElapsedMs) * 1000.0,
    io.format("  24-Sat ISL Mesh Graph Generation  %9d     %7.2f ms    %7.2f graphs/s\n",
        [i(N), f(ElapsedMs), f(OpsPerSec)], !IO).

:- func loop_isl_graph(int, list(pair(string, orbit_state)), int) = int.
loop_isl_graph(Count, States, Acc) = Res :-
    ( if Count =< 0 then
        Res = Acc
      else
        Graph = build_instantaneous_contact_graph(float(Count) * 10.0, States, 5000000.0),
        LinksCount = list.length(Graph ^ ccg_active_links),
        Res = loop_isl_graph(Count - 1, States, Acc + LinksCount)
    ).
