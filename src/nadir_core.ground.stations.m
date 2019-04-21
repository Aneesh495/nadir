:- module nadir_core.ground.stations.
:- interface.

:- import_module float, int, string, list.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.coords.

:- type rf_band
    --->    rf_x_band  % 8.0 - 8.4 GHz (600 Mbps nominal)
    ;       rf_ka_band % 25.5 - 27.0 GHz (2.0 Gbps nominal)
    ;       optical_direct_to_earth. % 100 Gbps laser downlinks

:- type ground_station
    --->    ground_station(
                gs_id               :: string,
                gs_name             :: string,
                gs_geo              :: geodetic,
                gs_min_elevation    :: float, % Radians (e.g. 5 deg = 0.087 rad)
                gs_antenna_count    :: int,   % Number of independent tracking dishes
                gs_supported_band   :: rf_band
            ).

% Global ground network catalog (Polar + Mid-latitude + Equatorial)
:- func standard_polar_and_equatorial_network = list(ground_station).

% Specific ground stations
:- func station_svalbard = ground_station.
:- func station_inuvik = ground_station.
:- func station_punta_arenas = ground_station.
:- func station_troll_antarctica = ground_station.
:- func station_singapore = ground_station.

% Formatting
:- func format_ground_station(ground_station) = string.

:- implementation.

:- import_module math.
:- import_module nadir_core.astro.constants.

station_svalbard =
    ground_station("GS_SVALBARD", "Svalbard Satellite Station, Norway",
                   geodetic(deg_to_rad(78.2297), deg_to_rad(15.4078), 450.0),
                   deg_to_rad(5.0), 4, rf_ka_band).

station_inuvik =
    ground_station("GS_INUVIK", "Inuvik Satellite Station, Canada",
                   geodetic(deg_to_rad(68.3607), deg_to_rad(-133.7230), 100.0),
                   deg_to_rad(5.0), 3, rf_ka_band).

station_punta_arenas =
    ground_station("GS_PUNTA_ARENAS", "Punta Arenas Station, Chile",
                   geodetic(deg_to_rad(-53.1638), deg_to_rad(-70.9171), 30.0),
                   deg_to_rad(5.0), 2, rf_x_band).

station_troll_antarctica =
    ground_station("GS_TROLL", "Troll Satellite Station, Antarctica",
                   geodetic(deg_to_rad(-72.0114), deg_to_rad(2.5350), 1270.0),
                   deg_to_rad(5.0), 2, rf_ka_band).

station_singapore =
    ground_station("GS_SINGAPORE", "Singapore Equatorial Gateway",
                   geodetic(deg_to_rad(1.3521), deg_to_rad(103.8198), 15.0),
                   deg_to_rad(10.0), 2, rf_x_band).

standard_polar_and_equatorial_network =
    [station_svalbard,
     station_inuvik,
     station_punta_arenas,
     station_troll_antarctica,
     station_singapore].

format_ground_station(GS) = Str :-
    string.format("[%s] %s | %s | Dishes: %d",
        [s(GS ^ gs_id),
         s(GS ^ gs_name),
         s(format_geodetic_deg(GS ^ gs_geo)),
         i(GS ^ gs_antenna_count)], Str).
