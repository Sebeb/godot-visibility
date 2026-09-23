shader_type canvas_item;

uniform sampler2D mask_tex : source_color;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float visibility = texture(mask_tex, UV).r;
	COLOR = vec4(0.0, 0.0, 0.0, clamp((1.0 - visibility) * opacity, 0.0, 1.0));
}
