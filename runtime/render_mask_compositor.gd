extends Node
class_name RenderMaskCompositor

const COMPOSITE_SHADER := preload("res://rendering/render_mask_composite.gdshader")
const MODE_OFF := 0
const MODE_ADDITIVE := 1
const MODE_MULTIPLICATIVE := 2

var _targets: Dictionary = {}
var _compose_request_count := 0
var _rebuild_count := 0


func compose(
	target: StringName,
	size: Vector2i,
	contributions: Array[Dictionary],
	fallback: Texture2D,
	source: Texture2D = null,
	source_revision: int = 0,
	uv_offset: Vector2 = Vector2.ZERO,
	uv_scale: Vector2 = Vector2.ONE,
	source_is_premultiplied: bool = false
) -> Texture2D:
	_compose_request_count += 1
	if size.x <= 0 or size.y <= 0:
		return source if source != null else fallback
	var state := _ensure_target(target, size)
	var signature := _signature(size, contributions, source, source_revision, uv_offset, uv_scale, source_is_premultiplied)
	if state.get("signature", "") == signature:
		return state["viewport"].get_texture()
	var material: ShaderMaterial = state["material"]
	material.set_shader_parameter("source_tex", source if source != null else fallback)
	material.set_shader_parameter("apply_to_source", source != null)
	material.set_shader_parameter("uv_offset", uv_offset)
	material.set_shader_parameter("uv_scale", uv_scale)
	material.set_shader_parameter("source_is_premultiplied", source_is_premultiplied)
	for index in 4:
		var contribution: Dictionary = contributions[index] if index < contributions.size() else {}
		material.set_shader_parameter("mask_%d" % index, contribution.get("texture", fallback))
		material.set_shader_parameter("mode_%d" % index, _mode_value(contribution.get("mode", "off")))
	state["signature"] = signature
	state["revision"] = int(state.get("revision", 0)) + 1
	state["viewport"].render_target_update_mode = SubViewport.UPDATE_ONCE
	_targets[target] = state
	_rebuild_count += 1
	return state["viewport"].get_texture()


func clear_target(target: StringName) -> void:
	var state: Dictionary = _targets.get(target, {})
	var viewport := state.get("viewport") as SubViewport
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
	_targets.erase(target)


func clear() -> void:
	for target_variant in _targets.keys():
		clear_target(StringName(target_variant))


func debug_get_snapshot(target: StringName = &"") -> Dictionary:
	var state: Dictionary = _targets.get(target, {}) if target != &"" else {}
	return {
		"target_count": _targets.size(),
		"compose_request_count": _compose_request_count,
		"rebuild_count": _rebuild_count,
		"target_signature": String(state.get("signature", "")),
		"revision": int(state.get("revision", 0)),
	}


func _ensure_target(target: StringName, size: Vector2i) -> Dictionary:
	var state: Dictionary = _targets.get(target, {})
	if not state.is_empty():
		var existing_viewport: SubViewport = state["viewport"]
		if existing_viewport.size == size:
			return state
		# Resize in place; recreating the viewport would strand the previous one as a child.
		existing_viewport.size = size
		(state["rect"] as ColorRect).size = Vector2(size)
		state["signature"] = ""
		_targets[target] = state
		return state
	var viewport := SubViewport.new()
	# Masked colour targets must retain their source coverage between GPU passes.
	viewport.transparent_bg = true
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var material := ShaderMaterial.new()
	material.shader = COMPOSITE_SHADER
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	return {"viewport": viewport, "material": material, "rect": rect, "signature": "", "revision": 0}


func _mode_value(mode: Variant) -> int:
	match String(mode).strip_edges().to_lower():
		"additive": return MODE_ADDITIVE
		"multiplicative": return MODE_MULTIPLICATIVE
		_: return MODE_OFF


func _signature(
	size: Vector2i,
	contributions: Array[Dictionary],
	source: Texture2D,
	source_revision: int,
	uv_offset: Vector2 = Vector2.ZERO,
	uv_scale: Vector2 = Vector2.ONE,
	source_is_premultiplied: bool = false
) -> String:
	var parts := [
		str(size.x),
		str(size.y),
		str(source.get_rid()) if source != null else "no_source",
		str(source_revision),
		str(uv_offset),
		str(uv_scale),
		str(source_is_premultiplied),
	]
	for contribution in contributions:
		var texture := contribution.get("texture") as Texture2D
		parts.append("%s:%s:%s" % [
			str(texture.get_rid()) if texture != null else "none",
			str(contribution.get("mode", "off")),
			str(contribution.get("revision", 0)),
		])
	return "|".join(parts)
