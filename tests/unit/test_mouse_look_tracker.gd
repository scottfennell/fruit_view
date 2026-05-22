# test_mouse_look_tracker.gd
#
# Unit tests for MouseLookTracker.
# Requires the GUT addon: https://github.com/bitwes/Gut
# Install via the Godot editor AssetLib or place the addon in addons/gut/.

extends GutTest

var _tracker: MouseLookTracker


func before_each() -> void:
	_tracker = MouseLookTracker.new()
	# Skip mouse capture in tests — add_child triggers _ready
	add_child_autofree(_tracker)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_motion(dx: float, dy: float) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, dy)
	return e


# ── Tests ──────────────────────────────────────────────────────────────────────

func test_initial_rotation_is_zero() -> void:
	assert_eq(_tracker.get_rotation(), Vector3.ZERO,
		"Rotation should be zero before any input")


func test_rightward_mouse_decreases_yaw() -> void:
	_tracker._input(_make_motion(100.0, 0.0))
	var rot := _tracker.get_rotation()
	assert_lt(rot.y, 0.0, "Rightward mouse motion should decrease yaw (turn right)")


func test_leftward_mouse_increases_yaw() -> void:
	_tracker._input(_make_motion(-100.0, 0.0))
	var rot := _tracker.get_rotation()
	assert_gt(rot.y, 0.0, "Leftward mouse motion should increase yaw (turn left)")


func test_downward_mouse_decreases_pitch() -> void:
	_tracker._input(_make_motion(0.0, 100.0))
	var rot := _tracker.get_rotation()
	assert_lt(rot.x, 0.0, "Downward mouse motion should decrease pitch (look down)")


func test_upward_mouse_increases_pitch() -> void:
	_tracker._input(_make_motion(0.0, -100.0))
	var rot := _tracker.get_rotation()
	assert_gt(rot.x, 0.0, "Upward mouse motion should increase pitch (look up)")


func test_pitch_clamped_at_positive_half_pi() -> void:
	_tracker._input(_make_motion(0.0, -100_000.0))
	var rot := _tracker.get_rotation()
	assert_almost_eq(rot.x, PI * 0.5, 0.001,
		"Pitch should not exceed +PI/2 (looking straight up)")


func test_pitch_clamped_at_negative_half_pi() -> void:
	_tracker._input(_make_motion(0.0, 100_000.0))
	var rot := _tracker.get_rotation()
	assert_almost_eq(rot.x, -PI * 0.5, 0.001,
		"Pitch should not go below -PI/2 (looking straight down)")


func test_roll_is_always_zero() -> void:
	_tracker._input(_make_motion(50.0, 50.0))
	var rot := _tracker.get_rotation()
	assert_eq(rot.z, 0.0, "Roll should always be zero")


func test_yaw_accumulates_across_multiple_inputs() -> void:
	_tracker._input(_make_motion(10.0, 0.0))
	_tracker._input(_make_motion(10.0, 0.0))
	_tracker._input(_make_motion(10.0, 0.0))
	var single := MouseLookTracker.new()
	add_child_autofree(single)
	single._input(_make_motion(30.0, 0.0))
	assert_almost_eq(
		_tracker.get_rotation().y,
		single.get_rotation().y,
		0.0001,
		"Accumulated motion should equal equivalent single large motion"
	)
