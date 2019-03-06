:- module nadir_core.access.target.
:- interface.

:- import_module float, int, string, list, bool.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.propagator.

:- type observation_target
    --->    observation_target(
                tgt_id              :: string,
                tgt_name            :: string,
                tgt_geo             :: geodetic,
                tgt_priority        :: int,   % 0: Emergency, 1: High, 2: Standard, 3: Background
                tgt_min_elevation   :: float, % Radians (e.g. 20 deg = 0.349 rad)
                tgt_max_off_nadir   :: float, % Radians (e.g. 30 deg = 0.523 rad)
                tgt_min_solar_elev  :: float  % Radians (e.g. 10 deg = 0.174 rad)
            ).

:- type target_access_sample
    --->    target_access_sample(
                tas_epoch          :: datetime,
                tas_dt_sec         :: float,
                tas_elevation      :: float, % Radians above horizon
                tas_azimuth        :: float, % Radians clockwise from North
                tas_slant_range    :: float, % Meters
                tas_off_nadir      :: float, % Satellite look angle (radians)
                tas_solar_elev     :: float, % Target sun elevation (radians)
                tas_is_visible     :: bool
            ).

:- type target_access_window
    --->    target_access_window(
                taw_target_id      :: string,
                taw_sat_id         :: string,
                taw_start_epoch    :: datetime,
                taw_start_dt       :: float,
                taw_end_epoch      :: datetime,
                taw_end_dt         :: float,
                taw_duration_sec   :: float,
                taw_max_elevation  :: float, % Radians
                taw_min_off_nadir  :: float, % Radians
                taw_solar_elev_mid :: float  % Radians
            ).

% Evaluate single time instant geometry between satellite and target
:- func evaluate_target_access(observation_target, vec3, datetime, float) = target_access_sample.

% Compute all visibility access windows for a target across an ephemeris track
:- func compute_target_access_windows(string, observation_target, list(orbit_ephemeris_point)) = list(target_access_window).

% Formatting
:- func format_access_window(target_access_window) = string.

:- implementation.

:- import_module math.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.sun.

evaluate_target_access(Target, SatEcef, Epoch, Dt_sec) = Sample :-
    TargetGeo = Target ^ tgt_geo,
    Topo = ecef_to_topocentric(TargetGeo, SatEcef),
    El = Topo ^ topo_elevation,
    Az = Topo ^ topo_azimuth,
    Range = Topo ^ topo_range,
    % Compute satellite off-nadir look angle towards target
    NadirGeo = ecef_to_geodetic(SatEcef),
    _Altitude = NadirGeo ^ geo_alt,
    TargetEcef = geodetic_to_ecef(TargetGeo),
    % Satellite nadir vector points from satellite to Earth center
    % Range vector points from satellite to target: rho = target - sat
    SatToTarget = vec3_sub(TargetEcef, SatEcef),
    SatToEarthCenter = vec3_scale(-1.0, SatEcef),
    LookAngle = vec3_angle(SatToEarthCenter, SatToTarget),
    % Solar elevation at target
    SolarEl = target_solar_elevation(TargetGeo, Epoch),
    % Visibility criteria check
    MinEl = Target ^ tgt_min_elevation,
    MaxLook = Target ^ tgt_max_off_nadir,
    MinSolar = Target ^ tgt_min_solar_elev,
    ( if (El >= MinEl, LookAngle =< MaxLook, SolarEl >= MinSolar) then
        Visible = yes
      else
        Visible = no
    ),
    Sample = target_access_sample(Epoch, Dt_sec, El, Az, Range, LookAngle, SolarEl, Visible).

compute_target_access_windows(SatId, Target, Ephemeris) = Windows :-
    Samples = list.map(
        ( func(Pt) = evaluate_target_access(Target, Pt ^ oep_ecef_pos, Pt ^ oep_epoch, Pt ^ oep_dt_sec) ),
        Ephemeris),
    Windows = extract_windows(SatId, Target ^ tgt_id, Samples, no, []).

:- func extract_windows(string, string, list(target_access_sample), bool, list(target_access_sample)) = list(target_access_window).
extract_windows(SatId, TgtId, [], InWindow, CurrGroup) = Out :-
    ( InWindow = yes, CurrGroup = [_ | _] ->
        Out = [build_window_from_samples(SatId, TgtId, list.reverse(CurrGroup))]
    ;
        Out = []
    ).
extract_windows(SatId, TgtId, [Sample | Rest], InWindow, CurrGroup) = Out :-
    Vis = Sample ^ tas_is_visible,
    (
        InWindow = no,
        ( Vis = yes ->
            Out = extract_windows(SatId, TgtId, Rest, yes, [Sample])
        ;
            Out = extract_windows(SatId, TgtId, Rest, no, [])
        )
    ;
        InWindow = yes,
        ( Vis = yes ->
            Out = extract_windows(SatId, TgtId, Rest, yes, [Sample | CurrGroup])
        ;
            Window = build_window_from_samples(SatId, TgtId, list.reverse(CurrGroup)),
            Out = [Window | extract_windows(SatId, TgtId, Rest, no, [])]
        )
    ).

:- func build_window_from_samples(string, string, list(target_access_sample)) = target_access_window.
build_window_from_samples(SatId, TgtId, Samples) = Window :-
    ( Samples = [First | _] ->
        Last = list.det_last(Samples),
        StartEpoch = First ^ tas_epoch,
        StartDt    = First ^ tas_dt_sec,
        EndEpoch   = Last ^ tas_epoch,
        EndDt      = Last ^ tas_dt_sec,
        Duration   = EndDt - StartDt,
        % Find max elevation, min look angle, and mid solar elevation
        MaxEl = list.foldl((func(S, Acc) = (if S ^ tas_elevation > Acc then S ^ tas_elevation else Acc)),
                           Samples, -math.pi),
        MinLook = list.foldl((func(S, Acc) = (if S ^ tas_off_nadir < Acc then S ^ tas_off_nadir else Acc)),
                             Samples, math.pi),
        MidIdx = list.length(Samples) / 2,
        MidSample = list.det_index1(Samples, MidIdx + 1),
        SolarMid = MidSample ^ tas_solar_elev,
        Window = target_access_window(TgtId, SatId, StartEpoch, StartDt, EndEpoch, EndDt,
                                      Duration, MaxEl, MinLook, SolarMid)
    ;
        % Fallback for empty list (should not occur)
        Epoch0 = datetime(2026, 1, 1, 0, 0, 0.0),
        Window = target_access_window(TgtId, SatId, Epoch0, 0.0, Epoch0, 0.0, 0.0, 0.0, 0.0, 0.0)
    ).

format_access_window(W) = Str :-
    string.format("Target: %s | Sat: %s | Window: [%s -> %s] Dur: %0.1fs | MaxEl: %0.1f deg | MinLook: %0.1f deg | Solar: %0.1f deg",
        [s(W ^ taw_target_id),
         s(W ^ taw_sat_id),
         s(format_iso8601(W ^ taw_start_epoch)),
         s(format_iso8601(W ^ taw_end_epoch)),
         f(W ^ taw_duration_sec),
         f(rad_to_deg(W ^ taw_max_elevation)),
         f(rad_to_deg(W ^ taw_min_off_nadir)),
         f(rad_to_deg(W ^ taw_solar_elev_mid))], Str).
