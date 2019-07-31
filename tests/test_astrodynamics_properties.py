"""Property-based invariant testing suite for nadir astrodynamics algorithms.

Verifies mathematical invariants, conservation laws, coordinate round-trips,
and symmetry properties under randomized inputs.
"""

import math
import random
import unittest

EARTH_RADIUS_EQUATORIAL_M = 6378137.0
EARTH_RADIUS_POLAR_M = 6356752.314245
EARTH_MU_M3_S2 = 3.986004418e14
WGS84_F = 1.0 / 298.257223563
WGS84_E2 = WGS84_F * (2.0 - WGS84_F)


def vec3_norm(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def vec3_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vec3_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vec3_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vec3_scale(v, s):
    return (v[0] * s, v[1] * s, v[2] * s)


def quat_norm(q):
    return math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])


def quat_slerp(q1, q2, t):
    dot = q1[0] * q2[0] + q1[1] * q2[1] + q1[2] * q2[2] + q1[3] * q2[3]
    if dot < 0.0:
        q2 = (-q2[0], -q2[1], -q2[2], -q2[3])
        dot = -dot
    if dot > 0.9995:
        # Linear interpolation fallback for near-identical quaternions
        raw = (
            q1[0] + t * (q2[0] - q1[0]),
            q1[1] + t * (q2[1] - q1[1]),
            q1[2] + t * (q2[2] - q1[2]),
            q1[3] + t * (q2[3] - q1[3]),
        )
        n = quat_norm(raw)
        return (raw[0] / n, raw[1] / n, raw[2] / n, raw[3] / n)
    theta_0 = math.acos(dot)
    sin_theta_0 = math.sin(theta_0)
    theta = theta_0 * t
    s0 = math.cos(theta) - dot * math.sin(theta) / sin_theta_0
    s1 = math.sin(theta) / sin_theta_0
    return (
        s0 * q1[0] + s1 * q2[0],
        s0 * q1[1] + s1 * q2[1],
        s0 * q1[2] + s1 * q2[2],
        s0 * q1[3] + s1 * q2[3],
    )


def geodetic_to_ecef(lat_rad, lon_rad, alt_m):
    sin_lat = math.sin(lat_rad)
    cos_lat = math.cos(lat_rad)
    n = EARTH_RADIUS_EQUATORIAL_M / math.sqrt(1.0 - WGS84_E2 * sin_lat * sin_lat)
    x = (n + alt_m) * cos_lat * math.cos(lon_rad)
    y = (n + alt_m) * cos_lat * math.sin(lon_rad)
    z = (n * (1.0 - WGS84_E2) + alt_m) * sin_lat
    return (x, y, z)


def ecef_to_geodetic(x, y, z):
    # Bowring closed form
    p = math.sqrt(x * x + y * y)
    lon_rad = math.atan2(y, x)
    if p < 1e-6:
        lat_rad = math.pi / 2.0 if z >= 0.0 else -math.pi / 2.0
        alt_m = abs(z) - EARTH_RADIUS_POLAR_M
        return (lat_rad, lon_rad, alt_m)
    b = EARTH_RADIUS_EQUATORIAL_M * (1.0 - WGS84_F)
    e_prime2 = (EARTH_RADIUS_EQUATORIAL_M**2 - b**2) / (b**2)
    theta = math.atan2(z * EARTH_RADIUS_EQUATORIAL_M, p * b)
    sin_t = math.sin(theta)
    cos_t = math.cos(theta)
    lat_rad = math.atan2(
        z + e_prime2 * b * (sin_t**3),
        p - WGS84_E2 * EARTH_RADIUS_EQUATORIAL_M * (cos_t**3),
    )
    sin_lat = math.sin(lat_rad)
    n = EARTH_RADIUS_EQUATORIAL_M / math.sqrt(1.0 - WGS84_E2 * sin_lat * sin_lat)
    alt_m = p / math.cos(lat_rad) - n
    return (lat_rad, lon_rad, alt_m)


def eci_to_ecef(r_eci, gmst_rad):
    cos_g = math.cos(gmst_rad)
    sin_g = math.sin(gmst_rad)
    return (
        cos_g * r_eci[0] + sin_g * r_eci[1],
        -sin_g * r_eci[0] + cos_g * r_eci[1],
        r_eci[2],
    )


def ecef_to_eci(r_ecef, gmst_rad):
    cos_g = math.cos(gmst_rad)
    sin_g = math.sin(gmst_rad)
    return (
        cos_g * r_ecef[0] - sin_g * r_ecef[1],
        sin_g * r_ecef[0] + cos_g * r_ecef[1],
        r_ecef[2],
    )


def line_of_sight_tangent_altitude(r1, r2):
    # Ray from r1 to r2: r(t) = r1 + t * (r2 - r1), t in [0, 1]
    d = vec3_sub(r2, r1)
    d_sq = vec3_dot(d, d)
    if d_sq < 1e-12:
        return vec3_norm(r1) - EARTH_RADIUS_EQUATORIAL_M
    t_min = -vec3_dot(r1, d) / d_sq
    if t_min <= 0.0:
        closest = r1
    elif t_min >= 1.0:
        closest = r2
    else:
        closest = vec3_add(r1, vec3_scale(d, t_min))
    return vec3_norm(closest) - EARTH_RADIUS_EQUATORIAL_M


class TestAstrodynamicsProperties(unittest.TestCase):
    """Property-based verification test suite."""

    def setUp(self):
        random.seed(42)

    def test_quaternion_slerp_invariants(self):
        """Quaternion SLERP preserves unit norm and satisfies endpoint conditions."""
        for _ in range(50):
            # Generate random unit quaternions
            q1_raw = tuple(random.uniform(-1.0, 1.0) for _ in range(4))
            n1 = quat_norm(q1_raw)
            q1 = tuple(x / n1 for x in q1_raw)

            q2_raw = tuple(random.uniform(-1.0, 1.0) for _ in range(4))
            n2 = quat_norm(q2_raw)
            q2 = tuple(x / n2 for x in q2_raw)

            # Test endpoints t=0 and t=1
            q_start = quat_slerp(q1, q2, 0.0)
            self.assertAlmostEqual(quat_norm(q_start), 1.0, places=9)
            # Dot product with q1 should be +1 or -1 (antipodal representation)
            dot_start = abs(vec3_dot(q_start[:3], q1[:3]) + q_start[3] * q1[3])
            self.assertAlmostEqual(dot_start, 1.0, places=6)

            q_end = quat_slerp(q1, q2, 1.0)
            self.assertAlmostEqual(quat_norm(q_end), 1.0, places=9)
            dot_end = abs(vec3_dot(q_end[:3], q2[:3]) + q_end[3] * q2[3])
            self.assertAlmostEqual(dot_end, 1.0, places=6)

            # Intermediate parameter t in (0, 1)
            t = random.uniform(0.01, 0.99)
            q_mid = quat_slerp(q1, q2, t)
            self.assertAlmostEqual(quat_norm(q_mid), 1.0, places=9)

    def test_eci_ecef_roundtrip_isometry(self):
        """ECI to ECEF rotation preserves vector norms and recovers original vector."""
        for _ in range(50):
            # Arbitrary satellite vector in orbit range [6500 km, 45000 km]
            r_mag = random.uniform(6.5e6, 4.5e7)
            theta = random.uniform(0.0, 2.0 * math.pi)
            phi = random.uniform(-math.pi / 2.0, math.pi / 2.0)
            r_eci = (
                r_mag * math.cos(phi) * math.cos(theta),
                r_mag * math.cos(phi) * math.sin(theta),
                r_mag * math.sin(phi),
            )
            gmst = random.uniform(0.0, 2.0 * math.pi)

            r_ecef = eci_to_ecef(r_eci, gmst)
            r_eci_recovered = ecef_to_eci(r_ecef, gmst)

            # Norm preservation (isometry)
            self.assertAlmostEqual(vec3_norm(r_eci), vec3_norm(r_ecef), places=7)

            # Exact vector reconstruction to sub-millimeter precision
            diff = vec3_norm(vec3_sub(r_eci, r_eci_recovered))
            self.assertLess(diff, 1e-8)

    def test_geodetic_ecef_roundtrip(self):
        """WGS-84 geodetic to ECEF and Bowring inversion round-trip invariance."""
        for _ in range(50):
            lat = random.uniform(-math.pi * 0.49, math.pi * 0.49)
            lon = random.uniform(-math.pi, math.pi)
            alt = random.uniform(-500.0, 1.5e6)  # Deep mine to LEO altitude

            x, y, z = geodetic_to_ecef(lat, lon, alt)
            lat_rec, lon_rec, alt_rec = ecef_to_geodetic(x, y, z)

            self.assertAlmostEqual(lat, lat_rec, places=7)
            self.assertAlmostEqual(lon, lon_rec, places=7)
            # Bowring single-step formula achieves centimeter accuracy across all LEO altitudes
            self.assertLess(abs(alt - alt_rec), 0.05)

    def test_vis_viva_specific_energy_conservation(self):
        """Vis-viva equation: Specific orbital energy is constant along Keplerian orbit."""
        for _ in range(30):
            a = random.uniform(6.8e6, 2.0e7)  # Semi-major axis (meters)
            e = random.uniform(0.001, 0.75)   # Eccentricity
            expected_energy = -EARTH_MU_M3_S2 / (2.0 * a)

            # Evaluate at 10 true anomalies around the orbit
            for i in range(10):
                nu = (2.0 * math.pi * i) / 10.0
                r = a * (1.0 - e * e) / (1.0 + e * math.cos(nu))
                # Vis-viva formula: v^2 = mu * (2/r - 1/a)
                v_sq = EARTH_MU_M3_S2 * (2.0 / r - 1.0 / a)
                v = math.sqrt(v_sq)
                specific_energy = (v * v) / 2.0 - EARTH_MU_M3_S2 / r
                self.assertAlmostEqual(specific_energy, expected_energy, places=3)

    def test_line_of_sight_symmetry(self):
        """Line-of-sight tangent altitude is symmetric between transmitter and receiver."""
        for _ in range(40):
            r1 = (
                random.uniform(-1e7, 1e7),
                random.uniform(-1e7, 1e7),
                random.uniform(-1e7, 1e7),
            )
            r2 = (
                random.uniform(-1e7, 1e7),
                random.uniform(-1e7, 1e7),
                random.uniform(-1e7, 1e7),
            )
            alt_forward = line_of_sight_tangent_altitude(r1, r2)
            alt_reverse = line_of_sight_tangent_altitude(r2, r1)
            self.assertAlmostEqual(alt_forward, alt_reverse, places=6)


if __name__ == "__main__":
    unittest.main()
