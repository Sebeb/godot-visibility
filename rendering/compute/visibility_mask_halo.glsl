#[compute]
#version 450

// PGO-101 stage ②: builds the strict halo support bound.
//
// The continuous phase field is allowed to bleed outside the permitted
// substrate to form a soft organic halo, but that support must be *strictly*
// bounded by `halo_radius_cells` rather than left to floating-point decay to
// eventually look black. This pass computes, for every simulation texel,
//
//     support(p) = max over substrate texels q of (1 - L1(p, q) / radius)
//
// clamped to [0, 1]. That is exactly separable: a horizontal max-with-linear-
// penalty followed by a vertical one over the same penalty reproduces the L1
// (diamond) ramp, because the penalty is additive in |dx| and |dy|. Two passes
// of (2 * radius + 1) taps replace an O(radius^2) neighbourhood search.
//
// The result is 1.0 everywhere inside the substrate, ramps linearly to 0 at an
// L1 distance of `radius`, and is exactly 0 beyond it. The phase field is
// clamped by this value outside the substrate, so no halo pixel can ever be
// non-zero past the configured radius, at any frame rate or tick count.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D packed_tex;
// R32_SFLOAT rather than R8: single-channel 8-bit storage images are an
// optional Vulkan format, R32_SFLOAT is mandatory.
layout(set = 0, binding = 1, r32f) uniform restrict readonly image2D previous_tex;
layout(set = 0, binding = 2, r32f) uniform restrict writeonly image2D support_out;

layout(push_constant, std430) uniform Params {
	ivec4 sizes;  // sim_w, sim_h, radius_texels, axis (0 = horizontal seed pass, 1 = vertical pass)
} params;

const int MAX_RADIUS = 64;

void main() {
	ivec2 sim_size = params.sizes.xy;
	int radius = params.sizes.z;
	int axis = params.sizes.w;
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= sim_size.x || p.y >= sim_size.y || sim_size.x <= 0 || sim_size.y <= 0) {
		return;
	}
	if (radius <= 0) {
		// A zero halo radius means "no support outside the substrate at all".
		float substrate = axis == 0 ? imageLoad(packed_tex, p).r : imageLoad(previous_tex, p).r;
		imageStore(support_out, p, vec4(substrate, 0.0, 0.0, 1.0));
		return;
	}

	float penalty_step = 1.0 / float(radius);
	float best = 0.0;
	int limit = min(radius, MAX_RADIUS);
	for (int offset = -limit; offset <= limit; offset++) {
		ivec2 s = axis == 0 ? ivec2(p.x + offset, p.y) : ivec2(p.x, p.y + offset);
		s = clamp(s, ivec2(0), sim_size - ivec2(1));
		float value = axis == 0 ? imageLoad(packed_tex, s).r : imageLoad(previous_tex, s).r;
		best = max(best, value - float(abs(offset)) * penalty_step);
	}
	imageStore(support_out, p, vec4(clamp(best, 0.0, 1.0), 0.0, 0.0, 1.0));
}
