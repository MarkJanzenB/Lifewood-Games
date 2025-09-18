# res://scripts/world_new.gd
extends Node2D
class_name GameWorldNew

signal world_loaded()
signal all_players_spawned()
signal game_started()

# Node references
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_container: Node2D = $Players
@onready var loading_screen: Control = $UI/LoadingScreen
@onready var loading_label: Label = $UI/LoadingScreen/LoadingPanel/LoadingVBox/LoadingLabel
@onready var progress_bar: ProgressBar = $UI/LoadingScreen/LoadingPanel/LoadingVBox/ProgressBar
@onready var status_label: Label = $UI/LoadingScreen/LoadingPanel/LoadingVBox/StatusLabel
@onready var debug_ui: Control = $UI/DebugUI
@onready var player_count_label: Label = $UI/DebugUI/DebugPanel/DebugVBox/PlayerCountLabel
@onready var connection_label: Label = $UI/DebugUI/DebugPanel/DebugVBox/ConnectionLabel
@onready var authority_label: Label = $UI/DebugUI/DebugPanel/DebugVBox/AuthorityLabel

# Game configuration
var spawn_points := [
	Vector2(0, -200),    # Center top
	Vector2(-200, 0),    # Left center
	Vector2(200, 0),     # Right center
	Vector2(-100, 150),  # Bottom left
	Vector2(100, 150)    # Bottom right
]

# Game state
var _spawned_players: Dictionary = {}
var _is_loading := true
var _debug_visible := false
var _game_initialized := false

# Server-side game state
var game_state := {
	"round": 0,
	"players": {},
	"started": false,
	"time_remaining": 300.0  # 5 minutes default
}

func _ready() -> void:
	print("[World] Initializing new world...")
	
	# Connect NetworkManager signals
	if NetworkManager:
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		NetworkManager.game_started.connect(_on_game_started)
	
	# Set up input handling
	set_process_input(true)
	
	# Initialize loading screen
	_show_loading_screen()
	
	# Start world initialization
	await get_tree().process_frame
	_initialize_world()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				_toggle_debug_ui()
			KEY_W, KEY_A, KEY_S, KEY_D:
				if not _is_loading:
					_handle_movement_input(event.keycode)

func _initialize_world() -> void:
	print("[World] Starting world initialization...")
	
	# Update loading progress
	_update_loading_progress(0.1, "Connecting to NetworkManager...")
	await get_tree().process_frame
	
	# Initialize server state if we're the server
	if multiplayer.is_server():
		print("[World] Initializing as server...")
		game_state.players = NetworkManager.players.duplicate()
		_update_loading_progress(0.3, "Setting up server state...")
	else:
		print("[World] Initializing as client...")
		_update_loading_progress(0.3, "Connecting to server...")
	
	await get_tree().create_timer(0.5).timeout
	
	# Load world environment
	_update_loading_progress(0.5, "Loading environment...")
	await _load_environment()
	
	# Initialize players
	_update_loading_progress(0.7, "Initializing players...")
	await _initialize_players()
	
	# Finalize initialization
	_update_loading_progress(0.9, "Finalizing...")
	await get_tree().create_timer(0.3).timeout
	
	# Complete loading
	_complete_loading()

func _load_environment() -> void:
	# Environment is already set up in the scene
	# This is where you'd load dynamic environment elements
	print("[World] Environment loaded")
	await get_tree().process_frame

func _initialize_players() -> void:
	if multiplayer.is_server():
		print("[World] Server initializing players...")
		await _spawn_all_players()
	else:
		print("[World] Client waiting for player spawn...")
		# Clients wait for server to spawn players
	
	# Notify NetworkManager that the game scene is ready
	NetworkManager.notify_game_scene_loaded()

func _spawn_all_players() -> void:
	if not multiplayer.is_server():
		print("[World] Only server can spawn players")
		return
	
	var players_dict = NetworkManager.players
	if players_dict.is_empty():
		print("[World] No players to spawn")
		return
	
	print("[World] Spawning ", players_dict.size(), " players...")
	
	# Clear existing players
	_despawn_all_players()
	
	# Get sorted player IDs for deterministic spawning
	var player_ids: Array[int] = []
	for key in players_dict.keys():
		player_ids.append(int(key))
	player_ids.sort()
	
	# Spawn each player
	for i in range(min(player_ids.size(), spawn_points.size())):
		var player_id: int = player_ids[i]
		var player_data: Dictionary = players_dict[player_id]
		var spawn_pos: Vector2 = spawn_points[i]
		
		print("[World] Spawning player ", player_id, " at ", spawn_pos)
		
		# Server-only spawn using MultiplayerSpawner
		var new_player: Node = multiplayer_spawner.spawn(player_id)
		if new_player == null:
			print("[World] Failed to spawn player ", player_id)
			continue
		
		# Configure the spawned player
		_configure_player(new_player, player_id, player_data, spawn_pos)
	
	print("[World] All players spawned successfully")
	all_players_spawned.emit()

func _configure_player(player: Node, player_id: int, player_data: Dictionary, spawn_pos: Vector2) -> void:
	# Set player name and position
	player.name = "Player_" + str(player_id)
	
	# Set multiplayer authority
	player.set_multiplayer_authority(player_id, true)
	
	# Position the player
	if player is Node2D:
		(player as Node2D).global_position = spawn_pos
	
	# Configure player properties
	if player.has_method("setup_multiplayer_player"):
		player.setup_multiplayer_player(player_data, player_id == multiplayer.get_unique_id())
	
	# Set up camera and input for local player
	var is_local_player := player_id == multiplayer.get_unique_id()
	if is_local_player:
		_setup_local_player(player)
		print("[World] Local player ", player_id, " configured")
	else:
		_setup_remote_player(player)
		print("[World] Remote player ", player_id, " configured")
	
	# Store reference
	_spawned_players[player_id] = player

func _setup_local_player(player: Node) -> void:
	# Enable camera for local player
	if player.has_node("Camera2D"):
		var camera = player.get_node("Camera2D")
		camera.enabled = true
		camera.make_current()
	
	# Enable input processing
	if player.has_method("set_is_main_player"):
		player.set_is_main_player(true)
	elif "is_main_player" in player:
		player.is_main_player = true

func _setup_remote_player(player: Node) -> void:
	# Disable camera for remote players
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").enabled = false

func _despawn_all_players() -> void:
	for child in players_container.get_children():
		child.queue_free()
	_spawned_players.clear()

func _show_loading_screen() -> void:
	if loading_screen:
		loading_screen.visible = true
		loading_screen.mouse_filter = Control.MOUSE_FILTER_STOP

func _update_loading_progress(progress: float, status: String) -> void:
	if progress_bar:
		progress_bar.value = progress * 100.0
	if status_label:
		status_label.text = status
	print("[World] Loading: ", int(progress * 100), "% - ", status)

func _complete_loading() -> void:
	_update_loading_progress(1.0, "Ready!")
	await get_tree().create_timer(0.5).timeout
	
	_is_loading = false
	if loading_screen:
		loading_screen.visible = false
		loading_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_game_initialized = true
	print("[World] World initialization complete!")
	world_loaded.emit()
	
	# Start the game if we're the server
	if multiplayer.is_server():
		_start_game()

func _start_game() -> void:
	if not multiplayer.is_server():
		return
	
	game_state.started = true
	print("[World] Game started!")
	
	# Sync game start to all clients
	_sync_game_start.rpc()
	game_started.emit()

@rpc("authority", "call_local", "reliable")
func _sync_game_start() -> void:
	print("[World] Game start received")
	game_started.emit()

func _handle_movement_input(keycode: int) -> void:
	if not _game_initialized:
		return
	
	var direction := ""
	match keycode:
		KEY_W:
			direction = "up"
		KEY_S:
			direction = "down"
		KEY_A:
			direction = "left"
		KEY_D:
			direction = "right"
	
	if direction != "":
		_send_input_to_server(direction)

func _send_input_to_server(direction: String) -> void:
	if multiplayer.is_server():
		_handle_player_input(multiplayer.get_unique_id(), direction)
	else:
		_rpc_player_input.rpc_id(1, direction)

@rpc("any_peer", "reliable")
func _rpc_player_input(direction: String) -> void:
	if not multiplayer.is_server():
		return
	
	var sender_id := multiplayer.get_remote_sender_id()
	_handle_player_input(sender_id, direction)

func _handle_player_input(player_id: int, direction: String) -> void:
	# Get player name for logging
	var player_name := "Player " + str(player_id)
	if NetworkManager.players.has(player_id):
		player_name = String(NetworkManager.players[player_id].get("name", player_name))
	
	# Log the input and broadcast to all clients
	_sync_input_log.rpc(player_id, player_name, direction)

@rpc("authority", "call_local", "reliable")
func _sync_input_log(player_id: int, player_name: String, direction: String) -> void:
	var key_name := ""
	match direction:
		"up": key_name = "W"
		"down": key_name = "S"
		"left": key_name = "A"
		"right": key_name = "D"
	
	print("[Input] ", player_name, " moved ", direction, " (", key_name, " key)")

func _toggle_debug_ui() -> void:
	_debug_visible = !_debug_visible
	if debug_ui:
		debug_ui.visible = _debug_visible
	
	if _debug_visible:
		_update_debug_info()

func _update_debug_info() -> void:
	if not _debug_visible or not debug_ui:
		return
	
	# Update player count
	if player_count_label:
		player_count_label.text = "Players: " + str(NetworkManager.players.size())
	
	# Update connection status
	if connection_label:
		var status := "None"
		if multiplayer.multiplayer_peer:
			status = "Server" if multiplayer.is_server() else "Client"
			status += " (ID: " + str(multiplayer.get_unique_id()) + ")"
		connection_label.text = "Connection: " + status
	
	# Update authority info
	if authority_label:
		var auth_text := "Authority: "
		if multiplayer.is_server():
			auth_text += "Server"
		else:
			auth_text += "Client"
		authority_label.text = auth_text

# NetworkManager signal handlers
func _on_player_list_changed(players: Dictionary) -> void:
	print("[World] Player list changed: ", players.keys())
	_update_debug_info()
	
	# Re-spawn players if we're the server and the game is initialized
	if multiplayer.is_server() and _game_initialized:
		await _spawn_all_players()

func _on_player_joined(player_id: int, player_data: Dictionary) -> void:
	print("[World] Player joined: ", player_id, " - ", player_data.get("name", "Unknown"))
	_update_debug_info()

func _on_player_left(player_id: int) -> void:
	print("[World] Player left: ", player_id)
	
	# Remove from spawned players
	if _spawned_players.has(player_id):
		var player = _spawned_players[player_id]
		if is_instance_valid(player):
			player.queue_free()
		_spawned_players.erase(player_id)
	
	_update_debug_info()

func _on_game_started(player_data: Dictionary) -> void:
	print("[World] Game started signal received from NetworkManager")
	# Additional game start logic can go here

# Process function for continuous updates
func _process(_delta: float) -> void:
	if _debug_visible:
		_update_debug_info()
