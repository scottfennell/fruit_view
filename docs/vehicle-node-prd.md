# PRD: Raspberry Pi Vehicle Node

## Problem Statement

The current repo defines the viewer side of the FPV system, but the Raspberry Pi that lives on the RC vehicle is still implicit. That leaves several critical concerns unresolved: how the vehicle boots into a usable state, how camera streaming is exposed, how control packets are received and translated into hardware output, how telemetry is produced, and how the system survives repeated hard power cycles without corrupting storage.

The vehicle node needs to behave like a small appliance rather than a general-purpose Linux machine. It should be reproducible from a local command-line workflow, personalized per vehicle, SSH-administerable, resilient to abrupt power loss, and compatible with a future shared RC-style control model that can extend beyond this tracked vehicle.

## Solution

Build a Raspberry Pi 3 A+ vehicle-node image generator inside this repo. The generator produces a fully personalized Raspberry Pi OS Lite 32-bit image for one vehicle profile. That image boots directly into a read-only appliance with:

- Wi-Fi client networking and a true static IP
- SSH access for administration
- a CSI-camera RTSP service using `libcamera` plus a pinned off-the-shelf RTSP server
- one Python vehicle daemon handling control, telemetry, session state, and GPIO-based ESC output
- RAM-backed runtime state and logs so abrupt power loss does not damage the system

The long-term control boundary becomes a generic 8-channel RC-style UDP protocol, with vehicle-specific interpretation handled by a typed per-vehicle profile.

## Goals

1. Generate a fully flashable Raspberry Pi image locally from a single high-level command.
2. Keep real per-vehicle secrets and network settings out of git.
3. Make the flashed system boot directly into a working appliance with no interactive setup.
4. Keep root and boot read-only during normal operation.
5. Stream camera video over RTSP to the existing viewer architecture.
6. Run the first tracked-vehicle control stack directly on the Pi using two ESC outputs.
7. Preserve a clean path toward a shared RC-channel protocol for future vehicles and transports.
8. Document the target protocol and profile contracts clearly enough that the viewer can migrate afterward.

## Non-Goals

1. On-device package upgrades or in-place software updates. Reflashing is the update path.
2. Persistent local logs or mutable local configuration during normal operation.
3. GPS, battery sensing, or speed sensing in v1.
4. RTSP authentication in v1.
5. Multi-operator support.
6. ELRS, MAVLink, aircraft profiles, or USB VRX input in v1.
7. A general recovery shell or recovery partition. Reflash is recovery.

## Primary User Stories

1. As an operator, I want the vehicle Pi to power on and immediately begin providing camera streaming and control services so I can drive without a manual Linux bring-up step.
2. As an operator, I want the vehicle node to survive frequent hard power cuts without SD-card corruption so the system behaves like embedded hardware.
3. As an operator, I want to administer the vehicle node over SSH so I can inspect and debug it without attaching local peripherals.
4. As a developer, I want one canonical per-vehicle profile so the image builder and viewer can derive their configs from the same source of truth.
5. As a developer, I want the image build to fail hard on invalid profile data so broken images are caught before flashing.
6. As a developer, I want the control protocol to move toward generic RC channels so the system can later support non-tracked vehicles and alternate controller transports.
7. As a developer, I want a dry-run mode so I can validate the control daemon and session safety logic without energizing the drivetrain.

## Target Platform

### Hardware

- Raspberry Pi 3 A+
- CSI camera module
- two brushed-motor ESCs, one per track
- Wi-Fi client on an existing LAN
- optional wired Ethernet fallback via compatible adapter

### OS and Build Environment

- Base image: Raspberry Pi OS Lite 32-bit, Bookworm, exact version pinned
- Image generation environment: Docker-based Linux environment, invoked locally
- Image output: validated `.img` plus compressed `.img.xz`

## System Overview

The vehicle-node subsystem consists of four layers:

1. Canonical per-vehicle profile
2. Image-generation pipeline
3. Boot-time system services
4. Runtime control and telemetry behavior

### Canonical Vehicle Profile

Each vehicle has one explicit TOML profile kept outside git under a local ignored directory. Checked-in example profiles define the expected schema.

The profile is the source of truth for:

- schema version
- stable `vehicle_id`
- vehicle type, initially `tracked`
- hostname
- Wi-Fi country code, SSID, password, and static-IP settings
- optional admin public key paths
- camera orientation and streaming settings
- tracked-vehicle channel mapping and GPIO assignments
- per-ESC pulse calibration, deadband, and ramp settings
- generated viewer connection details such as RTSP host

Profiles are fully explicit and strictly validated. Unknown fields are rejected.

### Image Generator

The repo exposes one high-level build command that:

1. validates the selected vehicle profile
2. checks for a clean git tree by default, with explicit override support
3. auto-downloads missing pinned upstream artifacts
4. patches a pinned Raspberry Pi OS Lite base image
5. embeds the current checked-out repo state for vehicle-side code
6. generates per-profile SSH host keys at build time
7. renders the canonical runtime settings file onto the boot partition
8. stages systemd services, camera server binary, Python runtime files, and network config
9. validates the resulting image contents
10. emits both raw and compressed image artifacts named with the vehicle profile and source identifier

Validation is filesystem-content validation only in v1. The build does not attempt automated boot testing.

## Boot and Filesystem Model

### Appliance Behavior

- system boots directly into services, not an interactive desktop session
- root partition is read-only in normal operation
- boot partition is read-only in normal operation
- runtime writable paths use RAM-backed state
- local logs are RAM-only and disappear on reboot
- normal time sync is enabled

### Update and Recovery Model

- configuration changes happen on the development machine
- software updates happen by rebuilding and reflashing the SD card
- recovery from corruption or misconfiguration is also done by reflashing

## Networking Model

### Wi-Fi

- joins an existing Wi-Fi network
- uses a true static IP configured on the Pi itself
- requires explicit Wi-Fi country code in each profile
- uses `NetworkManager` on Bookworm

### Wired Fallback

- wired fallback is allowed
- wired networking uses DHCP

### Administration Surface

- SSH only in v1
- `pi` user retained
- password login allowed
- `authorized_keys` also installed from local public key files
- per-profile host keys are precomputed during image generation

## Camera and Streaming

### Requirements

- CSI camera input
- hardware H.264 encoding required
- optimize for low latency rather than maximum quality
- first target is a modest low-latency preset such as 720p at 30 fps

### Architecture

- use the modern `libcamera` stack
- use a pinned off-the-shelf single-binary RTSP server
- RTSP stream is open on the LAN in v1
- RTSP server runs as its own `systemd` service
- camera service starts at boot and retries until networking is available
- control remains independent of camera health

Camera orientation, resolution, frame rate, bitrate, and related stream tuning live in the per-vehicle profile with repo defaults.

## Control Protocol Target

The existing viewer currently emits semantic `throttle + steering + head pose` packets. This vehicle-node work targets a documented successor protocol while allowing the viewer migration to happen afterward.

### Protocol Direction

- migrate toward generic RC channels
- controller-side mixing remains responsible for vehicle semantics
- tracked vehicle consumes direct left and right track channels

### Wire-Level Intent

- transport: unicast UDP
- fixed repo-wide control port
- small protocol header
- target `vehicle_id` included in the packet
- sender monotonic timestamp/tick included for freshness ordering
- fixed-length payload of 8 signed float channels in `[-1.0, 1.0]`
- LAN trust is acceptable for v1; no shared-secret authentication yet

Exact binary field layout remains an implementation detail, but the contract above is part of the target PRD.

## Tracked Vehicle Control Profile

### Channel Mapping

- `ch1`: left track
- `ch2`: right track
- `ch3`: camera pan / future gimbal yaw
- `ch4`: camera tilt / future gimbal pitch
- `ch5`: arm switch
- `ch6`: mode / spare
- `ch7`: spare
- `ch8`: spare

`ch3` and `ch4` are included in the mapping now even though the first hardware image does not actively drive them.

### Output Hardware

- one ESC output per track
- direct GPIO-driven PWM generation on the Pi
- use a dedicated timing-capable GPIO/PWM stack
- left and right ESCs each have explicit profile-defined pulse calibration
- each ESC also has explicit profile-defined deadband
- configurable ramp limiting is applied in the vehicle daemon

Future pan/tilt outputs are reserved in schema and config, but may remain unset in v1.

### Runtime Shape

- one main Python daemon handles session logic, control parsing, output scheduling, and telemetry
- daemon runs as root in v1 for simplicity
- daemon uses a single event loop/state machine model
- daemon runs a fixed 100 Hz control loop
- controller target send rate is 50 Hz
- dry-run mode exists from the start and is enabled via runtime config

## Safety Model

### Session Ownership

- vehicle learns telemetry destination from valid control packets
- vehicle only updates telemetry destination from valid packets belonging to the active session
- vehicle locks onto one active controller session
- another controller may take over only after the existing session reaches the `lost` state

### Arming Rules

- arm is controlled by a latched dedicated switch channel
- vehicle boots disarmed
- both track channels must be near neutral before arming is accepted
- after a true signal-loss event, full re-arm sequence is required

### Link-Loss Rules

Two-stage link-loss behavior is required:

1. `degraded` after short packet loss:
   - immediately command both tracks to neutral
   - remain logically armed
2. `lost` after prolonged packet loss:
   - disarm completely
   - require full re-arm sequence once packets return

Target starting values from design discussion:

- degrade timeout: 250 ms
- lost timeout: 2.0 s

## Telemetry v1

The viewer contract expects battery, speed, signal, and GPS fields. The vehicle node should send only what it can honestly produce in v1 and default the rest.

### Available in v1

- generic signal-quality value derived from Wi-Fi status

### Unavailable in v1

- battery voltage
- speed
- GPS latitude/longitude

Wi-Fi signal metrics are normalized on the vehicle side into a generic link-quality value suitable for the existing telemetry display.

## Generated Runtime Settings

The canonical runtime settings file is generated onto the boot partition. This keeps the image aligned with a future workflow where a mounted image can be retargeted by replacing one settings file instead of rebuilding from scratch.

In v1, images are still fully personalized during build time. The boot-partition config location is chosen to preserve the later retargeting path.

## Testing Strategy

### Required Automated Tests

Automated tests are required for:

- profile parsing and schema validation
- generated config rendering
- control packet parsing
- monotonic-tick freshness handling
- active-session lock behavior
- arm/disarm and re-arm sequence logic
- degraded/lost link-state transitions
- channel-to-output calibration and deadband application
- ramp-limiting behavior
- dry-run mode behavior

### Manual Bring-Up Tests

Manual validation remains acceptable for:

- Raspberry Pi image flashing and boot
- Wi-Fi association on real hardware
- RTSP camera bring-up and latency tuning
- GPIO timing behavior on Pi hardware
- real ESC arming and drivetrain behavior

## Documentation Requirements

The implementation must document:

- canonical vehicle profile schema
- generated image contents and file layout
- systemd service list and responsibilities
- target RC control packet contract
- tracked-vehicle channel mapping
- telemetry defaults and unavailable-field semantics
- dry-run workflow
- image build and validation workflow

This documentation needs to be complete enough that the viewer-side protocol migration can happen later without rediscovering vehicle-node assumptions.

## Out of Scope

1. Migration of the existing Godot viewer to the new RC-channel protocol in the same change set.
2. Persistent on-device settings edits during normal read-only operation.
3. Recovery shell, A/B updates, overlayfs root, or transactional update system.
4. Battery ADC integration, wheel encoders, IMU odometry, or GPS hardware.
5. Gimbal or servo outputs on `ch3` and `ch4` in v1.
6. RTSP authentication or encrypted control transport in v1.
7. Controller authentication beyond LAN trust in v1.
8. Multi-vehicle arbitration or handoff.

## Risks and Follow-Ups

1. Pi 3 A+ may be tight on CPU/network headroom for low-latency RTSP plus control. Camera presets will need real-hardware tuning.
2. Exact ESC behavior, especially reverse semantics and arming quirks, must be bench-characterized before enabling real drive outputs.
3. The RC-channel packet contract is intentionally documented ahead of viewer migration; the repo will temporarily straddle old and new control assumptions.
4. The precise Wi-Fi-signal normalization formula should be chosen during implementation and documented once measured against real hardware.
5. Future ELRS, MAVLink, aircraft profiles, and USB VRX video input should build on the canonical profile and RC-channel abstraction rather than introducing parallel control models.
