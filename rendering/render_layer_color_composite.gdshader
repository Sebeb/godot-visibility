shader_type canvas_item;
render_mode unshaded, blend_mix;

// Canvas render-target textures store premultiplied RGB. Normalize those
// members back to straight alpha before blend_mix so translucent fills and
// antialiased edges are not multiplied by alpha a second time.
uniform sampler2D source_tex : source_color, filter_nearest;
uniform bool source_is_premultiplied = false;

void fragment() {
	vec4 sampled = texture(source_tex, UV);
	if (source_is_premultiplied) {
		sampled.rgb = sampled.a > 0.00001 ? sampled.rgb / sampled.a : vec3(0.0);
	}
	COLOR = sampled * COLOR;
}
