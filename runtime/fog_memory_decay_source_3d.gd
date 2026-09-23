extends Node3D
class_name FogMemoryDecaySource3D

## Lifecycle-owned explored-memory decay contribution. It carries no concrete
## pill/gameplay activation policy; authored StateStore state supplies enablement.

signal decay_changed(source: FogMemoryDecaySource3D)

const _FOG_MANAGER_GROUP := "fog_camera_manager"
const SharedStateKeys := preload("res://shared/state/shared_state_keys.gd")

# Enables this authored contribution before its optional StateStore condition is applied.
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		_emit_decay_changed()

# Holds rate, priority, protection, cadence, and dissolve settings for this source.
@export var config: FogMemoryDecayConfig = null:
	set(value):
		if config == value:
			return
		config = value
		_emit_decay_changed()

# Optional StateStore path whose resolved truthiness gates this contribution.
@export var enable_state_path := "":
	set(value):
		if enable_state_path == value:
			return
		enable_state_path = value
		_rebind_enable_state()
		_emit_decay_changed()

var _manager: FogCameraManager = null
var _enable_variable: StateVariable = null
var _condition_enabled := true
var _viewing_map_variable: StateVariable = null
var _viewing_map := false


func _ready() -> void:
	_rebind_enable_state()
	_rebind_viewing_map_state()
	_resolve_manager_once()
	if _manager != null:
		_manager.register_memory_decay_source(self)
	elif get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _exit_tree() -> void:
	if _manager != null:
		_manager.unregister_memory_decay_source(self)
	_manager = null
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	_disconnect_enable_state()
	_disconnect_viewing_map_state()


func is_decay_enabled() -> bool:
	return enabled and _condition_enabled and get_effective_recency_rate_per_second() > 0.0


## Resolves the frontier speed this contribution currently advances at, in recency
## units per second. Forgetting is always running; opening the map only speeds it up.
func get_effective_recency_rate_per_second() -> float:
	if config == null:
		return 0.0
	var rate := config.get_effective_recency_rate_per_second()
	if _viewing_map:
		rate *= config.get_effective_map_open_multiplier()
	return rate


func _resolve_manager_once() -> void:
	if _manager != null and is_instance_valid(_manager):
		return
	_manager = get_tree().get_first_node_in_group(_FOG_MANAGER_GROUP) as FogCameraManager


func _on_tree_node_added(node: Node) -> void:
	if not node is FogCameraManager:
		return
	_manager = node as FogCameraManager
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	_manager.register_memory_decay_source(self)


func _rebind_enable_state() -> void:
	_disconnect_enable_state()
	_condition_enabled = true
	if enable_state_path.strip_edges().is_empty():
		return
	_enable_variable = StateStore.get_variable(enable_state_path)
	if _enable_variable == null:
		_condition_enabled = false
		return
	if not _enable_variable.resolved_value_changed.is_connected(_on_enable_state_changed):
		_enable_variable.resolved_value_changed.connect(_on_enable_state_changed)
	_on_enable_state_changed(_enable_variable.get_path(), null, _enable_variable.resolved_value)


func _disconnect_enable_state() -> void:
	if _enable_variable != null and is_instance_valid(_enable_variable) and _enable_variable.resolved_value_changed.is_connected(_on_enable_state_changed):
		_enable_variable.resolved_value_changed.disconnect(_on_enable_state_changed)
	_enable_variable = null


func _on_enable_state_changed(_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_condition_enabled = bool(new_value)
	_emit_decay_changed()


func _rebind_viewing_map_state() -> void:
	_disconnect_viewing_map_state()
	_viewing_map_variable = StateStore.get_variable(SharedStateKeys.PLAYER_VIEWING_MAP)
	if _viewing_map_variable == null:
		return
	if not _viewing_map_variable.resolved_value_changed.is_connected(_on_viewing_map_changed):
		_viewing_map_variable.resolved_value_changed.connect(_on_viewing_map_changed)
	_on_viewing_map_changed(_viewing_map_variable.get_path(), null, _viewing_map_variable.resolved_value)


func _disconnect_viewing_map_state() -> void:
	if _viewing_map_variable != null and is_instance_valid(_viewing_map_variable) and _viewing_map_variable.resolved_value_changed.is_connected(_on_viewing_map_changed):
		_viewing_map_variable.resolved_value_changed.disconnect(_on_viewing_map_changed)
	_viewing_map_variable = null


func _on_viewing_map_changed(_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	var next := bool(new_value)
	if _viewing_map == next:
		return
	_viewing_map = next
	# The frontier speed changed, so the controller must re-arbitrate and reschedule.
	_emit_decay_changed()


func _emit_decay_changed() -> void:
	if is_inside_tree():
		decay_changed.emit(self)
