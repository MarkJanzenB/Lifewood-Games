# res://scripts/world.gd
class_name GameWorld
extends Node2D

signal world_loaded()

@onready var player_spawner = $PlayerSpawner
@onready var loading_screen: Node = get_node_or_null("LoadingScreen")

const PLAYER_SCENE := preload("res://scenes/player.tscn")

# Predefined spawn points for up to 5 players
var spawn_points := [Vector2(39, -323), Vector2(-103, -335), Vector2(200, 100), Vector2(-200, 100), Vector2(0, 200)]
var _is_loading := true

func _ready():
	# The server is responsible for spawning players.
	if multiplayer.is_server():
		_spawn_players()
	
	# Set up loading screen
	if loading_screen:
		loading_screen.visible = true
		loading_screen.update_progress(0.1, "Initializing...")
	
	# Wait for first frame to ensure all nodes are ready
	await get_tree().process_frame
	
	# Validate NetworkManager (autoload)
	if get_node_or_null("/root/NetworkManager") == null:
		push_error("[World] NetworkManager not found!")
		queue_free()
		return
	
	# Start loading sequence
	_load_world_async()

	# Configure MultiplayerSpawner for proper replication (so clients get spawned automatically)
	if player_spawner and player_spawner is MultiplayerSpawner:
		# Ensure the correct player scene is spawnable
		if "spawnable_scenes" in player_spawner:
			player_spawner.spawnable_scenes = PackedStringArray(["res://scenes/player.tscn"]) 
		# Provide a spawn function used by all peers to instantiate the node
		player_spawner.spawn_function = Callable(self, "_spawn_player_node")

func _spawn_players():
	_spawn_all_players()

func _setup_player(node, id):
	var player_info = NetworkManager.players[id]
	node.set_player_name(player_info["name"])

func _load_world_async():
	if loading_screen:
		loading_screen.update_progress(0.2, "Loading players...")
	
	# Connect to game manager signals
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.game_state_changed.connect(_on_game_state_changed)
		gm.player_joined.connect(_on_player_joined)
		gm.player_left.connect(_on_player_left)
	
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
	for id_key in players.keys():
		int_ids.append(int(id_key))
	int_ids.sort()
	
	# Spawn each player via MultiplayerSpawner so it replicates to clients
	for i in range(min(int_ids.size(), spawn_points.size())):
		var id: int = int_ids[i]
		var pdata: Dictionary = players.get(id, {})
		var spawn_data := {
			"id": id,
			"name": pdata.get("name", "Player%d" % id),
			"role": pdata.get("role", "hider"),
			"char_index": int(pdata.get("char_index", -1)),
			"spawn_index": i
		}
		if player_spawner and player_spawner is MultiplayerSpawner:
			player_spawner.spawn(spawn_data, id)
		else:
			# Fallback: local-only spawn (dev mode)
			var new_player = _spawn_player_node(spawn_data)
			add_child(new_player)
	
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
	var gm := get_node_or_null("/root/GameManager")
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
	for child in get_children():
		if child is PlayerCharacter and child.get_multiplayer_authority() == player_id:
			child.queue_free()
			break

# Spawn function used by MultiplayerSpawner on all peers
func _spawn_player_node(data: Dictionary) -> Node:
	var id: int = int(data.get("id", 0))
	var spawn_index: int = int(data.get("spawn_index", 0))
	var role_str: String = String(data.get("role", "hider"))
	var char_index: int = int(data.get("char_index", -1))
	var player_name: String = String(data.get("name", "Player%d" % id))

	var p = PLAYER_SCENE.instantiate()
	# Set authority so only the owning peer sends sync
	p.set_multiplayer_authority(id, true)
	# Basic properties
	if "player_name" in p:
		p.player_name = player_name
	# Role
	var role = PlayerCharacter.PlayerRole.SEEKER if role_str == "seeker" else PlayerCharacter.PlayerRole.HIDER
	if p.has_method("assign_role"):
		p.assign_role(role)
	# Character index
	if char_index >= 0 and p.has_method("apply_character_index"):
		p.apply_character_index(char_index)
	# Position
	p.global_position = spawn_points[spawn_index] if spawn_index < spawn_points.size() else Vector2(100, 100)

	# Ensure MultiplayerSynchronizer has a replication config
	var sync := p.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		var rc := SceneReplicationConfig.new()
		# Replicate common properties
		rc.add_property(":global_position")
		# Add other properties here as needed, e.g., state variables on the script
		sync.replication_config = rc
		sync.visibility_public = true
		sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	# Camera for local player
	if id == multiplayer.get_unique_id() and p.has_node("Camera2D"):
		p.get_node("Camera2D").enabled = true
		p.get_node("Camera2D").make_current()
	return p

func _despawn_all_players() -> void:
	for child in get_children():
		if child is PlayerCharacter:
			child.queue_free()
