# test_udp_control_output.gd
#
# Unit tests for UDPControlOutput.
# Tests the packet byte layout via _build_packet() directly — no live socket needed.

extends GutTest

var _output: UDPControlOutput


func before_each() -> void:
	_output = UDPControlOutput.new()
	add_child_autofree(_output)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _read_f32(data: PackedByteArray, offset: int) -> float:
	return data.decode_float(offset)


func _read_u8(data: PackedByteArray, offset: int) -> int:
	return data.decode_u8(offset)


func _read_u16(data: PackedByteArray, offset: int) -> int:
	return data.decode_u16(offset)


func _read_u32(data: PackedByteArray, offset: int) -> int:
	return data.decode_u32(offset)


func _build_packet(
	throttle: float,
	steering: float,
	head_yaw: float,
	head_pitch: float,
	armed: bool = false,
	tick: int = 77,
	vehicle_id: int = 100
) -> PackedByteArray:
	return _output._build_packet(throttle, steering, head_yaw, head_pitch, armed, tick, vehicle_id)


# ── Packet layout tests ────────────────────────────────────────────────────────

func test_packet_magic_header() -> void:
	var pkt := _build_packet(0.0, 0.0, 0.0, 0.0)
	assert_eq(pkt.slice(0, 4).get_string_from_utf8(), "FRC1", "magic should be FRC1")


func test_packet_header_fields() -> void:
	var pkt := _build_packet(0.0, 0.0, 0.0, 0.0, false, 1234, 100)
	assert_eq(_read_u8(pkt, 4), 1, "version at offset 4")
	assert_eq(_read_u8(pkt, 5), 8, "channel count at offset 5")
	assert_eq(_read_u16(pkt, 6), 0, "reserved field at offset 6")
	assert_eq(_read_u32(pkt, 8), 100, "vehicle_id at offset 8")
	assert_eq(_read_u32(pkt, 12), 1234, "tick at offset 12")


func test_packet_left_track_channel_uses_arcade_mix() -> void:
	var pkt := _build_packet(0.75, 0.25, 0.0, 0.0)
	assert_almost_eq(_read_f32(pkt, 16), 1.0, 0.0001, "left track at channel 1")


func test_packet_right_track_channel_uses_arcade_mix() -> void:
	var pkt := _build_packet(0.75, 0.25, 0.0, 0.0)
	assert_almost_eq(_read_f32(pkt, 20), 0.5, 0.0001, "right track at channel 2")


func test_packet_head_channels_are_clamped() -> void:
	var pkt := _build_packet(0.0, 0.0, 1.23, -1.5)
	assert_almost_eq(_read_f32(pkt, 24), 1.0, 0.0001, "head_yaw should be clamped at channel 3")
	assert_almost_eq(_read_f32(pkt, 28), -1.0, 0.0001, "head_pitch should be clamped at channel 4")


func test_packet_arm_channel_reflects_toggle_state() -> void:
	var pkt := _build_packet(0.0, 0.0, 0.0, 0.0, true)
	assert_almost_eq(_read_f32(pkt, 32), 1.0, 0.0001, "arm switch should be channel 5")


func test_packet_spare_channels_default_to_zero() -> void:
	var pkt := _build_packet(0.0, 0.0, 0.0, 0.0)
	assert_almost_eq(_read_f32(pkt, 36), 0.0, 0.0001, "channel 6 should default to zero")
	assert_almost_eq(_read_f32(pkt, 40), 0.0, 0.0001, "channel 7 should default to zero")
	assert_almost_eq(_read_f32(pkt, 44), 0.0, 0.0001, "channel 8 should default to zero")


func test_packet_size_matches_protocol_contract() -> void:
	var pkt := _build_packet(0.0, 0.0, 0.0, 0.0)
	assert_eq(pkt.size(), 48, "RC packet should be exactly 48 bytes")


func test_next_tick_strictly_increases() -> void:
	assert_eq(_output._next_tick(), 1, "first tick should be 1")
	assert_eq(_output._next_tick(), 2, "second tick should be 2")


func test_keepalive_resets_timer() -> void:
	# After send(), _time_since_send should be 0.
	_output.send(0.5, 0.5, 0.0, 0.0)
	assert_almost_eq(_output._time_since_send, 0.0, 0.001,
		"_time_since_send should reset to 0 after send()")
