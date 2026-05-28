from __future__ import annotations

import unittest

from vehicle_node.src.fruit_vehicle.packet import ControlPacket
from vehicle_node.src.fruit_vehicle.runtime_settings import RuntimeSettings
from vehicle_node.src.fruit_vehicle.session import LinkState, VehicleSession


def _settings() -> RuntimeSettings:
    return RuntimeSettings(
        vehicle_id=101,
        hostname="fruit-test",
        dry_run=True,
        control_port=9000,
        telemetry_return_port=9002,
        degrade_timeout_ms=250,
        lost_timeout_ms=2000,
        loop_hz=100,
        left_channel_index=0,
        right_channel_index=1,
        arm_channel_index=4,
        wifi_signal_floor_dbm=-90.0,
        wifi_signal_ceiling_dbm=-30.0,
    )


class SessionTests(unittest.TestCase):
    def test_neutral_required_before_arming(self) -> None:
        session = VehicleSession(_settings())
        packet = ControlPacket(101, 1, (0.6, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        session.accept_packet(("10.0.0.2", 4000), packet, 0.0)
        self.assertFalse(session.snapshot().armed)

    def test_active_session_lock_blocks_other_sender_before_lost(self) -> None:
        session = VehicleSession(_settings())
        a = ControlPacket(101, 1, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        b = ControlPacket(101, 2, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        self.assertTrue(session.accept_packet(("10.0.0.2", 4000), a, 0.0))
        self.assertFalse(session.accept_packet(("10.0.0.3", 4001), b, 0.1))
        self.assertEqual(session.snapshot().active_sender, ("10.0.0.2", 4000))

    def test_lost_requires_low_then_high_rearm(self) -> None:
        session = VehicleSession(_settings())
        arm = ControlPacket(101, 1, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        session.accept_packet(("10.0.0.2", 4000), arm, 0.0)
        self.assertTrue(session.snapshot().armed)
        session.advance(2.1)
        self.assertEqual(session.snapshot().link_state, LinkState.LOST)
        self.assertFalse(session.snapshot().armed)

        recovered_high = ControlPacket(101, 2, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        session.accept_packet(("10.0.0.2", 4000), recovered_high, 2.2)
        self.assertFalse(session.snapshot().armed)

        recovered_low = ControlPacket(101, 3, (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
        recovered_high_again = ControlPacket(
            101, 4, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0)
        )
        session.accept_packet(("10.0.0.2", 4000), recovered_low, 2.3)
        session.accept_packet(("10.0.0.2", 4000), recovered_high_again, 2.4)
        self.assertTrue(session.snapshot().armed)

    def test_degraded_neutralizes_outputs_but_keeps_armed_state(self) -> None:
        session = VehicleSession(_settings())
        neutral_arm = ControlPacket(101, 1, (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        drive = ControlPacket(101, 2, (0.7, -0.4, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0))
        session.accept_packet(("10.0.0.2", 4000), neutral_arm, 0.0)
        session.accept_packet(("10.0.0.2", 4000), drive, 0.1)
        snapshot = session.advance(0.5)
        self.assertEqual(snapshot.link_state, LinkState.DEGRADED)
        self.assertTrue(snapshot.armed)
        self.assertEqual(snapshot.output.left, 0.0)
        self.assertEqual(snapshot.output.right, 0.0)
