# res://scripts/world.gd
extends Node2D
class_name GameWorld

signal world_loaded()
signal all_players_spawned()

@onready var loading_screen := get_node_or_null("LoadingScreen")
@onready var players_container: Node = $Players

# Predefined spawn points for up to 5 players (Statically Typed)
var spawn_points: Array[Vector2] = [Vector2(39, -323), Vector2(-103, -335), Vector2(200, 100), Vector2(-200, 100), Vector2(0, 200)]

# Server-side game state (Statically Typed)
var game_state: Dictionary = {
	"current_round": 0,
	"players": {},
	"game_started": false
}
var _is_loading: bool = true
var _spawned_players: Dictionary = {}
var _spawn_attempts: int = 0
var _max_spawn_attempts: int = 10

func _ready() -> void:
	print("[DevWorld] Starting dev test world")
	
	# Configure MultiplayerSpawner
	var spawner = $MultiplayerSpawner
	spawner.spawn_function = _spawn_player_with_data
	print("[DevWorld] MultiplayerSpawner configured")
	
	# Auto-assign roles after a short delay to ensure all players are spawned
	await get_tree().create_timer(2.0).timeout
	_auto_assign_roles() 
	
	# Connect to NetworkManager signals
	if NetworkManager.player_list_changed.connect(_on_player_list_changed) != OK:
		print("[World] Failed to connect to player_list_changed signal")
	
	# Connect to network events
	if multiplayer.peer_connected.connect(_on_peer_connected) != OK:
		print("[World] Failed to connect to peer_connected signal")
	if multiplayer.peer_disconnected.connect(_on_peer_disconnected) != OK:
		print("[World] Failed to connect to peer_disconnected signal")
	
	# Start spawning players
	_spawn_all_players()

func _input(event):
	# Debug key to check players
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			print("[World] === F1 DEBUG: Checking all players ===")
			_debug_check_all_players()
		elif event.keycode == KEY_F3:
			print("[World] === F3 DEBUG: Reassigning roles ===")
			if multiplayer.is_server():
				_assign_player_roles()
		elif event.keycode == KEY_F4:
			print("[World] === F4 DEBUG: Testing movement sync ===")
			_test_movement_sync()
		elif event.keycode == KEY_F5:
			print("[World] === F5 DEBUG: Testing visual sync ===")
			_test_visual_sync()
		elif event.keycode == KEY_F6:
			print("[World] === F6 DEBUG: Testing username display ===")
			_test_username_display()
		elif event.keycode == KEY_F8:
			print("[World] === F8 DEBUG: Testing fire/sak functions ===")
			_test_fire_sak_functions()
		elif event.keycode == KEY_F9:
			print("[World] === F9 DEBUG: Manual role assignment for testing ===")
			_manual_role_assignment()
		elif event.keycode == KEY_F10:
			print("[World] === F10 DEBUG: Check player states ===")
			_check_player_states()
		elif event.keycode == KEY_F11:
			print("[World] === F11 DEBUG: Test animations directly ===")
			_test_animations_directly()
		elif event.keycode == KEY_F12:
			print("[World] === F12 DEBUG: Test role overlay ===")
			_test_role_overlay()
		elif event.keycode == KEY_R:
			print("[World] === R KEY: Quick role assignment ===")
			_quick_role_assignment()
		elif event.keycode == KEY_G:
			print("[World] === G KEY: Check scene structure ===")
			_debug_scene_structure()
		elif event.keycode == KEY_F2:
			print("[World] === F2 DEBUG: Manually applying colors ===")
			_debug_apply_colors_manually()

# Server-only function to validate and execute player actions
@rpc("any_peer", "call_local", "reliable")
func player_action(action: String, data: Dictionary):
	if not multiplayer.is_server():
		return
		
	var player_id = multiplayer.get_remote_sender_id()
	
	# Validate player can perform this action
	if not _validate_action(player_id, action, data):
		return
		
	# Execute the action
	match action:
		"attack":
			_handle_attack(player_id, data)
		"move":
			_handle_move(player_id, data)
		
	# Sync state to all clients
	update_game_state.rpc(game_state)

@rpc("authority", "reliable")
func update_game_state(new_state: Dictionary) -> void:
	game_state = new_state

# Client function to request actions
func request_action(action: String, data: Dictionary):
	player_action.rpc_id(1, action, data)

# Server validation function
func _validate_action(player_id: int, action: String, data: Dictionary) -> bool:
	# Implement validation logic here
	return true

func _load_world_async():
	# Connect to network manager for initial player sync
	# IMPORTANT: Only the server should spawn via MultiplayerSpawner.
	if multiplayer.is_server() and not NetworkManager.players.is_empty():
		_spawn_all_players()
	
	if loading_screen:
		loading_screen.update_progress(0.2, "Loading players...")
	
	# Simulate loading other world elements
	await _load_world_objects()
	
	# Finalize loading
	_on_world_loaded()

func _load_world_objects() -> void:
	# Load and initialize world objects here
	if loading_screen:
		loading_screen.update_progress(0.5, "Loading environment...")
	
	# Simulate loading time
	await get_tree().create_timer(0.5).timeout
	
	# Load other resources if needed
	if loading_screen:
		loading_screen.update_progress(0.8, "Finalizing...")
	
	await get_tree().process_frame

func _on_world_loaded() -> void:
	_is_loading = false
	if loading_screen:
		loading_screen.update_progress(1.0, "Ready!")
		await get_tree().create_timer(0.5).timeout
		loading_screen.hide_screen()
	
	print("[World] World loaded successfully")
	world_loaded.emit()

func _on_player_list_changed(players: Dictionary) -> void:
	# Prevent recursive spawning during game
	if multiplayer.is_server() and not game_state["game_started"]:
		_despawn_all_players()
		_spawn_all_players()

func _spawn_all_players() -> void:
	if not multiplayer.is_server():
		return

	# Pull canonical spawn data (includes char_index and spawn order)
	var players_dict = NetworkManager.get_spawn_data()

	if players_dict.is_empty():
		return

	# Clear existing spawned players
	_spawned_players.clear()
	_despawn_all_players()

	# Convert keys to integers and sort for deterministic spawn order
	var int_ids: Array[int] = []
	for key in players_dict.keys():
		int_ids.append(int(key))
	int_ids.sort()

	# Spawn each player via RPC
	for i in range(min(int_ids.size(), spawn_points.size())):
		var id: int = int_ids[i]
		var player_data: Dictionary = players_dict[id]
		# Use RPC to spawn player on all clients
		_spawn_player_on_clients.rpc(id, player_data, spawn_points[i], i)

# MultiplayerSpawner callback function
func _spawn_player_with_data(data: Variant) -> Node:
	print("[DevWorld] _spawn_player_with_data called with: ", data)
	
	# Create player instance
	var player_scene = preload("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	
	# Set up player with data if provided
	if data is Dictionary:
		var player_data = data as Dictionary
		if "player_id" in player_data:
			player.name = "Player_" + str(player_data["player_id"])
		if "player_name" in player_data:
			player.player_name = player_data["player_name"]
		if "char_index" in player_data:
			player.character_index = player_data["char_index"]
	
	return player

	# Mark game as started to prevent respawning
	game_state["game_started"] = true

	# Assign roles after all players are spawned
	await get_tree().process_frame
	_assign_player_roles()

	# Notify NetworkManager that game scene is loaded
	NetworkManager.notify_game_scene_loaded()
	all_players_spawned.emit()

	# Initialize game mechanics
	_initialize_game_mechanics()

@rpc("authority", "call_local", "reliable")
func _spawn_player_on_clients(player_id: int, player_data: Dictionary, spawn_pos: Vector2, spawn_index: int) -> void:
	# Get character index from player data
	var character_index: int = int(player_data.get("char_index", 0))
	var player_name: String = str(player_data.get("name", "Player" + str(player_id)))
	
	# Create character using the factory
	var new_player: PlayerCharacter = CharacterFactory.create_character(character_index)
	if new_player == null:
		print("[World] ERROR: Failed to create character for player ", player_id)
		return
	
	# Add to the scene
	players_container.add_child(new_player, true)
	new_player.name = "Player_" + str(player_id)
	
	# Set multiplayer authority - each player controls their own character
	new_player.set_multiplayer_authority(player_id, true)
	print("[World] Set multiplayer authority for player ", player_id, " to ", player_id)
	
	# Position the player
	if new_player is Node2D:
		(new_player as Node2D).global_position = spawn_pos
	
	# Configure player properties
	if new_player.has_method("setup_multiplayer_player"):
		var is_local_player = (player_id == multiplayer.get_unique_id())
		print("[World] Setting up player ", player_id, " as local: ", is_local_player)
		new_player.setup_multiplayer_player(player_data, is_local_player)
	
	# Set player name and update display
	if "player_name" in new_player:
		new_player.player_name = player_name
		print("[World] Set player name to: ", new_player.player_name)
		# Update username display after setting the name
		if new_player.has_method("update_username_display"):
			new_player.update_username_display()
	
	# Apply character appearance (color) based on character index - sync to all clients
	_sync_character_appearance.rpc(player_id, character_index)
	
	# Store spawned player
	_spawned_players[player_id] = new_player
	
	print("[World] Successfully created player ", player_id, " (", player_name, ") at ", spawn_pos)
	
	if player_id == multiplayer.get_unique_id():
		if new_player.has_node("Camera2D"):
			var camera = new_player.get_node("Camera2D")
			camera.enabled = true
			camera.make_current()
		
		# Enable input processing for local player
		if new_player.has_method("set_is_main_player"):
			new_player.set_is_main_player(true)
		elif "is_main_player" in new_player:
			new_player.is_main_player = true
	else:
		# Disable camera for remote players
		if new_player.has_node("Camera2D"):
			new_player.get_node("Camera2D").enabled = false
	
	_spawned_players[player_id] = new_player

func _despawn_all_players() -> void:
	for child in players_container.get_children():
		child.queue_free()
	_spawned_players.clear()

func _handle_attack(player_id: int, data: Dictionary) -> void:
	# Implement attack logic here
	pass

func _handle_move(player_id: int, data: Dictionary) -> void:
	# Implement move logic here
	pass

# GameManager signal handlers
func _on_game_state_changed(new_state: int) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if not gm:
		return
	match new_state:
		gm.GameState.LOBBY:
			print("Game State: Lobby")
		gm.GameState.STARTING:
			print("Game State: Starting")
		gm.GameState.IN_PROGRESS:
			print("Game State: In Progress")
			# Additional in-game setup can go here
		gm.GameState.GAME_OVER:
			print("Game State: Game Over")

func _on_player_joined(player_id: int, player_data: Dictionary) -> void:
	print("Player joined:", player_id, " Data:", player_data)
	# Handle player joined event
	if multiplayer.is_server():
		_spawn_all_players()

func _on_player_left(player_id: int) -> void:
	print("Player left:", player_id)
	# Handle player left event
	if multiplayer.is_server():
		_despawn_player(player_id)


func _despawn_player(player_id: int) -> void:
	var p := players_container.get_node_or_null("Player_" + str(player_id))
	if p:
		p.queue_free()

# Role assignment for multiplayer (Statically Typed)
func _assign_player_roles() -> void:
	if not multiplayer.is_server():
		return
	
	var all_players: Array[Node] = players_container.get_children()
	if all_players.is_empty():
		return
	
	# Randomly select one seeker, rest are hiders
	var seeker_index: int = randi() % all_players.size()
	
	for i in range(all_players.size()):
		var player: PlayerCharacter = all_players[i] as PlayerCharacter
		if not player:
			continue
			
		if i == seeker_index:
			# Assign SEEKER role
			player.assign_role(PlayerCharacter.PlayerRole.SEEKER)
			_sync_player_role.rpc(player.get_multiplayer_authority(), PlayerCharacter.PlayerRole.SEEKER)
		else:
			# Assign HIDER role
			player.assign_role(PlayerCharacter.PlayerRole.HIDER)
			_sync_player_role.rpc(player.get_multiplayer_authority(), PlayerCharacter.PlayerRole.HIDER)

@rpc("any_peer", "call_local", "reliable")
func _sync_player_role(player_id: int, role: PlayerCharacter.PlayerRole) -> void:
	var player: PlayerCharacter = players_container.get_node_or_null("Player_" + str(player_id)) as PlayerCharacter
	if player:
		player.assign_role(role)

func _initialize_game_mechanics() -> void:
	if not multiplayer.is_server():
		return
	
	print("[World] Initializing game mechanics...")
	
	# Debug: Check all spawned players
	_debug_check_all_players()
	
	# Wait a moment for roles to be assigned
	await get_tree().create_timer(0.5).timeout

# Debug function to check all players
func _debug_check_all_players():
	print("[World] === DEBUGGING ALL PLAYERS ===")
	var all_players = players_container.get_children()
	print("[World] Total players in scene: ", all_players.size())
	
	for i in range(all_players.size()):
		var player = all_players[i] as PlayerCharacter
		if player:
			print("[World] Player ", i, ":")
			print("  - Name: ", player.player_name)
			print("  - Character Index: ", player.character_index)
			print("  - Character Name: ", player.get_character_name())
			print("  - Role: ", PlayerCharacter.PlayerRole.keys()[player.role])
			print("  - Multiplayer Authority: ", player.get_multiplayer_authority())
			print("  - Is Multiplayer Authority: ", player.is_multiplayer_authority())
			print("  - Is Local Player: ", player.is_main_player)
			print("  - Can Move: ", player.can_move)
			print("  - Can Attack: ", player.can_attack)
			print("  - Global Position: ", player.global_position)
			print("  - Current Unique ID: ", multiplayer.get_unique_id())
		else:
			print("[World] Player ", i, " is not a PlayerCharacter!")

@rpc("any_peer", "call_local", "reliable")
func _sync_character_appearance(player_id: int, character_index: int):
	print("[World] Syncing character appearance for player ", player_id, " with character index ", character_index)
	
	var player: PlayerCharacter = players_container.get_node_or_null("Player_" + str(player_id)) as PlayerCharacter
	if not player:
		print("[World] ERROR: Could not find player ", player_id, " for appearance sync")
		return
	
	_apply_character_appearance(player, character_index)

func _apply_character_appearance(player: PlayerCharacter, character_index: int):
	if character_index < 0 or character_index >= CharacterFactory.get_character_count():
		print("[World] Invalid character index: ", character_index)
		return
	
	var color = CharacterFactory.get_character_color(character_index)
	var character_name = CharacterFactory.get_character_name(character_index)
	
	print("[World] Applying ", character_name, " appearance with color: ", color)
	
	# Apply color to animated sprite
	if player.has_node("AnimatedSprite2D"):
		var sprite = player.get_node("AnimatedSprite2D")
		sprite.modulate = color
		print("[World] Successfully applied ", character_name, " color: ", color)
	else:
		print("[World] ERROR: No AnimatedSprite2D found on player!")
	
	# Ensure character index is set
	player.character_index = character_index
	print("[World] Character appearance applied for ", character_name)

func _test_movement_sync():
	print("[World] === MOVEMENT SYNC TEST ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			print("[World] Player: ", p.player_name)
			print("  - Authority: ", p.get_multiplayer_authority())
			print("  - Is Authority: ", p.is_multiplayer_authority())
			print("  - Is Main Player: ", p.is_main_player)
			print("  - Can Move: ", p.can_move)
			print("  - Physics Process: ", p.is_physics_processing())
			print("  - Position: ", p.global_position)
			print("  - Velocity: ", p.velocity)

func _test_visual_sync():
	print("[World] === VISUAL SYNC TEST ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			print("[World] Player: ", p.player_name)
			print("  - Character Index: ", p.character_index)
			print("  - Character Name: ", p.get_character_name())
			if p.has_node("AnimatedSprite2D"):
				var sprite = p.get_node("AnimatedSprite2D")
				print("  - Sprite Color: ", sprite.modulate)
				print("  - Current Animation: ", sprite.animation)
				print("  - Is Flipped: ", sprite.flip_h)
				print("  - Is Playing: ", sprite.is_playing())
			else:
				print("  - ERROR: No AnimatedSprite2D found!")

func _test_username_display():
	print("[World] === USERNAME DISPLAY TEST ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			print("[World] Player: ", p.player_name)
			print("  - Has username_label: ", p.username_label != null)
			if p.username_label:
				print("  - Label text: '", p.username_label.text, "'")
				print("  - Label position: ", p.username_label.position)
				print("  - Label visible: ", p.username_label.visible)
			else:
				print("  - ERROR: No username label found!")
				# Try to create it
				if p.has_method("_create_username_label"):
					p._create_username_label()
					print("  - Created username label")

func _test_fire_sak_functions():
	print("[World] === FIRE/SAK FUNCTION TEST ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			print("[World] Player: ", p.player_name)
			print("  - Role: ", PlayerCharacter.PlayerRole.keys()[p.role])
			print("  - Has execute_fire_projectile: ", p.has_method("execute_fire_projectile"))
			print("  - Has execute_sak_attack: ", p.has_method("execute_sak_attack"))
			print("  - Has set_ammo: ", p.has_method("set_ammo"))
			print("  - Has eliminate: ", p.has_method("eliminate"))
			print("  - Current ammo: ", p.ammo)
			print("  - Can attack: ", p.can_attack)
			print("  - Can move: ", p.can_move)
			
			# Check GameManager connection
			var gm = get_node_or_null("/root/GameManager")
			if gm:
				print("  - GameManager found: ", gm.name)
				print("  - GameManager has request_player_action: ", gm.has_method("request_player_action"))
			else:
				print("  - ❌ GameManager NOT found!")

func _manual_role_assignment():
	print("[World] === MANUAL ROLE ASSIGNMENT ===")
	var all_players = players_container.get_children()
	
	if all_players.size() == 0:
		print("[World] No players found!")
		return
	
	for i in range(all_players.size()):
		var player = all_players[i] as PlayerCharacter
		if player:
			# First player becomes seeker, rest become hiders
			if i == 0:
				player.assign_role(PlayerCharacter.PlayerRole.SEEKER)
				player.can_attack = true
				player.can_move = true
				print("[World] Assigned SEEKER role to: ", player.player_name)
			else:
				player.assign_role(PlayerCharacter.PlayerRole.HIDER)
				player.can_attack = true
				player.can_move = true
				print("[World] Assigned HIDER role to: ", player.player_name)
	
	print("[World] Role assignment complete - overlays should be showing for main players")

func _check_player_states():
	print("[World] === PLAYER STATE CHECK ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			print("[World] Player: ", p.player_name)
			print("  - Role: ", PlayerCharacter.PlayerRole.keys()[p.role])
			print("  - Ammo: ", p.ammo)
			print("  - Can attack: ", p.can_attack)
			print("  - Can move: ", p.can_move)
			print("  - Is main player: ", p.is_main_player)
			print("  - Is multiplayer authority: ", p.is_multiplayer_authority())
			print("  - Current state: ", PlayerCharacter.PlayerState.keys()[p.current_state])
			print("  - Is dying: ", p.is_dying)
			print("  - Is in action: ", p.is_in_action)
			print("  - Script class: ", p.get_script().get_global_name() if p.get_script() else "No script")

func _test_animations_directly():
	print("[World] === ANIMATION TEST ===")
	var all_players = players_container.get_children()
	
	for i in range(all_players.size()):
		var player = all_players[i] as PlayerCharacter
		if player:
			print("[World] Testing animations for: ", player.player_name)
			
			# Test seeker_bang animation
			if i == 0:  # First player
				print("[World] Testing SEEKER_BANG animation")
				player.animated_sprite.stop()
				player.animated_sprite.play("seeker_bang")
				player.is_in_action = true
				print("[World] Animation started: ", player.animated_sprite.animation, " playing: ", player.animated_sprite.is_playing())
			
			# Test hider_sak animation  
			elif i == 1:  # Second player
				print("[World] Testing HIDER_SAK animation")
				player.animated_sprite.stop()
				player.animated_sprite.play("hider_sak")
				player.is_in_action = true
				print("[World] Animation started: ", player.animated_sprite.animation, " playing: ", player.animated_sprite.is_playing())
			
			# Test death animation
			elif i == 2:  # Third player
				print("[World] Testing DEATH animation")
				player.animated_sprite.stop()
				player.animated_sprite.play("death")
				print("[World] Animation started: ", player.animated_sprite.animation, " playing: ", player.animated_sprite.is_playing())

func _test_role_overlay():
	print("[World] === ROLE OVERLAY TEST ===")
	var all_players = players_container.get_children()
	
	for player in all_players:
		if player is PlayerCharacter:
			var p = player as PlayerCharacter
			if p.is_main_player:
				print("[World] Testing role overlay for main player: ", p.player_name)
				print("[World] Player role: ", PlayerCharacter.PlayerRole.keys()[p.role])
				p.display_role_for_round()
				break

func _quick_role_assignment():
	print("[World] === QUICK ROLE ASSIGNMENT ===")
	var all_players = players_container.get_children()
	
	if all_players.size() == 0:
		print("[World] No players found in players_container!")
		return
	
	print("[World] Found ", all_players.size(), " players")
	
	# Assign first player as seeker, rest as hiders
	for i in range(all_players.size()):
		var player = all_players[i] as PlayerCharacter
		if player:
			print("[World] Processing player ", i, ": ", player.player_name)
			if i == 0:
				# First player becomes seeker
				player.assign_role(PlayerCharacter.PlayerRole.SEEKER)
				player.can_attack = true
				player.can_move = true
				print("[World] ✅ Assigned SEEKER to: ", player.player_name, " (Ammo: ", player.ammo, ")")
			else:
				# Rest become hiders
				player.assign_role(PlayerCharacter.PlayerRole.HIDER)
				player.can_attack = true
				player.can_move = true
				print("[World] ✅ Assigned HIDER to: ", player.player_name)
		else:
			print("[World] ❌ Player ", i, " is not a PlayerCharacter!")
	
	print("[World] Role assignment complete! Press F12 to test role overlays")
	print("[World] Press SPACE to use fire/sak actions")

func _auto_assign_roles():
	print("[World] === AUTO ROLE ASSIGNMENT ===")
	var all_players = players_container.get_children()
	
	if all_players.size() >= 2:
		print("[World] Auto-assigning roles to ", all_players.size(), " players")
		_quick_role_assignment()
	else:
		print("[World] Waiting for more players... (", all_players.size(), "/2)")

func _debug_scene_structure():
	print("[World] === SCENE STRUCTURE DEBUG ===")
	print("[World] Current scene: ", get_tree().current_scene.name)
	print("[World] Root children:")
	for child in get_tree().root.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	print("[World] DevWorld children:")
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Check for GameManager specifically
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		print("[World] ✅ GameManager found at /root/GameManager")
	else:
		print("[World] ❌ GameManager NOT found at /root/GameManager")
		
	# Check if we can find it elsewhere
	var gm_alt = get_tree().get_first_node_in_group("game_manager")
	if gm_alt:
		print("[World] ✅ GameManager found in group: ", gm_alt.get_path())
	else:
		print("[World] ❌ GameManager not found in 'game_manager' group")

# Debug function to manually apply colors
func _debug_apply_colors_manually():
	print("[World] Manually applying colors to all players...")
	var all_players = players_container.get_children()
	
	for i in range(all_players.size()):
		var player = all_players[i] as PlayerCharacter
		if player and player.has_node("AnimatedSprite2D"):
			var sprite = player.get_node("AnimatedSprite2D")
			var char_index = player.character_index
			if char_index >= 0 and char_index < CharacterFactory.CHARACTER_COLORS.size():
				var color = CharacterFactory.get_character_color(char_index)
				sprite.modulate = color
				print("[World] Applied color ", color, " to player ", i, " (", CharacterFactory.get_character_name(char_index), ")")
			else:
				print("[World] Invalid character index for player ", i, ": ", char_index)
	
	# Get GameManager and initialize the game
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm and gm.has_method("initialize_game"):
		gm.initialize_game()
	else:
		print("[World] GameManager not found or doesn't have initialize_game method")

# Handle peer connected
func _on_peer_connected(id: int):
	print("[World] Peer connected: ", id)
	# Respawn players when new peer connects
	if multiplayer.is_server():
		_spawn_all_players()

# Handle peer disconnected  
func _on_peer_disconnected(id: int):
	print("[World] Peer disconnected: ", id)
	# Clean up disconnected player
	_despawn_player(id)
