# test_telemetry_input.gd
#
# Unit tests for TelemetryInput.
# Tests _parse_and_emit() directly — no live UDP socket required.

extends GutTest

var _input: TelemetryInput

# Signal capture helpers
var _last_battery:  float = -1.0
var _last_speed:    float = -1.0
var _last_rssi:     float = -1.0
var _last_gps_lat:  float = -999.0
var _last_gps_lon:  float = -999.0
var _signal_counts: Dictionary = {}


func before_each() -> void:
	_input = TelemetryInput.new()
	add_child_autofree(_input)

	_last_battery = -1.0
	_last_speed   = -1.0
	_last_rssi    = -1.0
	_last_gps_lat = -999.0
	_last_gps_lon = -999.0
	_signal_counts = {
		"battery_voltage_changed": 0,
		"speed_changed":           0,
		"signal_rssi_changed":     0,
		"gps_position_changed":    0,
	}

	_input.battery_voltage_changed.connect(func(v): _last_battery = v; _signal_counts["battery_voltage_changed"] += 1)
	_input.speed_changed.connect(func(v): _last_speed = v; _signal_counts["speed_changed"] += 1)
	_input.signal_rssi_changed.connect(func(v): _last_rssi = v; _signal_counts["signal_rssi_changed"] += 1)
	_input.gps_position_changed.connect(func(lat, lon): _last_gps_lat = lat; _last_gps_lon = lon; _signal_counts["gps_position_changed"] += 1)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_packet(
	battery: float,
	speed:   float,
	rssi:    float,
	lat:     float,
	lon:     float
) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(28)
	data.encode_float(0,  battery)
	data.encode_float(4,  speed)
	data.encode_float(8,  rssi)
	data.encode_double(12, lat)
	data.encode_double(20, lon)
	return data


# ── Signal emission tests ──────────────────────────────────────────────────────

func test_battery_voltage_signal_emitted_with_correct_value() -> void:
	_input._parse_and_emit(_make_packet(12.4, 0.0, 0.0, 0.0, 0.0))
	assert_almost_eq(_last_battery, 12.4, 0.001, "battery_voltage_changed value")


func test_speed_signal_emitted_with_correct_value() -> void:
	_input._parse_and_emit(_make_packet(0.0, 3.5, 0.0, 0.0, 0.0))
	assert_almost_eq(_last_speed, 3.5, 0.001, "speed_changed value")


func test_rssi_signal_emitted_with_correct_value() -> void:
	_input._parse_and_emit(_make_packet(0.0, 0.0, -72.0, 0.0, 0.0))
	assert_almost_eq(_last_rssi, -72.0, 0.001, "signal_rssi_changed value")


func test_gps_lat_lon_emitted_correctly() -> void:
	_input._parse_and_emit(_make_packet(0.0, 0.0, 0.0, 37.7749, -122.4194))
	assert_almost_eq(_last_gps_lat,  37.7749,   0.00001, "gps_position_changed lat")
	assert_almost_eq(_last_gps_lon, -122.4194,  0.00001, "gps_position_changed lon")


func test_all_four_signals_emitted_per_packet() -> void:
	_input._parse_and_emit(_make_packet(12.0, 2.0, -65.0, 1.0, 2.0))
	for signal_name in _signal_counts:
		assert_eq(_signal_counts[signal_name], 1,
			"Signal '%s' should fire exactly once per packet" % signal_name)


func test_two_packets_emit_signals_twice() -> void:
	_input._parse_and_emit(_make_packet(11.0, 1.0, -60.0, 0.0, 0.0))
	_input._parse_and_emit(_make_packet(10.0, 2.0, -70.0, 1.0, 1.0))
	assert_eq(_signal_counts["battery_voltage_changed"], 2,
		"Each packet should trigger its own signal emission")
	assert_almost_eq(_last_battery, 10.0, 0.001,
		"Last received value should be from the most recent packet")


func test_short_packet_emits_no_signals() -> void:
	# _parse_and_emit has a size guard that silently discards truncated packets.
	# Verify that calling it directly with a short payload emits no signals.
	var short := PackedByteArray()
	short.resize(10)
	_input._parse_and_emit(short)
	for signal_name in _signal_counts:
		assert_eq(_signal_counts[signal_name], 0,
			"Signal '%s' must not be emitted for a truncated packet" % signal_name)
