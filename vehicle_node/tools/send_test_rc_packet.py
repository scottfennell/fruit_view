from __future__ import annotations

import argparse
from pathlib import Path
import socket
import sys
import time

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from vehicle_node.src.fruit_vehicle.packet import encode_control_packet


def main() -> int:
    parser = argparse.ArgumentParser(description="Send a test dry-run RC packet")
    parser.add_argument("--host", default="192.168.86.18")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--vehicle-id", type=int, default=100)
    parser.add_argument("--tick", type=int, default=None)
    parser.add_argument("--left", type=float, default=0.0)
    parser.add_argument("--right", type=float, default=0.0)
    parser.add_argument("--arm", type=float, default=0.0)
    args = parser.parse_args()

    channels = [0.0] * 8
    channels[0] = args.left
    channels[1] = args.right
    channels[4] = args.arm
    tick = int(time.monotonic() * 1000) if args.tick is None else args.tick

    payload = encode_control_packet(args.vehicle_id, tick, channels)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.sendto(payload, (args.host, args.port))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
