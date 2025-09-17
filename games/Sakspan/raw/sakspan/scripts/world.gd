# res://scripts/world.gd
class_name GameWorld
extends Node2D

signal world_loaded()

@onready var player_spawner := $PlayerSpawner
@onready var loading_screen := $LoadingScreen

# Predefined spawn points for up to 5 players
var spawn_points := [Vector2(39, -323), Vector2(-103, -335), Vector2(200, 100), Vector2(-200, 100), Vector2(0, 200)]
var _is_loading := true

func _ready():
	# Set up loading screen
	if loading_screen:
		loading_screen.visible = true
		loading_screen.update_progress(0.1, "Initializing...")
	
	# Wait for first frame to ensure all nodes are ready
	await get_tree().process_frame
	
	# Validate NetworkManager
	if not Engine.has_singleton("NetworkManager"):
		push_error("NetworkManager not found!")
		return
	
	# Start loading sequence
	_load_world_async()

func _load_world_async():
	if loading_screen:
		loading_screen.update_progress(0.2, "Loading players...")
	
	# Connect to game manager signals
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.player_joined.connect(_on_player_joined)
	GameManager.player_left.connect(_on_player_left)
	
	# Connect to network manager for initial player sync
	NetworkManager.player_list_changed.connect(_on_player_list_changed, CONNECT_DEFERRED)
	
	# If we're the server, start the game logic
	if multiplayer.is_server():
		# Initialize players if any exist
		if not NetworkManager.players.is_empty():
			_try_spawn_players()
	else:
		# Clients can request a resync if needed
		NetworkManager.request_players_resync()
	
	# Simulate loading other world elements
	await _load_world_objects()
	
	# Finalize loading
	_on_world_loaded()

func _try_spawn_players(max_attempts: int = 10, delay: float = 0.2) -> void:
	print("[World] Attempting to spawn players...")
	
	# If we already have players, spawn them immediately
	if not NetworkManager.players.is_empty():
		print("[World] Players already available, spawning...")
		_spawn_all_players()
		return
		
	print("[World] No players found, starting retry timer...")
	var attempts = 0
	var timer = Timer.new()
	timer.one_shot = false
	add_child(timer)
	
	var _on_timeout = func():
		attempts += 1
		print("[World] Attempt ", attempts, " to find players...")
		
		if not NetworkManager.players.is_empty():
			print("[World] Players found after ", attempts, " attempts")
			timer.stop()
			timer.queue_free() 
			_spawn_all_players()
		elif attempts >= max_attempts:
			print("[World] Failed to find players after ", max_attempts, " attempts")
			timer.stop()
			timer.queue_free()
			# Notify the player that we couldn't find any players
			if loading_screen:
				loading_screen.update_progress(0.3, "Failed to find players. Please try again.")
	
	timer.timeout.connect(_on_timeout, CONNECT_DEFERRED)
	timer.start(delay)

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
		loading_screen.hide()
	
	print("[World] World loaded successfully")
	world_loaded.emit()

func _spawn_all_players() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		print("[World] Cannot spawn players - world not ready")
		return
		
	if loading_screen:
		loading_screen.update_progress(0.3, "Spawning players...")
	
	var players = NetworkManager.players.duplicate()
	if players.is_empty():
		print("[World] No players to spawn")
		return
	
	print("[World] Spawning players:", players)
	
	# Convert keys to integers and sort for deterministic spawn order
	var int_ids: Array[int] = []
	for id_str in players.keys():
		if id_str.is_valid_int():
			int_ids.append(int(id_str))
	int_ids.sort()
	
	# Spawn each player
	for i in range(min(int_ids.size(), spawn_points.size())):
		var id: int = int_ids[i]
		var id_str = str(id)  # Convert to string for dictionary access
		var pdata: Dictionary = players.get(id_str, {})
		
		print("[World] Attempting to spawn player ", id, " with data: ", pdata)
		
		var new_player = player_spawner.spawn(id)
		if not is_instance_valid(new_player):
			print("[World] Failed to spawn player ", id)
			continue
		
		# Set basic properties
		new_player.player_name = pdata.get("name", "Player%d" % id)
		
		# Set role and ensure proper group assignment
		if pdata.has("role"):
			var role_str = pdata["role"]
			var role = PlayerCharacter.PlayerRole.SEEKER if role_str == "seeker" else PlayerCharacter.PlayerRole.HIDER
			new_player.assign_role(role)
			
			# Double-check group assignment
			if role == PlayerCharacter.PlayerRole.SEEKER:
				if not new_player.is_in_group("seeker"):
					new_player.add_to_group("seeker")
				if new_player.is_in_group("hider"):
					new_player.remove_from_group("hider")
			else:
				if not new_player.is_in_group("hider"):
					new_player.add_to_group("hider")
		
		# Set character index if specified
		if pdata.has("char_index") and new_player.has_method("apply_character_index"):
			new_player.apply_character_index(int(pdata["char_index"]))
		
		# Set authority and position
		new_player.set_multiplayer_authority(id, true)
		new_player.global_position = spawn_points[i] if i < spawn_points.size() else Vector2(100, 100)
		
		# Set up camera for local player
		if id == multiplayer.get_unique_id():
			print("[World] Setting up camera for local player", id)
			if new_player.has_node("Camera2D"):
				new_player.get_node("Camera2D").enabled = true
				new_player.get_node("Camera2D").make_current()
		else:
			print("[World] Spawned remote player", id)
	
	if loading_screen:
		loading_screen.update_progress(0.4, "Players spawned")

func _on_player_list_changed(_players: Dictionary) -> void:
	if multiplayer.is_server() and not _is_loading:
		print("[World] Player list changed, respawning players")
		_despawn_all_players()
		_spawn_all_players()

func _on_player_list_changed_once(_players: Dictionary) -> void:
	if multiplayer.is_server():
		print("[World] Detected player list change after load; respawning on server.")
		_despawn_all_players()
		_spawn_all_players()

# GameManager signal handlers
func _on_game_state_changed(new_state: int) -> void:
	match new_state:
		GameManager.GameState.LOBBY:
			print("Game State: Lobby")
		GameManager.GameState.STARTING:
			print("Game State: Starting")
		GameManager.GameState.IN_PROGRESS:
			print("Game State: In Progress")
			# Additional in-game setup can go here
		GameManager.GameState.GAME_OVER:
			print("Game State: Game Over")

func _on_player_joined(player_id: int, player_data: Dictionary) -> void:
	print("Player joined:", player_id, " Data:", player_data)
	# Handle player joined event
	if multiplayer.is_server():
		_try_spawn_players()

func _on_player_left(player_id: int) -> void:
	print("Player left:", player_id)
	# Handle player left event
	if multiplayer.is_server():
		_despawn_player(player_id)

func _despawn_player(player_id: int) -> void:
	for child in get_children():
		if child is PlayerCharacter and child.player_id == player_id:
			child.queue_free()
			break

func _despawn_all_players() -> void:
	for child in get_children():
		if child is PlayerCharacter:
			child.queue_free()
