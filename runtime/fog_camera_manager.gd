extends Node
class_name FogCameraManager

## Engine-facing owner of the visibility surfaces. A host supplies only a
## rectangular cell extent, three world scalars, reveal sources, and blockers.

signal fog_history_surface_updated(dirty_uv_rects: Array[Rect2])
signal world_configured(grid_size: Vector2i, settings: VisibilityWorldSettings)

const FOG_CAPTURE_2D_LIGHT_MASK := (1 << 19) | 1
const FOG_MANAGER_GROUP := "visibility_manager"
const FOG_BLOCKER_2D_GROUP := "visibility_blocker_2d"
const DYNAMIC_SEGMENT_PROVIDER_GROUP := "visibility_segment_provider"
const HISTORY_SHADER := preload("res://addons/visibility/rendering/fog_history_merge.gdshader")
const FOG_MEMORY_DECAY_CONTROLLER_SCENE_PATH := "res://addons/visibility/runtime/fog_memory_decay_controller.tscn"

@export_range(1, 128, 1) var capture_resolution_per_grid_square := 24
@export_range(1, 64, 1) var history_dirty_tile_resolution := 8

var _grid_size := Vector2i.ZERO
var _world_settings: VisibilityWorldSettings = null
var _capture_rect := Rect2(Vector2.ZERO, Vector2.ONE)
var _current_viewport: SubViewport = null
var _current_root: Node2D = null
var _current_receiver: ColorRect = null
var _occluder_root: Node2D = null
var _history_viewport: SubViewport = null
var _history_rect: ColorRect = null
var _history_material: ShaderMaterial = null
var _black_texture: Texture2D = null
var _reveal_sources: Dictionary = {}
var _blockers: Dictionary = {}
var _dynamic_occluders: Dictionary = {}
var _dynamic_provider_revisions: Dictionary = {}
var _render_mask_surfaces: Dictionary = {}
var _render_mask_texture_revisions: Dictionary = {}
var _memory_decay_controller: Node = null
var _capture_dirty := true
var _history_reset_pending := true
var _revision := 0


func _ready() -> void:
	add_to_group(FOG_MANAGER_GROUP)
	_ensure_capture_graph()
	_register_existing_components()
	if get_tree() != null:
		if not get_tree().node_added.is_connected(_on_tree_node_added):
			get_tree().node_added.connect(_on_tree_node_added)
		if not get_tree().node_removed.is_connected(_on_tree_node_removed):
			get_tree().node_removed.connect(_on_tree_node_removed)
	set_process(true)


func _exit_tree() -> void:
	set_process(false)
	if get_tree() != null:
		if get_tree().node_added.is_connected(_on_tree_node_added):
			get_tree().node_added.disconnect(_on_tree_node_added)
		if get_tree().node_removed.is_connected(_on_tree_node_removed):
			get_tree().node_removed.disconnect(_on_tree_node_removed)
	for source in _live_values(_reveal_sources):
		_release_source(source)
	for blocker in _live_values(_blockers):
		_release_blocker(blocker)
	_clear_dynamic_occluders()
	remove_from_group(FOG_MANAGER_GROUP)


## Replaces all host-specific world injection. Reconfiguration is supported so
## editors and level loaders can reuse one manager between worlds.
func configure_world(grid_size: Vector2i, settings: VisibilityWorldSettings) -> void:
	_grid_size = Vector2i(maxi(0, grid_size.x), maxi(0, grid_size.y))
	_world_settings = settings.normalized() if settings != null else null
	_capture_rect = _calculate_capture_rect()
	_apply_capture_layout()
	_sync_all_source_cell_sizes()
	_capture_dirty = true
	_history_reset_pending = true
	world_configured.emit(_grid_size, _world_settings)


func get_grid_size() -> Vector2i:
	return _grid_size


func get_world_settings() -> VisibilityWorldSettings:
	return _world_settings


func get_visibility_rect() -> Rect2:
	return _capture_rect


func is_world_configured() -> bool:
	return _world_settings != null and _grid_size.x > 0 and _grid_size.y > 0


func register_render_mask_surface(name: StringName, texture: Texture2D) -> void:
	if name.is_empty():
		return
	if texture == null:
		unregister_render_mask_surface(name)
		return
	if _render_mask_surfaces.get(name) == texture:
		return
	_render_mask_surfaces[name] = texture
	_bump_render_mask_revision(name)


func unregister_render_mask_surface(name: StringName) -> void:
	if not _render_mask_surfaces.erase(name):
		return
	_bump_render_mask_revision(name)


func get_render_mask_texture(name: StringName) -> Texture2D:
	match name:
		&"current_visibility":
			return get_current_texture()
		&"fog_of_war":
			return get_fog_of_war_texture()
		_:
			return _render_mask_surfaces.get(name) as Texture2D


func get_render_mask_texture_revision(name: StringName) -> int:
	return int(_render_mask_texture_revisions.get(name, 0))


func get_current_texture() -> Texture2D:
	return _current_viewport.get_texture() if _current_viewport != null else null


func get_fog_of_war_texture() -> Texture2D:
	return _history_viewport.get_texture() if _history_viewport != null else null


func reset_fog_of_war_texture() -> void:
	_history_reset_pending = true
	_capture_dirty = true


func register_reveal_source(source: Node) -> bool:
	if not source is FogRevealSource2D:
		return false
	var key := source.get_instance_id()
	if _reveal_sources.has(key):
		return true
	_reveal_sources[key] = source
	var changed := Callable(self, "_on_reveal_source_changed")
	if source.has_signal("source_changed") and not source.is_connected("source_changed", changed):
		source.connect("source_changed", changed)
	var exiting := Callable(self, "_on_reveal_source_exiting").bind(source)
	if not source.tree_exiting.is_connected(exiting):
		source.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)
	_sync_source_cell_size(source as FogRevealSource2D)
	_adopt_source(source as FogRevealSource2D)
	_capture_dirty = true
	return true


func unregister_reveal_source(source: Node) -> void:
	if source == null:
		return
	_reveal_sources.erase(source.get_instance_id())
	_release_source(source)
	_capture_dirty = true


func register_fog_blocker(blocker: Node) -> bool:
	if blocker == null or not blocker.has_method("attach_capture_occluder"):
		return false
	var key := blocker.get_instance_id()
	if _blockers.has(key):
		return true
	_blockers[key] = blocker
	var changed := Callable(self, "_on_blocker_changed")
	if blocker.has_signal("blocker_changed") and not blocker.is_connected("blocker_changed", changed):
		blocker.connect("blocker_changed", changed)
	var exiting := Callable(self, "_on_blocker_exiting").bind(blocker)
	if not blocker.tree_exiting.is_connected(exiting):
		blocker.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)
	_adopt_blocker(blocker)
	_capture_dirty = true
	return true


func unregister_fog_blocker(blocker: Node) -> void:
	if blocker == null:
		return
	_blockers.erase(blocker.get_instance_id())
	_release_blocker(blocker)
	_capture_dirty = true


func register_memory_decay_source(source: Node) -> int:
	_ensure_memory_decay_controller()
	if _memory_decay_controller == null or not _memory_decay_controller.has_method("register_source"):
		return -1
	return int(_memory_decay_controller.call("register_source", source))


func unregister_memory_decay_source(source: Node) -> void:
	if _memory_decay_controller != null and _memory_decay_controller.has_method("unregister_source"):
		_memory_decay_controller.call("unregister_source", source)


func is_grid_cell_currently_visible(cell: Vector2i) -> bool:
	if not is_world_configured():
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_size.x or cell.y >= _grid_size.y:
		return false
	var center := Vector2(cell) * _world_settings.cell_size + Vector2.ONE * _world_settings.cell_size * 0.5
	for source_variant in _live_values(_reveal_sources):
		var source := source_variant as FogRevealSource2D
		if source == null or not source.is_effectively_enabled():
			continue
		var offset := center - source.get_effective_origin()
		var distance := offset.length()
		if distance > source.get_effective_range():
			continue
		if source.shape != FogRevealSource2D.Shape.CONE or distance <= 0.0001:
			return true
		var angle := rad_to_deg(acos(clampf(source.get_effective_forward().dot(offset / distance), -1.0, 1.0)))
		if angle <= source.cone_angle_degrees * 0.5:
			return true
	return false


func _process(_delta: float) -> void:
	if not is_world_configured():
		return
	_refresh_dynamic_occluders()
	if not _capture_dirty:
		return
	_ensure_capture_graph()
	if _history_reset_pending:
		_clear_history()
	_current_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_history_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_capture_dirty = false
	_revision += 1
	_render_mask_texture_revisions[&"current_visibility"] = _revision
	_render_mask_texture_revisions[&"fog_of_war"] = _revision
	fog_history_surface_updated.emit([Rect2(Vector2.ZERO, Vector2.ONE)])


func _ensure_capture_graph() -> void:
	if _current_viewport != null and is_instance_valid(_current_viewport):
		return
	_current_viewport = SubViewport.new()
	_current_viewport.name = "VisibilityCurrentViewport"
	_current_viewport.transparent_bg = false
	_current_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_current_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_current_viewport)
	_current_receiver = ColorRect.new()
	_current_receiver.color = Color.BLACK
	_current_receiver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_receiver.visibility_layer = FOG_CAPTURE_2D_LIGHT_MASK
	_current_viewport.add_child(_current_receiver)
	_current_root = Node2D.new()
	_current_root.name = "VisibilityCaptureRoot"
	_current_viewport.add_child(_current_root)
	_occluder_root = Node2D.new()
	_occluder_root.name = "VisibilityOccluders"
	_current_root.add_child(_occluder_root)
	_history_viewport = SubViewport.new()
	_history_viewport.name = "VisibilityHistoryViewport"
	_history_viewport.transparent_bg = false
	_history_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_history_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_history_viewport)
	_history_material = ShaderMaterial.new()
	_history_material.shader = HISTORY_SHADER
	_history_rect = ColorRect.new()
	_history_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history_rect.material = _history_material
	_history_viewport.add_child(_history_rect)
	_apply_capture_layout()


func _apply_capture_layout() -> void:
	if _current_viewport == null:
		return
	var size := Vector2i.ONE
	if is_world_configured():
		size = Vector2i(maxi(1, _grid_size.x * capture_resolution_per_grid_square), maxi(1, _grid_size.y * capture_resolution_per_grid_square))
	_current_viewport.size = size
	_history_viewport.size = size
	_current_receiver.size = Vector2(size)
	_history_rect.size = Vector2(size)
	if _current_root != null:
		var scale_value := Vector2(size) / _capture_rect.size
		_current_root.position = -_capture_rect.position * scale_value
		_current_root.scale = scale_value
	_black_texture = _solid_texture(size, Color.BLACK)
	if _history_material != null:
		_history_material.set_shader_parameter("previous_tex", _black_texture)
		_history_material.set_shader_parameter("current_tex", get_current_texture())


func _calculate_capture_rect() -> Rect2:
	if not is_world_configured():
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var padding := _world_settings.wall_thickness * 0.5
	return Rect2(Vector2(-padding, -padding), Vector2(_grid_size) * _world_settings.cell_size + Vector2.ONE * padding * 2.0)


func _clear_history() -> void:
	_history_reset_pending = false
	if _history_material != null:
		_history_material.set_shader_parameter("previous_tex", _black_texture)
		_history_material.set_shader_parameter("current_tex", get_current_texture())


func _register_existing_components() -> void:
	if get_tree() == null:
		return
	for source in get_tree().get_nodes_in_group("visibility_reveal_source_2d"):
		register_reveal_source(source)
	for blocker in get_tree().get_nodes_in_group(FOG_BLOCKER_2D_GROUP):
		register_fog_blocker(blocker)


func _on_tree_node_added(node: Node) -> void:
	if node is FogRevealSource2D:
		register_reveal_source(node)
	elif node.is_in_group(FOG_BLOCKER_2D_GROUP):
		register_fog_blocker(node)
	if node.is_in_group(DYNAMIC_SEGMENT_PROVIDER_GROUP):
		_capture_dirty = true


func _on_tree_node_removed(node: Node) -> void:
	if node == null:
		return
	_reveal_sources.erase(node.get_instance_id())
	_blockers.erase(node.get_instance_id())
	if node.is_in_group(DYNAMIC_SEGMENT_PROVIDER_GROUP):
		_remove_dynamic_provider(node.get_instance_id())


func _on_reveal_source_changed(source: FogRevealSource2D) -> void:
	_adopt_source(source)
	_capture_dirty = true


func _on_reveal_source_exiting(source: Node) -> void:
	unregister_reveal_source(source)


func _on_blocker_changed(_blocker: Node, _revision_value: int) -> void:
	_capture_dirty = true


func _on_blocker_exiting(blocker: Node) -> void:
	unregister_fog_blocker(blocker)


func _adopt_source(source: FogRevealSource2D) -> void:
	if _current_root == null:
		return
	var light := source.attach_capture_light(_current_root)
	if light != null:
		light.position = source.get_effective_origin()
		light.rotation = source.global_rotation if source.is_inside_tree() else source.rotation


func _release_source(source: Node) -> void:
	if source != null and is_instance_valid(source) and source.has_method("get_capture_light"):
		var light := source.call("get_capture_light") as PointLight2D
		if light != null and is_instance_valid(light) and light.get_parent() != source:
			light.queue_free()


func _adopt_blocker(blocker: Node) -> void:
	if _occluder_root != null:
		blocker.call("attach_capture_occluder", _occluder_root)


func _release_blocker(blocker: Node) -> void:
	if blocker != null and is_instance_valid(blocker) and blocker.has_method("release_capture_occluder"):
		blocker.call("release_capture_occluder")


func _sync_source_cell_size(source: FogRevealSource2D) -> void:
	if source != null:
		source.set_world_cell_size(_world_settings.cell_size if _world_settings != null else 1.0)


func _sync_all_source_cell_sizes() -> void:
	for source in _live_values(_reveal_sources):
		_sync_source_cell_size(source as FogRevealSource2D)


func _refresh_dynamic_occluders() -> void:
	if get_tree() == null or _occluder_root == null:
		return
	var active: Dictionary = {}
	for provider in get_tree().get_nodes_in_group(DYNAMIC_SEGMENT_PROVIDER_GROUP):
		if provider == null or not provider.has_method("get_visibility_segments_2d"):
			continue
		var provider_id := provider.get_instance_id()
		active[provider_id] = true
		var revision_value := int(provider.call("get_visibility_segments_2d_revision")) if provider.has_method("get_visibility_segments_2d_revision") else 0
		if int(_dynamic_provider_revisions.get(provider_id, -1)) == revision_value:
			continue
		_dynamic_provider_revisions[provider_id] = revision_value
		_rebuild_dynamic_provider(provider_id, provider.call("get_visibility_segments_2d") as Array)
	for provider_id in _dynamic_provider_revisions.keys():
		if not active.has(provider_id):
			_remove_dynamic_provider(int(provider_id))


func _rebuild_dynamic_provider(provider_id: int, segments: Array) -> void:
	_remove_dynamic_provider(provider_id)
	var thickness := maxf(0.001, _world_settings.wall_thickness if _world_settings != null else 0.1)
	for index in segments.size():
		var segment := segments[index] as Dictionary
		var start := segment.get("start", Vector2.ZERO) as Vector2
		var end := segment.get("end", Vector2.ZERO) as Vector2
		if start.is_equal_approx(end):
			continue
		var occluder := LightOccluder2D.new()
		occluder.light_mask = FOG_CAPTURE_2D_LIGHT_MASK
		var polygon := OccluderPolygon2D.new()
		polygon.closed = true
		var normal := (end - start).normalized().orthogonal() * thickness * 0.25
		polygon.polygon = PackedVector2Array([start + normal, end + normal, end - normal, start - normal])
		occluder.occluder = polygon
		_occluder_root.add_child(occluder)
		_dynamic_occluders["%d:%d" % [provider_id, index]] = occluder
	_capture_dirty = true


func _remove_dynamic_provider(provider_id: int) -> void:
	_dynamic_provider_revisions.erase(provider_id)
	var prefix := "%d:" % provider_id
	for key in _dynamic_occluders.keys():
		if String(key).begins_with(prefix):
			var occluder := _dynamic_occluders[key] as LightOccluder2D
			if occluder != null and is_instance_valid(occluder):
				occluder.queue_free()
			_dynamic_occluders.erase(key)
	_capture_dirty = true


func _clear_dynamic_occluders() -> void:
	for occluder in _dynamic_occluders.values():
		if occluder != null and is_instance_valid(occluder):
			occluder.queue_free()
	_dynamic_occluders.clear()
	_dynamic_provider_revisions.clear()


func _ensure_memory_decay_controller() -> void:
	if _memory_decay_controller != null and is_instance_valid(_memory_decay_controller):
		return
	var scene := load(FOG_MEMORY_DECAY_CONTROLLER_SCENE_PATH) as PackedScene
	if scene == null:
		return
	_memory_decay_controller = scene.instantiate()
	add_child(_memory_decay_controller)


func _bump_render_mask_revision(name: StringName) -> void:
	_revision += 1
	_render_mask_texture_revisions[name] = _revision


func _solid_texture(size: Vector2i, color: Color) -> Texture2D:
	var image := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _live_values(registry: Dictionary) -> Array:
	var result: Array = []
	var stale: Array = []
	for key in registry.keys():
		var value: Variant = registry[key]
		if value == null or not is_instance_valid(value):
			stale.append(key)
		else:
			result.append(value)
	for key in stale:
		registry.erase(key)
	return result
