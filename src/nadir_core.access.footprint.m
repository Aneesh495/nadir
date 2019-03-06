:- module nadir_core.access.footprint.
:- interface.

:- import_module float, string.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.

:- type sensor_geometry
    --->    sensor_geometry(
                sg_fov_cross_track :: float, % Full cross-track FOV in radians
                sg_fov_along_track :: float, % Full along-track FOV in radians
                sg_max_off_nadir   :: float, % Maximum agile slew capability (FOR) in radians
                sg_detector_pixels :: int    % Linear pixel resolution
            ).

:- type sensor_footprint
    --->    sensor_footprint(
                fp_nadir_geo    :: geodetic, % Sub-satellite geodetic nadir point
                fp_swath_width  :: float,    % Ground swath width in meters
                fp_ground_res   :: float,    % Ground Sampling Distance (GSD) at nadir in meters
                fp_access_width :: float     % Total Field-of-Regard accessible width in meters
            ).

% Standard optical push-broom payload (e.g. 0.5m - 3m GSD class)
:- func default_high_res_optical_sensor = sensor_geometry.
:- func default_medium_res_multispectral_sensor = sensor_geometry.

% Compute instantaneous nadir ground footprint
:- func compute_footprint(sensor_geometry, vec3) = sensor_footprint.

% Off-nadir look angle calculation from satellite altitude and ground distance
:- func ground_distance_to_look_angle(float, float) = float.
:- func look_angle_to_ground_distance(float, float) = float.

% Compute GSD (Ground Sampling Distance) degradation at an off-nadir angle
:- func off_nadir_gsd(float, float) = float.

% Formatting
:- func format_footprint(sensor_footprint) = string.

:- implementation.

:- import_module math, int, list.
:- import_module nadir_core.astro.constants.

% High-resolution push-broom: 1.5 deg FOV, +/- 30 deg agile slew, 12000 pixels
default_high_res_optical_sensor =
    sensor_geometry(deg_to_rad(1.5), deg_to_rad(0.01), deg_to_rad(30.0), 12000).

% Medium-res multispectral: 8.0 deg FOV, +/- 20 deg slew, 6000 pixels
default_medium_res_multispectral_sensor =
    sensor_geometry(deg_to_rad(8.0), deg_to_rad(0.02), deg_to_rad(20.0), 6000).

compute_footprint(Sensor, SatEcef) = Footprint :-
    % 1. Sub-satellite nadir point
    NadirGeo = ecef_to_geodetic(SatEcef),
    Altitude = NadirGeo ^ geo_alt,
    % 2. Instantaneous swath width: W = 2 * h * tan(FOV/2)
    FovCross = Sensor ^ sg_fov_cross_track,
    Swath = 2.0 * Altitude * tan(FovCross * 0.5),
    % 3. Ground Sampling Distance (GSD) at nadir: GSD = Swath / Pixels
    Pixels = float(Sensor ^ sg_detector_pixels),
    ( if Pixels > 0.0 then Gsd0 = Swath / Pixels else Gsd0 = 1.0 ),
    % 4. Field of Regard accessible width: W_for = 2 * ground_dist(max_slew)
    MaxOffNadir = Sensor ^ sg_max_off_nadir,
    GroundReach = look_angle_to_ground_distance(Altitude, MaxOffNadir),
    AccessWidth = 2.0 * GroundReach,
    Footprint = sensor_footprint(NadirGeo, Swath, Gsd0, AccessWidth).

% Spherical geometry relation between look angle eta, Earth central angle lambda, and ground distance
% sin(eta) / Re = sin(eta + lambda) / (Re + h)
look_angle_to_ground_distance(Altitude, Eta) = GroundDist :-
    Re = earth_radius_equatorial,
    R_sat = Re + Altitude,
    SinEta = sin(Eta),
    SinPhi = (R_sat / Re) * SinEta,
    ( if SinPhi >= 1.0 then
        % Horizon grazing angle
        Phi = half_pi
      else
        Phi = asin(SinPhi)
    ),
    % Earth central angle: lambda = phi - eta
    Lambda = Phi - Eta,
    GroundDist = Re * Lambda.

ground_distance_to_look_angle(Altitude, GroundDist) = Eta :-
    Re = earth_radius_equatorial,
    R_sat = Re + Altitude,
    Lambda = GroundDist / Re,
    % Using law of cosines in satellite-center-target triangle
    % Slant range rho: rho^2 = Re^2 + R_sat^2 - 2*Re*R_sat*cos(lambda)
    Rho_sq = (Re * Re) + (R_sat * R_sat) - (2.0 * Re * R_sat * cos(Lambda)),
    ( if Rho_sq > 0.0 then Rho = sqrt(Rho_sq) else Rho = Altitude ),
    % Using law of sines: sin(eta) / Re = sin(lambda) / rho
    SinEta = (Re / Rho) * sin(Lambda),
    ( if SinEta >= 1.0 then Eta = half_pi
      else if SinEta =< -1.0 then Eta = -half_pi
      else Eta = asin(SinEta)
    ).

% GSD grows with slant range squared and projection tilt factor: GSD(eta) = GSD_0 / cos^2(eta + lambda)
off_nadir_gsd(GsdNadir, Eta) = GsdActual :-
    CosEta = cos(Eta),
    ( if CosEta > 0.1 then
        % Approximate degradation with 1 / cos^1.5(eta)
        GsdActual = GsdNadir / (CosEta * sqrt(CosEta))
      else
        GsdActual = GsdNadir * 10.0
    ).

format_footprint(sensor_footprint(Nadir, Swath, Gsd, ForWidth)) = Str :-
    string.format("Nadir: %s | Swath: %0.1f km | GSD: %0.2f m | Access Width: %0.1f km",
        [s(format_geodetic_deg(Nadir)),
         f(Swath / 1000.0),
         f(Gsd),
         f(ForWidth / 1000.0)], Str).
