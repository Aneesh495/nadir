:- module nadir_core.scheduler.constraints.
:- interface.

:- import_module float, bool, list.
:- use_module nadir_core.platform.
:- import_module nadir_core.platform.slew.
:- use_module nadir_core.access.
:- import_module nadir_core.access.target.
:- use_module nadir_core.scheduler.
:- import_module nadir_core.scheduler.types.

% Check whether two sequential observations on the same satellite have sufficient slew time
:- func is_slew_feasible(agile_adcs_limits, float, float, float, float) = bool.

% Check whether an observation interval fits inside an access window
:- func is_observation_contained(target_access_window, float, float) = bool.

% Complete pairwise verification of an observation schedule for a single satellite
:- func verify_satellite_timeline(agile_adcs_limits, list(scheduled_observation)) = bool.

:- implementation.

:- import_module math.

is_slew_feasible(ADCS, PrevLook, PrevEndDt, NextLook, NextStartDt) = Feasible :-
    AvailableTime = NextStartDt - PrevEndDt,
    DeltaAngle = abs(NextLook - PrevLook),
    RequiredSlewTime = slew_duration_seconds(ADCS, DeltaAngle),
    ( if AvailableTime >= RequiredSlewTime then
        Feasible = yes
      else
        Feasible = no
    ).

is_observation_contained(Window, ObsStart, ObsEnd) = Contained :-
    ( if (ObsStart >= Window ^ taw_start_dt,
          ObsEnd =< Window ^ taw_end_dt,
          ObsEnd > ObsStart) then
        Contained = yes
      else
        Contained = no
    ).

verify_satellite_timeline(_ADCS, []) = yes.
verify_satellite_timeline(_ADCS, [_]) = yes.
verify_satellite_timeline(ADCS, [Obs1, Obs2 | Rest]) = Valid :-
    % Check that Obs2 starts after Obs1 ends with adequate slew time
    PrevLook = Obs1 ^ so_look_angle,
    PrevEnd = Obs1 ^ so_obs_end_dt,
    NextLook = Obs2 ^ so_look_angle,
    NextStart = Obs2 ^ so_obs_start_dt,
    Feasible = is_slew_feasible(ADCS, PrevLook, PrevEnd, NextLook, NextStart),
    ( if Feasible = yes then
        Valid = verify_satellite_timeline(ADCS, [Obs2 | Rest])
      else
        Valid = no
    ).
