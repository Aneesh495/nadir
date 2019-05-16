:- module nadir_core.io_geojson.
:- interface.

:- import_module string, list.
:- use_module nadir_core.astro.
:- use_module nadir_core.access.
:- use_module nadir_core.ground.
:- import_module nadir_core.astro.propagator.
:- import_module nadir_core.access.target.
:- import_module nadir_core.ground.stations.

% Export satellite sub-satellite ground track as GeoJSON LineString feature
:- func export_ground_track_geojson(string, list(orbit_ephemeris_point)) = string.

% Export observation target catalog as GeoJSON FeatureCollection of Points
:- func export_targets_geojson(list(observation_target)) = string.

% Export ground station network as GeoJSON FeatureCollection of Points
:- func export_ground_stations_geojson(list(ground_station)) = string.

:- implementation.

:- import_module float, int.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.coords.

export_ground_track_geojson(SatId, Track) = Feature :-
    CoordStrings = list.map((func(Pt) = S :-
        Geo = Pt ^ oep_geo_pos,
        LatDeg = rad_to_deg(Geo ^ geo_lat),
        LonDeg = rad_to_deg(Geo ^ geo_lon),
        string.format("[%0.6f, %0.6f]", [f(LonDeg), f(LatDeg)], S)
    ), Track),
    CoordsListStr = string.join_list(",\n          ", CoordStrings),
    PtCount = list.length(Track),
    string.format("{\n" ++
                  "  \"type\": \"Feature\",\n" ++
                  "  \"properties\": {\n" ++
                  "    \"satellite_id\": \"%s\",\n" ++
                  "    \"sample_count\": %d\n" ++
                  "  },\n" ++
                  "  \"geometry\": {\n" ++
                  "    \"type\": \"LineString\",\n" ++
                  "    \"coordinates\": [\n" ++
                  "      %s\n" ++
                  "    ]\n" ++
                  "  }\n" ++
                  "}",
        [s(SatId), i(PtCount), s(CoordsListStr)], Feature).

export_targets_geojson(Targets) = FeatureColl :-
    Features = list.map((func(Tgt) = F :-
        Geo = Tgt ^ tgt_geo,
        LatDeg = rad_to_deg(Geo ^ geo_lat),
        LonDeg = rad_to_deg(Geo ^ geo_lon),
        AltM   = Geo ^ geo_alt,
        string.format("    {\n" ++
                      "      \"type\": \"Feature\",\n" ++
                      "      \"properties\": {\n" ++
                      "        \"target_id\": \"%s\",\n" ++
                      "        \"name\": \"%s\",\n" ++
                      "        \"priority\": %d,\n" ++
                      "        \"min_elevation_deg\": %0.2f,\n" ++
                      "        \"max_off_nadir_deg\": %0.2f\n" ++
                      "      },\n" ++
                      "      \"geometry\": {\n" ++
                      "        \"type\": \"Point\",\n" ++
                      "        \"coordinates\": [%0.6f, %0.6f, %0.1f]\n" ++
                      "      }\n" ++
                      "    }",
            [s(Tgt ^ tgt_id),
             s(Tgt ^ tgt_name),
             i(Tgt ^ tgt_priority),
             f(rad_to_deg(Tgt ^ tgt_min_elevation)),
             f(rad_to_deg(Tgt ^ tgt_max_off_nadir)),
             f(LonDeg), f(LatDeg), f(AltM)], F)
    ), Targets),
    FeaturesBody = string.join_list(",\n", Features),
    string.format("{\n" ++
                  "  \"type\": \"FeatureCollection\",\n" ++
                  "  \"features\": [\n" ++
                  "%s\n" ++
                  "  ]\n" ++
                  "}", [s(FeaturesBody)], FeatureColl).

export_ground_stations_geojson(Stations) = FeatureColl :-
    Features = list.map((func(GS) = F :-
        Geo = GS ^ gs_geo,
        LatDeg = rad_to_deg(Geo ^ geo_lat),
        LonDeg = rad_to_deg(Geo ^ geo_lon),
        AltM   = Geo ^ geo_alt,
        string.format("    {\n" ++
                      "      \"type\": \"Feature\",\n" ++
                      "      \"properties\": {\n" ++
                      "        \"station_id\": \"%s\",\n" ++
                      "        \"name\": \"%s\",\n" ++
                      "        \"antenna_dishes\": %d,\n" ++
                      "        \"min_elevation_deg\": %0.2f\n" ++
                      "      },\n" ++
                      "      \"geometry\": {\n" ++
                      "        \"type\": \"Point\",\n" ++
                      "        \"coordinates\": [%0.6f, %0.6f, %0.1f]\n" ++
                      "      }\n" ++
                      "    }",
            [s(GS ^ gs_id),
             s(GS ^ gs_name),
             i(GS ^ gs_antenna_count),
             f(rad_to_deg(GS ^ gs_min_elevation)),
             f(LonDeg), f(LatDeg), f(AltM)], F)
    ), Stations),
    FeaturesBody = string.join_list(",\n", Features),
    string.format("{\n" ++
                  "  \"type\": \"FeatureCollection\",\n" ++
                  "  \"features\": [\n" ++
                  "%s\n" ++
                  "  ]\n" ++
                  "}", [s(FeaturesBody)], FeatureColl).
