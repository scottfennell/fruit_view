from __future__ import annotations

import argparse

from _common import ROOT  # noqa: F401
from vehicle_node.src.fruit_vehicle.profile import load_profile
from vehicle_node.src.fruit_vehicle.runtime_settings import (
    build_runtime_settings,
    render_runtime_settings,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    profile = load_profile(args.profile)
    settings = build_runtime_settings(profile, dry_run=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(render_runtime_settings(settings))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
