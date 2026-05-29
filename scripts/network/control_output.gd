# ControlOutput
#
# Abstract base class for sending vehicle control packets.
#
# Semantic control values expected from the viewer input layer:
#   throttle   : [-1.0, 1.0]  negative = reverse, positive = forward
#   steering   : [-1.0, 1.0]  negative = left, positive = right
#   head_yaw   : radians, current head yaw from HeadTracker
#   head_pitch : radians, current head pitch from HeadTracker
#   armed      : latched arm-switch state
#
# Concrete implementations may serialize these semantics into a transport-specific
# packet. UDPControlOutput mixes throttle + steering into left/right RC channels.

class_name ControlOutput
extends Node


func send(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	armed:      bool = false
) -> void:
	pass
