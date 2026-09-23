extends Node
class_name PackedVisibilityCapture

## PGO-101's packed auxiliary fog capture.
##
## The organic visibility simulation needs three lanes the composed `game_world`
## mask cannot carry: which texels are permanent reveal seeds, which of those
## seeds belong to occlusion-bypass sources, and where the fog blockers are.
## They are packed into one texture's three colour channels rather than one
## texture per concept:
##
##   R  permanent seed, normal (occlusion-enabled) source
##   G  permanent seed, occlusion-bypass source
##   B  fog blocker geometry
##
## Alpha is deliberately left alone.
##
## WHY A SEPARATE SURFACE FROM THE CURRENT-VISIBILITY CAPTURE
## The Goal leaves the final channel assignment open ("Final channel assignments
## must be settled after PGO-116 lands"). The current-visibility capture is a
## light-only render whose reveal lights write all of RGB, and whose alpha is
## already read as the explored-memory lane by `fog_history_merge.gdshader`.
## Recolouring those lights to free G and B would still leave only two free
## channels for three lanes, and would put a rendering-critical gameplay surface
## at risk for no gain. This surface is instead a plain unshaded additive paint
## of the SAME authoritative geometry, at the SAME size, over the SAME
## wall-inclusive maze rect, so the pack kernel can treat the two as one
## coordinate space. One extra texture carries three lanes.
##
## The blocker lane is painted from `FogBlocker2D.get_polygon()` — byte for byte
## the polygon the component hands its `LightOccluder2D` — so the blocker
## representation and the occluder can never drift apart.

const CAPTURE_VIEWPORT_NAME := "FogPackedAuxViewport"
const CAPTURE_ROOT_NAME := "FogPackedAuxRoot"
const CAPTURE_BACKGROUND_NAME := "FogPackedAuxBackground"
## Square resolution of the generated hard-edged seed disc. The seed must be a
## binary pinned value, so this texture has no falloff at all: a soft source
## could evaporate, which is exactly what the Goal forbids.
const SEED_TEXTURE_RESOLUTION := 64
const LANE_SEED_NORMAL := Color(1.0, 0.0, 0.0, 1.0)
const LANE_SEED_BYPASS := Color(0.0, 1.0, 0.0, 1.0)
const LANE_BLOCKER := Color(0.0, 0.0, 1.0, 1.0)

static var _seed_texture: ImageTexture = null

var _viewport: SubViewport = null
var _root: Node2D = null
var _background: ColorRect = null
var _seed_painters: Dictionary = {}
var _blocker_painters: Dictionary = {}
var _capture_rect := Rect2(Vector2.ZERO, Vector2.ONE)
var _signature := ""
var _revision := 0
var _redraw_count := 0


## Mirrors the current-visibility capture's size and maze rect. Everything drawn
## here uses the same maze-local coordinates the capture root does, so the two
## surfaces are texel-aligned by construction rather than by convention.
func configure(size: Vector2i, capture_rect: Rect2) -> void:
	_ensure_nodes()
	if size.x > 0 and size.y > 0 and _viewport.size != size:
		_viewport.size = size
		_signature = ""
	if not _capture_rect.is_equal_approx(capture_rect):
		_capture_rect = capture_rect
		_signature = ""
	_background.size = Vector2(_viewport.size)
	if _capture_rect.size.x > 0.0 and _capture_rect.size.y > 0.0:
		var pixels_per_world_unit := Vector2(_viewport.size) / _capture_rect.size
		_root.position = -_capture_rect.position * pixels_per_world_unit
		_root.scale = pixels_per_world_unit


## Repaints the lanes if anything they depend on changed. `sources` and
## `blockers` are the manager's live registries; `maze_pixels_to_world` is the
## same gameplay-pixels-to-maze-world scale the capture lights are placed with.
func sync(
	sources: Array,
	blockers: Array,
	seed_radius_world: float,
	maze_pixels_to_world: float
) -> void:
	_ensure_nodes()
	var signature_parts := PackedStringArray([
		str(_viewport.size),
		str(_capture_rect),
		"%.4f" % seed_radius_world,
	])

	var live_seed_keys := {}
	for source: Node in sources:
		if source == null or not is_instance_valid(source) or not source.has_method("get_effective_origin"):
			continue
		var key := source.get_instance_id()
		live_seed_keys[key] = true
		var painter := _ensure_seed_painter(key)
		var enabled := bool(source.call("is_effectively_enabled"))
		var bypass := not bool(source.get("occlusion_enabled"))
		painter.visible = enabled and seed_radius_world > 0.0
		painter.position = (source.call("get_effective_origin") as Vector2) * maze_pixels_to_world
		painter.scale = Vector2.ONE * (seed_radius_world * 2.0 / float(SEED_TEXTURE_RESOLUTION))
		painter.modulate = LANE_SEED_BYPASS if bypass else LANE_SEED_NORMAL
		signature_parts.append("s%d:%d:%d:%.3f,%.3f" % [
			key,
			1 if painter.visible else 0,
			1 if bypass else 0,
			painter.position.x,
			painter.position.y,
		])
	_release_stale(_seed_painters, live_seed_keys)

	var live_blocker_keys := {}
	for blocker: Node in blockers:
		if blocker == null or not is_instance_valid(blocker) or not blocker.has_method("get_polygon"):
			continue
		var key := blocker.get_instance_id()
		live_blocker_keys[key] = true
		var polygon: PackedVector2Array = blocker.call("get_polygon")
		var painter := _ensure_blocker_painter(key)
		# Godot rejects a Polygon2D with fewer than three points, exactly as it
		# rejects the matching OccluderPolygon2D.
		painter.visible = polygon.size() >= 3
		if painter.visible:
			painter.polygon = polygon
		signature_parts.append("b%d:%d:%d" % [
			key,
			1 if painter.visible else 0,
			int(blocker.call("get_geometry_revision")),
		])
	_release_stale(_blocker_painters, live_blocker_keys)

	var signature := "|".join(signature_parts)
	if signature == _signature:
		return
	_signature = signature
	_revision += 1
	_redraw_count += 1
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func get_texture() -> Texture2D:
	_ensure_nodes()
	return _viewport.get_texture()


func get_revision() -> int:
	return _revision


func debug_get_snapshot() -> Dictionary:
	return {
		"size": _viewport.size if _viewport != null else Vector2i.ZERO,
		"revision": _revision,
		"redraw_count": _redraw_count,
		"seed_painters": _seed_painters.size(),
		"blocker_painters": _blocker_painters.size(),
		"update_mode": _viewport.render_target_update_mode if _viewport != null else SubViewport.UPDATE_DISABLED,
	}


func _ensure_nodes() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = CAPTURE_VIEWPORT_NAME
	_viewport.disable_3d = true
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_background = ColorRect.new()
	_background.name = CAPTURE_BACKGROUND_NAME
	_background.color = Color.BLACK
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_background)

	_root = Node2D.new()
	_root.name = CAPTURE_ROOT_NAME
	_viewport.add_child(_root)


func _ensure_seed_painter(key: int) -> Sprite2D:
	var painter := _seed_painters.get(key) as Sprite2D
	if painter != null and is_instance_valid(painter):
		return painter
	painter = Sprite2D.new()
	painter.name = "SeedPainter_%d" % key
	painter.texture = _get_seed_texture()
	painter.centered = true
	painter.material = _lane_material()
	_root.add_child(painter)
	_seed_painters[key] = painter
	return painter


func _ensure_blocker_painter(key: int) -> Polygon2D:
	var painter := _blocker_painters.get(key) as Polygon2D
	if painter != null and is_instance_valid(painter):
		return painter
	painter = Polygon2D.new()
	painter.name = "BlockerPainter_%d" % key
	painter.color = LANE_BLOCKER
	painter.material = _lane_material()
	_root.add_child(painter)
	_blocker_painters[key] = painter
	return painter


## Additive so overlapping painters saturate their own lane instead of the last
## one drawn winning, and unshaded so the isolated capture canvas's reveal
## lights cannot tint a lane.
func _lane_material() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return material


func _release_stale(registry: Dictionary, live_keys: Dictionary) -> void:
	for key_variant in registry.keys():
		if live_keys.has(key_variant):
			continue
		var painter := registry[key_variant] as Node
		if painter != null and is_instance_valid(painter):
			painter.queue_free()
		registry.erase(key_variant)


static func _get_seed_texture() -> ImageTexture:
	if _seed_texture != null:
		return _seed_texture
	var image := Image.create(SEED_TEXTURE_RESOLUTION, SEED_TEXTURE_RESOLUTION, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(SEED_TEXTURE_RESOLUTION, SEED_TEXTURE_RESOLUTION) * 0.5
	var radius := float(SEED_TEXTURE_RESOLUTION) * 0.5
	for y in SEED_TEXTURE_RESOLUTION:
		for x in SEED_TEXTURE_RESOLUTION:
			var inside := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) <= radius
			image.set_pixel(x, y, Color.WHITE if inside else Color(0.0, 0.0, 0.0, 0.0))
	_seed_texture = ImageTexture.create_from_image(image)
	return _seed_texture
