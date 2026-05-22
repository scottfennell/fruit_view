# TelemetryInput
#
# Receives binary telemetry packets from the vehicle Pi over UDP and emits
# a typed Godot signal for each field. Consumers (TelemetryPanel nodes) connect
# to these signals — they never touch the network layer directly.
#
# Packet layout (little-endian, 28 bytes total):
#   Offset  0 : battery_voltage (f32, volts)
#   Offset  4 : speed           (f32, m/s)
#   Offset  8 : signal_rssi     (f32, dBm — typically negative)
#   Offset 12 : gps_lat         (f64, decimal degrees)
#   Offset 20 : gps_lon         (f64, decimal degrees)
#
# Malformed packets (< PACKET_SIZE bytes) are silently dropped.
#
# Configuration (project.godot):
#   telemetry/port — UDP port to bind for incoming packets (default 9002)

class_name TelemetryInput
extends Node

const PACKET_SIZE  := 28
const SETTING_PORT := "telemetry/port"
const DEFAULT_PORT := 9002

signal battery_voltage_changed(volts: float)
signal speed_changed(metres_per_second: float)
signal signal_rssi_changed(dbm: float)
signal gps_position_changed(lat: float, lon: float)

var _socket: PacketPeerUDP = PacketPeerUDP.new()


func _ready() -> void:
	var port := ProjectSettings.get_setting(SETTING_PORT, DEFAULT_PORT) as int
	var err  := _socket.bind(port)
	if err != OK:
		push_error("TelemetryInput: failed to bind UDP port %d (error %d)" % [port, err])


func _process(_delta: float) -> void:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if packet.size() >= PACKET_SIZE:
			_parse_and_emit(packet)


# Parse a complete telemetry packet and emit signals.
# Exposed (not prefixed __) so unit tests can inject packets directly.
func _parse_and_emit(data: PackedByteArray) -> void:
	var battery := data.decode_float(0)
	var speed   := data.decode_float(4)
	var rssi    := data.decode_float(8)
	var lat     := data.decode_double(12)
	var lon     := data.decode_double(20)

	battery_voltage_changed.emit(battery)
	speed_changed.emit(speed)
	signal_rssi_changed.emit(rssi)
	gps_position_changed.emit(lat, lon)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_socket.close()
