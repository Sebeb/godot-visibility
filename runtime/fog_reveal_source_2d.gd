extends Node2D
class_name FogRevealSource2D

## A pushed visibility source. Optional corner peeking is delegated to a host
## object with solve_corner_peek(origin, facing), so this node knows no topology.

signal source_changed(source: FogRevealSource2D)
signal corner_peek_offset_changed(offset: Vector2)

enum Shape { OMNI, CONE }

const _MANAGER_GROUP := "visibility_manager"
const _SOURCE_GROUP := "visibility_reveal_source_2d"
const _TEXTURE_RESOLUTION := 128

@export var enabled := true:
	set(value):
		if enabled != value:
			enabled = value
			_sync_source()

@export_range(0.0, 256.0, 0.1) var reveal_range := 10.0:
	set(value):
		var next_value := maxf(0.0, value)
		if not is_equal_approx(reveal_range, next_value):
			reveal_range = next_value
			_sync_source()

@export var shape: Shape = Shape.OMNI:
	set(value):
		if shape != value:
			shape = value
			_capture_texture = null
			_sync_source()

@export_range(1.0, 179.0, 1.0) var cone_angle_degrees := 70.0:
	set(value):
		var next_value := clampf(value, 1.0, 179.0)
		if not is_equal_approx(cone_angle_degrees, next_value):
			cone_angle_degrees = next_value
			_capture_texture = null
			_sync_source()

@export var occlusion_enabled := true:
	set(value):
		if occlusion_enabled != value:
			occlusion_enabled = value
			_sync_source()

@export var origin_node: Node2D = null:
	set(value):
		origin_node = value
		_sync_origin_tracking()

var corner_peek_solver: Object = null:
	set(value):
		corner_peek_solver = value
		if corner_peek_solver == null:
			_set_corner_peek_offset(Vector2.ZERO)
		_sync_origin_tracking()

@export_range(0.0, 64.0, 0.1) var corner_peek_ease_rate := 8.0

var _capture_light: PointLight2D = null
var _capture_texture: ImageTexture = null
var _manager: FogCameraManager = null
var _world_cell_size := 1.0
var _corner_peek_offset := Vector2.ZERO
var _last_origin := Vector2.INF
var _last_rotation := INF


func _enter_tree() -> void:
	add_to_group(_SOURCE_GROUP)
	set_notify_transform(true)


func _ready() -> void:
	_ensure_capture_light()
	_sync_origin_tracking()
	_sync_source()
	_resolve_manager_once()
	if _manager != null:
		_manager.register_reveal_source(self)
	elif get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _exit_tree() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.unregister_reveal_source(self)
	_manager = null
	if _capture_light != null and is_instance_valid(_capture_light) and _capture_light.get_parent() != self:
		_capture_light.queue_free()
	_capture_light = null
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	remove_from_group(_SOURCE_GROUP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_emit_source_changed_if_moved()


func get_capture_light() -> PointLight2D:
	_ensure_capture_light()
	return _capture_light


func attach_capture_light(capture_parent: Node) -> PointLight2D:
	if _capture_light != null and is_instance_valid(_capture_light):
		if _capture_light.get_parent() == capture_parent:
			return _capture_light
		_capture_light.queue_free()
		_capture_light = null
	_ensure_capture_light(capture_parent)
	_sync_source()
	return _capture_light


func get_effective_range() -> float:
	return reveal_range * _world_cell_size


func set_world_cell_size(cell_size: float) -> void:
	var next_value := maxf(0.0001, cell_size)
	if is_equal_approx(_world_cell_size, next_value):
		return
	_world_cell_size = next_value
	_sync_source()


func get_world_cell_size() -> float:
	return _world_cell_size


func get_effective_origin() -> Vector2:
	return _base_effective_origin() + _corner_peek_offset


func get_corner_peek_offset() -> Vector2:
	return _corner_peek_offset


func get_effective_forward() -> Vector2:
	return Vector2.RIGHT.rotated(global_rotation if is_inside_tree() else rotation)


func is_effectively_enabled() -> bool:
	return enabled


func _base_effective_origin() -> Vector2:
	if origin_node != null and is_instance_valid(origin_node) and origin_node.is_inside_tree():
		return origin_node.global_position
	return global_position


func _physics_process(delta: float) -> void:
	_advance_corner_peek(delta)
	_emit_source_changed_if_moved()


func _advance_corner_peek(delta: float) -> void:
	var target := Vector2.ZERO
	if corner_peek_solver != null and corner_peek_solver.has_method("solve_corner_peek"):
		var solved: Variant = corner_peek_solver.call("solve_corner_peek", _base_effective_origin(), get_effective_forward())
		if solved is Vector2:
			target = solved as Vector2
	var ease := clampf(1.0 - exp(-corner_peek_ease_rate * maxf(0.0, delta)), 0.0, 1.0)
	_set_corner_peek_offset(_corner_peek_offset.lerp(target, ease))


func _set_corner_peek_offset(value: Vector2) -> void:
	var next_value := Vector2.ZERO if value.length_squared() < 0.00000001 else value
	if _corner_peek_offset.is_equal_approx(next_value):
		return
	_corner_peek_offset = next_value
	corner_peek_offset_changed.emit(_corner_peek_offset)
	_emit_source_changed()


func _sync_origin_tracking() -> void:
	set_physics_process(origin_node != null or corner_peek_solver != null)
	_last_origin = get_effective_origin() if is_inside_tree() else Vector2.INF
	_last_rotation = global_rotation if is_inside_tree() else INF


func _emit_source_changed_if_moved() -> void:
	var origin := get_effective_origin()
	var rotation_now := global_rotation
	if origin.is_equal_approx(_last_origin) and is_equal_approx(rotation_now, _last_rotation):
		return
	_last_origin = origin
	_last_rotation = rotation_now
	_emit_source_changed()


func _ensure_capture_light(capture_parent: Node = self) -> void:
	if _capture_light != null and is_instance_valid(_capture_light):
		return
	_capture_light = PointLight2D.new()
	_capture_light.name = "VisibilityCaptureLight"
	_capture_light.visibility_layer = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.range_item_cull_mask = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.shadow_item_cull_mask = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.energy = 1.0
	_capture_light.color = Color.WHITE
	capture_parent.add_child(_capture_light)


func _sync_source() -> void:
	if not is_node_ready():
		return
	_ensure_capture_light()
	_capture_light.enabled = is_effectively_enabled()
	_capture_light.shadow_enabled = occlusion_enabled
	_capture_light.texture = _get_capture_texture()
	_capture_light.texture_scale = maxf(0.01, get_effective_range()) / (float(_TEXTURE_RESOLUTION) * 0.5)
	_emit_source_changed()


func _get_capture_texture() -> ImageTexture:
	if _capture_texture == null:
		_capture_texture = _falloff_texture()
	return _capture_texture


func _falloff_texture() -> ImageTexture:
	var image := Image.create(_TEXTURE_RESOLUTION, _TEXTURE_RESOLUTION, false, Image.FORMAT_RGBA8)
	var center := Vector2(_TEXTURE_RESOLUTION, _TEXTURE_RESOLUTION) * 0.5
	var radius := float(_TEXTURE_RESOLUTION) * 0.5
	for y in _TEXTURE_RESOLUTION:
		for x in _TEXTURE_RESOLUTION:
			var offset := Vector2(x, y) - center
			var angle_ok := shape != Shape.CONE or absf(rad_to_deg(offset.angle())) <= cone_angle_degrees * 0.5
			var t := clampf(1.0 - offset.length() / radius, 0.0, 1.0) if angle_ok else 0.0
			var intensity := t * t * (3.0 - 2.0 * t)
			image.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)


func _resolve_manager_once() -> void:
	if get_tree() != null:
		_manager = get_tree().get_first_node_in_group(_MANAGER_GROUP) as FogCameraManager


func _on_tree_node_added(node: Node) -> void:
	if node is FogCameraManager:
		_manager = node as FogCameraManager
		get_tree().node_added.disconnect(_on_tree_node_added)
		_manager.register_reveal_source(self)


func _emit_source_changed() -> void:
	if is_inside_tree():
		source_changed.emit(self)
