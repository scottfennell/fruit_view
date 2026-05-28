from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tomllib

from .profile import VehicleProfile


@dataclass(frozen=True)
class RuntimeSettings:
    vehicle_id: int
    hostname: str
    dry_run: bool
    control_port: int
    telemetry_return_port: int
    degrade_timeout_ms: int
    lost_timeout_ms: int
    loop_hz: int
    left_channel_index: int
    right_channel_index: int
    arm_channel_index: int
    wifi_signal_floor_dbm: float
    wifi_signal_ceiling_dbm: float


def build_runtime_settings(
    profile: VehicleProfile, dry_run: bool = True
) -> RuntimeSettings:
    return RuntimeSettings(
        vehicle_id=profile.vehicle_id,
        hostname=profile.hostname,
        dry_run=dry_run,
        control_port=profile.control.port,
        telemetry_return_port=profile.control.telemetry_return_port,
        degrade_timeout_ms=profile.control.degrade_timeout_ms,
        lost_timeout_ms=profile.control.lost_timeout_ms,
        loop_hz=profile.control.loop_hz,
        left_channel_index=profile.tracked.left_channel - 1,
        right_channel_index=profile.tracked.right_channel - 1,
        arm_channel_index=profile.tracked.arm_channel - 1,
        wifi_signal_floor_dbm=profile.telemetry.wifi_signal_floor_dbm,
        wifi_signal_ceiling_dbm=profile.telemetry.wifi_signal_ceiling_dbm,
    )


def render_runtime_settings(settings: RuntimeSettings) -> str:
    return "\n".join(
        [
            "schema_version = 1",
            f"vehicle_id = {settings.vehicle_id}",
            f'hostname = "{settings.hostname}"',
            f"dry_run = {str(settings.dry_run).lower()}",
            "",
            "[control]",
            f"port = {settings.control_port}",
            f"telemetry_return_port = {settings.telemetry_return_port}",
            f"degrade_timeout_ms = {settings.degrade_timeout_ms}",
            f"lost_timeout_ms = {settings.lost_timeout_ms}",
            f"loop_hz = {settings.loop_hz}",
            "",
            "[tracked]",
            f"left_channel_index = {settings.left_channel_index}",
            f"right_channel_index = {settings.right_channel_index}",
            f"arm_channel_index = {settings.arm_channel_index}",
            "",
            "[telemetry]",
            f"wifi_signal_floor_dbm = {settings.wifi_signal_floor_dbm}",
            f"wifi_signal_ceiling_dbm = {settings.wifi_signal_ceiling_dbm}",
            "",
        ]
    )


def load_runtime_settings(path: str | Path) -> RuntimeSettings:
    with Path(path).open("rb") as handle:
        raw = tomllib.load(handle)
    control = raw["control"]
    tracked = raw["tracked"]
    telemetry = raw["telemetry"]
    return RuntimeSettings(
        vehicle_id=int(raw["vehicle_id"]),
        hostname=str(raw["hostname"]),
        dry_run=bool(raw["dry_run"]),
        control_port=int(control["port"]),
        telemetry_return_port=int(control["telemetry_return_port"]),
        degrade_timeout_ms=int(control["degrade_timeout_ms"]),
        lost_timeout_ms=int(control["lost_timeout_ms"]),
        loop_hz=int(control["loop_hz"]),
        left_channel_index=int(tracked["left_channel_index"]),
        right_channel_index=int(tracked["right_channel_index"]),
        arm_channel_index=int(tracked["arm_channel_index"]),
        wifi_signal_floor_dbm=float(telemetry["wifi_signal_floor_dbm"]),
        wifi_signal_ceiling_dbm=float(telemetry["wifi_signal_ceiling_dbm"]),
    )
