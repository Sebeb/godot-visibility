shader_type canvas_item;

uniform sampler2D mask_tex : source_color;
uniform bool camera_room_mask_enabled = false;
uniform sampler2D camera_room_mask_tex_from : source_color;
uniform sampler2D camera_room_mask_tex_to : source_color;
uniform float camera_room_mask_blend : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float visibility = texture(mask_tex, UV).r;
	if (camera_room_mask_enabled) {
		float from_mask = texture(camera_room_mask_tex_from, UV).r;
		float to_mask = texture(camera_room_mask_tex_to, UV).r;
		float room_mask = clamp(mix(from_mask, to_mask, clamp(camera_room_mask_blend, 0.0, 1.0)), 0.0, 1.0);
		visibility *= room_mask;
	}
	COLOR = vec4(0.0, 0.0, 0.0, clamp((1.0 - visibility) * opacity, 0.0, 1.0));
}
