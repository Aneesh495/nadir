:- module nadir_core.io_czml.
:- interface.

:- import_module string, list, pair.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.temporal.
:- import_module nadir_core.astro.propagator.

% Export satellite orbital track into Cesium CZML packet
:- func export_satellite_czml(string, datetime, list(orbit_ephemeris_point)) = string.

% Export complete constellation trajectory document in CZML format
:- func export_constellation_czml(string, datetime, datetime, list(pair(string, list(orbit_ephemeris_point)))) = string.

% Export inter-satellite laser link polyline between two satellites
:- func export_isl_link_czml(string, string, string, datetime, float, float) = string.

:- implementation.

:- import_module float, int.
:- import_module nadir_core.astro.vec3.

export_constellation_czml(DocName, StartTime, EndTime, SatTracks) = CzmlStr :-
    Header = format_czml_header(DocName, StartTime, EndTime),
    SatPackets = list.map((func(SatId - Track) =
        export_satellite_czml(SatId, StartTime, Track)
    ), SatTracks),
    Body = string.join_list(",\n", SatPackets),
    CzmlStr = "[\n" ++ Header ++ ",\n" ++ Body ++ "\n]".

:- func format_czml_header(string, datetime, datetime) = string.
format_czml_header(DocName, StartTime, EndTime) = Header :-
    StartIso = format_iso8601(StartTime),
    EndIso   = format_iso8601(EndTime),
    string.format("  {\n" ++
                  "    \"id\": \"document\",\n" ++
                  "    \"name\": \"%s\",\n" ++
                  "    \"version\": \"1.0\",\n" ++
                  "    \"clock\": {\n" ++
                  "      \"interval\": \"%s/%s\",\n" ++
                  "      \"currentTime\": \"%s\",\n" ++
                  "      \"multiplier\": 60,\n" ++
                  "      \"range\": \"LOOP_STOP\",\n" ++
                  "      \"step\": \"SYSTEM_CLOCK_MULTIPLIER\"\n" ++
                  "    }\n" ++
                  "  }",
        [s(DocName), s(StartIso), s(EndIso), s(StartIso)], Header).

export_satellite_czml(SatId, StartTime, Track) = Packet :-
    StartIso = format_iso8601(StartTime),
    CartesianValues = format_cartesian_samples(Track),
    string.format("  {\n" ++
                  "    \"id\": \"%s\",\n" ++
                  "    \"name\": \"%s\",\n" ++
                  "    \"position\": {\n" ++
                  "      \"interpolationAlgorithm\": \"LAGRANGE\",\n" ++
                  "      \"interpolationDegree\": 5,\n" ++
                  "      \"referenceFrame\": \"FIXED\",\n" ++
                  "      \"epoch\": \"%s\",\n" ++
                  "      \"cartesian\": [\n" ++
                  "        %s\n" ++
                  "      ]\n" ++
                  "    },\n" ++
                  "    \"point\": {\n" ++
                  "      \"color\": { \"rgba\": [0, 220, 255, 255] },\n" ++
                  "      \"pixelSize\": 7\n" ++
                  "    },\n" ++
                  "    \"path\": {\n" ++
                  "      \"material\": { \"solidColor\": { \"color\": { \"rgba\": [0, 180, 255, 180] } } },\n" ++
                  "      \"width\": 1.5,\n" ++
                  "      \"resolution\": 60,\n" ++
                  "      \"leadTime\": 2700,\n" ++
                  "      \"trailTime\": 2700\n" ++
                  "    }\n" ++
                  "  }",
        [s(SatId), s(SatId), s(StartIso), s(CartesianValues)], Packet).

:- func format_cartesian_samples(list(orbit_ephemeris_point)) = string.
format_cartesian_samples(Track) = Str :-
    SampleStrings = list.map((func(Pt) = S :-
        Dt = Pt ^ oep_dt_sec,
        Pos = Pt ^ oep_ecef_pos,
        string.format("%0.1f, %0.3f, %0.3f, %0.3f",
            [f(Dt), f(Pos ^ v_x), f(Pos ^ v_y), f(Pos ^ v_z)], S)
    ), Track),
    Str = string.join_list(",\n        ", SampleStrings).

export_isl_link_czml(LinkId, SatSrc, SatDst, Epoch0, StartDt, EndDt) = Packet :-
    StartEpoch = add_seconds(Epoch0, StartDt),
    EndEpoch   = add_seconds(Epoch0, EndDt),
    Interval = format_iso8601(StartEpoch) ++ "/" ++ format_iso8601(EndEpoch),
    string.format("  {\n" ++
                  "    \"id\": \"ISL_%s\",\n" ++
                  "    \"name\": \"Laser ISL %s to %s\",\n" ++
                  "    \"availability\": \"%s\",\n" ++
                  "    \"polyline\": {\n" ++
                  "      \"positions\": {\n" ++
                  "        \"references\": [\"%s#position\", \"%s#position\"]\n" ++
                  "      },\n" ++
                  "      \"material\": {\n" ++
                  "        \"solidColor\": { \"color\": { \"rgba\": [50, 255, 50, 220] } }\n" ++
                  "      },\n" ++
                  "      \"width\": 2.0\n" ++
                  "    }\n" ++
                  "  }",
        [s(LinkId), s(SatSrc), s(SatDst), s(Interval), s(SatSrc), s(SatDst)], Packet).
