from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .packet import ControlPacket
from .runtime_settings import RuntimeSettings


class LinkState(str, Enum):
    IDLE = "idle"
    ACTIVE = "active"
    DEGRADED = "degraded"
    LOST = "lost"


@dataclass(frozen=True)
class OutputCommand:
    left: float
    right: float


@dataclass(frozen=True)
class SessionSnapshot:
    link_state: LinkState
    armed: bool
    active_sender: tuple[str, int] | None
    telemetry_target: tuple[str, int] | None
    output: OutputCommand
    requires_rearm_cycle: bool


class VehicleSession:
    ARM_THRESHOLD = 0.5
    NEUTRAL_THRESHOLD = 0.1

    def __init__(self, settings: RuntimeSettings) -> None:
        self._settings = settings
        self._active_sender: tuple[str, int] | None = None
        self._telemetry_target: tuple[str, int] | None = None
        self._last_tick: int | None = None
        self._last_packet_at: float | None = None
        self._link_state = LinkState.IDLE
        self._armed = False
        self._saw_arm_low_after_loss = True
        self._requires_rearm_cycle = False
        self._left = 0.0
        self._right = 0.0

    def snapshot(self) -> SessionSnapshot:
        return SessionSnapshot(
            link_state=self._link_state,
            armed=self._armed,
            active_sender=self._active_sender,
            telemetry_target=self._telemetry_target,
            output=OutputCommand(self._left, self._right),
            requires_rearm_cycle=self._requires_rearm_cycle,
        )

    def accept_packet(
        self, sender: tuple[str, int], packet: ControlPacket, now: float
    ) -> bool:
        if self._active_sender is None or self._link_state == LinkState.LOST:
            self._active_sender = sender
            self._last_tick = None
            self._link_state = LinkState.ACTIVE
            if self._requires_rearm_cycle:
                self._saw_arm_low_after_loss = False
        else:
            if sender != self._active_sender:
                return False

        if self._last_tick is not None and packet.tick <= self._last_tick:
            return False

        self._last_tick = packet.tick
        self._last_packet_at = now
        self._link_state = LinkState.ACTIVE
        self._telemetry_target = (sender[0], self._settings.telemetry_return_port)

        left = packet.channels[self._settings.left_channel_index]
        right = packet.channels[self._settings.right_channel_index]
        arm = packet.channels[self._settings.arm_channel_index]

        if arm <= 0.0:
            self._saw_arm_low_after_loss = True

        near_neutral = (
            abs(left) <= self.NEUTRAL_THRESHOLD and abs(right) <= self.NEUTRAL_THRESHOLD
        )
        if self._armed and arm <= 0.0:
            self._armed = False
        elif not self._armed and arm >= self.ARM_THRESHOLD and near_neutral:
            if not self._requires_rearm_cycle or self._saw_arm_low_after_loss:
                self._armed = True
                self._requires_rearm_cycle = False

        if self._armed:
            self._left = left
            self._right = right
        else:
            self._left = 0.0
            self._right = 0.0
        return True

    def advance(self, now: float) -> SessionSnapshot:
        if self._last_packet_at is None:
            return self.snapshot()

        elapsed_ms = (now - self._last_packet_at) * 1000.0
        if elapsed_ms >= self._settings.lost_timeout_ms:
            self._link_state = LinkState.LOST
            self._armed = False
            self._left = 0.0
            self._right = 0.0
            self._requires_rearm_cycle = True
        elif elapsed_ms >= self._settings.degrade_timeout_ms:
            self._link_state = LinkState.DEGRADED
            self._left = 0.0
            self._right = 0.0
        return self.snapshot()
