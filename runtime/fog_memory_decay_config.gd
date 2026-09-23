extends Resource
class_name FogMemoryDecayConfig

## Authored gameplay-neutral parameters for one fog-memory contribution.
##
## PGO-157 makes forgetting age-ordered rather than radial: a contribution advances
## a frontier through the history texture's recency gradient, so the oldest explored
## areas are erased first no matter where the player currently stands.

# Advances the forgetting frontier by this much recency (0..1 across all explored
# history) per second. 0 disables this contribution.
@export_range(0.0, 1.0, 0.00001) var recency_rate_per_second := 0.0015
# Multiplies the rate while the player has the map open, per the design's
# "slow, but greatly increases while the map is open".
@export_range(1.0, 256.0, 0.1) var map_open_multiplier := 12.0
# Selects the winning decay tier; only the highest enabled priority advances.
@export var priority := 0
# Sets the one-shot scheduling interval in seconds while this tier wins.
@export_range(0.01, 10.0, 0.01) var cadence_seconds := 0.2
# Controls the soft visual profile applied while this contribution decays history.
@export var dissolve_profile: FogMemoryDissolveProfile = null
# Binds this contribution to a pill so its rates resolve through the PGO-180
# "gameplay_config/pill_effects/<pill_type>/<property>" live-tuning namespace.
@export var config_pill_type: StringName = &""


## Resolves the authored base rate through gameplay_config, falling back to the
## shipped value when no override is set.
func get_effective_recency_rate_per_second() -> float:
	return maxf(0.0, GameplayConfig.get_float(_config_path("decay_recency_rate"), recency_rate_per_second))


func get_effective_map_open_multiplier() -> float:
	return maxf(1.0, GameplayConfig.get_float(_config_path("decay_map_open_multiplier"), map_open_multiplier))


func _config_path(property_name: String) -> String:
	if String(config_pill_type).is_empty():
		# An unbound contribution has no pill namespace, so nothing can override it.
		return "__unbound__/%s" % property_name
	return "pill_effects/%s/%s" % [String(config_pill_type), property_name]
