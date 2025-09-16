# res://scripts/global/SceneChanger.gd
extends Node

var current_scene: Node = null

func _ready():
	var root = get_tree().root
	# Ensure current_scene is properly initialized, getting the last child of the root
	# which is typically the main scene when the game starts.
	if root.get_child_count() > 0:
		current_scene = root.get_child(root.get_child_count() - 1)
	else:
		# Fallback or error handling if no initial scene is found
		printerr("Warning: No initial scene found in the root.")
		# Consider exiting or loading a default scene here if this state is not expected.


func change_scene_to_file(scene_path: String, init_data: Dictionary = {}):
	"""
	Public function to initiate a scene change.
	It's crucial that the 'scene_path' provided when calling this function is correct.
	Example of a correct call from another script:
	SceneChanger.change_scene_to_file("res://scenes/UI/Lobby_Wait_Room/lobby_wait_room_menu.tscn")
	You can also pass optional initialization data for the new scene:
	SceneChanger.change_scene_to_file(path, {"lobby_info": {...}, "is_host": true})
	"""
	call_deferred("_deferred_change_scene", scene_path, init_data)


func _deferred_change_scene(scene_path: String, init_data: Dictionary = {}):
	# Free the current scene if it exists to prevent memory leaks.
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
	
	# Load the new scene resource from the provided path.
	var next_scene_packed = load(scene_path)
	
	# --- This is the error checking that caught your file path issue ---
	# Check if the scene was loaded successfully. If not, it's because the path is wrong.
	if next_scene_packed == null:
		printerr("Failed to load scene: '%s'. 'load()' returned null. Check if the file path is correct and the resource is valid." % scene_path)
		return
	
	# Check if the loaded resource is actually a PackedScene that can be instantiated.
	if not (next_scene_packed is PackedScene):
		printerr("Resource loaded from '%s' is not a PackedScene. Cannot instantiate." % scene_path)
		return

	# Instantiate the new scene.
	current_scene = next_scene_packed.instantiate()
	
	# Check if instantiation was successful.
	if current_scene == null:
		printerr("Failed to instantiate scene from '%s'. 'instantiate()' returned null." % scene_path)
		return

	# Add the new scene to the root of the scene tree, making it active.
	get_tree().root.add_child(current_scene)

	# Toggle visibility of the autoloaded GameUI HUD depending on the target scene.
	# Only show HUD during actual gameplay scene.
	if Engine.has_singleton("GameManager"):
		var gm = GameManager
		if gm and gm.game_ui_instance:
			var file := scene_path.get_file()
			var is_game_scene = (file == "game.tscn" or file == "world.tscn")
			gm.game_ui_instance.visible = is_game_scene

	# If there is initialization data, try to pass it to the new scene using common hooks.
	if init_data and current_scene:
		# Specific hook for the lobby wait room scene
		if current_scene.has_method("_initialize_lobby") and init_data.has("lobby_info"):
			current_scene.call("_initialize_lobby", init_data.get("lobby_info", {}), bool(init_data.get("is_host", false)))
		# Generic hook for any scene that wants initial data
		elif current_scene.has_method("receive_init_data"):
			current_scene.call("receive_init_data", init_data)
