#!/usr/bin/env bash
set -euo pipefail
#
# Export the Godot project as a Linux ARM64 binary.
# Run this on your Mac (development machine).
#
# Prerequisites:
#   - Godot 4.3+ installed with the Linux ARM64 export templates
#     (Editor → Export → Manage Export Templates → Download)
#
# Env overrides:
#   GODOT   Path to the Godot 4 binary
#           Searched in order: $GODOT env var, godot4, Godot.app, godot

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- locate Godot binary ---
if [[ -n "${GODOT:-}" ]]; then
    GODOT_BIN="$GODOT"
elif command -v godot4 &>/dev/null; then
    GODOT_BIN="godot4"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
elif command -v godot &>/dev/null; then
    GODOT_BIN="godot"
else
    echo "ERROR: Godot 4 binary not found." >&2
    echo "  Set GODOT=/path/to/godot4, install to /Applications/Godot.app," >&2
    echo "  or put godot4/godot on your PATH." >&2
    exit 1
fi

mkdir -p "$PROJECT_ROOT/build"

echo "Godot:   $GODOT_BIN"
echo "Project: $PROJECT_ROOT"
echo "Output:  $PROJECT_ROOT/build/fruit_view_linux_arm64"
echo ""
echo "Exporting Linux ARM64..."

"$GODOT_BIN" \
    --headless \
    --path "$PROJECT_ROOT" \
    --export-release "Linux ARM64" \
    "$PROJECT_ROOT/build/fruit_view_linux_arm64"

echo ""
echo "Build complete: $PROJECT_ROOT/build/fruit_view_linux_arm64"
echo "Run './deploy/deploy.sh' to push to the Orange Pi."
