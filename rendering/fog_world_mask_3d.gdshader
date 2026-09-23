shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;

uniform sampler2D mask_tex : source_color;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float visibility = texture(mask_tex, UV).r;
	ALBEDO = vec3(0.0);
	ALPHA = clamp((1.0 - visibility) * opacity, 0.0, 1.0);
}
