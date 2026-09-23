shader_type canvas_item;

uniform sampler2D seen_tex : source_color, filter_linear;
uniform sampler2D previous_tex : source_color, filter_linear;
uniform sampler2D cell_open_tex : source_color, filter_nearest;

uniform vec2 texel_size = vec2(0.001);
uniform vec2 world_size_cells = vec2(1.0);
uniform float diffusion_rate : hint_range(0.0, 1.0) = 0.12;
uniform float propagation_decay : hint_range(0.0, 1.0) = 0.97;
uniform float unseen_glow_cap : hint_range(0.0, 1.0) = 1.0;
uniform float seed_threshold : hint_range(0.0, 1.0) = 0.6;

float sample_prev(vec2 uv) {
	return clamp(texture(previous_tex, uv).r, 0.0, 1.0);
}

vec4 sample_cell_open(vec2 cell_coord) {
	vec2 safe_cells = max(world_size_cells, vec2(1.0));
	vec2 clamped_cell = clamp(cell_coord, vec2(0.0), safe_cells - vec2(1.0));
	vec2 cell_uv = (clamped_cell + vec2(0.5)) / safe_cells;
	return texture(cell_open_tex, cell_uv);
}

bool can_step(vec2 uv, vec2 delta) {
	vec2 uv_next = uv + delta;
	if (uv_next.x < 0.0 || uv_next.y < 0.0 || uv_next.x > 1.0 || uv_next.y > 1.0) {
		return false;
	}

	vec2 safe_cells = max(world_size_cells, vec2(1.0));
	vec2 uv_safe = min(uv, vec2(0.999999));
	vec2 uv_next_safe = min(uv_next, vec2(0.999999));
	vec2 cell = floor(uv_safe * safe_cells);
	vec2 next_cell = floor(uv_next_safe * safe_cells);
	vec4 open_here = sample_cell_open(cell);

	if (next_cell.x > cell.x) {
		if (open_here.r < 0.5) {
			return false;
		}
		vec4 open_next = sample_cell_open(next_cell);
		if (open_next.g < 0.5) {
			return false;
		}
	}
	if (next_cell.x < cell.x) {
		if (open_here.g < 0.5) {
			return false;
		}
		vec4 open_next = sample_cell_open(next_cell);
		if (open_next.r < 0.5) {
			return false;
		}
	}
	if (next_cell.y > cell.y) {
		if (open_here.b < 0.5) {
			return false;
		}
		vec4 open_next = sample_cell_open(next_cell);
		if (open_next.a < 0.5) {
			return false;
		}
	}
	if (next_cell.y < cell.y) {
		if (open_here.a < 0.5) {
			return false;
		}
		vec4 open_next = sample_cell_open(next_cell);
		if (open_next.b < 0.5) {
			return false;
		}
	}

	return true;
}

void fragment() {
	vec2 uv = UV;
	float seen = clamp(texture(seen_tex, uv).r, 0.0, 1.0);
	float seen_seed = smoothstep(clamp(seed_threshold, 0.0, 0.99), 1.0, seen);
	float prev = sample_prev(uv);

	float candidate = max(prev, seen_seed);
	float decay = clamp(propagation_decay, 0.0, 1.0);

	vec2 dx = vec2(texel_size.x, 0.0);
	if (can_step(uv, dx)) {
		candidate = max(candidate, sample_prev(uv + dx) * decay);
	}
	if (can_step(uv, -dx)) {
		candidate = max(candidate, sample_prev(uv - dx) * decay);
	}

	vec2 dy = vec2(0.0, texel_size.y);
	if (can_step(uv, dy)) {
		candidate = max(candidate, sample_prev(uv + dy) * decay);
	}
	if (can_step(uv, -dy)) {
		candidate = max(candidate, sample_prev(uv - dy) * decay);
	}

	float cap = seen_seed + (1.0 - seen_seed) * clamp(unseen_glow_cap, 0.0, 1.0);
	float target = min(candidate, cap);
	float grown = prev + max(0.0, target - prev) * clamp(diffusion_rate, 0.0, 1.0);
	float glow = max(prev, grown);
	float out_visibility = max(seen, glow);

	COLOR = vec4(out_visibility, out_visibility, out_visibility, out_visibility);
}
