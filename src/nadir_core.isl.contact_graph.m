:- module nadir_core.isl.contact_graph.
:- interface.

:- import_module float, string, list, bool, pair.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.kepler.

:- type optical_link_edge
    --->    optical_link_edge(
                ole_from_sat       :: string,
                ole_to_sat         :: string,
                ole_distance_m     :: float,
                ole_prop_delay_sec :: float, % Propagation delay = distance / c
                ole_doppler_factor :: float, % Frequency shift factor Delta_f / f_0
                ole_is_active      :: bool
            ).

:- type constellation_contact_graph
    --->    constellation_contact_graph(
                ccg_epoch_dt_sec   :: float,
                ccg_active_links   :: list(optical_link_edge),
                ccg_total_nodes    :: int
            ).

% Evaluate single pairwise optical laser link between two satellites
:- func evaluate_optical_link(string, orbit_state, string, orbit_state, float) = optical_link_edge.

% Construct full instantaneous contact graph for constellation at an epoch
% Takes list of (SatId, OrbitState) pairs and max laser range in meters (e.g. 5,000,000m)
:- func build_instantaneous_contact_graph(float, list(pair(string, orbit_state)), float) = constellation_contact_graph.

% Formatting
:- func format_link_edge(optical_link_edge) = string.

:- implementation.

:- use_module nadir_core.access.
:- import_module nadir_core.access.occultation.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.vec3.

evaluate_optical_link(Sat1Id, State1, Sat2Id, State2, MaxRange_m) = Edge :-
    R1 = State1 ^ os_pos,
    V1 = State1 ^ os_vel,
    R2 = State2 ^ os_pos,
    V2 = State2 ^ os_vel,
    % Relative range vector
    DeltaR = vec3_sub(R2, R1),
    Dist = vec3_norm(DeltaR),
    DeltaV = vec3_sub(V2, V1),
    % Range rate: d(rho)/dt = DeltaR . DeltaV / rho
    ( if Dist > 1.0e-3 then
        RangeRate = vec3_dot(DeltaR, DeltaV) / Dist
      else
        RangeRate = 0.0
    ),
    % Doppler factor: Delta_f / f0 = - RangeRate / c
    Doppler = -RangeRate / speed_of_light,
    PropDelay = Dist / speed_of_light,
    % Check geometric criteria: range within limit AND clear line-of-sight (40km atmospheric buffer)
    LOS = is_link_available(R1, R2, 40000.0),
    ( if (Dist =< MaxRange_m, Dist > 1000.0, LOS = yes) then
        Active = yes
      else
        Active = no
    ),
    Edge = optical_link_edge(Sat1Id, Sat2Id, Dist, PropDelay, Doppler, Active).

build_instantaneous_contact_graph(Dt_sec, SatStates, MaxRange_m) = Graph :-
    TotalNodes = list.length(SatStates),
    Links = generate_all_links(SatStates, SatStates, MaxRange_m, []),
    ActiveLinks = list.filter((pred(E::in) is semidet :- E ^ ole_is_active = yes), Links),
    Graph = constellation_contact_graph(Dt_sec, ActiveLinks, TotalNodes).

:- func generate_all_links(list(pair(string, orbit_state)), list(pair(string, orbit_state)), float, list(optical_link_edge)) = list(optical_link_edge).
generate_all_links([], _All, _MaxRange, Acc) = Acc.
generate_all_links([P1 | Rest], All, MaxRange, Acc) = Result :-
    P1 = Sat1 - State1,
    % Generate directed links to all other satellites
    Neighbors = list.filter((pred(P::in) is semidet :- (P = Sat2 - _), Sat2 \= Sat1), All),
    LinksFromP1 = list.map((func(P2) = evaluate_optical_link(Sat1, State1, P2 ^ fst, P2 ^ snd, MaxRange)), Neighbors),
    Result = generate_all_links(Rest, All, MaxRange, LinksFromP1 ++ Acc).

format_link_edge(Edge) = Str :-
    string.format("[%s <-> %s] Dist: %0.1f km | Delay: %0.2f ms | Doppler: %+0.2e",
        [s(Edge ^ ole_from_sat),
         s(Edge ^ ole_to_sat),
         f(Edge ^ ole_distance_m / 1000.0),
         f(Edge ^ ole_prop_delay_sec * 1000.0),
         f(Edge ^ ole_doppler_factor)], Str).
