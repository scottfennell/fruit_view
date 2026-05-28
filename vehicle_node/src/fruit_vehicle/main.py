from __future__ import annotations

import argparse
from pathlib import Path

from .daemon import VehicleDaemon
from .runtime_settings import load_runtime_settings


def _default_config_path() -> str:
    for candidate in [
        "/boot/firmware/fruit-view/runtime-settings.toml",
        "/boot/fruit-view/runtime-settings.toml",
    ]:
        if Path(candidate).exists():
            return candidate
    return "/boot/firmware/fruit-view/runtime-settings.toml"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the fruit vehicle daemon")
    parser.add_argument("--config", default=_default_config_path())
    args = parser.parse_args()

    settings = load_runtime_settings(args.config)
    daemon = VehicleDaemon(settings)
    daemon.run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
