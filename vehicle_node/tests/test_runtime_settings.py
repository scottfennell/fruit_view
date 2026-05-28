from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from vehicle_node.src.fruit_vehicle.profile import load_profile
from vehicle_node.src.fruit_vehicle.runtime_settings import (
    build_runtime_settings,
    load_runtime_settings,
    render_runtime_settings,
)


class RuntimeSettingsTests(unittest.TestCase):
    def test_runtime_settings_round_trip(self) -> None:
        example = (
            Path(__file__).resolve().parents[1]
            / "profiles"
            / "examples"
            / "tracked.example.toml"
        )
        profile = load_profile(example)
        settings = build_runtime_settings(profile, dry_run=True)
        rendered = render_runtime_settings(settings)

        with TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "runtime-settings.toml"
            path.write_text(rendered, encoding="utf-8")
            loaded = load_runtime_settings(path)

        self.assertTrue(loaded.dry_run)
        self.assertEqual(loaded.vehicle_id, profile.vehicle_id)
        self.assertEqual(loaded.arm_channel_index, 4)
