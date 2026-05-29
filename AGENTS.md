# AGENTS.md — fruit_view

## What this repo is

**fruit_view** is a Godot 4 FPV telepresence viewer for an RC vehicle. It renders a live wide-angle camera feed onto the interior of a hemisphere. The operator wears XREAL Air 2 Pro AR glasses on an Orange Pi SBC; head rotation moves the viewpoint inside the hemisphere. A gamepad controls the vehicle over UDP. Telemetry overlays (battery, speed, RSSI, GPS) float on the sphere surface.

Full viewer requirements: `PRD.md`. Vehicle-node planning: `docs/vehicle-node-prd.md`. User-facing setup and workflow: `README.md`.

---

## Hard constraints — never violate these

- **Engine**: Godot 4.6.3. **Language**: GDScript only — no C#, no GDNative, no GDExtension (yet).
- **Primary runtime**: Orange Pi (Linux ARM64) + XREAL Air 2 Pro via USB-C. SSH host `192.168.86.22`, user `orangepi`.
- **Dev machine**: macOS. Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`.
- **No OpenXR on Orange Pi**. Head tracking comes from XRLinuxDriver → OpenTrack UDP port 4242.
- **Monoscopic only** — XREAL Air 2 Pro is 1920×1080, both eyes same image. Do not introduce stereo rendering.
- **Git SSH alias**: `github.com-scottfennell` — all `git remote` operations already use this. Don't change remotes.
- **GDScript style**: snake_case, `class_name` declarations, `@export` vars, signals over direct coupling. No `get_node()` paths longer than one level.

---

## Architecture

Every subsystem is swappable at runtime via `ProjectSettings`. The factory lives in `scripts/main.gd`.

```
main.gd  (Node3D root)
├── HemisphereMeshBuilder     static build(); 180° equirectangular UV
├── hemisphere.gdshader       unlit, cull_disabled; distortion_k1 hook (unused)
├── HeadTracker  (abstract base: scripts/head_tracking/head_tracker.gd)
│   ├── MouseLookTracker      mouse delta accumulation — Mac dev mode
│   └── OpenTrackUDPTracker   XRLinuxDriver → 48-byte OpenTrack UDP packets
├── VideoSource  (abstract base: scripts/video/)
│   ├── LocalFileSource       wraps VideoStreamPlayer
│   └── RTSPGStreamerSource    spawns video_sidecar.py over TCP port 9001
├── InputHandler              gamepad axes; recenter on Space / JOY_BUTTON_BACK
├── UDPControlOutput          mixes viewer semantics into 8-channel RC UDP packet
├── TelemetryInput            UDP listener → battery/speed/RSSI/GPS signals
└── TelemetryPanel ×4         Label3D nodes on sphere surface
```

### Key abstractions

| File | Role |
|---|---|
| `scripts/head_tracking/head_tracker.gd` | Base class: `get_rotation() → Vector2`, `recenter()` |
| `scripts/video/` | All video source classes |
| `scripts/network/udp_control_output.gd` | Outbound control UDP |
| `scripts/network/telemetry_input.gd` | Inbound telemetry UDP |
| `scripts/input_handler.gd` | Gamepad + keyboard → signals |

---

## Configuration switches (ProjectSettings)

Override on Orange Pi via `~/fruit_view/override.cfg` beside the binary — no rebuild needed.

| Key | Dev default | Pi override |
|---|---|---|
| `head_tracker/mode` | `mouse_look` | `opentrack_udp` |
| `head_tracker/opentrack_port` | `4242` | `4242` |
| `head_tracker/sensitivity` | `1.0` | tunable |
| `video/source` | `local_file` | `rtsp_gstreamer` |
| `video/rtsp_url` | `rtsp://192.168.86.18:8554/stream` | real camera URL |
| `video/sidecar_port` | `9001` | `9001` |
| `control/vehicle_host` | `192.168.86.18` | real vehicle IP |
| `control/vehicle_port` | `9000` | `9000` |
| `control/vehicle_id` | `100` | current `rcmower` profile id |
| `telemetry/port` | `9002` | `9002` |

---

## Deploy workflow

```bash
# Build Linux ARM64 binary + rsync to Pi:
./deploy/deploy.sh --build

# Rsync only (binary already built):
./deploy/deploy.sh

# Override Pi address:
PI_HOST=10.0.0.5 PI_USER=pi ./deploy/deploy.sh
```

Files deployed to `~/fruit_view/` on the Pi:
- Godot binary (exported PCK embedded)
- `override.cfg`
- `video_sidecar.py`
- `setup_pi.sh`, `launch.sh`, `check_opentrack.py`

Launch on Pi: `~/fruit_view/launch.sh` (or `SCREEN=1 ~/fruit_view/launch.sh` for external display).

---

## Tricky implementation details

**Sidecar path resolution** (`scripts/video/rtsp_gstreamer_source.gd`):
`globalize_path("res://...")` does not work in an exported binary with embedded PCK.
Use `_resolve_sidecar_path()`: in-editor → `globalize_path`, in production → `OS.get_executable_path().get_base_dir()`.

**Pitch negation** (`scripts/main.gd`):
OpenTrack positive pitch = up. Godot Camera3D positive rotation.x = down.
Pitch is negated at the camera application layer (`-rot.x`), not inside the tracker.

**Recenter implementation** (`scripts/head_tracking/opentrack_udp_tracker.gd`):
Captures current `_yaw`/`_pitch` as an offset. Subsequent `get_rotation()` subtracts the offset.
This works without any driver API call.

**Shader UV debug grid** (`shaders/hemisphere.gdshader`):
When `video_texture` is the default white (`r+g+b >= 2.99`), the shader draws a procedural blue/orange UV grid. It disappears automatically when live video arrives.

**project.godot key**: `run/main_scene` (not `config/main_scene` — the editor will silently ignore the wrong key).

**XRLinuxDriver**:
- Binary: `~/.local/bin/xrDriver`; CLI: `~/.local/bin/xr_driver_cli`
- Systemd user service: `~/.config/systemd/user/xr_driver.service` (enabled, starts on login)
- Log: `~/.local/state/xr_driver/driver.log`
- `libcarina_vio.so` is in `~/.local/share/xr_driver/lib/`; `/etc/ld.so.conf.d/xr_driver.conf` + `ldconfig` exposes it

**OpenTrack packet format**: 6×`float64` LE, 48 bytes total. Yaw at offset 24, pitch at offset 32 (degrees).

**Video format requirements** (`sidecar/video_sidecar.py`):
The GStreamer sidecar pipeline is fixed as:
```
rtspsrc location="<URL>" latency=0 protocols=tcp
  ! rtph264depay ! avdec_h264 ! videoconvert ! video/x-raw,format=RGBA ! appsink
```
- **Required codec**: H.264 (AVC). H.265, MJPEG, VP8/VP9 are not supported without modifying the pipeline.
- **Transport**: RTP over RTSP (`rtsp://` URL). TCP transport forced (`protocols=tcp`).
- **Resolution / frame rate**: any — the sidecar writes width/height into each frame header; Godot resizes `ImageTexture` on resolution change.
- **File mode** (`--file`): uses `filesrc ! decodebin`, so any GStreamer-decodable format works (MP4/H.264 confirmed on Orange Pi with `gstreamer1.0-libav` installed).
- `LocalFileSource` (in-editor only): Godot's `VideoStreamPlayer` supports `.ogv` (Ogg Theora) only.

---

## Current status

| Feature | State |
|---|---|
| Hemisphere mesh + UV | Done |
| Unlit shader + distortion hook | Done |
| Mouse-look tracker (Mac dev) | Done |
| OpenTrack UDP tracker (Pi) | Done |
| Recenter + sensitivity | Done |
| Local file video source | Done |
| RTSP/GStreamer video source | Done |
| UDP control output + gamepad | Done |
| Telemetry input + HUD | Done |
| TelemetryPanelLayout config resource | Done |
| Status overlay (Connecting… / No signal) | Done |
| Linux ARM64 export + deploy | Done |
| XRLinuxDriver systemd service | Done |
| GStreamer on Orange Pi | Done — `gstreamer1.0-libav` installed; pipeline verified |
| GUT test framework | Done — v9.6.0, 47/47 tests passing |
| Full hardware stack verified (#6) | Done — fullscreen on XREAL, head tracking live, video on hemisphere confirmed 2026-05-24 |
| End-to-end FPV session (#9) | Needs RC vehicle + Pi camera physically connected |
| OpenXR tracker (Meta Quest) | Parked — future work |

### Remaining hardware-only steps (issue #9)

### Vehicle node planning

Vehicle-side Raspberry Pi work is now tracked in-repo, but it is still a separate subsystem from the Godot viewer code described above.

- PRD: `docs/vehicle-node-prd.md`
- Issues: `#10` through `#14`
- Important: the viewer now emits the same fixed-length 8-channel RC packet as the vehicle node. The migration boundary is that the viewer still owns semantic input mixing (`throttle/steering/head pose`) before serializing RC channels.

Issue #6 is fully closed. The remaining work requires RC vehicle + camera:

1. Connect Pi camera to RC vehicle
2. Start RTSP stream from camera
3. Run `launch.sh` and verify live RTSP feed on hemisphere with head tracking

**ARM64 rendering note**: Vulkan is unavailable on RK3588 via X11 (VK_KHR_surface missing). Godot falls back to OpenGL 3 automatically. libGL rockchip/rknpu DRI errors appear in the log but rendering works correctly.

**XRLinuxDriver**: Systemd service shows restart-loop errors only because the already-running daemon (PID stable since boot) prevents a second instance — the first instance is fine. OpenTrack UDP target is `127.0.0.1:4242`.

---

## Tests

Uses the [GUT](https://github.com/bitwes/Gut) framework. v9.6.0 is checked in at `addons/gut/`.

```bash
# Headless run:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit
```

Test files live in `tests/unit/`.

---

## Agent skills

### Issue tracker

Issues live in GitHub Issues at `github.com/scottfennell/fruit_view`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: one `CONTEXT.md` + `docs/adr/` at the root. See `docs/agents/domain.md`.
