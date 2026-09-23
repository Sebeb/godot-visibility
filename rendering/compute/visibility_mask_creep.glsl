#[compute]
#version 450

// PGO-101 stage ④: one ordered single-texel dilation step of the discrete
// creep claims.
//
// The continuous phase field alone cannot guarantee that a one-texel-wide
// substrate filament ever reaches full white: its renormalised neighbourhood is
// dominated by the dark non-substrate texels flanking it. Discrete creep exists
// to make complete fill a guarantee rather than an emergent property. Claims
// propagate ONLY through permitted substrate, so they can never invent
// visibility the composed mask did not grant.
//
// Propagation rule, per step:
//   * A texel is a propagation source when it is a reveal seed, or when its
//     claim has reached 1.0.
//   * A texel adjacent to a propagation source gains `creep_power`, capped at
//     1.0. It does not itself become a source until it reaches 1.0.
//
// That two-stage rule is what reproduces the proof-of-concept's coupling
// between nominal creep speed and creep power: with `creep_power = 0.05` a
// texel needs 20 steps to become a source, so the effective front velocity is
// `nominal_speed * creep_power`, not `nominal_speed`. The owner reports both
// numbers in its debug snapshot.
//
// `step_parity` alternates the neighbourhood between four-connected and
// eight-connected so the front approximates radial growth instead of marching
// out as a diamond or a square. The eight-connected step keeps the same
// no-corner-cutting rule as the phase field.
//
// Two lanes again: .b normal claim (blocker-aware), .a occlusion-bypass claim
// (blockers not applicable). A bypass claim can never write the normal lane, so
// an `occlusion_enabled = false` source cannot grant wall bypass to any other
// source.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D packed_tex;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D state_in;
layout(set = 0, binding = 2, rgba16f) uniform restrict writeonly image2D state_out;

layout(push_constant, std430) uniform Params {
	ivec4 sizes;   // sim_w, sim_h, step_parity (0 = four-connected, 1 = eight-connected), creep_enabled
	vec4 params0;  // creep_power, source_threshold, unused, unused
} params;

ivec2 g_sim_size;

ivec2 clamp_texel(ivec2 p) {
	return clamp(p, ivec2(0), g_sim_size - ivec2(1));
}

void main() {
	g_sim_size = params.sizes.xy;
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= g_sim_size.x || p.y >= g_sim_size.y || g_sim_size.x <= 0 || g_sim_size.y <= 0) {
		return;
	}

	vec4 state = imageLoad(state_in, p);
	vec4 packed_value = imageLoad(packed_tex, p);
	float substrate = packed_value.r;
	float blocked = packed_value.a;
	bool creep_enabled = params.sizes.w != 0;

	if (!creep_enabled) {
		imageStore(state_out, p, vec4(state.r, state.g, 0.0, 0.0));
		return;
	}

	float claim_normal = (substrate > 0.5 && blocked < 0.5) ? state.b : 0.0;
	float claim_bypass = substrate > 0.5 ? state.a : 0.0;

	float creep_power = params.params0.x;
	float source_threshold = params.params0.y;
	bool eight_connected = params.sizes.z != 0;

	const ivec2 CARDINALS[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	const ivec2 CORNERS[4] = ivec2[4](ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1));

	bool reached_normal = false;
	bool reached_bypass = false;

	if (substrate > 0.5) {
		for (int i = 0; i < 4; i++) {
			ivec2 n = clamp_texel(p + CARDINALS[i]);
			vec4 ns = imageLoad(state_in, n);
			vec4 np = imageLoad(packed_tex, n);
			bool source_n = ns.b >= source_threshold || (np.g > 0.5 && np.r > 0.5);
			bool source_b = ns.a >= source_threshold || (np.b > 0.5 && np.r > 0.5);
			// A normal claim may not step onto or out of a blocker.
			if (blocked < 0.5 && np.a < 0.5 && source_n) {
				reached_normal = true;
			}
			if (source_b) {
				reached_bypass = true;
			}
		}
		if (eight_connected) {
			for (int i = 0; i < 4; i++) {
				ivec2 d = CORNERS[i];
				ivec2 n = clamp_texel(p + d);
				vec4 ns = imageLoad(state_in, n);
				vec4 np = imageLoad(packed_tex, n);
				vec4 side_h = imageLoad(packed_tex, clamp_texel(p + ivec2(d.x, 0)));
				vec4 side_v = imageLoad(packed_tex, clamp_texel(p + ivec2(0, d.y)));
				bool source_n = ns.b >= source_threshold || (np.g > 0.5 && np.r > 0.5);
				bool source_b = ns.a >= source_threshold || (np.b > 0.5 && np.r > 0.5);
				// No corner cutting, and no diagonal hop across a substrate gap:
				// both flanking texels must be permitted substrate and open.
				bool open_normal = blocked < 0.5
					&& np.a < 0.5
					&& side_h.a < 0.5 && side_v.a < 0.5
					&& side_h.r > 0.5 && side_v.r > 0.5;
				bool open_bypass = side_h.r > 0.5 && side_v.r > 0.5;
				if (open_normal && source_n) {
					reached_normal = true;
				}
				if (open_bypass && source_b) {
					reached_bypass = true;
				}
			}
		}
	}

	if (reached_normal && claim_normal < 1.0) {
		claim_normal = min(1.0, claim_normal + creep_power);
	}
	if (reached_bypass && claim_bypass < 1.0) {
		claim_bypass = min(1.0, claim_bypass + creep_power);
	}

	// The claim is a floor on the field, never a reduction of it.
	float field_normal = blocked > 0.5 ? 0.0 : max(state.r, claim_normal);
	float field_bypass = max(state.g, claim_bypass);
	imageStore(state_out, p, vec4(field_normal, field_bypass, claim_normal, claim_bypass));
}
