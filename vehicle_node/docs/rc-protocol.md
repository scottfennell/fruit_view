# RC Protocol Contract

The dry-run daemon accepts a fixed-length UDP control packet intended to replace the current viewer-side `throttle + steering + head pose` packet later.

## Control packet

- transport: unicast UDP
- default port: `9000`
- endianness: little-endian
- size: `48` bytes

Binary layout:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `char[4]` | magic = `FRC1` |
| 4 | `u8` | version = `1` |
| 5 | `u8` | channel_count = `8` |
| 6 | `u16` | reserved = `0` |
| 8 | `u32` | target `vehicle_id` |
| 12 | `u32` | sender monotonic tick |
| 16 | `f32[8]` | channels `ch1..ch8`, each in `[-1.0, 1.0]` |

Packets with the wrong magic, version, channel count, target `vehicle_id`, size, or out-of-range channel values are rejected.

Ticks must be strictly increasing within the active session. Stale or duplicate ticks are ignored.

## Tracked mapping

- `ch1`: left track
- `ch2`: right track
- `ch3`: camera pan / future gimbal yaw
- `ch4`: camera tilt / future gimbal pitch
- `ch5`: latched arm switch
- `ch6`: mode / spare
- `ch7`: spare
- `ch8`: spare

## Session and safety rules

- the vehicle locks onto the first valid controller session
- only packets from the active session can update telemetry destination or control state
- another sender may take over only after the link reaches `lost`
- the vehicle boots disarmed
- arming is accepted only while both track channels are near neutral
- `degraded` begins after `250 ms` without packets and commands tracks back to neutral while preserving armed state
- `lost` begins after `2.0 s` without packets and disarms completely
- once `lost` has occurred, a low-then-high arm-switch cycle is required before arming is accepted again

## Telemetry packet

The dry-run daemon emits the existing viewer telemetry packet shape so the Godot viewer does not need to change yet.

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `f32` | battery voltage, default `0.0` |
| 4 | `f32` | speed, default `0.0` |
| 8 | `f32` | Wi-Fi signal in dBm-like form |
| 12 | `f64` | GPS latitude, default `0.0` |
| 20 | `f64` | GPS longitude, default `0.0` |

The telemetry destination is learned from the active controller session's source IP plus the configured telemetry return port.
