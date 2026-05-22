# HeadTracker
#
# Abstract base class for all head tracking implementations.
# Provides a single unified interface consumed by main.gd each frame.
#
# Implementations:
#   MouseLookTracker      — mouse delta accumulation for Mac development
#   OpenTrackUDPTracker   — XRLinuxDriver via OpenTrack UDP (Orange Pi + XREAL)
#   OpenXRTracker         — Godot XRServer for Meta Quest (future)

class_name HeadTracker
extends Node


# Returns the current head orientation as (pitch, yaw, roll) in radians.
#
#   pitch (x): rotation around X axis — positive = look up
#   yaw   (y): rotation around Y axis — positive = look left
#   roll  (z): rotation around Z axis — unused initially, always 0
func get_rotation() -> Vector3:
	return Vector3.ZERO
