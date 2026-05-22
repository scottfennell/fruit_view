#!/usr/bin/env bash
#
# Launch fruit_view on the Orange Pi.
# Run this ON the Pi after connecting the XREAL Air 2 Pro and starting XRLinuxDriver.
#
# Usage:
#   ./launch.sh               # launch on screen 0
#   SCREEN=1 ./launch.sh      # launch on screen 1 (if XREAL is not the primary display)
#
# Find the right screen index with:
#   xrandr --listmonitors
#
# Env overrides:
#   SCREEN   Godot screen index for the XREAL display  (default: 0)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/fruit_view_linux_arm64"
SCREEN="${SCREEN:-0}"

if [[ ! -x "$BINARY" ]]; then
    echo "ERROR: binary not found or not executable: $BINARY" >&2
    exit 1
fi

# Confirm XRLinuxDriver is likely running by checking for an OpenTrack listener.
if ! ss -ulnp 2>/dev/null | grep -q ":4242 "; then
    echo "WARNING: nothing appears to be listening on UDP 4242."
    echo "  Head tracking may not work. Start XRLinuxDriver with: xr_driver_start"
    echo "  Continuing anyway..."
    echo ""
fi

echo "Launching fruit_view on screen $SCREEN..."
exec "$BINARY" --screen "$SCREEN"
