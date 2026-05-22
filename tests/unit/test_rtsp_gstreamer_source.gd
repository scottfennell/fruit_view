# test_rtsp_gstreamer_source.gd
#
# Unit tests for RTSPGStreamerSource.
# Tests _handle_complete_frame() and _consume_frames() directly —
# no live TCP socket or GStreamer process required.

extends GutTest

var _source: RTSPGStreamerSource


func before_each() -> void:
	_source = RTSPGStreamerSource.new()
	add_child_autofree(_source)


# ── _handle_complete_frame ────────────────────────────────────────────────────

func test_get_texture_null_before_first_frame() -> void:
	assert_null(_source.get_texture(),
		"get_texture() should be null before any frame has been received")


func test_is_playing_false_before_first_frame() -> void:
	assert_false(_source.is_playing(),
		"is_playing() should be false before any frame has been received")


func test_handle_frame_makes_texture_non_null() -> void:
	var data := _solid_rgba(4, 4, 255, 0, 0, 255)
	_source._handle_complete_frame(4, 4, data)
	assert_not_null(_source.get_texture(),
		"get_texture() should return a texture after _handle_complete_frame()")


func test_handle_frame_sets_is_playing() -> void:
	var data := _solid_rgba(2, 2, 0, 255, 0, 255)
	_source._handle_complete_frame(2, 2, data)
	assert_true(_source.is_playing(),
		"is_playing() should be true after a frame has been received " +
		"(when connected — here we set _has_frame directly)")


func test_handle_frame_updates_texture_on_second_call() -> void:
	_source._handle_complete_frame(2, 2, _solid_rgba(2, 2, 255, 0, 0, 255))
	var first := _source.get_texture()
	_source._handle_complete_frame(4, 4, _solid_rgba(4, 4, 0, 0, 255, 255))
	# Texture object is reused (updated in place) — it should still be non-null
	assert_not_null(_source.get_texture(),
		"Texture should remain valid after a second frame")


# ── _consume_frames (buffer logic) ───────────────────────────────────────────

func test_consume_frames_parses_single_frame() -> void:
	_source._recv = _framed(2, 2, _solid_rgba(2, 2, 128, 128, 128, 255))
	_source._consume_frames()
	assert_not_null(_source.get_texture(),
		"_consume_frames() should produce a texture from a valid framed buffer")


func test_consume_frames_handles_two_frames_in_buffer() -> void:
	var buf := PackedByteArray()
	buf.append_array(_framed(2, 2, _solid_rgba(2, 2, 255, 0, 0, 255)))
	buf.append_array(_framed(2, 2, _solid_rgba(2, 2, 0, 255, 0, 255)))
	_source._recv = buf
	_source._consume_frames()
	# Both frames consumed — buffer should be empty
	assert_eq(_source._recv.size(), 0,
		"Buffer should be empty after consuming two complete frames")


func test_consume_frames_waits_for_incomplete_frame() -> void:
	# Header only, no pixel data
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, 4)  # width
	header.encode_u32(4, 4)  # height
	_source._recv = header
	_source._consume_frames()
	# Buffer unchanged — not enough data to complete the frame
	assert_eq(_source._recv.size(), 8,
		"Incomplete frame should remain in buffer until full data arrives")


# ── Helpers ────────────────────────────────────────────────────────────────────

# Build a PackedByteArray of solid RGBA pixels (w × h pixels).
func _solid_rgba(w: int, h: int, r: int, g: int, b: int, a: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in range(w * h):
		data[i * 4 + 0] = r
		data[i * 4 + 1] = g
		data[i * 4 + 2] = b
		data[i * 4 + 3] = a
	return data


# Wrap pixel data in the sidecar frame protocol header.
func _framed(w: int, h: int, rgba: PackedByteArray) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, w)
	header.encode_u32(4, h)
	header.append_array(rgba)
	return header
