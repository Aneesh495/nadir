#!/usr/bin/env python3
"""
Verification utility to ensure no em dashes or en dashes exist in the codebase.
Strict check across all source files, documentation, and metadata.
"""

import os
import sys

FORBIDDEN_CHARS = {
    '\u2014': 'EM DASH (\\u2014)',
    '\u2013': 'EN DASH (\\u2013)',
}

EXCLUDED_DIRS = {'.git', 'Mercury', 'bin'}

def scan_file(filepath):
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line_no, line in enumerate(f, 1):
                for char, name in FORBIDDEN_CHARS.items():
                    if char in line:
                        errors.append((line_no, name, line.strip()))
    except Exception as e:
        print(f"Warning: could not read {filepath}: {e}")
    return errors

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    has_errors = False
    scanned_count = 0

    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fname in files:
            ext = os.path.splitext(fname)[1]
            if ext in {'.m', '.c', '.h', '.py', '.sh', '.md', '.json', '.csv', '.tle', '.txt', ''}:
                filepath = os.path.join(root, fname)
                errors = scan_file(filepath)
                scanned_count += 1
                if errors:
                    has_errors = True
                    print(f"Violation in {filepath}:")
                    for line_no, name, line_content in errors:
                        print(f"  Line {line_no}: contains {name} -> {line_content}")

    if has_errors:
        print(f"\nFAILED: Forbidden dashes found in scanned files.")
        sys.exit(1)
    else:
        print(f"PASSED: Scanned {scanned_count} files. Zero forbidden dashes found.")
        sys.exit(0)

if __name__ == '__main__':
    main()
