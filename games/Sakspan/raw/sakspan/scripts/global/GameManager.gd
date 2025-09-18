#res://scripts/GameManager.gd

class_name GameManager
extends Node

# Game State
enum GameState {
	LOBBY,              # Players are in lobby
	STARTING,           # Game is starting (for backward compatibility)
	WAITING_TO_START,   # Waiting to start (for compatibility)
	HIDER_HEADSTART,    # Hiders get a head start
	GAME_START_COUNTDOWN, # Final countdown before game starts
	IN_PROGRESS,        # Game is in progress
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

# Timers
@onready var main_timer: Timer = Timer.new()
@onready var ammo_cooldown_timer: Timer = Timer.new()
@onready var sak_delay_timer: Timer = Timer.new()

# Working game mechanics variables
var current_state: GameState = GameState.LOBBY

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
	
	# Connect timer signals
	main_timer.timeout.connect(_on_main_timer_timeout)
	ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
	sak_delay_timer.timeout.connect(_on_sak_delay_timer_timeout)
	
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
func on_player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter) -> void:
	# This function now only handles the kill feed. The win check is separate.
	var message = ""
	if attacker.role == PlayerCharacter.PlayerRole.SEEKER:
		message = attacker.player_name + " bonked " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER:
		if eliminated_player.role == PlayerCharacter.PlayerRole.SEEKER:
			message = attacker.player_name + " just bonked " + eliminated_player.player_name
		else:
			message = attacker.player_name + " accidentally bonked " + eliminated_player.player_name
	
	if game_ui_instance and game_ui_instance.has_method("show_kill_feed"):
		game_ui_instance.show_kill_feed(message)

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

func _process(delta: float) -> void:
	if current_state == GameState.GAME_START_COUNTDOWN:
		if game_ui_instance and game_ui_instance.has_method("update_countdown"):
			game_ui_instance.update_countdown(str(ceil(main_timer.time_left)), true)
	update_ui()
	
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
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("", false)
				game_ui_instance.update_countdown("10", true)
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
	if current_state == GameState.HIDER_HEADSTART:
		change_game_state(GameState.GAME_START_COUNTDOWN)
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
