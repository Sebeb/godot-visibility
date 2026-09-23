extends Resource
class_name FogMemoryDecayConfig

## Authored gameplay-neutral parameters for one fog-memory contribution.
##
## Forgetting is age-ordered rather than radial: a contribution advances a frontier
## through the history texture's recency gradient, so the oldest explored areas are
## erased first no matter where the player currently stands.

# Advances the forgetting frontier by this much recency (0..1 across all explored
# history) per second. 0 disables this contribution.
@export_range(0.0, 1.0, 0.00001) var recency_rate_per_second := VisibilityTuning.DEFAULT_RECENCY_RATE_PER_SECOND
# Multiplies the rate while the player has the map open, per the design's
# "slow, but greatly increases while the map is open".
@export_range(1.0, 256.0, 0.1) var map_open_multiplier := VisibilityTuning.DEFAULT_MAP_OPEN_MULTIPLIER
# Selects the winning decay tier; only the highest enabled priority advances.
@export var priority := 0
# Sets the one-shot scheduling interval in seconds while this tier wins.
@export_range(0.01, 10.0, 0.01) var cadence_seconds := 0.2
# Controls the soft visual profile applied while this contribution decays history.
@export var dissolve_profile: FogMemoryDissolveProfile = null
# Optional adapter namespace for live values supplied by the host.
@export var tuning_path: StringName = &""


func get_effective_recency_rate_per_second(tuning: VisibilityTuning = null) -> float:
	var fallback := recency_rate_per_second if tuning == null else tuning.recency_rate_per_second
	return maxf(0.0, float(_get_tuned_value(tuning, &"decay_recency_rate", fallback)))


func get_effective_map_open_multiplier(tuning: VisibilityTuning = null) -> float:
	var fallback := map_open_multiplier if tuning == null else tuning.map_open_multiplier
	return maxf(1.0, float(_get_tuned_value(tuning, &"decay_map_open_multiplier", fallback)))


func _get_tuned_value(tuning: VisibilityTuning, property_name: StringName, fallback: Variant) -> Variant:
	if tuning == null or tuning_path.is_empty():
		return fallback
	return tuning.get_value(StringName("%s/%s" % [tuning_path, property_name]), fallback)
