shader_type canvas_item;
render_mode unshaded, blend_add;

// Render-mask object layers are visualization content, not scalar masking at
// this boundary. Black contributes nothing; white contributes the full tint.
uniform sampler2D source_tex : source_color, filter_nearest;
uniform vec4 source_tint : source_color = vec4(1.0);

void fragment() {
	float intensity = texture(source_tex, UV).r;
	COLOR = vec4(source_tint.rgb * intensity, source_tint.a * intensity);
}
