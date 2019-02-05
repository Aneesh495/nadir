#!/usr/bin/env python3
"""
Unit tests for NADIR structural integrity and Python bindings.
"""

import unittest
import os
import subprocess

class TestNadirStructure(unittest.TestCase):
    def setUp(self):
        self.root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def test_binaries_built(self):
        nadir_bin = os.path.join(self.root_dir, 'bin', 'nadir')
        test_bin = os.path.join(self.root_dir, 'bin', 'test_runner')
        self.assertTrue(os.path.exists(nadir_bin), "nadir binary must exist")
        self.assertTrue(os.path.exists(test_bin), "test_runner binary must exist")

    def test_mercury_test_runner_execution(self):
        test_bin = os.path.join(self.root_dir, 'bin', 'test_runner')
        res = subprocess.run([test_bin], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("All Engine Unit Tests Passed", res.stdout)

if __name__ == '__main__':
    unittest.main()
