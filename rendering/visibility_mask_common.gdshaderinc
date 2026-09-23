uniform bool visibility_mask_enabled = false;
uniform sampler2D current_visibility_tex : source_color;
uniform bool camera_room_mask_enabled = false;
uniform sampler2D camera_room_mask_tex_from : source_color;
uniform sampler2D camera_room_mask_tex_to : source_color;
uniform float camera_room_mask_blend : hint_range(0.0, 1.0) = 1.0;
uniform vec3 visibility_world_origin = vec3(0.0);
uniform mat3 visibility_world_to_maze_basis = mat3(1.0);
uniform vec2 visibility_maze_min_xz = vec2(0.0);
uniform vec2 visibility_maze_size_xz = vec2(1.0);

float sample_camera_room_mask(vec2 uv) {
	if (!camera_room_mask_enabled) {
		return 1.0;
	}
	float from_mask = texture(camera_room_mask_tex_from, uv).r;
	float to_mask = texture(camera_room_mask_tex_to, uv).r;
	return clamp(mix(from_mask, to_mask, clamp(camera_room_mask_blend, 0.0, 1.0)), 0.0, 1.0);
}

float sample_visibility_at_world_pos(vec3 world_pos) {
	vec3 maze_pos = visibility_world_to_maze_basis * (world_pos - visibility_world_origin);
	vec2 maze_size = max(visibility_maze_size_xz, vec2(0.0001));
	vec2 uv = (maze_pos.xz - visibility_maze_min_xz) / maze_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	float visibility = visibility_mask_enabled ? clamp(texture(current_visibility_tex, uv).r, 0.0, 1.0) : 1.0;
	return visibility * sample_camera_room_mask(uv);
}
