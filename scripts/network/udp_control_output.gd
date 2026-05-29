# UDPControlOutput
#
# Serialises viewer control values into the fixed-length 8-channel RC packet and
# sends it to the vehicle Pi over UDP. Also fires a neutral keepalive packet when no
# send() call has been made within the configured idle interval.
#
# Packet layout (all values little-endian):
#   Offset  0 : magic         (char[4] = "FRC1")
#   Offset  4 : version       (u8 = 1)
#   Offset  5 : channel_count (u8 = 8)
#   Offset  6 : reserved      (u16 = 0)
#   Offset  8 : vehicle_id    (u32)
#   Offset 12 : tick          (u32)
#   Offset 16 : channels      (f32[8])
#
# Viewer semantic mapping:
#   ch1 = left track  = clamp(throttle + steering)
#   ch2 = right track = clamp(throttle - steering)
#   ch3 = head yaw    = clamp(head_yaw)
#   ch4 = head pitch  = clamp(head_pitch)
#   ch5 = arm switch  = 1.0 when armed, otherwise 0.0
#   ch6..ch8 = spare  = 0.0
#
# Configuration (project.godot):
#   control/vehicle_host           — IP of the vehicle Pi (default 192.168.86.18)
#   control/vehicle_port           — UDP port on the Pi   (default 9000)
#   control/vehicle_id             — target vehicle id    (default 100)
#   control/keepalive_interval_sec — seconds between keepalives when idle (default 0.5)

class_name UDPControlOutput
extends ControlOutput

const SETTING_HOST      := "control/vehicle_host"
const SETTING_PORT      := "control/vehicle_port"
const SETTING_VEHICLE_ID := "control/vehicle_id"
const SETTING_KEEPALIVE := "control/keepalive_interval_sec"

const DEFAULT_HOST      := "192.168.86.18"
const DEFAULT_PORT      := 9000
const DEFAULT_VEHICLE_ID := 100
const DEFAULT_KEEPALIVE := 0.5

const PACKET_MAGIC     := "FRC1"
const PACKET_VERSION   := 1
const CHANNEL_COUNT    := 8
const PACKET_SIZE      := 48
const TICK_WRAP        := 4294967295

var _socket:             PacketPeerUDP = PacketPeerUDP.new()
var _keepalive_interval: float
var _time_since_send:    float = 0.0
var _vehicle_id:         int
var _tick:               int = 0


func _ready() -> void:
	var host := ProjectSettings.get_setting(SETTING_HOST, DEFAULT_HOST) as String
	var port := ProjectSettings.get_setting(SETTING_PORT, DEFAULT_PORT) as int
	_vehicle_id = ProjectSettings.get_setting(SETTING_VEHICLE_ID, DEFAULT_VEHICLE_ID) as int
	_keepalive_interval = ProjectSettings.get_setting(
		SETTING_KEEPALIVE, DEFAULT_KEEPALIVE
	) as float
	_socket.set_dest_address(host, port)


func _process(delta: float) -> void:
	_time_since_send += delta
	if _time_since_send >= _keepalive_interval:
		# Keep the vehicle session alive with a neutral, disarmed packet.
		_transmit(_build_packet(0.0, 0.0, 0.0, 0.0, false, _next_tick(), _vehicle_id))


func send(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	armed:      bool = false
) -> void:
	_transmit(
		_build_packet(throttle, steering, head_yaw, head_pitch, armed, _next_tick(), _vehicle_id)
	)


# Returns the serialised packet as a PackedByteArray.
# Kept separate from send() so tests can inspect the byte layout directly.
func _build_packet(
	throttle:   float,
	steering:   float,
	head_yaw:   float,
	head_pitch: float,
	armed:      bool,
	tick:       int,
	vehicle_id: int
) -> PackedByteArray:
	var left_track := _clamp_channel(throttle + steering)
	var right_track := _clamp_channel(throttle - steering)
	var arm_value := 1.0 if armed else 0.0
	var channels := [
		left_track,
		right_track,
		_clamp_channel(head_yaw),
		_clamp_channel(head_pitch),
		arm_value,
		0.0,
		0.0,
		0.0,
	]

	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data(PACKET_MAGIC.to_utf8_buffer())
	buf.put_u8(PACKET_VERSION)
	buf.put_u8(CHANNEL_COUNT)
	buf.put_u16(0)
	buf.put_u32(vehicle_id)
	buf.put_u32(tick)
	for value in channels:
		buf.put_float(value)
	assert(buf.data_array.size() == PACKET_SIZE)
	return buf.data_array


func _clamp_channel(value: float) -> float:
	return clampf(value, -1.0, 1.0)


func _next_tick() -> int:
	_tick += 1
	if _tick > TICK_WRAP:
		_tick = 1
	return _tick


func _transmit(packet: PackedByteArray) -> void:
	_socket.put_packet(packet)
	_time_since_send = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_socket.close()
