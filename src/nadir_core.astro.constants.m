:- module nadir_core.astro.constants.
:- interface.

:- import_module float.

% WGS-84 Reference Ellipsoid
:- func wgs84_a = float.          % Semi-major axis in meters
:- func wgs84_f = float.          % Flattening factor
:- func wgs84_b = float.          % Semi-minor axis in meters
:- func wgs84_e2 = float.         % First eccentricity squared
:- func wgs84_ep2 = float.        % Second eccentricity squared

% Earth Gravitational & Dynamic Parameters
:- func earth_mu = float.         % Geocentric gravitational parameter (m^3 / s^2)
:- func earth_mu_km = float.      % Geocentric gravitational parameter (km^3 / s^2)
:- func earth_j2 = float.         % Second zonal harmonic (oblateness)
:- func earth_j3 = float.         % Third zonal harmonic
:- func earth_j4 = float.         % Fourth zonal harmonic
:- func earth_omega = float.      % Earth nominal rotation rate (rad / s)
:- func earth_radius_equatorial = float. % Equatorial radius in meters
:- func earth_radius_polar = float.      % Polar radius in meters

% Physical Constants
:- func speed_of_light = float.   % Vacuum speed of light (m / s)
:- func astronomical_unit = float.% 1 AU in meters
:- func solar_radius = float.     % Solar radius in meters
:- func solar_constant = float.   % Solar irradiance at 1 AU (W / m^2)

% Mathematical & Angle Utilities
:- func astro_pi = float.
:- func two_pi = float.
:- func half_pi = float.
:- func deg_to_rad(float) = float.
:- func rad_to_deg(float) = float.
:- func wrap_two_pi(float) = float.
:- func wrap_pi(float) = float.

:- implementation.

:- import_module math.

wgs84_a = 6378137.0.
wgs84_f = 1.0 / 298.257223563.
wgs84_b = wgs84_a * (1.0 - wgs84_f).
wgs84_e2 = 2.0 * wgs84_f - (wgs84_f * wgs84_f).
wgs84_ep2 = (wgs84_a * wgs84_a - wgs84_b * wgs84_b) / (wgs84_b * wgs84_b).

earth_mu = 3.986004418e14.
earth_mu_km = 398600.4418.
earth_j2 = 1.08262668e-3.
earth_j3 = -2.5327e-6.
earth_j4 = -1.6196e-6.
earth_omega = 7.2921151467e-5.
earth_radius_equatorial = 6378137.0.
earth_radius_polar = 6356752.314245.

speed_of_light = 299792458.0.
astronomical_unit = 149597870700.0.
solar_radius = 696340000.0.
solar_constant = 1361.0.

astro_pi = math.pi.
two_pi = 2.0 * math.pi.
half_pi = math.pi / 2.0.

deg_to_rad(Deg) = Deg * (math.pi / 180.0).
rad_to_deg(Rad) = Rad * (180.0 / math.pi).

wrap_two_pi(Angle) = Wrapped :-
    Rem = Angle - float(floor_to_int(Angle / two_pi)) * two_pi,
    ( if Rem < 0.0 then
        Wrapped = Rem + two_pi
      else
        Wrapped = Rem
    ).

wrap_pi(Angle) = Wrapped :-
    A = wrap_two_pi(Angle),
    ( if A > math.pi then
        Wrapped = A - two_pi
      else
        Wrapped = A
    ).
