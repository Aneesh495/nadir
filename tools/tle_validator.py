#!/usr/bin/env python3
"""
Comprehensive NORAD Two-Line Element (TLE) Validator.
Validates structural format, modulo 10 checksums, and astrodynamic parameter ranges.
"""

import argparse
import sys
from pathlib import Path


def calculate_checksum(line: str) -> int:
    """Calculates expected modulo 10 checksum for a TLE line."""
    total = 0
    for char in line[:68]:
        if char.isdigit():
            total += int(char)
        elif char == "-":
            total += 1
    return total % 10


def validate_tle_file(filepath: Path) -> tuple[int, list[str]]:
    """Validates an entire TLE file and returns satellite count and error list."""
    errors = []
    sat_count = 0

    if not filepath.exists():
        return 0, [f"File not found: {filepath}"]

    with open(filepath, "r", encoding="utf-8") as f:
        raw_lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]

    idx = 0
    while idx < len(raw_lines):
        line = raw_lines[idx]
        if line.startswith("1 "):
            line1 = line
            if idx + 1 >= len(raw_lines):
                errors.append(f"Line 1 at index {idx} has no matching Line 2")
                break
            line2 = raw_lines[idx + 1]
            idx += 2
        elif line.startswith("2 "):
            errors.append(f"Unexpected Line 2 without preceding Line 1 at index {idx}")
            idx += 1
            continue
        else:
            # Satellite name header in 3-line format
            idx += 1
            if idx < len(raw_lines) and raw_lines[idx].startswith("1 "):
                line1 = raw_lines[idx]
                idx += 1
                if idx < len(raw_lines) and raw_lines[idx].startswith("2 "):
                    line2 = raw_lines[idx]
                    idx += 1
                else:
                    errors.append(f"Missing Line 2 after Line 1 at index {idx}")
                    continue
            else:
                errors.append(f"Unrecognized header without Line 1 at index {idx - 1}")
                continue

        # Validate line lengths
        if len(line1) != 69:
            errors.append(f"Line 1 length is {len(line1)}, expected 69: '{line1}'")
        if len(line2) != 69:
            errors.append(f"Line 2 length is {len(line2)}, expected 69: '{line2}'")

        # Validate checksums
        c1_actual = int(line1[-1]) if line1[-1].isdigit() else -1
        c1_exp = calculate_checksum(line1)
        if c1_actual != c1_exp:
            errors.append(f"Line 1 checksum mismatch: actual {c1_actual}, expected {c1_exp}")

        c2_actual = int(line2[-1]) if line2[-1].isdigit() else -1
        c2_exp = calculate_checksum(line2)
        if c2_actual != c2_exp:
            errors.append(f"Line 2 checksum mismatch: actual {c2_actual}, expected {c2_exp}")

        # Validate physical parameter ranges
        try:
            inc = float(line2[8:16])
            raan = float(line2[17:25])
            ecc = float("0." + line2[26:33])
            argp = float(line2[34:42])
            ma = float(line2[43:51])
            mm = float(line2[52:63])

            if not (0.0 <= inc <= 180.0):
                errors.append(f"Inclination {inc} out of range [0, 180]")
            if not (0.0 <= raan <= 360.0):
                errors.append(f"RAAN {raan} out of range [0, 360]")
            if not (0.0 <= ecc < 1.0):
                errors.append(f"Eccentricity {ecc} out of elliptical range [0, 1)")
            if not (0.0 <= argp <= 360.0):
                errors.append(f"Arg of perigee {argp} out of range [0, 360]")
            if not (0.0 <= ma <= 360.0):
                errors.append(f"Mean anomaly {ma} out of range [0, 360]")
            if not (0.0 < mm <= 20.0):
                errors.append(f"Mean motion {mm} rev/day out of bounds")

            sat_count += 1
        except Exception as e:
            errors.append(f"Failed to parse numerical fields: {e}")

    return sat_count, errors


def main():
    parser = argparse.ArgumentParser(description="Validate NORAD TLE files.")
    parser.add_argument("tle_file", type=str, help="Path to TLE file")
    args = parser.parse_args()

    filepath = Path(args.tle_file)
    sat_count, errors = validate_tle_file(filepath)

    if errors:
        print(f"Validation FAILED with {len(errors)} error(s):")
        for err in errors:
            print(f"  [ERROR] {err}")
        sys.exit(1)
    else:
        print(f"Validation PASSED: {sat_count} satellites verified with 100% valid checksums.")


if __name__ == "__main__":
    main()
