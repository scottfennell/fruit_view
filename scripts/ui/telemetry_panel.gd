# TelemetryPanel
#
# A Label3D positioned on the hemisphere surface at a fixed spherical
# coordinate, always facing the camera at the origin.
#
# Subscribes to TelemetryInput signals to update its displayed value live.
# The panel's label prefix and the signal it subscribes to are configured at
# construction time via setup().

class_name TelemetryPanel
extends Node3D

# Hemisphere radius is 50; place panels slightly inside so they read in front
# of the video texture (no z-fighting).
const DEFAULT_RADIUS := 48.0

var _label: Label3D
var _prefix: String = ""


func _ready() -> void:
	_label = Label3D.new()
	_label.font_size   = 64
	_label.outline_size = 8
	_label.modulate    = Color.WHITE
	_label.outline_modulate = Color.BLACK
	_label.billboard   = BaseMaterial3D.BILLBOARD_DISABLED
	_label.double_sided = true
	_label.text = _prefix + "—"
	add_child(_label)


# Position this panel on the hemisphere surface and wire it to a TelemetryInput.
#
# telemetry:     the TelemetryInput node to subscribe to
# signal_name:   name of the signal on TelemetryInput to connect
# prefix:        display text prepended to the value (e.g. "Bat: ")
# azimuth_deg:   horizontal angle in degrees (-90° left to +90° right)
# elevation_deg: vertical angle in degrees (-90° down to +90° up)
# radius:        distance from origin (default DEFAULT_RADIUS)
func setup(
	telemetry:     TelemetryInput,
	signal_name:   String,
	prefix:        String,
	azimuth_deg:   float,
	elevation_deg: float,
	radius:        float = DEFAULT_RADIUS
) -> void:
	_prefix = prefix
	_place_on_sphere(azimuth_deg, elevation_deg, radius)

	# Connect the appropriate signal.  gps_position_changed has two args;
	# all other signals have one.
	if signal_name == "gps_position_changed":
		telemetry.gps_position_changed.connect(_on_gps_position)
	else:
		telemetry.get(signal_name).connect(_on_single_value)


func _place_on_sphere(az_deg: float, el_deg: float, radius: float) -> void:
	var theta := deg_to_rad(az_deg)
	var phi   := deg_to_rad(el_deg)

	# Same coordinate mapping as HemisphereMeshBuilder: forward = -Z
	var x := cos(phi) * sin(theta)
	var y := sin(phi)
	var z := -cos(phi) * cos(theta)

	position = Vector3(x, y, z) * radius

	# Face the origin so the label is readable from the camera.
	# Guard against degenerate up-vector at the poles.
	var up := Vector3.UP if abs(y / radius) < 0.99 else Vector3.RIGHT
	look_at(Vector3.ZERO, up)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_single_value(value: float) -> void:
	_label.text = "%s%.2f" % [_prefix, value]


func _on_gps_position(lat: float, lon: float) -> void:
	_label.text = "%s%.5f, %.5f" % [_prefix, lat, lon]
