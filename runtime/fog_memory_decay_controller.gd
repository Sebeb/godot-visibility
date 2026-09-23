extends Node
class_name FogMemoryDecayController

## Owns decay contribution arbitration and demand-driven one-shot scheduling.

signal active_tier_changed()
signal contributions_changed()
signal decay_tick(contributions: Array[Dictionary])

const GPU_BATCH_SIZE := 8
const MAX_GPU_BATCHES := 8
const MAX_REGISTERED_SOURCES := GPU_BATCH_SIZE * MAX_GPU_BATCHES

var _sources: Dictionary = {}
var _countdown_active := false
var _countdown_remaining := 0.0
var _last_active_priority: Variant = null
var _tick_count := 0
var _configuration_change_count := 0
var _last_cadence_seconds := 0.0
var _registration_rejection_count := 0
var _idle_schedule_count := 0
var _idle_timeout_skip_count := 0
var _worst_schedule_usec := 0


func _ready() -> void:
	set_process(true)


## Decay cadence is a gameplay duration, so the countdown runs on the world
## clock. A Godot Timer node would follow the engine clock instead, which no
## longer stops when the world freezes.
func _process(delta: float) -> void:
	if not _countdown_active:
		return
	# The host advances this controller with its chosen simulation delta.
	_countdown_remaining -= delta
	if _countdown_remaining <= 0.0:
		_countdown_active = false
		_on_timer_timeout()


func _exit_tree() -> void:
	_countdown_active = false
	for entry_variant in _sources.values():
		_disconnect_source((entry_variant as Dictionary).get("source") as FogMemoryDecaySource3D)
	_sources.clear()


func register_source(source: FogMemoryDecaySource3D) -> int:
	if source == null or not is_instance_valid(source):
		return -1
	var handle: int = source.get_instance_id()
	if _sources.has(handle):
		return -1
	if _sources.size() >= MAX_REGISTERED_SOURCES:
		_registration_rejection_count += 1
		return -1
	_sources[handle] = {"source": source}
	if not source.decay_changed.is_connected(_on_source_changed):
		source.decay_changed.connect(_on_source_changed)
	if not source.tree_exiting.is_connected(_on_source_tree_exiting.bind(source)):
		source.tree_exiting.connect(_on_source_tree_exiting.bind(source))
	_configuration_change_count += 1
	contributions_changed.emit()
	_recompute_schedule()
	return handle


func unregister_source(source: FogMemoryDecaySource3D) -> void:
	if source == null:
		return
	var handle: int = source.get_instance_id()
	if not _sources.has(handle):
		return
	_disconnect_source(source)
	_sources.erase(handle)
	_configuration_change_count += 1
	contributions_changed.emit()
	_recompute_schedule()


func has_registered_sources() -> bool:
	return not _sources.is_empty()


func has_enabled_sources() -> bool:
	return not _winning_contributions().is_empty()


func get_winning_contributions() -> Array[Dictionary]:
	return _winning_contributions()


func debug_get_snapshot() -> Dictionary:
	var active: Array[Dictionary] = _winning_contributions()
	return {
		"registered_count": _sources.size(),
		"enabled_count": _enabled_sources().size(),
		"winning_count": active.size(),
		"winning_priority": _winning_priority(),
		"timer_running": _countdown_active,
		"tick_count": _tick_count,
		"configuration_change_count": _configuration_change_count,
		"gpu_batch_size": GPU_BATCH_SIZE,
		"max_gpu_batches": MAX_GPU_BATCHES,
		"registration_rejection_count": _registration_rejection_count,
		"idle_schedule_count": _idle_schedule_count,
		"idle_timeout_skip_count": _idle_timeout_skip_count,
		"worst_schedule_usec": _worst_schedule_usec,
	}


func debug_fire_tick() -> void:
	_on_timer_timeout()


## Reports how far the forgetting frontier should advance on the next GPU pass,
## in recency units. Contributions in the winning tier combine to their fastest.
func get_pending_frontier_advance() -> float:
	var fastest_rate := 0.0
	for contribution in _winning_contributions():
		fastest_rate = maxf(fastest_rate, float(contribution["rate"]))
	return fastest_rate * _last_cadence_seconds


## Reports the softest authored frontier edge across the winning tier.
func get_frontier_soft_edge() -> float:
	var soft_edge := 0.0
	for contribution in _winning_contributions():
		var profile := contribution.get("dissolve_profile") as FogMemoryDissolveProfile
		if profile != null:
			soft_edge = maxf(soft_edge, profile.soft_edge_recency)
	return soft_edge


func _on_source_changed(_source: FogMemoryDecaySource3D) -> void:
	_configuration_change_count += 1
	contributions_changed.emit()
	_recompute_schedule()


func _on_source_tree_exiting(source: FogMemoryDecaySource3D) -> void:
	unregister_source(source)


func _disconnect_source(source: FogMemoryDecaySource3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source.decay_changed.is_connected(_on_source_changed):
		source.decay_changed.disconnect(_on_source_changed)
	var exit_callback := _on_source_tree_exiting.bind(source)
	if source.tree_exiting.is_connected(exit_callback):
		source.tree_exiting.disconnect(exit_callback)


func _enabled_sources() -> Array[FogMemoryDecaySource3D]:
	var result: Array[FogMemoryDecaySource3D] = []
	for entry_variant in _sources.values():
		var source: FogMemoryDecaySource3D = (entry_variant as Dictionary).get("source") as FogMemoryDecaySource3D
		if source != null and is_instance_valid(source) and source.is_decay_enabled():
			result.append(source)
	return result


func _winning_priority() -> Variant:
	var highest: Variant = null
	for source in _enabled_sources():
		var priority: int = source.config.priority
		if highest == null or priority > int(highest):
			highest = priority
	return highest


func _winning_contributions() -> Array[Dictionary]:
	var highest: Variant = _winning_priority()
	var result: Array[Dictionary] = []
	if highest == null:
		return result
	var sorted_handles: Array = _sources.keys()
	sorted_handles.sort()
	for handle_variant in sorted_handles:
		var handle: int = int(handle_variant)
		var entry: Dictionary = _sources[handle] as Dictionary
		var source: FogMemoryDecaySource3D = entry.get("source") as FogMemoryDecaySource3D
		if source == null or not is_instance_valid(source) or not source.is_decay_enabled() or source.config.priority != int(highest):
			continue
		result.append({
			"handle": handle,
			"rate": source.get_effective_recency_rate_per_second(),
			"dissolve_profile": source.config.dissolve_profile,
		})
	return result


func _recompute_schedule() -> void:
	var started_usec := Time.get_ticks_usec()
	var active: Array[Dictionary] = _winning_contributions()
	var priority: Variant = _winning_priority()
	if priority != _last_active_priority:
		_last_active_priority = priority
		active_tier_changed.emit()
	if active.is_empty():
		_countdown_active = false
		_idle_schedule_count += 1
		_record_schedule_cost(started_usec)
		return
	var cadence := 10.0
	for contribution in active:
		var source: FogMemoryDecaySource3D = (_sources[int(contribution["handle"])] as Dictionary).get("source") as FogMemoryDecaySource3D
		cadence = minf(cadence, source.config.cadence_seconds)
	_last_cadence_seconds = maxf(0.01, cadence)
	_countdown_remaining = _last_cadence_seconds
	_countdown_active = true
	_record_schedule_cost(started_usec)


func _on_timer_timeout() -> void:
	var active: Array[Dictionary] = _winning_contributions()
	if active.is_empty():
		_idle_timeout_skip_count += 1
		_recompute_schedule()
		return
	_tick_count += 1
	decay_tick.emit(active)
	_recompute_schedule()


func _record_schedule_cost(started_usec: int) -> void:
	_worst_schedule_usec = maxi(_worst_schedule_usec, Time.get_ticks_usec() - started_usec)
