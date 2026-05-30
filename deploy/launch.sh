#!/usr/bin/env bash
#
# Launch fruit_view on the Orange Pi.
# Run this ON the Pi after connecting the XREAL Air 2 Pro and starting XRLinuxDriver.
#
# Usage:
#   ./launch.sh                                  # launch on screen 0
#   SCREEN=1 ./launch.sh                         # launch on screen 1
#   RENDERING_DRIVER=opengl3 ./launch.sh         # force desktop GL path
#   DISPLAY_DRIVER=wayland ./launch.sh           # override display backend
#
# Find the right screen index with:
#   xrandr --listmonitors
#
# Env overrides:
#   SCREEN             Godot screen index for the XREAL display   (default: 0)
#   DISPLAY            X11 display to use when launching over SSH (default: :0)
#   XAUTHORITY         Xauthority file to use                     (default: ~/.Xauthority)
#   DISPLAY_DRIVER     Godot display backend                      (default: x11)
#   RENDERING_DRIVER   Godot rendering driver                     (default: opengl3_es)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/fruit_view_linux_arm64"
SCREEN="${SCREEN:-0}"
DISPLAY="${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
DISPLAY_DRIVER="${DISPLAY_DRIVER:-x11}"
RENDERING_DRIVER="${RENDERING_DRIVER:-opengl3_es}"

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
echo "  DISPLAY=$DISPLAY"
echo "  XAUTHORITY=$XAUTHORITY"
echo "  display driver: $DISPLAY_DRIVER"
echo "  rendering driver: $RENDERING_DRIVER"

export DISPLAY
export XAUTHORITY

exec "$BINARY" \
    --display-driver "$DISPLAY_DRIVER" \
    --rendering-driver "$RENDERING_DRIVER" \
    --fullscreen \
    --screen "$SCREEN"
