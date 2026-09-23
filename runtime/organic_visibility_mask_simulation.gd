extends Node
class_name OrganicVisibilityMaskSimulation

## GPU owner for PGO-101's organic animated visibility mask.
##
## Replaces PGO-100's square max/min post-pass with a RenderingDevice compute
## ping-pong simulation. It owns every compute resource, the fixed-step
## schedule, dispatch ordering, ping-pong promotion, reset/reseed, and the
## demand-driven activity window.
##
## The simulation is strictly presentation-only. Gameplay visibility, cell
## discovery, AI, placement and fog history all keep reading the raw masks they
## own; nothing in this file is ever consulted by an authoritative query.
##
## Data flow, all on the GPU, with no per-frame readback anywhere:
##
##   composed `game_world` mask ─┐
##                               ├─▶ pack ─▶ packed lanes ─▶ halo (h, v)
##   packed auxiliary capture ───┘                │
##                                                ▼
##                              phase tick ─▶ creep substeps ─▶ present
##                                    └── ping-pong ──┘            │
##                                                                 ▼
##                                              world visibility materials
##
## The only readback in the file is inside `seed_islands()`, the explicitly
## manual island-seeding command the Goal carves out for it.

const SchedulerScript := preload("res://systems/maze/organic_visibility_mask_scheduler.gd")
const PACK_SHADER_PATH := "res://rendering/compute/visibility_mask_pack.glsl"
const HALO_SHADER_PATH := "res://rendering/compute/visibility_mask_halo.glsl"
const PHASE_SHADER_PATH := "res://rendering/compute/visibility_mask_phase.glsl"
const CREEP_SHADER_PATH := "res://rendering/compute/visibility_mask_creep.glsl"
const PRESENT_SHADER_PATH := "res://rendering/compute/visibility_mask_present.glsl"

const WORKGROUP_SIZE := 8
const MIN_SIM_AXIS := 8
const MAX_SIM_AXIS := 2048
## Blur weights. Only the corner weight is a state variable; the centre and
## cardinal weights are fixed because they set the operator's scale rather than
## its character, and the flat-front calibration below is expressed relative to
## them.
const CENTER_WEIGHT := 1.0
const CARDINAL_WEIGHT := 0.5
## Seeds and blockers are painted as hard unshaded geometry, so anything that
## survived the conservative max-downsample genuinely covered the texel.
const AUXILIARY_LANE_THRESHOLD := 0.5
## A claim only becomes a propagation source once it is fully claimed. This is
## what couples nominal creep speed to creep power, exactly as the
## proof-of-concept did.
const CLAIM_SOURCE_THRESHOLD := 0.999
## Hard ceiling on how long the simulation keeps dispatching after its last
## input change, so a pathological convergence estimate cannot pin the GPU.
const MAX_ACTIVE_SECONDS := 30.0
const FOUR_CONNECTED: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _configuration: Dictionary = {}
var _scheduler := SchedulerScript.new()

var _rendering_device: RenderingDevice = null
var _rendering_device_checked := false
var _resources_ready := false
var _resource_failure := ""

var _shaders: Dictionary = {}
var _pipelines: Dictionary = {}
var _sampler := RID()
var _packed_texture := RID()
var _halo_scratch_texture := RID()
var _halo_texture := RID()
var _state_textures: Array[RID] = []
var _present_texture := RID()
var _uniform_sets: Dictionary = {}
## Set from the main thread when an input texture changes; consumed on the
## render thread, which is the only place a uniform-set RID may be freed.
## Clearing the dictionary directly from the main thread would strand every RID
## in it, which is exactly the render-resource leak the quality gate watches for.
var _uniform_sets_dirty := false
var _state_parity := 0

var _present_texture_2d: Texture2DRD = null
var _substrate_texture: Texture2D = null
var _auxiliary_texture: Texture2D = null
var _substrate_rid := RID()
var _auxiliary_rid := RID()
var _input_revision := -1
var _last_packed_revision := -1
var _sim_size := Vector2i.ZERO
var _source_size := Vector2i.ZERO
var _rect_cells := Vector2.ZERO

var _enabled := false
var _active_seconds_remaining := 0.0
var _dispatched_frames := 0
var _present_ready := false
var _reset_requested := false
var _debug_view_enabled := false
var _tick_dispatch_count := 0
var _creep_dispatch_count := 0
var _pack_dispatch_count := 0
var _island_seed_count := 0
## Every GPU-to-CPU readback this object has ever performed, from any entry
## point. The continuous runtime path must leave this at zero forever; only the
## manual island command and the test-only debug reads may move it.
var _readback_count := 0
var _last_island_report: Dictionary = {}
var _debug_packed_image: Image = null
var _debug_state_texel := Vector2i.ZERO
var _debug_state_lanes := PackedFloat32Array()
## Nuclei planted by the manual island command whose claim has not yet been
## observed back. They count as reachable during the next reachability pass so
## the same component cannot be seeded twice before it registers.
var _pending_island_nuclei: Array[Vector2i] = []


func _exit_tree() -> void:
	_release_resources()


## Applies the `system/2d_rendering/animated_visibility_mask/**` configuration.
## Structural changes (simulation resolution) rebuild the GPU resources; every
## other value is picked up by the next dispatch without touching unrelated
## rendering state.
func configure(configuration: Dictionary) -> void:
	var previous_pixels_per_cell := int(_configuration.get("simulation_pixels_per_cell", 0))
	var previous_enabled := _enabled
	_configuration = configuration.duplicate()
	_enabled = bool(_configuration.get("enabled", false))
	if int(_configuration.get("simulation_pixels_per_cell", 0)) != previous_pixels_per_cell:
		_reset_requested = true
	if _enabled and not previous_enabled:
		_reset_requested = true
	if not _enabled:
		_present_ready = false
		_active_seconds_remaining = 0.0


## Binds this frame's inputs. `substrate` is the composed `game_world` mask and
## `auxiliary` is the packed seed/bypass/blocker capture; both are rendered over
## the same wall-inclusive maze rect at the same size, which is what lets the
## pack kernel treat them as one coordinate space.
func set_inputs(
	substrate: Texture2D,
	auxiliary: Texture2D,
	input_revision: int,
	rect_cells: Vector2
) -> void:
	if substrate != _substrate_texture or auxiliary != _auxiliary_texture:
		_substrate_texture = substrate
		_auxiliary_texture = auxiliary
		_uniform_sets_dirty = true
	if not rect_cells.is_equal_approx(_rect_cells):
		_rect_cells = rect_cells
		_reset_requested = true
	if input_revision != _input_revision:
		_input_revision = input_revision
		_active_seconds_remaining = _convergence_bound_seconds()


func request_reset() -> void:
	_reset_requested = true


func set_debug_view_enabled(enabled: bool) -> void:
	_debug_view_enabled = enabled


## The presented visibility texture, or `fallback` while the simulation is
## disabled, unsupported, or has not yet published a completed frame. Returning
## the raw composed mask is an exact presentation bypass, which is also what
## makes a headless run (no RenderingDevice) behave as if the feature were off.
func get_output_texture(fallback: Texture2D) -> Texture2D:
	if not is_presenting():
		return fallback
	return _present_texture_2d


## True while `get_output_texture` returns the simulated field rather than the
## fallback. Callers that publish a revision alongside the texture must agree
## with this predicate, or a consumer caches a texture the revision denies.
func is_presenting() -> bool:
	return _enabled and _present_ready and _present_texture_2d != null


## Advances once per dispatched simulation frame, which is precisely when the
## presented field can differ from the one before it. Consumed as the
## `game_world_animated` render-mask revision so the compositor recomposes a routed
## layer exactly on the frames the field actually moved.
func get_present_revision() -> int:
	return _dispatched_frames


func update(delta: float) -> void:
	if not _enabled or _substrate_texture == null or _auxiliary_texture == null:
		return
	if not _ensure_rendering_device():
		return
	var desired_size := _desired_sim_size()
	if desired_size.x <= 0 or desired_size.y <= 0:
		return
	var substrate_rid := _substrate_texture.get_rid()
	var auxiliary_rid := _auxiliary_texture.get_rid()
	var source_size := Vector2i(_substrate_texture.get_size())
	if substrate_rid != _substrate_rid or auxiliary_rid != _auxiliary_rid or source_size != _source_size:
		_substrate_rid = substrate_rid
		_auxiliary_rid = auxiliary_rid
		_source_size = source_size
		_uniform_sets_dirty = true
	if desired_size != _sim_size:
		_sim_size = desired_size
		_reset_requested = true

	var reset_now := _reset_requested
	_reset_requested = false
	if reset_now:
		_scheduler.reset()
		_present_ready = false
		_active_seconds_remaining = _convergence_bound_seconds()

	var repack := reset_now or _input_revision != _last_packed_revision
	if repack:
		_last_packed_revision = _input_revision

	var ticks := PackedInt32Array()
	if _active_seconds_remaining > 0.0:
		_active_seconds_remaining = maxf(0.0, _active_seconds_remaining - maxf(0.0, delta))
		ticks = _scheduler.advance(
			delta,
			_float_config("ticks_per_second", 60.0),
			_creep_steps_per_tick(),
			int(_configuration.get("max_catch_up_steps", 4))
		)
	# Static simulation state, or a rendered frame short enough to owe no tick
	# yet: dispatch nothing at all rather than re-recording a settled state. At
	# 144 FPS against a 60-tick schedule most frames land here, which is the
	# whole point of metering by tick rather than by frame.
	if ticks.is_empty() and not repack:
		return

	var batch := {
		"reset": reset_now,
		"repack": repack,
		"ticks": ticks,
		"sim_size": _sim_size,
		"source_size": _source_size,
		"substrate_rid": _substrate_rid,
		"auxiliary_rid": _auxiliary_rid,
		"parameters": _resolve_dispatch_parameters(),
		"debug_view": _debug_view_enabled,
	}
	_dispatched_frames += 1
	RenderingServer.call_on_render_thread(_render_thread_dispatch.bind(batch))
	# A dispatch recorded this frame is only guaranteed complete for the next
	# frame's sampling, so the public texture is withheld until then. That is
	# the same "never bind the buffer queued for this frame" contract PGO-100's
	# chain held, expressed for compute.
	if _dispatched_frames >= 2:
		_present_ready = true


func debug_get_snapshot() -> Dictionary:
	return {
		"enabled": _enabled,
		"supported": _rendering_device != null,
		"resource_failure": _resource_failure,
		"present_ready": _present_ready,
		"sim_size": _sim_size,
		"source_size": _source_size,
		"executed_ticks": _scheduler.get_executed_ticks(),
		"dropped_ticks": _scheduler.get_dropped_ticks(),
		"total_creep_steps": _scheduler.get_total_creep_steps(),
		"creep_steps_per_tick": _creep_steps_per_tick(),
		"effective_creep_cells_per_second": effective_creep_cells_per_second(),
		"growth_bias_per_tick": _growth_bias_per_tick(),
		"shrink_bias_per_tick": _shrink_bias_per_tick(),
		"flat_front_gradient": flat_front_gradient(_float_config("sharpness", 1.05), _corner_weight()),
		"tick_dispatch_count": _tick_dispatch_count,
		"creep_dispatch_count": _creep_dispatch_count,
		"pack_dispatch_count": _pack_dispatch_count,
		"dispatched_frames": _dispatched_frames,
		"active_seconds_remaining": _active_seconds_remaining,
		"island_seed_count": _island_seed_count,
		"readback_count": _readback_count,
		"pending_island_nuclei": _pending_island_nuclei.size(),
		"last_island_report": _last_island_report,
		"debug_view": _debug_view_enabled,
	}


## Effective phase-field front velocity in maze cells per second for a FLAT
## front. Curvature and blockers legitimately change the local apparent speed:
## a convex boundary loses to its own renormalised neighbourhood and advances
## slower, a concave one faster, and a blocker that removes taps changes both.
## The control is nevertheless expressed in cells per second because that is
## the number that is stable to tune against.
func effective_creep_cells_per_second() -> float:
	return _float_config("creep_speed_cells_per_second", 4.0) * _float_config("creep_power", 0.05)


## Steady-state gradient of the phase field at its boundary, in field units per
## simulation texel.
##
## The 3x3 blur adds `sigma_blur^2` to the profile variance each tick while the
## sharpen multiplies its slope by `sharpness`. They balance at
## `sigma_profile^2 = sigma_blur^2 / (2 * (sharpness - 1))`, and a Gaussian
## profile of that width has peak slope `1 / (sigma_profile * sqrt(TAU))`.
## A directional bias of `b` per tick therefore moves the 0.5 crossing by
## `b / gradient` texels per tick, which is the calibration the growth and
## shrink speeds are converted through.
static func flat_front_gradient(sharpness: float, corner_weight: float) -> float:
	var corner := maxf(0.0, corner_weight)
	var total := CENTER_WEIGHT + 4.0 * CARDINAL_WEIGHT + 4.0 * corner
	var blur_variance := 2.0 * (CARDINAL_WEIGHT + 2.0 * corner) / maxf(0.0001, total)
	var sharpen := maxf(1.0001, sharpness)
	var profile_variance := blur_variance / (2.0 * (sharpen - 1.0))
	return 1.0 / maxf(0.0001, sqrt(profile_variance) * sqrt(TAU))


## Converts a user-facing front speed in maze cells per second into the signed
## per-tick bias the phase kernel applies.
static func bias_for_speed(
	cells_per_second: float,
	pixels_per_cell: float,
	ticks_per_second: float,
	sharpness: float,
	corner_weight: float
) -> float:
	var texels_per_tick := maxf(0.0, cells_per_second) * maxf(0.0, pixels_per_cell) / maxf(0.0001, ticks_per_second)
	# Half a field unit per tick is already a hard snap; clamping there keeps a
	# absurd speed from turning the operator into a step function.
	return clampf(texels_per_tick * flat_front_gradient(sharpness, corner_weight), 0.0, 0.5)


## Plants a stable seed nucleus in every permitted-substrate component that no
## active seed or valid claim can reach.
##
## This is the one place the Goal permits a GPU readback, and it is manual only:
## no `game_world` revision, provider change or player movement reaches it. Two
## bounded reads (packed lanes, simulation state) and one bounded write.
func seed_islands() -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "disabled"}
	if not _ensure_rendering_device():
		return {"ok": false, "reason": "no_rendering_device"}
	if not _resources_ready or _sim_size.x <= 0:
		return {"ok": false, "reason": "not_ready"}
	# Runs on the render thread so the readback observes a consistent, fully
	# recorded state rather than a half-written ping-pong. A GDScript lambda
	# captures by value, so the report is handed back through the member the
	# debug snapshot reads anyway rather than through the closure.
	_last_island_report = {}
	RenderingServer.call_on_render_thread(_run_island_seed_on_render_thread)
	RenderingServer.force_sync()
	_island_seed_count += 1
	_active_seconds_remaining = _convergence_bound_seconds()
	return _last_island_report


func _run_island_seed_on_render_thread() -> void:
	_last_island_report = _seed_islands_on_render_thread()


## Test-only bounded readback of the packed simulation input, so a fixture can
## assert the lane assignment the kernels actually see rather than the lane
## assignment the painters intended. Never called from the runtime path.
func debug_read_packed_image() -> Image:
	if not _ensure_rendering_device() or not _resources_ready or _packed_texture == RID():
		return null
	_debug_packed_image = null
	RenderingServer.call_on_render_thread(_read_packed_on_render_thread)
	RenderingServer.force_sync()
	return _debug_packed_image


## Test-only bounded readback of the four simulation lanes at one texel:
## `[normal field, bypass field, normal claim, bypass claim]`.
func debug_read_state_lanes(texel: Vector2i) -> PackedFloat32Array:
	if not _ensure_rendering_device() or not _resources_ready or _state_textures.is_empty():
		return PackedFloat32Array()
	_debug_state_texel = texel
	_debug_state_lanes = PackedFloat32Array()
	RenderingServer.call_on_render_thread(_read_state_on_render_thread)
	RenderingServer.force_sync()
	return _debug_state_lanes


func _read_state_on_render_thread() -> void:
	_readback_count += 1
	var format := _rendering_device.texture_get_format(_state_textures[_state_parity])
	var bytes := _rendering_device.texture_get_data(_state_textures[_state_parity], 0)
	var offset := (_debug_state_texel.y * int(format.width) + _debug_state_texel.x) * 8
	var lanes := PackedFloat32Array()
	for component in 4:
		lanes.append(bytes.decode_half(offset + component * 2))
	_debug_state_lanes = lanes


func _read_packed_on_render_thread() -> void:
	_readback_count += 1
	var format := _rendering_device.texture_get_format(_packed_texture)
	var bytes := _rendering_device.texture_get_data(_packed_texture, 0)
	_debug_packed_image = Image.create_from_data(
		int(format.width), int(format.height), false, Image.FORMAT_RGBA8, bytes
	)


func _float_config(key: String, fallback: float) -> float:
	var value: Variant = _configuration.get(key, fallback)
	return float(value) if (value is float or value is int) else fallback


func _corner_weight() -> float:
	return maxf(0.0, _float_config("corner_weight", 0.25))


func _pixels_per_cell() -> float:
	return maxf(1.0, float(int(_configuration.get("simulation_pixels_per_cell", 8))))


func _growth_bias_per_tick() -> float:
	return bias_for_speed(
		_float_config("growth_speed_cells_per_second", 3.0),
		_pixels_per_cell(),
		_float_config("ticks_per_second", 60.0),
		_float_config("sharpness", 1.05),
		_corner_weight()
	)


func _shrink_bias_per_tick() -> float:
	return bias_for_speed(
		_float_config("shrink_speed_cells_per_second", 3.0),
		_pixels_per_cell(),
		_float_config("ticks_per_second", 60.0),
		_float_config("sharpness", 1.05),
		_corner_weight()
	)


## Creep substeps owed per simulation tick. Metering creep per TICK rather than
## per frame is what keeps the whole simulation a pure function of the tick
## count, and therefore identical at 30, 60 and 144 rendered frames per second.
func _creep_steps_per_tick() -> float:
	var texels_per_second := _float_config("creep_speed_cells_per_second", 4.0) * _pixels_per_cell()
	return texels_per_second / maxf(0.0001, _float_config("ticks_per_second", 60.0))


func _halo_radius_texels() -> int:
	return int(round(maxf(0.0, _float_config("halo_radius_cells", 0.75)) * _pixels_per_cell()))


func _desired_sim_size() -> Vector2i:
	if _rect_cells.x <= 0.0 or _rect_cells.y <= 0.0:
		return Vector2i.ZERO
	var pixels_per_cell := _pixels_per_cell()
	return Vector2i(
		clampi(int(round(_rect_cells.x * pixels_per_cell)), MIN_SIM_AXIS, MAX_SIM_AXIS),
		clampi(int(round(_rect_cells.y * pixels_per_cell)), MIN_SIM_AXIS, MAX_SIM_AXIS)
	)


## How long the simulation can still be doing visible work after its last input
## change. Derived from the slowest front that has to cross the whole surface,
## so a settled mask stops dispatching instead of burning GPU time forever.
func _convergence_bound_seconds() -> float:
	var diagonal_cells := (Vector2(maxf(1.0, _rect_cells.x), maxf(1.0, _rect_cells.y))).length()
	var growth := _float_config("growth_speed_cells_per_second", 3.0)
	var shrink := _float_config("shrink_speed_cells_per_second", 3.0)
	var creep := effective_creep_cells_per_second()
	var slowest := maxf(0.01, minf(minf(maxf(growth, 0.01), maxf(shrink, 0.01)), maxf(creep, 0.01)))
	var halo_settle := maxf(0.0, _float_config("halo_radius_cells", 0.75)) / maxf(0.01, shrink)
	return minf(MAX_ACTIVE_SECONDS, diagonal_cells / slowest + halo_settle)


func _resolve_dispatch_parameters() -> Dictionary:
	var creep_speed := _float_config("creep_speed_cells_per_second", 4.0)
	return {
		"substrate_threshold": clampf(_float_config("substrate_threshold", 0.35), 0.0, 1.0),
		"sharpness": maxf(1.0001, _float_config("sharpness", 1.05)),
		"corner_weight": _corner_weight(),
		"growth_bias": _growth_bias_per_tick(),
		"shrink_bias": _shrink_bias_per_tick(),
		"creep_power": clampf(_float_config("creep_power", 0.05), 0.0001, 1.0),
		"creep_enabled": creep_speed > 0.0,
		"halo_radius_texels": _halo_radius_texels(),
	}


func _ensure_rendering_device() -> bool:
	if not _rendering_device_checked:
		_rendering_device_checked = true
		_rendering_device = RenderingServer.get_rendering_device()
		if _rendering_device == null:
			# Headless and dummy-driver runs have no RenderingDevice. The
			# simulation stays an exact presentation bypass rather than
			# emitting an error per frame.
			_resource_failure = "no_rendering_device"
	return _rendering_device != null


# --- render-thread side ------------------------------------------------------
# Everything below runs on the rendering thread. It touches only RenderingDevice
# resources this object owns, plus counters that are read for diagnostics.


func _render_thread_dispatch(batch: Dictionary) -> void:
	if _rendering_device == null:
		return
	var sim_size: Vector2i = batch["sim_size"]
	if not _ensure_gpu_resources(sim_size):
		return
	if bool(batch["reset"]):
		_clear_state_textures()
	if not _ensure_uniform_sets(batch):
		return

	var parameters: Dictionary = batch["parameters"]
	var compute_list := _rendering_device.compute_list_begin()
	if bool(batch["repack"]):
		_record_pack(compute_list, batch, parameters)
		_record_halo(compute_list, batch, parameters)
	var ticks: PackedInt32Array = batch["ticks"]
	for tick_index in ticks.size():
		_record_phase(compute_list, batch, parameters)
		for _step in ticks[tick_index]:
			_record_creep(compute_list, batch, parameters)
	_record_present(compute_list, batch)
	_rendering_device.compute_list_end()


func _record_pack(compute_list: int, batch: Dictionary, parameters: Dictionary) -> void:
	var sim_size: Vector2i = batch["sim_size"]
	var source_size: Vector2i = batch["source_size"]
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipelines["pack"])
	_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_sets["pack"], 0)
	_rendering_device.compute_list_set_push_constant(
		compute_list,
		_encode_push([
			sim_size.x, sim_size.y, source_size.x, source_size.y,
			float(parameters["substrate_threshold"]),
			AUXILIARY_LANE_THRESHOLD,
			AUXILIARY_LANE_THRESHOLD,
			0.0,
		]),
		32
	)
	_dispatch(compute_list, sim_size)
	_pack_dispatch_count += 1


func _record_halo(compute_list: int, batch: Dictionary, parameters: Dictionary) -> void:
	var sim_size: Vector2i = batch["sim_size"]
	var radius := int(parameters["halo_radius_texels"])
	for axis in 2:
		_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipelines["halo"])
		_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_sets["halo_%d" % axis], 0)
		_rendering_device.compute_list_set_push_constant(
			compute_list,
			_encode_push([sim_size.x, sim_size.y, radius, axis]),
			16
		)
		_dispatch(compute_list, sim_size)


func _record_phase(compute_list: int, batch: Dictionary, parameters: Dictionary) -> void:
	var sim_size: Vector2i = batch["sim_size"]
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipelines["phase"])
	_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_sets["phase_%d" % _state_parity], 0)
	_rendering_device.compute_list_set_push_constant(
		compute_list,
		_encode_push([
			sim_size.x, sim_size.y, 1 if bool(parameters["creep_enabled"]) else 0, 0,
			CENTER_WEIGHT, CARDINAL_WEIGHT, float(parameters["corner_weight"]), float(parameters["sharpness"]),
			float(parameters["growth_bias"]), float(parameters["shrink_bias"]), 0.0, 0.0,
		]),
		48
	)
	_dispatch(compute_list, sim_size)
	_state_parity = 1 - _state_parity
	_tick_dispatch_count += 1


## The four-connected / eight-connected alternation is driven by the GLOBAL
## dispatch counter, not by the substep's index inside its tick. A per-tick index
## resets every tick, so with a non-integer substeps-per-tick rate the sequence
## skews toward eight-connected and the front marches out as a square instead of
## approximating a radial one.
func _record_creep(compute_list: int, batch: Dictionary, parameters: Dictionary) -> void:
	var sim_size: Vector2i = batch["sim_size"]
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipelines["creep"])
	_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_sets["creep_%d" % _state_parity], 0)
	_rendering_device.compute_list_set_push_constant(
		compute_list,
		_encode_push([
			sim_size.x, sim_size.y, _creep_dispatch_count % 2, 1 if bool(parameters["creep_enabled"]) else 0,
			float(parameters["creep_power"]), CLAIM_SOURCE_THRESHOLD, 0.0, 0.0,
		]),
		32
	)
	_dispatch(compute_list, sim_size)
	_state_parity = 1 - _state_parity
	_creep_dispatch_count += 1


func _record_present(compute_list: int, batch: Dictionary) -> void:
	var sim_size: Vector2i = batch["sim_size"]
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipelines["present"])
	_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_sets["present_%d" % _state_parity], 0)
	_rendering_device.compute_list_set_push_constant(
		compute_list,
		_encode_push([sim_size.x, sim_size.y, 1 if bool(batch["debug_view"]) else 0, 0]),
		16
	)
	_dispatch(compute_list, sim_size)


## Every pass in the list reads the image the previous pass wrote: pack feeds
## halo, halo feeds phase, and each creep substep feeds the next. The barrier is
## the ordering guarantee that makes the substeps ORDERED substeps rather than
## a race, so it is issued unconditionally rather than relying on the graph to
## infer the dependency.
func _dispatch(compute_list: int, sim_size: Vector2i) -> void:
	var groups_x := int(ceil(float(sim_size.x) / float(WORKGROUP_SIZE)))
	var groups_y := int(ceil(float(sim_size.y) / float(WORKGROUP_SIZE)))
	_rendering_device.compute_list_dispatch(compute_list, maxi(1, groups_x), maxi(1, groups_y), 1)
	_rendering_device.compute_list_add_barrier(compute_list)


static func _encode_push(values: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		var value: Variant = values[index]
		if value is int:
			bytes.encode_s32(index * 4, int(value))
		else:
			bytes.encode_float(index * 4, float(value))
	return bytes


func _ensure_gpu_resources(sim_size: Vector2i) -> bool:
	if _resources_ready and _sim_size_matches(sim_size):
		return true
	_release_gpu_resources()
	if not _ensure_shaders():
		return false
	if _sampler == RID():
		var sampler_state := RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_sampler = _rendering_device.sampler_create(sampler_state)

	_packed_texture = _create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	_halo_scratch_texture = _create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	_halo_texture = _create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	_state_textures = [
		_create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT),
		_create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT),
	]
	_present_texture = _create_storage_texture(sim_size, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	if _present_texture == RID():
		_resource_failure = "texture_create_failed"
		return false
	_clear_state_textures()
	_rendering_device.texture_clear(_present_texture, Color(0.0, 0.0, 0.0, 1.0), 0, 1, 0, 1)
	if _present_texture_2d == null:
		_present_texture_2d = Texture2DRD.new()
	_present_texture_2d.texture_rd_rid = _present_texture
	_state_parity = 0
	_resources_ready = true
	_resource_failure = ""
	return true


func _sim_size_matches(sim_size: Vector2i) -> bool:
	if _present_texture == RID():
		return false
	var format := _rendering_device.texture_get_format(_present_texture)
	return format.width == sim_size.x and format.height == sim_size.y


func _create_storage_texture(size: Vector2i, format: int) -> RID:
	var texture_format := RDTextureFormat.new()
	texture_format.width = maxi(1, size.x)
	texture_format.height = maxi(1, size.y)
	texture_format.depth = 1
	texture_format.array_layers = 1
	texture_format.mipmaps = 1
	texture_format.format = format
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	# CAN_COPY_TO is what `texture_clear()` requires; CAN_UPDATE is what the
	# manual island command's single bounded write-back requires.
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return _rendering_device.texture_create(texture_format, RDTextureView.new(), [])


func _clear_state_textures() -> void:
	for texture in _state_textures:
		if texture != RID():
			_rendering_device.texture_clear(texture, Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	if _halo_texture != RID():
		_rendering_device.texture_clear(_halo_texture, Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	if _halo_scratch_texture != RID():
		_rendering_device.texture_clear(_halo_scratch_texture, Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	if _packed_texture != RID():
		_rendering_device.texture_clear(_packed_texture, Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	_state_parity = 0


func _ensure_shaders() -> bool:
	if not _pipelines.is_empty():
		return true
	var paths := {
		"pack": PACK_SHADER_PATH,
		"halo": HALO_SHADER_PATH,
		"phase": PHASE_SHADER_PATH,
		"creep": CREEP_SHADER_PATH,
		"present": PRESENT_SHADER_PATH,
	}
	for key_variant in paths.keys():
		var key := String(key_variant)
		var shader_file := load(String(paths[key_variant])) as RDShaderFile
		if shader_file == null:
			_resource_failure = "missing_shader:%s" % key
			return false
		var spirv := shader_file.get_spirv()
		if spirv == null:
			_resource_failure = "missing_spirv:%s" % key
			return false
		var shader := _rendering_device.shader_create_from_spirv(spirv)
		if shader == RID():
			_resource_failure = "shader_create_failed:%s" % key
			return false
		_shaders[key] = shader
		_pipelines[key] = _rendering_device.compute_pipeline_create(shader)
	return true


func _ensure_uniform_sets(batch: Dictionary) -> bool:
	if _uniform_sets_dirty:
		_uniform_sets_dirty = false
		_free_uniform_sets()
	if not _uniform_sets.is_empty():
		return true
	var substrate_rd := RenderingServer.texture_get_rd_texture(batch["substrate_rid"])
	var auxiliary_rd := RenderingServer.texture_get_rd_texture(batch["auxiliary_rid"])
	if substrate_rd == RID() or auxiliary_rd == RID():
		_resource_failure = "input_texture_unavailable"
		return false

	_uniform_sets["pack"] = _rendering_device.uniform_set_create([
		_sampler_uniform(0, substrate_rd),
		_sampler_uniform(1, auxiliary_rd),
		_image_uniform(2, _packed_texture),
	], _shaders["pack"], 0)
	_uniform_sets["halo_0"] = _rendering_device.uniform_set_create([
		_image_uniform(0, _packed_texture),
		_image_uniform(1, _halo_texture),
		_image_uniform(2, _halo_scratch_texture),
	], _shaders["halo"], 0)
	_uniform_sets["halo_1"] = _rendering_device.uniform_set_create([
		_image_uniform(0, _packed_texture),
		_image_uniform(1, _halo_scratch_texture),
		_image_uniform(2, _halo_texture),
	], _shaders["halo"], 0)
	for parity in 2:
		_uniform_sets["phase_%d" % parity] = _rendering_device.uniform_set_create([
			_image_uniform(0, _packed_texture),
			_image_uniform(1, _halo_texture),
			_image_uniform(2, _state_textures[parity]),
			_image_uniform(3, _state_textures[1 - parity]),
		], _shaders["phase"], 0)
		_uniform_sets["creep_%d" % parity] = _rendering_device.uniform_set_create([
			_image_uniform(0, _packed_texture),
			_image_uniform(1, _state_textures[parity]),
			_image_uniform(2, _state_textures[1 - parity]),
		], _shaders["creep"], 0)
		_uniform_sets["present_%d" % parity] = _rendering_device.uniform_set_create([
			_image_uniform(0, _packed_texture),
			_image_uniform(1, _state_textures[parity]),
			_image_uniform(2, _present_texture),
		], _shaders["present"], 0)
	return true


func _sampler_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(_sampler)
	uniform.add_id(texture)
	return uniform


func _image_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(texture)
	return uniform


func _free_uniform_sets() -> void:
	for key_variant in _uniform_sets.keys():
		var set_rid: RID = _uniform_sets[key_variant]
		if set_rid != RID() and _rendering_device.uniform_set_is_valid(set_rid):
			_rendering_device.free_rid(set_rid)
	_uniform_sets.clear()


func _release_gpu_resources() -> void:
	if _rendering_device == null:
		return
	_free_uniform_sets()
	for texture in _state_textures:
		if texture != RID():
			_rendering_device.free_rid(texture)
	_state_textures.clear()
	var owned: Array[RID] = [_packed_texture, _halo_scratch_texture, _halo_texture, _present_texture]
	for texture in owned:
		if texture != RID():
			_rendering_device.free_rid(texture)
	_packed_texture = RID()
	_halo_scratch_texture = RID()
	_halo_texture = RID()
	_present_texture = RID()
	if _present_texture_2d != null:
		_present_texture_2d.texture_rd_rid = RID()
	_resources_ready = false


func _release_resources() -> void:
	if _rendering_device == null:
		return
	_release_gpu_resources()
	for key_variant in _pipelines.keys():
		var pipeline: RID = _pipelines[key_variant]
		if pipeline != RID():
			_rendering_device.free_rid(pipeline)
	_pipelines.clear()
	for key_variant in _shaders.keys():
		var shader: RID = _shaders[key_variant]
		if shader != RID():
			_rendering_device.free_rid(shader)
	_shaders.clear()
	if _sampler != RID():
		_rendering_device.free_rid(_sampler)
		_sampler = RID()


@warning_ignore("integer_division")
func _seed_islands_on_render_thread() -> Dictionary:
	_readback_count += 1
	var packed_bytes := _rendering_device.texture_get_data(_packed_texture, 0)
	var state_bytes := _rendering_device.texture_get_data(_state_textures[_state_parity], 0)
	var width := _sim_size.x
	var height := _sim_size.y
	var expected_packed := width * height * 4
	if packed_bytes.size() < expected_packed:
		return {"ok": false, "reason": "packed_readback_short"}

	var minimum_area_texels := int(round(
		maxf(0.0, _float_config("minimum_island_area_cells", 0.25)) * pow(_pixels_per_cell(), 2.0)
	))
	var nucleus_radius := maxi(1, int(round(
		maxf(0.0, _float_config("island_seed_radius_cells", 0.15)) * _pixels_per_cell()
	)))

	var substrate := PackedByteArray()
	substrate.resize(width * height)
	var reachable := PackedByteArray()
	reachable.resize(width * height)
	var frontier: Array[int] = []
	for index in width * height:
		var offset := index * 4
		var permitted := packed_bytes[offset] > 127
		var blocked := packed_bytes[offset + 3] > 127
		var seeded := packed_bytes[offset + 1] > 127 or packed_bytes[offset + 2] > 127
		substrate[index] = 1 if (permitted and not blocked) else 0
		var claimed := false
		if state_bytes.size() >= (index + 1) * 8:
			# RGBA16F: the normal claim is component 2, the bypass claim is 3.
			claimed = _decode_half(state_bytes, index * 8 + 4) > 0.5 \
				or _decode_half(state_bytes, index * 8 + 6) > 0.5
		if substrate[index] == 1 and (seeded or claimed):
			reachable[index] = 1
			frontier.append(index)
	for nucleus: Vector2i in _pending_island_nuclei:
		var pending_index := nucleus.y * width + nucleus.x
		if pending_index >= 0 and pending_index < substrate.size() and substrate[pending_index] == 1 and reachable[pending_index] == 0:
			reachable[pending_index] = 1
			frontier.append(pending_index)

	_flood(substrate, reachable, frontier, width, height)

	var components := _collect_components(substrate, reachable, width, height, minimum_area_texels)
	var planted: Array[Vector2i] = []
	for component_variant: Variant in components:
		var component: Dictionary = component_variant
		planted.append(component["nucleus"] as Vector2i)
	if not planted.is_empty():
		_plant_nuclei(state_bytes, planted, nucleus_radius, width, height)
		_rendering_device.texture_update(_state_textures[_state_parity], 0, state_bytes)
	_pending_island_nuclei.assign(planted)
	return {
		"ok": true,
		"components_found": components.size(),
		"components_seeded": planted.size(),
		"minimum_area_texels": minimum_area_texels,
		"nucleus_radius_texels": nucleus_radius,
		"sim_size": _sim_size,
	}


static func _decode_half(bytes: PackedByteArray, offset: int) -> float:
	if offset + 1 >= bytes.size():
		return 0.0
	return bytes.decode_half(offset)


@warning_ignore("integer_division")
func _flood(
	substrate: PackedByteArray,
	reachable: PackedByteArray,
	frontier: Array[int],
	width: int,
	height: int
) -> void:
	while not frontier.is_empty():
		var index: int = frontier.pop_back()
		var x := index % width
		var y := index / width
		for offset in FOUR_CONNECTED:
			var nx := x + offset.x
			var ny := y + offset.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbour := ny * width + nx
			if substrate[neighbour] == 1 and reachable[neighbour] == 0:
				reachable[neighbour] = 1
				frontier.append(neighbour)


## Groups unreachable substrate into connected components, drops undersized
## ones, and picks a nucleus per survivor: the texel furthest from the component
## boundary (an interior maximum), falling back to the texel nearest the
## centroid when the component has no interior.
@warning_ignore("integer_division")
func _collect_components(
	substrate: PackedByteArray,
	reachable: PackedByteArray,
	width: int,
	height: int,
	minimum_area_texels: int
) -> Array:
	var visited := PackedByteArray()
	visited.resize(width * height)
	var components: Array = []
	for start in width * height:
		if substrate[start] == 0 or reachable[start] == 1 or visited[start] == 1:
			continue
		var members: Array[int] = []
		var stack: Array[int] = [start]
		visited[start] = 1
		while not stack.is_empty():
			var index: int = stack.pop_back()
			members.append(index)
			var x := index % width
			var y := index / width
			for offset in FOUR_CONNECTED:
				var nx := x + offset.x
				var ny := y + offset.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var neighbour := ny * width + nx
				if substrate[neighbour] == 1 and reachable[neighbour] == 0 and visited[neighbour] == 0:
					visited[neighbour] = 1
					stack.append(neighbour)
		if members.size() < maxi(1, minimum_area_texels):
			continue
		components.append({
			"area": members.size(),
			"nucleus": _pick_nucleus(members, substrate, width, height),
		})
	return components


@warning_ignore("integer_division")
func _pick_nucleus(members: Array[int], substrate: PackedByteArray, width: int, height: int) -> Vector2i:
	var centroid := Vector2.ZERO
	for index: int in members:
		centroid += Vector2(index % width, index / width)
	centroid /= float(members.size())
	var best_index: int = members[0]
	var best_depth := -1
	var best_centroid_distance := INF
	for index: int in members:
		var x := index % width
		var y := index / width
		var depth := 0
		while depth < 8:
			var radius := depth + 1
			var solid := true
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height or substrate[ny * width + nx] == 0:
						solid = false
						break
				if not solid:
					break
			if not solid:
				break
			depth = radius
		var centroid_distance := Vector2(x, y).distance_to(centroid)
		if depth > best_depth or (depth == best_depth and centroid_distance < best_centroid_distance):
			best_depth = depth
			best_centroid_distance = centroid_distance
			best_index = index
	return Vector2i(best_index % width, best_index / width)


func _plant_nuclei(
	state_bytes: PackedByteArray,
	nuclei: Array[Vector2i],
	radius: int,
	width: int,
	height: int
) -> void:
	for nucleus: Vector2i in nuclei:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius:
					continue
				var x := nucleus.x + dx
				var y := nucleus.y + dy
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				var offset := (y * width + x) * 8
				if offset + 8 > state_bytes.size():
					continue
				# Field red and normal claim blue both go fully claimed so the
				# nucleus is a propagation source on the very next creep step.
				state_bytes.encode_half(offset, 1.0)
				state_bytes.encode_half(offset + 4, 1.0)
