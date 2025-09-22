#res://scripts/GameManager.gd
extends Node

# Game State
enum GameState {
	LOBBY,              # Players are in lobby
	STARTING,           # Game is starting (for backward compatibility)
	WAITING_TO_START,   # Waiting to start (for compatibility)
	PRE_GAME_FREEZE,    # Phase 1: All players frozen, role announcements (5s)
	HIDER_HEADSTART,    # Phase 2: Hiders move, Seeker blind (10s)
	GAME_START_COUNTDOWN, # Legacy countdown state (maps to SEEKER_RELEASED)
	SEEKER_RELEASED,    # Phase 3: Seeker released, Hiders can't attack (5s)
	IN_PROGRESS,        # Phase 4: Full gameplay active
	FINISHED,           # Game finished (for compatibility)
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

# Networked variables (Statically Typed)
var players: Dictionary = {}  # player_id: {name: String, ready: bool, role: String, ...}
var game_state: int = GameState.LOBBY
var current_round: int = 1
var match_start_time: float = 0.0
var game_ui_instance: Node = null  # Will be set by the GameUI scene when it loads

# Make this a proper singleton
static var instance: GameManager = null

# Timers (will be instantiated in _enter_tree)
var main_timer: Timer
var ammo_cooldown_timer: Timer
var sak_delay_timer: Timer
var phase_timer: Timer

# Working game mechanics variables
var current_state: GameState = GameState.LOBBY

func _enter_tree():
	if instance != null:
		queue_free()
		return
	instance = self
	
	# Initialize timers with correct sequence: Instantiate -> Add -> Configure
	
	# --- Main Game Timer ---
	main_timer = Timer.new()
	add_child(main_timer)
	main_timer.one_shot = true
	main_timer.timeout.connect(_on_main_timer_timeout)
	
	# --- Ammo Cooldown Timer ---
	ammo_cooldown_timer = Timer.new()
	add_child(ammo_cooldown_timer)
	ammo_cooldown_timer.one_shot = true
	ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
	
	# --- Sak Delay Timer ---
	sak_delay_timer = Timer.new()
	add_child(sak_delay_timer)
	sak_delay_timer.one_shot = true
	sak_delay_timer.timeout.connect(_on_sak_delay_timer_timeout)
	
	# --- Phase Timer (for staged gameplay) ---
	phase_timer = Timer.new()
	add_child(phase_timer)
	phase_timer.one_shot = true
	phase_timer.timeout.connect(_on_phase_timer_timeout)
	
	# Connect player elimination signal
	player_eliminated.connect(on_player_eliminated)
	
func _exit_tree():
	if instance == self:
		instance = null

# Game management functions

func check_win_conditions() -> void:
	await get_tree().process_frame # Wait one frame to ensure nodes are updated
	
	var all_hiders: Array[Node] = get_tree().get_nodes_in_group("hider")
	var all_seekers: Array[Node] = get_tree().get_nodes_in_group("seeker")
	
	var living_hiders_count: int = all_hiders.filter(func(hider): return (hider as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()
	var living_seekers_count: int = all_seekers.filter(func(seeker): return (seeker as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()

	var game_over: bool = false
	var winning_text: String = ""
	var seekers_win: bool = false

	if living_hiders_count == 0:
		winning_text = "SEEKERS WIN!"
		seekers_win = true
		game_over = true
		
	if living_seekers_count == 0:
		winning_text = "HIDERS WIN!"
		seekers_win = false
		game_over = true
		
	if game_over:
		print(winning_text)
		change_game_state(GameState.FINISHED)
		
		var players_list: Array[Node] = all_hiders + all_seekers
		for p in players_list:
			var player_instance: PlayerCharacter = p as PlayerCharacter
			if player_instance and player_instance.is_main_player:
				var did_i_win: bool = (player_instance.role == PlayerCharacter.PlayerRole.SEEKER and seekers_win) or \
								(player_instance.role == PlayerCharacter.PlayerRole.HIDER and not seekers_win)
				# Show game over UI if available
				if game_ui_instance and game_ui_instance.has_method("show_game_over"):
					game_ui_instance.show_game_over(did_i_win, winning_text)
				get_tree().paused = true
				break


# References (Statically Typed)
@onready var network_manager: Node = get_node_or_null("/root/NetworkManager")
@onready var world: Node2D = get_node_or_null("/root/World")

func _ready() -> void:
	# This function runs ONCE when the app starts.
	# Connect to tree_changed signal immediately - this is more reliable than external management
	get_tree().tree_changed.connect(_on_tree_changed)
	print("[GameManager] GameManager singleton is ready and listening for scene tree changes.")
	
	# Set process to handle game timing
	set_process(false)

# ROBUST: Self-managing scene detection that only activates during multiplayer sessions
func _on_tree_changed() -> void:
	"""Robust entry point for game loop - only activates when multiplayer session exists"""
	# We only care about this signal if a multiplayer session is active
	if not multiplayer.has_multiplayer_peer():
		return
	
	# We only care if the SERVER peer has just loaded the dev_world
	if not multiplayer.is_server():
		return
	
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path == "res://scenes/dev/dev_world.tscn":
		# Disconnect the signal to prevent it from running multiple times
		if get_tree().tree_changed.is_connected(_on_tree_changed):
			get_tree().tree_changed.disconnect(_on_tree_changed)
		
		print("[GameManager] 🎯 Detected dev_world scene load on server. Initializing game...")
		initialize_game_world()

# ROBUST: Self-contained game world initialization
func initialize_game_world() -> void:
	"""Initialize the game world - called automatically when dev_world scene loads"""
	if not multiplayer.is_server():
		print("[GameManager] ❌ initialize_game_world() called on client - ignoring")
		return
	
	print("[GameManager] 🏠 SERVER: Initializing game world...")
	
	# Initialize network manager reference
	if not network_manager:
		network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		push_error("NetworkManager not found!")
		return
	
	print("[GameManager] ✅ NetworkManager found with ", network_manager.players.size(), " players")
	
	# --- All game setup logic starts here ---
	# 1. Initialize timers and signals
	_initialize_game_timers()
	
	# 2. Spawn all players
	_spawn_all_players()
	
	# 3. Perform server initialization
	_initialize_server()
	
	# 4. Auto-start the game if we have players (for dev testing)
	if players.size() > 0:
		print("[GameManager] 🎮 Auto-starting game with ", players.size(), " players")
		# Wait a frame to ensure everything is initialized
		await get_tree().process_frame
		start_game()
	else:
		print("[GameManager] ⏳ Waiting for players to join before starting game")
	
	print("[GameManager] ✅ Game world initialization complete via robust scene detection")

# Comprehensive player spawning system
func _spawn_all_players() -> void:
	"""Spawn all players from NetworkManager data with proper type handling"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🎭 Spawning all players...")
	var players_dict = network_manager.players
	
	if players_dict.is_empty():
		print("[GameManager] ⚠️  No players to spawn")
		return
	
	# Get spawn points from dev_world
	var spawn_points: Array[Vector2] = [Vector2(100, 0), Vector2(-100, 0), Vector2(0, 100), Vector2(0, -100)]
	
	# Convert keys to integers and sort for deterministic spawn order
	var int_ids: Array[int] = []
	for key in players_dict.keys():
		int_ids.append(int(key))
	int_ids.sort()
	
	# Spawn each player via RPC with correct data types
	for i in range(min(int_ids.size(), spawn_points.size())):
		var player_id: int = int_ids[i]
		var player_data: Dictionary = players_dict[player_id]
		print("[GameManager] 🎭 Spawning player ", player_id, " with data: ", player_data)
		_spawn_player_on_all_clients.rpc(player_id, player_data, spawn_points[i])

@rpc("authority", "call_local", "reliable")
func _spawn_player_on_all_clients(player_id: int, player_data: Dictionary, spawn_pos: Vector2) -> void:
	"""Spawn a single player on all clients with correct type handling"""
	print("[GameManager] 🎭 Creating player ", player_id, " at ", spawn_pos)
	
	# Create player instance
	var player_scene = preload("res://scenes/player/Player.tscn")
	var new_player = player_scene.instantiate()
	
	# Set up multiplayer authority
	new_player.set_multiplayer_authority(player_id)
	new_player.name = "Player_" + str(player_id)
	
	# Find players container in dev_world
	var players_container = get_tree().get_first_node_in_group("players_container")
	if not players_container:
		# Fallback to finding by path
		players_container = get_node_or_null("/root/DevWorld/PlayersContainer")
	
	if players_container:
		# The 'true' parameter allows the spawner to use the name we already assigned (the peer_id)
		players_container.add_child(new_player, true)
	else:
		push_error("[GameManager] Could not find PlayersContainer!")
		return
	
	# Position the player
	new_player.global_position = spawn_pos
	
	# Configure player properties with CORRECT data types
	if new_player.has_method("setup_multiplayer_player"):
		var is_local: bool = (player_id == multiplayer.get_unique_id())
		# CRITICAL FIX: Pass Dictionary and boolean, not int and boolean
		new_player.setup_multiplayer_player(player_data, is_local)
	
	# PHASE 1: Grant immediate movement and attack capabilities for MPS testing
	if new_player.has_method("enable_basic_controls"):
		new_player.enable_basic_controls()
	else:
		# Fallback: Set basic control flags directly
		new_player.can_move = true
		new_player.can_attack = true
	
	print("[GameManager] ✅ Successfully created player ", player_id, " (", player_data.get("name", "Unknown"), ") at ", spawn_pos)

# REMOVED: Old _on_scene_changed function replaced with robust _on_tree_changed approach

# Initialize game timers and signals
func _initialize_game_timers() -> void:
	"""Initialize all timers and connect game-specific signals"""
	print("[GameManager] 🕐 Initializing game timers...")
	
	# Create and configure phase timer if not exists
	if not phase_timer:
		phase_timer = Timer.new()
		add_child(phase_timer)
		phase_timer.one_shot = true
		phase_timer.timeout.connect(_on_phase_timer_timeout)
	
	# Create and configure main timer if not exists
	if not main_timer:
		main_timer = Timer.new()
		add_child(main_timer)
		main_timer.one_shot = true
		main_timer.timeout.connect(_on_main_timer_timeout)
	
	# Create and configure ammo cooldown timer if not exists
	if not ammo_cooldown_timer:
		ammo_cooldown_timer = Timer.new()
		add_child(ammo_cooldown_timer)
		ammo_cooldown_timer.one_shot = true
		ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
	
	print("[GameManager] ✅ Game timers initialized")

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
func on_player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter) -> void:
	# Generate custom kill feed messages based on roles
	var message = ""
	
	if attacker.role == PlayerCharacter.PlayerRole.SEEKER and eliminated_player.role == PlayerCharacter.PlayerRole.HIDER:
		# Seeker eliminates Hider
		message = attacker.player_name + " just bonked " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER and eliminated_player.role == PlayerCharacter.PlayerRole.SEEKER:
		# Hider eliminates Seeker
		message = attacker.player_name + " just KO'ed " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER and eliminated_player.role == PlayerCharacter.PlayerRole.HIDER:
		# Hider accidentally eliminates another Hider
		message = attacker.player_name + " was jumpscared and accidentally hit " + eliminated_player.player_name + "!!"
	else:
		# Fallback for any other cases
		message = attacker.player_name + " eliminated " + eliminated_player.player_name
	
	print("[GameManager] Kill feed: ", message)
	
	# Show kill feed globally via RPC
	_show_kill_feed.rpc(message)

# Initialize game with proper role assignment and ammo
func initialize_game() -> void:
	var players_list: Array[Node] = get_tree().get_nodes_in_group("hider") + get_tree().get_nodes_in_group("seeker")
	for p in players_list:
		var player_instance: PlayerCharacter = p as PlayerCharacter
		if player_instance and player_instance.is_main_player:
			if game_ui_instance and game_ui_instance.has_method("initialize"):
				game_ui_instance.initialize(player_instance)
			break
			
	var all_hiders: Array[Node] = get_tree().get_nodes_in_group("hider")
	var all_seekers: Array[Node] = get_tree().get_nodes_in_group("seeker")
	if all_seekers.is_empty(): return
	
	var seeker: PlayerCharacter = all_seekers[0] as PlayerCharacter
	if seeker:
		seeker.set_ammo(all_hiders.size() + 1)
		print("[GameMaster] Seeker ammo set to: ", seeker.ammo)

	update_ui()
	change_game_state(GameState.HIDER_HEADSTART)

func update_ui() -> void:
	if not game_ui_instance: return
	
	var living_hiders_count: int = get_tree().get_nodes_in_group("hider").filter(func(hider): return (hider as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()
	if game_ui_instance.has_method("update_hiders_left"):
		game_ui_instance.update_hiders_left(living_hiders_count)
	
	var seekers: Array[Node] = get_tree().get_nodes_in_group("seeker")
	if not seekers.is_empty():
		var seeker: PlayerCharacter = seekers[0] as PlayerCharacter
		if seeker and game_ui_instance.has_method("update_ammo"):
			game_ui_instance.update_ammo(seeker.ammo)
	
	# Update announcer text based on current game state
	_update_announcer_text()

# Dynamic announcer text updates
func _update_announcer_text() -> void:
	"""Update announcer text based on current game state"""
	var announcer_text = ""
	var show_announcer = true
	
	match current_state:
		GameState.LOBBY:
			announcer_text = "Waiting for players..."
		GameState.STARTING:
			announcer_text = "Game starting..."
		GameState.WAITING_TO_START:
			announcer_text = "Preparing game..."
		GameState.PRE_GAME_FREEZE:
			announcer_text = "Role assignments complete!"
		GameState.HIDER_HEADSTART:
			announcer_text = "Hiders, GO! Find hiding spots!"
		GameState.GAME_START_COUNTDOWN:
			announcer_text = "Seeker preparing to hunt..."
		GameState.SEEKER_RELEASED:
			announcer_text = "The Seeker is on the move!"
		GameState.IN_PROGRESS:
			announcer_text = "The Hunt is On!"
		GameState.FINISHED:
			announcer_text = "Game Over"
		GameState.GAME_OVER:
			announcer_text = "Match ended"
		_:
			announcer_text = "Waiting for players..."
			show_announcer = false
	
	# Send announcer update to all clients
	if multiplayer.is_server():
		_rpc_update_announcer.rpc(announcer_text, show_announcer)
	elif game_ui_instance and game_ui_instance.has_method("update_status"):
		game_ui_instance.update_status(announcer_text, show_announcer)

@rpc("authority", "call_local", "reliable")
func _rpc_update_announcer(text: String, show: bool) -> void:
	"""RPC to update announcer text on all clients"""
	if game_ui_instance and game_ui_instance.has_method("update_status"):
		game_ui_instance.update_status(text, show)

# Ammo cooldown
func start_ammo_cooldown(duration: float = 5.0) -> void:
	print("Seeker is out of ammo! Starting ", duration, "-second cooldown...")
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

var _last_countdown_value: int = -1

func _process(delta: float) -> void:
	# Do not run process logic if we are not in a networked game yet
	if not multiplayer.has_multiplayer_peer():
		return
		
	# Handle countdown display (only update when value changes)
	if current_state == GameState.GAME_START_COUNTDOWN or current_state == GameState.SEEKER_RELEASED:
		if game_ui_instance and game_ui_instance.has_method("update_countdown"):
			var current_countdown = int(ceil(phase_timer.time_left))
			if current_countdown != _last_countdown_value:
				_last_countdown_value = current_countdown
				game_ui_instance.update_countdown(str(current_countdown), true)
	
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
	
	# Initialize the game mechanics
	initialize_game()
	
	# Start Phase 1: Pre-Game Freeze (5 seconds)
	_start_phase_1_freeze()

# Phase 1: Role Assignment & Freeze (5 seconds)
func _start_phase_1_freeze():
	print("[GameManager] Starting Phase 1: Pre-Game Freeze (5s)")
	change_game_state(GameState.PRE_GAME_FREEZE)
	
	# Freeze all players
	_set_all_players_movement(false)
	_set_all_players_attack(false)
	
	# Show role announcements to all clients
	_show_role_announcements.rpc()
	
	# Start 5-second timer for Phase 1
	phase_timer.wait_time = 5.0
	phase_timer.start()

# Phase 2: Hider Head Start & Seeker Blindness (10 seconds)
func _start_phase_2_hider_headstart():
	print("[GameManager] Starting Phase 2: Hider Head Start (10s)")
	change_game_state(GameState.HIDER_HEADSTART)
	
	# Enable movement for Hiders only
	_set_hiders_movement(true)
	_set_seekers_movement(false)
	
	# Blind the Seeker
	_activate_seeker_blindness.rpc()
	
	# Show countdown to all players
	_show_countdown.rpc(10)
	
	# Start 10-second timer for Phase 2
	phase_timer.wait_time = 10.0
	phase_timer.start()

# Phase 3: Seeker Release & Hider Attack Delay (5 seconds)
func _start_phase_3_seeker_released():
	print("[GameManager] Starting Phase 3: Seeker Released (5s)")
	change_game_state(GameState.SEEKER_RELEASED)
	
	# Enable Seeker movement and vision
	_set_seekers_movement(true)
	_deactivate_seeker_blindness.rpc()
	
	# Keep Hider attacks disabled
	_set_hiders_attack(false)
	_set_seekers_attack(true)
	
	# Show announcement
	_show_announcement.rpc("The Seeker is on the move!")
	
	# Start 5-second timer for Phase 3
	phase_timer.wait_time = 5.0
	phase_timer.start()

# Phase 4: Full Gameplay Begins
func _start_phase_4_full_gameplay():
	print("[GameManager] Starting Phase 4: Full Gameplay")
	change_game_state(GameState.IN_PROGRESS)
	
	# Enable all abilities for all players
	_set_all_players_movement(true)
	_set_all_players_attack(true)
	
	# Show role-specific announcements
	_show_seeker_warning.rpc()
	_show_hider_warning.rpc()
	
	# Start main game timer (if needed)
	match_start_time = Time.get_time_dict_from_system()["unix"]

# Phase timer timeout handler
func _on_phase_timer_timeout():
	if not multiplayer.is_server():
		return
	
	match current_state:
		GameState.PRE_GAME_FREEZE:
			_start_phase_2_hider_headstart()
		GameState.HIDER_HEADSTART:
			_start_phase_3_seeker_released()
		GameState.SEEKER_RELEASED:
			_start_phase_4_full_gameplay()

# Player control helper functions
func _set_all_players_movement(enabled: bool):
	_set_players_movement_by_role.rpc("all", enabled)

func _set_all_players_attack(enabled: bool):
	_set_players_attack_by_role.rpc("all", enabled)

func _set_hiders_movement(enabled: bool):
	_set_players_movement_by_role.rpc("hider", enabled)

func _set_seekers_movement(enabled: bool):
	_set_players_movement_by_role.rpc("seeker", enabled)

func _set_hiders_attack(enabled: bool):
	_set_players_attack_by_role.rpc("hider", enabled)

func _set_seekers_attack(enabled: bool):
	_set_players_attack_by_role.rpc("seeker", enabled)

func end_game(winning_team: String) -> void:
	if not multiplayer.is_server():
		return
	
	change_game_state(GameState.GAME_OVER)
	game_ended.emit(winning_team)
	rpc("_rpc_end_game", winning_team)

func change_game_state(new_state: GameState) -> void:
	if current_state == new_state: return
	current_state = new_state
	game_state = new_state  # Keep both for compatibility
	game_state_changed.emit(new_state)
	print("Game state changed to: ", GameState.keys()[new_state])
	
	# Sync to clients if we're the server
	if multiplayer.is_server():
		rpc("_rpc_change_game_state", new_state)
	
	match new_state:
		GameState.HIDER_HEADSTART:
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("Hiders, GO! Seeker is frozen.", true)
			main_timer.start(5.0)
		GameState.GAME_START_COUNTDOWN:
			# Legacy state - redirect to SEEKER_RELEASED behavior
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("The Seeker is on the move!", true)
				game_ui_instance.update_countdown("5", true)
			main_timer.start(10.0)
		GameState.IN_PROGRESS:
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("The Hunt is On!", true)
				game_ui_instance.update_countdown("GO!", false)
			sak_delay_timer.start(3.0)
		GameState.FINISHED:
			ammo_cooldown_timer.stop()

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
	current_state = new_state
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

# --- GAMEMASTER AUTHORITY FUNCTIONS ---

# Handle player action requests (Server Authority)
@rpc("any_peer", "reliable")
func request_player_action(player_id: int, action: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		print("[GameMaster] Action request mismatch: sender ", sender_id, " vs player ", player_id)
		return
	
	match action:
		"fire_projectile":
			_handle_fire_request(player_id)
		"sak_attack":
			_handle_sak_request(player_id)
		_:
			print("[GameMaster] Unknown action: ", action)

func _handle_fire_request(player_id: int) -> void:
	var player: PlayerCharacter = _get_player_by_id(player_id)
	if not player or player.role != PlayerCharacter.PlayerRole.SEEKER:
		return
	
	if player.ammo <= 0 or not player.can_attack:
		return
	
	# Approve the action
	player.ammo -= 1
	print("[GameMaster] Approved fire for player ", player_id, ". Ammo remaining: ", player.ammo)
	
	# Execute on all clients
	execute_player_fire.rpc(player_id)
	
	# Start cooldown if out of ammo
	if player.ammo == 0:
		start_ammo_cooldown()

func _handle_sak_request(player_id: int) -> void:
	var player: PlayerCharacter = _get_player_by_id(player_id)
	if not player or player.role != PlayerCharacter.PlayerRole.HIDER:
		return
	
	if not player.can_attack:
		return
	
	# Find valid targets in melee range
	var nearby_players: Array[Node2D] = player.melee_range.get_overlapping_bodies()
	var target: PlayerCharacter = null
	
	for body in nearby_players:
		var potential_target: PlayerCharacter = body as PlayerCharacter
		if potential_target and potential_target != player and potential_target.current_state == PlayerCharacter.PlayerState.ALIVE:
			target = potential_target
			break
	
	if not target:
		return
	
	print("[GameMaster] Approved SAK for player ", player_id, " on target ", target.get_multiplayer_authority())
	
	# Execute on all clients
	execute_player_sak.rpc(player_id, target.get_multiplayer_authority())

@rpc("authority", "call_local", "reliable")
func execute_player_fire(player_id: int) -> void:
	var player: PlayerCharacter = _get_player_by_id(player_id)
	if player:
		player.execute_fire_projectile()

@rpc("authority", "call_local", "reliable")
func execute_player_sak(attacker_id: int, target_id: int) -> void:
	var attacker: PlayerCharacter = _get_player_by_id(attacker_id)
	var target: PlayerCharacter = _get_player_by_id(target_id)
	if attacker and target:
		attacker.execute_sak_attack(target)

# === STAGED GAMEPLAY RPCs ===

@rpc("authority", "call_local", "reliable")
func _show_role_announcements():
	"""Show role announcements to all clients"""
	print("[GameManager] Showing role announcements")
	# Find local player and show their role
	var local_player = _get_local_player()
	if local_player and local_player.has_method("show_role_overlay"):
		local_player.show_role_overlay()

@rpc("authority", "call_local", "reliable")
func _set_players_movement_by_role(role_filter: String, enabled: bool):
	"""Set movement for players by role"""
	var local_player = _get_local_player()
	if not local_player:
		return
	
	var should_apply = false
	if role_filter == "all":
		should_apply = true
	elif role_filter == "seeker" and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		should_apply = true
	elif role_filter == "hider" and local_player.role == PlayerCharacter.PlayerRole.HIDER:
		should_apply = true
	
	if should_apply:
		local_player.can_move = enabled
		print("[GameManager] Set movement to ", enabled, " for ", role_filter, " (local player)")

@rpc("authority", "call_local", "reliable")
func _set_players_attack_by_role(role_filter: String, enabled: bool):
	"""Set attack ability for players by role"""
	var local_player = _get_local_player()
	if not local_player:
		return
	
	var should_apply = false
	if role_filter == "all":
		should_apply = true
	elif role_filter == "seeker" and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		should_apply = true
	elif role_filter == "hider" and local_player.role == PlayerCharacter.PlayerRole.HIDER:
		should_apply = true
	
	if should_apply:
		local_player.can_attack = enabled
		print("[GameManager] Set attack to ", enabled, " for ", role_filter, " (local player)")

@rpc("authority", "call_local", "reliable")
func _activate_seeker_blindness():
	"""Activate blindness UI for Seeker clients"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		print("[GameManager] Activating Seeker blindness")
		# Add blindness overlay to Seeker's UI
		_create_blindness_overlay()

@rpc("authority", "call_local", "reliable")
func _deactivate_seeker_blindness():
	"""Deactivate blindness UI for Seeker clients"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		print("[GameManager] Deactivating Seeker blindness")
		# Remove blindness overlay
		_remove_blindness_overlay()

@rpc("authority", "call_local", "reliable")
func _show_countdown(seconds: int):
	"""Show countdown timer to all players"""
	print("[GameManager] Showing countdown: ", seconds, " seconds")
	# This would integrate with the GameUI to show countdown

@rpc("authority", "call_local", "reliable")
func _show_announcement(message: String):
	"""Show announcement to all players"""
	print("[GameManager] Announcement: ", message)
	# This would integrate with the GameUI to show announcement

@rpc("authority", "call_local", "reliable")
func _show_seeker_warning():
	"""Show Seeker-specific warning"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		print("[GameManager] Seeker warning: Hiders can now 'Sak'! Be wary.")
		# Show warning in UI

@rpc("authority", "call_local", "reliable")
func _show_hider_warning():
	"""Show Hider-specific warning"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.HIDER:
		print("[GameManager] Hider warning: You can now 'Sak'! Be careful not to hit other Hiders.")
		# Show warning in UI

# Helper functions for staged gameplay
func _get_local_player() -> PlayerCharacter:
	"""Get the local player instance"""
	var players_in_scene = get_tree().get_nodes_in_group("players")
	for player in players_in_scene:
		if player.is_multiplayer_authority():
			return player as PlayerCharacter
	return null

func _create_blindness_overlay():
	"""Create black overlay for Seeker blindness"""
	var blindness_overlay = ColorRect.new()
	blindness_overlay.name = "SeekerBlindnessOverlay"
	blindness_overlay.color = Color.BLACK
	blindness_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blindness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add to the main scene
	get_tree().current_scene.add_child(blindness_overlay)

func _remove_blindness_overlay():
	"""Remove Seeker blindness overlay"""
	var overlay = get_tree().current_scene.get_node_or_null("SeekerBlindnessOverlay")
	if overlay:
		overlay.queue_free()

@rpc("authority", "call_local", "reliable")
func _show_kill_feed(message: String):
	"""Show kill feed message to all clients"""
	print("[GameManager] Kill feed message: ", message)
	
	# Find GameUI instance and show kill feed
	if game_ui_instance and game_ui_instance.has_method("show_kill_feed"):
		game_ui_instance.show_kill_feed(message)
	else:
		# Fallback: try to find dev_game_ui
		var dev_ui = get_tree().current_scene.get_node_or_null("GameUI")
		if dev_ui and dev_ui.has_method("show_kill_feed"):
			dev_ui.show_kill_feed(message)

@rpc("any_peer", "reliable")
func create_projectile(player_id: int, position: Vector2, rotation: float) -> void:
	if not multiplayer.is_server():
		return
	
	# Create projectile on server and sync to all clients
	spawn_projectile.rpc(player_id, position, rotation)

@rpc("authority", "call_local", "reliable")
func spawn_projectile(player_id: int, position: Vector2, rotation: float) -> void:
	var player: PlayerCharacter = _get_player_by_id(player_id)
	if not player:
		return
	
	var rock_scene: PackedScene = preload("res://scenes/RockProjectile.tscn")
	var rock: Node = rock_scene.instantiate()
	if "owner_player" in rock:
		rock.owner_player = player
	rock.global_position = position
	rock.rotation = rotation
	get_tree().get_root().add_child(rock)

@rpc("any_peer", "reliable")
func execute_elimination(target_id: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var target: PlayerCharacter = _get_player_by_id(target_id)
	var attacker: PlayerCharacter = _get_player_by_id(attacker_id)
	
	if target and attacker:
		print("[GameMaster] Executing elimination: ", attacker.player_name, " eliminated ", target.player_name)
		sync_elimination.rpc(target_id, attacker_id)

@rpc("authority", "call_local", "reliable")
func sync_elimination(target_id: int, attacker_id: int) -> void:
	var target: PlayerCharacter = _get_player_by_id(target_id)
	var attacker: PlayerCharacter = _get_player_by_id(attacker_id)
	
	if target and attacker:
		target.eliminate(attacker)

@rpc("any_peer", "reliable")
func handle_player_vision(seeker_id: int, target_id: int, is_visible: bool) -> void:
	if not multiplayer.is_server():
		return
	
	# GameMaster can log vision events, apply effects, etc.
	var seeker: PlayerCharacter = _get_player_by_id(seeker_id)
	var target: PlayerCharacter = _get_player_by_id(target_id)
	
	if seeker and target:
		if is_visible:
			print("[GameMaster] ", seeker.player_name, " spotted ", target.player_name)
		else:
			print("[GameMaster] ", seeker.player_name, " lost sight of ", target.player_name)

func _get_player_by_id(player_id: int) -> PlayerCharacter:
	var world_node: Node = get_node_or_null("/root/World")
	if not world_node:
		return null
	
	var players_container: Node = world_node.get_node_or_null("Players")
	if not players_container:
		return null
	
	var player_node: Node = players_container.get_node_or_null("Player_" + str(player_id))
	return player_node as PlayerCharacter

# --- SIGNAL HANDLERS ---

func _on_main_timer_timeout() -> void:
	# Legacy timer handler - integrate with new staged system
	if current_state == GameState.HIDER_HEADSTART:
		change_game_state(GameState.GAME_START_COUNTDOWN)  # Legacy transition
	elif current_state == GameState.GAME_START_COUNTDOWN:
		change_game_state(GameState.IN_PROGRESS)

func _on_ammo_cooldown_timeout() -> void:
	var seekers: Array[Node] = get_tree().get_nodes_in_group("seeker")
	if seekers.is_empty(): return
	var seeker: PlayerCharacter = seekers[0] as PlayerCharacter
	if seeker and seeker.current_state == PlayerCharacter.PlayerState.ALIVE:
		seeker.ammo += 1
		print("[GameMaster] Seeker ammo restored: ", seeker.ammo)

func _on_sak_delay_timer_timeout() -> void:
	for hider in get_tree().get_nodes_in_group("hider"):
		var hider_player: PlayerCharacter = hider as PlayerCharacter
		if hider_player:
			hider_player.can_attack = true
	print("[GameMaster] Hiders can now SAK!")
