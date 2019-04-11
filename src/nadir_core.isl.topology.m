:- module nadir_core.isl.topology.
:- interface.

:- import_module float, int, string, list.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.kepler.

:- type constellation_params
    --->    walker_delta(
                wd_total_sats      :: int,   % T: Total satellites (e.g. 24)
                wd_num_planes      :: int,   % P: Number of planes (e.g. 4)
                wd_phasing_f       :: int,   % F: Relative spacing parameter [0, P-1]
                wd_altitude_m      :: float, % Orbit altitude (e.g. 550,000 m)
                wd_inclination_rad :: float  % Orbit inclination (e.g. 53.0 deg = 0.925 rad)
            )
    ;       walker_star_polar(
                wsp_total_sats     :: int,   % T: Total satellites (e.g. 72)
                wsp_num_planes     :: int,   % P: Planes (e.g. 6)
                wsp_altitude_m     :: float, % Orbit altitude (e.g. 500,000 m)
                wsp_inclination_rad:: float  % Near polar or SSO (e.g. 97.4 deg = 1.700 rad)
            ).

:- type satellite_node
    --->    satellite_node(
                sat_id             :: string,
                sat_plane_idx      :: int,
                sat_pos_in_plane   :: int,
                sat_keplerian      :: keplerian_elements
            ).

:- type optical_laser_terminal
    --->    terminal_fore    % In-plane forward link
    ;       terminal_aft     % In-plane backward link
    ;       terminal_left    % Cross-plane left neighbor
    ;       terminal_right.  % Cross-plane right neighbor

% Generate initial constellation satellite nodes at epoch 0
:- func generate_constellation_nodes(constellation_params) = list(satellite_node).

% Get nominal topology neighbor ID for a satellite terminal
:- func get_nominal_neighbor(constellation_params, int, int, optical_laser_terminal) = string.

% Formatting
:- func format_satellite_node(satellite_node) = string.

:- implementation.

:- import_module math.
:- import_module nadir_core.astro.constants.

generate_constellation_nodes(walker_delta(T, P, F, Alt_m, Inc_rad)) = Nodes :-
    A = earth_radius_equatorial + Alt_m,
    SatsPerPlane = T / P,
    Nodes = generate_delta_planes(0, P, SatsPerPlane, F, T, A, Inc_rad, []).

generate_constellation_nodes(walker_star_polar(T, P, Alt_m, Inc_rad)) = Nodes :-
    A = earth_radius_equatorial + Alt_m,
    SatsPerPlane = T / P,
    Nodes = generate_star_planes(0, P, SatsPerPlane, T, A, Inc_rad, []).

:- func generate_delta_planes(int, int, int, int, int, float, float, list(satellite_node)) = list(satellite_node).
generate_delta_planes(PlaneIdx, TotalPlanes, SatsPerPlane, F, T, A, Inc, Acc) = Result :-
    ( if PlaneIdx >= TotalPlanes then
        Result = list.reverse(Acc)
      else
        % RAAN for plane p: Omega = 2 * pi * p / P
        Raan = two_pi * float(PlaneIdx) / float(TotalPlanes),
        % Phasing offset for plane p: delta_M = 2 * pi * F * p / T
        PhaseOffset = two_pi * float(F * PlaneIdx) / float(T),
        PlaneNodes = generate_plane_sats(PlaneIdx, 0, SatsPerPlane, Raan, PhaseOffset, A, Inc, []),
        NextAcc = list.reverse(PlaneNodes) ++ Acc,
        Result = generate_delta_planes(PlaneIdx + 1, TotalPlanes, SatsPerPlane, F, T, A, Inc, NextAcc)
    ).

:- func generate_star_planes(int, int, int, int, float, float, list(satellite_node)) = list(satellite_node).
generate_star_planes(PlaneIdx, TotalPlanes, SatsPerPlane, TotalSats, A, Inc, Acc) = Result :-
    ( if PlaneIdx >= TotalPlanes then
        Result = list.reverse(Acc)
      else
        % For polar star, RAAN is distributed across pi (180 deg)
        Raan = math.pi * float(PlaneIdx) / float(TotalPlanes),
        PhaseOffset = 0.0,
        PlaneNodes = generate_plane_sats(PlaneIdx, 0, SatsPerPlane, Raan, PhaseOffset, A, Inc, []),
        NextAcc = list.reverse(PlaneNodes) ++ Acc,
        Result = generate_star_planes(PlaneIdx + 1, TotalPlanes, SatsPerPlane, TotalSats, A, Inc, NextAcc)
    ).

:- func generate_plane_sats(int, int, int, float, float, float, float, list(satellite_node)) = list(satellite_node).
generate_plane_sats(PlaneIdx, SatIdx, SatsPerPlane, Raan, PhaseOffset, A, Inc, Acc) = Result :-
    ( if SatIdx >= SatsPerPlane then
        Result = list.reverse(Acc)
      else
        % Mean anomaly spacing: M = 2 * pi * s / S + PhaseOffset
        M0 = two_pi * float(SatIdx) / float(SatsPerPlane) + PhaseOffset,
        Nu0 = wrap_two_pi(M0),
        % Near-circular orbit (e = 0.0001)
        Kep = keplerian_elements(A, 0.0001, Inc, wrap_two_pi(Raan), 0.0, Nu0),
        string.format("SAT_P%02d_S%02d", [i(PlaneIdx), i(SatIdx)], SatId),
        Node = satellite_node(SatId, PlaneIdx, SatIdx, Kep),
        Result = generate_plane_sats(PlaneIdx, SatIdx + 1, SatsPerPlane, Raan, PhaseOffset, A, Inc, [Node | Acc])
    ).

get_nominal_neighbor(Params, PlaneIdx, SatIdx, Terminal) = NeighborId :-
    (
        Params = walker_delta(T, P, _, _, _),
        SatsPerPlane = T / P,
        TotalPlanes = P
    ;
        Params = walker_star_polar(T, P, _, _),
        SatsPerPlane = T / P,
        TotalPlanes = P
    ),
    (
        Terminal = terminal_fore,
        NextSat = (SatIdx + 1) mod SatsPerPlane,
        string.format("SAT_P%02d_S%02d", [i(PlaneIdx), i(NextSat)], NeighborId)
    ;
        Terminal = terminal_aft,
        PrevSat = (SatIdx - 1 + SatsPerPlane) mod SatsPerPlane,
        string.format("SAT_P%02d_S%02d", [i(PlaneIdx), i(PrevSat)], NeighborId)
    ;
        Terminal = terminal_left,
        LeftPlane = (PlaneIdx - 1 + TotalPlanes) mod TotalPlanes,
        string.format("SAT_P%02d_S%02d", [i(LeftPlane), i(SatIdx)], NeighborId)
    ;
        Terminal = terminal_right,
        RightPlane = (PlaneIdx + 1) mod TotalPlanes,
        string.format("SAT_P%02d_S%02d", [i(RightPlane), i(SatIdx)], NeighborId)
    ).

format_satellite_node(Node) = Str :-
    string.format("[%s (Plane %d, Sat %d)] %s",
        [s(Node ^ sat_id),
         i(Node ^ sat_plane_idx),
         i(Node ^ sat_pos_in_plane),
         s(format_keplerian(Node ^ sat_keplerian))], Str).
