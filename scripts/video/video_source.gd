# VideoSource
#
# Abstract base class for video frame providers.
# Implementations hide the details of their decode pipeline behind two methods.
#
# Implementations:
#   LocalFileSource       — Godot VideoStreamPlayer (development / offline)
#   RTSPGStreamerSource   — external GStreamer sidecar via Unix socket (issue #7)

class_name VideoSource
extends Node


# Returns the current decoded video frame as a Texture2D, or null if not ready.
func get_texture() -> Texture2D:
	return null


# Returns true when the source is actively delivering frames.
func is_playing() -> bool:
	return false


# Returns a human-readable status string for display when not playing.
# Empty string means the source is playing normally and no overlay is needed.
func get_status_text() -> String:
	return ""
