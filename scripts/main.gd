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
#   - Display a status overlay ("Connecting…" / "No signal") when the video
#     source is not delivering frames
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
var _status_label:    Label

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
	_wire_status_overlay()
	_configure_display()


func _process(_delta: float) -> void:
	# Push the latest video frame to the hemisphere material every tick.
	if _video_source != null:
		var tex := _video_source.get_texture()
		if tex != null:
			_hemisphere_mat.set_shader_parameter("video_texture", tex)

		# Update status overlay.
		if _status_label != null:
			var status := _video_source.get_status_text()
			_status_label.text    = status
			_status_label.visible = status != ""

	# Apply head tracking to camera each frame.
	if _head_tracker != null:
		var rot := _head_tracker.get_rotation()
		# OpenTrack pitch is positive-up; Godot Camera3D rotation.x is positive-down.
		# Negate pitch so looking down tilts the camera down, not up.
		_camera.rotation = Vector3(-rot.x, rot.y, 0.0)


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

	var layout := _load_panel_layout()
	for cfg in layout:
		var panel := TelemetryPanel.new()
		add_child(panel)
		panel.setup(
			_telemetry_input,
			cfg["signal"] as String,
			cfg["prefix"]  as String,
			cfg["az"]      as float,
			cfg["el"]      as float
		)


# Load the telemetry panel layout.  If a custom resource exists on disk it is
# used; otherwise the built-in defaults are returned.  The resource format is
# an Array of Dictionaries with keys: signal, prefix, az (float), el (float).
func _load_panel_layout() -> Array:
	const LAYOUT_PATH := "res://data/telemetry_panel_layout.tres"
	if ResourceLoader.exists(LAYOUT_PATH):
		var res = load(LAYOUT_PATH)
		if res is TelemetryPanelLayout:
			return res.panels
	return _default_panel_layout()


# Built-in fallback layout used when no .tres resource file is present.
func _default_panel_layout() -> Array:
	return [
		{ "signal": "battery_voltage_changed", "prefix": "Bat:  ", "az":  42.0, "el":  30.0 },
		{ "signal": "speed_changed",           "prefix": "Spd:  ", "az":  42.0, "el":  10.0 },
		{ "signal": "signal_rssi_changed",     "prefix": "RSSI: ", "az":  42.0, "el": -10.0 },
		{ "signal": "gps_position_changed",    "prefix": "GPS:  ", "az":  42.0, "el": -30.0 },
	]


func _wire_status_overlay() -> void:
	# A simple 2D label centred on screen.  Visible only when the video source
	# is not delivering frames; hidden the moment live video arrives.
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_status_label = Label.new()
	_status_label.text                   = "Connecting\u2026"
	_status_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	_status_label.anchors_preset         = Control.PRESET_FULL_RECT
	_status_label.add_theme_font_size_override("font_size", 48)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status_label.add_theme_constant_override("shadow_offset_x", 2)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_status_label)


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
