:- module nadir_core.isl.routing.
:- interface.

:- import_module float, string, list, bool.
:- use_module nadir_core.isl.
:- import_module nadir_core.isl.contact_graph.

:- type isl_route
    --->    isl_route(
                ir_source_sat       :: string,
                ir_dest_sat         :: string,
                ir_hop_path         :: list(string), % Ordered list of satellite IDs from source to dest
                ir_total_distance_m :: float,
                ir_total_delay_sec  :: float,        % Total speed-of-light propagation latency
                ir_is_routable      :: bool
            ).

% Find shortest-path optical route across constellation contact graph using Dijkstra's algorithm
:- func find_shortest_isl_route(constellation_contact_graph, string, string) = isl_route.

% End-to-end packet transfer time (seconds) including transmission latency across all hops
:- func packet_delivery_time(isl_route, float, float) = float.

% Formatting
:- func format_isl_route(isl_route) = string.

:- implementation.

:- import_module math, pair, maybe, int.

find_shortest_isl_route(Graph, SrcSat, DestSat) = Route :-
    ( if SrcSat = DestSat then
        Route = isl_route(SrcSat, DestSat, [SrcSat], 0.0, 0.0, yes)
      else
        ActiveLinks = Graph ^ ccg_active_links,
        % Run Dijkstra search from SrcSat to DestSat
        Visited = [],
        DistMap = [SrcSat - 0.0],
        PredMap = [],
        DijkstraResult = dijkstra_loop(SrcSat, DestSat, ActiveLinks, Visited, DistMap, PredMap),
        ( DijkstraResult = found(HopPath, TotDist, TotDelay) ->
            Route = isl_route(SrcSat, DestSat, HopPath, TotDist, TotDelay, yes)
        ;
            Route = isl_route(SrcSat, DestSat, [], 0.0, 0.0, no)
        )
    ).

:- type dijkstra_res
    --->    found(list(string), float, float)
    ;       not_found.

:- func dijkstra_loop(
    string,
    string,
    list(optical_link_edge),
    list(string),
    list(pair(string, float)),
    list(pair(string, string))
) = dijkstra_res.
dijkstra_loop(CurrNode, DestNode, Edges, Visited, Distances, Predecessors) = Result :-
    ( if CurrNode = DestNode then
        % Reconstruct path
        Path = reconstruct_path(DestNode, Predecessors, []),
        CurrDist = lookup_dist(DestNode, Distances),
        PropDelay = CurrDist / 299792458.0,
        Result = found(Path, CurrDist, PropDelay)
      else
        NewVisited = [CurrNode | Visited],
        CurrDist = lookup_dist(CurrNode, Distances),
        % Find outgoing active links from CurrNode
        OutEdges = list.filter((pred(E::in) is semidet :- E ^ ole_from_sat = CurrNode), Edges),
        % Relax neighbors
        Relaxed = relax_edges(OutEdges, CurrDist, NewVisited, Distances, Predecessors),
        Relaxed = NewDistances - NewPredecessors,
        % Pick unvisited node with minimum tentative distance
        NextCandidate = get_min_unvisited(NewDistances, NewVisited),
        ( NextCandidate = yes(NextNode) ->
            Result = dijkstra_loop(NextNode, DestNode, Edges, NewVisited, NewDistances, NewPredecessors)
        ;
            Result = not_found
        )
    ).

:- func relax_edges(
    list(optical_link_edge),
    float,
    list(string),
    list(pair(string, float)),
    list(pair(string, string))
) = pair(list(pair(string, float)), list(pair(string, string))).
relax_edges([], _CurrDist, _Visited, DistMap, PredMap) = DistMap - PredMap.
relax_edges([E | Rest], CurrDist, Visited, DistMap, PredMap) = Result :-
    Neighbor = E ^ ole_to_sat,
    ( if list.member(Neighbor, Visited) then
        Result = relax_edges(Rest, CurrDist, Visited, DistMap, PredMap)
      else
        NewDist = CurrDist + E ^ ole_distance_m,
        OldDist = lookup_dist(Neighbor, DistMap),
        ( if NewDist < OldDist then
            UpdatedDistMap = update_dist(Neighbor, NewDist, DistMap),
            UpdatedPredMap = [Neighbor - (E ^ ole_from_sat) | list.filter((pred(P::in) is semidet :- (P = K - _), K \= Neighbor), PredMap)],
            Result = relax_edges(Rest, CurrDist, Visited, UpdatedDistMap, UpdatedPredMap)
          else
            Result = relax_edges(Rest, CurrDist, Visited, DistMap, PredMap)
        )
    ).

:- func lookup_dist(string, list(pair(string, float))) = float.
lookup_dist(_Node, []) = 1.0e15. % Infinity
lookup_dist(Node, [K - V | Rest]) =
    ( if K = Node then V else lookup_dist(Node, Rest) ).

:- func update_dist(string, float, list(pair(string, float))) = list(pair(string, float)).
update_dist(Node, Dist, Map) = [Node - Dist | list.filter((pred(P::in) is semidet :- (P = K - _), K \= Node), Map)].

:- func get_min_unvisited(list(pair(string, float)), list(string)) = maybe(string).
get_min_unvisited(DistMap, Visited) = Best :-
    Unvisited = list.filter((pred(P::in) is semidet :- (P = K - _), not list.member(K, Visited)), DistMap),
    (
        Unvisited = [],
        Best = no
    ;
        Unvisited = [First | Rest],
        First = BestNode0 - BestDist0,
        BestNode = find_min_dist(Rest, BestNode0, BestDist0),
        Best = yes(BestNode)
    ).

:- func find_min_dist(list(pair(string, float)), string, float) = string.
find_min_dist([], CurrBestNode, _) = CurrBestNode.
find_min_dist([K - V | Rest], CurrBestNode, CurrBestDist) =
    ( if V < CurrBestDist then
        find_min_dist(Rest, K, V)
      else
        find_min_dist(Rest, CurrBestNode, CurrBestDist)
    ).

:- func reconstruct_path(string, list(pair(string, string)), list(string)) = list(string).
reconstruct_path(Curr, PredMap, Acc) = Path :-
    NewAcc = [Curr | Acc],
    Preds = list.filter((pred(P::in) is semidet :- (P = K - _), K = Curr), PredMap),
    ( Preds = [_ - Parent | _] ->
        Path = reconstruct_path(Parent, PredMap, NewAcc)
      ;
        Path = NewAcc
    ).

packet_delivery_time(Route, PacketSizeGigabits, LinkRateGbps) = DeliveryTime :-
    ( if Route ^ ir_is_routable = yes then
        Hops = float(list.length(Route ^ ir_hop_path) - 1),
        PropDelay = Route ^ ir_total_delay_sec,
        TransDelayPerHop = PacketSizeGigabits / LinkRateGbps,
        TotalTransDelay = Hops * TransDelayPerHop,
        DeliveryTime = PropDelay + TotalTransDelay
      else
        DeliveryTime = 1.0e9 % Unreachable
    ).

format_isl_route(R) = Str :-
    ( if R ^ ir_is_routable = yes then
        HopStr = string.join_list(" -> ", R ^ ir_hop_path),
        string.format("Route [%s -> %s]: %s | Hops: %d | Dist: %0.1f km | Latency: %0.2f ms",
            [s(R ^ ir_source_sat),
             s(R ^ ir_dest_sat),
             s(HopStr),
             i(list.length(R ^ ir_hop_path) - 1),
             f(R ^ ir_total_distance_m / 1000.0),
             f(R ^ ir_total_delay_sec * 1000.0)], Str)
      else
        string.format("Route [%s -> %s]: NO AVAILABLE ISL PATH (Occulted / Out of Range)",
            [s(R ^ ir_source_sat), s(R ^ ir_dest_sat)], Str)
    ).
