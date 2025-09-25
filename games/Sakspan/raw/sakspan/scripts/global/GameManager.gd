#res://scripts/GameManager.gd
extends Node

# Game State
enum GameState {
	LOBBY,              # Players are in lobby
	STARTING,           # Game is starting (for backward compatibility)
	WAITING_TO_START,   # Waiting to start (for compatibility)
	ROLE_TRANSITION,    # Phase 0: Players transition to seeker/hider roles (2s)
	PRE_GAME_FREEZE,    # Phase 1: All players frozen, role announcements (5s)
	HIDER_HEADSTART,    # Phase 2: Hiders move, Seeker frozen (10s countdown)
	GAME_START_COUNTDOWN, # Legacy countdown state (maps to SEEKER_RELEASED)
	SEEKER_RELEASED,    # Phase 3: Seeker moves/attacks, Hiders can't SAK (5s)
	SAK_DELAY_ACTIVE,   # Phase 4: Hiders still can't SAK, Seeker active (5s)
	IN_PROGRESS,        # Phase 5: Full gameplay active with all mechanics
	FINISHED,           # Game finished (for compatibility)
	GAME_OVER           # Game has ended
}

# Signals
signal game_state_changed(new_state: GameState)
signal game_ended(winning_team: String)
signal player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter)
signal player_joined(player_id: int, player_data: Dictionary)
signal player_left(player_id: int)
signal player_ready_changed(player_id: int, is_ready: bool)
signal game_starting(countdown: int)
signal seeker_revealed(seeker_name: String, seeker_character: String)
signal prep_countdown_updated(time_remaining: int)

# Configuration
@export var game_start_delay: float = 5.0  # 5 seconds countdown
@export var min_players: int = 2
@export var max_players: int = 5

# Networked variables (Statically Typed)
var players: Dictionary = {}  # player_id: {name: String, ready: bool, role: String, ...}
var current_round: int = 1
var match_start_time: float = 0.0
var game_ui_instance: Node = null  # Will be set by the GameUI scene when it loads

# Master Clock System - Server-Authoritative Timing
var current_countdown_value: int = 0
var next_state_after_countdown: GameState

# Make this a proper singleton
static var instance: GameManager = null

# Timers (will be instantiated in _enter_tree)
var master_clock: Timer  # The single source of truth for all timing
var main_timer: Timer
var ammo_cooldown_timer: Timer
var sak_delay_timer: Timer
var ammo_regen_timer: Timer
var game_over_timer: Timer
var players_disabled: bool = false
# phase_timer removed - replaced by master clock system

# Working game mechanics variables
var current_state: GameState = GameState.LOBBY
var game_state: GameState = GameState.LOBBY  # Legacy compatibility - kept in sync with current_state
var total_players: int = 0
var max_ammo_capacity: int = 0  # Will be set to total player count
var sak_delay_active: bool = false  # Prevents hiders from SAK during delay
# REMOVED: var seeker_can_attack - replaced with granular can_bang system

func _enter_tree():
	if instance != null:
		queue_free()
		return
	instance = self

func _initialize_timers():
	"""Initialize scene-specific game timers (called when dev_world loads)"""
	# Scene-specific timers that get recreated for each game session
	if not sak_delay_timer:
		sak_delay_timer = Timer.new()
		sak_delay_timer.wait_time = 3.0
		sak_delay_timer.one_shot = true
		sak_delay_timer.timeout.connect(_on_sak_delay_timer_timeout)
		add_child(sak_delay_timer)
	
	# phase_timer removed - replaced by master clock system
	
	if not ammo_regen_timer:
		ammo_regen_timer = Timer.new()
		ammo_regen_timer.wait_time = 0.5  # 0.5 seconds per stone regeneration
		ammo_regen_timer.one_shot = false
		ammo_regen_timer.timeout.connect(_on_ammo_regen_timer_timeout)
		add_child(ammo_regen_timer)
	
	print("[GameManager] ✅ Scene-specific game timers initialized")

func _cleanup_scene_timers():
	"""Clean up scene-specific timers when returning to lobby"""
	if sak_delay_timer and is_instance_valid(sak_delay_timer):
		sak_delay_timer.stop()
		sak_delay_timer.queue_free()
		sak_delay_timer = null
	
	# phase_timer removed - replaced by master clock system
	
	if ammo_regen_timer and is_instance_valid(ammo_regen_timer):
		ammo_regen_timer.stop()
		ammo_regen_timer.queue_free()
		ammo_regen_timer = null
	
	print("[GameManager] ✅ Scene-specific timers cleaned up")

func _exit_tree():
	if instance == self:
		instance = null

# Game management functions

# REMOVED: Duplicate check_win_conditions function - using the enhanced version below


# References (Statically Typed)
@onready var network_manager: Node = get_node_or_null("/root/NetworkManager")
@onready var world: Node2D = get_node_or_null("/root/World")

func _ready() -> void:
	# This function runs ONCE when the app starts.
	# GameManager is now PURELY PASSIVE - only responds to NetworkManager signals
	print("[GameManager] 🔧 DEBUG: _ready() called - current_state: ", GameState.keys()[current_state])
	print("[GameManager] 🔧 DEBUG: Multiplayer peer ID: ", multiplayer.get_unique_id())
	print("[GameManager] 🔧 DEBUG: Is server: ", multiplayer.is_server())
	
	if NetworkManager:
		NetworkManager.all_peers_verified_and_ready.connect(_on_all_peers_ready)
		print("[GameManager] ✅ DEBUG: Successfully connected to all_peers_verified_and_ready signal")
	else:
		print("[GameManager] ❌ DEBUG: NetworkManager not found during _ready()!")
	
	# Connect player elimination signal
	player_eliminated.connect(_on_player_eliminated)
	
	# Initialize singleton-level timers that persist across scene transitions
	_initialize_singleton_timers()
	
	print("[GameManager] GameManager singleton is ready and listening for NetworkManager ready signal.")
	
	# Connect all timer signals ONCE in _ready() - no more dynamic connections
	if master_clock:
		# Use a callable with proper binding to ensure 'self' context is preserved
		master_clock.timeout.connect(_on_master_clock_tick.bind())
		print("[GameManager] ✅ DEBUG: master_clock connected to _on_master_clock_tick")
	else:
		print("[GameManager] ❌ DEBUG: master_clock is null during _ready()!")
	
	# DEBUG: Manual trigger for testing (remove in production)
	print("[GameManager] DEBUG: To manually trigger role assignment, call GameManager.debug_start_role_assignment()")
	print("[GameManager] DEBUG: To test signal handler, call GameManager.debug_test_signal_handler()")
	print("[GameManager] DEBUG: To test RPC calls, call GameManager.debug_test_rpc_calls()")
	print("[GameManager] DEBUG: To test complete system integration, call GameManager.debug_test_complete_system()")
	print("[GameManager] DEBUG: To test dev_world initialization, call GameManager.debug_test_dev_world_init()")
	print("[GameManager] DEBUG: To test scene transition, call NetworkManager.debug_transition_to_dev_world()")
	
	# Set process to handle game timing
	set_process(false)

func _initialize_singleton_timers():
	"""Initialize timers that persist across scene transitions"""
	# Master Clock - The single source of truth for all timing (SINGLETON LEVEL)
	if not master_clock:
		master_clock = Timer.new()
		master_clock.wait_time = 1.0
		master_clock.one_shot = false
		# Signal connection moved to _ready() to prevent duplicate connections
		add_child(master_clock)
		print("[GameManager] ✅ Master Clock initialized at singleton level")
	
	# Other persistent timers that need to survive scene transitions
	if not main_timer:
		main_timer = Timer.new()
		main_timer.wait_time = 1.0
		main_timer.one_shot = true
		main_timer.timeout.connect(_on_main_timer_timeout)
		add_child(main_timer)
	
	if not ammo_cooldown_timer:
		ammo_cooldown_timer = Timer.new()
		ammo_cooldown_timer.wait_time = 5.0
		ammo_cooldown_timer.one_shot = true
		ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
		add_child(ammo_cooldown_timer)
	
	print("[GameManager] ✅ Singleton-level timers initialized")

# PHASE 2: GamePrep Role Assignment System
func start_role_assignment() -> void:
	"""Called by GamePrep scene to begin role assignment and countdown"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🎭 Starting role assignment in GamePrep scene...")
	
	# Get all connected players from NetworkManager
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		print("[GameManager] ❌ NetworkManager not found!")
		return
	
	var players_dict = network_manager.players
	var player_ids = players_dict.keys()
	
	if player_ids.size() < 1:
		print("[GameManager] ❌ Not enough players for role assignment")
		return
	
	print("[GameManager] 🎮 Found ", player_ids.size(), " players for role assignment")
	
	# Randomly select seeker
	var seeker_id = player_ids[randi() % player_ids.size()]
	var seeker_data = players_dict[seeker_id]
	var seeker_name = seeker_data.get("name", "Unknown Player")
	
	print("[GameManager] 🎯 Selected seeker: ", seeker_name, " (ID: ", seeker_id, ")")
	
	# Store seeker information in NetworkManager for later use
	for pid in player_ids:
		players_dict[pid]["is_seeker"] = (pid == seeker_id)
	
	# Broadcast seeker information to all clients via RPC
	rpc_update_seeker_info.rpc(seeker_name, "Character") # TODO: Add character info
	
	# Start 5-second countdown before transitioning to dev_world
	start_prep_countdown(5)

func start_prep_countdown(duration: int) -> void:
	"""Start the GamePrep countdown before transitioning to dev_world"""
	if not multiplayer.is_server():
		return
	
	current_countdown_value = duration
	print("[GameManager] ⏰ Starting GamePrep countdown: ", duration, " seconds")
	
	# Broadcast initial countdown via RPC
	rpc_update_prep_countdown.rpc(current_countdown_value)
	
	# Start master clock for countdown - state-based logic will handle it
	if master_clock:
		master_clock.start()

# _on_prep_countdown_tick() - REMOVED: Logic moved to _on_master_clock_tick() for state-based handling

# DEBUG FUNCTIONS - Remove in production
func debug_start_role_assignment() -> void:
	"""Manual trigger for role assignment - for testing only"""
	if not multiplayer.is_server():
		print("[GameManager] DEBUG: Only server can start role assignment")
		return
	
	print("[GameManager] 🔧 DEBUG: Manually triggering role assignment...")
	start_role_assignment()

func debug_test_signal_handler() -> void:
	"""Test the signal handler directly - for testing only"""
	print("[GameManager] 🔧 DEBUG: Testing signal handler directly...")
	_on_all_peers_ready()

func debug_test_rpc_calls() -> void:
	"""Test RPC calls directly - for testing only"""
	if not multiplayer.is_server():
		print("[GameManager] DEBUG: Only server can send RPCs")
		return
	
	print("[GameManager] 🔧 DEBUG: Testing RPC calls...")
	rpc_update_seeker_info.rpc("TestSeeker", "TestCharacter")
	update_countdown_ui.rpc(3)
	show_announcement_to_all.rpc("Test announcement!")
	update_hiders_count_rpc.rpc(2)
	broadcast_kill_feed_message_rpc.rpc("TestPlayer BANG'd TestVictim")

func debug_test_complete_system() -> void:
	"""Test complete system integration - for testing only"""
	if not multiplayer.is_server():
		print("[GameManager] DEBUG: Only server can test complete system")
		return
	
	print("[GameManager] 🔧 DEBUG: Testing complete system integration...")
	
	# Test player state initialization
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player.has_method("set_initial_state"):
			player.set_initial_state.rpc(1, 3, true, true)  # Test seeker state
			print("[GameManager] 📡 DEBUG: Sent set_initial_state to ", player.name)
	
	# Test UI updates
	update_countdown_ui.rpc(10)
	show_announcement_to_all.rpc("DEBUG: Complete system test!")
	update_hiders_count_rpc.rpc(3)
	broadcast_kill_feed_message_rpc.rpc("DEBUG: TestSeeker BANG'd TestHider")
	
	print("[GameManager] ✅ DEBUG: Complete system test executed")

func debug_test_dev_world_init() -> void:
	"""Test dev_world initialization directly - for testing only"""
	if not multiplayer.is_server():
		print("[GameManager] DEBUG: Only server can test dev_world initialization")
		return
	
	print("[GameManager] 🔧 DEBUG: Testing dev_world initialization directly...")
	
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path == "res://scenes/dev/dev_world.tscn":
		print("[GameManager] 🌍 DEBUG: In dev_world scene, calling initialize_game_world()...")
		initialize_game_world()
	else:
		print("[GameManager] ⚠️ DEBUG: Not in dev_world scene. Current: ", current_scene.scene_file_path if current_scene else "null")

func _transition_to_dev_world() -> void:
	"""Transition from GamePrep to dev_world scene"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🌍 Transitioning to dev_world...")
	
	# Use NetworkManager to command scene transition via RPC
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("change_to_dev_world"):
		network_manager.change_to_dev_world()
	else:
		print("[GameManager] ❌ CRITICAL: NetworkManager not found - cannot transition scenes!")
		return

# ROBUST: Single definitive trigger - no re-entrant loops
func _on_all_peers_ready() -> void:
	"""Called when NetworkManager confirms all peers are ready for current scene"""
	print("[GameManager] 🚨 DEBUG: _on_all_peers_ready() called! Server: ", multiplayer.is_server())
	if not multiplayer.is_server():
		print("[GameManager] 🚨 DEBUG: Not server, exiting...")
		return
	
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
	
	print("[GameManager] 🎯 SCENE TRIGGER: All peers ready. Scene: ", current_scene.scene_file_path)
	
	# Handle different scenes appropriately
	if current_scene.scene_file_path == "res://scenes/GamePrep.tscn":
		print("[GameManager] 🎭 GAMEPREP EXECUTION: Starting role assignment...")
		start_role_assignment()
	elif current_scene.scene_file_path == "res://scenes/dev/dev_world.tscn":
		print("[GameManager] 🌍 DEV_WORLD EXECUTION: Initializing game world...")
		initialize_game_world()
	else:
		print("[GameManager] ⚠️ Unknown scene for peer ready signal: ", current_scene.scene_file_path)

# ROBUST: Self-contained game world initialization
func initialize_game_world() -> void:
	"""Initialize the game world - called when dev_world scene is ready"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🏠 SERVER: Initializing game world...")
	
	# Initialize game timers for this scene
	_initialize_timers()
	
	# Start the actual game flow
	start_game_flow()
	
	print("[GameManager] ✅ Game world initialization complete")

# DEFINITIVE SYNCHRONIZATION BARRIER: Bulletproof game start flow - all peers verified ready
func start_game_flow() -> void:
	if not multiplayer.is_server(): return
	
	print("[GameManager] ✅ All peers verified. World is ready. Starting game logic.")
	
	# THE DEFINITIVE GUARANTEE: All peers have loaded scenes and players are spawned
	var player_nodes = get_tree().get_nodes_in_group("player")
	if player_nodes.is_empty():
		# This error should now be impossible to trigger
		push_error("[GameManager] FATAL: Game started but no player nodes were found in the scene!")
		return
	
	print("[GameManager] ✅ DEFINITIVE: Found ", player_nodes.size(), " verified players")
	
	# Initialize game systems
	_initialize_server()
	
	# --- PHASE 3: NEW GAME LOGIC FLOW ---
	# Roles already assigned in GamePrep, start directly at HIDER_HEADSTART
	print("[GameManager] 🎮 Starting dev_world game logic with ", player_nodes.size(), " players")
	
	# Apply roles to all players with proper UI configuration
	apply_roles_to_players(player_nodes)
	
	# Start directly with HIDER_HEADSTART phase (skip PRE_GAME_FREEZE since we have game prep screen)
	_execute_phase_transition(GameState.HIDER_HEADSTART)
	
	print("[GameManager] ✅ DEFINITIVE BARRIER: Game flow started successfully")

# PHASE 3: New staged game flow functions
func apply_roles_to_players(player_nodes: Array) -> void:
	"""Apply the roles determined in GamePrep to the spawned players"""
	if not multiplayer.is_server():
		return
	
	# Get the seeker info from NetworkManager (stored during GamePrep)
	var network_manager = NetworkManager
	if not network_manager:
		print("[GameManager] ❌ NetworkManager not found for role application!")
		return
	
	var players_dict = network_manager.players
	total_players = player_nodes.size()
	max_ammo_capacity = total_players
	
	print("[GameManager] 🎭 Applying roles to ", total_players, " players...")
	
	# PHASE 1: Authoritative Player State Initialization
	# Use comprehensive set_initial_state RPC instead of basic assign_role
	for player_node in player_nodes:
		var player_id = player_node.get_multiplayer_authority()
		var player_data = players_dict.get(player_id, {})
		var is_seeker = player_data.get("is_seeker", false)
		
		if is_seeker:
			print("[GameManager] 🎯 Initializing SEEKER: ", player_node.player_name)
			# set_initial_state(role_int, ammo_count, can_move, can_attack)
			player_node.set_initial_state.rpc(1, max_ammo_capacity, false, false)  # Frozen during Phase 1
			player_node.add_to_group("seeker")
		else:
			print("[GameManager] 🫥 Initializing HIDER: ", player_node.player_name)
			# set_initial_state(role_int, ammo_count, can_move, can_attack)
			player_node.set_initial_state.rpc(0, 0, false, false)  # Frozen during Phase 1
			player_node.add_to_group("hider")
	
	print("[GameManager] ✅ PHASE 1: Complete player state initialization with UI configuration")
	
	# CRITICAL: Initialize hider count AFTER all role assignments are complete
	await get_tree().process_frame  # Wait one frame for all RPC calls to complete
	_initialize_hiders_count()

# REMOVED: start_hider_headstart_phase() - Replaced by unified phase system

# REMOVED: Legacy functions replaced by unified role-based permission system:
# - _enable_hider_movement_only() - Use _set_hiders_movement(true) + _set_seekers_movement(false)
# - _send_role_announcements() - Use _show_role_announcements() RPC (already implemented)

func _remove_seeker_blindness() -> void:
	"""Remove blindness from seeker when SEEKER_RELEASED phase starts"""
	var players_list: Array[Node] = get_tree().get_nodes_in_group("player")
	for player in players_list:
		var player_char = player as PlayerCharacter
		if not player_char:
			continue
		
		if player_char.role == PlayerCharacter.PlayerRole.SEEKER:
			player_char.set_seeker_blinded.rpc(false)

# --- LEGACY FUNCTIONS REMOVED ---
# assign_roles() - Now handled in GamePrep phase
# start_countdown_sequence() - Replaced by start_hider_headstart_phase()

# --- LEGACY STATE MACHINE REMOVED ---
# transition_to_state() - Replaced by _execute_next_phase() for simplified flow
# Timer callbacks - Replaced by master clock system

# REMOVED: _spawn_all_players() and _spawn_player_on_all_clients() 
# NetworkManager is now the SOLE authority for player spawning
# GameManager only manages game logic, not world creation

# Debug helper function for troubleshooting scene tree issues
func _debug_print_scene_tree(node: Node, depth: int) -> void:
	if depth > 3: return  # Limit depth to avoid spam
	var indent = "  ".repeat(depth)
	print("[GameManager] 🔍 ", indent, node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		_debug_print_scene_tree(child, depth + 1)

# REMOVED: Old _on_scene_changed function replaced with robust _on_tree_changed approach

# --- LEGACY TIMER INITIALIZATION REMOVED ---
# _initialize_game_timers() - Redundant with _initialize_singleton_timers()

# Master Clock System - Server-Authoritative Timing
func _on_master_clock_tick() -> void:
	"""Master clock tick - uses current_state to determine behavior"""
	if not multiplayer.is_server():
		return
	
	# CRITICAL SAFETY CHECK: Ensure GameManager singleton is properly initialized
	if not self:
		print("[GameManager] ❌ CRITICAL: GameManager instance is null during clock tick!")
		return
	
	# Check if current_state is properly initialized
	if current_state == null:
		print("[GameManager] ❌ CRITICAL: current_state is null! Initializing to LOBBY...")
		current_state = GameState.LOBBY
		return
	
	# Additional safety check for master_clock
	if not master_clock:
		print("[GameManager] ❌ CRITICAL: master_clock is null during tick!")
		return
	
	# Use current_state to determine which countdown logic to execute
	match current_state:
		GameState.LOBBY:
			# GamePrep countdown logic
			current_countdown_value -= 1
			print("[GameManager] ⏰ GamePrep countdown: ", current_countdown_value)
			rpc_update_prep_countdown.rpc(current_countdown_value)
			
			if current_countdown_value <= 0:
				master_clock.stop()
				print("[GameManager] ✅ GamePrep countdown finished - transitioning to dev_world")
				_transition_to_dev_world()
		
		_:
			# Regular gameplay countdown mode
			current_countdown_value -= 1
			print("[GameManager] 🕐 Gameplay Clock Tick: ", current_countdown_value)
			
			# Broadcast countdown to all clients
			update_countdown_ui.rpc(current_countdown_value)
			
			# Check if countdown reached zero
			if current_countdown_value <= 0:
				master_clock.stop()
				print("[GameManager] ⏰ Countdown finished - executing next phase: ", GameState.keys()[next_state_after_countdown])
				_execute_next_phase(next_state_after_countdown)

func start_master_clock_countdown(duration: int, next_state: GameState) -> void:
	"""Start the master clock with specified duration and next state"""
	if not multiplayer.is_server():
		return
	
	current_countdown_value = duration
	next_state_after_countdown = next_state
	print("[GameManager] 🕐 Starting Master Clock: ", duration, "s -> ", GameState.keys()[next_state])
	
	# Broadcast initial countdown
	update_countdown_ui.rpc(current_countdown_value)
	
	# Start the master clock
	master_clock.start()

func _execute_next_phase(next_state: GameState) -> void:
	"""Execute the next phase using the unified transition system"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🔄 Executing phase: ", GameState.keys()[next_state])
	_execute_phase_transition(next_state)

# Centralized UI Broadcasting RPCs - Server Authority
# (Functions moved to Phase 3 section with enhanced logging)

@rpc("authority", "call_local", "reliable")
func show_role_rpc(title: String, subtitle: String) -> void:
	"""Show role reveal to specific player (called with rpc_id)"""
	if game_ui_instance and game_ui_instance.has_method("update_status"):
		var role_text = title + "\n" + subtitle
		game_ui_instance.update_status(role_text, true)

func _reveal_roles_to_players() -> void:
	"""Send role-specific messages to each player"""
	if not multiplayer.is_server():
		return
	
	var players_list: Array[Node] = get_tree().get_nodes_in_group("player")
	for player in players_list:
		var player_char = player as PlayerCharacter
		if not player_char:
			continue
		
		var player_id = player_char.get_multiplayer_authority()
		if player_char.role == PlayerCharacter.PlayerRole.SEEKER:
			show_role_rpc.rpc_id(player_id, "You are the SEEKER!", "Hunt down all Hiders!")
		elif player_char.role == PlayerCharacter.PlayerRole.HIDER:
			show_role_rpc.rpc_id(player_id, "You are a HIDER!", "Stay hidden and survive!")

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
		# Seeker Eliminates Hider: "Bang" projectile collision
		message = attacker.player_name + " BANG'd " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER and eliminated_player.role == PlayerCharacter.PlayerRole.SEEKER:
		# Hider Eliminates Seeker: "Sak" melee attack
		message = attacker.player_name + " SAK'd " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER and eliminated_player.role == PlayerCharacter.PlayerRole.HIDER:
		# Hider Eliminates Hider (Friendly Fire): "Sak" melee attack
		message = attacker.player_name + "'s SAK found the wrong target: " + eliminated_player.player_name + "!"
	else:
		# Fallback for any other cases
		message = attacker.player_name + " eliminated " + eliminated_player.player_name
	
	print("[GameManager] Kill feed: ", message)
	
	# Show kill feed globally via unified RPC system
	broadcast_kill_feed_message_rpc.rpc(message)

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

	# Hider count initialization moved to apply_roles_to_players() for better timing
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
	
	# Stop singleton-level timers (these persist but should be stopped)
	if master_clock and is_instance_valid(master_clock):
		master_clock.stop()
	if main_timer and is_instance_valid(main_timer):
		main_timer.stop()
	if ammo_cooldown_timer and is_instance_valid(ammo_cooldown_timer):
		ammo_cooldown_timer.stop()
	
	# Clean up scene-specific timers
	_cleanup_scene_timers()
	
	# Reset player ready states
	for player_id in players:
		players[player_id]["ready"] = false
	
	# Emit signal to update UI
	game_state_changed.emit(game_state)
	
	print("[GameManager] ✅ Successfully reset to lobby - all timers stopped/cleaned")

var _last_countdown_value: int = -1

func _process(delta: float) -> void:
	# Do not run process logic if we are not in a networked game yet
	if not multiplayer.has_multiplayer_peer():
		return
		
	# Handle countdown display (now handled by master clock system)
	# Countdown updates are broadcast via update_countdown_ui.rpc() from master clock
	
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
	
	# Role assignment now handled in GamePrep phase
	
	# Initialize the game mechanics
	initialize_game()
	
	# Start directly with Hider Head Start (10 seconds)
	_execute_phase_transition(GameState.HIDER_HEADSTART)

# === REFACTORED PHASE TRANSITION SYSTEM ===

# Phase configuration data structure
var phase_configs = {
	GameState.PRE_GAME_FREEZE: {
		"name": "Pre-Game Freeze",
		"duration": 5,
		"next_phase": GameState.HIDER_HEADSTART,
		"permissions": {
			"hider_movement": false,
			"hider_attack": false,
			"seeker_movement": false,
			"seeker_attack": false
		},
		"effects": ["show_role_announcements"],
		"announcements": []
	},
	GameState.HIDER_HEADSTART: {
		"name": "Hider Head Start",
		"duration": 10,
		"next_phase": GameState.SEEKER_RELEASED,
		"permissions": {
			"hider_movement": true,
			"hider_attack": false,
			"seeker_movement": false,
			"seeker_attack": false
		},
		"effects": ["activate_seeker_blindness"],
		"announcements": []
	},
	GameState.SEEKER_RELEASED: {
		"name": "Seeker Released",
		"duration": 5,
		"next_phase": GameState.IN_PROGRESS,
		"permissions": {
			"hider_movement": true,
			"hider_attack": false,
			"seeker_movement": true,
			"seeker_attack": true
		},
		"effects": ["deactivate_seeker_blindness"],
		"announcements": ["The Seeker is on the move!"]
	},
	GameState.IN_PROGRESS: {
		"name": "Full Gameplay",
		"duration": -1,  # No countdown, game continues until win condition
		"next_phase": null,
		"permissions": {
			"hider_movement": true,
			"hider_attack": true,
			"seeker_movement": true,
			"seeker_attack": true
		},
		"effects": [],
		"announcements": ["Full gameplay active!"]
	}
}

# Unified phase transition function
func _execute_phase_transition(phase: GameState):
	"""Execute a phase transition using the configuration system"""
	if not phase in phase_configs:
		push_error("[GameManager] Unknown phase: " + str(phase))
		return
	
	var config = phase_configs[phase]
	print("[GameManager] 🔄 Starting Phase: ", config.name, " (", GameState.keys()[phase], ")")
	
	# Update game state
	change_game_state(phase)
	
	# Apply player permissions
	_apply_phase_permissions(config.permissions)
	
	# Execute special effects
	_execute_phase_effects(config.effects)
	
	# Show announcements
	_show_phase_announcements(config.announcements)
	
	# Start countdown if needed
	if config.duration > 0 and config.next_phase != null:
		start_master_clock_countdown(config.duration, config.next_phase)
	
	print("[GameManager] ✅ Phase ", config.name, " initialized successfully")

# Apply player permissions based on phase configuration
func _apply_phase_permissions(permissions: Dictionary):
	"""Apply movement and attack permissions for the current phase"""
	print("[GameManager] 🎮 Applying phase permissions: ", permissions)
	
	# Apply hider permissions
	_set_hiders_movement(permissions.hider_movement)
	_set_hiders_sak(permissions.hider_attack)  # FIXED: Use granular SAK permission
	
	# Apply seeker permissions
	_set_seekers_movement(permissions.seeker_movement)
	_set_seekers_bang(permissions.seeker_attack)  # FIXED: Use granular BANG permission

# Execute special effects for the phase
func _execute_phase_effects(effects: Array):
	"""Execute special effects like blindness, UI changes, etc."""
	for effect in effects:
		match effect:
			"show_role_announcements":
				_show_role_announcements.rpc()
			"activate_seeker_blindness":
				_activate_seeker_blindness.rpc()
			"deactivate_seeker_blindness":
				_deactivate_seeker_blindness.rpc()
			_:
				print("[GameManager] ⚠️ Unknown effect: ", effect)

# Show announcements for the phase
func _show_phase_announcements(announcements: Array):
	"""Show announcements to players"""
	for announcement in announcements:
		_show_announcement.rpc(announcement)

# REMOVED: Legacy phase functions - replaced with direct _execute_phase_transition() calls
# All phase transitions now use the unified configuration-driven system

# --- LEGACY PHASE TIMER CALLBACK REMOVED ---
# _on_phase_timer_timeout() - Replaced by master clock system

# REMOVED: Legacy player control functions - replaced by unified role-based permission system
# The following functions were redundant with the new phase configuration system:
# - _freeze_all_players() - Use _apply_phase_permissions() with all false permissions
# - _enable_seeker_full_control() - Use role-specific _set_hiders_*() and _set_seekers_*() functions  
# - _enable_full_gameplay() - Use _apply_phase_permissions() with all true permissions
# All player control now goes through the configuration-driven phase system

func _start_ammo_regeneration():
	"""Start the ammo regeneration timer"""
	if ammo_regen_timer and not ammo_regen_timer.is_stopped():
		ammo_regen_timer.stop()
	ammo_regen_timer.start()
	print("[GameManager] 🔄 Ammo regeneration started - 1 stone per 0.5 seconds")

# Ammo regeneration callback
func _on_ammo_regen_timer_timeout():
	if not multiplayer.is_server():
		return
	
	# Find the seeker and regenerate their ammo
	for player in get_tree().get_nodes_in_group("player"):
		if player.has_method("get_role") and player.get_role() == 1:  # SEEKER
			if player.has_method("regenerate_ammo"):
				player.regenerate_ammo.rpc(player.max_ammo)
				print("[GameManager] 🔄 Regenerating ammo for seeker: ", player.player_name)
			break

# Player control helper functions
# REMOVED: _set_all_players_movement() and _set_all_players_attack() - redundant with role-specific functions

func _set_hiders_movement(enabled: bool):
	_set_players_movement_by_role.rpc("hider", enabled)

func _set_seekers_movement(enabled: bool):
	_set_players_movement_by_role.rpc("seeker", enabled)

# REFACTORED: Granular ability control functions
func _set_hiders_sak(enabled: bool):
	print("[GameManager] 🗡️ SERVER: Setting hider SAK permission: ", enabled)
	_set_players_abilities_by_role.rpc("hider", false, enabled)

func _set_seekers_bang(enabled: bool):
	print("[GameManager] 🎯 SERVER: Setting seeker BANG permission: ", enabled)
	_set_players_abilities_by_role.rpc("seeker", enabled, false)

# DEPRECATED: Legacy compatibility wrappers
func _set_hiders_attack(enabled: bool):
	print("[GameManager] ⚠️ DEPRECATED: _set_hiders_attack() - use _set_hiders_sak()")
	_set_hiders_sak(enabled)

func _set_seekers_attack(enabled: bool):
	print("[GameManager] ⚠️ DEPRECATED: _set_seekers_attack() - use _set_seekers_bang()")
	_set_seekers_bang(enabled)

func end_game(winning_team: String) -> void:
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🏁 GAME OVER: ", winning_team, " wins!")
	
	# Change state and notify all clients
	change_game_state(GameState.GAME_OVER)
	game_ended.emit(winning_team)
	
	# Disable all players immediately
	_handle_game_over_state()
	
	# Show game over to all clients
	_show_game_over_announcement.rpc(winning_team)
	
	# Start game over timer to return to lobby
	_start_game_over_timer()

# Player elimination and win condition system
func _on_player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter) -> void:
	"""Handle player elimination and check win conditions"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 💀 Player eliminated: ", eliminated_player.player_name, " by ", attacker.player_name)
	
	# Show kill feed notification to all clients
	var attacker_name = attacker.player_name if attacker else "Unknown"
	var victim_name = eliminated_player.player_name
	var method = "SAK" if attacker and attacker.role == PlayerCharacter.PlayerRole.HIDER else "BANG"
	var kill_message = attacker_name + " eliminated " + victim_name + " with " + method
	_show_kill_feed.rpc(kill_message)
	
	# Update hiders count if a hider was eliminated
	if eliminated_player.role == PlayerCharacter.PlayerRole.HIDER:
		_update_hiders_count()
	
	# Check win conditions after elimination (deferred to ensure state is updated)
	call_deferred("check_win_conditions")

func check_win_conditions() -> void:
	"""Check if game should end based on current player states"""
	if not multiplayer.is_server():
		return
	
	if current_state != GameState.IN_PROGRESS:
		return  # Only check during active gameplay
	
	var alive_hiders := 0
	var alive_seekers := 0
	
	# Count alive players by role
	for player in get_tree().get_nodes_in_group("player"):
		if player is PlayerCharacter and player.current_state == PlayerCharacter.PlayerState.ALIVE:
			if player.role == PlayerCharacter.PlayerRole.HIDER:
				alive_hiders += 1
			elif player.role == PlayerCharacter.PlayerRole.SEEKER:
				alive_seekers += 1
	
	print("[GameManager] 🏁 Win check - Alive Hiders: ", alive_hiders, ", Alive Seekers: ", alive_seekers)
	
	# Determine win conditions
	if alive_hiders == 0:
		end_game("Seekers")
	elif alive_seekers == 0:
		end_game("Hiders")
	# Game continues if both sides have alive players

func _update_hiders_count() -> void:
	"""Update and broadcast the current hiders count"""
	# Use call_deferred to ensure player state is updated first
	call_deferred("_calculate_and_broadcast_hiders_count")

func _calculate_and_broadcast_hiders_count() -> void:
	"""Calculate and broadcast hiders count after state updates"""
	var alive_hiders := 0
	for player in get_tree().get_nodes_in_group("player"):
		if player is PlayerCharacter and player.current_state == PlayerCharacter.PlayerState.ALIVE and player.role == PlayerCharacter.PlayerRole.HIDER:
			alive_hiders += 1
	
	print("[GameManager] 📊 Updated hiders count: ", alive_hiders)
	_update_hiders_count_ui.rpc(alive_hiders)

@rpc("authority", "call_local", "reliable")
func _show_game_over_announcement(winning_team: String) -> void:
	"""Show game over announcement to all players"""
	print("[GameManager] 🎬 _show_game_over_announcement called on peer ", multiplayer.get_unique_id(), " for team: ", winning_team)
	
	var message := ""
	if winning_team == "Seekers":
		message = "🎯 SEEKERS WIN! All hiders eliminated!"
	elif winning_team == "Hiders":
		message = "🪫 HIDERS WIN! All seekers eliminated!"
	else:
		message = "🏁 GAME OVER: " + winning_team + " wins!"
	
	print("[GameManager] 📢 ", message)
	
	# Ensure game state is set to GAME_OVER on all clients
	if current_state != GameState.GAME_OVER:
		change_game_state(GameState.GAME_OVER)
	
	# Disable all players on this client
	_disable_all_players_local()
	
	# Show GameOver scene with error handling
	await get_tree().process_frame  # Wait one frame to ensure state is updated
	_show_game_over_scene(winning_team, message)

func _show_game_over_scene(winning_team: String, message: String) -> void:
	"""Load and show the GameOver scene"""
	print("[GameManager] 🎬 Loading GameOver scene for: ", winning_team, " on peer: ", multiplayer.get_unique_id())
	
	# Safety check: ensure we have a valid scene tree
	if not get_tree() or not get_tree().current_scene:
		print("[GameManager] ⚠️ No valid scene tree, cannot show GameOver UI")
		return
	
	# PRIORITY: Try GameUI first (more reliable)
	if game_ui_instance and game_ui_instance.has_method("show_game_over"):
		# Ensure GameUI knows the local player's role
		var local_player = _get_local_player()
		if local_player and game_ui_instance.has_method("set_local_player_role"):
			game_ui_instance.set_local_player_role(local_player.role)
			
		game_ui_instance.show_game_over(winning_team, message)
		print("[GameManager] ✅ PRIMARY: GameOver shown in GameUI")
		return
	
	# FALLBACK: Try to load the separate GameOver scene
	var game_over_scene_path = "res://scenes/GameOverUI.tscn"
	if ResourceLoader.exists(game_over_scene_path):
		var game_over_scene = load(game_over_scene_path)
		if game_over_scene:
			var game_over_instance = game_over_scene.instantiate()
			if not game_over_instance:
				print("[GameManager] ❌ Failed to instantiate GameOver scene")
				return
				
			game_over_instance.add_to_group("game_over_ui")
			
			# Add to scene tree and make visible
			var current_scene = get_tree().current_scene
			if current_scene and is_instance_valid(current_scene):
				current_scene.add_child(game_over_instance)
				game_over_instance.visible = true
				print("[GameManager] ✅ GameOver UI added to scene tree")
			else:
				print("[GameManager] ❌ Failed to add GameOver UI - invalid current scene")
				return
			
			# Move to front - handle different node types
			if game_over_instance is CanvasLayer:
				# CanvasLayer uses 'layer' property, not 'z_index'
				game_over_instance.layer = 100
				print("[GameManager] Set CanvasLayer layer to 100")
			elif game_over_instance is Control:
				# Control nodes use 'z_index'
				game_over_instance.z_index = 100
				print("[GameManager] Set Control z_index to 100")
			else:
				print("[GameManager] Unknown node type for z-ordering: ", game_over_instance.get_class())
			
			# Configure the game over UI with multiple fallback methods
			var configured = false
			if game_over_instance.has_method("show_game_over"):
				game_over_instance.show_game_over(winning_team, message)
				configured = true
			elif game_over_instance.has_method("set_winner"):
				game_over_instance.set_winner(winning_team)
				configured = true
			elif game_over_instance.has_method("display_winner"):
				game_over_instance.display_winner(winning_team)
				configured = true
			elif game_over_instance.has_method("setup"):
				game_over_instance.setup(winning_team, message)
				configured = true
			
			if not configured:
				print("[GameManager] ⚠️ GameOver UI has no known configuration method")
			
			print("[GameManager] ✅ GameOver scene loaded and displayed")
			return
	
	print("[GameManager] ❌ Failed to load GameOver scene from: ", game_over_scene_path)
	
	# Fallback: Show in GameUI if available
	if game_ui_instance and game_ui_instance.has_method("show_game_over"):
		# Ensure GameUI knows the local player's role
		var local_player = _get_local_player()
		if local_player and game_ui_instance.has_method("set_local_player_role"):
			game_ui_instance.set_local_player_role(local_player.role)
			
		game_ui_instance.show_game_over(winning_team, message)
		print("[GameManager] ✅ Fallback: GameOver shown in GameUI")
	elif game_ui_instance and game_ui_instance.has_method("show_dramatic_announcement"):
		game_ui_instance.show_dramatic_announcement(message)
		print("[GameManager] ✅ Fallback: GameOver shown as dramatic announcement")
	else:
		print("[GameManager] ❌ No fallback UI available for GameOver")
	
	# Auto-return to lobby after 10 seconds if no user input
	print("[GameManager] ⏰ Auto-return to lobby in 10 seconds...")
	get_tree().create_timer(10.0).timeout.connect(_auto_return_to_lobby)

func _auto_return_to_lobby() -> void:
	"""Auto-return to lobby after game over timeout"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] ⏰ Auto-returning to lobby...")
	# Use SceneChanger to return to lobby
	if SceneChanger:
		SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/lobby_wait_room_menu.tscn")
	else:
		# Fallback: direct scene change
		get_tree().change_scene_to_file("res://scenes/UI/Multiplayer/lobby_wait_room_menu.tscn")

@rpc("authority", "call_local", "reliable")
func _update_hiders_count_ui(count: int) -> void:
	"""Update hiders count in UI"""
	if game_ui_instance and game_ui_instance.has_method("update_hiders_count"):
		game_ui_instance.update_hiders_count(count)

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
			# LEGACY: main_timer.start(5.0) - REMOVED to prevent conflicts with master_clock
		GameState.GAME_START_COUNTDOWN:
			# Legacy state - redirect to SEEKER_RELEASED behavior
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("The Seeker is on the move!", true)
				game_ui_instance.update_countdown("5", true)
			# LEGACY: main_timer.start(10.0) - REMOVED to prevent conflicts with master_clock
		GameState.IN_PROGRESS:
			if game_ui_instance and game_ui_instance.has_method("update_status"):
				game_ui_instance.update_status("The Hunt is On!", true)
				game_ui_instance.update_countdown("GO!", false)
			# SAK delay timer is still valid for gameplay mechanics
			sak_delay_timer.start(3.0)
		GameState.FINISHED:
			ammo_cooldown_timer.stop()

# --- LEGACY ROLE ASSIGNMENT REMOVED ---
# _assign_roles() - Now handled in GamePrep phase with apply_roles_to_players()

#region State Handlers
func _handle_starting_state(delta: float) -> void:
	# This would handle the countdown logic
	# When countdown reaches 0, start the game
	pass

func _handle_in_progress_state(delta: float) -> void:
	# Main game loop logic
	pass

func _handle_game_over_state() -> void:
	"""Handle game over state - stop all timers and disable interactions"""
	# Stop all game timers
	if master_clock and not master_clock.is_stopped():
		master_clock.stop()
	if ammo_regen_timer and not ammo_regen_timer.is_stopped():
		ammo_regen_timer.stop()
	if sak_delay_timer and not sak_delay_timer.is_stopped():
		sak_delay_timer.stop()
	
	# Disable all player abilities (only once)
	if multiplayer.is_server() and not players_disabled:
		players_disabled = true
		_disable_all_players.rpc()

func _start_game_over_timer() -> void:
	"""Start timer to return to lobby after game over"""
	if not multiplayer.is_server():
		return
	
	if not game_over_timer:
		game_over_timer = Timer.new()
		add_child(game_over_timer)
		game_over_timer.timeout.connect(_on_game_over_timer_timeout)
	
	game_over_timer.wait_time = 10.0  # 10 seconds to view results
	game_over_timer.one_shot = true
	game_over_timer.start()
	
	print("[GameManager] ⏰ Game over timer started - returning to lobby in 10 seconds")

func _on_game_over_timer_timeout() -> void:
	"""Reset game and return to lobby"""
	if not multiplayer.is_server():
		return
	
	print("[GameManager] 🔄 Resetting game and returning to lobby")
	
	# Reset all game state
	_reset_game_state()
	
	# Change to lobby state
	change_game_state(GameState.LOBBY)
	
	# Notify all clients to reset
	_reset_all_players.rpc()

func _reset_game_state() -> void:
	"""Reset all game variables and timers"""
	# Stop and clear all timers
	if master_clock:
		master_clock.stop()
	if ammo_regen_timer:
		ammo_regen_timer.stop()
	if sak_delay_timer:
		sak_delay_timer.stop()
	if game_over_timer:
		game_over_timer.stop()
	
	# Reset game variables
	total_players = 0
	max_ammo_capacity = 0
	sak_delay_active = false
	players_disabled = false
	
	# Clear player data
	players.clear()
	
	print("[GameManager] ✅ Game state reset complete")

@rpc("authority", "call_local", "reliable")
func _disable_all_players() -> void:
	"""Disable all player abilities during game over"""
	_disable_all_players_local()

func _disable_all_players_local() -> void:
	"""Disable all players on this client"""
	for player in get_tree().get_nodes_in_group("player"):
		if player is PlayerCharacter:
			player.can_move = false
			player.can_bang = false
			player.can_sak = false
	print("[GameManager] 🚫 All players disabled for game over")

@rpc("authority", "call_local", "reliable")
func _reset_all_players() -> void:
	"""Reset all players to lobby state"""
	# Reset all player nodes
	for player in get_tree().get_nodes_in_group("player"):
		if player is PlayerCharacter:
			player.reset_to_lobby_state()
	
	# Hide game over UI
	var game_over_ui = get_tree().get_first_node_in_group("game_over_ui")
	if game_over_ui:
		game_over_ui.queue_free()
	
	print("[GameManager] 🔄 All players reset to lobby state")

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

# GamePrep UI Update RPCs
@rpc("authority", "call_local", "reliable")
func rpc_update_seeker_info(seeker_name: String, character: String) -> void:
	"""RPC to update seeker information on all clients"""
	print("[GameManager] 📡 RPC: Updating seeker info - ", seeker_name)
	seeker_revealed.emit(seeker_name, character)

@rpc("authority", "call_local", "reliable")
func rpc_update_prep_countdown(countdown_value: int) -> void:
	"""RPC to update GamePrep countdown on all clients"""
	print("[GameManager] 📡 RPC: Updating prep countdown - ", countdown_value)
	prep_countdown_updated.emit(countdown_value)

# Phase 3: Role-Aware UI and Gameplay Mechanics RPCs
@rpc("authority", "call_local", "reliable")
func update_hiders_count_rpc(count: int) -> void:
	"""Broadcast hiders remaining count to all clients"""
	print("[GameManager] 📡 RPC: Broadcasting hiders count - ", count)
	if game_ui_instance and game_ui_instance.has_method("update_hiders_left"):
		game_ui_instance.update_hiders_left(count)

@rpc("authority", "call_local", "reliable")
func broadcast_kill_feed_message_rpc(message: String) -> void:
	"""Broadcast kill feed message to all clients"""
	print("[GameManager] 📡 RPC: Broadcasting kill feed - ", message)
	if game_ui_instance and game_ui_instance.has_method("show_kill_feed"):
		game_ui_instance.show_kill_feed(message)

@rpc("authority", "call_local", "reliable")
func update_countdown_ui(time: int) -> void:
	"""Broadcast countdown update to all clients"""
	print("[GameManager] 📡 RPC: Broadcasting countdown update - ", time, " (Peer: ", multiplayer.get_unique_id(), ")")
	if game_ui_instance and game_ui_instance.has_method("update_countdown"):
		var time_text = str(time) if time > 0 else "GO!"
		game_ui_instance.update_countdown(time_text, time > 0)

@rpc("authority", "call_local", "reliable") 
func show_announcement_to_all(text: String) -> void:
	"""Broadcast global announcement to all clients"""
	if game_ui_instance and game_ui_instance.has_method("update_status"):
		game_ui_instance.update_status(text, true)

func _initialize_hiders_count() -> void:
	"""Initialize and broadcast the hiders count at game start"""
	var hiders = get_tree().get_nodes_in_group("hider")
	var hiders_count = hiders.size()
	print("[GameManager] 📊 Initializing hiders count: ", hiders_count)
	update_hiders_count_rpc.rpc(hiders_count)

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
	
	if player.ammo <= 0 or not player.can_bang:
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
	
	if not player.can_sak:
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

@rpc("any_peer", "call_local", "reliable")
func _set_players_movement_by_role(role_filter: String, enabled: bool):
	"""Set movement for players by role"""
	print("[GameManager] 📡 RPC RECEIVED: _set_players_movement_by_role(", role_filter, ", ", enabled, ") on peer ", multiplayer.get_unique_id())
	
	var local_player = _get_local_player()
	if not local_player:
		print("[GameManager] ❌ No local player found for movement update")
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
		print("[GameManager] ✅ Set movement to ", enabled, " for ", role_filter, " (", local_player.player_name, ")")
	else:
		print("[GameManager] ⚠️ Movement update skipped - role filter '", role_filter, "' doesn't match local player role: ", PlayerCharacter.PlayerRole.keys()[local_player.role])

# REFACTORED: Granular ability permission system
@rpc("any_peer", "call_local", "reliable")
func _set_players_abilities_by_role(role_filter: String, can_bang: bool, can_sak: bool):
	"""Set granular abilities for players by role"""
	print("[GameManager] 📡 RPC RECEIVED: _set_players_abilities_by_role(", role_filter, ", BANG=", can_bang, ", SAK=", can_sak, ") on peer ", multiplayer.get_unique_id())
	print("[GameManager] 🔍 DEBUG: Connected peers: ", multiplayer.get_peers())
	print("[GameManager] 🔍 DEBUG: Is server: ", multiplayer.is_server())

	var players_in_scene = get_tree().get_nodes_in_group("player")
	print("[GameManager] 🔍 DEBUG: Evaluating ability permissions for ", players_in_scene.size(), " players")

	for player in players_in_scene:
		if not player is PlayerCharacter:
			continue

		var should_apply := false
		if role_filter == "all":
			should_apply = true
		elif role_filter == "seeker" and player.role == PlayerCharacter.PlayerRole.SEEKER:
			should_apply = true
		elif role_filter == "hider" and player.role == PlayerCharacter.PlayerRole.HIDER:
			should_apply = true

		if not should_apply:
			continue

		# Apply role-specific abilities
		if player.role == PlayerCharacter.PlayerRole.SEEKER:
			player.can_bang = can_bang
			player.can_sak = false  # Seekers never SAK
			print("[GameManager] ✅ Applied BANG=", can_bang, " to Seeker (", player.player_name, ") on peer ", multiplayer.get_unique_id())
		elif player.role == PlayerCharacter.PlayerRole.HIDER:
			player.can_bang = false  # Hiders never BANG
			player.can_sak = can_sak
			print("[GameManager] ✅ Applied SAK=", can_sak, " to Hider (", player.player_name, ") on peer ", multiplayer.get_unique_id())

# DEPRECATED: Legacy compatibility wrapper
@rpc("any_peer", "call_local", "reliable")
func _set_players_attack_by_role(role_filter: String, enabled: bool):
	"""DEPRECATED: Use _set_players_abilities_by_role() instead"""
	print("[GameManager] ⚠️ DEPRECATED: _set_players_attack_by_role() - use _set_players_abilities_by_role()")
	# Convert legacy call to new granular system
	if role_filter == "seeker":
		_set_players_abilities_by_role(role_filter, enabled, false)
	elif role_filter == "hider":
		_set_players_abilities_by_role(role_filter, false, enabled)
	else:
		_set_players_abilities_by_role(role_filter, enabled, enabled)

@rpc("any_peer", "call_local", "reliable")
func _activate_seeker_blindness():
	"""Activate blindness UI for Seeker clients"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		print("[GameManager] Activating Seeker blindness")
		# Add blindness overlay to Seeker's UI
		_create_blindness_overlay()

@rpc("any_peer", "call_local", "reliable")
func _deactivate_seeker_blindness():
	"""Deactivate blindness UI for Seeker clients"""
	var local_player = _get_local_player()
	if local_player and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		print("[GameManager] Deactivating Seeker blindness")
		# Remove blindness overlay
		_remove_blindness_overlay()

@rpc("any_peer", "call_local", "reliable")
func _show_countdown(seconds: int):
	"""Show countdown timer to all players"""
	print("[GameManager] Showing countdown: ", seconds, " seconds")
	# This would integrate with the GameUI to show countdown

@rpc("any_peer", "call_local", "reliable")
func _show_announcement(message: String):
	"""Show dramatic announcement to all players"""
	print("[GameManager] 🎯 DRAMATIC ANNOUNCEMENT: ", message)
	
	# Show announcement in GameUI if available
	if game_ui_instance and game_ui_instance.has_method("show_dramatic_announcement"):
		game_ui_instance.show_dramatic_announcement(message)
	elif game_ui_instance and game_ui_instance.has_method("update_status"):
		game_ui_instance.update_status(message, true)

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

@rpc("any_peer", "reliable")
func forward_spotted_alert(target_peer_id: int, show: bool) -> void:
	"""Server authoritative relay for spotted alert UI RPCs"""
	if not multiplayer.is_server():
		return

	var target_player := _get_player_by_authority(target_peer_id)
	if not target_player:
		print("[GameManager] ⚠️ forward_spotted_alert: No player found for authority ", target_peer_id)
		return

	var server_id := multiplayer.get_unique_id()
	if target_peer_id != server_id and not multiplayer.has_peer(target_peer_id):
		print("[GameManager] ⚠️ forward_spotted_alert: Peer ", target_peer_id, " no longer connected")
		return

	if show:
		if target_peer_id == server_id:
			target_player._trigger_spotted_alert()
		else:
			target_player._trigger_spotted_alert.rpc_id(target_peer_id)
		print("[GameManager] 📢 Forwarded SHOW spotted alert to peer ", target_peer_id)
	else:
		if target_peer_id == server_id:
			target_player._hide_spotted_alert()
		else:
			target_player._hide_spotted_alert.rpc_id(target_peer_id)
		print("[GameManager] 📢 Forwarded HIDE spotted alert to peer ", target_peer_id)

# Helper functions for staged gameplay
func _get_local_player() -> PlayerCharacter:
	"""Get the local player instance"""
	var players_in_scene = get_tree().get_nodes_in_group("player")
	var my_peer_id = multiplayer.get_unique_id()
	print("[GameManager] 🔍 DEBUG: Found ", players_in_scene.size(), " players in 'player' group")
	print("[GameManager] 🔍 DEBUG: My peer ID: ", my_peer_id)
	
	for player in players_in_scene:
		var player_authority = player.get_multiplayer_authority()
		print("[GameManager] 🔍 DEBUG: Checking player ", player.player_name, " - Authority: ", player_authority, " vs My ID: ", my_peer_id)
		if player_authority == my_peer_id:
			print("[GameManager] ✅ Found local player: ", player.player_name)
			return player as PlayerCharacter
	print("[GameManager] ❌ No local player found with matching authority")
	return null

func _get_player_by_authority(authority_id: int) -> PlayerCharacter:
	"""Find player node that has the specified multiplayer authority"""
	for player in get_tree().get_nodes_in_group("player"):
		if player is PlayerCharacter and player.get_multiplayer_authority() == authority_id:
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

@rpc("any_peer", "call_local", "reliable")
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
	# LEGACY TIMER HANDLER - DISABLED TO PREVENT CONFLICTS
	# This function is kept for compatibility but should not interfere with master_clock
	print("[GameManager] ⚠️ LEGACY: main_timer timeout ignored - master_clock is authoritative")
	# All phase transitions now handled by master_clock system

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
			hider_player.can_sak = true
	print("[GameMaster] Hiders can now SAK!")
