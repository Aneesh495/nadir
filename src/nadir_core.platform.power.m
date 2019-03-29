:- module nadir_core.platform.power.
:- interface.

:- import_module float, bool, string.

:- type power_subsystem_specs
    --->    power_subsystem_specs(
                pss_battery_capacity_wh :: float, % Nameplate capacity in Watt-hours (e.g. 600 Wh)
                pss_solar_peak_w        :: float, % Peak solar array power at 1 AU normal incidence (e.g. 280 W)
                pss_base_bus_draw_w     :: float, % Avionics, ADCS, thermal baseline power (e.g. 45 W)
                pss_payload_active_w    :: float, % Optical / SAR payload power when collecting (e.g. 175 W)
                pss_downlink_active_w   :: float, % High-rate RF transmitter power (e.g. 65 W)
                pss_slew_peak_w         :: float, % Reaction wheel peak power during agility slews (e.g. 50 W)
                pss_min_soc_threshold   :: float  % Safety minimum State of Charge (e.g. 0.65 = 65%)
            ).

:- type power_state
    --->    power_state(
                ps_soc                 :: float, % Current State of Charge [0.0, 1.0]
                ps_net_power_w         :: float, % Current net balance (generation - total load) in Watts
                ps_cumulative_wh_in    :: float, % Total energy harvested
                ps_cumulative_wh_out   :: float  % Total energy consumed
            ).

% Default configuration for 120kg remote sensing spacecraft
:- func default_power_specs = power_subsystem_specs.
:- func initial_power_state = power_state.

% Step power state over time interval dt (seconds)
% Inputs: specs, current power state, solar illumination fraction [0, 1], payload active (bool),
%         downlink active (bool), slewing active (bool), dt seconds
:- func step_power_state(power_subsystem_specs, power_state, float, bool, bool, bool, float) = power_state.

% Check whether power state satisfies minimum depth of discharge limit
:- func is_power_state_healthy(power_subsystem_specs, power_state) = bool.

% Formatting
:- func format_power_state(power_state) = string.

:- implementation.

:- import_module math, list.

default_power_specs =
    power_subsystem_specs(600.0, 280.0, 45.0, 175.0, 65.0, 50.0, 0.65).

initial_power_state = power_state(1.0, 0.0, 0.0, 0.0).

step_power_state(Specs, CurrState, IllumFrac, PayloadOn, DownlinkOn, SlewOn, Dt_sec) = NextState :-
    % 1. Solar generation: P_gen = P_peak * illumination_fraction
    P_gen = (Specs ^ pss_solar_peak_w) * IllumFrac,
    % 2. Total load: Base + Payload + Downlink + Slew
    P_base = Specs ^ pss_base_bus_draw_w,
    P_payload = (if PayloadOn = yes then Specs ^ pss_payload_active_w else 0.0),
    P_downlink = (if DownlinkOn = yes then Specs ^ pss_downlink_active_w else 0.0),
    P_slew = (if SlewOn = yes then Specs ^ pss_slew_peak_w else 0.0),
    P_load = P_base + P_payload + P_downlink + P_slew,
    % 3. Net power
    P_net = P_gen - P_load,
    % 4. State of Charge delta: delta_Wh = P_net * (dt / 3600)
    Capacity_wh = Specs ^ pss_battery_capacity_wh,
    Delta_wh = P_net * (Dt_sec / 3600.0),
    Delta_soc = Delta_wh / Capacity_wh,
    Soc0 = CurrState ^ ps_soc,
    Soc_raw = Soc0 + Delta_soc,
    ( if Soc_raw > 1.0 then Soc_next = 1.0
      else if Soc_raw < 0.0 then Soc_next = 0.0
      else Soc_next = Soc_raw
    ),
    Wh_in_delta = (if P_gen > 0.0 then P_gen * (Dt_sec / 3600.0) else 0.0),
    Wh_out_delta = P_load * (Dt_sec / 3600.0),
    NextState = power_state(Soc_next,
                            P_net,
                            CurrState ^ ps_cumulative_wh_in + Wh_in_delta,
                            CurrState ^ ps_cumulative_wh_out + Wh_out_delta).

is_power_state_healthy(Specs, State) = Healthy :-
    ( if State ^ ps_soc >= Specs ^ pss_min_soc_threshold then
        Healthy = yes
      else
        Healthy = no
    ).

format_power_state(State) = Str :-
    string.format("SoC: %0.1f%% | Net: %+0.1f W | Harvested: %0.1f Wh | Consumed: %0.1f Wh",
        [f(State ^ ps_soc * 100.0),
         f(State ^ ps_net_power_w),
         f(State ^ ps_cumulative_wh_in),
         f(State ^ ps_cumulative_wh_out)], Str).
