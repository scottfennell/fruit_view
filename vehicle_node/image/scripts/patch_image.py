from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import tempfile
import tarfile
from pathlib import Path
import tomllib

from _common import ROOT
from vehicle_node.src.fruit_vehicle.profile import VehicleProfile, load_profile
from vehicle_node.src.fruit_vehicle.runtime_settings import (
    build_runtime_settings,
    render_runtime_settings,
)


def _run(*args: str) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def _boot_partition_path(root: Path) -> Path:
    for candidate in [root / "boot" / "firmware", root / "boot"]:
        if candidate.exists():
            return candidate
    return root / "boot"


def _partition_map(image_path: Path) -> dict[int, tuple[int, int]]:
    output = _run("parted", "-s", str(image_path), "unit", "B", "print")
    partitions: dict[int, tuple[int, int]] = {}
    for line in output.splitlines():
        match = re.match(r"\s*(\d+)\s+(\d+)B\s+(\d+)B\s+(\d+)B\s+", line)
        if match is None:
            continue
        partitions[int(match.group(1))] = (int(match.group(2)), int(match.group(4)))

    if 1 not in partitions or 2 not in partitions:
        raise RuntimeError(
            f"failed to read expected partition layout from {image_path}"
        )
    return partitions


def _mount_partition(
    image_path: Path, mount_path: Path, offset: int, size: int
) -> None:
    subprocess.run(
        [
            "mount",
            "-o",
            f"loop,offset={offset},sizelimit={size}",
            str(image_path),
            str(mount_path),
        ],
        check=True,
    )


def _write(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    if mode is not None:
        path.chmod(mode)


def _render_nmconnection(profile: VehicleProfile) -> str:
    dns = ";".join(profile.wifi.dns_servers) + ";"
    return "\n".join(
        [
            "[connection]",
            f"id={profile.wifi.ssid}",
            "uuid=2a1b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
            "type=wifi",
            "interface-name=wlan0",
            "",
            "[wifi]",
            "mode=infrastructure",
            f"ssid={profile.wifi.ssid}",
            "",
            "[wifi-security]",
            "auth-alg=open",
            "key-mgmt=wpa-psk",
            f"psk={profile.wifi.password}",
            "",
            "[ipv4]",
            "method=manual",
            f"address1={profile.wifi.static_address},{profile.wifi.gateway}",
            f"dns={dns}",
            "",
            "[ipv6]",
            "addr-gen-mode=default",
            "method=auto",
            "",
            "[proxy]",
            "",
        ]
    )


def _render_ethernet_connection() -> str:
    return "\n".join(
        [
            "[connection]",
            "id=fruit-ethernet",
            "type=ethernet",
            "autoconnect=true",
            "",
            "[ipv4]",
            "method=auto",
            "",
            "[ipv6]",
            "method=ignore",
            "",
        ]
    )


def _camera_flips(profile: VehicleProfile) -> tuple[bool, bool]:
    orientation = profile.camera.orientation
    if orientation == "flip_horizontal":
        return True, False
    if orientation == "flip_vertical":
        return False, True
    if orientation == "rotate_180":
        return True, True
    return False, False


def _render_mediamtx_config(profile: VehicleProfile) -> str:
    hflip, vflip = _camera_flips(profile)
    return "\n".join(
        [
            "logLevel: info",
            "rtsp: yes",
            "protocols: [tcp]",
            f"rtspAddress: :{profile.camera.rtsp_port}",
            "paths:",
            "  stream:",
            "    source: rpiCamera",
            f"    rpiCameraWidth: {profile.camera.resolution_width}",
            f"    rpiCameraHeight: {profile.camera.resolution_height}",
            f"    rpiCameraHFlip: {str(hflip).lower()}",
            f"    rpiCameraVFlip: {str(vflip).lower()}",
            f"    rpiCameraFPS: {profile.camera.framerate}",
            f"    rpiCameraIDRPeriod: {max(1, profile.camera.framerate * 2)}",
            f"    rpiCameraBitrate: {profile.camera.bitrate_kbps * 1000}",
            "",
        ]
    )


def _render_networkmanager_conf() -> str:
    return "\n".join(
        [
            "[main]",
            "plugins=ifupdown,keyfile",
            "",
            "[ifupdown]",
            "managed=true",
            "",
            "[device]",
            "wifi.scan-rand-mac-address=no",
            "",
        ]
    )


def _render_hosts(hostname: str) -> str:
    return "\n".join(
        [
            "127.0.0.1\tlocalhost",
            f"127.0.1.1\t{hostname}",
            "",
        ]
    )


def _render_fstab(existing_content: str) -> str:
    return existing_content


def _render_tmpfiles() -> str:
    return "\n".join(
        [
            "d /var/log/fruit-vehicle 0755 root root - -",
            "d /run/fruit-vehicle 0755 root root - -",
            "",
        ]
    )


def _render_daemon_wrapper() -> str:
    return "\n".join(
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "export PYTHONPATH=/opt/fruit-vehicle",
            'exec /usr/bin/python3 -m fruit_vehicle.main "$@"',
            "",
        ]
    )


def _render_systemd_unit() -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=fruit_view vehicle daemon",
            "After=network-online.target",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=simple",
            "ExecStart=/usr/local/bin/fruit-vehicle-daemon",
            "Restart=always",
            "RestartSec=1",
            "WorkingDirectory=/opt/fruit-vehicle",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _render_mediamtx_unit() -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=fruit_view CSI camera RTSP service",
            "After=network-online.target",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=simple",
            "ExecStart=/usr/local/bin/mediamtx /etc/mediamtx.yml",
            "Restart=always",
            "RestartSec=2",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _render_wifi_country_unit(profile: VehicleProfile) -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=Set Wi-Fi country before NetworkManager",
            "After=local-fs.target",
            "Before=NetworkManager.service",
            "ConditionPathExists=!/etc/fruit-wifi-country.done",
            "",
            "[Service]",
            "Type=oneshot",
            f"ExecStart=/usr/bin/raspi-config nonint do_wifi_country {profile.wifi.country_code}",
            "ExecStart=/usr/bin/touch /etc/fruit-wifi-country.done",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _install_mediamtx(root_mount: Path, cache_dir: Path, lock_path: Path) -> None:
    with lock_path.open("rb") as handle:
        lock = tomllib.load(handle)["mediamtx_linux_armv7"]
    archive_path = cache_dir / lock["filename"]
    with tarfile.open(archive_path, "r:gz") as archive:
        member = archive.getmember("mediamtx")
        member.name = "mediamtx"
        archive.extract(member, path=root_mount / "usr" / "local" / "bin")
    (root_mount / "usr" / "local" / "bin" / "mediamtx").chmod(0o755)


def _disable_systemd_unit(root_mount: Path, unit_name: str) -> None:
    wants_dirs = [
        root_mount / "etc" / "systemd" / "system" / "multi-user.target.wants",
        root_mount / "etc" / "systemd" / "system" / "sockets.target.wants",
    ]
    for wants_dir in wants_dirs:
        wants_link = wants_dir / unit_name
        if wants_link.exists() or wants_link.is_symlink():
            wants_link.unlink()

    disabled_dir = root_mount / "etc" / "systemd" / "system"
    disabled_dir.mkdir(parents=True, exist_ok=True)
    masked_unit = disabled_dir / unit_name
    if masked_unit.exists() or masked_unit.is_symlink():
        masked_unit.unlink()
    masked_unit.symlink_to("/dev/null")


def _render_build_manifest(profile: VehicleProfile, source_id: str) -> str:
    return "\n".join(
        [
            f'source_id = "{source_id}"',
            f'profile_name = "{profile.profile_path.stem}"',
            f"vehicle_id = {profile.vehicle_id}",
            f'hostname = "{profile.hostname}"',
            "",
        ]
    )


def _render_custom_toml(profile: VehicleProfile) -> str:
    authorized_keys = ", ".join(
        f'"{key_path.read_text(encoding="utf-8").strip()}"'
        for key_path in profile.admin.authorized_key_paths
    )
    ssh_key_line = (
        f"authorized_keys = [{authorized_keys}]"
        if authorized_keys
        else "authorized_keys = []"
    )
    return "\n".join(
        [
            "config_version = 1",
            "",
            "[system]",
            f'hostname = "{profile.hostname}"',
            "",
            "[user]",
            'name = "pi"',
            f'password = "{profile.admin.password_hash}"',
            "password_encrypted = true",
            "",
            "[ssh]",
            "enabled = true",
            "password_authentication = true",
            ssh_key_line,
            "",
        ]
    )


def _ensure_cmdline_config(boot_mount: Path, profile: VehicleProfile) -> None:
    for candidate in [
        boot_mount / "cmdline.txt",
        boot_mount / "firmware" / "cmdline.txt",
    ]:
        if candidate.exists():
            parts = candidate.read_text(encoding="utf-8").strip().split()
            parts = [part for part in parts if part != "ro"]
            regdom = f"cfg80211.ieee80211_regdom={profile.wifi.country_code}"
            if regdom not in parts:
                parts.append(regdom)
            candidate.write_text(" ".join(parts) + "\n", encoding="utf-8")
            return


def _stage_boot(
    boot_mount: Path, profile: VehicleProfile, runtime_toml: str, manifest_toml: str
) -> None:
    boot_mount.mkdir(parents=True, exist_ok=True)
    boot_vehicle_dir = boot_mount / "fruit-view"
    _write(boot_vehicle_dir / "runtime-settings.toml", runtime_toml)
    _write(boot_vehicle_dir / "build-manifest.toml", manifest_toml)
    _write(boot_mount / "custom.toml", _render_custom_toml(profile))
    _ensure_cmdline_config(boot_mount, profile)


def _stage_root(
    root_mount: Path,
    profile: VehicleProfile,
    runtime_toml: str,
    manifest_toml: str,
    cache_dir: Path,
    lock_path: Path,
) -> None:
    root_boot_dir = _boot_partition_path(root_mount)
    _write(root_boot_dir / "fruit-view" / "runtime-settings.toml", runtime_toml)
    _write(root_boot_dir / "fruit-view" / "build-manifest.toml", manifest_toml)

    existing_fstab = ""
    fstab_path = root_mount / "etc" / "fstab"
    if fstab_path.exists():
        existing_fstab = fstab_path.read_text(encoding="utf-8")

    _write(root_mount / "etc" / "hostname", profile.hostname + "\n")
    _write(root_mount / "etc" / "hosts", _render_hosts(profile.hostname))
    _write(fstab_path, _render_fstab(existing_fstab))
    _write(root_mount / "etc" / "tmpfiles.d" / "fruit-vehicle.conf", _render_tmpfiles())

    _write(
        root_mount / "etc" / "NetworkManager" / "NetworkManager.conf",
        _render_networkmanager_conf(),
    )
    _write(
        root_mount
        / "etc"
        / "NetworkManager"
        / "system-connections"
        / "kaaos.nmconnection",
        _render_nmconnection(profile),
        mode=0o600,
    )
    _write(
        root_mount
        / "etc"
        / "NetworkManager"
        / "system-connections"
        / "fruit-ethernet.nmconnection",
        _render_ethernet_connection(),
        mode=0o600,
    )
    _write(root_mount / "etc" / "mediamtx.yml", _render_mediamtx_config(profile))

    home_ssh = root_mount / "home" / "pi" / ".ssh"
    if profile.admin.authorized_key_paths:
        authorized_keys = "".join(
            key_path.read_text(encoding="utf-8")
            for key_path in profile.admin.authorized_key_paths
        )
        _write(home_ssh / "authorized_keys", authorized_keys, mode=0o600)
        home_ssh.chmod(0o700)

    ssh_dir = root_mount / "etc" / "ssh"
    ssh_dir.mkdir(parents=True, exist_ok=True)
    for key_type in ["rsa", "ecdsa", "ed25519"]:
        key_path = ssh_dir / f"ssh_host_{key_type}_key"
        _run("ssh-keygen", "-q", "-N", "", "-t", key_type, "-f", str(key_path))

    opt_dir = root_mount / "opt" / "fruit-vehicle"
    shutil.copytree(
        ROOT / "src" / "fruit_vehicle", opt_dir / "fruit_vehicle", dirs_exist_ok=True
    )
    _install_mediamtx(root_mount, cache_dir, lock_path)
    _write(
        root_mount / "usr" / "local" / "bin" / "fruit-vehicle-daemon",
        _render_daemon_wrapper(),
        mode=0o755,
    )
    mediamtx_unit = root_mount / "etc" / "systemd" / "system" / "fruit-mediamtx.service"
    _write(mediamtx_unit, _render_mediamtx_unit())
    wifi_country_unit = (
        root_mount / "etc" / "systemd" / "system" / "fruit-wifi-country.service"
    )
    _write(wifi_country_unit, _render_wifi_country_unit(profile))
    unit_path = root_mount / "etc" / "systemd" / "system" / "fruit-vehicle.service"
    _write(unit_path, _render_systemd_unit())
    enabled_dir = root_mount / "etc" / "systemd" / "system" / "multi-user.target.wants"
    enabled_dir.mkdir(parents=True, exist_ok=True)
    enabled_link = enabled_dir / "fruit-vehicle.service"
    if enabled_link.exists() or enabled_link.is_symlink():
        enabled_link.unlink()
    enabled_link.symlink_to(Path("..") / "fruit-vehicle.service")
    mediamtx_link = enabled_dir / "fruit-mediamtx.service"
    if mediamtx_link.exists() or mediamtx_link.is_symlink():
        mediamtx_link.unlink()
    mediamtx_link.symlink_to(Path("..") / "fruit-mediamtx.service")
    wifi_country_link = enabled_dir / "fruit-wifi-country.service"
    if wifi_country_link.exists() or wifi_country_link.is_symlink():
        wifi_country_link.unlink()
    wifi_country_link.symlink_to(Path("..") / "fruit-wifi-country.service")
    _disable_systemd_unit(root_mount, "systemd-rfkill.service")
    _disable_systemd_unit(root_mount, "systemd-rfkill.socket")


def _copy_base_image(lock_path: Path, cache_dir: Path, output_path: Path) -> None:
    with lock_path.open("rb") as handle:
        lock = tomllib.load(handle)["raspios_lite_bookworm_armhf"]
    compressed = cache_dir / lock["filename"]
    with output_path.open("wb") as destination:
        subprocess.run(["xz", "-dc", str(compressed)], check=True, stdout=destination)


def _compress_output(output_path: Path) -> None:
    subprocess.run(["xz", "-zf", "-k", str(output_path)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--lock", required=True)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--dist-dir", required=True)
    parser.add_argument("--source-id", required=True)
    args = parser.parse_args()

    profile = load_profile(args.profile)
    dist_dir = Path(args.dist_dir)
    dist_dir.mkdir(parents=True, exist_ok=True)
    output_path = dist_dir / f"{profile.profile_path.stem}-{args.source_id}.img"
    _copy_base_image(Path(args.lock), Path(args.cache_dir), output_path)
    settings = build_runtime_settings(profile, dry_run=True)
    runtime_toml = render_runtime_settings(settings)
    manifest_toml = _render_build_manifest(profile, args.source_id)
    partitions = _partition_map(output_path)

    with tempfile.TemporaryDirectory() as temp_dir:
        boot_mount = Path(temp_dir) / "boot"
        root_mount = Path(temp_dir) / "root"
        boot_mount.mkdir()
        root_mount.mkdir()
        boot_offset, boot_size = partitions[1]
        root_offset, root_size = partitions[2]
        try:
            _mount_partition(output_path, boot_mount, boot_offset, boot_size)
            _stage_boot(boot_mount, profile, runtime_toml, manifest_toml)
            subprocess.run(["umount", str(boot_mount)], check=True)

            _mount_partition(output_path, root_mount, root_offset, root_size)
            _stage_root(
                root_mount,
                profile,
                runtime_toml,
                manifest_toml,
                Path(args.cache_dir),
                Path(args.lock),
            )
        finally:
            subprocess.run(["sync"], check=False)
            subprocess.run(["umount", str(root_mount)], check=False)
            subprocess.run(["umount", str(boot_mount)], check=False)

    _compress_output(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
