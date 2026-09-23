shader_type canvas_item;

uniform vec2 center_uv = vec2(0.5);
uniform vec2 world_size = vec2(1.0);
uniform float radius_world = 0.0;
uniform float border_world = 2.0;
uniform float fade_steepness = 1.5;
uniform float corner_steepness = 8.0;

void fragment() {
	vec2 safe_world_size = max(world_size, vec2(0.0001));
	vec2 offset_world = (UV - center_uv) * safe_world_size;
	float distance_world = length(offset_world);
	float inner_radius = max(radius_world, 0.0001);
	float outer_axis_radius = inner_radius + max(border_world, 0.0001);
	float corner_power = max(corner_steepness, 2.0);
	vec2 direction = abs(offset_world) / max(distance_world, 0.0001);
	float direction_metric = pow(
		pow(direction.x, corner_power) + pow(direction.y, corner_power),
		1.0 / corner_power
	);
	// Rounded-corner border position if it were unconstrained by the camera bounds.
	float unclamped_border_radius = outer_axis_radius / max(direction_metric, 0.0001);

	// True camera-bounds edge distance from the center, along the current direction,
	// so the border can never sit outside the rectangle the camera actually captures.
	vec2 edge_extent = vec2(
		offset_world.x >= 0.0 ? 1.0 - center_uv.x : center_uv.x,
		offset_world.y >= 0.0 ? 1.0 - center_uv.y : center_uv.y
	) * safe_world_size;
	vec2 axis_distance = edge_extent / max(direction, vec2(0.00001));
	float bounds_radius = min(axis_distance.x, axis_distance.y);

	// The border insets inward from the camera bounds (never extends past them), and the
	// fade fills the remaining gap from that inset border out to the true camera edge.
	float border_radius = min(unclamped_border_radius, bounds_radius);
	float fade_position = clamp(
		(distance_world - border_radius) / max(bounds_radius - border_radius, 0.0001),
		0.0,
		1.0
	);
	float darkness = pow(smoothstep(0.0, 1.0, fade_position), max(fade_steepness, 0.01));
	float value = 1.0 - darkness;
	COLOR = vec4(vec3(value), 1.0);
}
