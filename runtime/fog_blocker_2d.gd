extends Node2D
class_name FogBlocker2D

## A component-owned fog occluder generated from authoritative 2D wall geometry.

signal blocker_changed(blocker: FogBlocker2D, revision: int)

const BLOCKER_GROUP := "fog_blocker_2d"

var _geometry_revision := -1
var _polygon := PackedVector2Array()
var _capture_occluder: LightOccluder2D = null
var _manager: Node = null


func _enter_tree() -> void:
	add_to_group(BLOCKER_GROUP)


func _ready() -> void:
	_resolve_manager_once()
	if _manager != null:
		_manager.call("register_fog_blocker", self)
	elif get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func set_geometry(revision: int, polygon: PackedVector2Array) -> void:
	if revision == _geometry_revision and polygon == _polygon:
		return
	_geometry_revision = revision
	_polygon = polygon.duplicate()
	_apply_capture_geometry()
	blocker_changed.emit(self, _geometry_revision)


func get_geometry_revision() -> int:
	return _geometry_revision


func get_polygon() -> PackedVector2Array:
	return _polygon.duplicate()


func get_capture_occluder() -> LightOccluder2D:
	return _capture_occluder


func attach_capture_occluder(capture_parent: Node) -> LightOccluder2D:
	if _capture_occluder != null and is_instance_valid(_capture_occluder) and _capture_occluder.get_parent() != capture_parent:
		_capture_occluder.queue_free()
		_capture_occluder = null
	if _capture_occluder == null or not is_instance_valid(_capture_occluder):
		_capture_occluder = LightOccluder2D.new()
		_capture_occluder.name = "FogCaptureOccluder"
		_capture_occluder.light_mask = (1 << 19) | 1
		var occluder_polygon := OccluderPolygon2D.new()
		occluder_polygon.closed = true
		_capture_occluder.occluder = occluder_polygon
		capture_parent.add_child(_capture_occluder)
	_apply_capture_geometry()
	return _capture_occluder


func release_capture_occluder() -> void:
	if _capture_occluder != null and is_instance_valid(_capture_occluder):
		_capture_occluder.queue_free()
	_capture_occluder = null


func _exit_tree() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.call("unregister_fog_blocker", self)
	_manager = null
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	release_capture_occluder()


func _apply_capture_geometry() -> void:
	if _capture_occluder == null or not is_instance_valid(_capture_occluder):
		return
	if _polygon.size() < 3:
		# Godot rejects empty OccluderPolygon2D shapes. Keep any previous valid
		# shape hidden until this component receives a new canonical polygon.
		_capture_occluder.visible = false
		return
	_capture_occluder.visible = true
	var occluder_polygon := _capture_occluder.occluder as OccluderPolygon2D
	if occluder_polygon != null:
		occluder_polygon.polygon = _polygon


func _resolve_manager_once() -> void:
	if get_tree() != null:
		_manager = get_tree().get_first_node_in_group("fog_camera_manager")


func _on_tree_node_added(node: Node) -> void:
	if node.is_in_group("fog_camera_manager"):
		_manager = node
		get_tree().node_added.disconnect(_on_tree_node_added)
		_manager.call("register_fog_blocker", self)
