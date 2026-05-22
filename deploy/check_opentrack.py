#!/usr/bin/env python3
"""
Diagnostic: listen on UDP port 4242 and print incoming OpenTrack packets.

Run this ON the Orange Pi to confirm XRLinuxDriver is sending head tracking
data before launching fruit_view. Move the glasses and watch yaw/pitch change.
Press Ctrl+C to stop.

Usage:
    python3 check_opentrack.py
    python3 check_opentrack.py --port 4243   # non-default port

OpenTrack payload (48 bytes, all little-endian float64):
    offset  0 : x     (mm translation — unused)
    offset  8 : y     (mm translation — unused)
    offset 16 : z     (mm translation — unused)
    offset 24 : yaw   (degrees, positive = right)
    offset 32 : pitch (degrees, positive = up)
    offset 40 : roll  (degrees — unused initially)
"""

import argparse
import socket
import struct

PAYLOAD_SIZE = 48  # 6 x float64


def main() -> None:
    parser = argparse.ArgumentParser(description="Print OpenTrack UDP packets.")
    parser.add_argument("--port", type=int, default=4242,
                        help="UDP port to listen on (default: 4242)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("0.0.0.0", args.port))
    except OSError as exc:
        print(f"ERROR: cannot bind UDP port {args.port}: {exc}")
        print("  Is something else (e.g. fruit_view) already bound to this port?")
        raise SystemExit(1)

    print(f"Listening on UDP port {args.port} — move the XREAL glasses and watch the values.")
    print("Press Ctrl+C to stop.\n")

    header = f"{'yaw':>10}  {'pitch':>10}  {'roll':>10}  {'x_mm':>10}  {'y_mm':>10}  {'z_mm':>10}"
    print(header)
    print("-" * len(header))

    packet_count = 0
    try:
        while True:
            data, addr = sock.recvfrom(256)
            if len(data) < PAYLOAD_SIZE:
                print(f"  short packet ({len(data)} bytes) from {addr} — skipping")
                continue
            x, y, z, yaw, pitch, roll = struct.unpack_from("<6d", data, 0)
            print(f"{yaw:10.2f}  {pitch:10.2f}  {roll:10.2f}  {x:10.1f}  {y:10.1f}  {z:10.1f}")
            packet_count += 1
    except KeyboardInterrupt:
        print(f"\nStopped. Received {packet_count} packets.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
