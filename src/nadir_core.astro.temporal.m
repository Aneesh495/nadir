:- module nadir_core.astro.temporal.
:- interface.

:- import_module float, int, string, maybe.

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
:- func parse_iso8601(string) = maybe(datetime).

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

% Greenwich Mean Sidereal Time (IAU-82 / Astronomical Almanac continuous model)
jd_to_gmst(JD) = GMST_rad :-
    D = JD - 2451545.0,
    T = D / 36525.0,
    Gmst_deg0 = 280.46061837 +
                360.98564736629 * D +
                0.000387933 * (T * T) -
                (T * T * T) / 38710000.0,
    Gmst_deg = Gmst_deg0 - float(floor_to_int(Gmst_deg0 / 360.0)) * 360.0,
    ( if Gmst_deg < 0.0 then
        Gmst_norm = Gmst_deg + 360.0
      else
        Gmst_norm = Gmst_deg
    ),
    GMST_rad = deg_to_rad(Gmst_norm).

datetime_to_gmst(DT) = jd_to_gmst(datetime_to_jd(DT)).

format_iso8601(DT) = Str :-
    string.format("%04d-%02d-%02dT%02d:%02d:%06.3fZ",
        [i(DT ^ dt_year),
         i(DT ^ dt_month),
         i(DT ^ dt_day),
         i(DT ^ dt_hour),
         i(DT ^ dt_minute),
         f(DT ^ dt_second)], Str).

parse_iso8601(Str) = Result :-
    Trimmed = string.strip(Str),
    ( if string.split_at_char('T', Trimmed) = [DatePart, TimePart] then
        ( if
            string.split_at_char('-', DatePart) = [YStr, MStr, DStr],
            string.split_at_char(':', TimePart) = [HStr, MinStr, SecFullStr]
          then
            SecChars = string.to_char_list(SecFullStr),
            CleanSecChars = list.filter((pred(C::in) is semidet :- C \= ('Z'), C \= ('z')), SecChars),
            SecStr = string.from_char_list(CleanSecChars),
            ( if
                string.to_int(YStr, Y),
                string.to_int(MStr, M),
                string.to_int(DStr, D),
                string.to_int(HStr, H),
                string.to_int(MinStr, Min),
                string.to_float(SecStr, SecFloat)
              then
                Result = yes(datetime(Y, M, D, H, Min, SecFloat))
              else if
                string.to_int(YStr, Y),
                string.to_int(MStr, M),
                string.to_int(DStr, D),
                string.to_int(HStr, H),
                string.to_int(MinStr, Min),
                string.to_int(SecStr, SecInt)
              then
                Result = yes(datetime(Y, M, D, H, Min, float(SecInt)))
              else
                Result = no
            )
          else
            Result = no
        )
      else
        Result = no
    ).
