@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"FogCameraManager",
		"Node",
		preload("res://addons/visibility/runtime/fog_camera_manager.gd"),
		null
	)
	_log("Visibility enabled. Console and host state services are optional; no runtime manager is created by the plugin.")


func _exit_tree() -> void:
	remove_custom_type("FogCameraManager")


func _log(message: String, level := 1) -> void:
	var console := get_node_or_null("/root/Console")
	if console != null and console.has_method("try_log"):
		console.call("try_log", func() -> Array: return [message], level, "Visibility")
		return
	push_warning(message)
