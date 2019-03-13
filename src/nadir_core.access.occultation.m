:- module nadir_core.access.occultation.
:- interface.

:- import_module float, bool, string.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.vec3.

:- type line_of_sight_status
    --->    los_clear(los_clear_alt_m :: float)
    ;       los_occulted(los_occulted_alt_m :: float).

% Check line of sight between two satellite ECI positions
% Takes Sat1 position, Sat2 position, and atmospheric buffer height in meters (e.g. 40,000m)
:- func check_line_of_sight(vec3, vec3, float) = line_of_sight_status.

% Boolean query: is inter-satellite optical link available?
:- func is_link_available(vec3, vec3, float) = bool.

% Compute minimum ray tangent altitude above spherical Earth
:- func ray_tangent_altitude(vec3, vec3) = float.

% Formatting
:- func format_los_status(line_of_sight_status) = string.

:- implementation.

:- import_module math, list.
:- import_module nadir_core.astro.constants.

ray_tangent_altitude(R1, R2) = TangentAlt :-
    R1_mag = vec3_norm(R1),
    R2_mag = vec3_norm(R2),
    V_12 = vec3_sub(R2, R1),
    Dist_sq = vec3_norm_sqr(V_12),
    ( if Dist_sq < 1.0e-6 then
        TangentAlt = R1_mag - earth_radius_equatorial
      else
        % Projection parameter tau along line segment R(tau) = R1 + tau * (R2 - R1)
        Tau = -vec3_dot(R1, V_12) / Dist_sq,
        ( if Tau =< 0.0 then
            % Closest point is R1
            TangentAlt = R1_mag - earth_radius_equatorial
          else if Tau >= 1.0 then
            % Closest point is R2
            TangentAlt = R2_mag - earth_radius_equatorial
          else
            % Closest point is along the ray segment
            R_tangent = vec3_add(R1, vec3_scale(Tau, V_12)),
            TangentAlt = vec3_norm(R_tangent) - earth_radius_equatorial
        )
    ).

check_line_of_sight(R1, R2, BufferAlt_m) = Status :-
    TangentAlt = ray_tangent_altitude(R1, R2),
    ( if TangentAlt >= BufferAlt_m then
        Status = los_clear(TangentAlt)
      else
        Status = los_occulted(TangentAlt)
    ).

is_link_available(R1, R2, BufferAlt_m) = Available :-
    Status = check_line_of_sight(R1, R2, BufferAlt_m),
    (
        Status = los_clear(_),
        Available = yes
    ;
        Status = los_occulted(_),
        Available = no
    ).

format_los_status(los_clear(Alt)) = Str :-
    string.format("Clear Line-of-Sight (Tangent Altitude: %0.1f km)", [f(Alt / 1000.0)], Str).
format_los_status(los_occulted(Alt)) = Str :-
    string.format("Occulted by Earth/Atmosphere (Tangent Altitude: %0.1f km)", [f(Alt / 1000.0)], Str).
