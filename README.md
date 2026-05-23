# fruit_view

FPV telepresence viewer for an RC vehicle. Renders a live wide-angle camera feed onto the inside of a hemisphere. Head tracking via XREAL Air 2 Pro glasses rotates the viewpoint. Gamepad controls throttle and steering over UDP. Telemetry overlays (battery, speed, RSSI, GPS) float on the sphere surface.

Built with Godot 4 / GDScript. Runs on Orange Pi (Linux ARM64) + XREAL Air 2 Pro today; designed to swap to Meta Quest (OpenXR) later with no code changes.

See [PRD.md](PRD.md) for full requirements and design decisions.

---

## Hardware

| Component | Notes |
|---|---|
| Orange Pi 5B (or similar ARM64 SBC) | Runs the Godot app |
| XREAL Air 2 Pro | Connected to Pi via USB-C; appears as a 1920×1080 display |
| Raspberry Pi + wide-angle fisheye lens | Streams RTSP video over local network |
| USB/Bluetooth gamepad | Connected to Orange Pi |

---

## Prerequisites

**Development machine (macOS)**
- Godot 4.6+ with Linux ARM64 export templates installed
  (`Editor → Export Templates → Download and Install`)
- SSH key copied to the Pi (`ssh-copy-id orangepi@<PI_IP>`)

**Orange Pi (one-time setup)**
- Run `~/fruit_view/setup_pi.sh` after the first deploy (installs GStreamer + XRLinuxDriver)
- Run `xr_driver_setup` once to configure OpenTrack UDP output on port 4242

---

## Workflow

### Build and deploy

```bash
# Export Godot project as Linux ARM64 binary:
./deploy/build.sh

# Rsync binary + sidecar + configs to the Pi:
./deploy/deploy.sh

# Or do both in one step:
./deploy/deploy.sh --build
```

By default the Pi is expected at `orangepi@192.168.86.22`. Override with env vars:

```bash
PI_HOST=10.0.0.5 PI_USER=pi ./deploy/deploy.sh --build
```

### One-time Pi setup

```bash
ssh orangepi@192.168.86.22 'bash ~/fruit_view/setup_pi.sh'
# Then on the Pi:
xr_driver_setup   # configure OpenTrack UDP output, port 4242
```

### Launching the app

```bash
# On the Pi:
~/fruit_view/launch.sh

# If the XREAL is not screen 0 (check with: xrandr --listmonitors):
SCREEN=1 ~/fruit_view/launch.sh
```

XRLinuxDriver starts automatically on boot via a systemd user service installed
during setup. To start it manually: `systemctl --user start xr_driver.service`

### Validating head tracking (before launching)

```bash
python3 ~/fruit_view/check_opentrack.py
# Move the glasses — yaw/pitch should change in the terminal output.
# Ctrl+C to stop.
```

---

## Controls

| Input | Action |
|---|---|
| Left stick Y | Throttle |
| Left stick X | Steering |
| **Space** (keyboard) | Recenter head tracking |
| **Back / Select** (gamepad) | Recenter head tracking |

Recentering captures the current head pose as the new forward direction. Use it whenever the view feels misaligned after putting the glasses on.

---

## Configuration

All settings live in `project.godot`. For Orange Pi production, `deploy/override.cfg` is deployed alongside the binary and overrides the relevant keys without a rebuild.

**Tuning without rebuilding**: edit `~/fruit_view/override.cfg` on the Pi directly, then relaunch.

### Key settings

| Setting | Default | Description |
|---|---|---|
| `head_tracker/mode` | `mouse_look` | `mouse_look` (Mac dev) or `opentrack_udp` (Pi) |
| `head_tracker/opentrack_port` | `4242` | UDP port XRLinuxDriver sends to |
| `head_tracker/sensitivity` | `1.0` | Rotation speed multiplier. Increase to look around faster. |
| `video/source` | `local_file` | `local_file` or `rtsp_gstreamer` |
| `video/rtsp_url` | `rtsp://192.168.1.100:8554/stream` | RTSP stream URL from camera Pi |
| `video/sidecar_port` | `9001` | TCP port for the GStreamer sidecar |
| `control/vehicle_host` | `192.168.1.100` | IP of the vehicle Pi |
| `control/vehicle_port` | `9000` | UDP port on the vehicle Pi |
| `telemetry/port` | `9002` | Local UDP port for incoming telemetry |

### override.cfg (Pi production defaults)

```ini
[head_tracker]
mode="opentrack_udp"
opentrack_port=4242
sensitivity=1.0   ; increase for faster movement, e.g. 1.5

[video]
source="rtsp_gstreamer"
rtsp_url="rtsp://192.168.1.100:8554/stream"   ; update to your camera Pi's IP

[control]
vehicle_host="192.168.1.100"   ; update to your vehicle Pi's IP
vehicle_port=9000

[telemetry]
port=9002
```

---

## Network ports

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| 4242 | UDP | in (from XRLinuxDriver) | OpenTrack head tracking |
| 9000 | UDP | out (to vehicle Pi) | Control packets (throttle, steering, head pose) |
| 9001 | TCP | local | GStreamer sidecar → Godot frames |
| 9002 | UDP | in (from vehicle Pi) | Telemetry (battery, speed, RSSI, GPS) |

---

## UDP packet schemas

**Control output** (sent to vehicle Pi every frame, or as keepalive every 0.5 s):

```
[throttle:f32][steering:f32][head_yaw:f32][head_pitch:f32][aux_count:u8][aux[]:f32*]
```

All values little-endian. `aux_count` is 0 unless extended by future features.

**Telemetry input** (28 bytes, received from vehicle Pi):

```
[battery_voltage:f32][speed:f32][signal_rssi:f32][gps_lat:f64][gps_lon:f64]
```

---

## Architecture

```
main.gd  (Node3D)
├── HemisphereMeshBuilder   builds inverted hemisphere mesh at startup
├── hemisphere.gdshader     unlit, cull_disabled; distortion_k1 hook for future calibration
├── HeadTracker  ──────────────────────────────────────────────────────
│   ├── MouseLookTracker        mouse delta accumulation (Mac dev)
│   └── OpenTrackUDPTracker     XRLinuxDriver → OpenTrack UDP 48-byte packets
├── VideoSource  ──────────────────────────────────────────────────────
│   ├── LocalFileSource         wraps VideoStreamPlayer
│   └── RTSPGStreamerSource      spawns video_sidecar.py; receives RGBA frames over TCP
├── ControlOutput / InputHandler ─────────────────────────────────────
│   └── UDPControlOutput        gamepad axes + head pose → UDP binary packet
├── TelemetryInput              UDP listener → battery/speed/RSSI/GPS signals
└── TelemetryPanel (×4)         Label3D nodes at az=42°, el=±10°/±30°
```

All implementations are selected at runtime via `ProjectSettings`; no scene changes
are needed to switch between Mac dev mode and Orange Pi production.

---

## Video pipeline

```
RC vehicle Pi camera
  → GStreamer RTSP server (H.264, RTP/RTSP)
  → video_sidecar.py  [rtspsrc ! rtph264depay ! avdec_h264 ! videoconvert ! RGBA appsink]
  → TCP localhost:9001  (raw RGBA frames: 4-byte width, 4-byte height, width×height×4 pixels)
  → RTSPGStreamerSource  (TCP client; assembles frames into ImageTexture)
  → hemisphere.gdshader  (unlit, equirectangular UV)
```

`video_sidecar.py` is deployed alongside the binary as a separate file (not embedded
in the PCK) so Python can execute it directly.

### Required camera video format

The GStreamer sidecar expects the RTSP stream to contain **H.264 video**.
The pipeline is fixed as: `rtspsrc → rtph264depay → avdec_h264 → videoconvert → RGBA`.

| Property | Requirement |
|---|---|
| Codec | H.264 (AVC) |
| Container / transport | RTP over RTSP (`rtsp://` URL) |
| Resolution | Any — sidecar sends width/height per frame; Godot resizes texture dynamically |
| Frame rate | Any — sidecar drops frames when Godot is behind (`max-buffers=1 drop=true`) |
| Profile | Baseline, Main, or High |
| Colour space | Any — `videoconvert` normalises to RGBA before sending |

H.265 (HEVC), MJPEG, and VP8/VP9 are **not** supported by the current pipeline.
To add support, replace `rtph264depay ! avdec_h264` in `sidecar/video_sidecar.py`.

**Ideal camera setup** (Raspberry Pi + `gst-rtsp-server`):

```bash
gst-launch-1.0 rpicamsrc ! video/x-h264,width=1920,height=1080 \
  ! rtph264pay name=pay0 pt=96 \
  ! udpsink host=0.0.0.0 port=8554
```

Or via `libcamera-vid` piped into a GStreamer RTSP server — any setup that produces
an `rtsp://` URL serving H.264 works.

### Testing without a camera (file mode)

The sidecar also accepts a local video file:

```bash
python3 ~/fruit_view/video_sidecar.py --port 9001 --file /path/to/test.mp4
```

In file mode the pipeline is `filesrc ! decodebin`, so any format GStreamer can decode
(MP4/H.264, MKV, etc.) works. The Godot app reconnects automatically when it detects
the sidecar is listening on port 9001.

---

## Status

| Feature | State |
|---|---|
| Hemisphere mesh + equirectangular UV | Done |
| Unlit shader + distortion_k1 hook | Done |
| Mouse-look head tracker (Mac dev) | Done |
| OpenTrack UDP head tracker (Pi) | Done |
| Head tracking recenter (Space / gamepad Back) | Done |
| Head tracking sensitivity multiplier | Done |
| Local file video source (.ogv via VideoStreamPlayer) | Done |
| RTSP/GStreamer video source (H.264 over RTSP) | Done |
| GStreamer sidecar file mode (any format via decodebin) | Done |
| UDP control output + gamepad input | Done |
| Telemetry input + HUD panels | Done |
| Status overlay (Connecting… / No signal) | Done |
| Linux ARM64 export + deploy toolchain | Done |
| XRLinuxDriver auto-start (systemd) | Done |
| Full hardware stack on Pi + XREAL Air 2 Pro | Done — verified 2026-05-24 |
| End-to-end FPV session (issue #9) | Needs RC vehicle + Pi camera connected |
| OpenXR tracker for Meta Quest | Parked (future) |

---

## Tests

Unit tests use the [GUT](https://github.com/bitwes/Gut) framework. See [tests/README.md](tests/README.md) for setup and how to run headless.

```bash
# Headless test run (from repo root):
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit
```
