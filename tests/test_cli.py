"""
Automated CLI integration test suite for the NADIR mission planning binary.
Verifies invocation, argument parsing, error handling, and output formats.
"""

import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
NADIR_BIN = REPO_ROOT / "bin" / "nadir"


class TestNadirCLI(unittest.TestCase):
    """End-to-end integration tests for the compiled nadir command-line executable."""

    @classmethod
    def setUpClass(cls):
        """Ensure binary exists prior to executing CLI test suite."""
        if not NADIR_BIN.exists():
            subprocess.run(["make", "build"], cwd=REPO_ROOT, check=True)
        assert NADIR_BIN.exists(), f"Binary not found at {NADIR_BIN}"

    def run_cmd(self, *args):
        """Executes nadir binary with arguments and returns stdout string."""
        cmd = [str(NADIR_BIN)] + list(args)
        result = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        return result.stdout

    def test_version_command(self):
        """Asserts that version command prints architecture and build details."""
        out = self.run_cmd("version")
        self.assertIn("nadir version 1.0.0", out)
        self.assertIn("Mercury", out)
        self.assertIn("WGS-84 Geodesy", out)

    def test_help_command(self):
        """Asserts that help command outputs complete usage manual."""
        out = self.run_cmd("help")
        self.assertIn("Usage: nadir <command> [options]", out)
        self.assertIn("simulate", out)
        self.assertIn("propagate", out)
        self.assertIn("access", out)
        self.assertIn("schedule", out)
        self.assertIn("route", out)

    def test_route_command(self):
        """Asserts that route command calculates optimal optical crosslink path."""
        out = self.run_cmd("route")
        self.assertIn("ISL Route Found", out)
        self.assertIn("SAT_P00_S00 -> SAT_P00_S01 -> SAT_P00_S02", out)
        self.assertIn("Latency:", out)

    def test_schedule_command(self):
        """Asserts that schedule command solves multi-satellite observation plan."""
        out = self.run_cmd("schedule")
        self.assertIn("Mission Scheduler Result: 2 observations scheduled", out)
        self.assertIn("Scheduled Obs: [REQ_01 on SAT_01]", out)
        self.assertIn("Scheduled Obs: [REQ_02 on SAT_01]", out)

    def test_propagate_command(self):
        """Asserts that propagate command calculates Keplerian orbit ephemeris."""
        out = self.run_cmd("propagate", "--duration", "600", "--alt", "550")
        self.assertIn("Orbit Semi-Major Axis:", out)
        self.assertIn("Propagated 11 ephemeris points", out)
        self.assertIn("Sample Point 1:", out)

    def test_simulate_command(self):
        """Asserts that simulate command runs closed-loop mission timeline."""
        out = self.run_cmd("simulate", "--duration", "300")
        self.assertIn("Initializing constellation mission simulation", out)
        self.assertIn("Simulation 'NADIR 12-Sat Walker Operational Run' Complete", out)
        self.assertIn("Duration: 300.0s", out)
        self.assertIn("Min Battery SoC:", out)


if __name__ == "__main__":
    unittest.main()
