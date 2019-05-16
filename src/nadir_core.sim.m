:- module nadir_core.sim.
:- interface.

:- import_module float, int, string, list.
:- use_module nadir_core.astro.
:- use_module nadir_core.access.
:- use_module nadir_core.scheduler.
:- use_module nadir_core.isl.
:- use_module nadir_core.ground.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.access.target.
:- import_module nadir_core.scheduler.types.
:- import_module nadir_core.isl.topology.
:- import_module nadir_core.ground.stations.

:- type mission_config
    --->    mission_config(
                mc_sim_name         :: string,
                mc_start_epoch      :: datetime,
                mc_duration_sec     :: float,
                mc_time_step_sec    :: float,
                mc_constellation    :: list(satellite_node),
                mc_targets          :: list(observation_target),
                mc_requests         :: list(task_request),
                mc_ground_network   :: list(ground_station)
            ).

:- type satellite_sim_state
    --->    satellite_sim_state(
                sss_sat_id          :: string,
                sss_keplerian       :: keplerian_elements,
                sss_battery_soc     :: float,
                sss_storage_gb      :: float,
                sss_tasks_completed :: int,
                sss_data_downlinked :: float
            ).

:- type mission_telemetry
    --->    mission_telemetry(
                mt_total_tasks_requested  :: int,
                mt_total_tasks_completed  :: int,
                mt_data_collected_gb      :: float,
                mt_data_downlinked_gb     :: float,
                mt_min_battery_soc        :: float,
                mt_max_storage_used_gb    :: float,
                mt_isl_hops_routed        :: int,
                mt_downlink_passes_active :: int
            ).

:- type simulation_result
    --->    simulation_result(
                sr_config            :: mission_config,
                sr_telemetry         :: mission_telemetry,
                sr_final_sat_states  :: list(satellite_sim_state),
                sr_schedule          :: constellation_schedule
            ).

% Execute full closed-loop constellation mission simulation
:- func run_mission_simulation(mission_config) = simulation_result.

% Formatting
:- func format_simulation_summary(simulation_result) = string.

:- implementation.

:- import_module bool, math, pair.
:- use_module nadir_core.platform.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.propagator.
:- import_module nadir_core.astro.sun.
:- import_module nadir_core.platform.slew.
:- import_module nadir_core.platform.power.
:- import_module nadir_core.platform.storage.
:- import_module nadir_core.scheduler.optimizer.
:- import_module nadir_core.isl.contact_graph.
:- import_module nadir_core.isl.routing.
:- import_module nadir_core.ground.passes.
:- import_module nadir_core.ground.downlink.

run_mission_simulation(Config) = Result :-
    Nodes     = Config ^ mc_constellation,
    Targets   = Config ^ mc_targets,
    Requests  = Config ^ mc_requests,
    GroundNet = Config ^ mc_ground_network,
    Epoch0    = Config ^ mc_start_epoch,
    Duration  = Config ^ mc_duration_sec,
    StepSec   = Config ^ mc_time_step_sec,

    % 1. Propagate orbit ephemeris tracks for all constellation satellites
    MaxSteps = ceiling_to_int(Duration / StepSec) + 2,
    SatTracks = list.map((func(N) =
        (N ^ sat_id - propagate_orbit_track(N ^ sat_keplerian, Epoch0, StepSec, Duration, MaxSteps))
    ), Nodes),

    % 2. Evaluate candidate target access windows across constellation
    AccessWindows = list.condense(list.map((func(SatId - Track) =
        list.condense(list.map((func(Tgt) =
            compute_target_access_windows(SatId, Tgt, Track)
        ), Targets))
    ), SatTracks)),

    % 3. Execute constraint satisfaction mission scheduling optimizer
    Schedule = solve_constellation_schedule(default_agile_adcs, default_power_specs,
                                            default_storage_specs, Requests, AccessWindows),

    % 4. Compute ground station passes and downlink contact plan
    AllPasses = list.condense(list.map((func(SatId - Track) =
        list.condense(list.map((func(Station) =
            compute_ground_passes(SatId, Station, Track)
        ), GroundNet))
    ), SatTracks)),
    DownlinkPlan = allocate_downlink_contacts(GroundNet, AllPasses),

    % 5. Initialize satellite simulation states
    InitStates = list.map((func(N) =
        satellite_sim_state(N ^ sat_id, N ^ sat_keplerian, 1.0, 0.0, 0, 0.0)
    ), Nodes),

    % 6. Step timeline simulation loop
    SimLoopRes = sim_timeline_loop(0.0, Duration, StepSec, Epoch0, Nodes, SatTracks,
                                   Schedule ^ cs_observations, DownlinkPlan ^ dp_allocations,
                                   InitStates, 1.0, 0.0, 0),

    FinalStates = SimLoopRes ^ slr_states,
    MinSoc      = SimLoopRes ^ slr_min_soc,
    MaxStorage  = SimLoopRes ^ slr_max_storage,
    HopsRouted  = SimLoopRes ^ slr_hops_routed,

    TotalTasksReq = list.length(Requests),
    TotalTasksDone = list.length(Schedule ^ cs_observations),
    TotalCollected = list.foldl((func(Obs, Acc) = Acc + Obs ^ so_data_volume_gb),
                                Schedule ^ cs_observations, 0.0),
    TotalDownlinked = DownlinkPlan ^ dp_total_dumped_gb,
    PassesCount = DownlinkPlan ^ dp_passes_utilized,

    Telemetry = mission_telemetry(TotalTasksReq, TotalTasksDone, TotalCollected, TotalDownlinked,
                                  MinSoc, MaxStorage, HopsRouted, PassesCount),
    Result = simulation_result(Config, Telemetry, FinalStates, Schedule).

:- type sim_loop_result
    --->    sim_loop_result(
                slr_states      :: list(satellite_sim_state),
                slr_min_soc     :: float,
                slr_max_storage :: float,
                slr_hops_routed :: int
            ).

:- func sim_timeline_loop(float, float, float, datetime, list(satellite_node),
                          list(pair(string, list(orbit_ephemeris_point))),
                          list(scheduled_observation), list(allocated_downlink),
                          list(satellite_sim_state), float, float, int) = sim_loop_result.
sim_timeline_loop(CurrDt, Duration, StepSec, Epoch0, Nodes, Tracks, Observations, Downlinks,
                  States, MinSoc, MaxStorage, HopsAcc) = Result :-
    ( if CurrDt > Duration then
        Result = sim_loop_result(States, MinSoc, MaxStorage, HopsAcc)
      else
        CurrEpoch = add_seconds(Epoch0, CurrDt),
        Jd = datetime_to_jd(CurrEpoch),

        % Update each satellite state at this time step
        UpdatedStates = list.map((func(S) =
            step_single_satellite(S, CurrDt, StepSec, Jd, Tracks, Observations, Downlinks)
        ), States),

        % Update aggregate metrics
        StepMinSoc = list.foldl((func(S, Acc) =
            (if S ^ sss_battery_soc < Acc then S ^ sss_battery_soc else Acc)
        ), UpdatedStates, 1.0),
        NewMinSoc = (if StepMinSoc < MinSoc then StepMinSoc else MinSoc),

        StepMaxStorage = list.foldl((func(S, Acc) =
            (if S ^ sss_storage_gb > Acc then S ^ sss_storage_gb else Acc)
        ), UpdatedStates, 0.0),
        NewMaxStorage = (if StepMaxStorage > MaxStorage then StepMaxStorage else MaxStorage),

        % Check ISL routing sample at 60s intervals
        ( if (floor_to_int(CurrDt) mod 60 = 0, list.length(Nodes) >= 2) then
            SatPositions = list.map((func(N) = Pair :-
                SatId = N ^ sat_id,
                Pos = get_sat_pos_at_dt(SatId, CurrDt, Tracks),
                Pair = (SatId - orbit_state(Pos, vec3_zero))
            ), Nodes),
            ContactGraph = build_instantaneous_contact_graph(CurrDt, SatPositions, 5000000.0),
            FirstSat = (list.det_head(Nodes)) ^ sat_id,
            LastSat  = (list.det_last(Nodes)) ^ sat_id,
            Route = find_shortest_isl_route(ContactGraph, FirstSat, LastSat),
            ( if Route ^ ir_is_routable = yes then
                NewHops = HopsAcc + (list.length(Route ^ ir_hop_path) - 1)
              else
                NewHops = HopsAcc
            )
          else
            NewHops = HopsAcc
        ),

        NextDt = CurrDt + StepSec,
        Result = sim_timeline_loop(NextDt, Duration, StepSec, Epoch0, Nodes, Tracks,
                                   Observations, Downlinks, UpdatedStates, NewMinSoc,
                                   NewMaxStorage, NewHops)
    ).

:- func step_single_satellite(satellite_sim_state, float, float, float,
                              list(pair(string, list(orbit_ephemeris_point))),
                              list(scheduled_observation), list(allocated_downlink)) = satellite_sim_state.
step_single_satellite(SatState, CurrDt, StepSec, Jd, Tracks, Observations, Downlinks) = NextState :-
    SatId = SatState ^ sss_sat_id,
    SatEciPos = get_sat_pos_at_dt(SatId, CurrDt, Tracks),

    % EPS Power balance step
    PowerSpecs = default_power_specs,
    CurrPowerState = power_state(SatState ^ sss_battery_soc, 0.0, 0.0, 0.0),
    InSun = satellite_in_sunlight(SatEciPos, Jd),
    IsImaging = check_is_imaging(SatId, CurrDt, Observations),
    IsDownlinking = check_is_downlinking(SatId, CurrDt, Downlinks),
    NextPowerState = step_power_state(PowerSpecs, CurrPowerState, StepSec, InSun, IsImaging, IsDownlinking, 0.0),
    NewSoc = NextPowerState ^ ps_soc,

    % Storage buffer step
    ObsRateGbps = (if IsImaging = yes then 1.5 else 0.0),
    IngestedGb = ObsRateGbps * StepSec,

    % Downlink dump step
    DumpRateGbps = (if IsDownlinking = yes then 2.0 else 0.0),
    DumpedGb = DumpRateGbps * StepSec,

    CurrStorage = SatState ^ sss_storage_gb,
    NewStorage0 = (CurrStorage + IngestedGb) - DumpedGb,
    NewStorage = (if NewStorage0 < 0.0 then 0.0 else NewStorage0),

    NewTasksCompleted = SatState ^ sss_tasks_completed + (if IsImaging = yes then 1 else 0),
    NewTotalDumped    = SatState ^ sss_data_downlinked + DumpedGb,

    NextState = satellite_sim_state(SatId, SatState ^ sss_keplerian, NewSoc, NewStorage,
                                    NewTasksCompleted, NewTotalDumped).

:- func get_sat_pos_at_dt(string, float, list(pair(string, list(orbit_ephemeris_point)))) = vec3.
get_sat_pos_at_dt(SatId, CurrDt, Tracks) = Pos :-
    Matches = list.filter((pred(S - _::in) is semidet :- S = SatId), Tracks),
    ( if Matches = [_ - Track | _] then
        Pos = find_closest_pos(CurrDt, Track)
      else
        Pos = vec3_zero
    ).

:- func find_closest_pos(float, list(orbit_ephemeris_point)) = vec3.
find_closest_pos(_Dt, []) = vec3_zero.
find_closest_pos(Dt, [Pt | Rest]) = Pos :-
    ( if Rest = [NextPt | _] then
        ( if (Dt >= Pt ^ oep_dt_sec, Dt =< NextPt ^ oep_dt_sec) then
            Pos = Pt ^ oep_eci_pos
          else
            Pos = find_closest_pos(Dt, Rest)
        )
      else
        Pos = Pt ^ oep_eci_pos
    ).

:- func check_is_imaging(string, float, list(scheduled_observation)) = bool.
check_is_imaging(SatId, CurrDt, Observations) = Res :-
    Active = list.filter((pred(Obs::in) is semidet :-
        Obs ^ so_sat_id = SatId,
        CurrDt >= Obs ^ so_obs_start_dt,
        CurrDt =< Obs ^ so_obs_end_dt
    ), Observations),
    Res = (if Active = [_ | _] then yes else no).

:- func check_is_downlinking(string, float, list(allocated_downlink)) = bool.
check_is_downlinking(SatId, CurrDt, Downlinks) = Res :-
    Active = list.filter((pred(A::in) is semidet :-
        A ^ ad_sat_id = SatId,
        CurrDt >= A ^ ad_start_dt,
        CurrDt =< A ^ ad_end_dt
    ), Downlinks),
    Res = (if Active = [_ | _] then yes else no).

format_simulation_summary(Result) = Str :-
    Telem = Result ^ sr_telemetry,
    Cfg   = Result ^ sr_config,
    CompletionPct = (if Telem ^ mt_total_tasks_requested > 0 then
                        (float(Telem ^ mt_total_tasks_completed) / float(Telem ^ mt_total_tasks_requested)) * 100.0
                     else 0.0),
    string.format("=== Simulation '%s' Complete ===\n" ++
                  "Duration: %0.1fs | Epoch: %s\n" ++
                  "Tasks: %d/%d (%0.1f%%) Completed\n" ++
                  "Data Collected: %0.2f Gb | Downlinked: %0.2f Gb\n" ++
                  "Min Battery SoC: %0.1f%% | Max Storage Used: %0.2f Gb\n" ++
                  "ISL Mesh Hops Routed: %d | Downlink Contacts: %d\n" ++
                  "==================================",
        [s(Cfg ^ mc_sim_name),
         f(Cfg ^ mc_duration_sec),
         s(format_iso8601(Cfg ^ mc_start_epoch)),
         i(Telem ^ mt_total_tasks_completed),
         i(Telem ^ mt_total_tasks_requested),
         f(CompletionPct),
         f(Telem ^ mt_data_collected_gb),
         f(Telem ^ mt_data_downlinked_gb),
         f(Telem ^ mt_min_battery_soc * 100.0),
         f(Telem ^ mt_max_storage_used_gb),
         i(Telem ^ mt_isl_hops_routed),
         i(Telem ^ mt_downlink_passes_active)], Str).
