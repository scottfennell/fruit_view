from __future__ import annotations

from dataclasses import dataclass
import struct


MAGIC = b"FRC1"
VERSION = 1
CHANNEL_COUNT = 8
PACKET_STRUCT = struct.Struct("<4sBBHII8f")
PACKET_SIZE = PACKET_STRUCT.size


class PacketError(ValueError):
    pass


@dataclass(frozen=True)
class ControlPacket:
    vehicle_id: int
    tick: int
    channels: tuple[float, ...]


def encode_control_packet(
    vehicle_id: int, tick: int, channels: list[float] | tuple[float, ...]
) -> bytes:
    if len(channels) != CHANNEL_COUNT:
        raise PacketError("control packet requires exactly 8 channels")
    return PACKET_STRUCT.pack(
        MAGIC, VERSION, CHANNEL_COUNT, 0, vehicle_id, tick, *channels
    )


def decode_control_packet(data: bytes, expected_vehicle_id: int) -> ControlPacket:
    if len(data) != PACKET_SIZE:
        raise PacketError(f"expected {PACKET_SIZE} bytes, received {len(data)}")
    magic, version, channel_count, _reserved, vehicle_id, tick, *channels = (
        PACKET_STRUCT.unpack(data)
    )
    if magic != MAGIC:
        raise PacketError("invalid packet magic")
    if version != VERSION:
        raise PacketError("unsupported packet version")
    if channel_count != CHANNEL_COUNT:
        raise PacketError("unexpected channel count")
    if vehicle_id != expected_vehicle_id:
        raise PacketError("packet vehicle_id does not match runtime settings")
    for index, channel in enumerate(channels, start=1):
        if channel < -1.0 or channel > 1.0:
            raise PacketError(f"channel ch{index} out of range")
    return ControlPacket(vehicle_id=vehicle_id, tick=tick, channels=tuple(channels))
