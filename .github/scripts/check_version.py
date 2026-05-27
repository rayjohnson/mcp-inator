#!/usr/bin/env python3
"""
Validate that the proposed version is a valid semver bump.

Usage:
    check_version.py <latest_tag> <proposed_version> [main_version]

Exits non-zero if:
  - proposed_version <= latest_tag
  - main_version is provided and does not match latest_tag (broken state)
"""
import sys


def parse_semver(v):
    v = v.strip().lstrip("v")
    parts = v.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError(f"Not a valid semver: {v!r}")
    return tuple(int(p) for p in parts)


def main():
    if len(sys.argv) < 3:
        print("Usage: check_version.py <latest_tag> <proposed> [main_version]")
        sys.exit(1)

    latest_tag = sys.argv[1].strip()
    proposed = sys.argv[2].strip()
    main_version = sys.argv[3].strip() if len(sys.argv) > 3 else None

    if not latest_tag:
        print("No existing release tags — any valid semver is acceptable.")
        try:
            parse_semver(proposed)
        except ValueError as e:
            print(f"ERROR: {e}")
            sys.exit(1)
        print(f"OK: {proposed} (first release)")
        return

    try:
        tag_tuple = parse_semver(latest_tag)
        proposed_tuple = parse_semver(proposed)
    except ValueError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    if main_version:
        try:
            main_tuple = parse_semver(main_version)
            if main_tuple != tag_tuple:
                print(
                    f"ERROR: VERSION on main ({main_version}) does not match "
                    f"latest tag ({latest_tag}) — repo is in an inconsistent state."
                )
                sys.exit(1)
        except ValueError:
            print(f"WARNING: could not parse main VERSION: {main_version!r}")

    if proposed_tuple <= tag_tuple:
        print(
            f"ERROR: VERSION {proposed} must be greater than "
            f"the current release {latest_tag}"
        )
        sys.exit(1)

    print(f"OK: {proposed} > {latest_tag}")


if __name__ == "__main__":
    main()
