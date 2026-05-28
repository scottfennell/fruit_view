from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tomllib


class ProfileError(ValueError):
    pass


@dataclass(frozen=True)
class EscProfile:
    gpio_pin: int
    min_pulse_us: int
    neutral_pulse_us: int
    max_pulse_us: int
    deadband: float
    ramp_per_sec: float


@dataclass(frozen=True)
class TrackedProfile:
    left_channel: int
    right_channel: int
    pan_channel: int
    tilt_channel: int
    arm_channel: int
    left_esc: EscProfile
    right_esc: EscProfile


@dataclass(frozen=True)
class WifiProfile:
    country_code: str
    ssid: str
    password: str
    static_address: str
    gateway: str
    dns_servers: list[str]


@dataclass(frozen=True)
class AdminProfile:
    password_hash: str
    authorized_key_paths: list[Path]


@dataclass(frozen=True)
class CameraProfile:
    rtsp_port: int
    resolution_width: int
    resolution_height: int
    framerate: int
    bitrate_kbps: int
    orientation: str


@dataclass(frozen=True)
class ControlProfile:
    port: int
    degrade_timeout_ms: int
    lost_timeout_ms: int
    loop_hz: int
    telemetry_return_port: int


@dataclass(frozen=True)
class TelemetryProfile:
    wifi_signal_floor_dbm: float
    wifi_signal_ceiling_dbm: float


@dataclass(frozen=True)
class VehicleProfile:
    schema_version: int
    vehicle_id: int
    vehicle_type: str
    hostname: str
    wifi: WifiProfile
    admin: AdminProfile
    camera: CameraProfile
    control: ControlProfile
    telemetry: TelemetryProfile
    tracked: TrackedProfile
    profile_path: Path


def _expect_keys(raw: dict, allowed: set[str], context: str) -> None:
    unknown = sorted(set(raw.keys()) - allowed)
    if unknown:
        raise ProfileError(f"Unknown fields in {context}: {', '.join(unknown)}")


def _require(raw: dict, key: str, context: str):
    if key not in raw:
        raise ProfileError(f"Missing required field {context}.{key}")
    return raw[key]


def _as_int(value, context: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ProfileError(f"{context} must be an integer")
    return value


def _as_float(value, context: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProfileError(f"{context} must be numeric")
    return float(value)


def _as_str(value, context: str) -> str:
    if not isinstance(value, str) or not value:
        raise ProfileError(f"{context} must be a non-empty string")
    return value


def _as_str_list(value, context: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ProfileError(f"{context} must be a list of strings")
    return list(value)


def _load_esc(raw: dict, context: str) -> EscProfile:
    _expect_keys(
        raw,
        {
            "gpio_pin",
            "min_pulse_us",
            "neutral_pulse_us",
            "max_pulse_us",
            "deadband",
            "ramp_per_sec",
        },
        context,
    )
    esc = EscProfile(
        gpio_pin=_as_int(_require(raw, "gpio_pin", context), f"{context}.gpio_pin"),
        min_pulse_us=_as_int(
            _require(raw, "min_pulse_us", context), f"{context}.min_pulse_us"
        ),
        neutral_pulse_us=_as_int(
            _require(raw, "neutral_pulse_us", context), f"{context}.neutral_pulse_us"
        ),
        max_pulse_us=_as_int(
            _require(raw, "max_pulse_us", context), f"{context}.max_pulse_us"
        ),
        deadband=_as_float(_require(raw, "deadband", context), f"{context}.deadband"),
        ramp_per_sec=_as_float(
            _require(raw, "ramp_per_sec", context), f"{context}.ramp_per_sec"
        ),
    )
    if not (esc.min_pulse_us < esc.neutral_pulse_us < esc.max_pulse_us):
        raise ProfileError(
            f"{context} pulse calibration must satisfy min < neutral < max"
        )
    return esc


def load_profile(profile_path: str | Path) -> VehicleProfile:
    path = Path(profile_path).resolve()
    with path.open("rb") as handle:
        raw = tomllib.load(handle)

    _expect_keys(
        raw,
        {
            "schema_version",
            "vehicle_id",
            "vehicle_type",
            "hostname",
            "wifi",
            "admin",
            "camera",
            "control",
            "telemetry",
            "tracked",
        },
        "profile",
    )

    wifi_raw = _require(raw, "wifi", "profile")
    admin_raw = _require(raw, "admin", "profile")
    camera_raw = _require(raw, "camera", "profile")
    control_raw = _require(raw, "control", "profile")
    telemetry_raw = _require(raw, "telemetry", "profile")
    tracked_raw = _require(raw, "tracked", "profile")

    if not all(
        isinstance(section, dict)
        for section in [
            wifi_raw,
            admin_raw,
            camera_raw,
            control_raw,
            telemetry_raw,
            tracked_raw,
        ]
    ):
        raise ProfileError("Profile sections must be TOML tables")

    _expect_keys(
        wifi_raw,
        {
            "country_code",
            "ssid",
            "password",
            "static_address",
            "gateway",
            "dns_servers",
        },
        "wifi",
    )
    _expect_keys(admin_raw, {"password_hash", "authorized_keys"}, "admin")
    _expect_keys(
        camera_raw,
        {
            "rtsp_port",
            "resolution_width",
            "resolution_height",
            "framerate",
            "bitrate_kbps",
            "orientation",
        },
        "camera",
    )
    _expect_keys(
        control_raw,
        {
            "port",
            "degrade_timeout_ms",
            "lost_timeout_ms",
            "loop_hz",
            "telemetry_return_port",
        },
        "control",
    )
    _expect_keys(
        telemetry_raw, {"wifi_signal_floor_dbm", "wifi_signal_ceiling_dbm"}, "telemetry"
    )
    _expect_keys(
        tracked_raw,
        {
            "left_channel",
            "right_channel",
            "pan_channel",
            "tilt_channel",
            "arm_channel",
            "left_esc",
            "right_esc",
        },
        "tracked",
    )

    profile = VehicleProfile(
        schema_version=_as_int(
            _require(raw, "schema_version", "profile"), "schema_version"
        ),
        vehicle_id=_as_int(_require(raw, "vehicle_id", "profile"), "vehicle_id"),
        vehicle_type=_as_str(_require(raw, "vehicle_type", "profile"), "vehicle_type"),
        hostname=_as_str(_require(raw, "hostname", "profile"), "hostname"),
        wifi=WifiProfile(
            country_code=_as_str(
                _require(wifi_raw, "country_code", "wifi"), "wifi.country_code"
            ),
            ssid=_as_str(_require(wifi_raw, "ssid", "wifi"), "wifi.ssid"),
            password=_as_str(_require(wifi_raw, "password", "wifi"), "wifi.password"),
            static_address=_as_str(
                _require(wifi_raw, "static_address", "wifi"), "wifi.static_address"
            ),
            gateway=_as_str(_require(wifi_raw, "gateway", "wifi"), "wifi.gateway"),
            dns_servers=_as_str_list(
                _require(wifi_raw, "dns_servers", "wifi"), "wifi.dns_servers"
            ),
        ),
        admin=AdminProfile(
            password_hash=_as_str(
                _require(admin_raw, "password_hash", "admin"), "admin.password_hash"
            ),
            authorized_key_paths=[
                (path.parent / relative).resolve()
                for relative in _as_str_list(
                    _require(admin_raw, "authorized_keys", "admin"),
                    "admin.authorized_keys",
                )
            ],
        ),
        camera=CameraProfile(
            rtsp_port=_as_int(
                _require(camera_raw, "rtsp_port", "camera"), "camera.rtsp_port"
            ),
            resolution_width=_as_int(
                _require(camera_raw, "resolution_width", "camera"),
                "camera.resolution_width",
            ),
            resolution_height=_as_int(
                _require(camera_raw, "resolution_height", "camera"),
                "camera.resolution_height",
            ),
            framerate=_as_int(
                _require(camera_raw, "framerate", "camera"), "camera.framerate"
            ),
            bitrate_kbps=_as_int(
                _require(camera_raw, "bitrate_kbps", "camera"), "camera.bitrate_kbps"
            ),
            orientation=_as_str(
                _require(camera_raw, "orientation", "camera"), "camera.orientation"
            ),
        ),
        control=ControlProfile(
            port=_as_int(_require(control_raw, "port", "control"), "control.port"),
            degrade_timeout_ms=_as_int(
                _require(control_raw, "degrade_timeout_ms", "control"),
                "control.degrade_timeout_ms",
            ),
            lost_timeout_ms=_as_int(
                _require(control_raw, "lost_timeout_ms", "control"),
                "control.lost_timeout_ms",
            ),
            loop_hz=_as_int(
                _require(control_raw, "loop_hz", "control"), "control.loop_hz"
            ),
            telemetry_return_port=_as_int(
                _require(control_raw, "telemetry_return_port", "control"),
                "control.telemetry_return_port",
            ),
        ),
        telemetry=TelemetryProfile(
            wifi_signal_floor_dbm=_as_float(
                _require(telemetry_raw, "wifi_signal_floor_dbm", "telemetry"),
                "telemetry.wifi_signal_floor_dbm",
            ),
            wifi_signal_ceiling_dbm=_as_float(
                _require(telemetry_raw, "wifi_signal_ceiling_dbm", "telemetry"),
                "telemetry.wifi_signal_ceiling_dbm",
            ),
        ),
        tracked=TrackedProfile(
            left_channel=_as_int(
                _require(tracked_raw, "left_channel", "tracked"), "tracked.left_channel"
            ),
            right_channel=_as_int(
                _require(tracked_raw, "right_channel", "tracked"),
                "tracked.right_channel",
            ),
            pan_channel=_as_int(
                _require(tracked_raw, "pan_channel", "tracked"), "tracked.pan_channel"
            ),
            tilt_channel=_as_int(
                _require(tracked_raw, "tilt_channel", "tracked"), "tracked.tilt_channel"
            ),
            arm_channel=_as_int(
                _require(tracked_raw, "arm_channel", "tracked"), "tracked.arm_channel"
            ),
            left_esc=_load_esc(
                _require(tracked_raw, "left_esc", "tracked"), "tracked.left_esc"
            ),
            right_esc=_load_esc(
                _require(tracked_raw, "right_esc", "tracked"), "tracked.right_esc"
            ),
        ),
        profile_path=path,
    )

    if profile.schema_version != 1:
        raise ProfileError("schema_version must be 1")
    if profile.vehicle_id <= 0:
        raise ProfileError("vehicle_id must be positive")
    if profile.vehicle_type != "tracked":
        raise ProfileError("vehicle_type must be 'tracked'")
    if profile.camera.orientation not in {
        "normal",
        "flip_horizontal",
        "flip_vertical",
        "rotate_180",
    }:
        raise ProfileError(
            "camera.orientation must be one of: normal, flip_horizontal, flip_vertical, rotate_180"
        )
    if len(profile.wifi.country_code) != 2:
        raise ProfileError("wifi.country_code must be a two-letter code")
    if profile.control.degrade_timeout_ms >= profile.control.lost_timeout_ms:
        raise ProfileError(
            "control.degrade_timeout_ms must be less than control.lost_timeout_ms"
        )
    for channel_name in [
        profile.tracked.left_channel,
        profile.tracked.right_channel,
        profile.tracked.pan_channel,
        profile.tracked.tilt_channel,
        profile.tracked.arm_channel,
    ]:
        if channel_name < 1 or channel_name > 8:
            raise ProfileError("tracked channel values must be between 1 and 8")
    for key_path in profile.admin.authorized_key_paths:
        if not key_path.exists():
            raise ProfileError(f"authorized key file does not exist: {key_path}")

    return profile
