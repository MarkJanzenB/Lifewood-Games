#res://scripts/GameManager.gd

extends Node

# Game State
enum GameState {
	LOBBY,              # Players are in lobby
	STARTING,           # Game is starting (for backward compatibility)
	HIDER_HEADSTART,    # Hiders get a head start
	GAME_START_COUNTDOWN, # Final countdown before game starts
	IN_PROGRESS,        # Game is in progress
	GAME_OVER           # Game has ended
}

# Signals
signal game_state_changed(new_state: int)
signal player_joined(player_id: int, player_data: Dictionary)
signal player_left(player_id: int)
signal player_ready_changed(player_id: int, is_ready: bool)
signal game_starting(countdown: int)
signal game_ended(winning_team: String)
signal player_eliminated(eliminated_player: Object, attacker: Object)

# Configuration
@export var game_start_delay: float = 5.0  # 5 seconds countdown
@export var min_players: int = 2
@export var max_players: int = 5

# Networked variables
var players: Dictionary = {}  # player_id: {name: String, ready: bool, role: String, ...}
var game_state: int = GameState.LOBBY
var current_round: int = 1
var match_start_time: float = 0.0
var game_ui_instance: Node = null  # Will be set by the GameUI scene when it loads

# Make this a proper singleton
static var instance: Node = null

# Timers
@onready var main_timer: Timer = Timer.new()
@onready var ammo_cooldown_timer: Timer = Timer.new()
@onready var sak_delay_timer: Timer = Timer.new()

func _enter_tree():
	if instance != null:
		queue_free()
		return
	instance = self
	
	# Initialize timers
	add_child(main_timer)
	add_child(ammo_cooldown_timer)
	add_child(sak_delay_timer)
	
	main_timer.one_shot = true
	ammo_cooldown_timer.one_shot = true
	sak_delay_timer.one_shot = true
	
func _exit_tree():
	if instance == self:
		instance = null

# Game management functions

func check_win_conditions():
	# Check if all hiders are caught or time runs out
	var hiders_alive = 0
	for player_id in players:
		var player = get_node_or_null("/root/World/Players/" + str(player_id))
		if player and player.role == PlayerCharacter.PlayerRole.HIDER and player.current_state != PlayerCharacter.PlayerState.GHOST:
			hiders_alive += 1
	
	if hiders_alive == 0:
		# All hiders caught, seekers win
		game_state = GameState.GAME_OVER
		emit_signal("game_ended", "seekers")
	# Add other win conditions as needed


# References
@onready var network_manager = get_node_or_null("/root/NetworkManager") as Node
@onready var world = get_node_or_null("/root/World") as Node2D

func _ready() -> void:
	if not network_manager:
		push_error("NetworkManager not found!")
	
	# Connect to network manager signals if needed
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.peer_connected.is_connected(_on_player_connected):
			multiplayer.peer_connected.connect(_on_player_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_player_disconnected):
			multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Connect timer signals if needed
	# if not main_timer.timeout.is_connected(_on_main_timer_timeout):
	#     main_timer.timeout.connect(_on_main_timer_timeout)
	# if not ammo_cooldown_timer.timeout.is_connected(_on_ammo_cooldown_timeout):
	#     ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
	# if not sak_delay_timer.timeout.is_connected(_on_sak_delay_timer_timeout):
	#     sak_delay_timer.timeout.connect(_on_sak_delay_timer_timeout)
	
	# If we're the server, initialize the game
	if multiplayer.is_server():
		_initialize_server()
	
	# Set process to handle game timing
	set_process(false)

# Called by GameUI when it's ready
func register_game_ui(ui_instance: Node) -> void:
	if is_instance_valid(game_ui_instance):
		game_ui_instance.queue_free()
	game_ui_instance = ui_instance
	print("GameUI registered with GameManager")

# Called when GameUI is being removed
func unregister_game_ui(ui_instance: Node) -> void:
	if game_ui_instance == ui_instance:
		game_ui_instance = null
	print("GameUI unregistered from GameManager")




# Game state management
func set_game_state(new_state: GameState) -> void:
	if game_state == new_state:
		return
		
	game_state = new_state
	game_state_changed.emit(new_state)

# Player management
func on_player_eliminated(eliminated_player: Object, attacker: Object) -> void:
	if not is_instance_valid(eliminated_player) or not is_instance_valid(attacker):
		return
		
	player_eliminated.emit(eliminated_player, attacker)
	_check_win_conditions()

# Win condition checking
func _check_win_conditions() -> void:
	if not multiplayer.is_server():
		return
		
	# Add your win condition logic here
	# For example, check if all hiders are eliminated or time is up
	# Call game_ended.emit(winning_team) when game ends

# Ammo cooldown
func start_ammo_cooldown(duration: float) -> void:
	if not is_instance_valid(ammo_cooldown_timer):
		return
		
	ammo_cooldown_timer.start(duration)

func reset_to_lobby() -> void:
	"""Reset the game state back to the lobby."""
	game_state = GameState.LOBBY
	main_timer.stop()
	ammo_cooldown_timer.stop()
	
	# Reset player ready states
	for player_id in players:
		players[player_id]["ready"] = false
	
	# Emit signal to update UI
	game_state_changed.emit(game_state)

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
		
	match game_state:
		GameState.STARTING:
			_handle_starting_state(delta)
		GameState.IN_PROGRESS:
			_handle_in_progress_state(delta)
		GameState.GAME_OVER:
			_handle_game_over_state()

#region Server Functions
func _initialize_server() -> void:
	print("[GameManager] Initializing server...")
	# Register existing players if any
	if network_manager.players.size() > 0:
		for id in network_manager.players:
			_on_player_connected(id)
	
	# Start processing game logic
	set_process(true)

func start_game() -> void:
	if not multiplayer.is_server():
		return
	
	if players.size() < min_players:
		print("[GameManager] Not enough players to start game")
		return
	
	# Assign roles (1 seeker, rest are hiders)
	_assign_roles()
	
	# Set game state to starting
	change_game_state(GameState.STARTING)
	
	# Start countdown
	var countdown = int(game_start_delay)
	game_starting.emit(countdown)
	
	# Notify all clients to start the game
	rpc("_rpc_start_game", countdown)

func end_game(winning_team: String) -> void:
	if not multiplayer.is_server():
		return
	
	change_game_state(GameState.GAME_OVER)
	game_ended.emit(winning_team)
	rpc("_rpc_end_game", winning_team)

func change_game_state(new_state: GameState) -> void:
	if not multiplayer.is_server():
		return
		
	game_state = new_state
	game_state_changed.emit(new_state)
	rpc("_rpc_change_game_state", new_state)

func _assign_roles() -> void:
	if not multiplayer.is_server():
		return
	
	var player_ids = players.keys()
	if player_ids.is_empty():
		return
	
	# Randomly select one seeker
	var seeker_id = player_ids[randi() % player_ids.size()]
	
	for id in player_ids:
		var role = "seeker" if id == seeker_id else "hider"
		players[id]["role"] = role
		
		# Update the player's role in the network manager
		network_manager.update_player_role(id, role)
		
		# Notify the player of their role
		rpc_id(id, "_rpc_set_player_role", role)

#region State Handlers
func _handle_starting_state(delta: float) -> void:
	# This would handle the countdown logic
	# When countdown reaches 0, start the game
	pass

func _handle_in_progress_state(delta: float) -> void:
	# Main game loop logic
	pass

func _handle_game_over_state() -> void:
	# Handle game over state
	pass

#region Player Management
func _on_player_connected(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var player_data = network_manager.players.get(str(player_id), {})
	players[player_id] = {
		"name": player_data.get("name", "Player" + str(player_id)),
		"ready": false,
		"role": "",
		"score": 0
	}
	
	# Notify all clients about the new player
	rpc("_rpc_add_player", player_id, players[player_id])
	
	# Send current game state to the new player
	rpc_id(player_id, "_rpc_sync_game_state", players, game_state)
	
	player_joined.emit(player_id, players[player_id])

func _on_player_disconnected(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	players.erase(player_id)
	player_left.emit(player_id)
	
	# Notify all clients about the player leaving
	rpc("_rpc_remove_player", player_id)
	
	# If in progress and not enough players, end the game
	if game_state == GameState.IN_PROGRESS and players.size() < min_players:
		end_game("game_abandoned")

#region RPCs
@rpc("any_peer", "call_local", "reliable")
func set_player_ready(is_ready: bool) -> void:
	var player_id = multiplayer.get_remote_sender_id()
	if player_id in players:
		players[player_id]["ready"] = is_ready
		player_ready_changed.emit(player_id, is_ready)
		rpc("_rpc_update_player_ready", player_id, is_ready)
		
		# If all players are ready, start the game
		if multiplayer.is_server() and _all_players_ready():
			start_game()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game(countdown: int) -> void:
	game_starting.emit(countdown)
	# Additional game start logic for clients

@rpc("authority", "call_local", "reliable")
func _rpc_end_game(winning_team: String) -> void:
	game_ended.emit(winning_team)
	# Additional game end logic for clients

@rpc("authority", "call_local", "reliable")
func _rpc_change_game_state(new_state: GameState) -> void:
	game_state = new_state
	game_state_changed.emit(new_state)

@rpc("authority", "call_local", "reliable")
func _rpc_set_player_role(role: String) -> void:
	var player_id = multiplayer.get_remote_sender_id()
	if player_id in players:
		players[player_id]["role"] = role

@rpc("authority", "call_local", "reliable")
func _rpc_add_player(player_id: int, player_data: Dictionary) -> void:
	if player_id != multiplayer.get_unique_id():
		players[player_id] = player_data
		player_joined.emit(player_id, player_data)

@rpc("authority", "call_local", "reliable")
func _rpc_remove_player(player_id: int) -> void:
	players.erase(player_id)
	player_left.emit(player_id)

@rpc("authority", "call_local", "reliable")
func _rpc_update_player_ready(player_id: int, is_ready: bool) -> void:
	if player_id in players:
		players[player_id]["ready"] = is_ready
		player_ready_changed.emit(player_id, is_ready)

@rpc("authority", "call_local", "reliable")
func _rpc_sync_game_state(synced_players: Dictionary, current_state: GameState) -> void:
	players = synced_players.duplicate(true)
	game_state = current_state
	game_state_changed.emit(current_state)

#region Helper Functions
func _all_players_ready() -> bool:
	if players.size() < min_players:
		return false
	
	for player_data in players.values():
		if not player_data.get("ready", false):
			return false
	return true

func get_player_role(player_id: int) -> String:
	return players.get(player_id, {}).get("role", "")

func is_player_ready(player_id: int) -> bool:
	return players.get(player_id, {}).get("ready", false)

func get_player_count() -> int:
	return players.size()
