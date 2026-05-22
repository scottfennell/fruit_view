# OpenTrackUDPTracker
#
# HeadTracker implementation that receives head pose from XRLinuxDriver via the
# OpenTrack UDP protocol. Binds a local UDP port and parses incoming packets.
#
# OpenTrack payload format (48 bytes, all values little-endian float64):
#   Offset  0 : x     (mm, translation — unused)
#   Offset  8 : y     (mm, translation — unused)
#   Offset 16 : z     (mm, translation — unused)
#   Offset 24 : yaw   (degrees, positive = right)
#   Offset 32 : pitch (degrees, positive = up)
#   Offset 40 : roll  (degrees — unused initially)
#
# XRLinuxDriver must be configured to send to 127.0.0.1:<opentrack_port>.
#
# Configuration (project.godot):
#   head_tracker/opentrack_port — local UDP port to bind (default 4242)

class_name OpenTrackUDPTracker
extends HeadTracker

const PAYLOAD_SIZE := 48  # 6 × 8 bytes (float64)
const SETTING_PORT := "head_tracker/opentrack_port"
const DEFAULT_PORT := 4242

var _socket: PacketPeerUDP = PacketPeerUDP.new()
var _yaw:    float = 0.0
var _pitch:  float = 0.0


func _ready() -> void:
	var port := ProjectSettings.get_setting(SETTING_PORT, DEFAULT_PORT) as int
	var err   := _socket.bind(port)
	if err != OK:
		push_error(
			"OpenTrackUDPTracker: failed to bind UDP port %d (error %d). " % [port, err] +
			"Ensure XRLinuxDriver is sending to 127.0.0.1:%d." % port
		)


func _process(_delta: float) -> void:
	# Drain the receive buffer each frame, keeping only the latest packet.
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if packet.size() >= PAYLOAD_SIZE:
			_parse_packet(packet)


# Parse a 48-byte OpenTrack payload and update internal yaw/pitch.
# Exposed (not private) so unit tests can call it directly without a socket.
func _parse_packet(data: PackedByteArray) -> void:
	# PackedByteArray.decode_double(offset) reads 8 bytes as a little-endian float64.
	# Offsets: x=0, y=8, z=16, yaw=24, pitch=32, roll=40
	_yaw   = deg_to_rad(data.decode_double(24))
	_pitch = deg_to_rad(data.decode_double(32))


func get_rotation() -> Vector3:
	return Vector3(_pitch, _yaw, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_socket.close()
