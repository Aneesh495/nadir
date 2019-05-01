:- module nadir_core.io_target.
:- interface.

:- import_module string, list, maybe.
:- use_module nadir_core.access.
:- use_module nadir_core.scheduler.
:- import_module nadir_core.access.target.
:- import_module nadir_core.scheduler.types.

% Parse a single CSV line into an observation target
% Format: ID,NAME,LAT_DEG,LON_DEG,ALT_M,PRIORITY,MIN_ELEV_DEG,MAX_OFF_NADIR_DEG,MIN_SOLAR_ELEV_DEG
:- func parse_target_csv_line(string) = maybe(observation_target).

% Parse multi-line target catalog text, ignoring comment lines starting with '#'
:- func parse_target_catalog(string) = list(observation_target).

% Format observation target to CSV line
:- func format_target_csv_line(observation_target) = string.

% Parse a single CSV line into a task request
% Format: REQ_ID,TARGET_ID,PRIORITY,DURATION_SEC,VALUE_WEIGHT,DEADLINE_ISO8601
:- func parse_task_request_csv_line(string) = maybe(task_request).

% Parse multi-line task catalog text, ignoring comment lines starting with '#'
:- func parse_task_catalog(string) = list(task_request).

% Format task request to CSV line
:- func format_task_request_csv_line(task_request) = string.

:- implementation.

:- import_module float, int.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.temporal.

parse_target_csv_line(Line) = Result :-
    Trimmed = string.strip(Line),
    ( if (Trimmed = "" ; string.prefix(Trimmed, "#")) then
        Result = no
      else
        Tokens = string.split_at_char(',', Trimmed),
        ( if
            Tokens = [IdTok, NameTok, LatTok, LonTok, AltTok, PriTok, MinElTok, MaxOffTok, MinSolTok],
            string.to_float(string.strip(LatTok), LatDeg),
            string.to_float(string.strip(LonTok), LonDeg),
            string.to_float(string.strip(AltTok), AltM),
            string.to_int(string.strip(PriTok), Pri),
            string.to_float(string.strip(MinElTok), MinElDeg),
            string.to_float(string.strip(MaxOffTok), MaxOffDeg),
            string.to_float(string.strip(MinSolTok), MinSolDeg)
          then
            Geo = geodetic(deg_to_rad(LatDeg), deg_to_rad(LonDeg), AltM),
            Target = observation_target(string.strip(IdTok), string.strip(NameTok), Geo, Pri,
                                        deg_to_rad(MinElDeg), deg_to_rad(MaxOffDeg), deg_to_rad(MinSolDeg)),
            Result = yes(Target)
          else
            Result = no
        )
    ).

parse_target_catalog(Text) = Targets :-
    Lines = string.split_at_char('\n', Text),
    Targets = parse_target_lines(Lines, []).

:- func parse_target_lines(list(string), list(observation_target)) = list(observation_target).
parse_target_lines([], Acc) = list.reverse(Acc).
parse_target_lines([Line | Rest], Acc) = Result :-
    ( if parse_target_csv_line(Line) = yes(T) then
        Result = parse_target_lines(Rest, [T | Acc])
      else
        Result = parse_target_lines(Rest, Acc)
    ).

format_target_csv_line(T) = Str :-
    Geo = T ^ tgt_geo,
    LatDeg = rad_to_deg(Geo ^ geo_lat),
    LonDeg = rad_to_deg(Geo ^ geo_lon),
    AltM   = Geo ^ geo_alt,
    MinElDeg  = rad_to_deg(T ^ tgt_min_elevation),
    MaxOffDeg = rad_to_deg(T ^ tgt_max_off_nadir),
    MinSolDeg = rad_to_deg(T ^ tgt_min_solar_elev),
    string.format("%s,%s,%0.6f,%0.6f,%0.1f,%d,%0.2f,%0.2f,%0.2f",
        [s(T ^ tgt_id),
         s(T ^ tgt_name),
         f(LatDeg),
         f(LonDeg),
         f(AltM),
         i(T ^ tgt_priority),
         f(MinElDeg),
         f(MaxOffDeg),
         f(MinSolDeg)], Str).

parse_task_request_csv_line(Line) = Result :-
    Trimmed = string.strip(Line),
    ( if (Trimmed = "" ; string.prefix(Trimmed, "#")) then
        Result = no
      else
        Tokens = string.split_at_char(',', Trimmed),
        ( if
            Tokens = [ReqIdTok, TgtIdTok, PriTok, DurTok, WeightTok, DeadlineTok],
            string.to_int(string.strip(PriTok), Pri),
            string.to_float(string.strip(DurTok), DurSec),
            string.to_float(string.strip(WeightTok), WeightVal),
            DeadlineRes = parse_iso8601(string.strip(DeadlineTok)),
            DeadlineRes = yes(DeadlineDt)
          then
            Req = task_request(string.strip(ReqIdTok), string.strip(TgtIdTok),
                               Pri, DurSec, WeightVal, DeadlineDt),
            Result = yes(Req)
          else
            Result = no
        )
    ).

parse_task_catalog(Text) = Requests :-
    Lines = string.split_at_char('\n', Text),
    Requests = parse_task_lines(Lines, []).

:- func parse_task_lines(list(string), list(task_request)) = list(task_request).
parse_task_lines([], Acc) = list.reverse(Acc).
parse_task_lines([Line | Rest], Acc) = Result :-
    ( if parse_task_request_csv_line(Line) = yes(R) then
        Result = parse_task_lines(Rest, [R | Acc])
      else
        Result = parse_task_lines(Rest, Acc)
    ).

format_task_request_csv_line(R) = Str :-
    string.format("%s,%s,%d,%0.1f,%0.2f,%s",
        [s(R ^ tr_req_id),
         s(R ^ tr_target_id),
         i(R ^ tr_priority),
         f(R ^ tr_duration_sec),
         f(R ^ tr_value_weight),
         s(format_iso8601(R ^ tr_deadline))], Str).
