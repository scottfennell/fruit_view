from __future__ import annotations

import struct
import unittest

from vehicle_node.src.fruit_vehicle.telemetry import (
    TELEMETRY_STRUCT,
    clamp_signal,
    encode_viewer_telemetry,
)


class TelemetryTests(unittest.TestCase):
    def test_signal_is_clamped_to_profile_bounds(self) -> None:
        self.assertEqual(clamp_signal(-120.0, -90.0, -30.0), -90.0)
        self.assertEqual(clamp_signal(-20.0, -90.0, -30.0), -30.0)

    def test_existing_viewer_packet_shape_is_preserved(self) -> None:
        payload = encode_viewer_telemetry(-55.0, -90.0, -30.0)
        battery, speed, signal, lat, lon = TELEMETRY_STRUCT.unpack(payload)
        self.assertEqual(battery, 0.0)
        self.assertEqual(speed, 0.0)
        self.assertEqual(signal, -55.0)
        self.assertEqual(lat, 0.0)
        self.assertEqual(lon, 0.0)
