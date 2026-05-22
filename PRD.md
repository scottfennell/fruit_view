# PRD: XR Space — FPV Telepresence Viewer

## Problem Statement

Operating a remote RC vehicle from a standard screen provides a flat, low-immersion view that makes spatial awareness difficult. The operator cannot naturally look around the vehicle's environment, cannot get an intuitive sense of scale and direction, and has no ergonomic way to monitor vehicle telemetry without breaking focus from the video feed. Existing FPV solutions either require expensive proprietary hardware stacks or fail to provide a comfortable, extensible platform for a home-built telepresence system.

## Solution

A Godot 4 application that renders the RC vehicle's wide-angle camera feed onto the interior of a hemisphere, allowing the operator to look around the environment naturally using XREAL Air 2 Pro glasses and head tracking. Gamepad input is relayed to the vehicle over UDP. Vehicle telemetry is displayed as text panels anchored at fixed positions on the sphere surface. The application is designed around swappable abstractions so it runs on an Orange Pi (Linux ARM64) with XRLinuxDriver head tracking today, and on Meta Quest via OpenXR in the future, with minimal divergence.

## User Stories

1. As an operator, I want the RC vehicle's camera feed mapped onto the inside of a hemisphere, so that I can look around the environment naturally without any flat-screen cropping.
2. As an operator, I want my head rotation to move my viewpoint within the hemisphere, so that glancing left or right shows the corresponding part of the wide-angle feed.
3. As an operator, I want the video feed to fill the front 180° of my field of view, so that the wide-angle lens provides maximum situational awareness.
4. As an operator, I want to control the RC vehicle with a gamepad, so that I have precise throttle and steering control without needing to look at a separate interface.
5. As an operator, I want gamepad input to be relayed to the vehicle over UDP, so that the control path is low-latency and works on any local network.
6. As an operator, I want vehicle telemetry (battery, speed, signal strength, GPS) displayed as text panels anchored on the sphere surface, so that I can read status information without breaking my view of the camera feed.
7. As an operator, I want the telemetry panels to update in real time from a UDP data stream sent by the vehicle, so that I always have current vehicle state.
8. As an operator, I want head yaw and pitch included in the outgoing UDP control packet, so that a future gimbal can physically follow my gaze.
9. As an operator, I want the application to connect to the vehicle's RTSP stream by URL, so that no special software installation is required on the viewing machine beyond the Godot application.
10. As an operator, I want to substitute a local video file for the RTSP stream during development and testing, so that I can work without the vehicle being powered on.
11. As an operator, I want the application to run fullscreen on the XREAL Air 2 Pro display connected via USB-C, so that the hemisphere fills the glasses' field of view.
12. As an operator, I want head tracking to be sourced from XRLinuxDriver's OpenTrack UDP output, so that I can use the glasses' built-in IMU without requiring an OpenXR runtime on the Orange Pi.
13. As a developer, I want a mouse-look fallback head tracker, so that I can develop and test the application on a Mac without XREAL glasses attached.
14. As a developer, I want the head tracker implementation to be swappable at runtime via configuration, so that the same Godot project runs on Orange Pi (OpenTrack UDP) and Meta Quest (OpenXR) without code changes.
15. As a developer, I want the video source to be swappable at runtime, so that RTSP and local file sources can be toggled via a configuration value.
16. As a developer, I want the hemisphere UV mapping to be correct for equirectangular 180° video, so that the image maps cleanly onto the sphere surface without distortion correction for now.
17. As a developer, I want a shader hook on the hemisphere mesh for future lens distortion correction, so that OpenCV calibration coefficients can be applied without restructuring the scene.
18. As a developer, I want all outbound UDP control packets to follow a fixed schema (throttle, steering, head_yaw, head_pitch, aux[]), so that the vehicle-side firmware has a stable interface regardless of future client changes.
19. As a developer, I want all inbound telemetry packets to follow a fixed schema, so that the telemetry display layer does not need to know about network details.
20. As an operator, I want the sphere coordinate system to remain fixed while the video texture's origin tracks gimbal orientation (when available), so that fast head movements can look ahead of where the gimbal is pointing and the view snaps to the gimbal as it catches up.
21. As an operator, I want a static 16:9 video input to appear as a flat panel placed at a fixed point on the sphere surface, so that the same application handles both 180° immersive feeds and conventional flat video.
22. As an operator, I want the application to handle a dropped RTSP connection gracefully, showing a clear status indicator rather than crashing, so that brief network interruptions do not end the session.
23. As an operator, I want the application to attempt to reconnect to the RTSP stream automatically after a dropped connection, so that I do not need to restart the application after a brief signal loss.
24. As a developer, I want the application to export to Linux ARM64 from the Godot editor on macOS, so that I can iterate on a Mac and deploy to the Orange Pi without a separate build machine.

## Implementation Decisions

### Language and Engine
- Godot 4, GDScript throughout. No C#.
- Linux ARM64 is the primary export target. macOS is the development and secondary test platform.
- No OpenXR runtime is required on the Orange Pi. The application runs as a regular fullscreen Godot window on the XREAL display.

### Head Tracking Abstraction (`HeadTracker`)
- Abstract base class exposing `get_rotation() → Vector3` (yaw, pitch, roll in radians).
- `OpenTrackUDPTracker`: binds a UDP socket, receives 48-byte OpenTrack payloads (6 × float64: x, y, z, yaw, pitch, roll) from XRLinuxDriver on a configurable port (default 4242). Only yaw and pitch are used initially.
- `OpenXRTracker`: uses Godot's `XRServer` to read head pose from an OpenXR runtime. Intended for Meta Quest.
- `MouseLookTracker`: accumulates relative mouse motion for development on Mac.
- Active implementation selected via a project setting or environment variable at startup.

### Video Pipeline (`VideoSource`)
- Abstract base class exposing `get_texture() → Texture2D`, updated each frame.
- `RTSPGStreamerSource`: spawns an external GStreamer process (`gst-launch-1.0`) with an RTSP source pipeline. Decoded raw frames are written to a Unix domain socket. A background thread in Godot reads frames from the socket and uploads them to an `ImageTexture`. RTSP URL is configurable.
- `LocalFileSource`: wraps Godot's built-in `VideoStreamPlayer`. Used for development and offline testing. File path is configurable.
- Active implementation selected via a project setting.

### Hemisphere Geometry (`HemisphereMesh`)
- A programmatically generated inverted hemisphere mesh (normals facing inward, toward the camera at the origin).
- UV mapping corresponds to equirectangular 180° projection: U maps linearly to azimuth [−90°, +90°], V maps linearly to elevation [−90°, +90°].
- Accepts a `Texture2D` from `VideoSource` and applies it as the surface material.
- Exposes a shader parameter for future lens distortion coefficients (initially identity / no-op).
- Radius is configurable; default sized so the panels and camera sit comfortably inside.

### Camera (`SphericalCamera`)
- A `Camera3D` placed at the origin (centre of the hemisphere).
- Each `_process` frame: reads `HeadTracker.get_rotation()` and applies yaw and pitch as the camera's rotation. Roll ignored initially.
- When gimbal feedback is available (future): an additional rotation offset derived from gimbal orientation is composed with head rotation before application.

### Control Output (`ControlOutput`)
- Abstract base class exposing `send(throttle: float, steering: float, head_yaw: float, head_pitch: float, aux: Array)`.
- `UDPControlOutput`: serialises arguments into a fixed binary UDP packet and sends to a configurable IP:port. Packet schema: `[throttle: f32, steering: f32, head_yaw: f32, head_pitch: f32, aux_count: u8, aux[]: f32[]]`.
- Packet is sent each frame that input is active; a zero-throttle keepalive is sent at a configurable interval when no input is held.

### Telemetry Input (`TelemetryInput`)
- Binds a UDP socket on a configurable port.
- Parses incoming telemetry packets (schema TBD, but includes at minimum: battery_voltage, speed, signal_rssi, gps_lat, gps_lon).
- Emits a Godot signal per field on each received packet (e.g. `battery_voltage_changed(value: float)`).
- `TelemetryPanel` nodes subscribe to these signals and update their `Label3D` text.

### Input Handling (`InputHandler`)
- Reads `InputEventJoypadMotion` and `InputEventJoypadButton` each frame via Godot's `Input` singleton.
- Maps left stick Y → throttle, left stick X → steering (axis mapping configurable).
- Reads `HeadTracker.get_rotation()` for head_yaw and head_pitch.
- Calls `ControlOutput.send(...)` each frame.

### Telemetry Panels
- Each `TelemetryPanel` is a flat quad `MeshInstance3D` placed at a fixed spherical coordinate (radius, azimuth, elevation), rotated to face the origin.
- Text rendered via `Label3D` or a `SubViewport` with a `RichTextLabel`.
- Panel positions are defined in a configuration resource so they can be repositioned without code changes.

### Network Architecture
- All UDP sockets managed via Godot's `PacketPeerUDP`.
- Outbound: one socket for control packets (to vehicle Pi).
- Inbound: two sockets — one for OpenTrack head tracking (from XRLinuxDriver), one for telemetry (from vehicle Pi).
- Ports and IPs configurable via a `config.ini` or Godot project settings.

### Mac Development Mode
- `MouseLookTracker` active when no OpenTrack UDP source is configured.
- `LocalFileSource` active when no RTSP URL is configured.
- `UDPControlOutput` still functional if vehicle Pi is reachable on the same network.
- Application runs in a standard desktop window (not fullscreen) on Mac.

## Testing Decisions

### What makes a good test
Tests should validate observable external behaviour only — inputs in, outputs or signals out. No test should assert on internal state, private methods, or implementation details. Tests should be runnable headlessly (no display, no hardware attached).

### Modules to test

**`HeadTracker` (all implementations)**
- `OpenTrackUDPTracker`: send a crafted 48-byte UDP packet to the bound port; assert `get_rotation()` returns the expected yaw/pitch values.
- `MouseLookTracker`: inject synthetic `InputEventMouseMotion`; assert `get_rotation()` accumulates correctly.
- `OpenXRTracker`: mock `XRServer` pose; assert `get_rotation()` returns the transformed value.

**`VideoSource`**
- `RTSPGStreamerSource`: mock the Unix socket with a pre-recorded frame sequence; assert `get_texture()` returns an updated `ImageTexture` with the correct dimensions and pixel data.
- `LocalFileSource`: load a known test `.ogv` file; assert `get_texture()` is non-null after playback begins.

**`TelemetryInput`**
- Send a crafted UDP telemetry packet to the bound port; assert the correct signals are emitted with the correct values.
- Send a malformed packet; assert no signal is emitted and no crash occurs.

**`ControlOutput`**
- `UDPControlOutput`: call `send(...)` with known values; capture the outgoing UDP packet bytes; assert the binary layout matches the defined schema exactly.
- Assert a zero-throttle keepalive packet is sent after the configured idle interval.

### Testing tool
Godot's built-in `GUT` (Godot Unit Test) framework, or equivalent lightweight GDScript test harness.

## Out of Scope

- Lens distortion correction (calibration coefficients, OpenCV pipeline). Shader hook is included; calibration workflow is not.
- Gimbal hardware integration and gimbal orientation feedback loop. Head pose is already included in the control packet; the vehicle-side gimbal driver is out of scope.
- Stereo / side-by-side rendering for Meta Quest. The current monoscopic rendering pipeline will be adapted when Meta Quest is targeted; it is not designed now.
- WebRTC or WebXR delivery. RTSP/RTP over local network only.
- Multi-operator or shared-session support.
- Autonomous vehicle control or waypoint navigation.
- Video recording or DVR functionality.
- Android build. Orange Pi Linux ARM64 is the only non-Mac target at this stage.
- XREAL NRSDK / Android XREAL integration.
- Any Pi-side software (GStreamer pipeline, RC control firmware, telemetry transmitter). Those are separate projects.

## Further Notes

- The XREAL Air 2 Pro exhibits IMU drift under XRLinuxDriver (noted in the driver's own documentation). A drift-correction UI gesture or recalibration hotkey should be considered in a follow-up.
- The Orange Pi is ARM64. Godot 4 ARM64 Linux exports are functional but less battle-tested than x86_64. Export template compatibility should be validated early as a spike before full development begins.
- XRLinuxDriver marks XREAL support as not recommended (👎) due to XREAL's unwillingness to collaborate and the unofficial SDK. Monitor the driver project for regressions after XREAL firmware updates.
- The GStreamer sidecar process approach is Linux-specific. When Android targets are introduced, this will need to be replaced with a GDExtension wrapping libavcodec or a similar cross-platform video decode library. The `VideoSource` abstraction isolates this change to one implementation class.
- OpenTrack UDP payload format: 6 × `double` (little-endian), fields in order: `x, y, z, yaw, pitch, roll`. Values are in millimetres (x/y/z) and degrees (yaw/pitch/roll).
