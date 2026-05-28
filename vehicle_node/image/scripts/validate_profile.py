from __future__ import annotations

import argparse

from _common import ROOT  # noqa: F401
from vehicle_node.src.fruit_vehicle.profile import load_profile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    args = parser.parse_args()
    load_profile(args.profile)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
