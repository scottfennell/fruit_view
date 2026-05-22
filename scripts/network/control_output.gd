# ControlOutput
#
# Abstract base class for sending vehicle control packets.
#
# Packet schema (implemented by UDPControlOutput):
#   throttle   : f32  — [-1.0, 1.0]  negative = reverse, positive = forward
#   steering   : f32  — [-1.0, 1.0]  negative = left, positive = right
#   head_yaw   : f32  — radians, current head yaw from HeadTracker
#   head_pitch : f32  — radians, current head pitch from HeadTracker
#   aux_count  : u8   — number of auxiliary channel values that follow
#   aux[]      : f32[] — arbitrary auxiliary channels (camera tilt, lights, etc.)

class_name ControlOutput
extends Node


func send(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	aux:        Array = []
) -> void:
	pass
