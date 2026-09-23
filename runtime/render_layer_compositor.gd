extends Node
class_name RenderLayerCompositor

## Demand-driven RGBA compositor for one render-layer output. Members are
## ordered back-to-front direct-capture bands or promoted cache textures.

const COMPOSITE_SHADER := preload("res://addons/visibility/rendering/render_layer_color_composite.gdshader")
const MASK_VISUALIZATION_SHADER := preload("res://addons/visibility/rendering/render_layer_mask_visualization.gdshader")

signal refreshed(target: StringName, revision: int)

var _targets: Dictionary = {}
var _compose_request_count := 0
var _rebuild_count := 0


func compose(
	target: StringName,
	size: Vector2i,
	members: Array[Dictionary],
	fallback: Texture2D = null
) -> Texture2D:
	_compose_request_count += 1
	if size.x <= 0 or size.y <= 0:
		return fallback
	var state := _ensure_target(target, size)
	var signature := _signature(size, members)
	if state.get("signature", "") == signature:
		return state["viewport"].get_texture()
	_apply_members(state, members)
	state["signature"] = signature
	state["revision"] = int(state.get("revision", 0)) + 1
	state["viewport"].render_target_update_mode = SubViewport.UPDATE_ONCE
	_targets[target] = state
	_schedule_refresh_notification(target)
	_rebuild_count += 1
	return state["viewport"].get_texture()


func clear_target(target: StringName) -> void:
	var state: Dictionary = _targets.get(target, {})
	_cancel_refresh_notification(target, state)
	var viewport := state.get("viewport") as SubViewport
	if viewport != null and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
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
		"rendered_revision": int(state.get("rendered_revision", 0)),
		"refresh_pending": bool(state.get("refresh_pending", false)),
		"member_count": (state.get("rects", []) as Array).size(),
		"member_modes": (state.get("member_modes", []) as Array).duplicate(),
	}


func _ensure_target(target: StringName, size: Vector2i) -> Dictionary:
	var state: Dictionary = _targets.get(target, {})
	if not state.is_empty() and state["viewport"].size == size:
		return state
	if not state.is_empty():
		clear_target(target)
	var viewport := SubViewport.new()
	viewport.name = "%sColorCompositeViewport" % target
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.size = size
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	return {
		"viewport": viewport,
		"rects": [],
		"signature": "",
		"revision": 0,
		"rendered_revision": 0,
		"refresh_pending": false,
		"member_modes": [],
	}


func _schedule_refresh_notification(target: StringName) -> void:
	var state: Dictionary = _targets.get(target, {})
	if state.is_empty() or bool(state.get("refresh_pending", false)):
		return
	var notification_already_scheduled := _has_pending_refresh_notification()
	state["refresh_pending"] = true
	_targets[target] = state
	if notification_already_scheduled:
		return
	if DisplayServer.get_name() == "headless":
		call_deferred("_on_frame_post_draw")
		return
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)


func _cancel_refresh_notification(target: StringName, state: Dictionary) -> void:
	if state.is_empty() or not bool(state.get("refresh_pending", false)):
		return
	state["refresh_pending"] = false
	_targets[target] = state
	if not _has_pending_refresh_notification() and RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _has_pending_refresh_notification() -> bool:
	for state_variant in _targets.values():
		if bool((state_variant as Dictionary).get("refresh_pending", false)):
			return true
	return false


func _on_frame_post_draw() -> void:
	var completed_targets: Array[StringName] = []
	for target_variant in _targets.keys():
		var target := StringName(target_variant)
		var state: Dictionary = _targets.get(target, {})
		if not bool(state.get("refresh_pending", false)):
			continue
		state["refresh_pending"] = false
		state["rendered_revision"] = int(state.get("revision", 0))
		_targets[target] = state
		completed_targets.append(target)
	for target in completed_targets:
		var state: Dictionary = _targets.get(target, {})
		# Downstream viewport work must begin outside frame_post_draw or Godot may
		# discard a newly assigned UPDATE_ONCE while finalizing this frame.
		call_deferred("_emit_completed_refresh", target, int(state.get("rendered_revision", 0)))


func _emit_completed_refresh(target: StringName, revision: int) -> void:
	var state: Dictionary = _targets.get(target, {})
	if state.is_empty() or revision > int(state.get("rendered_revision", 0)):
		return
	refreshed.emit(target, revision)


func _apply_members(state: Dictionary, members: Array[Dictionary]) -> void:
	var rects: Array = state["rects"]
	var viewport := state["viewport"] as SubViewport
	var member_modes: Array[String] = []
	for index in members.size():
		var rect: ColorRect = rects[index] if index < rects.size() else _create_member_rect(viewport, index)
		if index >= rects.size():
			rects.append(rect)
		var texture := members[index].get("texture") as Texture2D
		var member_mode := String(members[index].get("mode", "direct"))
		member_modes.append(member_mode)
		rect.visible = texture != null
		if texture != null:
			var material := rect.material as ShaderMaterial
			material.shader = MASK_VISUALIZATION_SHADER if member_mode == "external" else COMPOSITE_SHADER
			material.set_shader_parameter("source_tex", texture)
			if member_mode == "external":
				material.set_shader_parameter("source_tint", members[index].get("tint", Color.WHITE))
			else:
				material.set_shader_parameter("source_is_premultiplied", bool(members[index].get("premultiplied", false)))
	for index in range(members.size(), rects.size()):
		rects[index].visible = false
	state["rects"] = rects
	state["member_modes"] = member_modes


func _create_member_rect(viewport: SubViewport, index: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "OrderedColorMember%d" % index
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = COMPOSITE_SHADER
	rect.material = material
	viewport.add_child(rect)
	return rect


func _signature(size: Vector2i, members: Array[Dictionary]) -> String:
	var parts := [str(size.x), str(size.y)]
	for member in members:
		var texture := member.get("texture") as Texture2D
		parts.append("%s:%s:%s:%s:%s" % [
			str(member.get("mode", "direct")),
			str(texture.get_rid()) if texture != null else "none",
			str(member.get("revision", 0)),
			str(bool(member.get("premultiplied", false))),
			str(member.get("tint", Color.WHITE)),
		])
	return "|".join(parts)
