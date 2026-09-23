extends Node2D
class_name FogRevealSource2D

## Authoritative maze-world fog revealer. Its PointLight2D is authored with
## the owning 2D entity; FogCameraManager observes lifecycle changes but never
## creates a transform proxy for this component.

signal source_changed(source: FogRevealSource2D)
signal corner_peek_offset_changed(offset: Vector2)

enum Shape { OMNI, CONE }

const _FOG_MANAGER_GROUP := "fog_camera_manager"
const _STATE_GAMEPLAY_STATE := "game_state/gameplay_state"
const _GAMEPLAY_STATE_LEVEL_GEN := "level_gen"
const _TEXTURE_RESOLUTION := 128

const GameplayConfig := preload("res://shared/state/gameplay_config.gd")
const _CORNER_PEEK_ENABLED_CONFIG_PATH := "player/corner_peek/enabled"
const _CORNER_PEEK_EASE_RATE_CONFIG_PATH := "player/corner_peek/ease_rate"
const _CORNER_PEEK_TRIGGER_DISTANCE_CONFIG_PATH := "player/corner_peek/trigger_distance_cells"
const _CORNER_PEEK_MAX_OFFSET_CONFIG_PATH := "player/corner_peek/max_offset_cells"
const _CORNER_PEEK_TARGET_OVERSHOOT_CONFIG_PATH := "player/corner_peek/target_overshoot_cells"
const _DEFAULT_CORNER_PEEK_EASE_RATE := 8.0
# Keep fallbacks identical to the first-person consumer: these are one shared
# gameplay tuning surface, not camera-mode-specific copies. Every distance is
# in maze cells, which is what lets one knob mean the same thing here (maze
# pixels) and in first person (3D world units).
const _DEFAULT_CORNER_PEEK_TRIGGER_DISTANCE_CELLS := 1.0
const _DEFAULT_CORNER_PEEK_MAX_OFFSET_CELLS := 0.3
const _DEFAULT_CORNER_PEEK_TARGET_OVERSHOOT_CELLS := 0.125

# Enables this source's authored light contribution to fog visibility.
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		_sync_source()

# Sets the source reveal radius in maze world units when no state path is bound.
@export_range(0.0, 256.0, 0.1) var reveal_range := 10.0:
	set(value):
		if is_equal_approx(reveal_range, value):
			return
		reveal_range = maxf(0.0, value)
		_sync_source()

# Selects an omni disc or directed cone reveal shape.
@export var shape: Shape = Shape.OMNI:
	set(value):
		if shape == value:
			return
		shape = value
		_capture_texture = null
		_sync_source()

# Sets the cone's full angle in degrees when Shape is CONE.
@export_range(1.0, 179.0, 1.0) var cone_angle_degrees := 70.0:
	set(value):
		if is_equal_approx(cone_angle_degrees, value):
			return
		cone_angle_degrees = clampf(value, 1.0, 179.0)
		_capture_texture = null
		_sync_source()

# Controls whether fog capture geometry occludes this source.
@export var occlusion_enabled := true:
	set(value):
		if occlusion_enabled == value:
			return
		occlusion_enabled = value
		_sync_source()

# Optional node whose global position this source reveals from. Left empty, the
# owning entity's EntityInfo detection origin is used, so a source authored on a
# static prefab root still follows the body that actually moves.
@export var origin_node: Node2D = null:
	set(value):
		if origin_node == value:
			return
		origin_node = value
		_sync_origin_tracking()

# Optional StateStore path that overrides reveal_range while it resolves to a number.
@export var range_state_path := "":
	set(value):
		if range_state_path == value:
			return
		range_state_path = value
		_rebind_range_state()
		_sync_source()

var _capture_light: PointLight2D = null
var _capture_texture: ImageTexture = null
var _manager: FogCameraManager = null
var _range_variable: StateVariable = null
var _resolved_range := 0.0
var _maze_cell_size_world := 1.0
var _gameplay_state_allows_enabled := true
var _entity_info: EntityInfo = null
var _last_origin := Vector2.INF
var _last_rotation := INF

var _corner_peek_maze_data: MazeGenerator.MazeData = null
var _corner_peek_cell_size := 1.0
var _corner_peek_offset := Vector2.ZERO
var _last_published_corner_peek_offset := Vector2.INF
var _corner_peek_maze_view: MazeView = null
var _corner_peek_last_facing := Vector2.RIGHT
var _corner_peek_last_base_origin := Vector2.INF
var _corner_peek_intent_source: MovementIntentSource2D = null
var _corner_peek_intent_source_resolved := false
var _corner_peek_facing_override_active := false
var _corner_peek_facing_override := Vector2.RIGHT


func _enter_tree() -> void:
	set_notify_transform(true)


func _ready() -> void:
	_ensure_capture_light()
	_entity_info = _find_entity_info()
	_sync_origin_tracking()
	_rebind_range_state()
	_bind_gameplay_state()
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
	_disconnect_range_state()
	_disconnect_gameplay_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_emit_source_changed_if_moved()


func get_capture_light() -> PointLight2D:
	_ensure_capture_light()
	return _capture_light


## Recreates this component-owned light directly in the isolated capture canvas.
## Godot binds Light2D to its first canvas entry, so a source light cannot be
## safely moved between the gameplay and capture canvases after it is live.
func attach_capture_light(capture_parent: Node) -> PointLight2D:
	if _capture_light != null and is_instance_valid(_capture_light):
		if _capture_light.get_parent() == capture_parent:
			return _capture_light
		_capture_light.queue_free()
		_capture_light = null
	_ensure_capture_light(capture_parent)
	_sync_source()
	return _capture_light


## Reveal range in maze world units, which is what every fog consumer (capture
## light texture scale, history dirty rects, the view-distance mask radius, and
## the CPU cell-visibility query) works in.
##
## A state-backed range is authored in CELLS - `level_state/player_sight_distance`
## is the shipped 3.5-cell player sight - so it has to be scaled by the maze's
## world cell size to survive a `gameplay_config/maze/cell_size_px` retune. The
## authored `reveal_range` export stays absolute: it is a per-prefab world-space
## number, not a grid-relative one.
func get_effective_range() -> float:
	if range_state_path.strip_edges().is_empty():
		return reveal_range
	return _resolved_range * _maze_cell_size_world


## Pushed by FogCameraManager from the live MazeBuilderSettings, on registration
## and again whenever the maze is (re)applied, so a live cell-size retune scales
## sight distance with the rest of the maze. Stays 1.0 for a source with no maze
## context, which keeps a bare fixture's authored numbers literal.
func set_maze_cell_size_world(cell_size_world: float) -> void:
	var next_cell_size := maxf(0.0001, cell_size_world)
	if is_equal_approx(_maze_cell_size_world, next_cell_size):
		return
	_maze_cell_size_world = next_cell_size
	if not range_state_path.strip_edges().is_empty():
		_sync_source()


func get_maze_cell_size_world() -> float:
	return _maze_cell_size_world


## The maze-space position this source reveals from. An entity's moving body is
## a sibling of this node, not an ancestor, so this node's own transform stays at
## the spawn cell for the entity's whole life and cannot be the origin. Includes
## the corner-peek offset, if any, so every consumer (fog capture, movement
## diffing) sees the same authoritative position.
##
## The peek offset is deliberately a maze-space delta, not a delta in this
## node's own rotating space: the fog capture canvas and the paired 3D light
## both place it against maze geometry, so a rotating 2D pivot must not turn it.
func get_effective_origin() -> Vector2:
	return _to_maze_space(_base_effective_origin()) + _get_corner_peek_offset()


func _base_effective_origin() -> Vector2:
	if origin_node != null and is_instance_valid(origin_node) and origin_node.is_inside_tree():
		return origin_node.global_position
	if _entity_info != null and is_instance_valid(_entity_info):
		return _entity_info.get_detection_global_position()
	return global_position


## Wires up the maze context corner peek needs (grid data + cell size, in the
## same maze-local world units MazeWallGeometry2D's other consumers use).
## Passing null data disables peek again (e.g. between levels while the maze
## is rebuilding).
func set_corner_peek_maze_context(maze_data: MazeGenerator.MazeData, cell_size: float, _unused_maze_root: Variant = null, maze_view: MazeView = null) -> void:
	_corner_peek_maze_data = maze_data
	_corner_peek_cell_size = maxf(0.0001, cell_size)
	_corner_peek_maze_view = maze_view
	if maze_data == null or maze_view == null:
		_set_corner_peek_offset(Vector2.ZERO)
	# A rebuilt maze usually means a respawned entity, so the intent source this
	# was holding may belong to the previous one.
	_corner_peek_intent_source = null
	_corner_peek_intent_source_resolved = false
	_sync_origin_tracking()


## Queries the shared forward contract both camera modes use, from the
## entity's own input intent.
func _compute_corner_peek_target_offset() -> Vector2:
	if _corner_peek_maze_data == null or _corner_peek_maze_view == null:
		return Vector2.ZERO
	if not bool(GameplayConfig.get_value(_CORNER_PEEK_ENABLED_CONFIG_PATH, true)):
		return Vector2.ZERO
	var trigger_distance_cells := GameplayConfig.get_float(_CORNER_PEEK_TRIGGER_DISTANCE_CONFIG_PATH, _DEFAULT_CORNER_PEEK_TRIGGER_DISTANCE_CELLS)
	var max_offset_cells := GameplayConfig.get_float(_CORNER_PEEK_MAX_OFFSET_CONFIG_PATH, _DEFAULT_CORNER_PEEK_MAX_OFFSET_CELLS)
	if trigger_distance_cells <= 0.0 or max_offset_cells <= 0.0:
		return Vector2.ZERO
	# Every distance knob is authored in cells so it follows a live
	# `gameplay_config/maze/cell_size_px` retune, and is converted here into the
	# maze-pixel space this view -- and the query -- work in.
	var overshoot := GameplayConfig.get_float(_CORNER_PEEK_TARGET_OVERSHOOT_CONFIG_PATH, _DEFAULT_CORNER_PEEK_TARGET_OVERSHOOT_CELLS) * _corner_peek_cell_size
	# Everything below is maze space. The maze's 2D root is a rotating pivot (the
	# Rotation modifier spins it), so an entity's global position and a global
	# input direction both carry that rotation while the wall grid the query
	# answers against never does. Feeding them in raw makes the whole gesture
	# swing off the maze as it turns. The offset comes back in maze space too,
	# which is the space every consumer of it already works in.
	var origin := _to_maze_space(_base_effective_origin())
	var result := _corner_peek_maze_view.query_corner_peek(
		origin,
		_corner_peek_facing(origin),
		trigger_distance_cells * _corner_peek_cell_size,
		max_offset_cells * _corner_peek_cell_size,
		overshoot
	)
	_publish_corner_peek_snapshot(result)
	if not bool(result.get("valid", false)):
		return Vector2.ZERO
	return (result.get("target", origin) as Vector2) - origin


## A point in this source's own space, restated in the maze view's.
func _to_maze_space(point: Vector2) -> Vector2:
	if _corner_peek_maze_view == null or not _corner_peek_maze_view.is_inside_tree():
		return point
	return _corner_peek_maze_view.to_local(point)


## A direction in this source's own space, restated in the maze view's. Uses the
## basis alone, so the pivot's translation never leaks into a heading.
func _direction_to_maze_space(direction: Vector2) -> Vector2:
	if _corner_peek_maze_view == null or not _corner_peek_maze_view.is_inside_tree():
		return direction
	var maze_direction := _corner_peek_maze_view.global_transform.basis_xform_inv(direction)
	if maze_direction.length_squared() <= 0.0000001:
		return direction
	return maze_direction.normalized()


func _publish_corner_peek_snapshot(snapshot: Dictionary) -> void:
	if get_tree() == null:
		return
	var producer := get_tree().get_first_node_in_group("corner_peek_object_layer_producer")
	if producer != null and producer.has_method("set_snapshot"):
		producer.call("set_snapshot", snapshot)


func _advance_corner_peek(delta: float) -> void:
	var target_offset := _compute_corner_peek_target_offset()
	var ease_rate := GameplayConfig.get_float(_CORNER_PEEK_EASE_RATE_CONFIG_PATH, _DEFAULT_CORNER_PEEK_EASE_RATE)
	# Framerate-independent exponential ease-toward-target, matching the
	# first-person peek's "1 - exp(-rate*delta)" idiom.
	var ease_t := clampf(1.0 - exp(-maxf(0.0, ease_rate) * maxf(0.0, delta)), 0.0, 1.0)
	var next_offset := _corner_peek_offset.lerp(target_offset, ease_t)
	if next_offset.length_squared() < 0.00000001:
		next_offset = Vector2.ZERO
	_set_corner_peek_offset(next_offset)


func _get_corner_peek_offset() -> Vector2:
	return _corner_peek_offset


## Exposes the presentation-only, already-eased offset for the paired player
## light without exposing a second fog or movement authority.
func get_corner_peek_offset() -> Vector2:
	return _corner_peek_offset


func _set_corner_peek_offset(next_offset: Vector2) -> void:
	if _corner_peek_offset.is_equal_approx(next_offset):
		return
	_corner_peek_offset = next_offset
	if _corner_peek_offset.is_equal_approx(_last_published_corner_peek_offset):
		return
	_last_published_corner_peek_offset = _corner_peek_offset
	corner_peek_offset_changed.emit(_corner_peek_offset)


## Corner peek follows the entity's raw movement *input*, not the motion that
## input produced. Walking into the wall beside a corner is the exact case the
## gesture exists for, and there the body is blocked: its movement delta is
## zero (or is being redirected along the wall by collision sliding), so a
## facing derived from realised motion either goes stale or points the wrong
## way. Releasing the input keeps the last non-zero intent, which is what holds
## the peek open while the player stands still.
##
## An entity that publishes no intent (a hand-built fixture, anything moved by
## writing its transform) still falls back to its realised movement.
##
## Answers in maze space, from a maze-space `origin`: the movement fallback is
## differenced there already, and a published intent is the entity's own
## (rotating) space, so it is converted rather than trusted.
func _corner_peek_facing(maze_space_origin: Vector2) -> Vector2:
	_update_last_movement_facing(maze_space_origin)
	if _corner_peek_facing_override_active:
		return _direction_to_maze_space(_corner_peek_facing_override)
	var intent := _resolve_corner_peek_intent_source()
	if intent == null:
		return _corner_peek_last_facing
	var desired := intent.get_desired_direction()
	if desired.length_squared() > 0.0001:
		return _direction_to_maze_space(desired)
	var heading := intent.get_latest_heading()
	if heading.length_squared() > 0.0001:
		return _direction_to_maze_space(heading)
	return _corner_peek_last_facing


## Claims the corner-peek aim heading from an external source (the
## first-person look yaw), in this source's own local 2D space -- the same
## space a published movement intent already arrives in (see
## _corner_peek_facing()), so it is converted into maze space the same way.
## Movement's own intent/realised-motion heading is ignored while this is
## active.
func set_corner_peek_facing_override(local_direction: Vector2) -> void:
	if local_direction.length_squared() <= 0.0001:
		return
	_corner_peek_facing_override_active = true
	_corner_peek_facing_override = local_direction.normalized()


## Releases the override; corner peek resumes aiming from movement intent /
## realised motion on the next update.
func clear_corner_peek_facing_override() -> void:
	_corner_peek_facing_override_active = false


func _resolve_corner_peek_intent_source() -> MovementIntentSource2D:
	if _corner_peek_intent_source != null and is_instance_valid(_corner_peek_intent_source):
		return _corner_peek_intent_source
	if _corner_peek_intent_source_resolved and _corner_peek_intent_source == null:
		return null
	_corner_peek_intent_source_resolved = true
	_corner_peek_intent_source = _find_movement_intent_source(get_parent())
	return _corner_peek_intent_source


## The intent source is a sibling *branch*, not a sibling node - the player
## authors it under its MovementController - so this walks the whole owning
## entity subtree rather than only the source's own siblings.
static func _find_movement_intent_source(root: Node) -> MovementIntentSource2D:
	if root == null:
		return null
	if root is MovementIntentSource2D:
		return root as MovementIntentSource2D
	for child in root.get_children():
		var found := _find_movement_intent_source(child)
		if found != null:
			return found
	return null


func _update_last_movement_facing(origin: Vector2) -> void:
	if _corner_peek_last_base_origin != Vector2.INF:
		var moved := origin - _corner_peek_last_base_origin
		if moved.length_squared() > 0.0001:
			_corner_peek_last_facing = moved.normalized()
	_corner_peek_last_base_origin = origin


## Maze-space direction a CONE source faces. The generated cone texture opens
## around local +X, and the capture light mirrors this node's global rotation,
## so the two stay consistent by construction. Meaningless for OMNI sources.
func get_effective_forward() -> Vector2:
	var world_forward := Vector2.RIGHT.rotated(global_rotation if is_inside_tree() else rotation)
	return _direction_to_maze_space(world_forward)


## A tracked origin is a plain Node2D with no transform signal to observe, so its
## movement is polled. Sources that reveal from their own transform keep relying
## on NOTIFICATION_TRANSFORM_CHANGED and never process. Corner peek also needs
## per-physics-frame easing, so it opts a source into processing the same way.
func _sync_origin_tracking() -> void:
	var tracks_external_origin := origin_node != null or _entity_info != null
	set_physics_process(tracks_external_origin or _corner_peek_maze_data != null)
	_reset_motion_cache()


func _physics_process(delta: float) -> void:
	_advance_corner_peek(delta)
	_emit_source_changed_if_moved()


## The 2D maze space rewrites its own transform every frame, and Godot notifies
## on assignment rather than on an actual change, so an ungated transform
## notification would re-emit for every source on every frame and force a capture
## redraw the fog is otherwise demand-driven enough to skip.
func _emit_source_changed_if_moved() -> void:
	var origin := get_effective_origin()
	var rotation_now := global_rotation
	if origin.is_equal_approx(_last_origin) and is_equal_approx(rotation_now, _last_rotation):
		return
	_last_origin = origin
	_last_rotation = rotation_now
	_emit_source_changed()


func _reset_motion_cache() -> void:
	_last_origin = get_effective_origin() if is_inside_tree() else Vector2.INF
	_last_rotation = global_rotation if is_inside_tree() else INF


func _find_entity_info() -> EntityInfo:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is EntityInfo:
			return child as EntityInfo
	return null


func is_effectively_enabled() -> bool:
	return enabled and _gameplay_state_allows_enabled


func _ensure_capture_light(capture_parent: Node = self) -> void:
	if _capture_light != null and is_instance_valid(_capture_light):
		return
	_capture_light = PointLight2D.new()
	_capture_light.name = "FogCaptureLight"
	_capture_light.visibility_layer = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.range_item_cull_mask = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.shadow_item_cull_mask = FogCameraManager.FOG_CAPTURE_2D_LIGHT_MASK
	_capture_light.energy = 1.0
	_capture_light.color = Color.WHITE
	if capture_parent == self:
		_capture_light.texture = _get_capture_texture()
	capture_parent.add_child(_capture_light)


func _sync_source() -> void:
	if not is_node_ready():
		return
	_ensure_capture_light()
	var changed := false
	var next_enabled := is_effectively_enabled()
	if _capture_light.enabled != next_enabled:
		_capture_light.enabled = next_enabled
		changed = true
	if _capture_light.shadow_enabled != occlusion_enabled:
		_capture_light.shadow_enabled = occlusion_enabled
		changed = true
	var capture_texture := _get_capture_texture()
	if _capture_light.texture != capture_texture:
		_capture_light.texture = capture_texture
		changed = true
	var next_texture_scale := maxf(0.01, get_effective_range()) / (float(_TEXTURE_RESOLUTION) * 0.5)
	if not is_equal_approx(_capture_light.texture_scale, next_texture_scale):
		_capture_light.texture_scale = next_texture_scale
		changed = true
	if changed:
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
			var distance := offset.length()
			var angle_ok := shape != Shape.CONE or absf(rad_to_deg(offset.angle())) <= cone_angle_degrees * 0.5
			var t := clampf(1.0 - distance / radius, 0.0, 1.0) if angle_ok else 0.0
			var intensity := t * t * (3.0 - 2.0 * t)
			image.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)


func _resolve_manager_once() -> void:
	_manager = get_tree().get_first_node_in_group(_FOG_MANAGER_GROUP) as FogCameraManager


func _on_tree_node_added(node: Node) -> void:
	if node is FogCameraManager:
		_manager = node as FogCameraManager
		get_tree().node_added.disconnect(_on_tree_node_added)
		_manager.register_reveal_source(self)


func _emit_source_changed() -> void:
	if is_inside_tree():
		source_changed.emit(self)


func _rebind_range_state() -> void:
	_disconnect_range_state()
	_set_resolved_range(reveal_range)
	if range_state_path.strip_edges().is_empty():
		return
	if not StateStore.variable_instance_replaced.is_connected(_on_range_variable_instance_replaced):
		StateStore.variable_instance_replaced.connect(_on_range_variable_instance_replaced)
	_bind_range_variable(StateStore.get_variable(range_state_path))


func _disconnect_range_state() -> void:
	if _range_variable != null and is_instance_valid(_range_variable) and _range_variable.resolved_value_changed.is_connected(_on_range_state_changed):
		_range_variable.resolved_value_changed.disconnect(_on_range_state_changed)
	_range_variable = null
	if StateStore.variable_instance_replaced.is_connected(_on_range_variable_instance_replaced):
		StateStore.variable_instance_replaced.disconnect(_on_range_variable_instance_replaced)


func _bind_range_variable(variable: StateVariable) -> void:
	_range_variable = variable
	if _range_variable == null:
		_set_resolved_range(reveal_range)
		return
	if not _range_variable.resolved_value_changed.is_connected(_on_range_state_changed):
		_range_variable.resolved_value_changed.connect(_on_range_state_changed)
	_on_range_state_changed(_range_variable.get_path(), null, _range_variable.resolved_value)


func _on_range_state_changed(_path: StringName, _old_value: Variant, value: Variant) -> void:
	if value is float or value is int:
		_set_resolved_range(maxf(0.0, float(value)))
	else:
		_set_resolved_range(reveal_range)


func _on_range_variable_instance_replaced(
	variable_path: StringName,
	_previous_variable: StateVariable,
	replacement_variable: StateVariable
) -> void:
	if variable_path != StringName(_normalized_range_state_path()):
		return
	_disconnect_range_variable()
	_bind_range_variable(replacement_variable)


func _disconnect_range_variable() -> void:
	if _range_variable != null and is_instance_valid(_range_variable) and _range_variable.resolved_value_changed.is_connected(_on_range_state_changed):
		_range_variable.resolved_value_changed.disconnect(_on_range_state_changed)
	_range_variable = null


func _set_resolved_range(value: float) -> void:
	var next_range := maxf(0.0, value)
	if is_equal_approx(_resolved_range, next_range):
		return
	_resolved_range = next_range
	_sync_source()


func _normalized_range_state_path() -> String:
	return range_state_path.strip_edges().to_lower().trim_prefix("/").trim_suffix("/")


func _bind_gameplay_state() -> void:
	var variable := StateStore.get_variable(_STATE_GAMEPLAY_STATE)
	if variable != null:
		variable.resolved_value_changed.connect(_on_gameplay_state_changed)
		_on_gameplay_state_changed(variable.get_path(), null, variable.resolved_value)


func _disconnect_gameplay_state() -> void:
	var variable := StateStore.get_variable(_STATE_GAMEPLAY_STATE)
	if variable != null and variable.resolved_value_changed.is_connected(_on_gameplay_state_changed):
		variable.resolved_value_changed.disconnect(_on_gameplay_state_changed)


func _on_gameplay_state_changed(_path: StringName, _old_value: Variant, value: Variant) -> void:
	_gameplay_state_allows_enabled = str(value) != _GAMEPLAY_STATE_LEVEL_GEN
	_sync_source()
