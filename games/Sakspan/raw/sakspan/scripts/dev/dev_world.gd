# In res://scripts/dev/dev_world.gd
extends Node2D

func _ready():
	# Wait for the next frame to guarantee all singletons (like 'multiplayer') are stable
	await get_tree().process_frame

	if not multiplayer.has_multiplayer_peer():
		push_error("dev_world loaded without a multiplayer peer. Aborting initialization.")
		return

	print("[DevWorld] dev_world.tscn has loaded for peer ", multiplayer.get_unique_id())
	print("[DevWorld] Scene is now managed by GameManager's scene detection system")

	if multiplayer.is_server():
		if Engine.has_singleton("GameManager"):
			GameManager.initialize_game_world()
		else:
			push_error("FATAL: GameManager singleton not found!")
