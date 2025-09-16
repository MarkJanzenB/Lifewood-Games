# res://scripts/world.gd
extends Node2D

@onready var player_spawner := $PlayerSpawner

# Predefined spawn points for up to 5 players
var spawn_points := [Vector2(39, -323), Vector2(-103, -335), Vector2(200, 100), Vector2(-200, 100), Vector2(0, 200)]

func _ready():
	await get_tree().process_frame
	if not Engine.has_singleton("NetworkManager"):
		return
	var players := NetworkManager.players if Engine.has_singleton("NetworkManager") else {}
	# Remove any previously spawned players (if scene was reloaded)
	for child in get_children():
		if child is PlayerCharacter:
			child.queue_free()
	
	# Spawn a player for each peer in the lobby
	var player_ids := players.keys()
	player_ids.sort() # Sort for deterministic spawn order
	for i in range(min(player_ids.size(), 5)):
		var id = int(player_ids[i])
		var pdata = players[id]
		var new_player = player_spawner.spawn(id)
		if new_player:
			new_player.player_name = pdata.get("name", "Player%d" % id)
			if pdata.has("role"):
				if new_player.has_method("assign_role"):
					new_player.assign_role(PlayerCharacter.PlayerRole.SEEKER if pdata["role"] == "seeker" else PlayerCharacter.PlayerRole.HIDER)
			if pdata.has("char_index") and new_player.has_method("apply_character_index"):
				new_player.apply_character_index(int(pdata["char_index"]))
			# Set authority so only the correct peer can control their avatar
			new_player.set_multiplayer_authority(id, true)
			# Place at a spawn point
			if i < spawn_points.size():
				new_player.global_position = spawn_points[i]
			else:
				new_player.global_position = Vector2(0, 0)
			# Enable camera for local player
			if id == multiplayer.get_unique_id():
				if new_player.has_node("Camera2D"):
					new_player.get_node("Camera2D").enabled = true

	if multiplayer.is_server():
		GameManager.start_game_logic()
