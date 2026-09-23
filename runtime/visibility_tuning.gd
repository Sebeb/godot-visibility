extends Resource
class_name VisibilityTuning

## Addon-owned defaults and the optional boundary to a host state system.
##
## A host adapter may implement:
##   get_value(path: StringName, default_value: Variant) -> Variant
##   connect_changed(path: StringName, callback: Callable) -> void
## It may also implement disconnect_changed(path, callback) for clean teardown.

const DEFAULT_RECENCY_RATE_PER_SECOND := 0.0015
const DEFAULT_MAP_OPEN_MULTIPLIER := 12.0
const DEFAULT_VIEWING_MAP_STATE_PATH := &"visibility/viewing_map"

@export_range(0.0, 1.0, 0.00001) var recency_rate_per_second := DEFAULT_RECENCY_RATE_PER_SECOND
@export_range(1.0, 256.0, 0.1) var map_open_multiplier := DEFAULT_MAP_OPEN_MULTIPLIER
@export var viewing_map_state_path: StringName = DEFAULT_VIEWING_MAP_STATE_PATH

var state_adapter: Object = null


func get_value(path: StringName, default_value: Variant) -> Variant:
	if state_adapter == null or not is_instance_valid(state_adapter) or not state_adapter.has_method("get_value"):
		return default_value
	return state_adapter.call("get_value", path, default_value)


func connect_changed(path: StringName, callback: Callable) -> bool:
	if state_adapter == null or not is_instance_valid(state_adapter) or not state_adapter.has_method("connect_changed"):
		return false
	state_adapter.call("connect_changed", path, callback)
	return true


func disconnect_changed(path: StringName, callback: Callable) -> void:
	if state_adapter == null or not is_instance_valid(state_adapter) or not state_adapter.has_method("disconnect_changed"):
		return
	state_adapter.call("disconnect_changed", path, callback)
