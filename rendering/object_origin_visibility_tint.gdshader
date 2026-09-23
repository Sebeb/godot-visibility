shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://rendering/visibility_mask_common.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture_albedo = false;
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_disable;
uniform bool use_icon_overlay = false;
uniform sampler2D icon_texture : source_color, filter_nearest, repeat_disable;
uniform float icon_radius : hint_range(0.001, 4.0) = 0.32;
uniform float icon_alpha_threshold : hint_range(0.0, 1.0) = 0.05;
uniform bool invert_icon_colors = false;
uniform bool identity_hidden = false;
uniform float color_tint_strength : hint_range(0.0, 1.0) = 0.95;
uniform bool gold_shine_enabled = false;
uniform float gold_shine_strength : hint_range(0.0, 4.0) = 1.0;
uniform float gold_shine_width : hint_range(0.001, 0.5) = 0.08;
uniform bool toxin_tint_enabled = false;
uniform vec4 toxin_tint_color : source_color = vec4(0.32, 0.90, 0.20, 1.0);
uniform float toxin_tint_weight : hint_range(0.0, 1.0) = 0.75;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform bool backlight_enabled = false;
uniform vec4 backlight : source_color = vec4(1.0);

instance uniform bool use_visibility_sample_world_position = false;
instance uniform vec3 visibility_sample_world_position = vec3(0.0);

varying vec3 object_origin_world;
varying vec3 world_pos;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	object_origin_world = MODEL_MATRIX[3].xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float sample_visibility() {
	// Per-fragment lookup, like maze_walls_visibility.gdshader, so a mesh straddling
	// the fog edge fades across its own surface instead of popping as one unit.
	// The entity-root offset keeps the whole draw anchored where MaskManager placed it,
	// so nested wobble/billboard transforms still cannot drag the lookup around.
	vec3 anchor_offset = use_visibility_sample_world_position
		? visibility_sample_world_position - object_origin_world
		: vec3(0.0);
	return sample_visibility_at_world_pos(world_pos + anchor_offset);
}

vec4 sample_icon_overlay() {
	if (!use_icon_overlay) {
		return vec4(0.0);
	}

	float cap_mask = smoothstep(0.72, 0.94, abs(local_normal.y));
	if (cap_mask <= 0.0) {
		return vec4(0.0);
	}

	vec2 icon_uv = (local_pos.xz / max(icon_radius * 2.0, 0.0001)) + vec2(0.5);
	if (local_normal.y < 0.0) {
		icon_uv.y = 1.0 - icon_uv.y;
	}
	if (icon_uv.x < 0.0 || icon_uv.y < 0.0 || icon_uv.x > 1.0 || icon_uv.y > 1.0) {
		return vec4(0.0);
	}

	vec4 icon = texture(icon_texture, icon_uv);
	if (invert_icon_colors) {
		icon.rgb = vec3(1.0) - icon.rgb;
	}
	icon.a *= cap_mask * step(icon_alpha_threshold, icon.a);
	return icon;
}

vec3 apply_color_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	float edge_coverage = smoothstep(0.08, 0.88, clamp(luma, 0.0, 1.0));
	float coverage = mix(clamp(luma, 0.0, 1.0), edge_coverage, color_tint_strength);
	vec3 effective_color = toxin_tint_enabled
		? mix(albedo_color.rgb, toxin_tint_color.rgb, toxin_tint_weight)
		: albedo_color.rgb;
	if (identity_hidden) {
		effective_color = mix(effective_color, vec3(0.82), 0.12);
	}
	return effective_color * coverage;
}

vec3 apply_gold_shine(vec3 color) {
	if (!gold_shine_enabled) {
		return color;
	}

	float shine_center = sin(TIME * 1.6) * 0.52;
	float shine_line = local_pos.x + local_pos.z * 0.58 - shine_center;
	float shine = smoothstep(gold_shine_width, 0.0, abs(shine_line));
	float cap_highlight = pow(clamp(abs(local_normal.y), 0.0, 1.0), 2.0);
	return color + albedo_color.rgb * (shine * 0.55 + cap_highlight * 0.16) * gold_shine_strength;
}

void fragment() {
	vec4 tex = use_texture_albedo ? texture(texture_albedo, UV) : vec4(1.0);
	vec4 base = tex * COLOR;
	// The black body is the black modifier's own treatment, so it must not depend on the
	// pill carrying an icon: a hidden pill has no icon overlay and still has to read as
	// black when it is a black pill.
	if (invert_icon_colors) {
		base.rgb = vec3(0.0);
	} else {
		base.rgb = apply_color_tint(base.rgb);
	}
	vec4 icon = sample_icon_overlay();
	icon.rgb = apply_color_tint(icon.rgb);
	base.rgb = mix(base.rgb, icon.rgb, icon.a);
	base.a = max(base.a, icon.a);
	base.rgb = apply_gold_shine(base.rgb);
	float visibility = sample_visibility();

	ALBEDO = base.rgb * visibility;
	ALPHA = base.a;
	METALLIC = gold_shine_enabled ? 0.72 : 0.0;
	SPECULAR = (gold_shine_enabled ? max(specular, 0.9) : specular) * visibility;
	ROUGHNESS = gold_shine_enabled ? min(roughness, 0.24) : roughness;
	EMISSION = base.rgb * visibility * emission_strength * (gold_shine_enabled ? 0.35 : 1.0);
	BACKLIGHT = (backlight_enabled ? backlight.rgb : vec3(0.0)) * visibility;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
