from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import socket
import time

from .packet import PacketError, decode_control_packet
from .runtime_settings import RuntimeSettings
from .session import SessionSnapshot, VehicleSession
from .telemetry import encode_viewer_telemetry


def _emit(message: str) -> None:
    print(message, flush=True)


class WifiSignalProvider:
    def __init__(
        self,
        interface_name: str = "wlan0",
        proc_net_wireless_path: str | Path = "/proc/net/wireless",
        fallback_signal_dbm: float = -65.0,
    ) -> None:
        self._interface_name = interface_name
        self._proc_net_wireless_path = Path(proc_net_wireless_path)
        self._fallback_signal_dbm = fallback_signal_dbm

    def read_signal_dbm(self) -> float:
        try:
            return self._read_proc_net_wireless()
        except (OSError, ValueError):
            return self._fallback_signal_dbm

    def _read_proc_net_wireless(self) -> float:
        for raw_line in self._proc_net_wireless_path.read_text(
            encoding="utf-8"
        ).splitlines():
            stripped = raw_line.strip()
            if not stripped.startswith(f"{self._interface_name}:"):
                continue

            payload = stripped.split(":", maxsplit=1)[1]
            fields = payload.split()
            if len(fields) < 3:
                raise ValueError("unexpected /proc/net/wireless format")

            level_field = fields[2].rstrip(".")
            return float(level_field)

        raise ValueError(
            f"interface {self._interface_name} not found in /proc/net/wireless"
        )


@dataclass
class DryRunState:
    left: float = 0.0
    right: float = 0.0
    armed: bool = False
    link_state: str = "idle"


class VehicleDaemon:
    def __init__(
        self,
        settings: RuntimeSettings,
        signal_provider: WifiSignalProvider | None = None,
    ) -> None:
        self._settings = settings
        self._signal_provider = signal_provider or WifiSignalProvider()
        self._session = VehicleSession(settings)
        self._state = DryRunState()
        self._control_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._control_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._control_socket.bind(("0.0.0.0", settings.control_port))
        self._control_socket.setblocking(False)
        self._telemetry_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._last_telemetry_at = 0.0
        self._last_snapshot = self._session.snapshot()

    def close(self) -> None:
        self._control_socket.close()
        self._telemetry_socket.close()

    def step(self, now: float | None = None) -> SessionSnapshot:
        now = time.monotonic() if now is None else now
        while True:
            try:
                payload, sender = self._control_socket.recvfrom(4096)
            except BlockingIOError:
                break
            try:
                packet = decode_control_packet(payload, self._settings.vehicle_id)
            except PacketError:
                continue
            self._session.accept_packet(sender, packet, now)

        snapshot = self._session.advance(now)
        self._log_snapshot_changes(self._last_snapshot, snapshot)
        self._last_snapshot = snapshot
        self._state.left = snapshot.output.left
        self._state.right = snapshot.output.right
        self._state.armed = snapshot.armed
        self._state.link_state = snapshot.link_state.value

        if snapshot.telemetry_target and now - self._last_telemetry_at >= 0.2:
            telemetry = encode_viewer_telemetry(
                self._signal_provider.read_signal_dbm(),
                self._settings.wifi_signal_floor_dbm,
                self._settings.wifi_signal_ceiling_dbm,
            )
            self._telemetry_socket.sendto(telemetry, snapshot.telemetry_target)
            self._last_telemetry_at = now

        return snapshot

    def _log_snapshot_changes(
        self, previous: SessionSnapshot, current: SessionSnapshot
    ) -> None:
        if (
            previous.active_sender != current.active_sender
            and current.active_sender is not None
        ):
            _emit(
                f"active session locked to {current.active_sender[0]}:{current.active_sender[1]}"
            )

        if (
            previous.telemetry_target != current.telemetry_target
            and current.telemetry_target is not None
        ):
            _emit(
                f"telemetry target set to {current.telemetry_target[0]}:{current.telemetry_target[1]}"
            )

        if previous.link_state != current.link_state:
            _emit(f"link state changed to {current.link_state.value}")

        if previous.armed != current.armed:
            _emit(f"armed state changed to {current.armed}")

        if previous.output != current.output and current.armed:
            _emit(
                "dry-run track output left=%.2f right=%.2f"
                % (current.output.left, current.output.right)
            )

    def run_forever(self) -> None:
        _emit(
            "fruit vehicle daemon listening on udp/%s for vehicle_id=%s"
            % (self._settings.control_port, self._settings.vehicle_id)
        )
        period = 1.0 / float(self._settings.loop_hz)
        try:
            while True:
                started = time.monotonic()
                self.step(started)
                elapsed = time.monotonic() - started
                time.sleep(max(0.0, period - elapsed))
        finally:
            self.close()
