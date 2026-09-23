#[compute]
#version 450

// PGO-101 stage ①: resamples the two full-resolution fog capture surfaces into
// the single packed simulation-resolution input the organic visibility mask
// simulation reads every tick.
//
// Inputs are two textures that share one coordinate space (both are rendered at
// the current-visibility capture viewport's size, over the same wall-inclusive
// world rect):
//   substrate_tex — the composed `game_world` render mask (red channel).
//   aux_tex       — the packed auxiliary capture: r = normal reveal seed,
//                   g = occlusion-bypass reveal seed, b = fog blocker geometry.
//
// Downsampling is a conservative MAX over every source texel a simulation texel
// covers, never a box average. A one-source-texel-wide blocker filament must
// still close its simulation texel, and a one-texel substrate filament must
// still open one, or the simulation would leak through gaps the capture never
// had. The taps are strided when the ratio exceeds MAX_TAPS so an extreme
// pixels-per-cell mismatch cannot turn this into an unbounded loop.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D substrate_tex;
layout(set = 0, binding = 1) uniform sampler2D aux_tex;
layout(set = 0, binding = 2, rgba8) uniform restrict writeonly image2D packed_out;

layout(push_constant, std430) uniform Params {
	ivec4 sizes;      // sim_w, sim_h, src_w, src_h
	vec4 thresholds;  // substrate, seed, blocker, unused
} params;

const int MAX_TAPS = 8;

void main() {
	ivec2 sim_size = params.sizes.xy;
	ivec2 src_size = params.sizes.zw;
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= sim_size.x || p.y >= sim_size.y || sim_size.x <= 0 || sim_size.y <= 0) {
		return;
	}

	vec2 scale = vec2(src_size) / vec2(sim_size);
	ivec2 first = ivec2(floor(vec2(p) * scale));
	ivec2 last = ivec2(ceil(vec2(p + 1) * scale)) - 1;
	first = clamp(first, ivec2(0), src_size - 1);
	last = clamp(max(last, first), ivec2(0), src_size - 1);

	ivec2 span = last - first + ivec2(1);
	ivec2 stride = max(ivec2(1), (span + ivec2(MAX_TAPS - 1)) / ivec2(MAX_TAPS));

	float substrate = 0.0;
	float seed_normal = 0.0;
	float seed_bypass = 0.0;
	float blocker = 0.0;
	for (int y = first.y; y <= last.y; y += stride.y) {
		for (int x = first.x; x <= last.x; x += stride.x) {
			ivec2 s = ivec2(x, y);
			substrate = max(substrate, texelFetch(substrate_tex, s, 0).r);
			vec4 aux = texelFetch(aux_tex, s, 0);
			seed_normal = max(seed_normal, aux.r);
			seed_bypass = max(seed_bypass, aux.g);
			blocker = max(blocker, aux.b);
		}
	}

	// The configurable substrate threshold is the sole grayscale-to-permitted
	// conversion. Seeds and blockers use a fixed low threshold because both are
	// painted as hard, unshaded, binary geometry: anything that survived the
	// conservative max above genuinely covered part of this texel.
	float permitted = substrate >= params.thresholds.x ? 1.0 : 0.0;
	float seed_n = seed_normal >= params.thresholds.y ? 1.0 : 0.0;
	float seed_b = seed_bypass >= params.thresholds.y ? 1.0 : 0.0;
	float blocked = blocker >= params.thresholds.z ? 1.0 : 0.0;

	imageStore(packed_out, p, vec4(permitted, seed_n, seed_b, blocked));
}
