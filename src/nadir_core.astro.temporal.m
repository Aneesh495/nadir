:- module nadir_core.astro.temporal.
:- interface.

:- import_module float, int, string.

:- type datetime
    --->    datetime(
                dt_year   :: int,
                dt_month  :: int,
                dt_day    :: int,
                dt_hour   :: int,
                dt_minute :: int,
                dt_second :: float
            ).

% Julian Date conversions
:- func datetime_to_jd(datetime) = float.
:- func jd_to_datetime(float) = datetime.
:- func jd_to_mjd(float) = float.
:- func mjd_to_jd(float) = float.

% Epoch arithmetic (seconds)
:- func add_seconds(datetime, float) = datetime.
:- func diff_seconds(datetime, datetime) = float.

% Sidereal Time
% Greenwich Mean Sidereal Time (GMST) in radians for a given Julian Date
:- func jd_to_gmst(float) = float.
% GMST in radians for a given datetime
:- func datetime_to_gmst(datetime) = float.

% Formatting utilities
:- func format_iso8601(datetime) = string.

:- implementation.

:- import_module math, list.
:- import_module nadir_core.astro.constants.

% Standard Julian Date formula from calendar date (Meeus algorithm)
datetime_to_jd(DT) = JD :-
    Y0 = DT ^ dt_year,
    M0 = DT ^ dt_month,
    D  = DT ^ dt_day,
    H  = DT ^ dt_hour,
    Min = DT ^ dt_minute,
    S  = DT ^ dt_second,
    ( if M0 =< 2 then
        Y = Y0 - 1,
        M = M0 + 12
      else
        Y = Y0,
        M = M0
    ),
    A = Y / 100,
    B = 2 - A + (A / 4),
    DayFraction = (float(H) + float(Min) / 60.0 + S / 3600.0) / 24.0,
    JD0 = float(floor_to_int(365.25 * float(Y + 4716))) +
          float(floor_to_int(30.6001 * float(M + 1))) +
          float(D) + float(B) - 1524.5,
    JD = JD0 + DayFraction.

jd_to_mjd(JD) = JD - 2400000.5.
mjd_to_jd(MJD) = MJD + 2400000.5.

jd_to_datetime(JD) = datetime(Year, Month, Day, Hour, Minute, Second) :-
    Z = floor_to_int(JD + 0.5),
    F = (JD + 0.5) - float(Z),
    ( if Z < 2299161 then
        A = Z
      else
        Alpha = floor_to_int((float(Z) - 1867216.25) / 36524.25),
        A = Z + 1 + Alpha - (Alpha / 4)
    ),
    B = A + 1524,
    C = floor_to_int((float(B) - 122.1) / 365.25),
    D = floor_to_int(365.25 * float(C)),
    E = floor_to_int((float(B - D)) / 30.6001),
    DayWithFrac = float(B - D - floor_to_int(30.6001 * float(E))) + F,
    Day = floor_to_int(DayWithFrac),
    ( if E < 14 then
        Month = E - 1
      else
        Month = E - 13
    ),
    ( if Month > 2 then
        Year = C - 4716
      else
        Year = C - 4715
    ),
    FractionOfDay = DayWithFrac - float(Day),
    TotalSeconds = FractionOfDay * 86400.0,
    Hour = floor_to_int(TotalSeconds / 3600.0),
    RemSec = TotalSeconds - float(Hour * 3600),
    Minute = floor_to_int(RemSec / 60.0),
    Second = RemSec - float(Minute * 60).

add_seconds(DT, Secs) = Res :-
    JD0 = datetime_to_jd(DT),
    JD1 = JD0 + (Secs / 86400.0),
    Res = jd_to_datetime(JD1).

diff_seconds(DT2, DT1) = (datetime_to_jd(DT2) - datetime_to_jd(DT1)) * 86400.0.

% Greenwich Mean Sidereal Time (IAU-82 model)
jd_to_gmst(JD) = GMST_rad :-
    T = (JD - 2451545.0) / 36525.0,
    % GMST in seconds of time at 0h UT1
    Theta0_sec = 24110.54841 +
                 8640184.812866 * T +
                 0.093104 * (T * T) -
                 6.2e-6 * (T * T * T),
    % Add Earth rotation for the fractional day (UT1)
    Theta0_deg = Theta0_sec / 240.0,
    Theta0_rad = deg_to_rad(Theta0_deg),
    GMST_rad = wrap_two_pi(Theta0_rad).

datetime_to_gmst(DT) = jd_to_gmst(datetime_to_jd(DT)).

format_iso8601(DT) = Str :-
    string.format("%04d-%02d-%02dT%02d:%02d:%06.3fZ",
        [i(DT ^ dt_year),
         i(DT ^ dt_month),
         i(DT ^ dt_day),
         i(DT ^ dt_hour),
         i(DT ^ dt_minute),
         f(DT ^ dt_second)], Str).
