:- module nadir_core.scheduler.optimizer.
:- interface.

:- import_module list.
:- use_module nadir_core.platform.
:- import_module nadir_core.platform.slew.
:- import_module nadir_core.platform.power.
:- import_module nadir_core.platform.storage.
:- use_module nadir_core.access.
:- import_module nadir_core.access.target.
:- use_module nadir_core.scheduler.
:- import_module nadir_core.scheduler.types.

% Solve constellation mission schedule
% Takes ADCS specs, power specs, storage specs, task requests, and candidate access windows
:- func solve_constellation_schedule(
    agile_adcs_limits,
    power_subsystem_specs,
    storage_subsystem_specs,
    list(task_request),
    list(target_access_window)
) = constellation_schedule.

:- implementation.

:- import_module float, int, string, bool, math.

solve_constellation_schedule(ADCS, PowerSpecs, StorageSpecs, Requests, Windows) = Schedule :-
    % 1. Sort task requests by priority score descending
    SortedRequests = sort_requests_by_priority(Requests),
    % 2. Greedily schedule observations with backtracking feasibility checks
    ScheduleLoop = schedule_tasks(ADCS, PowerSpecs, StorageSpecs, SortedRequests, Windows, []),
    % 3. Sort scheduled observations in chronological order
    OrderedSchedule = sort_observations_by_time(ScheduleLoop),
    TotalReqCount = list.length(Requests),
    FulfilledCount = list.length(OrderedSchedule),
    % Compute total value
    TotalVal = list.foldl((func(Obs, Acc) = Acc + Obs ^ so_energy_wh), OrderedSchedule, 0.0),
    Schedule = constellation_schedule(OrderedSchedule, TotalVal, FulfilledCount, TotalReqCount).

:- func sort_observations_by_time(list(scheduled_observation)) = list(scheduled_observation).
sort_observations_by_time([]) = [].
sort_observations_by_time([H | T]) = insert_obs_by_time(H, sort_observations_by_time(T)).

:- func insert_obs_by_time(scheduled_observation, list(scheduled_observation)) = list(scheduled_observation).
insert_obs_by_time(O, []) = [O].
insert_obs_by_time(O, [H | T]) =
    ( if O ^ so_obs_start_dt =< H ^ so_obs_start_dt then
        [O, H | T]
      else
        [H | insert_obs_by_time(O, T)]
    ).

:- func sort_requests_by_priority(list(task_request)) = list(task_request).
sort_requests_by_priority([]) = [].
sort_requests_by_priority([H | T]) = insert_req_by_priority(H, sort_requests_by_priority(T)).

:- func insert_req_by_priority(task_request, list(task_request)) = list(task_request).
insert_req_by_priority(R, []) = [R].
insert_req_by_priority(R, [H | T]) =
    ( if calculate_priority_score(R) >= calculate_priority_score(H) then
        [R, H | T]
      else
        [H | insert_req_by_priority(R, T)]
    ).

:- func schedule_tasks(
    agile_adcs_limits,
    power_subsystem_specs,
    storage_subsystem_specs,
    list(task_request),
    list(target_access_window),
    list(scheduled_observation)
) = list(scheduled_observation).
schedule_tasks(_ADCS, _Power, _Storage, [], _Windows, Acc) = Acc.
schedule_tasks(ADCS, Power, Storage, [Req | RestReqs], Windows, Acc) = FinalSchedule :-
    % Find candidate access windows matching this request's target
    TgtId = Req ^ tr_target_id,
    CandWindows = list.filter((pred(W::in) is semidet :- W ^ taw_target_id = TgtId), Windows),
    % Attempt insertion into schedule
    ( if try_schedule_request(ADCS, Power, Storage, Req, CandWindows, Acc, NewObs) then
        NextAcc = [NewObs | Acc]
      else
        NextAcc = Acc
    ),
    FinalSchedule = schedule_tasks(ADCS, Power, Storage, RestReqs, Windows, NextAcc).

:- pred try_schedule_request(
    agile_adcs_limits::in,
    power_subsystem_specs::in,
    storage_subsystem_specs::in,
    task_request::in,
    list(target_access_window)::in,
    list(scheduled_observation)::in,
    scheduled_observation::out
) is semidet.
try_schedule_request(ADCS, Power, Storage, Req, [Window | RestWindows], CurrentSched, ObsOut) :-
    ReqDur = Req ^ tr_duration_sec,
    WinDur = Window ^ taw_duration_sec,
    ( if WinDur >= ReqDur then
        % Place observation centered at mid-window
        WinStart = Window ^ taw_start_dt,
        ObsStart = WinStart + (WinDur - ReqDur) * 0.5,
        ObsEnd = ObsStart + ReqDur,
        SatId = Window ^ taw_sat_id,
        LookAngle = Window ^ taw_min_off_nadir,
        % Find prior observations on this satellite
        SatObs = list.filter((pred(O::in) is semidet :- O ^ so_sat_id = SatId), CurrentSched),
        % Verify no time collisions and feasible slews with existing satellite timeline
        ( if can_insert_observation(ADCS, SatObs, ObsStart, ObsEnd, LookAngle, SlewStart, SlewDur) then
            DataVolGb = (Storage ^ sss_payload_ingest_gbps) * ReqDur,
            EnergyWh = (Power ^ pss_payload_active_w) * (ReqDur / 3600.0),
            ObsOut = scheduled_observation(Req ^ tr_req_id, Req ^ tr_target_id, SatId,
                                           SlewStart, SlewDur, ObsStart, ObsEnd, LookAngle,
                                           EnergyWh, DataVolGb)
          else
            try_schedule_request(ADCS, Power, Storage, Req, RestWindows, CurrentSched, ObsOut)
        )
      else
        try_schedule_request(ADCS, Power, Storage, Req, RestWindows, CurrentSched, ObsOut)
    ).

:- pred can_insert_observation(
    agile_adcs_limits::in,
    list(scheduled_observation)::in,
    float::in,
    float::in,
    float::in,
    float::out,
    float::out
) is semidet.
can_insert_observation(ADCS, ExistingObs, NewStart, NewEnd, NewLook, SlewStartOut, SlewDurOut) :-
    BaseSlewDur = slew_duration_seconds(ADCS, abs(NewLook)),
    SlewStart = NewStart - BaseSlewDur,
    % Check that interval [SlewStart, NewEnd] does not overlap with any existing task on this sat
    NoOverlap = list.all_true((pred(Obs::in) is semidet :-
        ( Obs ^ so_obs_end_dt =< SlewStart ; Obs ^ so_slew_start_dt >= NewEnd )
    ), ExistingObs),
    ( if NoOverlap then
        SlewStartOut = SlewStart,
        SlewDurOut = BaseSlewDur
      else
        fail
    ).
