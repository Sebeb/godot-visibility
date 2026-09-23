@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"FogCameraManager",
		"Node",
		preload("res://addons/visibility/runtime/fog_camera_manager.gd"),
		null
	)


func _exit_tree() -> void:
	remove_custom_type("FogCameraManager")
