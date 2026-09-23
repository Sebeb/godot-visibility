shader_type canvas_item;

uniform sampler2D walls_tex : source_color, filter_nearest;
uniform float world_rotation_radians = 0.0;

void fragment() {
	vec2 offset = UV - vec2(0.5);
	float cosine = cos(-world_rotation_radians);
	float sine = sin(-world_rotation_radians);
	vec2 walls_uv = vec2(
		offset.x * cosine - offset.y * sine,
		offset.x * sine + offset.y * cosine
	) + vec2(0.5);
	COLOR = texture(walls_tex, walls_uv);
}
