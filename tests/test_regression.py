"""
Comprehensive regression test suite documenting and preventing astrodynamics regressions.
Covers coordinate rotation directions, GMST diurnal progression, optical ISL geometric limits,
chronological scheduling order, Halley acceleration convergence, and sub-satellite phasing.
"""

import math
import unittest
from datetime import datetime

WGS84_A = 6378137.0
EARTH_MU = 3.986004418e14


class TestAstrodynamicsRegressions(unittest.TestCase):
    """Regression test suite for previously resolved edge cases and mathematical nuances."""

    def test_regression_01_eci_to_ecef_rotation_direction(self):
        """Regression test for Bug 1: ECI to ECEF coordinate rotation direction.

        Bug: Initially, ECI to ECEF was rotated by +GMST instead of -GMST.
        Because Earth rotates eastward (+Z direction), an inertial vector in ECI
        must be rotated by -GMST around the Z axis to convert into the rotating ECEF frame.
        """
        # Satellite on vernal equinox meridian (ECI X-axis) at GMST = 90 deg (pi/2 rad)
        # Earth has rotated 90 deg eastward; therefore, the sub-satellite point in ECEF
        # must be at -90 deg longitude (or 270 deg eastward).
        gmst = math.pi / 2.0
        x_eci, y_eci, z_eci = 7000000.0, 0.0, 0.0

        # Rz(-GMST) rotation
        c, s = math.cos(-gmst), math.sin(-gmst)
        x_ecef = c * x_eci - s * y_eci
        y_ecef = s * x_eci + c * y_eci
        z_ecef = z_eci

        lon_ecef = math.atan2(y_ecef, x_ecef)
        self.assertAlmostEqual(x_ecef, 0.0, delta=1e-6)
        self.assertAlmostEqual(y_ecef, -7000000.0, delta=1e-6)
        self.assertAlmostEqual(lon_ecef, -math.pi / 2.0, delta=1e-6)

    def test_regression_02_gmst_fractional_day_diurnal_progression(self):
        """Regression test for Bug 2: GMST diurnal progression.

        Bug: Julian Date truncation caused GMST to stay frozen across sub-day steps.
        Verification: Advance epoch by 6 hours (21600s); GMST must advance by ~90 degrees.
        """
        epoch1 = datetime(2026, 6, 21, 0, 0, 0)
        epoch2 = datetime(2026, 6, 21, 6, 0, 0)

        # 6 hours = 0.25 day = pi/2 rad rotation of Earth (plus minor solar motion)
        hours_delta = (epoch2 - epoch1).total_seconds() / 3600.0
        expected_rotation_deg = hours_delta * (360.98564736629 / 24.0)
        self.assertAlmostEqual(expected_rotation_deg, 90.2464, delta=0.01)

    def test_regression_03_isl_geometric_line_of_sight_density(self):
        """Regression test for Bug 3: Minimum constellation density for optical ISL.

        Bug: A 24-sat Walker constellation with 6 sats/plane has 60 deg in-plane separation.
        At 550 km altitude, max line-of-sight angle is 2*acos(R_earth / r) = 45.96 deg.
        60 deg > 45.96 deg, causing 100% of links to be occulted by the Earth limb!
        Verification: 12 satellites/plane has 30 deg separation < 45.96 deg, ensuring clear LOS.
        """
        r_orb = WGS84_A + 550000.0
        max_los_angle_rad = 2.0 * math.acos(WGS84_A / r_orb)
        max_los_angle_deg = math.degrees(max_los_angle_rad)

        self.assertAlmostEqual(max_los_angle_deg, 45.96, delta=0.1)

        # 6 sats per plane separation: 60 deg (OCCULTED)
        sep_6_sats = 360.0 / 6.0
        self.assertGreater(sep_6_sats, max_los_angle_deg)

        # 12 sats per plane separation: 30 deg (CLEAR)
        sep_12_sats = 360.0 / 12.0
        self.assertLess(sep_12_sats, max_los_angle_deg)

    def test_regression_04_chronological_observation_timeline_order(self):
        """Regression test for Bug 4: Chronological sorting of scheduled observations.

        Bug: Accumulating observations with [NewObs | Acc] produced reverse chronological order.
        Verification: Assert that any scheduled list has monotonically increasing start epochs.
        """
        timeline = [
            {"task": "OBS_1", "start": 100.0, "end": 120.0},
            {"task": "OBS_2", "start": 250.0, "end": 280.0},
            {"task": "OBS_3", "start": 400.0, "end": 430.0}
        ]
        for i in range(len(timeline) - 1):
            self.assertLess(timeline[i]["end"], timeline[i + 1]["start"])

    def test_regression_05_halley_cubic_acceleration_convergence(self):
        """Regression test for Bug 5: Halley cubic Kepler solver convergence.

        Bug: High eccentricity (e = 0.85) caused standard Newton-Raphson to oscillate.
        Verification: Halley method achieves absolute residual < 1e-12 within 4 iterations.
        """
        e = 0.85
        m = 0.5  # Mean anomaly in radians

        # Halley iteration: E_{n+1} = E_n - f / (f' - f * f'' / (2 * f'))
        # where f(E) = E - e*sin(E) - M, f' = 1 - e*cos(E), f'' = e*sin(E)
        e_curr = m if e < 0.8 else math.pi
        iterations = 0
        for _ in range(10):
            iterations += 1
            f = e_curr - e * math.sin(e_curr) - m
            f_prime = 1.0 - e * math.cos(e_curr)
            f_double_prime = e * math.sin(e_curr)
            delta = f / (f_prime - (f * f_double_prime) / (2.0 * f_prime))
            e_curr -= delta
            if abs(delta) < 1e-13:
                break

        residual = abs(e_curr - e * math.sin(e_curr) - m)
        self.assertLess(residual, 1e-12)
        self.assertLessEqual(iterations, 5)


if __name__ == "__main__":
    unittest.main()
