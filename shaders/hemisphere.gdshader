shader_type spatial;
// Render unlit; disable back-face culling so the surface is visible from inside.
render_mode unshaded, cull_disabled;

// Video texture applied to the hemisphere interior.
// Defaults to opaque white until a VideoSource is wired up.
uniform sampler2D video_texture : source_color, hint_default_white;

// Radial distortion coefficient reserved for future OpenCV lens calibration.
// 0.0 = identity (no correction). Positive values apply barrel correction.
uniform float distortion_k1 : hint_range(-1.0, 1.0) = 0.0;

void fragment() {
	// Placeholder for future distortion correction:
	// When distortion_k1 != 0, UV will be warped here using the Brown-Conrady model.
	// For now, pass UV straight through.
	vec2 uv = UV;
	ALBEDO = texture(video_texture, uv).rgb;
}
