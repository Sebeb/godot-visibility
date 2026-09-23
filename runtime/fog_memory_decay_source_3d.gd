extends Node3D
class_name FogMemoryDecaySource3D

## Lifecycle-owned explored-memory decay contribution. Optional host state is
## reached only through the manager's VisibilityTuning adapter.

signal decay_changed(source: FogMemoryDecaySource3D)

const _FOG_MANAGER_GROUP := "visibility_manager"

# Enables this authored contribution before its optional adapter condition is applied.
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

# Optional adapter path whose resolved truthiness gates this contribution.
@export var enable_state_path: StringName = &"":
	set(value):
		if enable_state_path == value:
			return
		if _tuning != null and not enable_state_path.is_empty():
			_tuning.disconnect_changed(enable_state_path, _on_enable_state_changed)
		enable_state_path = value
		_rebind_enable_state()
		_emit_decay_changed()

var _manager: FogCameraManager = null
var _tuning: VisibilityTuning = null
var _condition_enabled := true
var _viewing_map := false


func _ready() -> void:
	_resolve_manager_once()
	if _manager != null:
		_adopt_manager_tuning()
		_manager.register_memory_decay_source(self)
	elif get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _exit_tree() -> void:
	if _manager != null:
		_manager.unregister_memory_decay_source(self)
	_manager = null
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	_disconnect_tuning()


func is_decay_enabled() -> bool:
	return enabled and _condition_enabled and get_effective_recency_rate_per_second() > 0.0


## Resolves the frontier speed this contribution currently advances at, in recency
## units per second. Forgetting is always running; opening the map only speeds it up.
func get_effective_recency_rate_per_second() -> float:
	if config == null:
		return 0.0
	var rate := config.get_effective_recency_rate_per_second(_tuning)
	if _viewing_map:
		rate *= config.get_effective_map_open_multiplier(_tuning)
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
	_adopt_manager_tuning()
	_manager.register_memory_decay_source(self)


func _rebind_enable_state() -> void:
	_condition_enabled = true
	if _tuning == null or enable_state_path.is_empty():
		return
	_condition_enabled = bool(_tuning.get_value(enable_state_path, true))
	_tuning.connect_changed(enable_state_path, _on_enable_state_changed)


func _on_enable_state_changed(new_value: Variant) -> void:
	_condition_enabled = bool(new_value)
	_emit_decay_changed()


func _rebind_viewing_map_state() -> void:
	_viewing_map = false
	if _tuning == null or _tuning.viewing_map_state_path.is_empty():
		return
	_viewing_map = bool(_tuning.get_value(_tuning.viewing_map_state_path, false))
	_tuning.connect_changed(_tuning.viewing_map_state_path, _on_viewing_map_changed)


func _on_viewing_map_changed(new_value: Variant) -> void:
	var next := bool(new_value)
	if _viewing_map == next:
		return
	_viewing_map = next
	# The frontier speed changed, so the controller must re-arbitrate and reschedule.
	_emit_decay_changed()


func _adopt_manager_tuning() -> void:
	_disconnect_tuning()
	_tuning = _manager.get_visibility_tuning() if _manager != null else null
	_rebind_enable_state()
	_rebind_viewing_map_state()


func _disconnect_tuning() -> void:
	if _tuning != null:
		if not enable_state_path.is_empty():
			_tuning.disconnect_changed(enable_state_path, _on_enable_state_changed)
		if not _tuning.viewing_map_state_path.is_empty():
			_tuning.disconnect_changed(_tuning.viewing_map_state_path, _on_viewing_map_changed)
	_tuning = null


func _emit_decay_changed() -> void:
	if is_inside_tree():
		decay_changed.emit(self)
