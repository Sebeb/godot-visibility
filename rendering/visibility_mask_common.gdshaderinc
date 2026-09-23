uniform bool visibility_mask_enabled = false;
uniform sampler2D current_visibility_tex : source_color;
uniform vec3 visibility_world_origin = vec3(0.0);
uniform mat3 visibility_world_to_local_basis = mat3(1.0);
uniform vec2 visibility_local_min_xz = vec2(0.0);
uniform vec2 visibility_local_size_xz = vec2(1.0);

float sample_visibility_at_world_pos(vec3 world_pos) {
	vec3 local_pos = visibility_world_to_local_basis * (world_pos - visibility_world_origin);
	vec2 local_size = max(visibility_local_size_xz, vec2(0.0001));
	vec2 uv = (local_pos.xz - visibility_local_min_xz) / local_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return visibility_mask_enabled ? clamp(texture(current_visibility_tex, uv).r, 0.0, 1.0) : 1.0;
}
