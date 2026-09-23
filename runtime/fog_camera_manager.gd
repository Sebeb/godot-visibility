extends Node
class_name FogCameraManager

signal fog_of_war_disabled_cheat_changed(enabled: bool)
signal fog_history_surface_updated(dirty_uv_rects: Array[Rect2])

enum WallFogMode { ON, DEBUG, OFF }

const CAMERA_TARGET_GROUP := "maze_camera_target"
const FOG_MANAGER_GROUP := "fog_camera_manager"
const FOG_BLOCKER_2D_GROUP := "fog_blocker_2d"
const FOG_OF_WAR_DISABLE_CHEAT_STATE_PATH := "cheats/fog_of_war_off"
const FOG_OF_WAR_RESET_COMMAND_PATH := "cheats/reset_fog_of_war"
const FORCE_ALL_DISCOVERED_STATE_PATH := "cheats/walls/force_all_discovered"
const WALLS_SET_ALL_DISCOVERED_COMMAND_PATH := "cheats/walls/set_all_discovered"
const WALLS_CLEAR_KNOWN_COMMAND_PATH := "cheats/walls/forget_all"
const ANIMATED_MASK_SEED_ISLANDS_COMMAND_PATH := "system/2d_rendering/animated_visibility_mask/seed_islands"
const ANIMATED_MASK_DEBUG_VIEW_COMMAND_PATH := "system/2d_rendering/animated_visibility_mask/debug_view"
const ANIMATED_MASK_SNAPSHOT_COMMAND_PATH := "system/2d_rendering/animated_visibility_mask/snapshot"
const CURRENT_VIEWPORT_NAME := "FogCurrentViewport"
const HISTORY_VIEWPORT_PREFIX := "FogSeenViewport"
const MERGE_RECT_NAME := "MergeRect"
const HISTORY_SHADER := preload("res://rendering/fog_history_merge.gdshader")
const FOG_MEMORY_DECAY_CONTROLLER_SCENE := preload("res://systems/maze/fog_memory_decay_controller.tscn")
const WORLD_MASK_3D_SHADER := preload("res://rendering/fog_world_mask_3d.gdshader")
const WORLD_MASK_2D_SHADER := preload("res://rendering/fog_world_mask_2d.gdshader")
const SPRITE_VISIBILITY_MASKED_SHADER := preload("res://rendering/sprite_visibility_masked.gdshader")
const OBJECT_ORIGIN_VISIBILITY_TINT_SHADER := preload("res://rendering/object_origin_visibility_tint.gdshader")
const PILL_PARTICLE_VISIBILITY_SHADER := preload("res://rendering/pill_particle_visibility.gdshader")
const PILL_BACK_GLOW_VISIBILITY_SHADER := preload("res://rendering/pill_back_glow_visibility.gdshader")
const MazeCellDiscovery2DScript := preload("res://systems/maze/maze_cell_discovery_2d.gd")
const MazeCellVisibility2DScript := preload("res://systems/maze/maze_cell_visibility_2d.gd")
const RenderMaskCompositorScript := preload("res://systems/maze/render_mask_compositor.gd")
const RenderMaskCompositionScript := preload("res://systems/maze/render_mask_composition.gd")
const OrganicVisibilityMaskSimulationScript := preload("res://systems/maze/organic_visibility_mask_simulation.gd")
const PackedVisibilityCaptureScript := preload("res://systems/maze/packed_visibility_capture.gd")
const WallMaskResamplerScript := preload("res://systems/maze/wall_mask_resampler.gd")
const SoundLightFieldSimulationScript := preload("res://systems/maze/sound_light_field_simulation.gd")
const SoundLightWallLaneCaptureScript := preload("res://systems/maze/sound_light_wall_lane_capture.gd")
const SoundLightEmitterSourceScript := preload("res://systems/maze/sound_light_emitter_source.gd")
const SOUND_LIGHT_WORLD_MASK_3D_SHADER := preload("res://rendering/sound_light_world_mask_3d.gdshader")
const SOUND_LIGHT_WORLD_MASK_2D_SHADER := preload("res://rendering/sound_light_world_mask_2d.gdshader")
const VIEW_DISTANCE_MASK_SHADER := preload("res://rendering/view_distance_mask.gdshader")
const CAMERA_ROOM_MASK_BLEND_SHADER := preload("res://rendering/camera_room_mask_blend.gdshader")
const WORLD_MASK_3D_NAME := "FogWorldMask3D"
const WORLD_MASK_2D_MAIN_NAME := "FogWorldMask2DMain"
const WORLD_MASK_2D_WALLS_NAME := "FogWorldMask2DWalls"
const SOUND_LIGHT_WORLD_MASK_3D_NAME := "SoundLightWorldMask3D"
const SOUND_LIGHT_WORLD_MASK_2D_MAIN_NAME := "SoundLightWorldMask2DMain"
const SOUND_LIGHT_WORLD_MASK_2D_WALLS_NAME := "SoundLightWorldMask2DWalls"
const WALL_KNOWLEDGE_2D_NAME := "MazeWallKnowledge2D"
const CELL_DISCOVERY_2D_NAME := "MazeCellDiscovery2D"
const CELL_VISIBILITY_2D_NAME := "MazeCellVisibility2D"
const _CONSOLE_STATE_GROUP_NAME := "state"
const _CONSOLE_STATE_GROUP_PRIORITY := -50
const _DEBUG_TEXTURE_WIDGET_MIN_SIZE := Vector2(220, 160)
const _RENDER_MASK_OBJECT_LAYER_ROOT_COMMAND_PATH := "system/2d_rendering/object_layers/debug/render_masks"
const _RENDER_MASK_ROOT_COMMAND_PATH := "system/2d_rendering/render_masks"
const SURFACE_CURRENT_VISIBILITY := &"current_visibility"
const SURFACE_FOG_OF_WAR := &"fog_of_war"
const SURFACE_VIEW_DISTANCE := &"view_distance"
const SURFACE_CAMERA_ROOMS := &"camera_rooms"
const FOG_CAPTURE_2D_ROOT_NAME := "FogCapture2DRoot"
const FOG_CAPTURE_2D_RECEIVER_NAME := "FogCapture2DReceiver"
## Dedicated 2D canvas light/occluder mask isolating the current-visibility
## capture graph so no unrelated 2D node (gameplay sprites, UI, debug layers)
## can receive or cast into the visibility surface. Reused by Phase 3/4's
## PointLight2D proxies and LightOccluder2D geometry. Applied via each
## CanvasItem's own `light_mask`/`visibility_layer` and each Light2D's
## `range_item_cull_mask`/`shadow_item_cull_mask` — deliberately NOT via
## `SubViewport.canvas_cull_mask`, which also silently suppresses every
## Light2D's contribution with no per-light override to compensate.
##
## Bit 0 (the `| 1`) is mandatory, not decorative: in this engine build
## (Godot 4.7 Forward+/Metal) 2D shadow-occluder culling only honours bit 0.
## A LightOccluder2D casts into a PointLight2D's shadow ONLY when bit 0 is set
## in both the occluder's `light_mask` and the light's `shadow_item_cull_mask`;
## any higher-bit-only mask (e.g. a bare `1 << 19`) still lights receivers
## correctly but silently casts no shadow, so occlusion has zero effect. The
## bit-19 layer is kept purely for authoring intent/isolation; bit 0 is what
## makes shadows actually render. Verified empirically: mask `1<<19` occludes=
## false, mask `(1<<19)|1` occludes=true. See PGO-97 / PTK-506/507 report.
const FOG_CAPTURE_2D_LIGHT_MASK := (1 << 19) | 1
## Square resolution of the generated reveal-source falloff textures.
const FOG_CAPTURE_2D_OCCLUDER_ROOT_NAME := "FogCapture2DOccluders"
## The 3D wall material (rendering/maze_walls_visibility.gdshader) lights a
## wall fragment by sampling this current-visibility capture at that
## fragment's own world position. A fog/vision occluder built at the full
## visual wall_thickness sits exactly on the wall's own visible near face, so
## the vision-cone shadow can clip that face and render it black. 2D light
## occlusion is edge-based, not volumetric, so a thinner occluder still fully
## blocks light reaching past the wall; shrinking it just pulls its edges
## back inside the visible wall so the wall's own surface stays lit.
const _OCCLUDER_THICKNESS_RATIO := 0.5
const _DYNAMIC_SEGMENT_PROVIDER_GROUP := "maze_render_segment_2d_provider"
const _RENDER_MASK_CAPTURED_NAMES: Array[StringName] = [&"fog_of_war", &"current_visibility", &"view_distance", &"camera_rooms"]
## The two derived masks carry the captured `game_world` composite -- raw and
## simulated -- to distinct presentation boundaries. `game_world` masks the
## captured in-game render texture; 3D world materials resolve only
## `game_world_animated`. See `_render_mask_texture` and `SharedStateKeys`.
const _RENDER_MASK_DERIVED_NAMES: Array[StringName] = [&"game_world", &"game_world_animated"]
const _RENDER_MASK_NAMES: Array[StringName] = [
	&"fog_of_war", &"current_visibility", &"view_distance", &"camera_rooms", &"game_world", &"game_world_animated"
]
## The three PGO-239 render layers plus the captured `game_world` substrate,
## which is special-cased below rather than being a render layer.
const _RENDER_MASK_TARGETS: Array[StringName] = [&"game_floor", &"game_walls", &"map", &"game_world"]
## `mask_0..mask_3` in `render_mask_composition.gdshader`.
const _RENDER_MASK_COMPOSITOR_SLOTS := 4
const _RENDER_MASK_PIXELS_PER_CEL_MIN := 1
const _RENDER_MASK_PIXELS_PER_CEL_MAX := 128
const _SURFACE_CONSUMER_WORLD_MASK := "__world_mask__"
const _SURFACE_CONSUMER_HISTORY_PIPELINE := "__history_pipeline__"
const _SURFACE_CONSUMER_DEBUG_READ := "__debug_read__"
const _DEBUG_SURFACE_CONSUMER_TTL_FRAMES := 2

# Sets the fallback render-texture resolution, in pixels per maze cel, used by every render mask
# whose own `system/2d_rendering/render_masks/<mask>/pixels_per_cel` state is left at zero.
@export_range(1, 128, 1) var capture_resolution_per_grid_square := 24
# Enables or disables mask 3d world with current visibility.
@export var mask_3d_world_with_current_visibility := true
# Sets the wall fog mode used by this component.
@export var wall_fog_mode: WallFogMode = WallFogMode.ON
# Sets the wall discovery delay frames used by this component.
@export_range(0, 8, 1) var wall_discovery_delay_frames := 2
# Sets the wall reveal speed used by this component.
@export_range(0.1, 32.0, 0.1) var wall_reveal_speed := 8.0
# Sets the wall debug unknown opacity used by this component.
@export_range(0.0, 1.0, 0.01) var wall_debug_unknown_alpha := 0.2
# Sets the tile grid resolution used to publish fog history dirty regions.
@export_range(1, 64, 1) var history_dirty_tile_resolution := 8
# Sets the fog history value at or above which a sample counts as unmasked.
@export_range(0.0, 1.0, 0.01) var cell_unmask_cutoff := 0.25
# Sets the unmasked area fraction of a cell that marks it discovered.
@export_range(0.0, 1.0, 0.01) var cell_discover_threshold := 0.35
# Sets the unmasked area fraction below which a discovered cell is forgotten.
@export_range(0.0, 1.0, 0.01) var cell_forget_threshold := 0.25
# Sets the minimum interval between whole-grid cell discovery readbacks in seconds.
@export_range(0.0, 1.0, 0.01) var cell_discovery_cadence_seconds := 0.05
# Sets the square GPU tap grid sampled inside each cell.
@export_range(1, 8, 1) var cell_discovery_tap_grid_size := 8
# Sets how far cell sampling is inset from the cell edges, as a fraction of cell size.
@export_range(0.0, 0.45, 0.01) var cell_discovery_interior_inset := 0.0
# Enables or disables mask 3d opacity.
@export_range(0.0, 1.0, 0.01) var mask_3d_opacity := 1.0
# Enables or disables mask 2d opacity.
@export_range(0.0, 1.0, 0.01) var mask_2d_opacity := 1.0

var _maze_data: Variant = null
var _builder_settings: MazeBuilderSettings = null

var _current_viewport: SubViewport = null
var _capture_background_2d: ColorRect = null
var _capture_root_2d: Node2D = null
var _capture_receiver_2d: ColorRect = null
## Explicit capture rectangle owned by the 2D backend (Decision 3), in maze-local
## XZ and padded half a wall thickness outside the cell grid on every edge. Sole
## authority for `_current_visibility_maze_rect()`.
var _capture_rect_2d := Rect2(Vector2.ZERO, Vector2.ONE)
var _history_viewports: Array[SubViewport] = []
var _history_rects: Array[ColorRect] = []
var _history_materials: Array[ShaderMaterial] = []
var _history_present_index := 0
var _history_initialized := false
var _black_texture: Texture2D = null
var _white_texture: Texture2D = null

var _world_mask_3d: MeshInstance3D = null
var _world_mask_3d_material: ShaderMaterial = null
var _source_floor_visibility_material: ShaderMaterial = null
var _source_walls_visibility_material: ShaderMaterial = null
var _source_sprite_visibility_materials: Dictionary = {}
var _source_origin_visibility_materials: Dictionary = {}
var _world_mask_2d_main: Sprite2D = null
var _world_mask_2d_main_material: ShaderMaterial = null
var _world_mask_2d_walls: Sprite2D = null
var _world_mask_2d_walls_material: ShaderMaterial = null
var _render_mask_compositor: Node = null
var _bound_two_d_world_renderer: TwoDWorldRenderer = null
var _render_mask_modes: Dictionary = {}
var _render_mask_pixels_per_cel: Dictionary = {}
var _render_mask_outputs_dirty := true
var _render_mask_texture_revisions: Dictionary = {}
## Targets already warned about exceeding `_RENDER_MASK_COMPOSITOR_SLOTS`.
var _over_subscribed_mask_targets: Dictionary = {}
## Monotonic revision published for the `game_world_animated` derived mask, and the
## resolved source it was last derived from. See `_refresh_derived_mask_revisions`.
var _animated_mask_revision := 0
var _animated_mask_source_key := ""
var _registered_render_mask_texture_widgets: Array[String] = []
var _game_world_mask_texture: Texture2D = null
var _game_world_mask_revision := 0
var _visibility_mask_simulation: OrganicVisibilityMaskSimulation = null
var _packed_visibility_capture: PackedVisibilityCapture = null
var _wall_mask_resampler: WallMaskResampler = null
var _animated_visibility_mask_enabled := false
## Live values of every `animated_visibility_mask/**` state variable, keyed by
## leaf. Handed to the simulation owner whole so a changed control updates the
## running simulation without reconstructing unrelated rendering state.
var _animated_visibility_mask_config: Dictionary = {}
var _animated_mask_debug_view := false
## PGO-323 PTK-890. `_sound_light_wall_lane_capture` is a plain `RefCounted`
## CPU rasteriser (see its own header), not a scene node, so it needs no
## add_child/queue_free lifecycle of its own -- only `_sound_light_field_simulation`
## (the GPU owner) does.
var _sound_light_field_simulation: SoundLightFieldSimulation = null
var _sound_light_wall_lane_capture: SoundLightWallLaneCapture = null
var _sound_light_enabled := false
## Live values of every `sound_light/**` state variable this manager forwards
## to `SoundLightFieldSimulation.configure()`, keyed by leaf -- same discipline
## as `_animated_visibility_mask_config`.
var _sound_light_config: Dictionary = {}
var _sound_light_world_mask_3d: MeshInstance3D = null
var _sound_light_world_mask_3d_material: ShaderMaterial = null
var _sound_light_world_mask_2d_main: Sprite2D = null
var _sound_light_world_mask_2d_main_material: ShaderMaterial = null
var _sound_light_world_mask_2d_walls: Sprite2D = null
var _sound_light_world_mask_2d_walls_material: ShaderMaterial = null
## `SoundLightEmitterSource` is a sibling under `MazeMain`, not a child of this
## manager, so it is resolved (lazily, via `EMITTER_SOURCE_GROUP`) rather than
## owned. A maze with no such node degrades to zero emitters, never an error.
var _sound_light_emitter_source: Node = null
var _view_distance_viewport: SubViewport = null
var _view_distance_material: ShaderMaterial = null
var _view_distance_mask_valid := false
var _view_distance_mask_dirty := true
var _view_distance_mask_rebuild_count := 0
var _vignette_border_cells := 2.0
var _vignette_fade_steepness := 1.5
var _vignette_corner_steepness := 8.0
var _camera_room_composite_viewport: SubViewport = null
var _camera_room_composite_material: ShaderMaterial = null
var _camera_room_composite_valid := false
var _camera_room_composite_dirty := true
var _camera_room_composite_rebuild_count := 0
var _camera_room_mask_enabled := false
var _camera_room_defs: Array = []
var _camera_room_masks_by_id: Dictionary = {}
var _camera_room_defs_signature := ""
var _camera_room_mask_viewport_size := Vector2i.ZERO
var _camera_room_active_id := -1
var _camera_room_transition_from_tex: Texture2D = null
var _camera_room_transition_to_tex: Texture2D = null
var _camera_room_mask_blend := 1.0
var _camera_room_mask_tween: Tween = null
var _camera_room_mask_rebuild_count := 0
var _camera_room_mask_texture_build_count := 0

var _wall_knowledge_2d: MazeWallKnowledge2D = null
var _cell_discovery_2d: MazeCellDiscovery2D = null
var _cell_visibility_2d: Node = null
var _fog_of_war_disabled_cheat_enabled := false
var _force_all_discovered := false
var _surface_states: Dictionary = {}
var _debug_surface_read_frames: Dictionary = {}
var _pending_history_dirty_uv_rects: Array[Rect2] = []
var _history_reset_pending_full_dirty := false
var _revealer_registry_traversal_count := 0
var _history_dirty_publication_count := 0
var _history_dirty_published_region_count := 0
var _history_dirty_published_area := 0.0
# PGO-157 age-ordered forgetting. The recency gradient in the history texture's
# green channel is renormalized by i / (i + 1) each pass, so the frontier that
# walks through it must be renormalized identically to stay aligned.
var _history_recency_steps := 0
var _forget_threshold := 0.0
var _decay_history_pass_pending := false
var _decay_gpu_pass_count := 0
var _decay_uploaded_contribution_count := 0
var _decay_uploaded_batch_count := 0
# This manager never calls Texture2D.get_image(); PGO-40 owns only its compact
# candidate-atlas readback and is instrumented separately.
var _full_texture_readback_count := 0
var _source_maze_mesh: MeshInstance3D = null
var _source_floor_mesh: MeshInstance3D = null
var _maze_root: Node3D = null
var _source_maze_global_transform := Transform3D.IDENTITY
var _source_maze_transform_known := false
var _source_refs_dirty := true
var _capture_geometry_dirty := true
var _capture_camera_dirty := true
var _wall_knowledge_settings_dirty := true
var _mask_overlays_dirty := true
var _mask_textures_dirty := true
var _visibility_material_bindings_dirty := true
var _visibility_material_params_dirty := true
var _source_sprite_cache_dirty := true
var _source_origin_material_cache_dirty := true
var _reveal_sources: Dictionary = {}
var _occluder_root_2d: Node2D = null
## Component-owned static geometry. FogCameraManager only provides the isolated
## capture canvas and invalidates its demand-driven surface; it never builds a
## wall occluder proxy.
var _fog_blockers: Dictionary = {}
## Dynamic (sliding-door and similar) occluders, keyed by
## "<provider_instance_id>:<segment_index>".
var _dynamic_wall_occluders: Dictionary = {}
## Last-seen get_maze_render_segments_2d_revision() per provider instance id.
## Providers notify this manager when their geometry changes; membership is
## refreshed only after a scene-tree change, never as idle-frame polling.
var _dynamic_occluder_provider_revisions: Dictionary = {}
var _dynamic_occluder_provider_nodes: Dictionary = {}
var _dynamic_occluder_membership_dirty := true
var _dynamic_occluder_registry_scan_count := 0
var _dynamic_occluder_rebuild_count := 0
var _static_occluder_rebuild_count := 0
var _dynamic_occluder_changed_segment_count := 0
var _static_occluder_changed_segment_count := 0
var _source_capture_light_update_count := 0
var _current_surface_redraw_count := 0
var _capture_viewport_revision := 0
var _memory_decay_controller: FogMemoryDecayController = null
var _source_sprite_nodes: Array[AnimatedSprite3D] = []
var _source_sprite_signatures: Dictionary = {}
var _source_visibility_material_refresh_count := 0
var _source_visibility_material_update_count := 0


func _ready() -> void:
	add_to_group(FOG_MANAGER_GROUP)
	_register_existing_fog_blockers()
	_bind_state_variables()
	_ensure_runtime_nodes()
	if get_tree() != null:
		if not get_tree().node_added.is_connected(_on_scene_tree_node_added):
			get_tree().node_added.connect(_on_scene_tree_node_added)
		if not get_tree().node_removed.is_connected(_on_scene_tree_node_removed):
			get_tree().node_removed.connect(_on_scene_tree_node_removed)
	_mark_full_refresh_needed(&"ready")
	_register_console_bindings()
	set_process(true)


## Covers the lifecycle ordering where a blocker enters the tree just before
## this manager joins its group. This is a one-time group lookup at manager
## readiness, never an idle-frame topology scan.
func _register_existing_fog_blockers() -> void:
	if get_tree() == null:
		return
	for blocker in get_tree().get_nodes_in_group(FOG_BLOCKER_2D_GROUP):
		register_fog_blocker(blocker as Node)


func _exit_tree() -> void:
	set_process(false)
	if get_tree() != null:
		if get_tree().node_added.is_connected(_on_scene_tree_node_added):
			get_tree().node_added.disconnect(_on_scene_tree_node_added)
		if get_tree().node_removed.is_connected(_on_scene_tree_node_removed):
			get_tree().node_removed.disconnect(_on_scene_tree_node_removed)
	if _camera_room_mask_tween != null and _camera_room_mask_tween.is_running():
		_camera_room_mask_tween.kill()
	_camera_room_mask_tween = null
	_apply_fog_of_war_disabled_cheat(false)
	_bind_two_d_world_renderer(null)
	_unregister_console_bindings()
	_disconnect_reveal_sources()
	_disconnect_memory_decay_controller()
	remove_from_group(FOG_MANAGER_GROUP)
	_release_runtime_render_resources()


func _release_runtime_render_resources() -> void:
	if _cell_discovery_2d != null and is_instance_valid(_cell_discovery_2d):
		_cell_discovery_2d.queue_free()
	if _current_viewport != null and is_instance_valid(_current_viewport):
		_current_viewport.world_3d = null
	for history_viewport in _history_viewports:
		if history_viewport != null and is_instance_valid(history_viewport):
			history_viewport.world_3d = null
	if _world_mask_3d != null and is_instance_valid(_world_mask_3d):
		_world_mask_3d.material_override = null
	if _wall_knowledge_2d != null and is_instance_valid(_wall_knowledge_2d):
		_wall_knowledge_2d.queue_free()
	_world_mask_3d = null
	_current_viewport = null
	_capture_background_2d = null
	_capture_root_2d = null
	_capture_receiver_2d = null
	_occluder_root_2d = null
	_fog_blockers.clear()
	_dynamic_wall_occluders.clear()
	_dynamic_occluder_provider_revisions.clear()
	_history_viewports.clear()
	_history_rects.clear()
	_history_materials.clear()
	_surface_states.clear()
	_debug_surface_read_frames.clear()
	_source_sprite_nodes.clear()
	_source_sprite_signatures.clear()
	_source_sprite_visibility_materials.clear()
	_source_origin_visibility_materials.clear()
	_reveal_sources.clear()
	_memory_decay_controller = null
	_camera_room_masks_by_id.clear()
	_camera_room_defs.clear()
	_camera_room_transition_from_tex = null
	_camera_room_transition_to_tex = null
	_source_maze_mesh = null
	_source_floor_mesh = null
	_maze_root = null
	_source_floor_visibility_material = null
	_source_walls_visibility_material = null
	_world_mask_3d_material = null
	_world_mask_2d_main_material = null
	_world_mask_2d_walls_material = null
	_world_mask_2d_main = null
	_world_mask_2d_walls = null
	if _render_mask_compositor != null and is_instance_valid(_render_mask_compositor):
		_render_mask_compositor.clear()
		_render_mask_compositor.queue_free()
	_render_mask_compositor = null
	_render_mask_modes.clear()
	_render_mask_texture_revisions.clear()
	_over_subscribed_mask_targets.clear()
	_animated_mask_revision = 0
	_animated_mask_source_key = ""
	_game_world_mask_texture = null
	_game_world_mask_revision = 0
	if _visibility_mask_simulation != null and is_instance_valid(_visibility_mask_simulation):
		_visibility_mask_simulation.queue_free()
	_visibility_mask_simulation = null
	if _packed_visibility_capture != null and is_instance_valid(_packed_visibility_capture):
		_packed_visibility_capture.queue_free()
	_packed_visibility_capture = null
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		_sound_light_field_simulation.queue_free()
	_sound_light_field_simulation = null
	_sound_light_wall_lane_capture = null
	if _sound_light_world_mask_3d != null and is_instance_valid(_sound_light_world_mask_3d):
		_sound_light_world_mask_3d.queue_free()
	_sound_light_world_mask_3d = null
	_sound_light_world_mask_3d_material = null
	if _sound_light_world_mask_2d_main != null and is_instance_valid(_sound_light_world_mask_2d_main):
		_sound_light_world_mask_2d_main.queue_free()
	_sound_light_world_mask_2d_main = null
	_sound_light_world_mask_2d_main_material = null
	if _sound_light_world_mask_2d_walls != null and is_instance_valid(_sound_light_world_mask_2d_walls):
		_sound_light_world_mask_2d_walls.queue_free()
	_sound_light_world_mask_2d_walls = null
	_sound_light_world_mask_2d_walls_material = null
	_sound_light_emitter_source = null
	if _wall_mask_resampler != null and is_instance_valid(_wall_mask_resampler):
		_wall_mask_resampler.queue_free()
	_wall_mask_resampler = null
	_view_distance_viewport = null
	_view_distance_material = null
	_view_distance_mask_valid = false
	_view_distance_mask_dirty = true
	_camera_room_composite_viewport = null
	_camera_room_composite_material = null
	_camera_room_composite_valid = false
	_camera_room_composite_dirty = true
	_black_texture = null
	_white_texture = null
	_wall_knowledge_2d = null
	_cell_discovery_2d = null
	_cell_visibility_2d = null


func _process(delta: float) -> void:
	if _maze_data == null or _builder_settings == null:
		return
	if not _runtime_nodes_are_valid():
		_ensure_runtime_nodes()
	_bind_two_d_world_renderer(_get_two_d_world_renderer())
	_ensure_source_references()
	_sync_maze_transform_if_changed()
	_sync_wall_knowledge_settings_if_needed()
	_sync_capture_geometry_if_needed()
	_refresh_capture_layout_if_needed()
	_refresh_dynamic_occluders_if_needed()
	_refresh_source_visibility_materials_if_needed()
	var current_refresh_requested := _schedule_surface_update(SURFACE_CURRENT_VISIBILITY)
	if current_refresh_requested and not _pending_history_dirty_uv_rects.is_empty():
		_invalidate_surface(SURFACE_FOG_OF_WAR, &"current_visibility_changed")
	var history_refresh_requested := _schedule_surface_update(SURFACE_FOG_OF_WAR)
	if history_refresh_requested:
		_mark_visibility_materials_dirty(&"history_surface_refresh")
	_mark_debug_surface_consumers_stale()
	_update_view_distance_mask_if_needed()
	_update_camera_room_composite_if_needed()
	# Composes the substrate, ticks the simulation, then composes the render
	# layers -- in that order. See the ordering contract on the function.
	_update_render_mask_outputs_if_needed(delta)
	_update_source_visibility_materials_if_needed()
	_sync_mask_overlays_if_needed()
	_update_mask_textures_if_needed()
	_sync_render_mask_object_layers()


func _bind_state_variables() -> void:
	_connect_state_variable(FOG_OF_WAR_DISABLE_CHEAT_STATE_PATH, _on_fog_of_war_off_changed)
	_connect_state_variable(FORCE_ALL_DISCOVERED_STATE_PATH, _on_force_all_discovered_changed)
	for leaf_variant in SharedStateKeys.ANIMATED_VISIBILITY_MASK_CONFIG_LEAVES:
		var leaf := String(leaf_variant)
		_connect_state_variable(
			"%s/%s" % [SharedStateKeys.ANIMATED_VISIBILITY_MASK_ROOT, leaf],
			Callable(self, "_on_animated_visibility_mask_config_changed").bind(leaf)
		)
	# `SoundLightEmitterSource` binds its OWN subset of `SOUND_LIGHT_CONFIG_LEAVES`
	# directly (player-emission/observer-side leaves); this manager only needs the
	# subset `SoundLightFieldSimulation.configure()` reads, but rebinding the whole
	# shared leaf array is harmless -- unread keys are simply ignored -- and keeps
	# this loop a literal mirror of the mask's own, single source of bind order.
	for leaf_variant in SharedStateKeys.SOUND_LIGHT_CONFIG_LEAVES:
		var leaf := String(leaf_variant)
		_connect_state_variable(
			"%s/%s" % [SharedStateKeys.SOUND_LIGHT_ROOT, leaf],
			Callable(self, "_on_sound_light_config_changed").bind(leaf)
		)
	_connect_state_variable(SharedStateKeys.SYSTEM_RENDERING_VIGNETTE_BORDER, _on_vignette_border_changed)
	_connect_state_variable(SharedStateKeys.SYSTEM_RENDERING_VIGNETTE_FADE_STEEPNESS, _on_vignette_fade_steepness_changed)
	_connect_state_variable(SharedStateKeys.SYSTEM_RENDERING_VIGNETTE_CORNER_STEEPNESS, _on_vignette_corner_steepness_changed)
	_connect_state_variable(SharedStateKeys.GAMEPLAY_CONFIG_FOG_CELL_UNMASK_CUTOFF, _on_cell_unmask_cutoff_changed)
	_connect_state_variable(SharedStateKeys.GAMEPLAY_CONFIG_FOG_CELL_DISCOVER_THRESHOLD, _on_cell_discover_threshold_changed)
	_connect_state_variable(SharedStateKeys.GAMEPLAY_CONFIG_FOG_CELL_FORGET_THRESHOLD, _on_cell_forget_threshold_changed)
	for mask_name in _RENDER_MASK_NAMES:
		# A derived mask has no capture surface to resize, so it has no
		# pixels-per-cel variable to bind. `game_world` inherits the capture
		# viewport; `game_world_animated`'s density is `simulation_pixels_per_cell`.
		if not _RENDER_MASK_DERIVED_NAMES.has(mask_name):
			_connect_state_variable(
				SharedStateKeys.render_mask_pixels_per_cel_path(String(mask_name)),
				Callable(self, "_on_render_mask_pixels_per_cel_changed").bind(mask_name)
			)
		for target in _RENDER_MASK_TARGETS:
			_connect_state_variable(
				SharedStateKeys.render_mask_path(String(mask_name), String(target)),
				_on_render_mask_mode_changed
			)


func _connect_state_variable(path: String, callback: Callable) -> void:
	var variable := StateStore.get_variable(path)
	if variable == null:
		return
	if not variable.resolved_value_changed.is_connected(callback):
		variable.resolved_value_changed.connect(callback)
	callback.call(variable.get_path(), null, variable.resolved_value)


func _on_render_mask_mode_changed(variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_render_mask_modes[String(variable_path)] = String(new_value).strip_edges().to_lower()
	_render_mask_outputs_dirty = true
	_invalidate_camera_room_composite()
	if is_inside_tree():
		_sync_surface_consumers()


## One handler for all fifteen controls. Each writes its own leaf and hands the
## whole configuration back to the simulation owner, which decides on its own
## which changes are structural. No control reaches past the presentation
## boundary, so none of them can dirty the capture, history or discovery graphs.
func _on_animated_visibility_mask_config_changed(
	_variable_path: StringName,
	_old_value: Variant,
	new_value: Variant,
	leaf: String
) -> void:
	_animated_visibility_mask_config[leaf] = new_value
	if leaf == "enabled":
		_animated_visibility_mask_enabled = bool(new_value)
		if _animated_visibility_mask_enabled and is_inside_tree():
			_ensure_visibility_mask_simulation()
		elif not _animated_visibility_mask_enabled:
			# Disabled is an exact presentation bypass, and that has to include
			# the resources: toggling the feature off releases the compute
			# owner and its auxiliary capture rather than leaving a dormant
			# RenderingDevice allocation and a SubViewport behind. The derived
			# `game_world_animated` mask falls back to the raw substrate, so any
			# layer routed to it keeps its fog across the toggle.
			_release_visibility_mask_simulation()
			_render_mask_outputs_dirty = true
	if _visibility_mask_simulation != null and is_instance_valid(_visibility_mask_simulation):
		_visibility_mask_simulation.configure(_animated_visibility_mask_config)
	_visibility_material_params_dirty = true


## Structural twin of `_on_animated_visibility_mask_config_changed` for the
## `sound_light/**` leaves `SoundLightFieldSimulation.configure()` reads. Leaves
## outside that subset (e.g. `player_emits`) are still written into
## `_sound_light_config` for completeness but are inert here -- they're read by
## `SoundLightEmitterSource`'s own binding instead.
func _on_sound_light_config_changed(
	_variable_path: StringName,
	_old_value: Variant,
	new_value: Variant,
	leaf: String
) -> void:
	_sound_light_config[leaf] = new_value
	if leaf == "enabled":
		_sound_light_enabled = bool(new_value)
		if _sound_light_enabled and is_inside_tree():
			_ensure_sound_light_field_simulation()
		elif not _sound_light_enabled:
			_release_sound_light_field_simulation()
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		_sound_light_field_simulation.configure(_sound_light_config)
	_mask_textures_dirty = true


func _on_cell_unmask_cutoff_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	cell_unmask_cutoff = clampf(float(new_value), 0.0, 1.0)
	_wall_knowledge_settings_dirty = true


func _on_cell_discover_threshold_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	cell_discover_threshold = clampf(float(new_value), 0.0, 1.0)
	_wall_knowledge_settings_dirty = true


func _on_cell_forget_threshold_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	cell_forget_threshold = clampf(float(new_value), 0.0, 1.0)
	_wall_knowledge_settings_dirty = true


func _on_vignette_border_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_vignette_border_cells = maxf(0.0, float(new_value))
	_invalidate_view_distance_mask()


func _on_vignette_fade_steepness_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_vignette_fade_steepness = maxf(0.01, float(new_value))
	_invalidate_view_distance_mask()


func _on_vignette_corner_steepness_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_vignette_corner_steepness = maxf(2.0, float(new_value))
	_invalidate_view_distance_mask()


func _on_render_mask_pixels_per_cel_changed(
	_variable_path: StringName,
	_old_value: Variant,
	new_value: Variant,
	mask_name: StringName
) -> void:
	var requested := int(new_value)
	if int(_render_mask_pixels_per_cel.get(mask_name, 0)) == requested:
		return
	_render_mask_pixels_per_cel[mask_name] = requested
	_apply_render_mask_capture_resolution(mask_name)


## Resolves a render mask's capture resolution in render-texture pixels per maze cel. A
## non-positive state value inherits the manager's `capture_resolution_per_grid_square`.
func get_render_mask_pixels_per_cel(mask_name: StringName) -> int:
	var pixels_per_cel := int(_render_mask_pixels_per_cel.get(mask_name, 0))
	if pixels_per_cel <= 0:
		pixels_per_cel = capture_resolution_per_grid_square
	return clampi(pixels_per_cel, _RENDER_MASK_PIXELS_PER_CEL_MIN, _RENDER_MASK_PIXELS_PER_CEL_MAX)


## Resolves a render mask's capture size in pixels. Without maze data there is no cel grid to
## scale, so producers fall back to the shared capture viewport's current size.
func _render_mask_capture_size(mask_name: StringName) -> Vector2i:
	if _maze_data == null:
		return _current_viewport.size if _current_viewport != null else Vector2i.ZERO
	var pixels_per_cel := get_render_mask_pixels_per_cel(mask_name)
	if mask_name == SURFACE_CURRENT_VISIBILITY or mask_name == SURFACE_FOG_OF_WAR:
		var cell_size := _builder_settings.cell_size if _builder_settings != null else 1.0
		var capture_rect := _wall_inclusive_maze_rect()
		return Vector2i(
			maxi(1, ceili(capture_rect.size.x / cell_size * pixels_per_cel)),
			maxi(1, ceili(capture_rect.size.y / cell_size * pixels_per_cel))
		)
	return Vector2i(
		maxi(1, int(_maze_data.width) * pixels_per_cel),
		maxi(1, int(_maze_data.height) * pixels_per_cel)
	)


## Re-sizes only the producer owned by the mask whose resolution changed. Fog-of-war and
## current-visibility share the capture pass, so either one re-runs the shared resize.
func _apply_render_mask_capture_resolution(mask_name: StringName) -> void:
	if _maze_data == null:
		return
	match mask_name:
		SURFACE_CURRENT_VISIBILITY, SURFACE_FOG_OF_WAR:
			var previous_history_size := _history_viewports[0].size if not _history_viewports.is_empty() else Vector2i.ZERO
			_resize_capture_targets()
			var history_size := _history_viewports[0].size if not _history_viewports.is_empty() else Vector2i.ZERO
			# A resized SubViewport loses its contents, so accumulated history cannot survive it.
			if history_size != previous_history_size:
				_reset_history()
		SURFACE_VIEW_DISTANCE:
			_invalidate_view_distance_mask()
		SURFACE_CAMERA_ROOMS:
			_rebuild_camera_room_masks(_camera_room_defs)
	_bump_render_mask_texture_revision(mask_name)


func _bump_render_mask_texture_revision(mask_name: StringName) -> void:
	_render_mask_texture_revisions[mask_name] = int(_render_mask_texture_revisions.get(mask_name, 0)) + 1
	_render_mask_outputs_dirty = true


func set_maze(data: Variant, builder_settings: MazeBuilderSettings) -> void:
	_apply_maze_state(data, builder_settings, true, false)


func refresh_runtime_maze(
	data: Variant,
	builder_settings: MazeBuilderSettings,
	preserve_history: bool = true,
	preserve_wall_state: bool = true
) -> void:
	_apply_maze_state(data, builder_settings, not preserve_history, preserve_wall_state)


func _apply_maze_state(
	data: Variant,
	builder_settings: MazeBuilderSettings,
	reset_history: bool,
	preserve_wall_state: bool
) -> void:
	_maze_data = data
	_builder_settings = builder_settings
	_sync_all_source_maze_cell_sizes()
	_ensure_runtime_nodes()
	var previous_capture_size := _current_viewport.size if _current_viewport != null else Vector2i.ZERO
	_resize_capture_targets()
	var capture_size_changed := _current_viewport != null and _current_viewport.size != previous_capture_size
	if reset_history or capture_size_changed:
		_reset_history()
	else:
		# A topology-preserving refresh keeps the same history authority but forces
		# PGO-40 to reconsider its compact watch candidates after UV remapping.
		_history_reset_pending_full_dirty = true
		_invalidate_surface(SURFACE_FOG_OF_WAR, &"topology_refresh")
	if _wall_knowledge_2d != null:
		_wall_knowledge_2d.set_maze(
			data,
			builder_settings,
			_get_main_maze_view(),
			_get_gameplay_wall_maze_view(),
			preserve_wall_state
		)
		_configure_cell_discovery()
	_mark_full_refresh_needed(&"maze_state")
	_sync_surface_consumers()
	# A same-layout preserving refresh (e.g. wall destruction) is an input revision,
	# not a simulation lifecycle boundary: only reseed when history/wall state was
	# actually reset or the capture itself was resized out from under the simulation.
	if reset_history or capture_size_changed:
		seed_animated_visibility_mask(true)


func set_camera_room_state(enabled: bool, camera_rooms: Array, active_room_id: int) -> void:
	var next_signature := _camera_room_defs_signature_for(camera_rooms)
	var viewport_size := _render_mask_capture_size(SURFACE_CAMERA_ROOMS)
	var needs_mask_rebuild := (
		next_signature != _camera_room_defs_signature
		or viewport_size != _camera_room_mask_viewport_size
	)
	if enabled == _camera_room_mask_enabled \
	and active_room_id == _camera_room_active_id \
	and not needs_mask_rebuild:
		return
	if _camera_room_mask_tween != null and _camera_room_mask_tween.is_running():
		_camera_room_mask_tween.kill()
	_camera_room_mask_enabled = enabled
	_camera_room_defs = camera_rooms.duplicate(true)
	_camera_room_active_id = active_room_id
	_wall_knowledge_settings_dirty = true
	if needs_mask_rebuild:
		_rebuild_camera_room_masks(_camera_room_defs)
	var active_tex := _camera_room_mask_texture_for_id(active_room_id)
	_camera_room_transition_from_tex = active_tex
	_camera_room_transition_to_tex = active_tex
	_camera_room_mask_blend = 1.0
	_mark_visibility_materials_dirty(&"camera_room_state")
	_mask_textures_dirty = true
	_render_mask_outputs_dirty = true
	_invalidate_camera_room_composite()


func begin_camera_room_transition(from_room_id: int, to_room_id: int, duration_sec: float) -> void:
	if _camera_room_mask_tween != null and _camera_room_mask_tween.is_running():
		_camera_room_mask_tween.kill()
	_camera_room_transition_from_tex = _camera_room_mask_texture_for_id(from_room_id)
	_camera_room_transition_to_tex = _camera_room_mask_texture_for_id(to_room_id)
	_camera_room_mask_blend = 0.0
	_camera_room_mask_tween = create_tween()
	_camera_room_mask_tween.set_ignore_time_scale(true)
	_camera_room_mask_tween.set_trans(Tween.TRANS_SINE)
	_camera_room_mask_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_room_mask_tween.tween_method(
		_set_camera_room_mask_blend,
		0.0,
		1.0,
		maxf(0.01, duration_sec)
	)
	_mark_visibility_materials_dirty(&"camera_room_transition_started")
	_invalidate_camera_room_composite()


func finish_camera_room_transition(active_room_id: int) -> void:
	if active_room_id != _camera_room_active_id:
		# This write pre-empts set_camera_room_state()'s no-op guard, which the
		# caller invokes immediately afterward to push the same room id — so the
		# wall-discovery sync must be forced here or it never fires, leaving
		# MazeWallKnowledge2D gating discovery on the stale room indefinitely.
		_wall_knowledge_settings_dirty = true
	_camera_room_active_id = active_room_id
	var active_tex := _camera_room_mask_texture_for_id(active_room_id)
	_camera_room_transition_from_tex = active_tex
	_camera_room_transition_to_tex = active_tex
	_camera_room_mask_blend = 1.0
	if _camera_room_mask_tween != null and _camera_room_mask_tween.is_running():
		_camera_room_mask_tween.kill()
	_mark_visibility_materials_dirty(&"camera_room_transition_finished")
	_invalidate_camera_room_composite()


func reset_camera_room_mask_debug_state() -> void:
	_camera_room_mask_rebuild_count = 0
	_camera_room_mask_texture_build_count = 0


func get_camera_room_mask_debug_state() -> Dictionary:
	return {
		"rebuild_count": _camera_room_mask_rebuild_count,
		"mask_texture_build_count": _camera_room_mask_texture_build_count,
		"mask_count": _camera_room_masks_by_id.size(),
		"defs_signature": _camera_room_defs_signature,
		"viewport_size": _camera_room_mask_viewport_size,
		"active_room_id": _camera_room_active_id,
	}


func _set_camera_room_mask_blend(value: float) -> void:
	_camera_room_mask_blend = clampf(value, 0.0, 1.0)
	_mark_visibility_materials_dirty(&"camera_room_mask_blend")
	_invalidate_camera_room_composite()


func get_current_texture() -> Texture2D:
	_note_surface_texture_read(SURFACE_CURRENT_VISIBILITY)
	if _current_viewport == null:
		return null
	return _current_viewport.get_texture()


func get_fog_of_war_texture() -> Texture2D:
	_note_surface_texture_read(SURFACE_FOG_OF_WAR)
	if _history_viewports.is_empty():
		return null
	return _history_viewports[_history_present_index].get_texture()


func get_seen_texture() -> Texture2D:
	return get_fog_of_war_texture()


func get_render_mask_texture(mask_name: StringName) -> Texture2D:
	match mask_name:
		&"fog_of_war":
			return get_fog_of_war_texture()
		&"current_visibility":
			return get_current_texture()
		_:
			return _render_mask_texture(mask_name)


func get_render_mask_texture_revision(mask_name: StringName) -> int:
	return int(_render_mask_texture_revisions.get(mask_name, -1))


func debug_get_surface_snapshot(surface: StringName) -> Dictionary:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return {}
	var consumer_keys: Dictionary = state.get("consumer_keys", {})
	var viewport := state.get("viewport") as SubViewport
	return {
		"surface": String(surface),
		"consumer_count": int(consumer_keys.size()),
		"dirty": bool(state.get("dirty", true)),
		"refresh_request_count": int(state.get("refresh_request_count", 0)),
		"invalidate_count": int(state.get("invalidate_count", 0)),
		"texture_read_count": int(state.get("texture_read_count", 0)),
		"last_dirty_reason": String(state.get("last_dirty_reason", "")),
		"update_mode": viewport.render_target_update_mode if viewport != null else SubViewport.UPDATE_DISABLED,
	}


func debug_get_cache_snapshot() -> Dictionary:
	return {
		"camera_room_mask_rebuild_count": _camera_room_mask_rebuild_count,
		"source_visibility_material_refresh_count": _source_visibility_material_refresh_count,
		"source_visibility_material_update_count": _source_visibility_material_update_count,
		"revealer_count": _reveal_sources.size(),
		"revealer_registry_traversal_count": _revealer_registry_traversal_count,
		"source_capture_light_update_count": _source_capture_light_update_count,
		"dynamic_occluder_registry_scan_count": _dynamic_occluder_registry_scan_count,
		"occluder_rebuild_count": _static_occluder_rebuild_count + _dynamic_occluder_rebuild_count,
		"occluder_changed_segment_count": _static_occluder_changed_segment_count + _dynamic_occluder_changed_segment_count,
		"static_occluder_rebuild_count": _static_occluder_rebuild_count,
		"static_occluder_changed_segment_count": _static_occluder_changed_segment_count,
		"dynamic_occluder_rebuild_count": _dynamic_occluder_rebuild_count,
		"dynamic_occluder_changed_segment_count": _dynamic_occluder_changed_segment_count,
		"dynamic_occluder_provider_count": _dynamic_occluder_provider_nodes.size(),
		"dynamic_occluder_count": _dynamic_wall_occluders.size(),
		"dynamic_occluder_polygon_point_count": _dynamic_wall_occluders.size() * 4,
		"static_occluder_count": _fog_blockers.size(),
		"static_occluder_polygon_point_count": _fog_blockers.size() * 4,
		"current_surface_redraw_count": _current_surface_redraw_count,
		"capture_viewport_size": _current_viewport.size if _current_viewport != null else Vector2i.ZERO,
		"capture_viewport_revision": _capture_viewport_revision,
		"history_dirty_publication_count": _history_dirty_publication_count,
		"history_dirty_published_region_count": _history_dirty_published_region_count,
		"history_dirty_published_area": _history_dirty_published_area,
		"decay_gpu_pass_count": _decay_gpu_pass_count,
		"decay_uploaded_contribution_count": _decay_uploaded_contribution_count,
		"decay_uploaded_batch_count": _decay_uploaded_batch_count,
		"full_texture_readback_count": _full_texture_readback_count,
		"sprite_material_count": _source_sprite_visibility_materials.size(),
		"origin_material_count": _source_origin_visibility_materials.size(),
		"animated_visibility_mask": _visibility_mask_simulation.debug_get_snapshot() if _visibility_mask_simulation != null else {},
		"packed_visibility_capture": _packed_visibility_capture.debug_get_snapshot() if _packed_visibility_capture != null else {},
		"sound_light_field": debug_get_sound_light_snapshot(),
	}


func _on_scene_tree_node_added(node: Node) -> void:
	if node != null and node.is_in_group(FOG_BLOCKER_2D_GROUP):
		register_fog_blocker(node)
	_on_scene_tree_node_changed(node)


func _on_scene_tree_node_removed(node: Node) -> void:
	if node != null and node.is_in_group(FOG_BLOCKER_2D_GROUP):
		unregister_fog_blocker(node)
	_on_scene_tree_node_changed(node)


func _on_scene_tree_node_changed(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		_source_refs_dirty = true
	if node is AnimatedSprite3D:
		_visibility_material_bindings_dirty = true
		_visibility_material_params_dirty = true
		_source_sprite_cache_dirty = true
	if node is GeometryInstance3D:
		_visibility_material_bindings_dirty = true
		_visibility_material_params_dirty = true
		_source_origin_material_cache_dirty = true
	var node_id := node.get_instance_id()
	if node.has_method("get_maze_render_segments_2d") \
	or node.is_in_group(_DYNAMIC_SEGMENT_PROVIDER_GROUP) \
	or _dynamic_occluder_provider_nodes.has(node_id):
		_dynamic_occluder_membership_dirty = true


func _mark_full_refresh_needed(reason: StringName) -> void:
	_source_refs_dirty = true
	_capture_geometry_dirty = true
	_capture_camera_dirty = true
	_wall_knowledge_settings_dirty = true
	_mask_overlays_dirty = true
	_mask_textures_dirty = true
	_visibility_material_bindings_dirty = true
	_visibility_material_params_dirty = true
	_source_sprite_cache_dirty = true
	_source_origin_material_cache_dirty = true
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, reason)
	_invalidate_surface(SURFACE_FOG_OF_WAR, reason)


func _mark_visibility_materials_dirty(reason: StringName) -> void:
	_visibility_material_params_dirty = true
	_mask_overlays_dirty = true
	_mask_textures_dirty = true


func _ensure_surface_state(surface: StringName, viewport: SubViewport) -> void:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		state = {
			"viewport": viewport,
			"consumer_keys": {},
			"dirty": true,
			"refresh_request_count": 0,
			"invalidate_count": 1,
			"texture_read_count": 0,
			"last_dirty_reason": "initial",
		}
	else:
		state["viewport"] = viewport
	_surface_states[surface] = state
	_apply_surface_update_mode(surface)


func _invalidate_surface(surface: StringName, reason: StringName) -> void:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return
	state["dirty"] = true
	state["invalidate_count"] = int(state.get("invalidate_count", 0)) + 1
	state["last_dirty_reason"] = String(reason)
	_surface_states[surface] = state
	_apply_surface_update_mode(surface)


func _note_surface_texture_read(surface: StringName) -> void:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return
	state["texture_read_count"] = int(state.get("texture_read_count", 0)) + 1
	_surface_states[surface] = state
	_debug_surface_read_frames[surface] = Engine.get_process_frames()
	_sync_surface_consumers()


func _set_surface_consumer(surface: StringName, consumer_key: String, active: bool) -> void:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return
	var consumer_keys: Dictionary = state.get("consumer_keys", {})
	var had_consumers := not consumer_keys.is_empty()
	if active:
		consumer_keys[consumer_key] = true
	else:
		consumer_keys.erase(consumer_key)
	state["consumer_keys"] = consumer_keys
	_surface_states[surface] = state
	if active and not had_consumers:
		# A surface with no consumers is left UPDATE_DISABLED and never rendered, so its
		# texture can be stale or blank. A newly-gained consumer (e.g. a vision-affecting
		# pill effect switching a render-mask target from "off" to active) must force a
		# fresh render immediately rather than waiting for the next unrelated invalidation
		# (normally player movement), or the mask shows blank/stale content for a moment.
		_invalidate_surface(surface, &"consumer_gained")
	else:
		_apply_surface_update_mode(surface)


func _surface_recently_read(surface: StringName) -> bool:
	var read_frame := int(_debug_surface_read_frames.get(surface, -10000))
	return Engine.get_process_frames() - read_frame <= _DEBUG_SURFACE_CONSUMER_TTL_FRAMES


func _surface_has_consumers(surface: StringName) -> bool:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return false
	var consumer_keys: Dictionary = state.get("consumer_keys", {})
	return not consumer_keys.is_empty()


func _apply_surface_update_mode(surface: StringName) -> void:
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty():
		return
	var viewport := state.get("viewport") as SubViewport
	if viewport == null:
		return
	if not _surface_has_consumers(surface):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif bool(state.get("dirty", false)) and viewport.render_target_update_mode != SubViewport.UPDATE_ONCE:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _sync_surface_consumers() -> void:
	var history_debug_active := _surface_recently_read(SURFACE_FOG_OF_WAR)
	var history_world_mask_active := _render_mask_has_active_target(&"fog_of_war")
	var current_world_mask_active := _render_mask_has_active_target(&"current_visibility")
	var history_owned: bool = _maze_data != null and (not _reveal_sources.is_empty() or (_memory_decay_controller != null and _memory_decay_controller.has_registered_sources()))
	var history_consumed: bool = history_debug_active or history_world_mask_active or history_owned
	_set_surface_consumer(SURFACE_FOG_OF_WAR, _SURFACE_CONSUMER_WORLD_MASK, history_world_mask_active)
	_set_surface_consumer(SURFACE_FOG_OF_WAR, _SURFACE_CONSUMER_DEBUG_READ, history_debug_active)
	_set_surface_consumer(SURFACE_FOG_OF_WAR, _SURFACE_CONSUMER_HISTORY_PIPELINE, history_owned)
	_set_surface_consumer(SURFACE_CURRENT_VISIBILITY, _SURFACE_CONSUMER_WORLD_MASK, current_world_mask_active)
	_set_surface_consumer(SURFACE_CURRENT_VISIBILITY, _SURFACE_CONSUMER_HISTORY_PIPELINE, history_consumed)
	_set_surface_consumer(SURFACE_CURRENT_VISIBILITY, _SURFACE_CONSUMER_DEBUG_READ, _surface_recently_read(SURFACE_CURRENT_VISIBILITY))


func _render_mask_has_active_target(mask_name: StringName) -> bool:
	for target in _RENDER_MASK_TARGETS:
		var path := SharedStateKeys.render_mask_path(String(mask_name), String(target))
		if RenderMaskCompositionScript.mode_is_active(_render_mask_modes.get(path, "off")):
			return true
	return false


func _render_mask_target_has_active_consumer(target: StringName) -> bool:
	if target == &"game_world":
		return _maze_data != null and (_source_floor_mesh != null or _source_maze_mesh != null)
	var renderer := _bound_two_d_world_renderer if _bound_two_d_world_renderer != null else _get_two_d_world_renderer()
	if renderer == null:
		return false
	return renderer.get_surface_consumer_count(target) > 0


func _bind_two_d_world_renderer(renderer: TwoDWorldRenderer) -> void:
	if _bound_two_d_world_renderer == renderer:
		return
	var changed_callable := Callable(self, "_on_two_d_world_renderer_outputs_changed")
	var coverage_changed_callable := Callable(self, "_on_two_d_world_renderer_coverage_changed")
	if _bound_two_d_world_renderer != null and _bound_two_d_world_renderer.outputs_changed.is_connected(changed_callable):
		_bound_two_d_world_renderer.outputs_changed.disconnect(changed_callable)
	if _bound_two_d_world_renderer != null and _bound_two_d_world_renderer.render_layer_coverage_changed.is_connected(coverage_changed_callable):
		_bound_two_d_world_renderer.render_layer_coverage_changed.disconnect(coverage_changed_callable)
	if _bound_two_d_world_renderer != null:
		_bound_two_d_world_renderer.set_render_mask_texture_provider(null)
	_bound_two_d_world_renderer = renderer
	if _bound_two_d_world_renderer != null and not _bound_two_d_world_renderer.outputs_changed.is_connected(changed_callable):
		_bound_two_d_world_renderer.outputs_changed.connect(changed_callable)
		_bound_two_d_world_renderer.set_render_mask_texture_provider(self)
	if _bound_two_d_world_renderer != null and not _bound_two_d_world_renderer.render_layer_coverage_changed.is_connected(coverage_changed_callable):
		_bound_two_d_world_renderer.render_layer_coverage_changed.connect(coverage_changed_callable)
	_render_mask_outputs_dirty = true
	_sync_render_mask_object_layers()


func _on_two_d_world_renderer_coverage_changed(_render_layer: StringName) -> void:
	_render_mask_outputs_dirty = true


func _sync_render_mask_object_layers() -> void:
	if _bound_two_d_world_renderer == null:
		return
	for mask_name in _RENDER_MASK_NAMES:
		_bound_two_d_world_renderer.notify_render_mask_texture_changed(
			mask_name,
			get_render_mask_texture_revision(mask_name)
		)


func _on_two_d_world_renderer_outputs_changed() -> void:
	_render_mask_outputs_dirty = true


func _mark_debug_surface_consumers_stale() -> void:
	for surface in [SURFACE_CURRENT_VISIBILITY, SURFACE_FOG_OF_WAR]:
		var state: Dictionary = _surface_states.get(surface, {})
		var consumer_keys: Dictionary = state.get("consumer_keys", {})
		if consumer_keys.has(_SURFACE_CONSUMER_DEBUG_READ) and not _surface_recently_read(surface):
			_sync_surface_consumers()
			return


func _schedule_surface_update(surface: StringName) -> bool:
	if not _surface_has_consumers(surface):
		return false
	var state: Dictionary = _surface_states.get(surface, {})
	if state.is_empty() or not bool(state.get("dirty", false)):
		return false
	if surface == SURFACE_FOG_OF_WAR:
		return _advance_history_once()
	var viewport := state.get("viewport") as SubViewport
	if viewport == null:
		return false
	# RenderingServer consumes UPDATE_ONCE on its own copy after the draw, but never
	# writes the scene-side property back, so this stays UPDATE_ONCE forever once set.
	# Re-assigning it is what actually requests the next draw; treating UPDATE_ONCE as
	# "a request is already in flight" permanently froze the surface after its first
	# render. `dirty` is the real single-schedule-per-invalidation guard, and it is
	# cleared immediately below.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	state["dirty"] = false
	state["refresh_request_count"] = int(state.get("refresh_request_count", 0)) + 1
	if surface == SURFACE_CURRENT_VISIBILITY:
		_current_surface_redraw_count += 1
	_surface_states[surface] = state
	_render_mask_texture_revisions[surface] = int(_render_mask_texture_revisions.get(surface, 0)) + 1
	_render_mask_outputs_dirty = true
	return true


func _ensure_source_references() -> void:
	if not _source_refs_dirty \
	and _source_maze_mesh != null and is_instance_valid(_source_maze_mesh) \
	and _source_floor_mesh != null and is_instance_valid(_source_floor_mesh):
		return
	var next_source_maze_mesh := _resolve_source_maze_mesh()
	var next_source_floor_mesh := _resolve_source_floor_mesh()
	var next_maze_root := next_source_maze_mesh.get_parent() as Node3D if next_source_maze_mesh != null else null
	if _source_maze_mesh != next_source_maze_mesh or _source_floor_mesh != next_source_floor_mesh or _maze_root != next_maze_root:
		_capture_geometry_dirty = true
		_capture_camera_dirty = true
		_visibility_material_bindings_dirty = true
		_visibility_material_params_dirty = true
		_source_sprite_cache_dirty = true
		_source_origin_material_cache_dirty = true
		_source_maze_mesh = next_source_maze_mesh
		_source_floor_mesh = next_source_floor_mesh
		_maze_root = next_maze_root
		_source_maze_transform_known = false
	_source_refs_dirty = false


func _sync_maze_transform_if_changed() -> void:
	if _source_maze_mesh == null or not is_instance_valid(_source_maze_mesh):
		_source_maze_transform_known = false
		return
	var current_transform := _source_maze_mesh.global_transform
	if _source_maze_transform_known and current_transform.is_equal_approx(_source_maze_global_transform):
		return
	_source_maze_global_transform = current_transform
	_source_maze_transform_known = true
	# The capture is authored in maze-local 2D coordinates, so a world-space
	# transform changes only downstream shader mapping, never the capture texture.
	_visibility_material_params_dirty = true


func _sync_wall_knowledge_settings_if_needed() -> void:
	if not _wall_knowledge_settings_dirty:
		return
	_sync_wall_knowledge_settings()
	_wall_knowledge_settings_dirty = false


func _sync_capture_geometry_if_needed() -> void:
	if not _capture_geometry_dirty:
		return
	_sync_capture_geometry()
	_capture_geometry_dirty = false
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"capture_geometry")


func _refresh_capture_layout_if_needed() -> void:
	if not _capture_camera_dirty:
		return
	_refresh_capture_layout()
	_capture_camera_dirty = false
	# Cell -> UV is derived from the capture rect, so it has to follow the camera.
	_configure_cell_discovery()
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"capture_layout")
	_mark_visibility_materials_dirty(&"capture_layout")


func _refresh_source_visibility_materials_if_needed() -> void:
	if not _visibility_material_bindings_dirty \
	and not _source_sprite_cache_dirty \
	and not _source_origin_material_cache_dirty:
		return
	_ensure_source_visibility_materials()
	_visibility_material_bindings_dirty = false


func _update_source_visibility_materials_if_needed() -> void:
	if not _visibility_material_params_dirty:
		return
	_update_source_visibility_materials()
	_visibility_material_params_dirty = false
	_source_visibility_material_update_count += 1


func _sync_mask_overlays_if_needed() -> void:
	if not _mask_overlays_dirty:
		return
	_sync_mask_overlays()
	_mask_overlays_dirty = false


func _update_mask_textures_if_needed() -> void:
	if not _mask_textures_dirty:
		return
	_update_mask_textures()
	_mask_textures_dirty = false


## Registers a live, event-driven fog source. Duplicate registration is rejected.
## Reveal geometry is authored exclusively in the 2D maze world; a source of any
## other type has no maze-space origin this manager can honour.
func register_reveal_source(source: Node) -> bool:
	if source == null or not is_instance_valid(source) or not (source is FogRevealSource2D):
		return false
	var key := source.get_instance_id()
	if _reveal_sources.has(key):
		return false
	# Before the history rect, which is derived from the effective range.
	_sync_source_maze_cell_size(source)
	_reveal_sources[key] = {
		"source": source,
		"history_rect": _history_dirty_uv_rect_for_source(source),
	}
	_adopt_2d_source_capture_light(source)
	_invalidate_view_distance_mask()
	if source.has_signal("source_changed") and not source.is_connected("source_changed", _on_reveal_source_changed):
		source.connect("source_changed", _on_reveal_source_changed)
	if not source.tree_exiting.is_connected(_on_reveal_source_tree_exiting.bind(source)):
		source.tree_exiting.connect(_on_reveal_source_tree_exiting.bind(source))
	_on_reveal_source_changed(source)
	_sync_surface_consumers()
	return true


## Unregisters a source and removes only its current-visibility contribution.
func unregister_reveal_source(source: Node) -> void:
	if source == null:
		return
	var key := source.get_instance_id()
	if not _reveal_sources.has(key):
		return
	if source.has_signal("source_changed") and source.is_connected("source_changed", _on_reveal_source_changed):
		source.disconnect("source_changed", _on_reveal_source_changed)
	var exiting_callback := _on_reveal_source_tree_exiting.bind(source)
	if source.tree_exiting.is_connected(exiting_callback):
		source.tree_exiting.disconnect(exiting_callback)
	var entry := _reveal_sources.get(key) as Dictionary
	_queue_history_dirty_rect(entry.get("history_rect", Rect2()) as Rect2)
	_reveal_sources.erase(key)
	_release_2d_source_capture_light(source as FogRevealSource2D)
	_invalidate_view_distance_mask()
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"reveal_source_removed")
	_sync_surface_consumers()


## Registers a component-owned blocker. The manager supplies only its isolated
## capture canvas; canonical wall geometry and LightOccluder2D lifetime remain
## owned by FogBlocker2D and MazeBuilder.
func register_fog_blocker(blocker: Node) -> bool:
	if blocker == null or not is_instance_valid(blocker) or not blocker.has_method("attach_capture_occluder"):
		return false
	var key := blocker.get_instance_id()
	if _fog_blockers.has(key):
		return false
	_fog_blockers[key] = blocker
	if blocker.has_signal("blocker_changed") and not blocker.blocker_changed.is_connected(_on_fog_blocker_changed):
		blocker.blocker_changed.connect(_on_fog_blocker_changed)
	if not blocker.tree_exiting.is_connected(_on_fog_blocker_tree_exiting.bind(blocker)):
		blocker.tree_exiting.connect(_on_fog_blocker_tree_exiting.bind(blocker))
	_adopt_fog_blocker(blocker)
	_static_occluder_rebuild_count += 1
	_static_occluder_changed_segment_count += 1
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"fog_blocker_registered")
	_queue_full_history_dirty_for_topology()
	return true


func unregister_fog_blocker(blocker: Node) -> void:
	if blocker == null:
		return
	var key := blocker.get_instance_id()
	if not _fog_blockers.has(key):
		return
	if blocker.has_signal("blocker_changed") and blocker.blocker_changed.is_connected(_on_fog_blocker_changed):
		blocker.blocker_changed.disconnect(_on_fog_blocker_changed)
	var exiting_callback := _on_fog_blocker_tree_exiting.bind(blocker)
	if blocker.tree_exiting.is_connected(exiting_callback):
		blocker.tree_exiting.disconnect(exiting_callback)
	_fog_blockers.erase(key)
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"fog_blocker_removed")
	_queue_full_history_dirty_for_topology()


func _adopt_fog_blocker(blocker: Node) -> void:
	_ensure_occluder_root()
	if _occluder_root_2d != null:
		blocker.call("attach_capture_occluder", _occluder_root_2d)


func _on_fog_blocker_changed(blocker: Node, _revision: int) -> void:
	if blocker == null or not _fog_blockers.has(blocker.get_instance_id()):
		return
	_adopt_fog_blocker(blocker)
	_static_occluder_rebuild_count += 1
	_static_occluder_changed_segment_count += 1
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"fog_blocker_changed")
	_queue_full_history_dirty_for_topology()


func _on_fog_blocker_tree_exiting(blocker: Node) -> void:
	unregister_fog_blocker(blocker)


## Registers a lifecycle-owned memory-decay source and returns its opaque handle.
func register_memory_decay_source(source: FogMemoryDecaySource3D) -> int:
	_ensure_memory_decay_controller()
	if _memory_decay_controller == null:
		return -1
	var handle: int = _memory_decay_controller.register_source(source)
	if handle >= 0:
		_sync_surface_consumers()
		_invalidate_surface(SURFACE_FOG_OF_WAR, &"memory_decay_source_registered")
	return handle


## Unregisters a memory-decay source without changing already-forgotten history.
func unregister_memory_decay_source(source: FogMemoryDecaySource3D) -> void:
	if _memory_decay_controller == null:
		return
	_memory_decay_controller.unregister_source(source)
	_sync_surface_consumers()


func debug_get_memory_decay_snapshot() -> Dictionary:
	return _memory_decay_controller.debug_get_snapshot() if _memory_decay_controller != null else {
		"registered_count": 0,
		"enabled_count": 0,
		"winning_count": 0,
		"timer_running": false,
		"tick_count": 0,
	}


func _ensure_memory_decay_controller() -> void:
	if _memory_decay_controller != null and is_instance_valid(_memory_decay_controller):
		return
	_memory_decay_controller = get_node_or_null("FogMemoryDecayController") as FogMemoryDecayController
	if _memory_decay_controller == null:
		_memory_decay_controller = FOG_MEMORY_DECAY_CONTROLLER_SCENE.instantiate() as FogMemoryDecayController
		add_child(_memory_decay_controller)
	if not _memory_decay_controller.decay_tick.is_connected(_on_memory_decay_tick):
		_memory_decay_controller.decay_tick.connect(_on_memory_decay_tick)
	if not _memory_decay_controller.active_tier_changed.is_connected(_on_memory_decay_active_tier_changed):
		_memory_decay_controller.active_tier_changed.connect(_on_memory_decay_active_tier_changed)
	if not _memory_decay_controller.contributions_changed.is_connected(_on_memory_decay_contributions_changed):
		_memory_decay_controller.contributions_changed.connect(_on_memory_decay_contributions_changed)


func _disconnect_memory_decay_controller() -> void:
	if _memory_decay_controller == null or not is_instance_valid(_memory_decay_controller):
		return
	if _memory_decay_controller.decay_tick.is_connected(_on_memory_decay_tick):
		_memory_decay_controller.decay_tick.disconnect(_on_memory_decay_tick)
	if _memory_decay_controller.active_tier_changed.is_connected(_on_memory_decay_active_tier_changed):
		_memory_decay_controller.active_tier_changed.disconnect(_on_memory_decay_active_tier_changed)
	if _memory_decay_controller.contributions_changed.is_connected(_on_memory_decay_contributions_changed):
		_memory_decay_controller.contributions_changed.disconnect(_on_memory_decay_contributions_changed)


func _on_memory_decay_active_tier_changed() -> void:
	_sync_surface_consumers()
	if _memory_decay_controller == null or not _memory_decay_controller.has_enabled_sources():
		_clear_memory_decay_shader_parameters()


func _on_memory_decay_contributions_changed() -> void:
	# Never let a reveal- or topology-driven history pass reuse compact decay
	# inputs from a removed, disabled, moved, or reconfigured source. The next
	# scheduled decay tick uploads a fresh deterministic batch.
	_clear_memory_decay_shader_parameters()


func _on_memory_decay_tick(_contributions: Array[Dictionary]) -> void:
	# Forgetting is age-ordered and therefore global: the frontier advances through
	# the recency gradient, so every explored texel is a candidate and the whole
	# surface is republished. Scheduling stays event driven; a tick is the sole
	# recurring history invalidation.
	if _memory_decay_controller != null:
		_forget_threshold = clampf(_forget_threshold + _memory_decay_controller.get_pending_frontier_advance(), 0.0, 1.0)
		_history_reset_pending_full_dirty = true
		_upload_memory_decay_shader_parameters()
		_decay_history_pass_pending = true
	_invalidate_surface(SURFACE_FOG_OF_WAR, &"memory_decay_tick")


func _upload_memory_decay_shader_parameters() -> void:
	if _memory_decay_controller == null:
		return
	var soft_edge := _memory_decay_controller.get_frontier_soft_edge()
	for material in _history_materials:
		material.set_shader_parameter("forget_threshold", _forget_threshold)
		material.set_shader_parameter("forget_soft_edge", soft_edge)
	_decay_uploaded_contribution_count = _memory_decay_controller.get_winning_contributions().size()
	_decay_uploaded_batch_count = 1 if _decay_uploaded_contribution_count > 0 else 0


## Stops forgetting without rewinding the frontier, so already-erased memory stays
## erased and a re-enabled contribution resumes from where it left off.
func _clear_memory_decay_shader_parameters() -> void:
	for material in _history_materials:
		material.set_shader_parameter("forget_threshold", 0.0)
	_decay_uploaded_contribution_count = 0
	_decay_uploaded_batch_count = 0


func _disconnect_reveal_sources() -> void:
	_revealer_registry_traversal_count += _reveal_sources.size()
	for entry_variant in _reveal_sources.values():
		var entry := entry_variant as Dictionary
		var source := entry.get("source") as Node
		if source != null and is_instance_valid(source):
			if source.has_signal("source_changed") and source.is_connected("source_changed", _on_reveal_source_changed):
				source.disconnect("source_changed", _on_reveal_source_changed)
			var exiting_callback := _on_reveal_source_tree_exiting.bind(source)
			if source.tree_exiting.is_connected(exiting_callback):
				source.tree_exiting.disconnect(exiting_callback)
			_release_2d_source_capture_light(source as FogRevealSource2D)
	_reveal_sources.clear()


func _on_reveal_source_tree_exiting(source: Node) -> void:
	unregister_reveal_source(source)


func _on_reveal_source_changed(source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	var key := source.get_instance_id()
	var entry := _reveal_sources.get(key) as Dictionary
	if entry.is_empty():
		return
	var previous_rect := entry.get("history_rect", Rect2()) as Rect2
	var next_rect := _history_dirty_uv_rect_for_source(source)
	entry["history_rect"] = next_rect
	_reveal_sources[key] = entry
	_update_2d_source_capture_light(source as FogRevealSource2D)
	_invalidate_view_distance_mask()
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"reveal_source_changed")
	# The history pass sees the new current texture, so both the old footprint
	# (to clear a moved/disabled light) and the new footprint must be revisited.
	# A cone uses its enclosing range disc below, deliberately conservative for
	# rotation and soft-edge changes without a second LOS implementation.
	_queue_history_dirty_rect(previous_rect)
	if bool(source.call("is_effectively_enabled")):
		_queue_history_dirty_rect(next_rect)


func _queue_history_dirty_rect(rect: Rect2) -> void:
	var clipped := rect.intersection(Rect2(Vector2.ZERO, Vector2.ONE))
	if clipped.size.x > 0.0 and clipped.size.y > 0.0:
		_pending_history_dirty_uv_rects.append(clipped)


func _queue_full_history_dirty_for_topology() -> void:
	_queue_history_dirty_rect(Rect2(Vector2.ZERO, Vector2.ONE))


## A source's own history footprint, so disabling or moving one revealer
## republishes only the region it could have lit. A cone deliberately uses its
## enclosing range disc: conservative for rotation and soft-edge changes without
## a second line-of-sight implementation.
func _history_dirty_uv_rect_for_source(source: Node) -> Rect2:
	var source_2d := source as FogRevealSource2D
	if source_2d == null:
		return Rect2()
	var maze_rect := _current_visibility_maze_rect()
	if maze_rect.size.x <= 0.0 or maze_rect.size.y <= 0.0:
		return Rect2()
	var maze_position := source_2d.get_effective_origin() * _maze_pixels_to_world_scale()
	var uv_center := (maze_position - maze_rect.position) / maze_rect.size
	var source_range := source_2d.get_effective_range()
	var uv_radius := Vector2(source_range / maze_rect.size.x, source_range / maze_rect.size.y)
	return Rect2(uv_center - uv_radius, uv_radius * 2.0).intersection(Rect2(Vector2.ZERO, Vector2.ONE))


## A state-backed reveal range is authored in cells, so every source needs the
## live world cell size to resolve it into the world units this manager consumes.
## Re-pushed on every maze apply so a live `gameplay_config/maze/cell_size_px`
## retune scales sight distance with the rest of the maze.
func _sync_source_maze_cell_size(source: FogRevealSource2D) -> void:
	if source == null or not is_instance_valid(source) or _builder_settings == null:
		return
	source.set_maze_cell_size_world(_builder_settings.cell_size)


func _sync_all_source_maze_cell_sizes() -> void:
	for entry_variant in _reveal_sources.values():
		_sync_source_maze_cell_size((entry_variant as Dictionary).get("source") as FogRevealSource2D)


## Reparents the component-owned fog light into the isolated capture canvas.
## The source remains its sole creator/configurator; this manager only gives the
## light a capture canvas and mirrors the authoritative 2D transform.
func _adopt_2d_source_capture_light(source: FogRevealSource2D) -> void:
	if _capture_root_2d == null:
		return
	source.attach_capture_light(_capture_root_2d)
	_update_2d_source_capture_light(source)


func _update_2d_source_capture_light(source: FogRevealSource2D) -> void:
	if _capture_root_2d == null:
		return
	var capture_light := source.get_capture_light()
	if capture_light.get_parent() != _capture_root_2d:
		capture_light = source.attach_capture_light(_capture_root_2d)
	# The capture canvas is authored in maze world units, but a 2D source lives in
	# the gameplay maze space, which is authored in pixels. Convert, exactly as the
	# 2D-authored occluder geometry does, or the light lands `cell_size_px` times
	# too far from the maze origin and never reaches the capture rect at all.
	capture_light.position = source.get_effective_origin() * _maze_pixels_to_world_scale()
	# The capture root is unrotated maze space. Mirror the source's maze-local
	# heading, not its canvas-global rotation, so rotating the presentation pivot
	# cannot spin a cone independently of its maze-local entity.
	capture_light.rotation = source.get_effective_forward().angle()
	_source_capture_light_update_count += 1


## Scale factor from gameplay 2D maze pixels to the maze world units the capture
## canvas is authored in. Everything added to `_capture_root_2d` from 2D-authored
## data (reveal lights, wall occluders) must pass through this.
func _maze_pixels_to_world_scale() -> float:
	var main_view := _get_main_maze_view()
	var view_cell_size_px := maxf(0.0001, float(main_view.cell_size)) if main_view != null else 1.0
	var world_cell_size := maxf(0.0001, float(_builder_settings.cell_size)) if _builder_settings != null else 1.0
	return world_cell_size / view_cell_size_px


func _release_2d_source_capture_light(source: FogRevealSource2D) -> void:
	if source.is_inside_tree() and not source.is_queued_for_deletion():
		source.attach_capture_light(source)




func _ensure_occluder_root() -> void:
	if _capture_root_2d == null:
		return
	if _occluder_root_2d == null or not is_instance_valid(_occluder_root_2d):
		_occluder_root_2d = _capture_root_2d.get_node_or_null(FOG_CAPTURE_2D_OCCLUDER_ROOT_NAME) as Node2D
	if _occluder_root_2d == null:
		_occluder_root_2d = Node2D.new()
		_occluder_root_2d.name = FOG_CAPTURE_2D_OCCLUDER_ROOT_NAME
		_capture_root_2d.add_child(_occluder_root_2d)


func _apply_occluder_rect(registry: Dictionary, key: String, rect: Rect2) -> void:
	var occluder := registry.get(key) as LightOccluder2D
	if occluder == null or not is_instance_valid(occluder):
		occluder = LightOccluder2D.new()
		occluder.name = "FogOccluder_%s" % key.replace(",", "_").replace(":", "_")
		var polygon := OccluderPolygon2D.new()
		polygon.closed = true
		occluder.occluder = polygon
		occluder.light_mask = FOG_CAPTURE_2D_LIGHT_MASK
		_occluder_root_2d.add_child(occluder)
		registry[key] = occluder
	var polygon := occluder.occluder as OccluderPolygon2D
	polygon.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


## Dynamic occluders (sliding doors and similar) sourced from the
## `maze_render_segment_2d_provider` group's `occlusion_start_local`/
## `occlusion_end_local` payload, each keyed by its own
## `get_maze_render_segments_2d_revision()` plus a provider-owned
## `maze_render_segments_2d_changed` signal. The SceneTree group is scanned
## only when membership changed, so unchanged frames do no topology traversal.
func _refresh_dynamic_occluders_if_needed() -> void:
	if not _dynamic_occluder_membership_dirty:
		return
	_dynamic_occluder_membership_dirty = false
	if get_tree() == null or _builder_settings == null:
		return
	_ensure_occluder_root()
	if _occluder_root_2d == null:
		return
	_dynamic_occluder_registry_scan_count += 1
	var pixels_to_world := _maze_pixels_to_world_scale()
	var half_thickness := maxf(0.0, float(_builder_settings.wall_thickness)) * 0.5 * _OCCLUDER_THICKNESS_RATIO
	var seen_provider_ids: Dictionary = {}
	for node in get_tree().get_nodes_in_group(_DYNAMIC_SEGMENT_PROVIDER_GROUP):
		# A queued provider can still be returned by the group during its final
		# frame. Treat it as removed now, rather than retaining a stale shadow
		# until the SceneTree eventually purges the group membership.
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion() or not node.has_method("get_maze_render_segments_2d"):
			continue
		var provider_id := node.get_instance_id()
		seen_provider_ids[provider_id] = true
		_dynamic_occluder_provider_nodes[provider_id] = node
		if node.has_signal(&"maze_render_segments_2d_changed") and not node.is_connected(&"maze_render_segments_2d_changed", _on_dynamic_occluder_provider_changed.bind(node)):
			node.connect(&"maze_render_segments_2d_changed", _on_dynamic_occluder_provider_changed.bind(node))
		if not node.tree_exiting.is_connected(_on_dynamic_occluder_provider_tree_exiting.bind(node)):
			node.tree_exiting.connect(_on_dynamic_occluder_provider_tree_exiting.bind(node))
		var revision := int(node.call("get_maze_render_segments_2d_revision")) if node.has_method("get_maze_render_segments_2d_revision") else 0
		if _dynamic_occluder_provider_revisions.get(provider_id, -1) == revision:
			continue
		_dynamic_occluder_provider_revisions[provider_id] = revision
		_rebuild_dynamic_occluders_for_provider(provider_id, node, pixels_to_world, half_thickness)
		_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"dynamic_occluder_changed")
		_queue_full_history_dirty_for_topology()
	for provider_id_variant in _dynamic_occluder_provider_revisions.keys().duplicate():
		var provider_id: int = provider_id_variant
		if not seen_provider_ids.has(provider_id):
			_remove_dynamic_occluders_for_provider(provider_id)
			_dynamic_occluder_provider_revisions.erase(provider_id)
			_dynamic_occluder_provider_nodes.erase(provider_id)
			_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"dynamic_occluder_provider_removed")
			_queue_full_history_dirty_for_topology()


## Compatibility probe retained for focused tests and editor diagnostics. Normal
## runtime work calls `_refresh_dynamic_occluders_if_needed()` from `_process`
## and never invokes this explicit membership scan on an idle frame.
func _refresh_dynamic_occluders_if_changed() -> void:
	_dynamic_occluder_membership_dirty = true
	_refresh_dynamic_occluders_if_needed()


func _on_dynamic_occluder_provider_changed(provider: Node) -> void:
	if provider == null or not is_instance_valid(provider) or provider.is_queued_for_deletion() or _builder_settings == null:
		return
	var provider_id := provider.get_instance_id()
	if not _dynamic_occluder_provider_nodes.has(provider_id):
		_dynamic_occluder_membership_dirty = true
		return
	var pixels_to_world := _maze_pixels_to_world_scale()
	var half_thickness := maxf(0.0, float(_builder_settings.wall_thickness)) * 0.5 * _OCCLUDER_THICKNESS_RATIO
	_dynamic_occluder_provider_revisions[provider_id] = int(provider.call("get_maze_render_segments_2d_revision")) if provider.has_method("get_maze_render_segments_2d_revision") else 0
	_rebuild_dynamic_occluders_for_provider(provider_id, provider, pixels_to_world, half_thickness)
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"dynamic_occluder_changed")
	_queue_full_history_dirty_for_topology()


func _on_dynamic_occluder_provider_tree_exiting(provider: Node) -> void:
	if provider == null:
		return
	var provider_id := provider.get_instance_id()
	_remove_dynamic_occluders_for_provider(provider_id)
	_dynamic_occluder_provider_revisions.erase(provider_id)
	_dynamic_occluder_provider_nodes.erase(provider_id)
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"dynamic_occluder_provider_removed")
	_queue_full_history_dirty_for_topology()


func _rebuild_dynamic_occluders_for_provider(provider_id: int, provider: Node, pixels_to_world: float, half_thickness: float) -> void:
	_dynamic_occluder_rebuild_count += 1
	var segments_variant: Variant = provider.call("get_maze_render_segments_2d")
	var segments: Array = segments_variant if segments_variant is Array else []
	var index := 0
	for segment in segments:
		var occlusion_start: Vector2 = segment.occlusion_start_local if segment is MazeRenderSegment2D else Vector2.ZERO
		var occlusion_end: Vector2 = segment.occlusion_end_local if segment is MazeRenderSegment2D else Vector2.ZERO
		var start_world := occlusion_start * pixels_to_world
		var end_world := occlusion_end * pixels_to_world
		var key := "%d:%d" % [provider_id, index]
		var rect := _thin_segment_rect(start_world, end_world, maxf(half_thickness, 0.01))
		if rect.size.x > 0.001 and rect.size.y > 0.001:
			_apply_occluder_rect(_dynamic_wall_occluders, key, rect)
		index += 1
	_remove_stale_dynamic_occluders_for_provider(provider_id, index)
	_dynamic_occluder_changed_segment_count += index


func _remove_stale_dynamic_occluders_for_provider(provider_id: int, kept_count: int) -> void:
	for key_variant in _dynamic_wall_occluders.keys().duplicate():
		var key := String(key_variant)
		var parts := key.split(":")
		if parts.size() != 2 or int(parts[0]) != provider_id:
			continue
		if int(parts[1]) < kept_count:
			continue
		var stale := _dynamic_wall_occluders.get(key) as LightOccluder2D
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
		_dynamic_wall_occluders.erase(key)


func _remove_dynamic_occluders_for_provider(provider_id: int) -> void:
	_remove_stale_dynamic_occluders_for_provider(provider_id, 0)


## Axis-aligned rectangle around a door panel segment. Thickness extends only
## perpendicular to the segment so adjacent panels do not grow endpoint caps
## that close an authored peek gap. Sliding doors are authored on maze axes;
## use a conservative AABB only for an unexpected diagonal provider.
func _thin_segment_rect(start_point: Vector2, end_point: Vector2, half_thickness: float) -> Rect2:
	var min_point := Vector2(minf(start_point.x, end_point.x), minf(start_point.y, end_point.y))
	var max_point := Vector2(maxf(start_point.x, end_point.x), maxf(start_point.y, end_point.y))
	var delta := (end_point - start_point).abs()
	if delta.x >= delta.y * 100.0:
		min_point.y -= half_thickness
		max_point.y += half_thickness
	elif delta.y >= delta.x * 100.0:
		min_point.x -= half_thickness
		max_point.x += half_thickness
	else:
		min_point -= Vector2(half_thickness, half_thickness)
		max_point += Vector2(half_thickness, half_thickness)
	return Rect2(min_point, max_point - min_point)


func _sync_source_sprite_material_textures() -> void:
	for sprite in _source_sprite_nodes:
		if sprite == null or not is_instance_valid(sprite):
			continue
		var material := _source_sprite_visibility_materials.get(sprite.get_instance_id()) as ShaderMaterial
		if material == null or not is_instance_valid(material):
			continue
		var signature := [StringName(sprite.animation), sprite.frame]
		var sprite_id := str(sprite.get_instance_id())
		if _source_sprite_signatures.get(sprite_id) == signature:
			continue
		_source_sprite_signatures[sprite_id] = signature
		_sync_source_sprite_material_texture(sprite, material)


func _ensure_runtime_nodes() -> void:
	_ensure_viewports()
	_ensure_2d_capture_graph()
	_ensure_wall_knowledge_controller()
	_ensure_mask_overlays()


## Runtime construction is owned by `_ready()`, maze-state changes, and the
## individual public mutation paths. The idle loop only needs to recover if an
## owned node was actually removed. Calling the full ensure chain unconditionally
## made each walking frame re-register all object-layer producers through the 2D
## renderer: the sparse script profile measured 3,978 registrations and 149,294
## object-layer key normalizations across 34 frames.
func _runtime_nodes_are_valid() -> bool:
	if _current_viewport == null or not is_instance_valid(_current_viewport):
		return false
	if _capture_background_2d == null or not is_instance_valid(_capture_background_2d):
		return false
	if _capture_root_2d == null or not is_instance_valid(_capture_root_2d):
		return false
	if _capture_receiver_2d == null or not is_instance_valid(_capture_receiver_2d):
		return false
	if _history_viewports.size() != 2:
		return false
	for viewport in _history_viewports:
		if viewport == null or not is_instance_valid(viewport):
			return false
	if _wall_knowledge_2d == null or not is_instance_valid(_wall_knowledge_2d):
		return false
	if _cell_discovery_2d == null or not is_instance_valid(_cell_discovery_2d):
		return false
	if _cell_visibility_2d == null or not is_instance_valid(_cell_visibility_2d):
		return false
	if _world_mask_3d == null or not is_instance_valid(_world_mask_3d):
		return false
	if _world_mask_2d_main == null or not is_instance_valid(_world_mask_2d_main):
		return false
	if _world_mask_2d_walls == null or not is_instance_valid(_world_mask_2d_walls):
		return false
	if _sound_light_world_mask_3d == null or not is_instance_valid(_sound_light_world_mask_3d):
		return false
	if _sound_light_world_mask_2d_main == null or not is_instance_valid(_sound_light_world_mask_2d_main):
		return false
	return _sound_light_world_mask_2d_walls != null and is_instance_valid(_sound_light_world_mask_2d_walls)


## Builds the isolated 2D light-only capture graph inside the current-visibility
## SubViewport (Decision 2). A black cleared background, a wall-inclusive white
## receiver drawn in light-only mode, and a maze-space capture root authored
## directly in maze-local coordinates. Reveal-source PointLight2D proxies
## (Phase 3) and occluder geometry (Phase 4) are added under `_capture_root_2d`
## by later phases; this graph currently has no lights, so it renders solid
## black until those phases land.
func _ensure_2d_capture_graph() -> void:
	if _current_viewport == null:
		return

	# Explicit black background, distinct from the light-only white receiver
	# (Decision 2). `render_target_clear_mode` alone clears to the project's
	# default clear color (a mid-gray, not black), which would otherwise leak
	# through anywhere the light-only receiver has no light contribution.
	if _capture_background_2d == null or not is_instance_valid(_capture_background_2d):
		_capture_background_2d = _current_viewport.get_node_or_null("FogCapture2DBackground") as ColorRect
	if _capture_background_2d == null:
		_capture_background_2d = ColorRect.new()
		_capture_background_2d.name = "FogCapture2DBackground"
		_current_viewport.add_child(_capture_background_2d)
		_current_viewport.move_child(_capture_background_2d, 0)
	_capture_background_2d.color = Color.BLACK
	_capture_background_2d.visibility_layer = FOG_CAPTURE_2D_LIGHT_MASK
	_capture_background_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_background_2d.position = Vector2.ZERO
	_capture_background_2d.size = Vector2(_current_viewport.size)

	var previous_capture_root := _capture_root_2d
	if _capture_root_2d == null or not is_instance_valid(_capture_root_2d):
		_capture_root_2d = _current_viewport.get_node_or_null(FOG_CAPTURE_2D_ROOT_NAME) as Node2D
	if _capture_root_2d == null:
		_capture_root_2d = Node2D.new()
		_capture_root_2d.name = FOG_CAPTURE_2D_ROOT_NAME
		_current_viewport.add_child(_capture_root_2d)

	if _capture_receiver_2d == null or not is_instance_valid(_capture_receiver_2d):
		_capture_receiver_2d = _capture_root_2d.get_node_or_null(FOG_CAPTURE_2D_RECEIVER_NAME) as ColorRect
	if _capture_receiver_2d == null:
		_capture_receiver_2d = ColorRect.new()
		_capture_receiver_2d.name = FOG_CAPTURE_2D_RECEIVER_NAME
		_capture_root_2d.add_child(_capture_receiver_2d)
	var receiver_material := _capture_receiver_2d.material as CanvasItemMaterial
	if receiver_material == null:
		receiver_material = CanvasItemMaterial.new()
		_capture_receiver_2d.material = receiver_material
	receiver_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY
	_capture_receiver_2d.color = Color.WHITE
	_capture_receiver_2d.light_mask = FOG_CAPTURE_2D_LIGHT_MASK
	_capture_receiver_2d.visibility_layer = FOG_CAPTURE_2D_LIGHT_MASK
	_capture_receiver_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_receiver_2d.position = Vector2.ZERO
	# This runs every frame, so already-adopted lights must be left alone.
	# Re-adopting reconfigures each source, which re-emits `source_changed` and
	# dirties the capture surface on frames where nothing actually changed.
	if _capture_root_2d == previous_capture_root:
		return
	for entry_variant in _reveal_sources.values():
		var source := (entry_variant as Dictionary).get("source") as Node
		if source is FogRevealSource2D:
			_adopt_2d_source_capture_light(source)


func _ensure_viewports() -> void:
	if _current_viewport == null or not is_instance_valid(_current_viewport):
		_current_viewport = get_node_or_null(CURRENT_VIEWPORT_NAME) as SubViewport
	if _current_viewport == null:
		_current_viewport = SubViewport.new()
		_current_viewport.name = CURRENT_VIEWPORT_NAME
		_current_viewport.disable_3d = true
		_current_viewport.handle_input_locally = false
		_current_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_current_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_current_viewport.transparent_bg = false
		add_child(_current_viewport)
	_current_viewport.disable_3d = true
	_current_viewport.handle_input_locally = false
	_current_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_current_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_current_viewport.transparent_bg = false
	_ensure_surface_state(SURFACE_CURRENT_VISIBILITY, _current_viewport)

	if _history_viewports.is_empty():
		for index in range(2):
			var existing_viewport := get_node_or_null("%s%d" % [HISTORY_VIEWPORT_PREFIX, index]) as SubViewport
			if existing_viewport == null:
				continue
			var existing_rect := existing_viewport.get_node_or_null(MERGE_RECT_NAME) as ColorRect
			if existing_rect == null:
				continue
			var existing_material := existing_rect.material as ShaderMaterial
			if existing_material == null:
				existing_material = ShaderMaterial.new()
				existing_material.shader = HISTORY_SHADER
				existing_rect.material = existing_material
			existing_viewport.disable_3d = true
			existing_viewport.handle_input_locally = false
			existing_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			existing_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			existing_viewport.transparent_bg = false
			_history_viewports.append(existing_viewport)
			_history_rects.append(existing_rect)
			_history_materials.append(existing_material)

	if _history_viewports.is_empty():
		for index in range(2):
			var history_viewport := SubViewport.new()
			history_viewport.name = "FogSeenViewport%d" % index
			history_viewport.disable_3d = true
			history_viewport.handle_input_locally = false
			history_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			history_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			history_viewport.transparent_bg = false
			add_child(history_viewport)

			var merge_rect := ColorRect.new()
			merge_rect.name = "MergeRect"
			merge_rect.color = Color.BLACK
			merge_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			history_viewport.add_child(merge_rect)

			var material := ShaderMaterial.new()
			material.shader = HISTORY_SHADER
			merge_rect.material = material

			_history_viewports.append(history_viewport)
			_history_rects.append(merge_rect)
			_history_materials.append(material)

	for viewport in _history_viewports:
		viewport.disable_3d = true
		viewport.handle_input_locally = false
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.transparent_bg = false
	if not _history_viewports.is_empty():
		_ensure_surface_state(SURFACE_FOG_OF_WAR, _history_viewports[_history_present_index])


func _ensure_world_mask_3d() -> void:
	var maze_root := _get_maze_root()
	if maze_root == null:
		return

	if _world_mask_3d == null or not is_instance_valid(_world_mask_3d):
		_world_mask_3d = maze_root.get_node_or_null(WORLD_MASK_3D_NAME) as MeshInstance3D
	if _world_mask_3d == null:
		_world_mask_3d = MeshInstance3D.new()
		_world_mask_3d.name = WORLD_MASK_3D_NAME
		maze_root.add_child(_world_mask_3d)


## PGO-323 PTK-890. A genuinely separate `MeshInstance3D` from `_world_mask_3d`
## (not a `next_pass` on its material) -- `_world_mask_3d` is a dormant legacy
## overlay unconditionally `visible = false` everywhere it's touched in this
## file today (the LIVE visibility-mask darkening path is instead baked into
## the maze's own floor/wall material shaders, see `_apply_source_visibility_material`).
## Chaining sound-light onto that dead mesh's material would resurrect its
## unrelated darkening pass the moment this node needs to be visible. A fresh
## mesh instance costs one draw call and keeps the two concerns fully isolated.
func _ensure_sound_light_world_mask_3d() -> void:
	var maze_root := _get_maze_root()
	if maze_root == null:
		return
	if _sound_light_world_mask_3d == null or not is_instance_valid(_sound_light_world_mask_3d):
		_sound_light_world_mask_3d = maze_root.get_node_or_null(SOUND_LIGHT_WORLD_MASK_3D_NAME) as MeshInstance3D
	if _sound_light_world_mask_3d == null:
		_sound_light_world_mask_3d = MeshInstance3D.new()
		_sound_light_world_mask_3d.name = SOUND_LIGHT_WORLD_MASK_3D_NAME
		maze_root.add_child(_sound_light_world_mask_3d)


func _ensure_wall_knowledge_controller() -> void:
	var main_view := _get_main_maze_view()
	var wall_view := _get_gameplay_wall_maze_view()
	if _wall_knowledge_2d != null and is_instance_valid(_wall_knowledge_2d) \
	and _cell_discovery_2d != null and is_instance_valid(_cell_discovery_2d) \
	and _cell_visibility_2d != null and is_instance_valid(_cell_visibility_2d) \
	and main_view != null \
	and wall_view != null \
	and _wall_knowledge_2d.get("_main_maze_view") == main_view \
	and _wall_knowledge_2d.get("_wall_maze_view") == wall_view:
		return
	if _wall_knowledge_2d == null or not is_instance_valid(_wall_knowledge_2d):
		_wall_knowledge_2d = get_node_or_null(WALL_KNOWLEDGE_2D_NAME) as MazeWallKnowledge2D
	if _wall_knowledge_2d == null:
		_wall_knowledge_2d = MazeWallKnowledge2D.new()
		_wall_knowledge_2d.name = WALL_KNOWLEDGE_2D_NAME
		add_child(_wall_knowledge_2d)
	if _cell_discovery_2d == null or not is_instance_valid(_cell_discovery_2d):
		_cell_discovery_2d = MazeCellDiscovery2DScript.new()
		_cell_discovery_2d.name = CELL_DISCOVERY_2D_NAME
		add_child(_cell_discovery_2d)
		_cell_discovery_2d.cells_changed.connect(_on_discovered_cells_changed)
	if _cell_visibility_2d == null or not is_instance_valid(_cell_visibility_2d):
		_cell_visibility_2d = MazeCellVisibility2DScript.new()
		_cell_visibility_2d.name = CELL_VISIBILITY_2D_NAME
		add_child(_cell_visibility_2d)
	_wall_knowledge_settings_dirty = true
	_configure_cell_discovery()


func _sync_wall_knowledge_settings() -> void:
	if _wall_knowledge_2d == null:
		return
	_wall_knowledge_2d.apply_settings(
		int(wall_fog_mode),
		wall_discovery_delay_frames,
		wall_reveal_speed,
		wall_debug_unknown_alpha
	)
	if _cell_discovery_2d != null:
		_cell_discovery_2d.unmask_cutoff = cell_unmask_cutoff
		_cell_discovery_2d.discover_threshold = cell_discover_threshold
		_cell_discovery_2d.forget_threshold = minf(cell_forget_threshold, cell_discover_threshold)
		_cell_discovery_2d.reduction_cadence_seconds = cell_discovery_cadence_seconds
		_cell_discovery_2d.tap_grid_size = cell_discovery_tap_grid_size
		_cell_discovery_2d.cell_interior_inset = cell_discovery_interior_inset
		_configure_cell_discovery()
	_wall_knowledge_2d.set_views(_get_main_maze_view(), _get_gameplay_wall_maze_view())
	_wall_knowledge_2d.set_force_all_discovered(_force_all_discovered)
	# PGO-129: push the effective (active-granularity) membership derived from the
	# room defs the camera manager published, so wall discovery gates on the active
	# split child rather than raw MazeData. Empty while the effect is off.
	if _wall_knowledge_2d.has_method("set_camera_room_membership"):
		_wall_knowledge_2d.call("set_camera_room_membership", _effective_camera_room_membership())
	if _wall_knowledge_2d.has_method("set_camera_room_discovery_state"):
		_wall_knowledge_2d.call("set_camera_room_discovery_state", _camera_room_mask_enabled, _camera_room_active_id)


## Builds a cell -> sorted room ids map from the currently published camera-room
## defs (the effective leaves the manager sent to set_camera_room_state), or an
## empty map while the effect is disabled so wall knowledge falls back to MazeData.
func _effective_camera_room_membership() -> Dictionary:
	if not _camera_room_mask_enabled:
		return {}
	var membership: Dictionary = {}
	for room_variant in _camera_room_defs:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id := int(room.get("id", -1))
		if room_id < 0:
			continue
		var cells_variant: Variant = room.get("cells", [])
		if not (cells_variant is Array):
			continue
		for cell_variant in (cells_variant as Array):
			if typeof(cell_variant) != TYPE_VECTOR2I:
				continue
			var cell: Vector2i = cell_variant
			var ids: Array = membership.get(cell, [])
			if not ids.has(room_id):
				ids.append(room_id)
			membership[cell] = ids
	for cell_variant in membership.keys():
		var ids: Array = membership[cell_variant]
		ids.sort()
		membership[cell_variant] = ids
	return membership


func _configure_cell_discovery() -> void:
	if _cell_discovery_2d == null or _cell_visibility_2d == null \
	or _maze_data == null or _builder_settings == null:
		return
	var maze_size := Vector2i(int(_maze_data.width), int(_maze_data.height))
	if maze_size.x <= 0 or maze_size.y <= 0:
		return
	# The capture frames slightly more than the maze, so cell -> UV is derived from
	# the live capture rect rather than assuming cell / maze_size.
	var capture_rect := _current_visibility_maze_rect()
	if capture_rect.size.x <= 0.0 or capture_rect.size.y <= 0.0:
		return
	var cell_world := maxf(0.0001, float(_builder_settings.cell_size))
	var cell_uv_step := Vector2(cell_world, cell_world) / capture_rect.size
	var cell_uv_origin := -capture_rect.position / capture_rect.size
	_cell_discovery_2d.configure(self, maze_size, cell_uv_origin, cell_uv_step)
	_cell_visibility_2d.configure(self, maze_size, cell_uv_origin, cell_uv_step)
	# Discovery only publishes transitions, so a rebuilt wall graph has to be
	# resynced against the cells that are already known.
	if _wall_knowledge_2d != null and is_instance_valid(_wall_knowledge_2d):
		_wall_knowledge_2d.set_discovered_cells(_cell_discovery_2d.get_discovered_cells())


func get_cell_discovery() -> MazeCellDiscovery2D:
	return _cell_discovery_2d


func is_maze_cell_discovered(cell: Vector2i) -> bool:
	if _cell_discovery_2d == null or not is_instance_valid(_cell_discovery_2d):
		return false
	return _cell_discovery_2d.is_cell_discovered(cell)


func _on_discovered_cells_changed(discovered: Array, undiscovered: Array) -> void:
	if _wall_knowledge_2d != null and is_instance_valid(_wall_knowledge_2d):
		_wall_knowledge_2d.apply_cell_discovery_changes(discovered, undiscovered)


func debug_get_cell_discovery_metrics() -> Dictionary:
	if _cell_discovery_2d == null or not is_instance_valid(_cell_discovery_2d):
		return {}
	return _cell_discovery_2d.debug_get_metrics()


func get_cell_visibility() -> Node:
	return _cell_visibility_2d


func debug_get_cell_visibility_metrics() -> Dictionary:
	if _cell_visibility_2d == null or not is_instance_valid(_cell_visibility_2d):
		return {}
	return _cell_visibility_2d.debug_get_metrics()

func _ensure_mask_overlays() -> void:
	_ensure_world_mask_3d()
	if _world_mask_3d_material == null:
		_world_mask_3d_material = ShaderMaterial.new()
		_world_mask_3d_material.shader = WORLD_MASK_3D_SHADER
	if _world_mask_3d != null:
		_world_mask_3d.material_override = _world_mask_3d_material
		_world_mask_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world_mask_3d.layers = 1
		_world_mask_3d.visible = false

	if _world_mask_2d_main_material == null:
		_world_mask_2d_main_material = ShaderMaterial.new()
		_world_mask_2d_main_material.shader = WORLD_MASK_2D_SHADER
	if _world_mask_2d_walls_material == null:
		_world_mask_2d_walls_material = ShaderMaterial.new()
		_world_mask_2d_walls_material.shader = WORLD_MASK_2D_SHADER

	var main_view := _get_main_maze_view()
	if main_view != null:
		_world_mask_2d_main = _ensure_mask_sprite(main_view, WORLD_MASK_2D_MAIN_NAME, _world_mask_2d_main_material)

	var walls_view := _get_gameplay_wall_maze_view()
	if walls_view != null:
		_world_mask_2d_walls = _ensure_mask_sprite(walls_view, WORLD_MASK_2D_WALLS_NAME, _world_mask_2d_walls_material)

	_ensure_sound_light_world_mask_3d()
	if _sound_light_world_mask_3d_material == null:
		_sound_light_world_mask_3d_material = ShaderMaterial.new()
		_sound_light_world_mask_3d_material.shader = SOUND_LIGHT_WORLD_MASK_3D_SHADER
	if _sound_light_world_mask_3d != null:
		_sound_light_world_mask_3d.material_override = _sound_light_world_mask_3d_material
		_sound_light_world_mask_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sound_light_world_mask_3d.layers = 1
		_sound_light_world_mask_3d.visible = false

	if _sound_light_world_mask_2d_main_material == null:
		_sound_light_world_mask_2d_main_material = ShaderMaterial.new()
		_sound_light_world_mask_2d_main_material.shader = SOUND_LIGHT_WORLD_MASK_2D_SHADER
	if _sound_light_world_mask_2d_walls_material == null:
		_sound_light_world_mask_2d_walls_material = ShaderMaterial.new()
		_sound_light_world_mask_2d_walls_material.shader = SOUND_LIGHT_WORLD_MASK_2D_SHADER
	if main_view != null:
		_sound_light_world_mask_2d_main = _ensure_mask_sprite(
			main_view, SOUND_LIGHT_WORLD_MASK_2D_MAIN_NAME, _sound_light_world_mask_2d_main_material, 4096
		)
	if walls_view != null:
		_sound_light_world_mask_2d_walls = _ensure_mask_sprite(
			walls_view, SOUND_LIGHT_WORLD_MASK_2D_WALLS_NAME, _sound_light_world_mask_2d_walls_material, 4096
		)


func _ensure_mask_sprite(parent: Node2D, node_name: String, material: ShaderMaterial, z_index_value: int = 4096) -> Sprite2D:
	var sprite := parent.get_node_or_null(node_name) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = node_name
		sprite.centered = false
		sprite.z_as_relative = false
		sprite.z_index = z_index_value
		parent.add_child(sprite)
	sprite.material = material
	sprite.visible = false
	return sprite


func _sync_capture_geometry() -> void:
	_ensure_world_mask_3d()
	_ensure_sound_light_world_mask_3d()
	var source_floor := _source_floor_mesh
	if source_floor != null:
		if _world_mask_3d != null:
			_world_mask_3d.mesh = source_floor.mesh
			var mask_transform := source_floor.transform
			mask_transform.origin.y += maxf(0.0, float(_builder_settings.wall_height)) + 0.05
			_world_mask_3d.transform = mask_transform
			_world_mask_3d.layers = 1
			_world_mask_3d.visible = false
		if _sound_light_world_mask_3d != null:
			_sound_light_world_mask_3d.mesh = source_floor.mesh
			var sound_light_transform := source_floor.transform
			# Slightly above the (dormant) visibility-mask overlay's own offset so the
			# two never coincide exactly, in case a future change makes both visible
			# at once -- avoids z-fighting on two unshaded coplanar quads.
			sound_light_transform.origin.y += maxf(0.0, float(_builder_settings.wall_height)) + 0.06
			_sound_light_world_mask_3d.transform = sound_light_transform
			_sound_light_world_mask_3d.layers = 1


func _refresh_capture_layout() -> void:
	if _maze_data == null or _builder_settings == null:
		return

	# 3D walls are centred on the maze grid lines, so the visible maze extends
	# half a wall thickness beyond the cell grid on every edge. The ordinary 2D
	# projection textures use these same bounds; fog masks must do so too or their
	# wall shadows are stretched across a differently-sized texture.
	_capture_rect_2d = _wall_inclusive_maze_rect()
	if _capture_root_2d != null:
		var viewport_pixels := Vector2(_current_viewport.size) if _current_viewport != null else Vector2.ONE
		var pixels_per_world_unit := viewport_pixels / _capture_rect_2d.size
		_capture_root_2d.position = -_capture_rect_2d.position * pixels_per_world_unit
		_capture_root_2d.scale = pixels_per_world_unit
	if _capture_receiver_2d != null:
		_capture_receiver_2d.position = _capture_rect_2d.position
		_capture_receiver_2d.size = _capture_rect_2d.size


func _resize_capture_targets() -> void:
	if _maze_data == null or _builder_settings == null:
		return
	var current_size := _render_mask_capture_size(SURFACE_CURRENT_VISIBILITY)
	var history_size := _render_mask_capture_size(SURFACE_FOG_OF_WAR)

	if _current_viewport != null and _current_viewport.size != current_size:
		_current_viewport.size = current_size
	for viewport in _history_viewports:
		if viewport.size != history_size:
			viewport.size = history_size

	_black_texture = _build_solid_texture(current_size, Color.BLACK)
	_white_texture = _build_solid_texture(current_size, Color.WHITE)
	_invalidate_view_distance_mask()
	_rebuild_camera_room_masks(_camera_room_defs)
	_capture_camera_dirty = true
	_mask_overlays_dirty = true
	_mask_textures_dirty = true
	_visibility_material_params_dirty = true
	_bump_render_mask_texture_revision(SURFACE_FOG_OF_WAR)
	_bump_render_mask_texture_revision(SURFACE_CURRENT_VISIBILITY)
	_invalidate_surface(SURFACE_CURRENT_VISIBILITY, &"resize_capture_targets")
	_invalidate_surface(SURFACE_FOG_OF_WAR, &"resize_capture_targets")


func _wall_inclusive_maze_rect() -> Rect2:
	if _maze_data == null or _builder_settings == null:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var cell_world := maxf(0.0001, float(_builder_settings.cell_size))
	var half_wall := maxf(0.0, float(_builder_settings.wall_thickness)) * 0.5
	return Rect2(
		Vector2(-half_wall, -half_wall),
		Vector2(
			float(_maze_data.width) * cell_world + half_wall * 2.0,
			float(_maze_data.height) * cell_world + half_wall * 2.0
		)
	)


func _reset_history() -> void:
	_history_present_index = 0
	_history_initialized = false
	for viewport in _history_viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for material in _history_materials:
		material.set_shader_parameter("current_tex", _black_texture)
		material.set_shader_parameter("previous_tex", _black_texture)

	if not _history_viewports.is_empty():
		_history_materials[0].set_shader_parameter("current_tex", _black_texture)
		_history_materials[0].set_shader_parameter("previous_tex", _black_texture)
		_history_viewports[0].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_ensure_surface_state(SURFACE_FOG_OF_WAR, _history_viewports[0])
	_invalidate_surface(SURFACE_FOG_OF_WAR, &"reset_history")
	_history_reset_pending_full_dirty = true
	_history_recency_steps = 0
	_forget_threshold = 0.0
	_clear_memory_decay_shader_parameters()
	_pending_history_dirty_uv_rects.clear()
	_mask_textures_dirty = true
	_visibility_material_params_dirty = true


func _advance_history_once() -> bool:
	if _current_viewport == null or _history_viewports.size() < 2 or _black_texture == null:
		return false

	var next_index := 1 - _history_present_index
	var previous_texture: Texture2D = _black_texture
	if _history_initialized:
		previous_texture = _history_viewports[_history_present_index].get_texture()

	var current_texture := _current_viewport.get_texture()
	# Spread the retained gradient evenly across one more step so the newest memory
	# stays at 1.0 and the oldest approaches, but never reaches, 0.0.
	var recency_rescale := 1.0
	if _history_recency_steps > 0:
		recency_rescale = float(_history_recency_steps) / float(_history_recency_steps + 1)
	_history_recency_steps += 1
	_forget_threshold *= recency_rescale
	_history_materials[next_index].set_shader_parameter("current_tex", current_texture)
	_history_materials[next_index].set_shader_parameter("previous_tex", previous_texture)
	_history_materials[next_index].set_shader_parameter("recency_rescale", recency_rescale)
	_history_materials[next_index].set_shader_parameter("forget_threshold", _forget_threshold)
	_history_materials[next_index].set_shader_parameter("forget_soft_edge", _memory_decay_controller.get_frontier_soft_edge() if _memory_decay_controller != null else 0.0)

	_history_viewports[_history_present_index].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_history_viewports[next_index].render_target_update_mode = SubViewport.UPDATE_ONCE

	_history_present_index = next_index
	_history_initialized = true
	_ensure_surface_state(SURFACE_FOG_OF_WAR, _history_viewports[_history_present_index])
	var state: Dictionary = _surface_states.get(SURFACE_FOG_OF_WAR, {})
	state["dirty"] = false
	state["refresh_request_count"] = int(state.get("refresh_request_count", 0)) + 1
	state["last_dirty_reason"] = "history_advanced"
	_surface_states[SURFACE_FOG_OF_WAR] = state
	_mask_textures_dirty = true
	_visibility_material_params_dirty = true
	var dirty_rects: Array[Rect2] = []
	if _history_reset_pending_full_dirty:
		dirty_rects.append(Rect2(Vector2.ZERO, Vector2.ONE))
	else:
		dirty_rects = _coalesced_history_dirty_uv_rects()
	_history_reset_pending_full_dirty = false
	_pending_history_dirty_uv_rects.clear()
	if _decay_history_pass_pending:
		_decay_gpu_pass_count += 1
		_decay_history_pass_pending = false
	_history_dirty_publication_count += 1
	_history_dirty_published_region_count += dirty_rects.size()
	for dirty_rect in dirty_rects:
		_history_dirty_published_area += dirty_rect.get_area()
	fog_history_surface_updated.emit(dirty_rects)
	return true


func _coalesced_history_dirty_uv_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in _pending_history_dirty_uv_rects:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var merged := false
		for index in result.size():
			if _history_dirty_rects_can_coalesce(result[index], rect):
				result[index] = result[index].merge(rect)
				merged = true
				break
		if not merged:
			result.append(rect)
	return result


func _history_dirty_rects_can_coalesce(first: Rect2, second: Rect2) -> bool:
	if first.intersects(second):
		return true
	var tolerance := 0.002
	var same_rows := (
		is_equal_approx(first.position.y, second.position.y)
		and is_equal_approx(first.size.y, second.size.y)
		and first.position.x <= second.end.x + tolerance
		and second.position.x <= first.end.x + tolerance
	)
	if same_rows:
		return true
	return (
		is_equal_approx(first.position.x, second.position.x)
		and is_equal_approx(first.size.x, second.size.x)
		and first.position.y <= second.end.y + tolerance
		and second.position.y <= first.end.y + tolerance
	)


func _sync_mask_overlays() -> void:
	if _maze_data == null:
		return
	_sync_2d_mask_sprite(_world_mask_2d_main, false)
	_sync_2d_mask_sprite(_world_mask_2d_walls, false)
	if _world_mask_3d != null:
		_world_mask_3d.visible = false
	if _world_mask_3d_material != null:
		_world_mask_3d_material.set_shader_parameter("opacity", mask_3d_opacity)
	if _world_mask_2d_main_material != null:
		_world_mask_2d_main_material.set_shader_parameter("opacity", mask_2d_opacity)
		_apply_camera_room_mask_material_params(_world_mask_2d_main_material)
	if _world_mask_2d_walls_material != null:
		_world_mask_2d_walls_material.set_shader_parameter("opacity", mask_2d_opacity)
		_apply_camera_room_mask_material_params(_world_mask_2d_walls_material)

	# The additive overlay is only ever visible while the field is actually
	# presenting -- `is_presenting()` is the same exact-bypass contract
	# `get_output_texture(fallback)` already relies on, so "off/headless/no
	# frame yet" all correctly collapse to invisible rather than an empty-black
	# additive layer (harmless, but a wasted draw call every frame).
	var sound_light_presenting := _sound_light_enabled \
		and _sound_light_field_simulation != null \
		and is_instance_valid(_sound_light_field_simulation) \
		and _sound_light_field_simulation.is_presenting()
	_sync_2d_mask_sprite(_sound_light_world_mask_2d_main, sound_light_presenting)
	_sync_2d_mask_sprite(_sound_light_world_mask_2d_walls, sound_light_presenting)
	if _sound_light_world_mask_3d != null:
		_sound_light_world_mask_3d.visible = sound_light_presenting


func _sync_2d_mask_sprite(sprite: Sprite2D, enabled: bool) -> void:
	if sprite == null or _maze_data == null:
		return
	var maze_view := sprite.get_parent() as MazeView
	if maze_view == null:
		return
	var maze_px := Vector2(
		float(_maze_data.width) * float(maze_view.cell_size),
		float(_maze_data.height) * float(maze_view.cell_size)
	)
	var tex_size := Vector2.ONE
	if _current_viewport != null and _current_viewport.size.x > 0 and _current_viewport.size.y > 0:
		tex_size = Vector2(_current_viewport.size)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(
		maze_px.x / maxf(1.0, tex_size.x),
		maze_px.y / maxf(1.0, tex_size.y)
	)
	sprite.visible = enabled


func _update_mask_textures() -> void:
	var map_mask_tex := _game_world_mask_texture
	if map_mask_tex == null:
		map_mask_tex = _black_texture
	var world_mask_3d_tex := _render_mask_texture(&"game_world_animated")
	if world_mask_3d_tex == null:
		world_mask_3d_tex = _black_texture
	if _world_mask_2d_main != null:
		_world_mask_2d_main.texture = null
	if _world_mask_2d_walls != null:
		_world_mask_2d_walls.texture = null
	if _world_mask_2d_main_material != null:
		_world_mask_2d_main_material.set_shader_parameter("mask_tex", map_mask_tex)
		_apply_camera_room_mask_material_params(_world_mask_2d_main_material)
	if _world_mask_2d_walls_material != null:
		_world_mask_2d_walls_material.set_shader_parameter("mask_tex", map_mask_tex)
		_apply_camera_room_mask_material_params(_world_mask_2d_walls_material)
	if _world_mask_3d_material != null:
		_world_mask_3d_material.set_shader_parameter("mask_tex", world_mask_3d_tex)

	var sound_light_tex: Texture2D = _black_texture
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		sound_light_tex = _sound_light_field_simulation.get_output_texture(_black_texture)
	if _sound_light_world_mask_3d_material != null:
		_sound_light_world_mask_3d_material.set_shader_parameter("sound_light_tex", sound_light_tex)
	if _sound_light_world_mask_2d_main_material != null:
		_sound_light_world_mask_2d_main_material.set_shader_parameter("sound_light_tex", sound_light_tex)
	if _sound_light_world_mask_2d_walls_material != null:
		_sound_light_world_mask_2d_walls_material.set_shader_parameter("sound_light_tex", sound_light_tex)


## Composition order. `game_world` is the substrate the simulation reads and
## the `game_world`/`game_world_animated` derived masks republish, so the phases are
## strictly ordered: compose the substrate, tick the simulation, then compose the
## render layers. The flat `_RENDER_MASK_TARGETS` loop this replaced could not
## express that -- `game_world` sorts last, and the simulation ran after the whole
## pass -- so any layer routed to a derived mask sampled a field two hops stale.
func _update_render_mask_outputs_if_needed(delta: float) -> void:
	var outputs_dirty := _render_mask_outputs_dirty
	_render_mask_outputs_dirty = false
	if outputs_dirty:
		_compose_substrate_mask_output()
	_update_visibility_mask_simulation_if_needed(delta)
	_update_sound_light_field_simulation_if_needed(delta)
	var derived_changed := _refresh_derived_mask_revisions()
	if outputs_dirty or derived_changed:
		_compose_render_layer_mask_outputs()


## Publishes the live revision of each derived mask and reports whether either
## moved. The derived `game_world` mask is the substrate composite's own revision.
##
## `game_world_animated` cannot simply forward whichever source it is presenting
## from: the substrate revision and the simulation's dispatch count are
## independent counters, so a passthrough/presenting transition could land on
## the same number twice and read as "unchanged" while the texture changed. It
## therefore gets its own monotonic counter, bumped whenever the resolved
## (presenting, source revision) pair differs from the last published one.
func _refresh_derived_mask_revisions() -> bool:
	var presenting := _visibility_mask_simulation != null \
		and is_instance_valid(_visibility_mask_simulation) \
		and _visibility_mask_simulation.is_presenting()
	var animated_source := _visibility_mask_simulation.get_present_revision() if presenting else _game_world_mask_revision
	var animated_key := "%d:%d" % [1 if presenting else 0, animated_source]
	var changed := false
	if int(_render_mask_texture_revisions.get(&"game_world", -1)) != _game_world_mask_revision:
		_render_mask_texture_revisions[&"game_world"] = _game_world_mask_revision
		changed = true
	if animated_key != _animated_mask_source_key:
		_animated_mask_source_key = animated_key
		_animated_mask_revision += 1
		_render_mask_texture_revisions[&"game_world_animated"] = _animated_mask_revision
		changed = true
	return changed


## The compositor shader carries exactly four mask slots (`mask_0..mask_3`).
## Six mask names are registered now that PGO-101 added the two derived masks, so
## an over-subscribed target silently drops the extras. Routing a layer to
## `game_world`/`game_world_animated` is meant to REPLACE the captured masks on that
## layer, not stack on top of them; say so once per target rather than compose a
## quietly wrong picture. Deduped because this sits on the compose path.
func _warn_once_if_mask_slots_over_subscribed(target: StringName, contribution_count: int) -> void:
	if contribution_count <= _RENDER_MASK_COMPOSITOR_SLOTS:
		_over_subscribed_mask_targets.erase(target)
		return
	if _over_subscribed_mask_targets.has(target):
		return
	_over_subscribed_mask_targets[target] = true
	var message := "Render-mask target '%s' has %d active masks but the compositor has %d slots; the extras are dropped. Set the captured masks off on this target when routing it to a derived mask." % [
		String(target), contribution_count, _RENDER_MASK_COMPOSITOR_SLOTS
	]
	Console.try_log(func() -> Array: return [message], LogLevel.WARN)


func _compose_substrate_mask_output() -> void:
	FrameSampleProfiler.begin(&"fog/compose_substrate_mask_output")
	_ensure_render_mask_compositor()
	if _render_mask_compositor == null or _current_viewport == null \
	or not _render_mask_target_has_active_consumer(&"game_world"):
		FrameSampleProfiler.end(&"fog/compose_substrate_mask_output")
		return
	var size := _current_viewport.size
	var contributions := _render_mask_contributions_for_target(&"game_world")
	# `game_world` has no render layer and therefore no consumer-demanded
	# coverage, so it stays on the full capture-viewport composite.
	FrameSampleProfiler.count(&"fog/mask_compose_pass/game_world")
	FrameSampleProfiler.count(&"fog/mask_compose_pixels/game_world", size.x * size.y)
	_game_world_mask_texture = _render_mask_compositor.compose(&"game_world", size, contributions, _black_texture)
	# The animated visibility-mask simulation keys off this revision.
	_game_world_mask_revision += 1
	_visibility_material_params_dirty = true
	FrameSampleProfiler.end(&"fog/compose_substrate_mask_output")


func _compose_render_layer_mask_outputs() -> void:
	FrameSampleProfiler.begin(&"fog/update_render_mask_outputs_if_needed")
	FrameSampleProfiler.count(&"fog/update_render_mask_outputs_if_needed")
	_ensure_render_mask_compositor()
	if _render_mask_compositor == null or _current_viewport == null:
		FrameSampleProfiler.end(&"fog/update_render_mask_outputs_if_needed")
		return
	var size := _current_viewport.size
	var renderer := _get_two_d_world_renderer()
	for target in _RENDER_MASK_TARGETS:
		if target == &"game_world":
			continue
		if not _render_mask_target_has_active_consumer(target):
			if renderer != null:
				renderer.set_render_layer_output_override(target, null)
				_render_mask_compositor.clear_target(target)
			continue
		FrameSampleProfiler.begin(&"fog/mask_outputs/contributions")
		var contributions := _render_mask_contributions_for_target(target)
		FrameSampleProfiler.end(&"fog/mask_outputs/contributions")
		if renderer == null:
			continue
		_warn_once_if_mask_slots_over_subscribed(target, contributions.size())
		if contributions.is_empty():
			renderer.set_render_layer_output_override(target, null)
			_render_mask_compositor.clear_target(target)
			continue
		# PGO-96 stage ④: the mask textures (mask_0..mask_3) are always full-
		# maze resolution, but `target`'s own raw texture can now cover a
		# consumer-demanded sub-rect at its own density (see
		# `TwoDWorldRenderer.get_render_layer_coverage`). Compose at the
		# layer's own coverage.texture_size (not this fog viewport's size) so
		# the override texture matches the raw texture dimensions, and give
		# the shader `target`'s world_rect as a fraction of the full maze so
		# it can remap the full-maze-resolution masks into that sub-rect.
		FrameSampleProfiler.begin(&"fog/mask_outputs/coverage")
		var target_coverage := renderer.get_render_layer_coverage(target)
		FrameSampleProfiler.end(&"fog/mask_outputs/coverage")
		var target_size: Vector2i = target_coverage.get("texture_size", size)
		# UV remap is against the produced texture, so it must use the CAPTURED
		# region (wall-inclusive), not the cell-grid rect. See the coverage
		# contract doc on TwoDWorldRenderer.get_render_layer_coverage.
		var target_world_rect: Rect2 = target_coverage.get("capture_rect", target_coverage.get("world_rect", Rect2(Vector2.ZERO, renderer.get_maze_pixel_size())))
		var maze_pixel_size := renderer.get_maze_pixel_size()
		var uv_offset := Vector2.ZERO
		var uv_scale := Vector2.ONE
		if maze_pixel_size.x > 0.0 and maze_pixel_size.y > 0.0:
			uv_offset = target_world_rect.position / maze_pixel_size
			uv_scale = target_world_rect.size / maze_pixel_size
		FrameSampleProfiler.begin(&"fog/mask_outputs/raw_texture")
		var source := renderer.get_raw_render_layer_texture(target)
		FrameSampleProfiler.end(&"fog/mask_outputs/raw_texture")
		FrameSampleProfiler.begin(&"fog/mask_outputs/source_revision")
		var source_revision := renderer.get_raw_render_layer_texture_revision(target)
		FrameSampleProfiler.end(&"fog/mask_outputs/source_revision")
		FrameSampleProfiler.count(StringName("fog/mask_compose_pass/%s" % String(target)))
		FrameSampleProfiler.count(StringName("fog/mask_compose_pixels/%s" % String(target)), target_size.x * target_size.y)
		FrameSampleProfiler.begin(&"fog/mask_outputs/compose")
		var output: Texture2D = _render_mask_compositor.compose(
			target, target_size, contributions, _black_texture, source, source_revision, uv_offset, uv_scale, true
		)
		FrameSampleProfiler.end(&"fog/mask_outputs/compose")
		FrameSampleProfiler.begin(&"fog/mask_outputs/publish")
		renderer.set_render_layer_output_override(target, output)
		var mask_snapshot: Dictionary = _render_mask_compositor.debug_get_snapshot(target)
		renderer.note_render_layer_mask_composition(target, int(mask_snapshot.get("revision", 0)))
		FrameSampleProfiler.end(&"fog/mask_outputs/publish")
	FrameSampleProfiler.end(&"fog/update_render_mask_outputs_if_needed")


func _ensure_render_mask_compositor() -> void:
	if _render_mask_compositor != null and is_instance_valid(_render_mask_compositor):
		return
	_render_mask_compositor = RenderMaskCompositorScript.new()
	_render_mask_compositor.name = "RenderMaskCompositor"
	add_child(_render_mask_compositor)


func _ensure_visibility_mask_simulation() -> void:
	if _visibility_mask_simulation == null or not is_instance_valid(_visibility_mask_simulation):
		_visibility_mask_simulation = OrganicVisibilityMaskSimulationScript.new()
		_visibility_mask_simulation.name = "OrganicVisibilityMaskSimulation"
		add_child(_visibility_mask_simulation)
		_visibility_mask_simulation.configure(_animated_visibility_mask_config)
		_visibility_mask_simulation.set_debug_view_enabled(_animated_mask_debug_view)
	if _packed_visibility_capture == null or not is_instance_valid(_packed_visibility_capture):
		_packed_visibility_capture = PackedVisibilityCaptureScript.new()
		_packed_visibility_capture.name = "PackedVisibilityCapture"
		add_child(_packed_visibility_capture)


## Detaches the simulation owner and its auxiliary capture, then frees them.
## `remove_child` runs `_exit_tree` synchronously -- which is where both nodes
## release their GPU resources -- and makes the node invisible to a lookup on
## the same frame, while the object itself is destroyed on the deferred queue so
## a dispatch recorded this frame is never freed out from under the render thread.
func _release_visibility_mask_simulation() -> void:
	for node_variant in [_visibility_mask_simulation, _packed_visibility_capture]:
		var node := node_variant as Node
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() == self:
			remove_child(node)
		node.queue_free()
	_visibility_mask_simulation = null
	_packed_visibility_capture = null
	_animated_mask_source_key = ""


func _ensure_sound_light_field_simulation() -> void:
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		return
	_sound_light_field_simulation = SoundLightFieldSimulationScript.new()
	_sound_light_field_simulation.name = "SoundLightFieldSimulation"
	add_child(_sound_light_field_simulation)
	_sound_light_field_simulation.configure(_sound_light_config)
	if _sound_light_wall_lane_capture == null:
		_sound_light_wall_lane_capture = SoundLightWallLaneCaptureScript.new()


## Same deferred-free discipline as `_release_visibility_mask_simulation`: a
## dispatch already recorded on the render thread this frame must not be freed
## out from under it.
func _release_sound_light_field_simulation() -> void:
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		if _sound_light_field_simulation.get_parent() == self:
			remove_child(_sound_light_field_simulation)
		_sound_light_field_simulation.queue_free()
	_sound_light_field_simulation = null
	_sound_light_wall_lane_capture = null


## Advances PGO-101's organic mask. The packed auxiliary lanes are repainted
## first so the simulation never ticks against a capture that disagrees with the
## substrate it was composed from.
func _update_visibility_mask_simulation_if_needed(delta: float) -> void:
	if not _animated_visibility_mask_enabled or _game_world_mask_texture == null or _current_viewport == null:
		return
	FrameSampleProfiler.begin(&"fog/animated_visibility_mask")
	_ensure_visibility_mask_simulation()
	var capture_rect := _current_visibility_maze_rect()
	_packed_visibility_capture.configure(_current_viewport.size, capture_rect)
	_packed_visibility_capture.sync(
		_live_reveal_sources(),
		_live_fog_blockers(),
		_animated_mask_seed_radius_world(),
		_maze_pixels_to_world_scale()
	)
	var cell_world := maxf(0.0001, float(_builder_settings.cell_size)) if _builder_settings != null else 1.0
	_visibility_mask_simulation.set_inputs(
		_game_world_mask_texture,
		_packed_visibility_capture.get_texture(),
		_game_world_mask_revision + _packed_visibility_capture.get_revision(),
		capture_rect.size / cell_world
	)
	_visibility_mask_simulation.update(delta)
	_visibility_material_params_dirty = true
	FrameSampleProfiler.end(&"fog/animated_visibility_mask")


## PGO-323 PTK-890. The wall lane is resynced first, same ordering discipline as
## the mask's own packed-capture-before-`set_inputs` above: the simulation must
## never tick against a lane that disagrees with the wall graph it was painted
## from. Degrades to zero emitters (never an error) when no
## `SoundLightEmitterSource` is present in this maze's scene tree.
func _update_sound_light_field_simulation_if_needed(delta: float) -> void:
	if not _sound_light_enabled or _maze_data == null or _wall_knowledge_2d == null or _builder_settings == null:
		return
	FrameSampleProfiler.begin(&"fog/sound_light_field")
	_ensure_sound_light_field_simulation()
	var size_cells := Vector2i(maxi(1, int(_maze_data.width)), maxi(1, int(_maze_data.height)))
	var pixels_per_cell := maxf(1.0, float(int(_sound_light_config.get("simulation_pixels_per_cell", 8))))
	var sim_size := Vector2i(
		clampi(int(round(float(size_cells.x) * pixels_per_cell)), SoundLightFieldSimulationScript.MIN_SIM_AXIS, SoundLightFieldSimulationScript.MAX_SIM_AXIS),
		clampi(int(round(float(size_cells.y) * pixels_per_cell)), SoundLightFieldSimulationScript.MIN_SIM_AXIS, SoundLightFieldSimulationScript.MAX_SIM_AXIS)
	)
	_sound_light_wall_lane_capture.configure(sim_size, Vector2i.ZERO, size_cells, pixels_per_cell)
	_sound_light_wall_lane_capture.sync(_wall_knowledge_2d)
	# PGO-334: the frame handed to the simulation must be the one the wall lane
	# was just painted in -- cell (0,0) at texel (0,0), in unrotated maze-LOCAL
	# PIXELS, because that is the space `SoundLightEmitterSource` resolves each
	# voice into. It used to be handed `_current_visibility_maze_rect().position`
	# and `_builder_settings.cell_size`, which belong to the 3D world-unit capture
	# frame (1.75 world units per cell at HEAD, against 56 maze pixels): a 32x
	# scale error that put every emitter far off the simulation grid, with only
	# the then-enormous seed radius keeping anything on screen at all. That is
	# the real mechanism of the level-wide wash, underneath the radius itself.
	_sound_light_field_simulation.set_inputs(
		_sound_light_wall_lane_capture.get_texture(),
		Vector2(size_cells),
		Vector2.ZERO,
		maxf(0.0001, _wall_knowledge_2d.acoustic_cell_size_px())
	)
	_sound_light_field_simulation.set_emitters(_live_sound_light_emitters())
	_sound_light_field_simulation.update(delta)
	# Both textures AND overlay visibility need to re-check every ticking frame
	# -- `is_presenting()` can flip true mid-run (the simulation's own two-frame
	# warm-up) with no other unrelated dirty event to piggyback on.
	_mask_textures_dirty = true
	_mask_overlays_dirty = true
	FrameSampleProfiler.end(&"fog/sound_light_field")


## Resolved lazily (never cached across a maze reload) via `EMITTER_SOURCE_GROUP`
## -- `SoundLightEmitterSource` is a sibling under `MazeMain`, not a descendant
## of this manager, so no ancestor/child lookup can find it.
func _live_sound_light_emitters() -> Array[Dictionary]:
	if _sound_light_emitter_source == null or not is_instance_valid(_sound_light_emitter_source):
		if get_tree() == null:
			return []
		_sound_light_emitter_source = get_tree().get_first_node_in_group(SoundLightEmitterSourceScript.EMITTER_SOURCE_GROUP)
	if _sound_light_emitter_source == null or not _sound_light_emitter_source.has_method("get_emitters"):
		return []
	return _sound_light_emitter_source.call("get_emitters")


## PGO-323 PTK-889/PTK-892's test-facing seam: the whole live wiring state in
## one call, so an integration test can assert convergence/presentation/overlay
## behaviour through the real `MazeMain` plumbing without reaching into private
## fields. Never used by the runtime path itself.
func debug_get_sound_light_snapshot() -> Dictionary:
	var simulation_snapshot: Dictionary = {}
	var presenting := false
	if _sound_light_field_simulation != null and is_instance_valid(_sound_light_field_simulation):
		simulation_snapshot = _sound_light_field_simulation.debug_get_snapshot()
		presenting = _sound_light_field_simulation.is_presenting()
	return {
		"enabled": _sound_light_enabled,
		"simulation": simulation_snapshot,
		"presenting": presenting,
		"emitter_source_resolved": _sound_light_emitter_source != null and is_instance_valid(_sound_light_emitter_source),
		"live_emitter_count": _live_sound_light_emitters().size(),
		"overlay_3d_visible": _sound_light_world_mask_3d != null and _sound_light_world_mask_3d.visible,
	}


func get_sound_light_field_simulation() -> Node:
	return _sound_light_field_simulation


func _live_reveal_sources() -> Array:
	var sources: Array = []
	for entry_variant in _reveal_sources.values():
		var source := (entry_variant as Dictionary).get("source") as Node
		if source != null and is_instance_valid(source):
			sources.append(source)
	return sources


func _live_fog_blockers() -> Array:
	var blockers: Array = []
	for blocker_variant in _fog_blockers.values():
		var blocker := blocker_variant as Node
		if blocker != null and is_instance_valid(blocker):
			blockers.append(blocker)
	return blockers


## The seed radius, authored in maze cells, expressed in the maze world units
## the packed capture canvas is drawn in.
func _animated_mask_seed_radius_world() -> float:
	var cell_world := maxf(0.0001, float(_builder_settings.cell_size)) if _builder_settings != null else 1.0
	return maxf(0.0, float(_animated_visibility_mask_config.get("seed_radius_cells", 0.18))) * cell_world


## Restarts the presentation-only animated mask from a clean state without
## affecting any gameplay read. Called for maze loads, teleports and fog resets.
func seed_animated_visibility_mask(_defer_until_next_target: bool = false) -> void:
	if not _animated_visibility_mask_enabled:
		return
	_ensure_visibility_mask_simulation()
	_visibility_mask_simulation.request_reset()
	_visibility_material_params_dirty = true


## Plants a stable nucleus in every permitted-substrate island no active seed or
## valid claim can reach. Manual only: no ordinary `game_world` revision reaches
## it, and this is the only path in the feature that reads back from the GPU.
func seed_visibility_mask_islands() -> Dictionary:
	if not _animated_visibility_mask_enabled:
		return {"ok": false, "reason": "disabled"}
	_ensure_visibility_mask_simulation()
	return _visibility_mask_simulation.seed_islands()


func set_animated_visibility_mask_debug_view(enabled: bool) -> void:
	_animated_mask_debug_view = enabled
	if _visibility_mask_simulation != null and is_instance_valid(_visibility_mask_simulation):
		_visibility_mask_simulation.set_debug_view_enabled(enabled)


func get_animated_visibility_mask_debug_view() -> bool:
	return _animated_mask_debug_view


## Resamples the unconsumed game_walls layer into the current game-world mask coordinate space for PGO-101.
func get_walls_in_mask_space_texture() -> Texture2D:
	var renderer := _get_two_d_world_renderer()
	if renderer == null or _game_world_mask_texture == null:
		return null
	var walls_texture: Texture2D = renderer.get_inworld_walls_texture()
	if walls_texture == null:
		return null
	if _wall_mask_resampler == null or not is_instance_valid(_wall_mask_resampler):
		_wall_mask_resampler = WallMaskResamplerScript.new()
		_wall_mask_resampler.name = "WallMaskResampler"
		add_child(_wall_mask_resampler)
	var snapshot: Dictionary = renderer.debug_get_surface_snapshot(&"game_walls")
	return _wall_mask_resampler.resample(
		walls_texture,
		_game_world_mask_texture.get_size(),
		renderer.get_world_rotation(),
		int(snapshot.get("refresh_request_count", 0))
	)


func _render_mask_contributions_for_target(target: StringName) -> Array[Dictionary]:
	var contributions: Array[Dictionary] = []
	var renderer := _bound_two_d_world_renderer if _bound_two_d_world_renderer != null else _get_two_d_world_renderer()
	for mask_name in _RENDER_MASK_NAMES:
		# `game_world` IS the composite the derived masks republish, so letting
		# one contribute back into it would feed the simulation its own output.
		# The state variables still exist for schema and claim uniformity; this
		# is the single place their `game_world` mode is refused.
		if target == &"game_world" and _RENDER_MASK_DERIVED_NAMES.has(mask_name):
			continue
		if target != &"game_world" and renderer != null:
			var object_layer_key := renderer.get_render_mask_object_layer_key(mask_name)
			if object_layer_key != &"" and renderer.render_layer_has_object_layer(target, object_layer_key):
				continue
		var path := SharedStateKeys.render_mask_path(String(mask_name), String(target))
		var mode := String(_render_mask_modes.get(path, "off"))
		if not RenderMaskCompositionScript.mode_is_active(mode):
			continue
		var texture := _render_mask_texture(mask_name)
		if texture == null:
			continue
		contributions.append({
			"mask": mask_name,
			"texture": texture,
			"mode": mode,
			"revision": int(_render_mask_texture_revisions.get(mask_name, 0)),
		})
	return contributions


func _render_mask_texture(mask_name: StringName) -> Texture2D:
	match mask_name:
		&"fog_of_war":
			return _history_viewports[_history_present_index].get_texture() if not _history_viewports.is_empty() else _black_texture
		&"current_visibility":
			return _current_viewport.get_texture() if _current_viewport != null else _black_texture
		&"view_distance":
			return _view_distance_viewport.get_texture() if _view_distance_mask_valid and _view_distance_viewport != null else null
		&"camera_rooms":
			return _camera_room_composite_viewport.get_texture() if _camera_room_composite_valid and _camera_room_composite_viewport != null else null
		&"game_world":
			return _game_world_mask_texture
		&"game_world_animated":
			# Falls back to the raw substrate rather than to null, so a layer
			# routed here keeps its fog when the simulation is off, headless, or
			# still withholding its first presented frame.
			if _visibility_mask_simulation == null or not is_instance_valid(_visibility_mask_simulation):
				return _game_world_mask_texture
			return _visibility_mask_simulation.get_output_texture(_game_world_mask_texture)
		_:
			return null


## Reports the resolved pixels-per-cel and live texture size of every render mask, so
## resolution regressions can be asserted without a texture readback.
func debug_get_render_mask_resolution_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for mask_name in _RENDER_MASK_NAMES:
		var texture := _render_mask_texture(mask_name)
		snapshot[String(mask_name)] = {
			"pixels_per_cel": get_render_mask_pixels_per_cel(mask_name),
			"expected_size": _render_mask_capture_size(mask_name),
			"texture_size": Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO,
		}
	return snapshot


func _invalidate_view_distance_mask() -> void:
	_view_distance_mask_dirty = true
	_render_mask_outputs_dirty = true


func _update_view_distance_mask_if_needed() -> void:
	if not _view_distance_mask_dirty:
		return
	_view_distance_mask_dirty = false
	var source := _active_player_reveal_source()
	var radius := source.get_effective_range() if source != null else 0.0
	var maze_rect := _current_visibility_maze_rect()
	_view_distance_mask_valid = source != null and radius > 0.0 and maze_rect.size.x > 0.0 and maze_rect.size.y > 0.0
	if not _view_distance_mask_valid:
		_render_mask_texture_revisions.erase(&"view_distance")
		_render_mask_outputs_dirty = true
		return
	_ensure_view_distance_viewport()
	if _view_distance_viewport == null or _view_distance_material == null:
		_view_distance_mask_valid = false
		return
	var maze_position := source.get_effective_origin() * _maze_pixels_to_world_scale()
	var center_uv := (maze_position - maze_rect.position) / maze_rect.size
	_view_distance_material.set_shader_parameter("center_uv", center_uv)
	_view_distance_material.set_shader_parameter("world_size", maze_rect.size)
	_view_distance_material.set_shader_parameter("radius_world", radius)
	_view_distance_material.set_shader_parameter("border_world", _vignette_border_cells * maxf(0.0001, _builder_settings.cell_size))
	_view_distance_material.set_shader_parameter("fade_steepness", _vignette_fade_steepness)
	_view_distance_material.set_shader_parameter("corner_steepness", _vignette_corner_steepness)
	_view_distance_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_view_distance_mask_rebuild_count += 1
	_render_mask_texture_revisions[&"view_distance"] = _view_distance_mask_rebuild_count
	_render_mask_outputs_dirty = true


func _ensure_view_distance_viewport() -> void:
	if _current_viewport == null:
		return
	if _view_distance_viewport == null or not is_instance_valid(_view_distance_viewport):
		_view_distance_viewport = SubViewport.new()
		_view_distance_viewport.name = "ViewDistanceMaskViewport"
		_view_distance_viewport.transparent_bg = false
		_view_distance_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.name = "MaskRect"
		_view_distance_material = ShaderMaterial.new()
		_view_distance_material.shader = VIEW_DISTANCE_MASK_SHADER
		rect.material = _view_distance_material
		_view_distance_viewport.add_child(rect)
		add_child(_view_distance_viewport)
	var target_size := _render_mask_capture_size(SURFACE_VIEW_DISTANCE)
	if _view_distance_viewport.size != target_size:
		_view_distance_viewport.size = target_size
	var rect := _view_distance_viewport.get_node_or_null("MaskRect") as ColorRect
	if rect != null:
		rect.size = Vector2(_view_distance_viewport.size)


func _active_player_reveal_source() -> FogRevealSource2D:
	for entry_variant in _reveal_sources.values():
		var entry: Dictionary = entry_variant
		var source := entry.get("source") as FogRevealSource2D
		if source == null or not is_instance_valid(source) or not source.is_inside_tree():
			continue
		if source.range_state_path.strip_edges() == "level_state/player_sight_distance" and source.enabled:
			return source
	return null


func debug_get_view_distance_mask_snapshot() -> Dictionary:
	return {
		"valid": _view_distance_mask_valid,
		"dirty": _view_distance_mask_dirty,
		"rebuild_count": _view_distance_mask_rebuild_count,
		"has_texture": _view_distance_viewport != null,
		"border_cells": _vignette_border_cells,
		"fade_steepness": _vignette_fade_steepness,
		"corner_steepness": _vignette_corner_steepness,
	}


func _invalidate_camera_room_composite() -> void:
	_camera_room_composite_dirty = true
	_render_mask_outputs_dirty = true


func _update_camera_room_composite_if_needed() -> void:
	if not _camera_room_composite_dirty:
		return
	_camera_room_composite_dirty = false
	var from_tex := _camera_room_transition_from_tex if _camera_room_transition_from_tex != null else _camera_room_mask_texture_for_id(_camera_room_active_id)
	var to_tex := _camera_room_transition_to_tex if _camera_room_transition_to_tex != null else from_tex
	_camera_room_composite_valid = _camera_room_mask_enabled and from_tex != null and to_tex != null
	if not _camera_room_composite_valid:
		_render_mask_texture_revisions.erase(&"camera_rooms")
		_render_mask_outputs_dirty = true
		return
	_ensure_camera_room_composite_viewport()
	if _camera_room_composite_viewport == null or _camera_room_composite_material == null:
		_camera_room_composite_valid = false
		return
	_camera_room_composite_material.set_shader_parameter("from_mask", from_tex)
	_camera_room_composite_material.set_shader_parameter("to_mask", to_tex)
	_camera_room_composite_material.set_shader_parameter("blend_value", clampf(_camera_room_mask_blend, 0.0, 1.0))
	_camera_room_composite_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_camera_room_composite_rebuild_count += 1
	_render_mask_texture_revisions[&"camera_rooms"] = _camera_room_composite_rebuild_count
	_render_mask_outputs_dirty = true


func _ensure_camera_room_composite_viewport() -> void:
	if _current_viewport == null:
		return
	if _camera_room_composite_viewport == null or not is_instance_valid(_camera_room_composite_viewport):
		_camera_room_composite_viewport = SubViewport.new()
		_camera_room_composite_viewport.name = "CameraRoomMaskViewport"
		_camera_room_composite_viewport.transparent_bg = false
		_camera_room_composite_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.name = "MaskRect"
		_camera_room_composite_material = ShaderMaterial.new()
		_camera_room_composite_material.shader = CAMERA_ROOM_MASK_BLEND_SHADER
		rect.material = _camera_room_composite_material
		_camera_room_composite_viewport.add_child(rect)
		add_child(_camera_room_composite_viewport)
	var target_size := _render_mask_capture_size(SURFACE_CAMERA_ROOMS)
	if _camera_room_composite_viewport.size != target_size:
		_camera_room_composite_viewport.size = target_size
	var rect := _camera_room_composite_viewport.get_node_or_null("MaskRect") as ColorRect
	if rect != null:
		rect.size = Vector2(_camera_room_composite_viewport.size)


func debug_get_camera_room_composite_snapshot() -> Dictionary:
	return {
		"valid": _camera_room_composite_valid,
		"dirty": _camera_room_composite_dirty,
		"rebuild_count": _camera_room_composite_rebuild_count,
		"blend": _camera_room_mask_blend,
	}


func _apply_camera_room_mask_material_params(material: ShaderMaterial) -> void:
	if material == null:
		return
	# Camera-room visibility is already folded into the generalized game-world
	# texture; keep the legacy material inputs disabled to avoid applying it twice.
	var room_mask_enabled := false
	var from_tex := _camera_room_transition_from_tex if _camera_room_transition_from_tex != null else _camera_room_mask_texture_for_id(_camera_room_active_id)
	var to_tex := _camera_room_transition_to_tex if _camera_room_transition_to_tex != null else from_tex
	material.set_shader_parameter("camera_room_mask_enabled", room_mask_enabled)
	material.set_shader_parameter("camera_room_mask_tex_from", from_tex if from_tex != null else _black_texture)
	material.set_shader_parameter("camera_room_mask_tex_to", to_tex if to_tex != null else _black_texture)
	material.set_shader_parameter("camera_room_mask_blend", clampf(_camera_room_mask_blend, 0.0, 1.0))


func _rebuild_camera_room_masks(camera_rooms: Array) -> void:
	_camera_room_mask_rebuild_count += 1
	_camera_room_masks_by_id.clear()
	_camera_room_defs_signature = _camera_room_defs_signature_for(camera_rooms)
	_camera_room_mask_viewport_size = _render_mask_capture_size(SURFACE_CAMERA_ROOMS)
	if _camera_room_mask_viewport_size.x <= 0 or _camera_room_mask_viewport_size.y <= 0:
		return
	for room_variant in camera_rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id := int(room.get("id", -1))
		if room_id < 0:
			continue
		var cells_variant: Variant = room.get("cells", [])
		if not (cells_variant is Array):
			continue
		var tex := _build_camera_room_mask_texture(cells_variant as Array)
		_camera_room_masks_by_id[room_id] = tex
		_camera_room_mask_texture_build_count += 1
	var active_tex := _camera_room_mask_texture_for_id(_camera_room_active_id)
	# The rebuild replaces every room texture, so a transition still holding a discarded one
	# must re-point at the active room instead of blending two different resolutions.
	var rebuilt_textures := _camera_room_masks_by_id.values()
	if not rebuilt_textures.has(_camera_room_transition_from_tex):
		_camera_room_transition_from_tex = active_tex
	if not rebuilt_textures.has(_camera_room_transition_to_tex):
		_camera_room_transition_to_tex = active_tex
	_mask_textures_dirty = true
	_visibility_material_params_dirty = true
	_invalidate_camera_room_composite()


func _camera_room_defs_signature_for(camera_rooms: Array) -> String:
	var room_segments: Array[String] = []
	for room_variant in camera_rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var cells_variant: Variant = room.get("cells", [])
		if not (cells_variant is Array):
			continue
		var hash_value := 17
		for cell_variant in cells_variant:
			if typeof(cell_variant) != TYPE_VECTOR2I:
				continue
			var cell := cell_variant as Vector2i
			hash_value = int(hash_value * 31 + cell.x * 73856093 + cell.y * 19349663)
		room_segments.append("%d:%d:%d" % [int(room.get("id", -1)), (cells_variant as Array).size(), hash_value])
	room_segments.sort()
	return "|".join(room_segments)


func _build_camera_room_mask_texture(cells: Array) -> Texture2D:
	var size := _camera_room_mask_viewport_size
	if size.x <= 0 or size.y <= 0:
		return _black_texture
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var ppc := get_render_mask_pixels_per_cel(SURFACE_CAMERA_ROOMS)
	for cell_variant in cells:
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue
		var cell := cell_variant as Vector2i
		var start_x := maxi(0, cell.x * ppc)
		var start_y := maxi(0, cell.y * ppc)
		var end_x := mini(size.x, start_x + ppc)
		var end_y := mini(size.y, start_y + ppc)
		if end_x <= start_x or end_y <= start_y:
			continue
		image.fill_rect(Rect2i(start_x, start_y, end_x - start_x, end_y - start_y), Color.WHITE)
	return ImageTexture.create_from_image(image)


func _camera_room_mask_texture_for_id(room_id: int) -> Texture2D:
	var tex: Texture2D = _camera_room_masks_by_id.get(room_id)
	if tex != null:
		return tex
	return _black_texture


func _ensure_source_visibility_materials() -> void:
	var refreshed := false
	var source_floor := _source_floor_mesh
	if source_floor != null and source_floor.material_override is ShaderMaterial:
		if _source_floor_visibility_material == null or source_floor.material_override != _source_floor_visibility_material:
			_source_floor_visibility_material = (source_floor.material_override as ShaderMaterial).duplicate(true) as ShaderMaterial
			source_floor.material_override = _source_floor_visibility_material
			refreshed = true

	var source_walls := _source_maze_mesh
	if source_walls != null and source_walls.material_override is ShaderMaterial:
		if _source_walls_visibility_material == null or source_walls.material_override != _source_walls_visibility_material:
			_source_walls_visibility_material = (source_walls.material_override as ShaderMaterial).duplicate(true) as ShaderMaterial
			source_walls.material_override = _source_walls_visibility_material
			refreshed = true

	if _source_sprite_cache_dirty:
		_ensure_source_sprite_visibility_materials()
		refreshed = true
	if _source_origin_material_cache_dirty:
		_ensure_source_origin_visibility_materials()
		refreshed = true
	if refreshed:
		_visibility_material_params_dirty = true
		_source_visibility_material_refresh_count += 1


func _ensure_source_sprite_visibility_materials() -> void:
	var maze_root := _maze_root
	if maze_root == null:
		_source_sprite_nodes.clear()
		_source_sprite_visibility_materials.clear()
		_source_sprite_signatures.clear()
		_source_sprite_cache_dirty = false
		return

	var active_ids: Array[int] = []
	var sprites: Array[AnimatedSprite3D] = []
	_collect_animated_sprites(maze_root, sprites)
	_source_sprite_nodes = sprites

	for sprite in sprites:
		if sprite == null or not is_instance_valid(sprite):
			continue

		var sprite_id := sprite.get_instance_id()
		active_ids.append(sprite_id)

		var cached_material := _source_sprite_visibility_materials.get(sprite_id) as ShaderMaterial
		if cached_material != null and is_instance_valid(cached_material) and sprite.material_override == cached_material:
			if cached_material.shader == null:
				continue
			_connect_source_sprite_material_signals(sprite)
			_sync_source_sprite_material_texture(sprite, cached_material)
			continue

		var material := sprite.material_override as ShaderMaterial
		if material == null:
			material = ShaderMaterial.new()
			material.shader = SPRITE_VISIBILITY_MASKED_SHADER
			sprite.material_override = material
		elif material.shader == SPRITE_VISIBILITY_MASKED_SHADER:
			material = material.duplicate(true) as ShaderMaterial
			sprite.material_override = material
		else:
			continue

		_source_sprite_visibility_materials[sprite_id] = material
		_connect_source_sprite_material_signals(sprite)
		_sync_source_sprite_material_texture(sprite, material)

	var stale_ids: Array = _source_sprite_visibility_materials.keys()
	for sprite_id in stale_ids:
		if not active_ids.has(int(sprite_id)):
			_source_sprite_visibility_materials.erase(sprite_id)
			_source_sprite_signatures.erase(str(sprite_id))
	_source_sprite_cache_dirty = false


func _connect_source_sprite_material_signals(sprite: AnimatedSprite3D) -> void:
	var callback := _on_source_sprite_frame_changed.bind(sprite)
	if not sprite.frame_changed.is_connected(callback):
		sprite.frame_changed.connect(callback)
	if not sprite.animation_changed.is_connected(callback):
		sprite.animation_changed.connect(callback)


func _on_source_sprite_frame_changed(sprite: AnimatedSprite3D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var material := _source_sprite_visibility_materials.get(sprite.get_instance_id()) as ShaderMaterial
	if material == null or not is_instance_valid(material):
		return
	_sync_source_sprite_material_texture(sprite, material)


func _ensure_source_origin_visibility_materials() -> void:
	var maze_root := _maze_root
	if maze_root == null:
		_source_origin_visibility_materials.clear()
		_source_origin_material_cache_dirty = false
		return

	var active_keys: Array[String] = []
	var materials: Array[ShaderMaterial] = []
	_collect_origin_visibility_materials(maze_root, materials)

	for material in materials:
		if material == null or not is_instance_valid(material):
			continue
		if not _is_source_origin_visibility_shader(material.shader):
			continue
		var key := str(material.get_instance_id())
		active_keys.append(key)
		_source_origin_visibility_materials[key] = material

	var stale_keys: Array = _source_origin_visibility_materials.keys()
	for key_variant in stale_keys:
		var key := str(key_variant)
		if not active_keys.has(key):
			_source_origin_visibility_materials.erase(key)
	_source_origin_material_cache_dirty = false


func _update_source_visibility_materials() -> void:
	var current_tex := _current_viewport.get_texture() if _current_viewport != null else null
	var fog_of_war_tex := _history_viewports[_history_present_index].get_texture() if not _history_viewports.is_empty() else null
	var visibility_rect := _current_visibility_maze_rect()
	var maze_min_xz := visibility_rect.position
	var maze_size_xz := visibility_rect.size
	var source_maze := _source_maze_mesh
	var world_origin := Vector3.ZERO
	var world_to_maze_basis := Basis.IDENTITY
	if source_maze != null:
		world_origin = source_maze.global_position
		world_to_maze_basis = source_maze.global_basis.inverse()
	var world_contributions := _render_mask_contributions_for_target(&"game_world")
	var world_mask_enabled := not world_contributions.is_empty()
	# The single presentation boundary. Every authoritative consumer -- fog
	# history, cell discovery, wall knowledge, AI and placement -- reads the raw
	# masks upstream of this line and never sees the animated field.
	#
	# Resolved through `_render_mask_texture(&"game_world_animated")` rather than by
	# asking the simulation directly, so the texture the 3D world is masked with
	# is always the animated derivative, with its documented raw passthrough when
	# animation is disabled or unavailable.
	var world_mask_tex := _render_mask_texture(&"game_world_animated")
	var visibility_mask_enabled := world_mask_enabled
	var visibility_mask_tex := world_mask_tex if world_mask_enabled else _white_texture
	if visibility_mask_tex == null:
		visibility_mask_tex = _black_texture

	_apply_source_visibility_material(
		_source_floor_visibility_material,
		visibility_mask_enabled,
		visibility_mask_tex,
		world_origin,
		world_to_maze_basis,
		maze_min_xz,
		maze_size_xz
	)
	_apply_source_visibility_material(
		_source_walls_visibility_material,
		visibility_mask_enabled,
		visibility_mask_tex,
		world_origin,
		world_to_maze_basis,
		maze_min_xz,
		maze_size_xz
	)
	_apply_source_sprite_visibility_materials(
		visibility_mask_enabled,
		visibility_mask_tex,
		world_origin,
		world_to_maze_basis,
		maze_min_xz,
		maze_size_xz
	)
	_apply_source_origin_visibility_materials(
		visibility_mask_enabled,
		visibility_mask_tex,
		world_origin,
		world_to_maze_basis,
		maze_min_xz,
		maze_size_xz
	)


func _is_source_origin_visibility_shader(shader: Shader) -> bool:
	return (
		shader == OBJECT_ORIGIN_VISIBILITY_TINT_SHADER
		or shader == PILL_PARTICLE_VISIBILITY_SHADER
		or shader == PILL_BACK_GLOW_VISIBILITY_SHADER
	)


func _apply_source_visibility_material(
	material: ShaderMaterial,
	mask_enabled: bool,
	mask_tex: Texture2D,
	world_origin: Vector3,
	world_to_maze_basis: Basis,
	maze_min_xz: Vector2,
	maze_size_xz: Vector2
) -> void:
	if material == null or material.shader == null:
		return
	material.set_shader_parameter("visibility_mask_enabled", mask_enabled)
	material.set_shader_parameter("visibility_world_origin", world_origin)
	material.set_shader_parameter("visibility_world_to_maze_basis", world_to_maze_basis)
	material.set_shader_parameter("visibility_maze_min_xz", maze_min_xz)
	material.set_shader_parameter("visibility_maze_size_xz", maze_size_xz)
	material.set_shader_parameter("current_visibility_tex", mask_tex if mask_tex != null else _black_texture)


func _apply_source_sprite_visibility_materials(
	mask_enabled: bool,
	mask_tex: Texture2D,
	world_origin: Vector3,
	world_to_maze_basis: Basis,
	maze_min_xz: Vector2,
	maze_size_xz: Vector2
) -> void:
	for material_variant in _source_sprite_visibility_materials.values():
		if material_variant is ShaderMaterial:
			_apply_source_visibility_material(
				material_variant as ShaderMaterial,
				mask_enabled,
				mask_tex,
				world_origin,
				world_to_maze_basis,
				maze_min_xz,
				maze_size_xz
			)


func _apply_source_origin_visibility_materials(
	mask_enabled: bool,
	mask_tex: Texture2D,
	world_origin: Vector3,
	world_to_maze_basis: Basis,
	maze_min_xz: Vector2,
	maze_size_xz: Vector2
) -> void:
	for material_variant in _source_origin_visibility_materials.values():
		if material_variant is ShaderMaterial:
			_apply_source_visibility_material(
				material_variant as ShaderMaterial,
				mask_enabled,
				mask_tex,
				world_origin,
				world_to_maze_basis,
				maze_min_xz,
				maze_size_xz
			)


func _sync_source_sprite_material_texture(sprite: AnimatedSprite3D, material: ShaderMaterial) -> void:
	if sprite == null or material == null or not is_instance_valid(material):
		return
	if material.shader == null:
		return
	material.set_shader_parameter("sprite_texture", _get_animated_sprite_texture(sprite))


func _get_animated_sprite_texture(sprite: AnimatedSprite3D) -> Texture2D:
	if sprite == null or sprite.sprite_frames == null:
		return null
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return null
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		return null
	var frame_index := clampi(sprite.frame, 0, frame_count - 1)
	return sprite.sprite_frames.get_frame_texture(sprite.animation, frame_index)


## Explicit capture rectangle owned by the 2D backend (Decision 3), refreshed
## alongside the rest of the capture layout in `_refresh_capture_layout()`.
## Maze-local XZ, padded half a wall thickness outside the cell grid, matching
## every `uv = (Vector2(local.x, local.z) - rect.position) / rect.size` consumer.
func _current_visibility_maze_rect() -> Rect2:
	if _maze_data == null or _builder_settings == null:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return _capture_rect_2d


## Returns current gameplay visibility for a maze cell from the manager's registered reveal sources.
## This is a CPU-side fact query: it never reads rendered mask pixels and never performs a second
## line-of-sight trace. Occlusion remains owned by the fog presentation; placement conservatively
## treats every enabled source volume as visible.
func is_maze_cell_currently_visible(cell: Vector2i) -> bool:
	if _maze_data == null or _builder_settings == null:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= int(_maze_data.width) or cell.y >= int(_maze_data.height):
		return false
	var cell_world := maxf(0.0001, float(_builder_settings.cell_size))
	var cell_center_world := Vector2(
		(float(cell.x) + 0.5) * cell_world,
		(float(cell.y) + 0.5) * cell_world
	)
	var pixels_to_world := _maze_pixels_to_world_scale()
	for entry_variant in _reveal_sources.values():
		var entry := entry_variant as Dictionary
		var source := entry.get("source") as FogRevealSource2D
		if source == null or not is_instance_valid(source) or not source.is_effectively_enabled():
			continue
		if _source_volume_contains(source, cell_center_world, pixels_to_world):
			return true
	return false


## Conservative, non-occluding volume test in maze world units, matching the
## documented CPU-query contract. Source origins are authored in maze pixels,
## while ranges and the cell grid are authored in world units, so only the
## origin is converted.
func _source_volume_contains(source: FogRevealSource2D, cell_center_world: Vector2, pixels_to_world: float) -> bool:
	var offset := cell_center_world - source.get_effective_origin() * pixels_to_world
	var distance := offset.length()
	var effective_range := source.get_effective_range()
	if distance > effective_range:
		return false
	if source.shape != FogRevealSource2D.Shape.CONE:
		return true
	if distance <= 0.0001:
		return true
	var forward := source.get_effective_forward()
	var angle := rad_to_deg(acos(clampf(forward.dot(offset / distance), -1.0, 1.0)))
	return angle <= source.cone_angle_degrees


func _collect_animated_sprites(node: Node, out: Array[AnimatedSprite3D]) -> void:
	if node is AnimatedSprite3D:
		out.append(node as AnimatedSprite3D)
	for child in node.get_children():
		_collect_animated_sprites(child, out)


func _collect_origin_visibility_materials(node: Node, out: Array[ShaderMaterial]) -> void:
	if node.has_method("get_origin_visibility_materials"):
		var materials_variant: Variant = node.call("get_origin_visibility_materials")
		if materials_variant is Array:
			for material_variant in materials_variant:
				if material_variant is ShaderMaterial:
					out.append(material_variant as ShaderMaterial)
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() <= 0:
			for child in node.get_children():
				_collect_origin_visibility_materials(child, out)
			return
		var surface_count := mesh_instance.mesh.get_surface_count()
		for surface_index in range(surface_count):
			var material := mesh_instance.get_surface_override_material(surface_index) as ShaderMaterial
			if material != null:
				out.append(material)
	for child in node.get_children():
		_collect_origin_visibility_materials(child, out)


func _collect_lights(node: Node, out: Array[Light3D]) -> void:
	for child in node.get_children():
		if child is Light3D:
			out.append(child as Light3D)
		_collect_lights(child, out)


func _register_console_bindings() -> void:
	if Console == null:
		return
	# cheats/fog_of_war_off is a state variable; StateStore owns its console command.
	Console.add_command(FOG_OF_WAR_RESET_COMMAND_PATH, _reset_fog_of_war_texture_command, [], 0, "Resets the fog of war texture history.")
	_register_render_mask_texture_widgets()
	Console.add_command(WALLS_SET_ALL_DISCOVERED_COMMAND_PATH, _set_all_walls_discovered_command, [], 0, "Marks all maze walls as discovered.")
	Console.add_command(WALLS_CLEAR_KNOWN_COMMAND_PATH, _clear_known_walls_command, [], 0, "Clears known wall state for all maze walls.")
	Console.add_command(
		ANIMATED_MASK_SEED_ISLANDS_COMMAND_PATH,
		_seed_visibility_mask_islands_command,
		[],
		0,
		"Plants a seed nucleus in every animated-visibility-mask island no source can reach. Manual only."
	)
	Console.add_setget_command(
		ANIMATED_MASK_DEBUG_VIEW_COMMAND_PATH,
		_set_animated_visibility_mask_debug_view_command,
		get_animated_visibility_mask_debug_view,
		"Shows the animated visibility mask as the diagnostic view: red blocker, green organism, blue substrate."
	)
	Console.add_command(
		ANIMATED_MASK_SNAPSHOT_COMMAND_PATH,
		_print_animated_visibility_mask_snapshot_command,
		[],
		0,
		"Prints the animated visibility mask's dispatch counts, tick totals and effective creep velocity."
	)


func _unregister_console_bindings() -> void:
	if Console == null:
		return
	Console.batch_ui_updates(func():
		Console.remove_command(FOG_OF_WAR_RESET_COMMAND_PATH)
		if Console.has_method("remove_widget"):
			for widget_path in _registered_render_mask_texture_widgets:
				Console.remove_widget(widget_path)
		_registered_render_mask_texture_widgets.clear()
		Console.remove_command(WALLS_SET_ALL_DISCOVERED_COMMAND_PATH)
		Console.remove_command(WALLS_CLEAR_KNOWN_COMMAND_PATH)
		Console.remove_command(ANIMATED_MASK_SEED_ISLANDS_COMMAND_PATH)
		Console.remove_command(ANIMATED_MASK_DEBUG_VIEW_COMMAND_PATH)
		Console.remove_command(ANIMATED_MASK_SNAPSHOT_COMMAND_PATH)
	)


func _seed_visibility_mask_islands_command() -> void:
	var report := seed_visibility_mask_islands()
	if not bool(report.get("ok", false)):
		Console.print_line("Island seeding unavailable: %s" % String(report.get("reason", "unknown")))
		return
	Console.print_line("Seeded %d of %d unreachable island(s) (minimum %d texels)." % [
		int(report.get("components_seeded", 0)),
		int(report.get("components_found", 0)),
		int(report.get("minimum_area_texels", 0)),
	])


func _set_animated_visibility_mask_debug_view_command(enabled: bool) -> void:
	set_animated_visibility_mask_debug_view(enabled)


func _print_animated_visibility_mask_snapshot_command() -> void:
	if _visibility_mask_simulation == null or not is_instance_valid(_visibility_mask_simulation):
		Console.print_line("Animated visibility mask is not running.")
		return
	var snapshot: Dictionary = _visibility_mask_simulation.debug_get_snapshot()
	var keys := snapshot.keys()
	keys.sort()
	for key in keys:
		Console.print_line("%s: %s" % [String(key), str(snapshot[key])])


func _register_render_mask_texture_widgets() -> void:
	if Console == null or not Console.has_method("add_render_texture_widget"):
		return
	for mask_name in _RENDER_MASK_NAMES:
		var description := "Displays the %s render-mask texture." % String(mask_name).replace("_", " ")
		var texture_getter := Callable(self, "get_render_mask_texture").bind(mask_name)
		for root_command_path in [_RENDER_MASK_OBJECT_LAYER_ROOT_COMMAND_PATH, _RENDER_MASK_ROOT_COMMAND_PATH]:
			var widget_path := "%s/%s" % [root_command_path, String(mask_name)]
			Console.add_render_texture_widget(
				widget_path,
				texture_getter,
				description,
				_CONSOLE_STATE_GROUP_NAME,
				_CONSOLE_STATE_GROUP_PRIORITY,
				_DEBUG_TEXTURE_WIDGET_MIN_SIZE
			)
			_registered_render_mask_texture_widgets.append(widget_path)


func reset_fog_of_war_texture() -> void:
	if _black_texture == null and _current_viewport != null:
		_black_texture = _build_solid_texture(_current_viewport.size, Color.BLACK)
	if _white_texture == null and _current_viewport != null:
		_white_texture = _build_solid_texture(_current_viewport.size, Color.WHITE)
	_reset_history()
	# A reset changes the fog contribution even when the stationary current-visibility
	# surface does not redraw. Publish that new raw target for the animated post-pass.
	_bump_render_mask_texture_revision(SURFACE_FOG_OF_WAR)
	_update_mask_textures()
	_update_source_visibility_materials()


func _reset_fog_of_war_texture_command() -> void:
	reset_fog_of_war_texture()
	if Console != null:
		Console.print_line("Fog of War texture reset.")


func _on_fog_of_war_off_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_apply_fog_of_war_disabled_cheat(bool(new_value))


func _on_force_all_discovered_changed(_variable_path: StringName, _old_value: Variant, new_value: Variant) -> void:
	_force_all_discovered = bool(new_value)
	if _wall_knowledge_2d != null:
		_wall_knowledge_2d.set_force_all_discovered(_force_all_discovered)


## Mirrors `cheats/fog_of_war_off` onto the fog-of-war and view-distance masks of
## the `game_world` substrate. The state variable is the authority; this only
## projects it onto the mask claims. The floor projection un-fogs with it without
## a claim of its own, because it is routed to a derived mask that republishes
## that substrate -- it just animates off rather than snapping, since the
## simulation has to converge on the new substrate.
func _apply_fog_of_war_disabled_cheat(enabled: bool) -> void:
	var succeeded := true
	for mask_name in ["fog_of_war", "view_distance"]:
		for path in SharedStateKeys.direct_runtime_render_mask_paths(mask_name):
			if enabled:
				succeeded = StateStore.set_claim(path, SharedStateKeys.CLAIM_RENDER_MASK_FOG_DISABLED, "off") and succeeded
			else:
				StateStore.clear_claim(path, SharedStateKeys.CLAIM_RENDER_MASK_FOG_DISABLED)
			if enabled and not succeeded and Console != null:
				Console.print_error("Failed to disable fog of war cheat: missing state '%s'." % path)
	_fog_of_war_disabled_cheat_enabled = enabled and succeeded
	fog_of_war_disabled_cheat_changed.emit(_fog_of_war_disabled_cheat_enabled)


func set_all_walls_discovered() -> int:
	_ensure_wall_knowledge_controller()
	if _wall_knowledge_2d == null:
		return 0
	return _wall_knowledge_2d.set_all_walls_discovered()


func clear_known_walls() -> int:
	_ensure_wall_knowledge_controller()
	if _wall_knowledge_2d == null:
		return 0
	return _wall_knowledge_2d.clear_known_walls()


func _set_all_walls_discovered_command() -> void:
	var changed := set_all_walls_discovered()
	if Console != null:
		Console.print_line("Marked all walls as discovered (%d changed)." % changed)


func _clear_known_walls_command() -> void:
	var changed := clear_known_walls()
	if Console != null:
		Console.print_line("Cleared known wall state (%d changed)." % changed)


func _build_solid_texture(size: Vector2i, color: Color) -> Texture2D:
	var image := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)




func _get_parent_manager() -> MazeCameraManager:
	return get_parent() as MazeCameraManager


func _resolve_source_maze_mesh() -> MeshInstance3D:
	var manager := _get_parent_manager()
	return manager.get_bound_maze_mesh_instance() if manager != null else null


func _resolve_source_floor_mesh() -> MeshInstance3D:
	var manager := _get_parent_manager()
	return manager.get_bound_floor_mesh_instance() if manager != null else null


func _get_source_maze_mesh() -> MeshInstance3D:
	_ensure_source_references()
	return _source_maze_mesh


func _get_source_floor_mesh() -> MeshInstance3D:
	_ensure_source_references()
	return _source_floor_mesh


func _get_main_maze_view() -> MazeView:
	var renderer := _get_two_d_world_renderer()
	return renderer.get_interactive_maze_view() if renderer != null else null


func _get_gameplay_wall_maze_view() -> MazeView:
	var renderer := _get_two_d_world_renderer()
	return renderer.get_wall_lines_maze_view() if renderer != null else null


func _get_two_d_world_renderer() -> TwoDWorldRenderer:
	var manager := _get_parent_manager()
	return manager.get_bound_two_d_world_renderer() if manager != null else null


func _get_maze_root() -> Node3D:
	_ensure_source_references()
	return _maze_root
