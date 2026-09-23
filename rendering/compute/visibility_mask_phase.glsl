#[compute]
#version 450

// PGO-101 stage ③: one fixed simulation tick of the continuous phase field.
//
// The phase field owns the organic boundary, curvature smoothing, the soft
// halo, and retraction. Per tick, per lane:
//
//     blurred = renormalized_open_neighbourhood(field)
//     biased  = (blurred - 0.5) * sharpness + 0.5
//     biased += growth_bias   inside permitted substrate, IF blurred > 0
//     biased -= shrink_bias   outside permitted substrate
//     field   = clamp(biased, 0, 1)
//     field   = min(field, halo_ceiling)   outside permitted substrate
//     field   = max(field, claim)          discrete creep floor
//
// HALO BOUND VERSUS RETRACTION
// `halo_ceiling = max(halo_support, previous_field - shrink_bias)`. The raw
// support is a hard zero past the configured radius, so applying it directly
// would delete a retracting field the instant a large piece of substrate went
// away -- the boundary would not retract inward, it would simply vanish. Rate
// limiting the descent keeps both guarantees: the field can never RISE above
// the support, and it is pulled down by at least `shrink_bias` every tick, so
// it reaches the support in at most `1 / shrink_bias` ticks and lands on an
// exact zero rather than on a dim value that merely looks black. That is a
// computed bound, not floating-point decay.
//
// GROWTH ADVANCES A FRONT, IT DOES NOT CREATE ONE
// The `blurred > 0` gate is load bearing, not a micro-optimisation. Without it
// the operator self-nucleates: from an all-zero field, `(0 - 0.5) * 1.05 + 0.5`
// is -0.025, and any growth bias above `0.5 * (sharpness - 1)` makes that
// positive, so every permitted texel lights up on its own and the entire
// organic character -- seeds, creep, islands -- becomes meaningless. Gating on
// an exactly-zero neighbourhood is exact in floating point: a texel two or more
// away from anything non-zero has a bit-exact zero sum and cannot be biased.
// The gate also bounds the front at one texel per tick by construction, since
// only a texel adjacent to existing field is eligible to grow at all.
//
// Growth and shrink are the same spatial operator with opposite directional
// bias, which is what makes retraction move the boundary inward from the
// outside edge rather than fading the interior uniformly in place: a texel deep
// inside a removed region still averages ~1 from its neighbours and only starts
// falling once its own neighbourhood has darkened.
//
// Two independent lanes are simulated:
//   .r normal field  — blocker-aware. Blocked texels are forced to zero and
//                      contribute no weight to any neighbourhood.
//   .g bypass field  — belongs to `occlusion_enabled = false` reveal sources.
//                      It ignores blockers entirely. Keeping it in its own
//                      channel is what stops an occlusion-disabled source from
//                      granting wall bypass to unrelated normal sources.
//
// .b / .a carry the normal and bypass discrete claims. This pass only
// invalidates them (substrate removal, blockers, creep disabled) and pins
// seeds; growth of the claims themselves belongs to the creep pass.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D packed_tex;
layout(set = 0, binding = 1, r32f) uniform restrict readonly image2D halo_tex;
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D state_in;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D state_out;

layout(push_constant, std430) uniform Params {
	ivec4 sizes;    // sim_w, sim_h, creep_enabled, unused
	vec4 weights;   // center, cardinal, corner, sharpness
	vec4 biases;    // growth_bias, shrink_bias, unused, unused
} params;

ivec2 g_sim_size;

ivec2 clamp_texel(ivec2 p) {
	return clamp(p, ivec2(0), g_sim_size - ivec2(1));
}

float blocker_at(ivec2 p) {
	return imageLoad(packed_tex, clamp_texel(p)).a;
}

float field_at(ivec2 p, int lane) {
	vec4 s = imageLoad(state_in, clamp_texel(p));
	return lane == 0 ? s.r : s.g;
}

void main() {
	g_sim_size = params.sizes.xy;
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= g_sim_size.x || p.y >= g_sim_size.y || g_sim_size.x <= 0 || g_sim_size.y <= 0) {
		return;
	}

	vec4 packed_value = imageLoad(packed_tex, p);
	float substrate = packed_value.r;
	float seed_normal = packed_value.g;
	float seed_bypass = packed_value.b;
	float blocked = packed_value.a;
	float halo_support = imageLoad(halo_tex, p).r;
	vec4 previous = imageLoad(state_in, p);
	bool creep_enabled = params.sizes.z != 0;

	// Claim validity. A claim never survives absent substrate, and a normal
	// claim never survives an applicable blocker. Disabling creep clears every
	// claim in the same tick so the presented result is exactly the continuous
	// phase field alone, with no residual influence to decay away.
	float claim_normal = (creep_enabled && substrate > 0.5 && blocked < 0.5) ? previous.b : 0.0;
	float claim_bypass = (creep_enabled && substrate > 0.5) ? previous.a : 0.0;
	if (creep_enabled && substrate > 0.5) {
		if (seed_normal > 0.5 && blocked < 0.5) {
			claim_normal = 1.0;
		}
		if (seed_bypass > 0.5) {
			claim_bypass = 1.0;
		}
	}

	float center_w = params.weights.x;
	float card_w = params.weights.y;
	float corner_w = params.weights.z;
	float sharpness = params.weights.w;
	float growth_bias = params.biases.x;
	float shrink_bias = params.biases.y;

	const ivec2 CARDINALS[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	const ivec2 CORNERS[4] = ivec2[4](ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1));

	// --- normal lane -------------------------------------------------------
	float field_normal = 0.0;
	if (blocked < 0.5) {
		float sum = field_at(p, 0) * center_w;
		float weight = center_w;
		for (int i = 0; i < 4; i++) {
			ivec2 n = p + CARDINALS[i];
			if (blocker_at(n) < 0.5) {
				sum += field_at(n, 0) * card_w;
				weight += card_w;
			}
		}
		for (int i = 0; i < 4; i++) {
			ivec2 d = CORNERS[i];
			ivec2 n = p + d;
			// No corner cutting: a diagonal tap only participates when the
			// corner texel itself and BOTH of its adjacent cardinal texels are
			// open. That closes the diagonal pinch where two blockers meet at a
			// point and would otherwise leak a texel of field through the join.
			bool open = blocker_at(n) < 0.5
				&& blocker_at(p + ivec2(d.x, 0)) < 0.5
				&& blocker_at(p + ivec2(0, d.y)) < 0.5;
			if (open) {
				sum += field_at(n, 0) * corner_w;
				weight += corner_w;
			}
		}
		float blurred = weight > 0.0 ? sum / weight : field_at(p, 0);
		float biased = (blurred - 0.5) * sharpness + 0.5;
		biased += (substrate > 0.5) ? (blurred > 0.0 ? growth_bias : 0.0) : -shrink_bias;
		field_normal = clamp(biased, 0.0, 1.0);
		if (substrate <= 0.5) {
			field_normal = min(field_normal, max(halo_support, previous.r - shrink_bias));
		}
		field_normal = max(field_normal, claim_normal);
		if (substrate > 0.5 && seed_normal > 0.5) {
			field_normal = 1.0;
		}
	}

	// --- occlusion-bypass lane --------------------------------------------
	// Same operator, no blocker gating. Blocked texels are NOT forced to zero
	// here: for a source whose occlusion is disabled the blocker is simply not
	// applicable, and its substrate legitimately extends through the wall.
	float sum_b = field_at(p, 1) * center_w;
	float weight_b = center_w;
	for (int i = 0; i < 4; i++) {
		sum_b += field_at(p + CARDINALS[i], 1) * card_w;
		weight_b += card_w;
	}
	for (int i = 0; i < 4; i++) {
		sum_b += field_at(p + CORNERS[i], 1) * corner_w;
		weight_b += corner_w;
	}
	float blurred_b = weight_b > 0.0 ? sum_b / weight_b : field_at(p, 1);
	float biased_b = (blurred_b - 0.5) * sharpness + 0.5;
	biased_b += (substrate > 0.5) ? (blurred_b > 0.0 ? growth_bias : 0.0) : -shrink_bias;
	float field_bypass = clamp(biased_b, 0.0, 1.0);
	if (substrate <= 0.5) {
		field_bypass = min(field_bypass, max(halo_support, previous.g - shrink_bias));
	}
	field_bypass = max(field_bypass, claim_bypass);
	if (substrate > 0.5 && seed_bypass > 0.5) {
		field_bypass = 1.0;
	}

	imageStore(state_out, p, vec4(field_normal, field_bypass, claim_normal, claim_bypass));
}
