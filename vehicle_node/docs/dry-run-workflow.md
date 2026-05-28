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

## Re-arm expectations after real packet loss

If the link reaches `lost`, the daemon disarms and requires the arm switch to return low before another high arm command is accepted. This prevents a stale high switch from immediately re-arming on packet recovery.
