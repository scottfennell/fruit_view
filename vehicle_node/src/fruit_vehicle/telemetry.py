from __future__ import annotations

import struct


TELEMETRY_STRUCT = struct.Struct("<fffdd")


def clamp_signal(signal_dbm: float, floor_dbm: float, ceiling_dbm: float) -> float:
    if signal_dbm < floor_dbm:
        return floor_dbm
    if signal_dbm > ceiling_dbm:
        return ceiling_dbm
    return signal_dbm


def encode_viewer_telemetry(
    signal_dbm: float, floor_dbm: float, ceiling_dbm: float
) -> bytes:
    clamped = clamp_signal(signal_dbm, floor_dbm, ceiling_dbm)
    return TELEMETRY_STRUCT.pack(0.0, 0.0, clamped, 0.0, 0.0)
