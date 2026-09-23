extends RefCounted
class_name RenderMaskComposition

const MODE_OFF := &"off"
const MODE_ADDITIVE := &"additive"
const MODE_MULTIPLICATIVE := &"multiplicative"


static func compose_scalar(target: float, contributions: Array[Dictionary]) -> float:
	var multiplicative := 1.0
	var additive := 0.0
	for contribution in contributions:
		var mode := StringName(str(contribution.get("mode", MODE_OFF)).strip_edges().to_lower())
		var value := clampf(float(contribution.get("value", 0.0)), 0.0, 1.0)
		if mode == MODE_MULTIPLICATIVE:
			multiplicative *= value
		elif mode == MODE_ADDITIVE:
			additive += value
	return clampf(target * multiplicative + additive, 0.0, 1.0)


static func mode_is_active(mode: Variant) -> bool:
	var normalized := StringName(str(mode).strip_edges().to_lower())
	return normalized == MODE_ADDITIVE or normalized == MODE_MULTIPLICATIVE
