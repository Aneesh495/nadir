:- module nadir_core.astro.sun.
:- interface.

:- import_module float, string, bool.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.
:- import_module nadir_core.astro.kepler.
:- import_module nadir_core.astro.temporal.

:- type eclipse_state
    --->    full_sunlight
    ;       penumbra(fraction :: float) % 0.0 to 1.0
    ;       umbra.                      % Total eclipse (0.0 solar flux)

% Solar ephemeris calculation
% Returns unit vector pointing towards the Sun in ECI (J2000) frame for given Julian Date
:- func sun_vector_eci(float) = vec3.
:- func sun_position_eci(float) = vec3.

% Orbit Beta Angle (radians) between orbit normal and Sun vector
:- func orbit_beta_angle(keplerian_elements, float) = float.

% Satellite eclipse check
% Evaluates whether a satellite at position R_eci is eclipsed by the Earth
:- func satellite_eclipse_state(vec3, float) = eclipse_state.
:- func satellite_in_sunlight(vec3, float) = bool.
:- func satellite_illumination_fraction(vec3, float) = float.

% Target surface solar elevation angle (radians) above horizon
:- func target_solar_elevation(geodetic, datetime) = float.

% Formatting
:- func format_eclipse_state(eclipse_state) = string.

:- implementation.

:- import_module math, list.
:- import_module nadir_core.astro.constants.

% Analytical low-precision solar ephemeris (Astronomical Almanac / Montenbruck algorithm)
% Accurate to within 0.01 degrees across 1950 - 2050
sun_position_eci(JD) = vec3_scale(astronomical_unit * R_au, vec3(CosEcl * CosLambda,
                                                                 CosEpsilon * SinLambda - SinEpsilon * 0.0,
                                                                 SinEpsilon * SinLambda)) :-
    T = (JD - 2451545.0) / 36525.0,
    % Mean longitude of Sun
    L0_deg = 280.46646 + 36000.76983 * T + 0.0003032 * (T * T),
    % Mean anomaly of Sun
    M_deg  = 357.52911 + 35999.05029 * T - 0.0001537 * (T * T),
    M_rad  = deg_to_rad(M_deg),
    % Equation of center
    C_deg  = (1.914602 - 0.004817 * T - 0.000014 * (T * T)) * sin(M_rad) +
             (0.019993 - 0.000101 * T) * sin(2.0 * M_rad) +
             0.000289 * sin(3.0 * M_rad),
    % True ecliptic longitude
    Lambda_deg = L0_deg + C_deg,
    Lambda_rad = deg_to_rad(Lambda_deg),
    % Distance in AU
    R_au = 1.00014061 - 0.01670862 * cos(M_rad) - 0.000139589 * cos(2.0 * M_rad),
    % Obliquity of ecliptic (IAU 1980)
    Epsilon_deg = 23.439291 - 0.0130042 * T - 1.64e-7 * (T * T) + 5.04e-7 * (T * T * T),
    Epsilon_rad = deg_to_rad(Epsilon_deg),
    SinLambda = sin(Lambda_rad),
    CosLambda = cos(Lambda_rad),
    SinEpsilon = sin(Epsilon_rad),
    CosEpsilon = cos(Epsilon_rad),
    CosEcl = 1.0.

sun_vector_eci(JD) = vec3_normalize(sun_position_eci(JD)).

% Orbit Beta Angle: beta = asin(h_hat . s_hat)
orbit_beta_angle(Kep, JD) = Beta :-
    State = kepler_to_rv(Kep),
    H_vec = vec3_cross(State ^ os_pos, State ^ os_vel),
    H_hat = vec3_normalize(H_vec),
    S_hat = sun_vector_eci(JD),
    SinBeta = vec3_dot(H_hat, S_hat),
    ( if SinBeta > 1.0 then Beta = half_pi
      else if SinBeta < -1.0 then Beta = -half_pi
      else Beta = asin(SinBeta)
    ).

% Dual-cone Earth eclipse shadow model
satellite_eclipse_state(R_sat_eci, JD) = State :-
    S_hat = sun_vector_eci(JD),
    % Component of satellite position along Sun vector
    S_proj = vec3_dot(R_sat_eci, S_hat),
    ( if S_proj > 0.0 then
        % Satellite is on sunward side of Earth terminator plane
        State = full_sunlight
      else
        % Satellite is on nightside; calculate distance to Earth-Sun axis
        R_sat_sqr = vec3_norm_sqr(R_sat_eci),
        D_perp_sqr = R_sat_sqr - (S_proj * S_proj),
        ( if D_perp_sqr < 0.0 then D_perp = 0.0 else D_perp = sqrt(D_perp_sqr) ),
        Re = earth_radius_equatorial,
        Rs = solar_radius,
        Dist_sun = astronomical_unit,
        % Shadow cone geometry (projected onto negative Sun axis)
        X = abs(S_proj),
        % Umbra cone apex distance behind Earth
        Sin_alpha_u = (Rs - Re) / Dist_sun,
        Tan_alpha_u = Sin_alpha_u / sqrt(1.0 - Sin_alpha_u * Sin_alpha_u),
        R_umbra = Re - X * Tan_alpha_u,
        % Penumbra cone apex distance in front of Earth
        Sin_alpha_p = (Rs + Re) / Dist_sun,
        Tan_alpha_p = Sin_alpha_p / sqrt(1.0 - Sin_alpha_p * Sin_alpha_p),
        R_penumbra = Re + X * Tan_alpha_p,
        ( if (R_umbra > 0.0, D_perp =< R_umbra) then
            State = umbra
          else if D_perp >= R_penumbra then
            State = full_sunlight
          else
            % In penumbra zone: compute linear illumination fraction
            Frac = (D_perp - R_umbra) / (R_penumbra - R_umbra),
            State = penumbra(Frac)
        )
    ).

satellite_in_sunlight(R_sat_eci, JD) = InSun :-
    State = satellite_eclipse_state(R_sat_eci, JD),
    (
        State = full_sunlight,
        InSun = yes
    ;
        State = penumbra(F),
        ( if F > 0.1 then InSun = yes else InSun = no )
    ;
        State = umbra,
        InSun = no
    ).

satellite_illumination_fraction(R_sat_eci, JD) = Frac :-
    State = satellite_eclipse_state(R_sat_eci, JD),
    (
        State = full_sunlight,
        Frac = 1.0
    ;
        State = penumbra(F),
        Frac = F
    ;
        State = umbra,
        Frac = 0.0
    ).

% Calculate solar elevation angle at a target surface site on Earth
target_solar_elevation(SiteGeo, Epoch) = Elevation :-
    JD = datetime_to_jd(Epoch),
    S_eci = sun_vector_eci(JD),
    Gmst = datetime_to_gmst(Epoch),
    S_ecef = eci_to_ecef(S_eci, Gmst),
    % Create target site ECEF coordinate
    SiteEcef = geodetic_to_ecef(SiteGeo),
    % Calculate Topocentric solar vector
    % For an infinite distance source, range vector is parallel to S_ecef
    Lat = SiteGeo ^ geo_lat,
    Lon = SiteGeo ^ geo_lon,
    SinLat = sin(Lat),
    CosLat = cos(Lat),
    SinLon = sin(Lon),
    CosLon = cos(Lon),
    Sx = S_ecef ^ v_x,
    Sy = S_ecef ^ v_y,
    Sz = S_ecef ^ v_z,
    Up = CosLat * CosLon * Sx + CosLat * SinLon * Sy + SinLat * Sz,
    Elevation = asin(Up).

format_eclipse_state(full_sunlight) = "Full Sunlight (100% flux)".
format_eclipse_state(penumbra(Frac)) = Str :-
    string.format("Penumbra (%0.1f%% flux)", [f(Frac * 100.0)], Str).
format_eclipse_state(umbra) = "Umbra (Total Eclipse, 0% flux)".
