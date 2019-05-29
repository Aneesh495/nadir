#include "nadir_c_glue.h"
#include <math.h>
#include <time.h>

#define WGS84_A 6378137.0
#define WGS84_F (1.0 / 298.257223563)
#define WGS84_B (WGS84_A * (1.0 - WGS84_F))
#define WGS84_E2 (2.0 * WGS84_F - WGS84_F * WGS84_F)
#define WGS84_E_PRIME2 ((WGS84_A * WGS84_A - WGS84_B * WGS84_B) / (WGS84_B * WGS84_B))

double nadir_c_dot3(double x1, double y1, double z1,
                    double x2, double y2, double z2) {
    return (x1 * x2) + (y1 * y2) + (z1 * z2);
}

void nadir_c_cross3(double x1, double y1, double z1,
                    double x2, double y2, double z2,
                    double *rx, double *ry, double *rz) {
    if (rx) *rx = (y1 * z2) - (z1 * y2);
    if (ry) *ry = (z1 * x2) - (x1 * z2);
    if (rz) *rz = (x1 * y2) - (y1 * x2);
}

double nadir_c_norm3(double x, double y, double z) {
    return sqrt((x * x) + (y * y) + (z * z));
}

void nadir_c_mat3_mul_vec(const double m[9], const double v[3], double r[3]) {
    if (!m || !v || !r) return;
    r[0] = m[0] * v[0] + m[1] * v[1] + m[2] * v[2];
    r[1] = m[3] * v[0] + m[4] * v[1] + m[5] * v[2];
    r[2] = m[6] * v[0] + m[7] * v[1] + m[8] * v[2];
}

void nadir_c_bowring_geodetic(double x, double y, double z,
                             double *lat_rad, double *lon_rad, double *alt_m) {
    double p = sqrt(x * x + y * y);
    if (p < 1.0e-6) {
        if (lat_rad) *lat_rad = (z >= 0.0) ? (M_PI / 2.0) : (-M_PI / 2.0);
        if (lon_rad) *lon_rad = 0.0;
        if (alt_m)   *alt_m   = fabs(z) - WGS84_B;
        return;
    }

    double lon = atan2(y, x);
    double theta = atan2(z * WGS84_A, p * WGS84_B);
    double sin_th = sin(theta);
    double cos_th = cos(theta);

    double num = z + WGS84_E_PRIME2 * WGS84_B * sin_th * sin_th * sin_th;
    double den = p - WGS84_E2 * WGS84_A * cos_th * cos_th * cos_th;
    double lat = atan2(num, den);

    double sin_phi = sin(lat);
    double n = WGS84_A / sqrt(1.0 - WGS84_E2 * sin_phi * sin_phi);
    double alt = (p / cos(lat)) - n;

    if (lat_rad) *lat_rad = lat;
    if (lon_rad) *lon_rad = lon;
    if (alt_m)   *alt_m   = alt;
}

double nadir_c_monotime_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((double)ts.tv_sec * 1.0e9) + (double)ts.tv_nsec;
}
