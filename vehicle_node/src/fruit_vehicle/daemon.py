from __future__ import annotations

from dataclasses import dataclass
import socket
import time

from .packet import PacketError, decode_control_packet
from .runtime_settings import RuntimeSettings
from .session import SessionSnapshot, VehicleSession
from .telemetry import encode_viewer_telemetry


class WifiSignalProvider:
    def read_signal_dbm(self) -> float:
        return -65.0


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

    def run_forever(self) -> None:
        period = 1.0 / float(self._settings.loop_hz)
        try:
            while True:
                started = time.monotonic()
                self.step(started)
                elapsed = time.monotonic() - started
                time.sleep(max(0.0, period - elapsed))
        finally:
            self.close()
