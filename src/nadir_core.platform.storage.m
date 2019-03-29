:- module nadir_core.platform.storage.
:- interface.

:- import_module float, bool, string.

:- type storage_subsystem_specs
    --->    storage_subsystem_specs(
                sss_capacity_gigabits     :: float, % Total mass memory capacity (e.g. 2048 Gb = 256 GB)
                sss_payload_ingest_gbps   :: float, % Sensor write data rate during imaging (e.g. 2.4 Gbps)
                sss_downlink_rate_gbps    :: float, % RF X/Ka band downlink dump rate (e.g. 1.2 Gbps)
                sss_isl_rate_gbps         :: float, % Laser crosslink data transfer rate (e.g. 10.0 Gbps)
                sss_overflow_margin       :: float  % Safety threshold fraction (e.g. 0.95 = 95%)
            ).

:- type storage_state
    --->    storage_state(
                ss_used_gigabits          :: float, % Current stored payload data
                ss_high_priority_gb       :: float, % Priority partition
                ss_standard_gb            :: float, % Standard partition
                ss_total_ingested_gb      :: float, % Cumulative data written
                ss_total_downlinked_gb    :: float  % Cumulative data downlinked
            ).

% Default configuration
:- func default_storage_specs = storage_subsystem_specs.
:- func initial_storage_state = storage_state.

% Step storage state over time interval dt (seconds)
% Inputs: specs, current state, payload active (bool), is_high_priority (bool),
%         downlink active (bool), dt seconds
:- func step_storage_state(storage_subsystem_specs, storage_state, bool, bool, bool, float) = storage_state.

% Check whether mass memory has remaining capacity
:- func has_storage_capacity(storage_subsystem_specs, storage_state) = bool.
:- func storage_fraction_used(storage_subsystem_specs, storage_state) = float.

% Formatting
:- func format_storage_state(storage_subsystem_specs, storage_state) = string.

:- implementation.

:- import_module math, list.

default_storage_specs =
    storage_subsystem_specs(2048.0, 2.4, 1.2, 10.0, 0.95).

initial_storage_state = storage_state(0.0, 0.0, 0.0, 0.0, 0.0).

step_storage_state(Specs, CurrState, PayloadOn, IsHighPri, DownlinkOn, Dt_sec) = NextState :-
    % 1. Ingestion: Gb = rate * dt
    IngestRate = Specs ^ sss_payload_ingest_gbps,
    ( if PayloadOn = yes then
        IngestGb = IngestRate * Dt_sec
      else
        IngestGb = 0.0
    ),
    % 2. Downlink dump: Gb = rate * dt
    DumpRate = Specs ^ sss_downlink_rate_gbps,
    ( if DownlinkOn = yes then
        DumpGb = DumpRate * Dt_sec
      else
        DumpGb = 0.0
    ),
    % 3. Partition updates
    Cap = Specs ^ sss_capacity_gigabits,
    Used0 = CurrState ^ ss_used_gigabits,
    Used_raw = Used0 + IngestGb - DumpGb,
    ( if Used_raw > Cap then Used_next = Cap
      else if Used_raw < 0.0 then Used_next = 0.0
      else Used_next = Used_raw
    ),
    ( if (PayloadOn = yes, IsHighPri = yes) then
        HighPri_next = CurrState ^ ss_high_priority_gb + IngestGb
      else if DownlinkOn = yes then
        % Downlink high priority first
        HighPri_rem = CurrState ^ ss_high_priority_gb - DumpGb,
        ( if HighPri_rem < 0.0 then HighPri_next = 0.0 else HighPri_next = HighPri_rem )
      else
        HighPri_next = CurrState ^ ss_high_priority_gb
    ),
    StdPri_next = Used_next - HighPri_next,
    NextState = storage_state(Used_next,
                              HighPri_next,
                              StdPri_next,
                              CurrState ^ ss_total_ingested_gb + IngestGb,
                              CurrState ^ ss_total_downlinked_gb + DumpGb).

has_storage_capacity(Specs, State) = HasCap :-
    MaxAllowed = (Specs ^ sss_capacity_gigabits) * (Specs ^ sss_overflow_margin),
    ( if State ^ ss_used_gigabits < MaxAllowed then
        HasCap = yes
      else
        HasCap = no
    ).

storage_fraction_used(Specs, State) =
    State ^ ss_used_gigabits / Specs ^ sss_capacity_gigabits.

format_storage_state(Specs, State) = Str :-
    string.format("Used: %0.1f / %0.1f Gb (%0.1f%%) | Ingested: %0.1f Gb | Downlinked: %0.1f Gb",
        [f(State ^ ss_used_gigabits),
         f(Specs ^ sss_capacity_gigabits),
         f(storage_fraction_used(Specs, State) * 100.0),
         f(State ^ ss_total_ingested_gb),
         f(State ^ ss_total_downlinked_gb)], Str).
