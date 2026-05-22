# main.gd
#
# Root scene controller for fruit_view.
#
# Responsibilities:
#   - Build the hemisphere mesh and apply the hemisphere shader
#   - Instantiate the active HeadTracker implementation (config-driven)
#   - Instantiate the active VideoSource implementation (config-driven)
#   - Instantiate ControlOutput and InputHandler
#   - Instantiate TelemetryInput and spawn TelemetryPanel nodes
#   - Push the current video texture to the hemisphere material each frame
#   - Enforce fullscreen on Linux production targets

extends Node3D

# ── Scene references ──────────────────────────────────────────────────────────
@onready var _hemisphere: MeshInstance3D = $HemisphereMeshInstance
@onready var _camera: Camera3D           = $SphericalCamera

# ── Runtime objects (created in _ready) ───────────────────────────────────────
var _head_tracker:    HeadTracker
var _video_source:    VideoSource
var _control_output:  ControlOutput
var _input_handler:   InputHandler
var _telemetry_input: TelemetryInput

# ── Hemisphere geometry constants ─────────────────────────────────────────────
const HEMISPHERE_RADIUS := 50.0
const H_SEGMENTS        := 64
const V_SEGMENTS        := 32

# ── Shader material (kept for texture updates in _process) ────────────────────
var _hemisphere_mat: ShaderMaterial


func _ready() -> void:
	_build_hemisphere()
	_wire_head_tracker()
	_wire_video_source()
	_wire_control_output()
	_wire_telemetry()
	_configure_display()


func _process(_delta: float) -> void:
	# Push the latest video frame to the hemisphere material every tick.
	if _video_source != null:
		var tex := _video_source.get_texture()
		if tex != null:
			_hemisphere_mat.set_shader_parameter("video_texture", tex)

	# Apply head tracking to camera each frame.
	if _head_tracker != null:
		var rot := _head_tracker.get_rotation()
		_camera.rotation = Vector3(rot.x, rot.y, 0.0)


# ── Private builders ──────────────────────────────────────────────────────────

func _build_hemisphere() -> void:
	_hemisphere.mesh = HemisphereMeshBuilder.build(
		HEMISPHERE_RADIUS, H_SEGMENTS, V_SEGMENTS
	)
	_hemisphere_mat = ShaderMaterial.new()
	_hemisphere_mat.shader = load("res://shaders/hemisphere.gdshader")
	_hemisphere_mat.set_shader_parameter("distortion_k1", 0.0)
	_hemisphere.material_override = _hemisphere_mat


func _wire_head_tracker() -> void:
	_head_tracker = _create_head_tracker()
	add_child(_head_tracker)


func _wire_video_source() -> void:
	_video_source = _create_video_source()
	add_child(_video_source)


func _wire_control_output() -> void:
	_control_output = UDPControlOutput.new()
	add_child(_control_output)

	_input_handler = InputHandler.new()
	_input_handler.control_output = _control_output
	_input_handler.head_tracker   = _head_tracker
	add_child(_input_handler)


func _wire_telemetry() -> void:
	_telemetry_input = TelemetryInput.new()
	add_child(_telemetry_input)

	# Default panel layout — azimuth/elevation in degrees, panels on the right.
	# Positions are intentionally kept in code rather than a resource file until
	# an editor workflow exists; they are easy to tune here.
	var panels := [
		{ "signal": "battery_voltage_changed", "prefix": "Bat:  ", "az":  42.0, "el":  30.0 },
		{ "signal": "speed_changed",           "prefix": "Spd:  ", "az":  42.0, "el":  10.0 },
		{ "signal": "signal_rssi_changed",     "prefix": "RSSI: ", "az":  42.0, "el": -10.0 },
		{ "signal": "gps_position_changed",    "prefix": "GPS:  ", "az":  42.0, "el": -30.0 },
	]

	for cfg in panels:
		var panel := TelemetryPanel.new()
		add_child(panel)
		panel.setup(
			_telemetry_input,
			cfg["signal"] as String,
			cfg["prefix"]  as String,
			cfg["az"]      as float,
			cfg["el"]      as float
		)


func _configure_display() -> void:
	# Run fullscreen on the XREAL display (Orange Pi / Linux production).
	if OS.has_feature("linux") and not OS.has_feature("editor"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ── Factory helpers ───────────────────────────────────────────────────────────

func _create_head_tracker() -> HeadTracker:
	var mode := ProjectSettings.get_setting(
		"head_tracker/mode", "mouse_look"
	) as String
	match mode:
		"opentrack_udp":
			return OpenTrackUDPTracker.new()
		# "openxr" will be wired here in a future issue
		_:
			return MouseLookTracker.new()


func _create_video_source() -> VideoSource:
	var mode := ProjectSettings.get_setting(
		"video/source", "local_file"
	) as String
	match mode:
		"rtsp_gstreamer":
			return RTSPGStreamerSource.new()
		_:
			return LocalFileSource.new()
