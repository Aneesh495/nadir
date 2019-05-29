#ifndef NADIR_C_GLUE_H
#define NADIR_C_GLUE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * NADIR Astrodynamics Core C Acceleration Interface
 * High-performance C99 primitives for orbital mechanics and vector math.
 */

/* 3D Vector inner dot product */
double nadir_c_dot3(double x1, double y1, double z1,
                    double x2, double y2, double z2);

/* 3D Vector cross product: r = v1 x v2 */
void nadir_c_cross3(double x1, double y1, double z1,
                    double x2, double y2, double z2,
                    double *rx, double *ry, double *rz);

/* 3D Vector Euclidean 2-norm */
double nadir_c_norm3(double x, double y, double z);

/* 3x3 Matrix times 3D vector */
void nadir_c_mat3_mul_vec(const double m[9], const double v[3], double r[3]);

/* Closed-form Bowring algorithm: ECEF (x,y,z in meters) to Geodetic (lat rad, lon rad, alt m) */
void nadir_c_bowring_geodetic(double x, double y, double z,
                             double *lat_rad, double *lon_rad, double *alt_m);

/* High-resolution monotonic timestamp in nanoseconds */
double nadir_c_monotime_ns(void);

#ifdef __cplusplus
}
#endif

#endif /* NADIR_C_GLUE_H */
