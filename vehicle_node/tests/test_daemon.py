from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from vehicle_node.src.fruit_vehicle.daemon import WifiSignalProvider


class WifiSignalProviderTests(unittest.TestCase):
    def test_reads_real_signal_from_proc_net_wireless_format(self) -> None:
        with TemporaryDirectory() as temp_dir:
            wireless_path = Path(temp_dir) / "wireless"
            wireless_path.write_text(
                "Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n"
                " face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n"
                "wlan0: 0000   51.  -57.  -256        0      0      0      0      0        0\n",
                encoding="utf-8",
            )

            provider = WifiSignalProvider(proc_net_wireless_path=wireless_path)
            self.assertEqual(provider.read_signal_dbm(), -57.0)

    def test_falls_back_when_interface_is_missing(self) -> None:
        with TemporaryDirectory() as temp_dir:
            wireless_path = Path(temp_dir) / "wireless"
            wireless_path.write_text("header only\n", encoding="utf-8")

            provider = WifiSignalProvider(
                proc_net_wireless_path=wireless_path,
                fallback_signal_dbm=-70.0,
            )
            self.assertEqual(provider.read_signal_dbm(), -70.0)
