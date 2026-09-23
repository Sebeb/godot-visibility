shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool eye_recolor_enabled = false;
uniform vec4 eye_replacement_color : source_color = vec4(1.0, 0.02, 0.02, 1.0);
uniform float eye_whiteness_threshold : hint_range(0.0, 1.0) = 0.75;

instance uniform bool use_visibility_sample_world_position = false;
instance uniform vec3 visibility_sample_world_position = vec3(0.0);

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

varying vec3 object_origin_world;

void vertex() {
	object_origin_world = MODEL_MATRIX[3].xyz;
}

float sample_camera_room_mask(vec2 uv) {
	if (!camera_room_mask_enabled) {
		return 1.0;
	}
	float from_mask = texture(camera_room_mask_tex_from, uv).r;
	float to_mask = texture(camera_room_mask_tex_to, uv).r;
	return clamp(mix(from_mask, to_mask, clamp(camera_room_mask_blend, 0.0, 1.0)), 0.0, 1.0);
}

float sample_visibility() {
	vec3 sample_world_pos = use_visibility_sample_world_position ? visibility_sample_world_position : object_origin_world;
	vec3 maze_pos = visibility_world_to_maze_basis * (sample_world_pos - visibility_world_origin);
	vec2 maze_size = max(visibility_maze_size_xz, vec2(0.0001));
	vec2 uv = (maze_pos.xz - visibility_maze_min_xz) / maze_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	float visibility = visibility_mask_enabled ? clamp(texture(current_visibility_tex, uv).r, 0.0, 1.0) : 1.0;
	return visibility * sample_camera_room_mask(uv);
}

void fragment() {
	vec4 tex = texture(sprite_texture, UV);
	float visibility = sample_visibility();
	bool is_eye_pixel = tex.r > eye_whiteness_threshold
		&& tex.g > eye_whiteness_threshold
		&& tex.b > eye_whiteness_threshold;
	vec3 sprite_albedo = eye_recolor_enabled && is_eye_pixel ? eye_replacement_color.rgb : tex.rgb;

	if (visibility <= 0.0) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
	} else {
		ALBEDO = sprite_albedo * COLOR.rgb * visibility;
		ALPHA = tex.a * COLOR.a;
		METALLIC = 0.0;
		SPECULAR = specular;
		ROUGHNESS = roughness;
	}

	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
