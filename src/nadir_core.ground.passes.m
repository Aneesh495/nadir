:- module nadir_core.ground.passes.
:- interface.

:- import_module float, string, list.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.propagator.
:- use_module nadir_core.ground.
:- import_module nadir_core.ground.stations.

:- type ground_pass
    --->    ground_pass(
                gp_station_id       :: string,
                gp_sat_id           :: string,
                gp_aos_epoch        :: datetime, % Acquisition of Signal
                gp_aos_dt_sec       :: float,
                gp_los_epoch        :: datetime, % Loss of Signal
                gp_los_dt_sec       :: float,
                gp_duration_sec     :: float,
                gp_max_elevation    :: float,    % Radians
                gp_data_capacity_gb :: float     % Total Gigabits downloadable during pass
            ).

% Compute all ground station passes for a satellite across an ephemeris track
:- func compute_ground_passes(string, ground_station, list(orbit_ephemeris_point)) = list(ground_pass).

% Elevation-dependent adaptive coding and modulation (ACM) data rate in Gbps
:- func elevation_acm_rate_gbps(rf_band, float) = float.

% Formatting
:- func format_ground_pass(ground_pass) = string.

:- implementation.

:- import_module math, int, bool.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.coords.

elevation_acm_rate_gbps(rf_x_band, Elev) = Rate :-
    ElevDeg = rad_to_deg(Elev),
    ( if ElevDeg < 10.0 then Rate = 0.35
      else if ElevDeg < 25.0 then Rate = 0.60
      else Rate = 0.95
    ).

elevation_acm_rate_gbps(rf_ka_band, Elev) = Rate :-
    ElevDeg = rad_to_deg(Elev),
    ( if ElevDeg < 10.0 then Rate = 0.90
      else if ElevDeg < 25.0 then Rate = 1.60
      else if ElevDeg < 50.0 then Rate = 2.40
      else Rate = 3.20
    ).

elevation_acm_rate_gbps(optical_direct_to_earth, Elev) = Rate :-
    ElevDeg = rad_to_deg(Elev),
    ( if ElevDeg < 20.0 then Rate = 10.0
      else Rate = 50.0
    ).

compute_ground_passes(SatId, Station, Ephemeris) = Passes :-
    MinEl = Station ^ gs_min_elevation,
    Band  = Station ^ gs_supported_band,
    % Filter ephemeris points where satellite elevation >= min_elevation
    PassSamples = list.map((func(Pt) =
        eval_pass_point(Station ^ gs_geo, Pt)
    ), Ephemeris),
    Passes = group_pass_samples(SatId, Station ^ gs_id, MinEl, Band, PassSamples, no, []).

:- type pass_pt
    --->    pass_pt(
                ppt_epoch :: datetime,
                ppt_dt    :: float,
                ppt_elev  :: float
            ).

:- func eval_pass_point(geodetic, orbit_ephemeris_point) = pass_pt.
eval_pass_point(StationGeo, Pt) = pass_pt(Pt ^ oep_epoch, Pt ^ oep_dt_sec, Elev) :-
    Topo = ecef_to_topocentric(StationGeo, Pt ^ oep_ecef_pos),
    Elev = Topo ^ topo_elevation.

:- func group_pass_samples(string, string, float, rf_band, list(pass_pt), bool, list(pass_pt)) = list(ground_pass).
group_pass_samples(SatId, StId, _MinEl, Band, [], InPass, CurrGroup) = Out :-
    ( InPass = yes, CurrGroup = [_ | _] ->
        Out = [build_pass_from_points(SatId, StId, Band, list.reverse(CurrGroup))]
    ;
        Out = []
    ).
group_pass_samples(SatId, StId, MinEl, Band, [Pt | Rest], InPass, CurrGroup) = Out :-
    IsVisible = (if Pt ^ ppt_elev >= MinEl then yes else no),
    (
        InPass = no,
        ( IsVisible = yes ->
            Out = group_pass_samples(SatId, StId, MinEl, Band, Rest, yes, [Pt])
        ;
            Out = group_pass_samples(SatId, StId, MinEl, Band, Rest, no, [])
        )
    ;
        InPass = yes,
        ( IsVisible = yes ->
            Out = group_pass_samples(SatId, StId, MinEl, Band, Rest, yes, [Pt | CurrGroup])
        ;
            Pass = build_pass_from_points(SatId, StId, Band, list.reverse(CurrGroup)),
            Out = [Pass | group_pass_samples(SatId, StId, MinEl, Band, Rest, no, [])]
        )
    ).

:- func build_pass_from_points(string, string, rf_band, list(pass_pt)) = ground_pass.
build_pass_from_points(SatId, StId, Band, Points) = Pass :-
    ( Points = [First | _] ->
        Last = list.det_last(Points),
        AosEpoch = First ^ ppt_epoch,
        AosDt    = First ^ ppt_dt,
        LosEpoch = Last ^ ppt_epoch,
        LosDt    = Last ^ ppt_dt,
        Duration = LosDt - AosDt,
        MaxEl = list.foldl((func(P, Acc) = (if P ^ ppt_elev > Acc then P ^ ppt_elev else Acc)),
                           Points, -math.pi),
        % Integrate downloaded data volume: sum(rate(elev) * dt)
        ( if list.length(Points) > 1 then
            Dt_step = Duration / float(list.length(Points) - 1)
          else
            Dt_step = 1.0
        ),
        DataCap = list.foldl((func(P, Acc) = Acc + (elevation_acm_rate_gbps(Band, P ^ ppt_elev) * Dt_step)),
                             Points, 0.0),
        Pass = ground_pass(StId, SatId, AosEpoch, AosDt, LosEpoch, LosDt, Duration, MaxEl, DataCap)
    ;
        Epoch0 = datetime(2026, 1, 1, 0, 0, 0.0),
        Pass = ground_pass(StId, SatId, Epoch0, 0.0, Epoch0, 0.0, 0.0, 0.0, 0.0)
    ).

format_ground_pass(P) = Str :-
    string.format("[%s <- %s] AOS: %s -> LOS: %s | Dur: %0.1fs | MaxEl: %0.1f deg | Capacity: %0.1f Gb",
        [s(P ^ gp_station_id),
         s(P ^ gp_sat_id),
         s(format_iso8601(P ^ gp_aos_epoch)),
         s(format_iso8601(P ^ gp_los_epoch)),
         f(P ^ gp_duration_sec),
         f(rad_to_deg(P ^ gp_max_elevation)),
         f(P ^ gp_data_capacity_gb)], Str).
