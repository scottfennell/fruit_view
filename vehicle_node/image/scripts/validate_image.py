from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def _assert_exists(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"expected path missing: {path}")


def _partition_map(image_path: Path) -> dict[int, tuple[int, int]]:
    output = subprocess.run(
        ["parted", "-s", str(image_path), "unit", "B", "print"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    partitions: dict[int, tuple[int, int]] = {}
    for line in output.splitlines():
        match = re.match(r"\s*(\d+)\s+(\d+)B\s+(\d+)B\s+(\d+)B\s+", line)
        if match is None:
            continue
        partitions[int(match.group(1))] = (int(match.group(2)), int(match.group(4)))

    if 1 not in partitions or 2 not in partitions:
        raise SystemExit(f"failed to read expected partition layout from {image_path}")
    return partitions


def _mount_partition(
    image_path: Path, mount_path: Path, offset: int, size: int, read_only: bool
) -> None:
    options = ["loop", f"offset={offset}", f"sizelimit={size}"]
    if read_only:
        options.insert(0, "ro")
    subprocess.run(
        ["mount", "-o", ",".join(options), str(image_path), str(mount_path)],
        check=True,
    )


def validate_staged_tree(root_mount: Path, boot_mount: Path) -> None:
    _assert_exists(boot_mount / "custom.toml")
    _assert_exists(boot_mount / "fruit-view" / "runtime-settings.toml")
    _assert_exists(
        root_mount
        / "etc"
        / "NetworkManager"
        / "system-connections"
        / "kaaos.nmconnection"
    )
    _assert_exists(
        root_mount
        / "etc"
        / "NetworkManager"
        / "system-connections"
        / "fruit-ethernet.nmconnection"
    )
    _assert_exists(root_mount / "etc" / "mediamtx.yml")
    _assert_exists(root_mount / "etc" / "systemd" / "system" / "fruit-vehicle.service")
    _assert_exists(root_mount / "etc" / "systemd" / "system" / "fruit-mediamtx.service")
    _assert_exists(
        root_mount
        / "etc"
        / "systemd"
        / "system"
        / "multi-user.target.wants"
        / "fruit-vehicle.service"
    )
    _assert_exists(
        root_mount
        / "etc"
        / "systemd"
        / "system"
        / "multi-user.target.wants"
        / "fruit-wifi-country.service"
    )
    _assert_exists(
        root_mount
        / "etc"
        / "systemd"
        / "system"
        / "multi-user.target.wants"
        / "fruit-mediamtx.service"
    )
    _assert_exists(root_mount / "usr" / "local" / "bin" / "mediamtx")
    _assert_exists(root_mount / "opt" / "fruit-vehicle" / "fruit_vehicle" / "main.py")
    _assert_exists(root_mount / "etc" / "tmpfiles.d" / "fruit-vehicle.conf")
    _assert_exists(root_mount / "etc" / "fstab")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image")
    parser.add_argument("--root-dir")
    parser.add_argument("--boot-dir")
    args = parser.parse_args()

    if args.root_dir and args.boot_dir:
        validate_staged_tree(Path(args.root_dir), Path(args.boot_dir))
        return 0

    if not args.image:
        raise SystemExit(
            "either --image or both --root-dir and --boot-dir are required"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        image_path = Path(args.image)
        partitions = _partition_map(image_path)
        boot_mount = Path(temp_dir) / "boot-mount"
        boot_copy = Path(temp_dir) / "boot-copy"
        root_mount = Path(temp_dir) / "root"
        boot_mount.mkdir()
        boot_copy.mkdir()
        root_mount.mkdir()
        boot_offset, boot_size = partitions[1]
        root_offset, root_size = partitions[2]
        try:
            _mount_partition(
                image_path, boot_mount, boot_offset, boot_size, read_only=True
            )
            shutil.copytree(boot_mount, boot_copy, dirs_exist_ok=True)
            subprocess.run(["umount", str(boot_mount)], check=True)

            _mount_partition(
                image_path, root_mount, root_offset, root_size, read_only=True
            )
            validate_staged_tree(root_mount, boot_copy)
        finally:
            subprocess.run(["umount", str(root_mount)], check=False)
            subprocess.run(["umount", str(boot_mount)], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
