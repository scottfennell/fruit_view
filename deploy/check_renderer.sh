#!/usr/bin/env bash
set -euo pipefail

# Diagnose which graphics path the Orange Pi is actually using.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/fruit_view_linux_arm64"
DISPLAY="${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
DISPLAY_DRIVER="${DISPLAY_DRIVER:-x11}"
RENDERING_DRIVER="${RENDERING_DRIVER:-opengl3_es}"

if [[ ! -x "$BINARY" ]]; then
    echo "ERROR: binary not found or not executable: $BINARY" >&2
    exit 1
fi

export DISPLAY
export XAUTHORITY

echo "=== fruit_view renderer check ==="
echo "DISPLAY=$DISPLAY"
echo "XAUTHORITY=$XAUTHORITY"
echo "DISPLAY_DRIVER=$DISPLAY_DRIVER"
echo "RENDERING_DRIVER=$RENDERING_DRIVER"
echo ""

if command -v glxinfo >/dev/null 2>&1; then
    echo "--- glxinfo -B ---"
    glxinfo -B || true
    echo ""
fi

if command -v es2_info >/dev/null 2>&1; then
    echo "--- es2_info ---"
    es2_info | grep -E 'EGL_VERSION|EGL_VENDOR|GL_VERSION|GL_RENDERER' || true
    echo ""
fi

if pgrep -f "[f]ruit_view_linux_arm64" >/dev/null 2>&1; then
    echo "--- Godot startup probe ---"
    echo "Skipping probe because fruit_view is already running."
    echo "Stop the app and rerun this script if you want a clean startup log."
    exit 0
fi

echo "--- Godot startup probe ---"
"$BINARY" \
    --display-driver "$DISPLAY_DRIVER" \
    --rendering-driver "$RENDERING_DRIVER" \
    --quit-after 1
