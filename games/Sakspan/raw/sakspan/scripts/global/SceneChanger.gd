# res://scripts/global/SceneChanger.gd
extends Node

var current_scene: Node = null

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

func change_scene_to_file(scene_path: String):
	call_deferred("_deferred_change_scene", scene_path)

func _deferred_change_scene(scene_path: String):
	current_scene.queue_free()
	var next_scene_packed = load(scene_path)
	current_scene = next_scene_packed.instantiate()
	get_tree().root.add_child(current_scene)
