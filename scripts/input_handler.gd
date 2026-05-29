# InputHandler
#
# Reads gamepad axis values each frame, applies a deadzone, and forwards
# throttle + steering + head pose to ControlOutput.
#
# The output layer mixes throttle + steering into tracked left/right RC channels.
# Head yaw and pitch are carried in the reserved camera channels for future use.
#
# Recenter: press Space (keyboard) or the gamepad Back/Select button to capture
# the current head pose as the new forward direction.
#
# Arm toggle: press A (keyboard) or the gamepad South button to toggle the
# viewer-side arm switch channel.
#
# Configuration (project.godot):
#   input_map/throttle_axis — JoyAxis index for throttle (default JOY_AXIS_LEFT_Y = 1)
#   input_map/steering_axis — JoyAxis index for steering (default JOY_AXIS_LEFT_X = 0)

class_name InputHandler
extends Node

const SETTING_THROTTLE_AXIS := "input_map/throttle_axis"
const SETTING_STEERING_AXIS := "input_map/steering_axis"
const DEFAULT_THROTTLE_AXIS := JOY_AXIS_LEFT_Y  # 1
const DEFAULT_STEERING_AXIS := JOY_AXIS_LEFT_X  # 0
const DEADZONE              := 0.05

# Recenter bindings (not configurable at runtime — change here if needed).
const RECENTER_KEY    := KEY_SPACE
const RECENTER_BUTTON := JOY_BUTTON_BACK  # gamepad Select / Back / Share
const ARM_TOGGLE_KEY    := KEY_A
const ARM_TOGGLE_BUTTON := JOY_BUTTON_A

var control_output: ControlOutput
var head_tracker:   HeadTracker

var _throttle_axis: int
var _steering_axis: int
var _armed:         bool = false


func _ready() -> void:
	_throttle_axis = ProjectSettings.get_setting(
		SETTING_THROTTLE_AXIS, DEFAULT_THROTTLE_AXIS
	) as int
	_steering_axis = ProjectSettings.get_setting(
		SETTING_STEERING_AXIS, DEFAULT_STEERING_AXIS
	) as int


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == RECENTER_KEY:
			_recenter()
		elif key.pressed and not key.echo and key.keycode == ARM_TOGGLE_KEY:
			_toggle_arm()
	elif event is InputEventJoypadButton:
		var btn := event as InputEventJoypadButton
		if btn.pressed and btn.button_index == RECENTER_BUTTON:
			_recenter()
		elif btn.pressed and btn.button_index == ARM_TOGGLE_BUTTON:
			_toggle_arm()


func _process(_delta: float) -> void:
	if control_output == null:
		return

	# Negate Y: pushing the stick forward (negative axis) = positive throttle.
	var raw_t := -Input.get_joy_axis(0, _throttle_axis)
	var raw_s :=  Input.get_joy_axis(0, _steering_axis)

	var throttle := raw_t if abs(raw_t) > DEADZONE else 0.0
	var steering := raw_s if abs(raw_s) > DEADZONE else 0.0

	var head_yaw   := 0.0
	var head_pitch := 0.0
	if head_tracker != null:
		var rot    := head_tracker.get_rotation()
		head_yaw   = rot.y
		head_pitch = rot.x

	control_output.send(throttle, steering, head_yaw, head_pitch, _armed)


func _recenter() -> void:
	if head_tracker != null:
		head_tracker.recenter()


func _toggle_arm() -> void:
	_armed = not _armed
