# res://scripts/world.gd
extends Node2D
class_name GameWorld

signal world_loaded()
signal all_players_spawned()

@onready var multiplayer_spawner = $MultiplayerSpawner
@onready var loading_screen := $LoadingScreen
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

func _ready():
	if multiplayer.is_server():
		# Initialize server state
		game_state.players = NetworkManager.players.duplicate()
		
	# Connect to NetworkManager signals
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	
	if loading_screen:
		loading_screen.visible = true
		loading_screen.update_progress(0.1, "Initializing...")
	
	await get_tree().process_frame
	_load_world_async()

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
	if multiplayer.is_server():
		_despawn_all_players()
		_spawn_all_players()

func _spawn_all_players() -> void:
	if not multiplayer.is_server():
		return
		
	print("[World] Starting player spawn process...")
	var players_dict = NetworkManager.players
	
	if players_dict.is_empty():
		print("[World] No players to spawn")
		return
	
	# Clear existing spawned players
	_spawned_players.clear()
	_despawn_all_players()
	
	# Convert keys to integers and sort for deterministic spawn order
	var int_ids: Array[int] = []
	for key in players_dict.keys():
		int_ids.append(int(key))
	int_ids.sort()
	
	print("[World] Spawning players: ", int_ids)
	
	# Spawn each player via MultiplayerSpawner so it replicates to clients
	for i in range(min(int_ids.size(), spawn_points.size())):
		var id: int = int_ids[i]
		var player_data = players_dict[id]
		
		print("[World] Spawning player ", id, " at position ", spawn_points[i])
		
		# Use RPC to spawn player on all clients
		_spawn_player_on_clients.rpc(id, player_data, spawn_points[i], i)
	
	# Assign roles after all players are spawned
	_assign_player_roles()

	# Notify NetworkManager that game scene is loaded
	NetworkManager.notify_game_scene_loaded()
	all_players_spawned.emit()

	# Initialize game mechanics
	_initialize_game_mechanics()

@rpc("authority", "call_local", "reliable")
func _spawn_player_on_clients(player_id: int, player_data: Dictionary, spawn_pos: Vector2, spawn_index: int) -> void:
	print("[World] Spawning player ", player_id, " on client")
	
	# Create player instance
	var new_player: Node = multiplayer_spawner.spawn(player_id)
	if new_player == null:
		print("[World] Failed to spawn player ", player_id)
		return
		
	new_player.name = "Player_" + str(player_id)
	
	# Set multiplayer authority - each player controls their own character
	new_player.set_multiplayer_authority(player_id, true)
	
	# Position the player
	if new_player is Node2D:
		(new_player as Node2D).global_position = spawn_pos
	
	# Configure player properties
	if new_player.has_method("setup_multiplayer_player"):
		new_player.setup_multiplayer_player(player_data, player_id == multiplayer.get_unique_id())
	
	# Set player name
	if "player_name" in new_player:
		new_player.player_name = player_data.get("name", "Player" + str(player_id))
	
	# Set up camera and input for local player only
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
			
		print("[World] Local player ", player_id, " spawned and configured")
	else:
		# Disable camera for remote players
		if new_player.has_node("Camera2D"):
			new_player.get_node("Camera2D").enabled = false
		print("[World] Remote player ", player_id, " spawned")
	
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
		_try_spawn_players()

func _on_player_left(player_id: int) -> void:
	print("Player left:", player_id)
	# Handle player left event
	if multiplayer.is_server():
		_despawn_player(player_id)

func _despawn_player(player_id: int) -> void:
	var p := players_container.get_node_or_null(str(player_id))
	if p:
		p.queue_free()

# Role assignment for multiplayer (Statically Typed)
func _assign_player_roles() -> void:
	if not multiplayer.is_server():
		return
	
	var all_players: Array[Node] = players_container.get_children()
	if all_players.is_empty():
		return
	
	print("[World] Assigning roles to ", all_players.size(), " players")
	
	# Randomly select one seeker, rest are hiders
	var seeker_index: int = randi() % all_players.size()
	
	for i in range(all_players.size()):
		var player: PlayerCharacter = all_players[i] as PlayerCharacter
		if not player:
			continue
			
		if i == seeker_index:
			player.assign_role(PlayerCharacter.PlayerRole.SEEKER)
			_sync_player_role.rpc(player.get_multiplayer_authority(), PlayerCharacter.PlayerRole.SEEKER)
		else:
			player.assign_role(PlayerCharacter.PlayerRole.HIDER)
			_sync_player_role.rpc(player.get_multiplayer_authority(), PlayerCharacter.PlayerRole.HIDER)

@rpc("authority", "call_local", "reliable")
func _sync_player_role(player_id: int, role: PlayerCharacter.PlayerRole) -> void:
	var player: PlayerCharacter = players_container.get_node_or_null("Player_" + str(player_id)) as PlayerCharacter
	if player:
		player.assign_role(role)

func _initialize_game_mechanics() -> void:
	if not multiplayer.is_server():
		return
	
	print("[World] Initializing game mechanics...")
	
	# Wait a moment for roles to be assigned
	await get_tree().create_timer(0.5).timeout
	
	# Get GameManager and initialize the game
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm and gm.has_method("initialize_game"):
		gm.initialize_game()
	else:
		print("[World] GameManager not found or doesn't have initialize_game method")

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
			if loading_screen and loading_screen.has_method("update_progress"):
				loading_screen.update_progress(0.3, "Failed to find players. Please try again.")
	
	timer.timeout.connect(_on_timeout, CONNECT_DEFERRED)
	timer.start(delay)
