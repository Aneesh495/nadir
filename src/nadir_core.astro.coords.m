:- module nadir_core.astro.coords.
:- interface.

:- import_module float, string.
:- import_module nadir_core.astro.vec3.

:- type geodetic
    --->    geodetic(
                geo_lat :: float, % Latitude in radians [-pi/2, pi/2]
                geo_lon :: float, % Longitude in radians [-pi, pi]
                geo_alt :: float  % Height above WGS-84 ellipsoid in meters
            ).

:- type topocentric
    --->    topocentric(
                topo_azimuth   :: float, % Azimuth in radians [0, 2*pi] clockwise from North
                topo_elevation :: float, % Elevation in radians [-pi/2, pi/2] above horizon
                topo_range     :: float  % Slant range in meters
            ).

% ECI (J2000) <-> ECEF (WGS-84) Transformations
:- func eci_to_ecef(vec3, float) = vec3.
:- func ecef_to_eci(vec3, float) = vec3.
:- func eci_to_ecef_vel(vec3, vec3, float) = vec3.
:- func ecef_to_eci_vel(vec3, vec3, float) = vec3.

% Geodetic <-> ECEF Transformations
:- func geodetic_to_ecef(geodetic) = vec3.
:- func ecef_to_geodetic(vec3) = geodetic.

% Ground Site Topocentric Horizon Frame
% Given ground site geodetic position and satellite ECEF position
:- func ecef_to_topocentric(geodetic, vec3) = topocentric.

% Formatting utilities
:- func format_geodetic_deg(geodetic) = string.
:- func format_topocentric_deg(topocentric) = string.

:- implementation.

:- import_module math, list.
:- import_module nadir_core.astro.constants.

eci_to_ecef(R_eci, Gmst) = mat3_mul_vec(mat3_rot_z(Gmst), R_eci).

ecef_to_eci(R_ecef, Gmst) = mat3_mul_vec(mat3_rot_z(-Gmst), R_ecef).

eci_to_ecef_vel(R_eci, V_eci, Gmst) = V_ecef :-
    Rz = mat3_rot_z(Gmst),
    R_ecef = mat3_mul_vec(Rz, R_eci),
    V_rot = mat3_mul_vec(Rz, V_eci),
    % Corotational velocity: v_ecef = Rz * v_eci - omega x r_ecef
    Omega_vec = vec3(0.0, 0.0, earth_omega),
    V_cross = vec3_cross(Omega_vec, R_ecef),
    V_ecef = vec3_sub(V_rot, V_cross).

ecef_to_eci_vel(R_ecef, V_ecef, Gmst) = V_eci :-
    Rz_inv = mat3_rot_z(-Gmst),
    Omega_vec = vec3(0.0, 0.0, earth_omega),
    V_corot = vec3_add(V_ecef, vec3_cross(Omega_vec, R_ecef)),
    V_eci = mat3_mul_vec(Rz_inv, V_corot).

% Geodetic to ECEF (WGS-84)
geodetic_to_ecef(geodetic(Lat, Lon, Alt)) = vec3(X, Y, Z) :-
    A = wgs84_a,
    E2 = wgs84_e2,
    SinLat = sin(Lat),
    CosLat = cos(Lat),
    SinLon = sin(Lon),
    CosLon = cos(Lon),
    N = A / sqrt(1.0 - (E2 * SinLat * SinLat)),
    X = (N + Alt) * CosLat * CosLon,
    Y = (N + Alt) * CosLat * SinLon,
    Z = (N * (1.0 - E2) + Alt) * SinLat.

% ECEF to Geodetic using Bowring's closed-form algorithm
ecef_to_geodetic(vec3(X, Y, Z)) = geodetic(Lat, Lon, Alt) :-
    A = wgs84_a,
    B = wgs84_b,
    E2 = wgs84_e2,
    Ep2 = wgs84_ep2,
    P = sqrt((X * X) + (Y * Y)),
    ( if P < 1.0e-6 then
        % Near polar singularity
        Lon = 0.0,
        ( if Z >= 0.0 then
            Lat = half_pi,
            Alt = Z - B
          else
            Lat = -half_pi,
            Alt = -Z - B
        )
      else
        Lon = atan2(Y, X),
        Theta = atan2(Z * A, P * B),
        SinTheta = sin(Theta),
        CosTheta = cos(Theta),
        Num = Z + (Ep2 * B * (SinTheta * SinTheta * SinTheta)),
        Den = P - (E2 * A * (CosTheta * CosTheta * CosTheta)),
        Lat = atan2(Num, Den),
        SinLat = sin(Lat),
        N = A / sqrt(1.0 - (E2 * SinLat * SinLat)),
        Alt = (P / cos(Lat)) - N
    ).

% ECEF to Topocentric Azimuth, Elevation, Range
ecef_to_topocentric(SiteGeo, SatEcef) = topocentric(Az, El, Range) :-
    SiteEcef = geodetic_to_ecef(SiteGeo),
    RhoEcef = vec3_sub(SatEcef, SiteEcef),
    Range = vec3_norm(RhoEcef),
    ( if Range < 1.0e-6 then
        Az = 0.0,
        El = half_pi
      else
        Lat = SiteGeo ^ geo_lat,
        Lon = SiteGeo ^ geo_lon,
        SinLat = sin(Lat),
        CosLat = cos(Lat),
        SinLon = sin(Lon),
        CosLon = cos(Lon),
        % Transform to East-North-Up (ENU) frame
        Dx = RhoEcef ^ v_x,
        Dy = RhoEcef ^ v_y,
        Dz = RhoEcef ^ v_z,
        East  = -SinLon * Dx + CosLon * Dy,
        North = -SinLat * CosLon * Dx - SinLat * SinLon * Dy + CosLat * Dz,
        Up    =  CosLat * CosLon * Dx + CosLat * SinLon * Dy + SinLat * Dz,
        Horizontal = sqrt((East * East) + (North * North)),
        El = atan2(Up, Horizontal),
        RawAz = atan2(East, North),
        ( if RawAz < 0.0 then
            Az = RawAz + two_pi
          else
            Az = RawAz
        )
    ).

format_geodetic_deg(geodetic(Lat, Lon, Alt)) = Str :-
    string.format("Lat: %0.4f deg, Lon: %0.4f deg, Alt: %0.1f m",
        [f(rad_to_deg(Lat)), f(rad_to_deg(Lon)), f(Alt)], Str).

format_topocentric_deg(topocentric(Az, El, Range)) = Str :-
    string.format("Az: %0.2f deg, El: %0.2f deg, Range: %0.1f km",
        [f(rad_to_deg(Az)), f(rad_to_deg(El)), f(Range / 1000.0)], Str).
