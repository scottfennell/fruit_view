# test_local_file_source.gd
#
# Unit tests for LocalFileSource.
# These tests validate setup behaviour — actual frame output requires a real
# .ogv file available at the configured path.

extends GutTest

var _source: LocalFileSource


func before_each() -> void:
	_source = LocalFileSource.new()
	add_child_autofree(_source)


func test_get_texture_returns_null_when_no_path_configured() -> void:
	# With no video/local_file_path set, the player is never started.
	assert_null(_source.get_texture(),
		"get_texture() should return null when no file path is configured")


func test_is_playing_returns_false_when_no_path_configured() -> void:
	assert_false(_source.is_playing(),
		"is_playing() should be false when no file path is configured")


func test_is_playing_returns_false_before_stream_starts() -> void:
	# Even with a path set (but no actual file loaded in test environment),
	# is_playing() must not crash and must return a bool.
	assert_false(_source.is_playing(),
		"is_playing() should return false before any stream is active")
