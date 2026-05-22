# UDPControlOutput
#
# Serialises control values into a fixed binary packet and sends it to the
# vehicle Pi over UDP. Also fires a zero-throttle keepalive packet when no
# send() call has been made within the configured idle interval.
#
# Packet layout (all values little-endian):
#   Offset  0 : throttle   (f32)
#   Offset  4 : steering   (f32)
#   Offset  8 : head_yaw   (f32)
#   Offset 12 : head_pitch (f32)
#   Offset 16 : aux_count  (u8)
#   Offset 17+: aux[n]     (f32 × aux_count)
#
# Configuration (project.godot):
#   control/vehicle_host           — IP of the vehicle Pi (default 192.168.1.100)
#   control/vehicle_port           — UDP port on the Pi   (default 9000)
#   control/keepalive_interval_sec — seconds between keepalives when idle (default 0.5)

class_name UDPControlOutput
extends ControlOutput

const SETTING_HOST      := "control/vehicle_host"
const SETTING_PORT      := "control/vehicle_port"
const SETTING_KEEPALIVE := "control/keepalive_interval_sec"

const DEFAULT_HOST      := "192.168.1.100"
const DEFAULT_PORT      := 9000
const DEFAULT_KEEPALIVE := 0.5

var _socket:             PacketPeerUDP = PacketPeerUDP.new()
var _keepalive_interval: float
var _time_since_send:    float = 0.0


func _ready() -> void:
	var host := ProjectSettings.get_setting(SETTING_HOST, DEFAULT_HOST) as String
	var port := ProjectSettings.get_setting(SETTING_PORT, DEFAULT_PORT) as int
	_keepalive_interval = ProjectSettings.get_setting(
		SETTING_KEEPALIVE, DEFAULT_KEEPALIVE
	) as float
	_socket.set_dest_address(host, port)


func _process(delta: float) -> void:
	_time_since_send += delta
	if _time_since_send >= _keepalive_interval:
		# Fire a zero-throttle heartbeat so the Pi knows the link is alive.
		_transmit(_build_packet(0.0, 0.0, 0.0, 0.0, []))


func send(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	aux:        Array = []
) -> void:
	_transmit(_build_packet(throttle, steering, head_yaw, head_pitch, aux))


# Returns the serialised packet as a PackedByteArray.
# Kept separate from send() so tests can inspect the byte layout directly.
func _build_packet(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	aux:        Array
) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_float(throttle)
	buf.put_float(steering)
	buf.put_float(head_yaw)
	buf.put_float(head_pitch)
	buf.put_u8(min(aux.size(), 255))
	for value in aux:
		buf.put_float(float(value))
	return buf.data_array


func _transmit(packet: PackedByteArray) -> void:
	_socket.put_packet(packet)
	_time_since_send = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_socket.close()
