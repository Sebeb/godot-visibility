shader_type canvas_item;

// Merges live visibility into explored memory and maintains the PGO-157 recency
// channel that orders forgetting oldest-first.
//
// Channel contract: .r/.b/.a carry the explored mask every downstream consumer
// samples. .g carries recency, where 1.0 is "seen this pass" and lower values are
// progressively older. Each pass compresses the existing gradient by
// recency_rescale (i / (i + 1)), so the newest memory is always 1.0 and older
// memory spreads evenly toward 0.0 without ever colliding.

uniform sampler2D current_tex : source_color;
uniform sampler2D previous_tex : source_color;
// Compresses the retained recency gradient by i / (i + 1) for step count i.
uniform float recency_rescale = 1.0;
// Sets the live-visibility level at or above which a texel counts as seen now.
uniform float recency_write_threshold = 0.004;
// Erases memory whose recency has fallen to this advancing frontier. 0 forgets nothing.
uniform float forget_threshold = 0.0;
// Softens the frontier so memory dissolves rather than popping out.
uniform float forget_soft_edge = 0.01;

void fragment() {
	vec2 uv = UV;
	vec4 current_sample = texture(current_tex, uv);
	vec4 previous_sample = texture(previous_tex, uv);
	float current_mask = current_sample.r;
	float previous_mask = previous_sample.r;
	float previous_recency = clamp(previous_sample.g * recency_rescale, 0.0, 1.0);
	bool seen_now = current_mask > recency_write_threshold;
	float recency = seen_now ? 1.0 : previous_recency;

	// Only memory older than the frontier is erased, so forgetting always runs
	// from the oldest explored areas toward the newest regardless of geometry.
	float retention = 1.0;
	if (forget_threshold > 0.0 && !seen_now) {
		float edge = max(forget_soft_edge, 0.0001);
		retention = smoothstep(forget_threshold - edge, forget_threshold + edge, recency);
	}

	float mask = max(current_mask, previous_mask * retention);
	// Erased memory must lose its age too, or a rediscovered texel would inherit
	// a stale frontier position and be forgotten again immediately.
	recency = seen_now ? 1.0 : recency * retention;
	float alpha = max(current_sample.a, previous_sample.a * retention);
	COLOR = vec4(mask, recency, mask, alpha);
}
