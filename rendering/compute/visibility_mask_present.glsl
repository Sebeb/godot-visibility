#[compute]
#version 450

// PGO-101 stage ⑤: resolves the two simulation lanes into the single grayscale
// texture the world visibility materials sample.
//
// Presented visibility is the maximum applicable field value, so an
// occlusion-bypass source lights its own region without the normal lane ever
// having been allowed through the wall.
//
// `debug_mode = 1` instead reproduces the proof-of-concept diagnostic view:
// blue substrate, green organism (claim/seed), red blocker. Internal channel
// order differs from that view so the presented red channel stays the
// grayscale visibility every existing consumer already reads.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D packed_tex;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D state_in;
layout(set = 0, binding = 2, rgba8) uniform restrict writeonly image2D present_out;

layout(push_constant, std430) uniform Params {
	ivec4 sizes;  // sim_w, sim_h, debug_mode, unused
} params;

void main() {
	ivec2 sim_size = params.sizes.xy;
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= sim_size.x || p.y >= sim_size.y || sim_size.x <= 0 || sim_size.y <= 0) {
		return;
	}
	vec4 state = imageLoad(state_in, p);
	if (params.sizes.z != 0) {
		vec4 packed_value = imageLoad(packed_tex, p);
		float organism = max(max(state.b, state.a), max(packed_value.g, packed_value.b));
		imageStore(present_out, p, vec4(packed_value.a, organism, packed_value.r, 1.0));
		return;
	}
	float presented = clamp(max(state.r, state.g), 0.0, 1.0);
	imageStore(present_out, p, vec4(presented, presented, presented, 1.0));
}
