# Vehicle Profile Schema

Vehicle profiles are TOML files. Real profiles live under `vehicle_node/profiles/local/` and are intentionally ignored by git.

Required top-level fields:

- `schema_version`: currently `1`
- `vehicle_id`: positive integer target id carried in RC packets
- `vehicle_type`: currently only `"tracked"`
- `hostname`: Linux hostname for the Pi image
- `[wifi]`: Wi-Fi client config and true static IP settings
- `[admin]`: `pi` password hash and optional authorized key paths
- `[camera]`: RTSP defaults and camera orientation settings
- `[control]`: control-port and link-loss timing settings
- `[telemetry]`: Wi-Fi signal normalization bounds
- `[tracked]`: tracked-vehicle channel mapping and ESC calibration

Unknown fields are rejected everywhere, including nested tables.

## Admin keys

`admin.authorized_keys` is a list of paths to public-key files. Relative paths are resolved relative to the profile file. Keep real keys under `vehicle_node/profiles/local/keys/` so the Docker builder can access them via the repo mount.

## Passwords

`admin.password_hash` stores the final SHA-512 password hash written into Raspberry Pi OS `userconf.txt`. Generate one locally with:

```bash
openssl passwd -6
```

## Tracked channel mapping

- `left_channel = 1`
- `right_channel = 2`
- `pan_channel = 3`
- `tilt_channel = 4`
- `arm_channel = 5`

`pan_channel` and `tilt_channel` are part of the profile now even though v1 dry-run mode does not actively drive those outputs.
