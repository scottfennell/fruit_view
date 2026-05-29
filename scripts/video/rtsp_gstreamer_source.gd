# RTSPGStreamerSource
#
# VideoSource implementation that receives decoded RGBA frames from the
# GStreamer sidecar process (sidecar/video_sidecar.py) over a local TCP
# connection.
#
# Frame protocol (per frame, little-endian):
#   Offset 0: width  (u32)
#   Offset 4: height (u32)
#   Offset 8: pixels (width × height × 4 bytes, RGBA8)
#
# The sidecar process is spawned automatically on _ready(). If the sidecar
# drops or the stream stalls, RTSPGStreamerSource reconnects automatically.
#
# Configuration (project.godot):
#   video/rtsp_url        — RTSP URL passed to the sidecar (default 192.168.86.18)
#   video/sidecar_port    — local TCP port for frames          (default 9001)
#   video/sidecar_python  — path to python3 binary             (default "python3")

class_name RTSPGStreamerSource
extends VideoSource

const SETTING_RTSP_URL := "video/rtsp_url"
const SETTING_PORT     := "video/sidecar_port"
const SETTING_PYTHON   := "video/sidecar_python"

const DEFAULT_URL    := "rtsp://192.168.86.18:8554/stream"
const DEFAULT_PORT   := 9001
const DEFAULT_PYTHON := "python3"

const RECONNECT_INTERVAL := 3.0  # seconds between connection attempts
const HEADER_SIZE        := 8    # width(u32) + height(u32)

# ── Network state ─────────────────────────────────────────────────────────────
var _peer:             StreamPeerTCP  = StreamPeerTCP.new()
var _connected:        bool           = false
var _reconnect_timer:  float          = RECONNECT_INTERVAL  # attempt immediately
# True once we have had at least one successful frame — used to distinguish
# "Connecting…" (never connected) from "No signal" (lost a live stream).
var _ever_connected:   bool           = false

# ── Receive buffer ────────────────────────────────────────────────────────────
# All bytes received from the sidecar accumulate here; complete frames are
# consumed from the front as they become available.
var _recv: PackedByteArray = PackedByteArray()

# ── Output texture ────────────────────────────────────────────────────────────
# Null until the first frame arrives. Use create_from_image() on first frame,
# then update() on subsequent frames (update() requires an already-initialised
# texture with matching dimensions).
var _texture:   ImageTexture = null
var _has_frame: bool         = false

# ── Sidecar process ───────────────────────────────────────────────────────────
var _sidecar_pid: int = -1

# ── Config (resolved in _ready) ───────────────────────────────────────────────
var _rtsp_url: String
var _port:     int
var _python:   String


func _ready() -> void:
	_rtsp_url = ProjectSettings.get_setting(SETTING_RTSP_URL, DEFAULT_URL)    as String
	_port     = ProjectSettings.get_setting(SETTING_PORT,     DEFAULT_PORT)   as int
	_python   = ProjectSettings.get_setting(SETTING_PYTHON,   DEFAULT_PYTHON) as String
	_spawn_sidecar()


func _process(delta: float) -> void:
	if not _connected:
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_INTERVAL:
			_reconnect_timer = 0.0
			_attempt_connect()
		return

	_peer.poll()

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_connected = false
		push_warning("RTSPGStreamerSource: sidecar disconnected — will retry in %.1fs." \
					  % RECONNECT_INTERVAL)
		return

	_drain_recv_buffer()
	_consume_frames()


func get_texture() -> Texture2D:
	return _texture if _has_frame else null


func is_playing() -> bool:
	return _connected and _has_frame


# Returns a status string for the overlay when not playing.
# "Connecting…"  — sidecar is starting up or has never delivered a frame.
# "No signal"    — stream was live but has since dropped.
# ""             — playing normally; overlay should be hidden.
func get_status_text() -> String:
	if is_playing():
		return ""
	return "No signal" if _ever_connected else "Connecting\u2026"


# ── Private: sidecar process ──────────────────────────────────────────────────

func _spawn_sidecar() -> void:
	var script := _resolve_sidecar_path()
	var args   := [script, "--port", str(_port), "--url", _rtsp_url]
	_sidecar_pid = OS.create_process(_python, args)
	if _sidecar_pid < 0:
		push_error("RTSPGStreamerSource: failed to spawn sidecar. " +
				   "Ensure '%s' is installed and video_sidecar.py is at: %s" % [_python, script])
	else:
		print("RTSPGStreamerSource: sidecar PID %d, port %d, script: %s" \
			  % [_sidecar_pid, _port, script])


# Returns the filesystem path to video_sidecar.py.
#
# In the editor res:// maps to the project directory, so globalize_path works.
# In an exported binary the PCK is embedded inside the executable; res:// files
# are not accessible as real filesystem paths. The deploy script places
# video_sidecar.py alongside the binary, so we resolve relative to the
# executable in production.
func _resolve_sidecar_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://sidecar/video_sidecar.py")
	return OS.get_executable_path().get_base_dir().path_join("video_sidecar.py")


# ── Private: connection management ────────────────────────────────────────────

func _attempt_connect() -> void:
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host("127.0.0.1", _port)
	if err != OK:
		return
	_connected = true
	_recv      = PackedByteArray()
	print("RTSPGStreamerSource: connected to sidecar on port %d." % _port)


# ── Private: frame assembly ───────────────────────────────────────────────────

func _drain_recv_buffer() -> void:
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var result := _peer.get_data(available)
	if result[0] == OK:
		_recv.append_array(result[1] as PackedByteArray)


func _consume_frames() -> void:
	while _recv.size() >= HEADER_SIZE:
		var w          := _recv.decode_u32(0)
		var h          := _recv.decode_u32(4)
		var pixel_size := w * h * 4
		var total      := HEADER_SIZE + pixel_size

		if _recv.size() < total:
			break  # Wait for the rest of the frame

		_handle_complete_frame(w, h, _recv.slice(HEADER_SIZE, total))
		_recv = _recv.slice(total)


# Handle a fully-assembled frame. Exposed for unit testing (avoids needing a
# live TCP socket in tests).
func _handle_complete_frame(width: int, height: int, rgba_data: PackedByteArray) -> void:
	var img := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, rgba_data
	)
	if _texture == null or _texture.get_width() != width or _texture.get_height() != height:
		# First frame or resolution change — create a new ImageTexture.
		# ImageTexture.update() requires an already-initialised texture with
		# matching dimensions, so we use create_from_image() here.
		_texture = ImageTexture.create_from_image(img)
	else:
		_texture.update(img)
	_has_frame      = true
	_ever_connected = true


# ── Cleanup ───────────────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if _connected:
			_peer.disconnect_from_host()
		if _sidecar_pid >= 0:
			OS.kill(_sidecar_pid)
			_sidecar_pid = -1
