#!/usr/bin/env bash
set -euo pipefail
#
# One-time setup for the Orange Pi.
# Run this ON the Pi (not on your Mac).
#
# Installs:
#   - Python 3 + GStreamer Python bindings  (required by video_sidecar.py)
#   - XRLinuxDriver                         (XREAL head tracking -> OpenTrack UDP)
#
# Assumptions: Debian/Ubuntu-based Orange Pi OS (apt available).

echo "=== fruit_view Pi setup ==="
echo ""

# ── 1. Python3 + GStreamer ────────────────────────────────────────────────────
echo "[1/3] Installing Python3 + GStreamer..."
sudo apt-get update -qq
sudo apt-get install -y \
    python3 \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gst-plugins-base-1.0 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-tools \
    gstreamer1.0-rtsp
echo "  GStreamer installed."

# ── 2. Verify GStreamer Python binding ────────────────────────────────────────
echo "[2/3] Verifying GStreamer Python binding..."
python3 - <<'EOF'
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
Gst.init(None)
print("  GStreamer %s OK" % Gst.version_string())
EOF

# ── 3. XRLinuxDriver ──────────────────────────────────────────────────────────
echo "[3/3] Installing XRLinuxDriver (XREAL head tracking)..."
echo "  Source: https://github.com/wheaney/XRLinuxDriver"
echo "  This may take a minute..."
echo ""
# Official install script — review at the URL above before running.
curl -fsSL https://raw.githubusercontent.com/wheaney/XRLinuxDriver/main/scripts/setup_xr_driver.sh | bash
echo "  XRLinuxDriver installed."

echo ""
echo "=== Setup complete ==="
echo ""
echo "Configure XRLinuxDriver to output OpenTrack UDP on port 4242:"
echo "  Run 'xr_driver_setup' and select the OpenTrack output mode."
echo "  The app expects packets on UDP 127.0.0.1:4242 (the driver default)."
echo ""
echo "Verify the XREAL display:"
echo "  xrandr --listmonitors"
echo "  Note which screen index (0, 1, …) is the XREAL Air 2 Pro."
echo "  Pass that index as SCREEN=N when running launch.sh if it is not 0."
echo ""
echo "Test head tracking before launching the app:"
echo "  python3 ~/fruit_view/check_opentrack.py"
echo "  (move the glasses and confirm yaw/pitch change, then Ctrl+C)"
