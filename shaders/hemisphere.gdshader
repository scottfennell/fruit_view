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
	vec3 video = texture(video_texture, uv).rgb;

	// Debug grid: shown when no live video is connected (video_texture is the
	// default all-white texture). Gives a visible reference for verifying head
	// tracking and hemisphere geometry without a real video feed.
	// Auto-replaced by the real frame once a VideoSource starts delivering frames.
	float cx      = mod(floor(uv.x * 10.0), 2.0);
	float cy      = mod(floor(uv.y *  6.0), 2.0);
	vec3  col_a   = vec3(0.15, 0.45, 0.85);  // blue
	vec3  col_b   = vec3(0.85, 0.55, 0.10);  // orange
	vec3  grid    = mix(col_a, col_b, mod(cx + cy, 2.0));

	// U and V axis labels baked into tint so orientation is readable at a glance.
	grid = mix(grid, vec3(uv.x, 0.2, 1.0 - uv.x), 0.25);

	// When the default-white texture is active every pixel sums to ~3.0.
	// Switch to the grid; once a real frame arrives this branch becomes 0.
	float no_video = step(2.99, video.r + video.g + video.b);
	ALBEDO = mix(video, grid, no_video);
}
