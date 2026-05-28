from __future__ import annotations

import unittest

from vehicle_node.src.fruit_vehicle.packet import (
    PacketError,
    decode_control_packet,
    encode_control_packet,
)


class PacketTests(unittest.TestCase):
    def test_encode_and_decode_round_trip(self) -> None:
        payload = encode_control_packet(
            101, 12, [0.0, 0.1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
        )
        packet = decode_control_packet(payload, expected_vehicle_id=101)
        self.assertEqual(packet.tick, 12)
        self.assertAlmostEqual(packet.channels[1], 0.1)

    def test_wrong_vehicle_id_is_rejected(self) -> None:
        payload = encode_control_packet(101, 1, [0.0] * 8)
        with self.assertRaises(PacketError):
            decode_control_packet(payload, expected_vehicle_id=999)

    def test_out_of_range_channel_is_rejected(self) -> None:
        payload = encode_control_packet(
            101, 1, [0.0, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        )
        with self.assertRaises(PacketError):
            decode_control_packet(payload, expected_vehicle_id=101)
