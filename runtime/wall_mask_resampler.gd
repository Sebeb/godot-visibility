extends Node
class_name WallMaskResampler

const RESAMPLE_SHADER := preload("res://addons/visibility/rendering/wall_mask_resample.gdshader")

var _viewport: SubViewport = null
var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _signature := ""
var _resample_count := 0


func resample(walls_texture: Texture2D, size: Vector2i, yaw: float, walls_revision: int) -> Texture2D:
	if walls_texture == null or size.x <= 0 or size.y <= 0:
		return null
	_ensure_target(size)
	var signature := "%s|%s|%.8f|%s" % [walls_texture.get_rid(), size, yaw, walls_revision]
	if signature == _signature:
		return _viewport.get_texture()
	_signature = signature
	_material.set_shader_parameter("walls_tex", walls_texture)
	_material.set_shader_parameter("world_rotation_radians", yaw)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_resample_count += 1
	return _viewport.get_texture()


func debug_get_snapshot() -> Dictionary:
	return {
		"signature": _signature,
		"resample_count": _resample_count,
		"update_mode": _viewport.render_target_update_mode if _viewport != null else SubViewport.UPDATE_DISABLED,
	}


static func remap_uv(mask_uv: Vector2, yaw: float) -> Vector2:
	return (mask_uv - Vector2(0.5, 0.5)).rotated(-yaw) + Vector2(0.5, 0.5)


func _ensure_target(size: Vector2i) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		if _viewport.size != size:
			_viewport.size = size
			_rect.size = Vector2(size)
			_signature = ""
		return
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rect = ColorRect.new()
	_rect.size = Vector2(size)
	_material = ShaderMaterial.new()
	_material.shader = RESAMPLE_SHADER
	_rect.material = _material
	_viewport.add_child(_rect)
	add_child(_viewport)
