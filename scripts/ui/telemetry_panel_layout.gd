# TelemetryPanelLayout
#
# Resource that defines the position and wiring of each TelemetryPanel on the
# hemisphere surface.  Stored as a .tres file so positions can be edited in the
# Godot Inspector without changing code.
#
# The default layout lives at res://data/telemetry_panel_layout.tres.
# To customise positions, duplicate that file, edit it in the Inspector, and
# point override.cfg at the new path — no rebuild required.
#
# Each entry in `panels` is a Dictionary with the following keys:
#   signal  (String)  — signal name on TelemetryInput (e.g. "battery_voltage_changed")
#   prefix  (String)  — label prefix prepended to the value (e.g. "Bat:  ")
#   az      (float)   — azimuth in degrees (-90° left to +90° right)
#   el      (float)   — elevation in degrees (-90° down to +90° up)

class_name TelemetryPanelLayout
extends Resource

@export var panels: Array = []
