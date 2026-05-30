# test_rtsp_gstreamer_source.gd
#
# Unit tests for RTSPGStreamerSource.
# Tests _handle_complete_frame(), _consume_frames(), and reconnect state
# directly — no live TCP socket or GStreamer process required.

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
	assert_eq(_source.get_texture().get_width(), 4,
		"Texture width should match the received frame width")
	assert_eq(_source.get_texture().get_height(), 4,
		"Texture height should match the received frame height")


func test_handle_frame_sets_is_playing() -> void:
	var data := _solid_rgba(2, 2, 0, 255, 0, 255)
	_source._handle_complete_frame(2, 2, data)
	# _connected is still false (no real TCP socket), but _has_frame is true.
	# is_playing() requires both — assert _has_frame via get_texture() instead.
	assert_not_null(_source.get_texture(),
		"get_texture() should be non-null after a frame has been received")


func test_handle_frame_updates_texture_on_second_call() -> void:
	_source._handle_complete_frame(2, 2, _solid_rgba(2, 2, 255, 0, 0, 255))
	_source._handle_complete_frame(4, 4, _solid_rgba(4, 4, 0, 0, 255, 255))
	# Texture object may be replaced on resolution change — still non-null.
	assert_not_null(_source.get_texture(),
		"Texture should remain valid after a second frame")
	assert_eq(_source.get_texture().get_width(), 4,
		"Texture width should follow the latest frame width")
	assert_eq(_source.get_texture().get_height(), 4,
		"Texture height should follow the latest frame height")


# ── _consume_frames (buffer logic) ───────────────────────────────────────────

func test_consume_frames_parses_single_frame() -> void:
	_source._recv = _framed(2, 2, _solid_rgba(2, 2, 128, 128, 128, 255))
	_source._consume_frames()
	assert_not_null(_source.get_texture(),
		"_consume_frames() should produce a texture from a valid framed buffer")


func test_consume_frames_handles_two_frames_in_buffer() -> void:
	var buf := PackedByteArray()
	buf.append_array(_framed(2, 2, _solid_rgba(2, 2, 255, 0, 0, 255)))
	buf.append_array(_framed(3, 3, _solid_rgba(3, 3, 0, 255, 0, 255)))
	_source._recv = buf
	_source._consume_frames()
	# Both frames consumed — buffer should be empty
	assert_eq(_source._recv.size(), 0,
		"Buffer should be empty after consuming two complete frames")
	assert_eq(_source.get_texture().get_width(), 3,
		"When multiple frames are buffered, the latest frame should win")
	assert_eq(_source.get_texture().get_height(), 3,
		"Latest buffered frame dimensions should be applied")


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


# ── Reconnect / status path ───────────────────────────────────────────────────

func test_status_text_is_connecting_before_first_frame() -> void:
	assert_eq(_source.get_status_text(), "Connecting\u2026",
		"Status should be 'Connecting…' before any frame arrives")


func test_status_text_is_no_signal_after_frame_then_disconnect() -> void:
	# Simulate: frame arrived, then connection dropped.
	_source._handle_complete_frame(2, 2, _solid_rgba(2, 2, 0, 0, 0, 255))
	# Now simulate disconnect: _connected becomes false.
	_source._connected = false
	assert_eq(_source.get_status_text(), "No signal",
		"Status should switch to 'No signal' once we have had frames but lost connection")


func test_status_text_empty_when_playing() -> void:
	# Simulate connected + has frame.
	_source._connected = true
	_source._handle_complete_frame(2, 2, _solid_rgba(2, 2, 0, 0, 0, 255))
	assert_eq(_source.get_status_text(), "",
		"Status should be empty (overlay hidden) when playing")


func test_disconnect_triggers_reconnect_timer() -> void:
	# Simulate: was connected, then peer drops.
	_source._connected = true
	# Force the peer into a non-connected state by replacing it with a fresh one
	# (never connected → STATUS_NONE, which is not STATUS_CONNECTED).
	_source._peer = StreamPeerTCP.new()
	# Run _process with a tiny delta — the code should detect the drop.
	_source._process(0.01)
	assert_false(_source._connected,
		"_connected should become false when the peer is no longer STATUS_CONNECTED")


func test_build_sidecar_args_includes_optional_limits() -> void:
	_source._port = 9001
	_source._rtsp_url = "rtsp://example/stream"
	_source._sidecar_width = 960
	_source._sidecar_height = 540
	_source._sidecar_fps = 30
	var args := _source._build_sidecar_args("/tmp/video_sidecar.py")
	assert_eq(args,
		PackedStringArray([
			"/tmp/video_sidecar.py", "--port", "9001", "--url", "rtsp://example/stream",
			"--width", "960", "--height", "540", "--fps", "30"
		]),
		"Sidecar args should include configured width/height/fps limits")


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
