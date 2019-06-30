#!/usr/bin/env python3
"""
Terminal Curses Constellation Operations Live Dashboard for NADIR.
Renders real-time telemetry, orbital sub-satellite positions, battery health, and event logs.
"""

import curses
import math
import time
from datetime import datetime, timezone

EARTH_RADIUS_KM = 6378.137


class MockSatellite:
    """Simulates a constellation node with live evolving orbital telemetry."""

    def __init__(self, sat_id: str, plane: int, index: int, alt_km: float = 550.0, inc_deg: float = 53.0):
        self.sat_id = sat_id
        self.plane = plane
        self.index = index
        self.alt_km = alt_km
        self.inc_deg = inc_deg
        self.speed_kms = math.sqrt(398600.4418 / (EARTH_RADIUS_KM + alt_km))
        self.battery_soc = 98.5
        self.storage_gb = 14.2
        self.is_sunlit = True
        self.active_task = "STANDBY"

    def update(self, sim_sec: float):
        """Advances orbital state and updates subsystem metrics."""
        period_sec = 5700.0
        phase = (sim_sec / period_sec) * 2.0 * math.pi + (self.plane * 1.57) + (self.index * 0.78)
        self.lat = math.sin(phase) * self.inc_deg
        self.lon = ((phase * 180.0 / math.pi) * 0.8) % 360.0 - 180.0

        # Eclipse cycle (40% of orbit in shadow)
        orbit_frac = (phase / (2.0 * math.pi)) % 1.0
        self.is_sunlit = not (0.35 <= orbit_frac <= 0.65)

        if self.is_sunlit:
            self.battery_soc = min(100.0, self.battery_soc + 0.05)
        else:
            self.battery_soc = max(40.0, self.battery_soc - 0.08)

        # Storage dynamics
        if self.active_task != "STANDBY":
            self.storage_gb = min(500.0, self.storage_gb + 0.2)


def render_dashboard(stdscr):
    """Curses event loop rendering the constellation telemetry dashboard."""
    curses.curs_set(0)
    stdscr.nodelay(True)
    stdscr.timeout(100)

    # Initialize sample constellation fleet
    sats = [
        MockSatellite(f"SAT_P00_S{i:02d}", 0, i) for i in range(4)
    ] + [
        MockSatellite(f"SAT_P01_S{i:02d}", 1, i) for i in range(4)
    ]

    events = [
        "12:00:00 [SYSTEM] NADIR Mission Control initialized 8 satellites across 2 orbital planes",
        "12:00:15 [ISL_MESH] Laser crosslinks established on 1064nm optical transceivers",
        "12:00:30 [SCHEDULER] Feasibility verification completed: 100% constraints satisfied",
        "12:00:45 [GROUND_NET] Svalbard Station tracking pass scheduled for SAT_P00_S00 (AOS 12:08)"
    ]

    sim_time_sec = 0.0
    multiplier = 10.0
    is_paused = False

    while True:
        key = stdscr.getch()
        if key == ord('q') or key == ord('Q'):
            break
        elif key == ord(' '):
            is_paused = not is_paused
        elif key == ord('+') or key == ord('='):
            multiplier = min(100.0, multiplier + 5.0)
        elif key == ord('-') or key == ord('_'):
            multiplier = max(1.0, multiplier - 5.0)

        if not is_paused:
            sim_time_sec += 0.1 * multiplier
            for sat in sats:
                sat.update(sim_time_sec)

        stdscr.erase()
        max_y, max_x = stdscr.getmaxyx()

        if max_y < 22 or max_x < 78:
            stdscr.addstr(0, 0, "Terminal window too small for NADIR dashboard. Please expand.")
            stdscr.refresh()
            time.sleep(0.1)
            continue

        # Header
        utc_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        header = f" NADIR CONSTELLATION OPERATIONS | {utc_str} | Sim Time: +{sim_time_sec:0.1f}s (x{multiplier:0.0f}) "
        stdscr.addstr(0, 0, "=" * (max_x - 1), curses.A_DIM)
        stdscr.addstr(1, max(0, (max_x - len(header)) // 2), header, curses.A_BOLD)
        stdscr.addstr(2, 0, "=" * (max_x - 1), curses.A_DIM)

        # Telemetry Table Header
        col_header = " SAT_ID        LAT      LON      ALT(km)   V(km/s)   SUN     BATT(%)   SSR(Gb) "
        stdscr.addstr(4, 2, col_header, curses.A_REVERSE)

        # Satellite Rows
        for idx, sat in enumerate(sats):
            sun_str = "SUNLIGHT" if sat.is_sunlit else "ECLIPSE "
            row = (
                f" {sat.sat_id:<12} {sat.lat:+6.1f}   {sat.lon:+7.1f}   "
                f"{sat.alt_km:6.1f}    {sat.speed_kms:4.2f}    {sun_str} "
                f"{sat.battery_soc:5.1f}%   {sat.storage_gb:5.1f}   "
            )
            stdscr.addstr(5 + idx, 2, row)

        # Ground Network & ISL Status
        net_y = 5 + len(sats) + 1
        stdscr.addstr(net_y, 0, "-" * (max_x - 1), curses.A_DIM)
        net_info = " GROUND NETWORK: Svalbard [ACTIVE] | Inuvik [IDLE] | Punta Arenas [IDLE] | Singapore [IDLE] "
        stdscr.addstr(net_y + 1, 2, net_info, curses.A_BOLD)
        isl_info = f" OPTICAL ISL MESH: Active Laser Links: 16 | CGR Latency: 24.1 ms | Routing Hops: 2 "
        stdscr.addstr(net_y + 2, 2, isl_info)

        # Event Log
        log_y = net_y + 4
        stdscr.addstr(log_y, 0, "-" * (max_x - 1), curses.A_DIM)
        stdscr.addstr(log_y + 1, 2, "MISSION EVENT LOG:", curses.A_BOLD)
        for i, ev in enumerate(events[-4:]):
            if log_y + 2 + i < max_y - 2:
                stdscr.addstr(log_y + 2 + i, 4, ev)

        # Footer
        footer = " [SPACE] Pause/Resume | [+/-] Warp Multiplier | [Q] Exit Dashboard "
        stdscr.addstr(max_y - 1, max(0, (max_x - len(footer)) // 2), footer, curses.A_DIM)

        stdscr.refresh()
        time.sleep(0.05)


def main():
    try:
        curses.wrapper(render_dashboard)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
