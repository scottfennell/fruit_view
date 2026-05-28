from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from vehicle_node.src.fruit_vehicle.profile import ProfileError, load_profile


VALID_PROFILE = """
schema_version = 1
vehicle_id = 42
vehicle_type = "tracked"
hostname = "fruit-test"

[wifi]
country_code = "US"
ssid = "ssid"
password = "secret"
static_address = "192.168.1.10/24"
gateway = "192.168.1.1"
dns_servers = ["192.168.1.1"]

[admin]
password_hash = "$6$hash"
authorized_keys = ["keys/id.pub"]

[camera]
rtsp_port = 8554
resolution_width = 1280
resolution_height = 720
framerate = 30
bitrate_kbps = 2500
orientation = "normal"

[control]
port = 9000
degrade_timeout_ms = 250
lost_timeout_ms = 2000
loop_hz = 100
telemetry_return_port = 9002

[telemetry]
wifi_signal_floor_dbm = -90.0
wifi_signal_ceiling_dbm = -30.0

[tracked]
left_channel = 1
right_channel = 2
pan_channel = 3
tilt_channel = 4
arm_channel = 5

[tracked.left_esc]
gpio_pin = 18
min_pulse_us = 1000
neutral_pulse_us = 1500
max_pulse_us = 2000
deadband = 0.05
ramp_per_sec = 1.0

[tracked.right_esc]
gpio_pin = 19
min_pulse_us = 1000
neutral_pulse_us = 1500
max_pulse_us = 2000
deadband = 0.05
ramp_per_sec = 1.0
"""


class ProfileTests(unittest.TestCase):
    def test_valid_profile_loads(self) -> None:
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "keys").mkdir()
            (root / "keys" / "id.pub").write_text(
                "ssh-ed25519 AAAATEST\n", encoding="utf-8"
            )
            profile_path = root / "vehicle.toml"
            profile_path.write_text(VALID_PROFILE, encoding="utf-8")
            profile = load_profile(profile_path)
            self.assertEqual(profile.vehicle_id, 42)
            self.assertEqual(profile.tracked.arm_channel, 5)

    def test_unknown_field_is_rejected(self) -> None:
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "keys").mkdir()
            (root / "keys" / "id.pub").write_text(
                "ssh-ed25519 AAAATEST\n", encoding="utf-8"
            )
            profile_path = root / "vehicle.toml"
            profile_path.write_text(
                VALID_PROFILE + "unexpected = 1\n", encoding="utf-8"
            )
            with self.assertRaises(ProfileError):
                load_profile(profile_path)

    def test_missing_authorized_key_path_is_rejected(self) -> None:
        with TemporaryDirectory() as temp_dir:
            profile_path = Path(temp_dir) / "vehicle.toml"
            profile_path.write_text(VALID_PROFILE, encoding="utf-8")
            with self.assertRaises(ProfileError):
                load_profile(profile_path)
