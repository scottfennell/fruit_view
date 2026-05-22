# MouseLookTracker
#
# HeadTracker implementation driven by relative mouse motion.
# Used for development and testing on Mac without XR hardware attached.
#
# Mouse capture is enabled on startup so the cursor does not leave the window.
# Press Escape to release the cursor (useful during development).
#
# Configuration (project.godot):
#   head_tracker/mouse_sensitivity  — degrees turned per pixel (default 0.1)

class_name MouseLookTracker
extends HeadTracker

const SETTING_SENSITIVITY := "head_tracker/mouse_sensitivity"
const DEFAULT_SENSITIVITY := 0.1

var _yaw:   float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	# Release cursor on Escape (development convenience)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			return

	if event is InputEventMouseMotion:
		var sensitivity := deg_to_rad(
			ProjectSettings.get_setting(SETTING_SENSITIVITY, DEFAULT_SENSITIVITY) as float
		)
		var motion := event as InputEventMouseMotion
		# Rightward mouse = turn right = decrease yaw (Godot: positive Y = turn left)
		_yaw   -= motion.relative.x * sensitivity
		# Downward mouse  = look down = decrease pitch
		_pitch -= motion.relative.y * sensitivity
		_pitch  = clamp(_pitch, -PI * 0.5, PI * 0.5)


func get_rotation() -> Vector3:
	return Vector3(_pitch, _yaw, 0.0)
