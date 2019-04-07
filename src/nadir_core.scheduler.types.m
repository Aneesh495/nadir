:- module nadir_core.scheduler.types.
:- interface.

:- import_module float, int, string, list.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.temporal.

:- type task_request
    --->    task_request(
                tr_req_id          :: string,
                tr_target_id       :: string,
                tr_priority        :: int,   % 0: Urgent/Disaster, 1: High, 2: Standard, 3: Background
                tr_duration_sec    :: float, % Required exposure/dwell duration in seconds
                tr_value_weight    :: float, % Objective function score contribution
                tr_deadline        :: datetime
            ).

:- type scheduled_observation
    --->    scheduled_observation(
                so_task_id         :: string,
                so_target_id       :: string,
                so_sat_id          :: string,
                so_slew_start_dt   :: float, % Slew start epoch (seconds from sim epoch)
                so_slew_duration   :: float, % Slew duration (seconds)
                so_obs_start_dt    :: float, % Imaging start epoch
                so_obs_end_dt      :: float, % Imaging end epoch
                so_look_angle      :: float, % Off-nadir angle (radians)
                so_energy_wh       :: float, % Energy consumed
                so_data_volume_gb  :: float  % Memory ingested
            ).

:- type constellation_schedule
    --->    constellation_schedule(
                cs_observations     :: list(scheduled_observation),
                cs_total_value      :: float,
                cs_fulfilled_count  :: int,
                cs_total_requests   :: int
            ).

% Priority weight scoring formula
:- func calculate_priority_score(task_request) = float.

% Formatting
:- func format_scheduled_observation(scheduled_observation) = string.
:- func format_constellation_schedule(constellation_schedule) = string.

:- implementation.

:- import_module math.
:- import_module nadir_core.astro.constants.

calculate_priority_score(Req) = Score :-
    Pri = Req ^ tr_priority,
    BaseWeight = Req ^ tr_value_weight,
    ( if Pri = 0 then Multiplier = 1000.0  % Emergency / Disaster Rapid Response
      else if Pri = 1 then Multiplier = 100.0 % High Priority Commercial
      else if Pri = 2 then Multiplier = 10.0  % Standard
      else Multiplier = 1.0                   % Background / Archive
    ),
    Score = BaseWeight * Multiplier.

format_scheduled_observation(Obs) = Str :-
    string.format("[%s on %s] Slew: %0.1fs -> Obs: [%0.1fs to %0.1fs] Dur: %0.1fs | Look: %0.1f deg | Data: %0.1f Gb",
        [s(Obs ^ so_task_id),
         s(Obs ^ so_sat_id),
         f(Obs ^ so_slew_duration),
         f(Obs ^ so_obs_start_dt),
         f(Obs ^ so_obs_end_dt),
         f(Obs ^ so_obs_end_dt - Obs ^ so_obs_start_dt),
         f(rad_to_deg(Obs ^ so_look_angle)),
         f(Obs ^ so_data_volume_gb)], Str).

format_constellation_schedule(Sched) = Str :-
    Yield = (if Sched ^ cs_total_requests > 0 then
                float(Sched ^ cs_fulfilled_count) / float(Sched ^ cs_total_requests) * 100.0
             else 0.0),
    string.format("Schedule: %d / %d tasks scheduled (%0.1f%% yield) | Total Value Score: %0.1f",
        [i(Sched ^ cs_fulfilled_count),
         i(Sched ^ cs_total_requests),
         f(Yield),
         f(Sched ^ cs_total_value)], Str).
