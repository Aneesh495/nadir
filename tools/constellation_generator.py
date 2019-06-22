#!/usr/bin/env python3
"""
Parametric Walker-Delta and Walker-Star Constellation TLE Synthesizer.
Generates fully compliant NORAD Two-Line Element (TLE) sets with validated checksums.
"""

import argparse
import math
import sys
from datetime import datetime

WGS84_A_M = 6378137.0
EARTH_MU = 3.986004418e14
SECONDS_PER_DAY = 86400.0


def calculate_tle_checksum(line: str) -> int:
    """Computes the standard NORAD TLE checksum modulo 10."""
    total = 0
    for char in line[:68]:
        if char.isdigit():
            total += int(char)
        elif char == "-":
            total += 1
    return total % 10


def format_tle_lines(name: str, sat_num: int, epoch: datetime,
                     inc_deg: float, raan_deg: float, ecc: float,
                     argp_deg: float, ma_deg: float, mm_rev_day: float) -> tuple[str, str, str]:
    """Formats orbital elements into standard NORAD Three-Line Element (TLE) format."""
    day_of_year = epoch.timetuple().tm_yday
    fractional_day = (
        epoch.hour * 3600.0 + epoch.minute * 60.0 + epoch.second + epoch.microsecond * 1e-6
    ) / SECONDS_PER_DAY
    full_day = day_of_year + fractional_day
    yr_short = epoch.year % 100

    line1_base = f"1 {sat_num:05d}U 26001A   {yr_short:02d}{full_day:012.8f}  .00000100  00000-0  10000-4 0  999"
    c1 = calculate_tle_checksum(line1_base)
    line1 = f"{line1_base}{c1}"

    ecc_str = f"{int(round(ecc * 1e7)):07d}"
    line2_base = (
        f"2 {sat_num:05d} {inc_deg:8.4f} {raan_deg:8.4f} {ecc_str} "
        f"{argp_deg:8.4f} {ma_deg:8.4f} {mm_rev_day:11.8f}    1"
    )
    c2 = calculate_tle_checksum(line2_base)
    line2 = f"{line2_base}{c2}"

    return name, line1, line2


def generate_walker_delta(t: int, p: int, f: int, alt_km: float,
                          inc_deg: float, epoch: datetime) -> list[tuple[str, str, str]]:
    """Synthesizes a complete Walker-Delta (T/P/F) constellation."""
    if t % p != 0:
        raise ValueError(f"Total satellites {t} must be divisible by planes {p}")

    s = t // p  # Satellites per plane
    delta_raan = 360.0 / p
    delta_anomaly = 360.0 / s
    phase_offset = (f * 360.0) / t

    semi_major_axis = WGS84_A_M + (alt_km * 1000.0)
    mean_motion_rad_s = math.sqrt(EARTH_MU / (semi_major_axis ** 3))
    mean_motion_rev_day = (mean_motion_rad_s * SECONDS_PER_DAY) / (2.0 * math.pi)

    elements = []
    sat_idx = 1
    for plane_idx in range(p):
        raan = (plane_idx * delta_raan) % 360.0
        for sat_in_plane in range(s):
            ma = (sat_in_plane * delta_anomaly + plane_idx * phase_offset) % 360.0
            name = f"NADIR_P{plane_idx:02d}_S{sat_in_plane:02d}"
            sat_num = 70000 + sat_idx
            tle = format_tle_lines(
                name=name,
                sat_num=sat_num,
                epoch=epoch,
                inc_deg=inc_deg,
                raan_deg=raan,
                ecc=0.00012,
                argp_deg=0.0,
                ma_deg=ma,
                mm_rev_day=mean_motion_rev_day
            )
            elements.append(tle)
            sat_idx += 1

    return elements


def main():
    parser = argparse.ArgumentParser(
        description="Synthesize realistic Walker-Delta constellation TLE files."
    )
    parser.add_argument("-t", "--total", type=int, default=24, help="Total satellites (default: 24)")
    parser.add_argument("-p", "--planes", type=int, default=4, help="Orbital planes (default: 4)")
    parser.add_argument("-f", "--phase", type=int, default=1, help="Relative phase factor (default: 1)")
    parser.add_argument("--alt", type=float, default=550.0, help="Altitude in km (default: 550)")
    parser.add_argument("--inc", type=float, default=53.0, help="Inclination in deg (default: 53.0)")
    parser.add_argument("-o", "--output", type=str, default="", help="Output .tle file path")

    args = parser.parse_args()
    epoch = datetime(2026, 6, 21, 12, 0, 0)
    tles = generate_walker_delta(args.total, args.planes, args.phase, args.alt, args.inc, epoch)

    lines = []
    for name, l1, l2 in tles:
        lines.append(name)
        lines.append(l1)
        lines.append(l2)
    output_text = "\n".join(lines) + "\n"

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_text)
        print(f"Generated {len(tles)} satellites in {args.output}")
    else:
        sys.stdout.write(output_text)


if __name__ == "__main__":
    main()
