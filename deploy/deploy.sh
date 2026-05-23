#!/usr/bin/env bash
set -euo pipefail
#
# Sync the built binary + sidecar + Pi configs to the Orange Pi.
# Run this on your Mac (development machine).
#
# Usage:
#   ./deploy/deploy.sh              # deploy only (binary must already be built)
#   ./deploy/deploy.sh --build      # run build.sh first, then deploy
#
# Env overrides:
#   PI_HOST   Hostname or IP of the Orange Pi   (default: orangepi.local)
#   PI_USER   SSH username on the Pi            (default: orangepi)
#   PI_DIR    Remote deploy directory           (default: fruit_view, relative to ~)
#   GODOT     Path to Godot binary              (passed through to build.sh if used)
#
# After the first deploy, run setup once on the Pi:
#   ssh $PI_USER@$PI_HOST 'bash ~/fruit_view/setup_pi.sh'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PI_HOST="${PI_HOST:-192.168.86.22}"
PI_USER="${PI_USER:-orangepi}"
PI_DIR="${PI_DIR:-fruit_view}"
REMOTE="${PI_USER}@${PI_HOST}"

# --- optional build step ---
if [[ "${1:-}" == "--build" ]]; then
    echo "Building Linux ARM64 binary..."
    "$SCRIPT_DIR/build.sh"
    echo ""
fi

BINARY="$PROJECT_ROOT/build/fruit_view_linux_arm64"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found: $BINARY" >&2
    echo "  Run './deploy/build.sh' first, or use './deploy/deploy.sh --build'." >&2
    exit 1
fi

echo "Target:  ${REMOTE}:~/${PI_DIR}/"
echo ""

# Create remote directory
ssh "$REMOTE" "mkdir -p ~/${PI_DIR}"

# Sync all deploy artefacts:
#   fruit_view_linux_arm64  — main Godot binary (PCK embedded)
#   video_sidecar.py        — GStreamer TCP frame server (must live beside the binary)
#   override.cfg            — Godot project settings override for Pi production
#   launch.sh               — launcher wrapper
#   setup_pi.sh             — one-time dependency installer
#   check_opentrack.py      — diagnostic: prints XRLinuxDriver head tracking packets
rsync -avz --progress \
    "$BINARY" \
    "$PROJECT_ROOT/sidecar/video_sidecar.py" \
    "$SCRIPT_DIR/override.cfg" \
    "$SCRIPT_DIR/launch.sh" \
    "$SCRIPT_DIR/setup_pi.sh" \
    "$SCRIPT_DIR/check_opentrack.py" \
    "${REMOTE}:~/${PI_DIR}/"

# Ensure scripts are executable
ssh "$REMOTE" \
    "chmod +x ~/${PI_DIR}/fruit_view_linux_arm64 \
              ~/${PI_DIR}/launch.sh \
              ~/${PI_DIR}/setup_pi.sh"

echo ""
echo "Deploy complete."
echo ""
echo "--- Next steps ---"
echo ""
echo "One-time Pi setup (if not done yet):"
echo "  ssh ${REMOTE} 'bash ~/${PI_DIR}/setup_pi.sh'"
echo ""
echo "Each session:"
echo "  1. Connect XREAL Air 2 Pro to the Pi via USB-C"
echo "  2. Start XRLinuxDriver:  ssh ${REMOTE} 'xr_driver_start'"
echo "  3. Verify head tracking: ssh ${REMOTE} 'python3 ~/${PI_DIR}/check_opentrack.py'"
echo "     (move the glasses and confirm yaw/pitch values change, then Ctrl+C)"
echo "  4. Launch the app:       ssh ${REMOTE} '~/${PI_DIR}/launch.sh'"
echo "     (or: SCREEN=1 ~/${PI_DIR}/launch.sh  if XREAL is not screen 0)"
