# LocalFileSource
#
# VideoSource implementation backed by Godot's built-in VideoStreamPlayer.
# Intended for development and offline testing — no network or external process
# required.
#
# Supported formats: .ogv (Ogg Theora). Other formats require a GDExtension.
#
# Configuration (project.godot):
#   video/local_file_path — res:// path to the video file (default: empty = no video)

class_name LocalFileSource
extends VideoSource

const SETTING_PATH := "video/local_file_path"
const DEFAULT_PATH := ""

var _player: VideoStreamPlayer


func _ready() -> void:
	_player = VideoStreamPlayer.new()
	# Must be visible in the scene tree to decode frames; hide it visually.
	_player.visible = false
	add_child(_player)

	var path := ProjectSettings.get_setting(SETTING_PATH, DEFAULT_PATH) as String
	if path.is_empty():
		push_warning("LocalFileSource: no file path set (video/local_file_path). " +
					 "Set it in project.godot to load a test video.")
		return

	var stream := load(path)
	if stream == null:
		push_error("LocalFileSource: could not load video at '%s'" % path)
		return

	_player.stream = stream
	_player.autoplay = true
	_player.play()


func get_texture() -> Texture2D:
	if _player != null and _player.is_playing():
		return _player.get_video_texture()
	return null


func is_playing() -> bool:
	return _player != null and _player.is_playing()
