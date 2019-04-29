:- module nadir_core.io_tle.
:- interface.

:- import_module string, bool, maybe, float, int.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.kepler.

:- type norad_tle
    --->    norad_tle(
                tle_name            :: string,
                tle_sat_number      :: int,
                tle_epoch_year      :: int,
                tle_epoch_day       :: float,
                tle_inclination_deg :: float,
                tle_raan_deg        :: float,
                tle_eccentricity    :: float,
                tle_arg_perigee_deg :: float,
                tle_mean_anomaly_deg:: float,
                tle_mean_motion_rev :: float,
                tle_rev_number      :: int
            ).

% Parse standard 2-line or 3-line NORAD TLE strings
:- func parse_tle(string, string, string) = maybe(norad_tle).
:- func parse_tle_two_line(string, string) = maybe(norad_tle).

% Verify NORAD TLE checksum modulo 10
:- func verify_tle_checksum(string) = bool.

% Convert parsed TLE to Keplerian state elements at epoch
:- func tle_to_keplerian(norad_tle) = keplerian_elements.

% Convert TLE fractional day of year to UTC datetime
:- func tle_epoch_to_datetime(int, float) = datetime.

% Formatting
:- func format_tle_summary(norad_tle) = string.

:- implementation.

:- import_module math, char, list.
:- import_module nadir_core.astro.constants.

parse_tle_two_line(Line1, Line2) = parse_tle("UNKNOWN", Line1, Line2).

parse_tle(Name, Line1, Line2) = Result :-
    Trimmed1 = string.strip(Line1),
    Trimmed2 = string.strip(Line2),
    Len1 = string.length(Trimmed1),
    Len2 = string.length(Trimmed2),
    ( if (Len1 >= 68, Len2 >= 68) then
        % Verify line indicators
        C1 = string.unsafe_index(Trimmed1, 0),
        C2 = string.unsafe_index(Trimmed2, 0),
        ( if (C1 = '1', C2 = '2') then
            % Extract line 1 fields
            SatNum1Str = string.strip(string.between(Trimmed1, 2, 7)),
            EpochYrStr = string.strip(string.between(Trimmed1, 18, 20)),
            EpochDayStr = string.strip(string.between(Trimmed1, 20, 32)),

            % Extract line 2 fields
            _SatNum2Str = string.strip(string.between(Trimmed2, 2, 7)),
            IncStr     = string.strip(string.between(Trimmed2, 8, 16)),
            RaanStr    = string.strip(string.between(Trimmed2, 17, 25)),
            EccStr     = string.strip(string.between(Trimmed2, 26, 33)),
            ArgPStr    = string.strip(string.between(Trimmed2, 34, 42)),
            MStr       = string.strip(string.between(Trimmed2, 43, 51)),
            MmStr      = string.strip(string.between(Trimmed2, 52, 63)),
            RevStr     = string.strip(string.between(Trimmed2, 63, 68)),

            ( if
                string.to_int(SatNum1Str, SatNum),
                string.to_int(EpochYrStr, ShortYr),
                string.to_float(EpochDayStr, EpochDay),
                string.to_float(IncStr, IncDeg),
                string.to_float(RaanStr, RaanDeg),
                string.to_float("0." ++ EccStr, Ecc),
                string.to_float(ArgPStr, ArgPDeg),
                string.to_float(MStr, M_Deg),
                string.to_float(MmStr, MmRev),
                string.to_int(RevStr, RevNum)
              then
                FullYear = (if ShortYr < 57 then 2000 + ShortYr else 1900 + ShortYr),
                Tle = norad_tle(string.strip(Name), SatNum, FullYear, EpochDay,
                                IncDeg, RaanDeg, Ecc, ArgPDeg, M_Deg, MmRev, RevNum),
                Result = yes(Tle)
              else
                Result = no
            )
          else
            Result = no
        )
      else
        Result = no
    ).

verify_tle_checksum(Line) = Valid :-
    Trimmed = string.strip(Line),
    Len = string.length(Trimmed),
    ( if Len >= 69 then
        Sum = list.foldl((func(Idx, Acc) = Acc + char_tle_weight(string.unsafe_index(Trimmed, Idx))),
                         0 .. 67, 0),
        ExpectedModulo = Sum mod 10,
        CheckChar = string.unsafe_index(Trimmed, 68),
        ( if char.to_int(CheckChar, ActualVal), ActualVal - 48 = ExpectedModulo then
            Valid = yes
          else
            Valid = no
        )
      else
        Valid = no
    ).

:- func char_tle_weight(char) = int.
char_tle_weight(C) = W :-
    ( if char.is_digit(C) then
        char.to_int(C, Val),
        W = Val - 48
      else if C = ('-') then
        W = 1
      else
        W = 0
    ).

tle_epoch_to_datetime(Year, EpochDay) = Dt :-
    % Jan 1 00:00:00 of Year
    Jan1 = datetime(Year, 1, 1, 0, 0, 0.0),
    Jan1_JD = datetime_to_jd(Jan1),
    % EpochDay is 1-based (Day 1.5 is Jan 1 at 12:00:00)
    TargetJD = Jan1_JD + (EpochDay - 1.0),
    Dt = jd_to_datetime(TargetJD).

tle_to_keplerian(Tle) = Kep :-
    % Mean motion n in rad/s: rev/day * 2pi / 86400
    N_rad_per_sec = (Tle ^ tle_mean_motion_rev * two_pi) / 86400.0,
    % a = (mu / n^2)^(1/3)
    A = pow(earth_mu / (N_rad_per_sec * N_rad_per_sec), 1.0 / 3.0),
    Ecc = Tle ^ tle_eccentricity,
    Inc = deg_to_rad(Tle ^ tle_inclination_deg),
    Raan = deg_to_rad(Tle ^ tle_raan_deg),
    ArgP = deg_to_rad(Tle ^ tle_arg_perigee_deg),
    M_rad = deg_to_rad(Tle ^ tle_mean_anomaly_deg),
    Nu = mean_to_true_anomaly(M_rad, Ecc),
    Kep = keplerian_elements(A, Ecc, Inc, Raan, ArgP, Nu).

format_tle_summary(Tle) = Str :-
    string.format("[%s #%05d] Epoch: %d Day %0.4f | Inc: %0.2f deg | a: %0.1f km | e: %0.5f",
        [s(Tle ^ tle_name),
         i(Tle ^ tle_sat_number),
         i(Tle ^ tle_epoch_year),
         f(Tle ^ tle_epoch_day),
         f(Tle ^ tle_inclination_deg),
         f((pow(earth_mu / (((Tle ^ tle_mean_motion_rev * two_pi) / 86400.0) * ((Tle ^ tle_mean_motion_rev * two_pi) / 86400.0)), 1.0/3.0)) / 1000.0),
         f(Tle ^ tle_eccentricity)], Str).
