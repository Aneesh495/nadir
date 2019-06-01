:- module nadir_core.c_fastpath.
:- interface.

:- import_module float.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.vec3.
:- import_module nadir_core.astro.coords.

% High-performance vector dot product
:- func fast_dot3(float, float, float, float, float, float) = float.

% High-performance vector cross product
:- func fast_cross3(vec3, vec3) = vec3.

% High-performance Euclidean vector norm
:- func fast_norm3(float, float, float) = float.

% Hardware-accelerated Bowring geodetic algorithm
:- func fast_bowring_geodetic(vec3) = geodetic.

% POSIX monotonic clock in nanoseconds
:- func fast_monotime_ns = float.

:- implementation.

:- pragma foreign_decl("C", "
#include <math.h>
#include <time.h>

#define C_WGS84_A 6378137.0
#define C_WGS84_F (1.0 / 298.257223563)
#define C_WGS84_B (C_WGS84_A * (1.0 - C_WGS84_F))
#define C_WGS84_E2 (2.0 * C_WGS84_F - C_WGS84_F * C_WGS84_F)
#define C_WGS84_E_PRIME2 ((C_WGS84_A * C_WGS84_A - C_WGS84_B * C_WGS84_B) / (C_WGS84_B * C_WGS84_B))
").

:- pragma foreign_proc("C",
    fast_dot3(X1::in, Y1::in, Z1::in, X2::in, Y2::in, Z2::in) = (Dot::out),
    [will_not_call_mercury, promise_pure],
"
    Dot = (X1 * X2) + (Y1 * Y2) + (Z1 * Z2);
").

:- pragma foreign_proc("C",
    fast_norm3(X::in, Y::in, Z::in) = (Norm::out),
    [will_not_call_mercury, promise_pure],
"
    Norm = sqrt((X * X) + (Y * Y) + (Z * Z));
").

:- pred fast_c_cross(float::in, float::in, float::in,
                     float::in, float::in, float::in,
                     float::out, float::out, float::out) is det.
:- pragma foreign_proc("C",
    fast_c_cross(X1::in, Y1::in, Z1::in,
                 X2::in, Y2::in, Z2::in,
                 Rx::out, Ry::out, Rz::out),
    [will_not_call_mercury, promise_pure],
"
    Rx = (Y1 * Z2) - (Z1 * Y2);
    Ry = (Z1 * X2) - (X1 * Z2);
    Rz = (X1 * Y2) - (Y1 * X2);
").

fast_cross3(vec3(X1, Y1, Z1), vec3(X2, Y2, Z2)) = vec3(Rx, Ry, Rz) :-
    fast_c_cross(X1, Y1, Z1, X2, Y2, Z2, Rx, Ry, Rz).

:- pred fast_c_bowring(float::in, float::in, float::in,
                       float::out, float::out, float::out) is det.
:- pragma foreign_proc("C",
    fast_c_bowring(X::in, Y::in, Z::in,
                   Lat::out, Lon::out, Alt::out),
    [will_not_call_mercury, promise_pure],
"
    double p = sqrt(X * X + Y * Y);
    if (p < 1.0e-6) {
        Lat = (Z >= 0.0) ? (M_PI / 2.0) : (-M_PI / 2.0);
        Lon = 0.0;
        Alt = fabs(Z) - C_WGS84_B;
    } else {
        Lon = atan2(Y, X);
        double theta = atan2(Z * C_WGS84_A, p * C_WGS84_B);
        double sin_th = sin(theta);
        double cos_th = cos(theta);
        double num = Z + C_WGS84_E_PRIME2 * C_WGS84_B * sin_th * sin_th * sin_th;
        double den = p - C_WGS84_E2 * C_WGS84_A * cos_th * cos_th * cos_th;
        Lat = atan2(num, den);
        double sin_phi = sin(Lat);
        double n = C_WGS84_A / sqrt(1.0 - C_WGS84_E2 * sin_phi * sin_phi);
        Alt = (p / cos(Lat)) - n;
    }
").

fast_bowring_geodetic(vec3(X, Y, Z)) = geodetic(Lat, Lon, Alt) :-
    fast_c_bowring(X, Y, Z, Lat, Lon, Alt).

:- pragma foreign_proc("C",
    fast_monotime_ns = (Nanos::out),
    [will_not_call_mercury, promise_pure],
"
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    Nanos = ((double)ts.tv_sec * 1.0e9) + (double)ts.tv_nsec;
").
