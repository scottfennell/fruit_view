from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from vehicle_node.image.scripts.validate_image import validate_staged_tree


class ImageValidationTests(unittest.TestCase):
    def test_validate_staged_tree_accepts_required_layout(self) -> None:
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "root"
            boot = Path(temp_dir) / "boot"
            (root / "etc" / "NetworkManager" / "system-connections").mkdir(parents=True)
            (root / "etc" / "systemd" / "system" / "multi-user.target.wants").mkdir(
                parents=True
            )
            (root / "opt" / "fruit-vehicle" / "fruit_vehicle").mkdir(parents=True)
            (root / "etc" / "tmpfiles.d").mkdir(parents=True)
            (root / "etc").mkdir(exist_ok=True)
            boot.mkdir()

            (boot / "custom.toml").write_text("config_version = 1\n", encoding="utf-8")
            (boot / "fruit-view").mkdir()
            (boot / "fruit-view" / "runtime-settings.toml").write_text(
                "schema_version = 1\n", encoding="utf-8"
            )
            (
                root
                / "etc"
                / "NetworkManager"
                / "system-connections"
                / "kaaos.nmconnection"
            ).write_text("", encoding="utf-8")
            (
                root
                / "etc"
                / "NetworkManager"
                / "system-connections"
                / "fruit-ethernet.nmconnection"
            ).write_text("", encoding="utf-8")
            (root / "etc" / "systemd" / "system" / "fruit-vehicle.service").write_text(
                "", encoding="utf-8"
            )
            (root / "etc" / "systemd" / "system" / "fruit-mediamtx.service").write_text(
                "", encoding="utf-8"
            )
            (
                root
                / "etc"
                / "systemd"
                / "system"
                / "multi-user.target.wants"
                / "fruit-vehicle.service"
            ).write_text("", encoding="utf-8")
            (
                root
                / "etc"
                / "systemd"
                / "system"
                / "multi-user.target.wants"
                / "fruit-wifi-country.service"
            ).write_text("", encoding="utf-8")
            (
                root
                / "etc"
                / "systemd"
                / "system"
                / "multi-user.target.wants"
                / "fruit-mediamtx.service"
            ).write_text("", encoding="utf-8")
            (root / "etc" / "mediamtx.yml").write_text("", encoding="utf-8")
            (root / "opt" / "fruit-vehicle" / "fruit_vehicle" / "main.py").write_text(
                "", encoding="utf-8"
            )
            (root / "usr" / "local" / "bin").mkdir(parents=True)
            (root / "usr" / "local" / "bin" / "mediamtx").write_text(
                "", encoding="utf-8"
            )
            (root / "etc" / "tmpfiles.d" / "fruit-vehicle.conf").write_text(
                "", encoding="utf-8"
            )
            (root / "etc" / "fstab").write_text("", encoding="utf-8")

            validate_staged_tree(root, boot)
