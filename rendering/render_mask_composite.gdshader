shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D source_tex : source_color;
uniform sampler2D mask_0 : source_color;
uniform sampler2D mask_1 : source_color;
uniform sampler2D mask_2 : source_color;
uniform sampler2D mask_3 : source_color;
uniform int mode_0 = 0;
uniform int mode_1 = 0;
uniform int mode_2 = 0;
uniform int mode_3 = 0;
uniform bool apply_to_source = false;
uniform bool source_is_premultiplied = false;
// PGO-96 stage ④: `source_tex` (when present) is a render layer's own raw
// texture, sampled 1:1 at this composite's UV (the destination viewport is
// always sized to match it). The mask textures (`mask_0`..`mask_3`) are
// always rendered at full-world resolution regardless of the render layer's
// own coverage sub-rect, so they need remapping into full-world UV space:
// `mask_uv = UV * uv_scale + uv_offset`, where `uv_offset`/`uv_scale` are the
// render layer's `coverage.world_rect` expressed as a fraction of the full
// world (see `FogCameraManager._update_render_mask_outputs_if_needed`).
// Defaults (0,0)/(1,1) are the identity mapping used for the full-world
// `game_world` target, which never sets these.
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);

void apply_mask(float value, int mode, inout float multiplicative, inout float additive) {
	if (mode == 2) {
		multiplicative *= value;
	} else if (mode == 1) {
		additive += value;
	}
}

void fragment() {
	vec2 mask_uv = UV * uv_scale + uv_offset;
	float multiplicative = 1.0;
	float additive = 0.0;
	apply_mask(texture(mask_0, mask_uv).r, mode_0, multiplicative, additive);
	apply_mask(texture(mask_1, mask_uv).r, mode_1, multiplicative, additive);
	apply_mask(texture(mask_2, mask_uv).r, mode_2, multiplicative, additive);
	apply_mask(texture(mask_3, mask_uv).r, mode_3, multiplicative, additive);
	if (!apply_to_source) {
		float result = clamp(multiplicative + additive, 0.0, 1.0);
		COLOR = vec4(vec3(result), 1.0);
	} else {
		vec4 source = texture(source_tex, UV);
		// Canvas render-target inputs use premultiplied RGB. Normalize to
		// straight alpha before blend_mix, matching render_layer_color_composite.
		if (source_is_premultiplied) {
			source.rgb = source.a > 0.00001 ? source.rgb / source.a : vec3(0.0);
		}
		// A visibility mask changes visible colour contribution only. It must
		// never modify the source coverage or add coverage to transparent texels.
		source.rgb = clamp(source.rgb * multiplicative + vec3(additive), vec3(0.0), vec3(1.0));
		COLOR = source;
	}
}
