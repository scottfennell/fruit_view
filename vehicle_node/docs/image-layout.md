# Image Layout

The image builder personalizes a pinned Raspberry Pi OS Lite 32-bit image with these key changes.

## Boot partition

- `custom.toml` for Raspberry Pi OS first-boot hostname, `pi` password, SSH, and key install
- `fruit-view/runtime-settings.toml` generated from the canonical profile
- `fruit-view/build-manifest.toml` describing the build source id and selected profile
- `cmdline.txt` updated with the Wi-Fi regulatory domain

## Root partition

- `/etc/hostname` and `/etc/hosts`
- `/etc/NetworkManager/system-connections/kaaos.nmconnection`
- `/etc/NetworkManager/system-connections/fruit-ethernet.nmconnection`
- `/etc/ssh/ssh_host_*` precomputed host keys
- `/home/pi/.ssh/authorized_keys` when configured
- `/etc/mediamtx.yml`
- `/usr/local/bin/mediamtx`
- `/etc/systemd/system/fruit-mediamtx.service`
- `/etc/systemd/system/multi-user.target.wants/fruit-mediamtx.service`
- `/opt/fruit-vehicle/fruit_vehicle/` Python runtime files
- `/usr/local/bin/fruit-vehicle-daemon` runtime wrapper
- `/etc/systemd/system/fruit-vehicle.service`
- `/etc/systemd/system/multi-user.target.wants/fruit-vehicle.service` enablement symlink
- `/etc/tmpfiles.d/fruit-vehicle.conf` runtime directories created in RAM at boot

## Validation

Validation is filesystem-content validation only in v1. The build checks that the expected files exist and that the image carries the intended networking, SSH, RTSP, and daemon configuration. It does not attempt automated boot or hardware bring-up.
