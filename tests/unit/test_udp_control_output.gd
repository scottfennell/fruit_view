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


# ── Packet layout tests ────────────────────────────────────────────────────────

func test_packet_throttle_at_offset_0() -> void:
	var pkt := _output._build_packet(0.75, 0.0, 0.0, 0.0, [])
	assert_almost_eq(_read_f32(pkt, 0), 0.75, 0.0001, "throttle at offset 0")


func test_packet_steering_at_offset_4() -> void:
	var pkt := _output._build_packet(0.0, -0.5, 0.0, 0.0, [])
	assert_almost_eq(_read_f32(pkt, 4), -0.5, 0.0001, "steering at offset 4")


func test_packet_head_yaw_at_offset_8() -> void:
	var pkt := _output._build_packet(0.0, 0.0, 1.23, 0.0, [])
	assert_almost_eq(_read_f32(pkt, 8), 1.23, 0.0001, "head_yaw at offset 8")


func test_packet_head_pitch_at_offset_12() -> void:
	var pkt := _output._build_packet(0.0, 0.0, 0.0, -0.45, [])
	assert_almost_eq(_read_f32(pkt, 12), -0.45, 0.0001, "head_pitch at offset 12")


func test_packet_aux_count_zero_when_no_aux() -> void:
	var pkt := _output._build_packet(0.0, 0.0, 0.0, 0.0, [])
	assert_eq(_read_u8(pkt, 16), 0, "aux_count should be 0 when aux array is empty")


func test_packet_minimum_size_without_aux() -> void:
	var pkt := _output._build_packet(0.0, 0.0, 0.0, 0.0, [])
	# 4+4+4+4 bytes (floats) + 1 byte (aux_count) = 17 bytes
	assert_eq(pkt.size(), 17, "Packet without aux channels should be 17 bytes")


func test_packet_aux_channels_appended_correctly() -> void:
	var pkt := _output._build_packet(0.0, 0.0, 0.0, 0.0, [1.0, 2.0])
	assert_eq(_read_u8(pkt, 16), 2, "aux_count should be 2")
	assert_almost_eq(_read_f32(pkt, 17), 1.0, 0.0001, "first aux value at offset 17")
	assert_almost_eq(_read_f32(pkt, 21), 2.0, 0.0001, "second aux value at offset 21")


func test_packet_aux_count_capped_at_255() -> void:
	var big_aux := []
	for i in range(300):
		big_aux.append(0.0)
	var pkt := _output._build_packet(0.0, 0.0, 0.0, 0.0, big_aux)
	assert_eq(_read_u8(pkt, 16), 255, "aux_count should be capped at 255")


func test_keepalive_resets_timer() -> void:
	# After send(), _time_since_send should be 0.
	_output.send(0.5, 0.5, 0.0, 0.0)
	assert_almost_eq(_output._time_since_send, 0.0, 0.001,
		"_time_since_send should reset to 0 after send()")
