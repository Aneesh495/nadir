:- module nadir_core.ground.downlink.
:- interface.

:- import_module float, int, string, list.
:- use_module nadir_core.ground.
:- import_module nadir_core.ground.stations.
:- import_module nadir_core.ground.passes.

:- type allocated_downlink
    --->    allocated_downlink(
                ad_station_id       :: string,
                ad_sat_id           :: string,
                ad_antenna_idx      :: int,
                ad_start_dt         :: float,
                ad_end_dt           :: float,
                ad_data_dumped_gb   :: float
            ).

:- type downlink_plan
    --->    downlink_plan(
                dp_allocations      :: list(allocated_downlink),
                dp_total_dumped_gb  :: float,
                dp_passes_utilized  :: int
            ).

% Allocate ground station antenna contacts resolving dish contention
:- func allocate_downlink_contacts(list(ground_station), list(ground_pass)) = downlink_plan.

% Formatting
:- func format_allocated_downlink(allocated_downlink) = string.

:- implementation.

allocate_downlink_contacts(Stations, Passes) = Plan :-
    SortedPasses = sort_passes_by_capacity(Passes),
    Allocations = schedule_passes_loop(Stations, SortedPasses, []),
    TotalDump = list.foldl((func(A, Acc) = Acc + A ^ ad_data_dumped_gb), Allocations, 0.0),
    Plan = downlink_plan(Allocations, TotalDump, list.length(Allocations)).

:- func sort_passes_by_capacity(list(ground_pass)) = list(ground_pass).
sort_passes_by_capacity([]) = [].
sort_passes_by_capacity([H | T]) = insert_pass_by_capacity(H, sort_passes_by_capacity(T)).

:- func insert_pass_by_capacity(ground_pass, list(ground_pass)) = list(ground_pass).
insert_pass_by_capacity(P, []) = [P].
insert_pass_by_capacity(P, [H | T]) =
    ( if P ^ gp_data_capacity_gb >= H ^ gp_data_capacity_gb then
        [P, H | T]
      else
        [H | insert_pass_by_capacity(P, T)]
    ).

:- func schedule_passes_loop(list(ground_station), list(ground_pass), list(allocated_downlink)) = list(allocated_downlink).
schedule_passes_loop(_Stations, [], Acc) = list.reverse(Acc).
schedule_passes_loop(Stations, [Pass | Rest], Acc) = Result :-
    StId = Pass ^ gp_station_id,
    StationMatches = list.filter((pred(S::in) is semidet :- S ^ gs_id = StId), Stations),
    ( if StationMatches = [St | _] then
        MaxDishes = St ^ gs_antenna_count,
        PassStart = Pass ^ gp_aos_dt_sec,
        PassEnd   = Pass ^ gp_los_dt_sec,
        Overlaps = list.filter((pred(A::in) is semidet :-
            A ^ ad_station_id = StId,
            not (A ^ ad_end_dt =< PassStart ; A ^ ad_start_dt >= PassEnd)
        ), Acc),
        DishInUseCount = list.length(Overlaps),
        ( if DishInUseCount < MaxDishes then
            NewAlloc = allocated_downlink(StId, Pass ^ gp_sat_id, DishInUseCount + 1,
                                          PassStart, PassEnd, Pass ^ gp_data_capacity_gb),
            NextAcc = [NewAlloc | Acc]
          else
            NextAcc = Acc
        )
      else
        NextAcc = Acc
    ),
    Result = schedule_passes_loop(Stations, Rest, NextAcc).

format_allocated_downlink(A) = Str :-
    string.format("[%s Dish #%d <- %s] Time: [%0.1fs to %0.1fs] Dump: %0.1f Gb",
        [s(A ^ ad_station_id),
         i(A ^ ad_antenna_idx),
         s(A ^ ad_sat_id),
         f(A ^ ad_start_dt),
         f(A ^ ad_end_dt),
         f(A ^ ad_data_dumped_gb)], Str).
