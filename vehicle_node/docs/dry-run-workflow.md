# Dry-Run Workflow

Dry-run mode keeps the runtime daemon fully active while hardware outputs stay disabled.

## What dry-run proves

- RC packet parsing and `vehicle_id` targeting
- active-session locking and takeover after `lost`
- neutral-before-arm enforcement
- degraded and lost link transitions
- telemetry return-address learning
- mapped left/right track command values without energizing ESCs

## How to inspect it on a Pi later

Once a generated image is flashed and booted, inspect the service with:

```bash
systemctl status fruit-vehicle.service
journalctl -u fruit-vehicle.service
```

The service wrapper reads `/boot/firmware/fruit-view/runtime-settings.toml` first and falls back to `/boot/fruit-view/runtime-settings.toml` so it works across Raspberry Pi OS boot-mount conventions.

The daemon now reports real Wi-Fi link quality from `/proc/net/wireless` when `wlan0` is present, while unavailable telemetry fields continue to default to `0.0`.

## How to send a manual test packet

From another machine on the LAN:

```bash
python3 vehicle_node/tools/send_test_rc_packet.py --host 192.168.86.18 --vehicle-id 100 --arm 1.0
```

Useful follow-up checks on the Pi:

```bash
journalctl -u fruit-vehicle.service -n 100 -o cat
ss -lunp | grep 9000
```

## Re-arm expectations after real packet loss

If the link reaches `lost`, the daemon disarms and requires the arm switch to return low before another high arm command is accepted. This prevents a stale high switch from immediately re-arming on packet recovery.
