# res://scripts/player.gd (Multiplayer + Working Mechanics Integration)

class_name PlayerCharacter
extends CharacterBody2D

# --- ENUM DEFINITIONS ---
enum PlayerRole { HIDER, SEEKER }
enum PlayerState { ALIVE, GHOST }

# --- CONSTANTS ---
const ROCK_PROJECTILE_SCENE = preload("res://scenes/RockProjectile.tscn")

# --- EXPORTED VARIABLES ---
@export var walk_speed: float = 200.0
@export var run_speed: float = 350.0
@export var is_main_player: bool = false
@export var role: PlayerRole = PlayerRole.HIDER
@export var player_name: String = "Player"
@export var ammo: int = 0
@export var character_index: int = 0 

# --- NODE REFERENCES ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var vision_cone: Area2D = $VisionCone
@onready var vision_light: PointLight2D = $VisionCone/PointLight2D
@onready var melee_range: Area2D = $MeleeRange
@onready var muzzle: Marker2D = $Muzzle
@onready var camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

# Role overlay UI
var role_overlay: Control = null
var role_label: Label = null
var role_timer: Timer = null

# --- STATE VARIABLES (Statically Typed) ---
var _sync_position: Vector2 = Vector2.ZERO
var _sync_animation: String = ""
var _sync_flip: bool = false
var _last_animation: String = ""
var _animation_transition_time: float = 0.0
var current_state: PlayerState = PlayerState.ALIVE
var hiders_in_cone: Array[PlayerCharacter] = []
var visible_targets: Array[PlayerCharacter] = []
var previously_visible_hiders: Array[PlayerCharacter] = []
var is_in_action: bool = false
var target_for_sak: PlayerCharacter = null
var is_dying: bool = false
var can_move: bool = false  # Controlled by GameManager
var can_attack: bool = false  # Controlled by GameManager
var can_sak: bool = false  # Controlled by GameManager - separate SAK control
var max_ammo: int = 0  # Maximum ammo capacity (set by GameManager)

# LOS (Line of Sight) system for Seeker
var los_range: float = 150.0  # Seeker's sight range
var los_angle: float = 60.0   # Seeker's sight cone angle (degrees)
var spotted_targets: Array[PlayerCharacter] = []  # Currently spotted Hiders

# Username display
var username_label: Label = null

# Collision layers:
# 1 - Default (players, obstacles)
# 2 - Vision (for line of sight checks)
# 3 - Ghosts (visible to all players)
# 4 - Obstacles

# --- CORE FUNCTIONS ---

func _ready():
	await get_tree().process_frame
	
	# Add to player group for collision detection
	add_to_group("player")
	
	# Connect to GameManager signals
	if GameManager:
		GameManager.game_state_changed.connect(_on_game_state_changed)
	
	# Configure multiplayer authority
	_configure_multiplayer_authority()
	
	# Create username label
	_create_username_label()
	
	# Setup MultiplayerSynchronizer with empty config (for spawning only)
	if sync:
		sync.set_multiplayer_authority(get_multiplayer_authority())
		print("[Player] MultiplayerSynchronizer set up for spawning: ", player_name)
	
	# Configure role-specific settings
	if role == PlayerRole.HIDER:
		vision_light.energy = 0.5

func _configure_multiplayer_authority():
	# Configure based on multiplayer authority
	if not is_multiplayer_authority():
		# Remote players: disable input but keep physics for movement sync
		set_process_unhandled_input(false)
		if camera:
			camera.enabled = false
		if vision_light:
			vision_light.visible = false
		if vision_cone:
			vision_cone.monitoring = false
		if melee_range:
			melee_range.monitoring = false
	else:
		# This is the local player - enable everything
		is_main_player = true
		can_move = true
		can_attack = true
		if camera:
			camera.enabled = true
			camera.make_current()

# Called by World script when spawning players
func setup_multiplayer_player(player_data: Dictionary, is_local: bool):
	player_name = player_data.get("name", "Player")
	is_main_player = is_local
	
	# Enable movement and attacks for all players
	can_move = true
	can_attack = true
	
	# Update username display
	update_username_display()
	
	# Configure based on whether this is the local player
	if is_local:
		if camera:
			camera.enabled = true
			camera.make_current()
		print("[Player] Set up LOCAL player: ", player_name)
	else:
		if camera:
			camera.enabled = false

# PHASE 1: Basic controls enablement for MPS testing
func enable_basic_controls() -> void:
	"""Enable immediate movement and attack capabilities for testing"""
	can_move = true
	can_attack = true
	print("[Player] ", player_name, " - Basic controls enabled for MPS testing")

func _create_username_label():
	# Create username label above the player
	username_label = Label.new()
	username_label.text = player_name if player_name != "" else "Player"
	username_label.position = Vector2(-25, -40)  # Position above the character
	username_label.add_theme_font_size_override("font_size", 14)
	username_label.add_theme_color_override("font_color", Color.WHITE)
	username_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	username_label.add_theme_constant_override("shadow_offset_x", 1)
	username_label.add_theme_constant_override("shadow_offset_y", 1)
	username_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(username_label)
	print("[Player] Created username label: ", username_label.text)

func update_username_display():
	if username_label:
		username_label.text = player_name if player_name != "" else "Player"
		print("[Player] Updated username display to: ", username_label.text)

func set_is_main_player(value: bool):
	is_main_player = value
	_configure_multiplayer_authority()



func get_character_name() -> String:
	return CharacterFactory.get_character_name(character_index)

# Create role overlay UI
func _create_role_overlay() -> void:
	if not is_main_player:
		return  # Only show overlay for the local player
	
	# Create overlay container
	role_overlay = Control.new()
	role_overlay.name = "RoleOverlay"
	role_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	role_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create background panel
	var background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)  # Semi-transparent black
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	role_overlay.add_child(background)
	
	# Create role label
	role_label = Label.new()
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# Style the label
	var font_size = 72
	role_label.add_theme_font_size_override("font_size", font_size)
	role_label.add_theme_color_override("font_color", Color.WHITE)
	role_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	role_label.add_theme_constant_override("shadow_offset_x", 3)
	role_label.add_theme_constant_override("shadow_offset_y", 3)
	
	role_overlay.add_child(role_label)
	
	# Create timer
	role_timer = Timer.new()
	role_timer.wait_time = 3.0
	role_timer.one_shot = true
	role_timer.timeout.connect(_hide_role_overlay)
	role_overlay.add_child(role_timer)
	
	# Add to camera so it follows the player
	if camera:
		camera.add_child(role_overlay)
	else:
		add_child(role_overlay)
	
	print("[Player] Role overlay created for ", player_name)

# Show role overlay with appropriate styling
func show_role_overlay() -> void:
	if not is_main_player or not role_label:
		return
	
	# Set role text and color based on role
	if role == PlayerRole.SEEKER:
		role_label.text = "YOU ARE THE SEEKER"
		role_label.add_theme_color_override("font_color", Color.RED)
		role_label.add_theme_color_override("font_outline_color", Color.DARK_RED)
		print("[Player] Showing SEEKER overlay for ", player_name)
	else:
		role_label.text = "YOU ARE A HIDER"
		role_label.add_theme_color_override("font_color", Color.CYAN)
		role_label.add_theme_color_override("font_outline_color", Color.BLUE)
		print("[Player] Showing HIDER overlay for ", player_name)
	
	# Add outline for better visibility
	role_label.add_theme_constant_override("outline_size", 2)
	
	# Show overlay and start timer
	if role_overlay:
		role_overlay.visible = true
		role_timer.start()
		print("[Player] Role overlay shown, timer started for 3 seconds")

# Hide role overlay
func _hide_role_overlay() -> void:
	if role_overlay:
		role_overlay.visible = false
		print("[Player] Role overlay hidden for ", player_name)

# Public function to trigger role display
func display_role_for_round() -> void:
	if not is_main_player:
		return
		
	# Create overlay if it doesn't exist
	if not role_overlay:
		_create_role_overlay()
	
	# Show the overlay
	show_role_overlay()

# Direct fire function (fallback when GameManager not available)
func _direct_fire_projectile() -> void:
	if role != PlayerRole.SEEKER or ammo <= 0 or is_in_action:
		return
	
	print("[Player] Direct fire - reducing ammo from ", ammo, " to ", ammo - 1)
	ammo -= 1
	execute_fire_projectile()

# Direct SAK function (fallback when GameManager not available)  
func _direct_sak_attack() -> void:
	if role != PlayerRole.HIDER or is_in_action:
		return
	
	# Find target in melee range
	var nearby_players: Array[Node2D] = melee_range.get_overlapping_bodies()
	var target: PlayerCharacter = null
	
	for body in nearby_players:
		var potential_target: PlayerCharacter = body as PlayerCharacter
		if potential_target and potential_target != self and potential_target.current_state == PlayerState.ALIVE:
			target = potential_target
			break
	
	if target:
		print("[Player] Direct SAK attack on ", target.player_name)
		execute_sak_attack(target)
	else:
		print("[Player] No valid SAK target found")

# Direct projectile creation (fallback)
func _create_projectile_direct() -> void:
	if not ROCK_PROJECTILE_SCENE:
		print("[Player] ERROR: ROCK_PROJECTILE_SCENE not loaded!")
		return
		
	var rock = ROCK_PROJECTILE_SCENE.instantiate()
	if "owner_player" in rock:
		rock.owner_player = self
	rock.global_position = muzzle.global_position
	rock.rotation = vision_cone.global_rotation
	
	# Ensure rock is visible on all layers
	if rock.has_node("Sprite2D"):
		var sprite = rock.get_node("Sprite2D")
		sprite.visible = true
		sprite.modulate = Color.WHITE
		print("[Player] Rock sprite visibility set to: ", sprite.visible)
	
	# Add to current scene instead of root for better organization
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(rock)
	else:
		get_tree().root.add_child(rock)
	
	print("[Player] Created projectile at ", muzzle.global_position, " with rotation ", rock.rotation)

# Direct elimination (fallback)
func _eliminate_target_direct(target: PlayerCharacter) -> void:
	if not is_instance_valid(target):
		return
	print("[Player] Directly eliminating ", target.player_name)
	target.eliminate(self)

func _physics_process(delta: float):
	if is_dying: return
	
	# SAFETY GUARD: If there is no multiplayer peer assigned, do nothing this frame
	# This prevents the "Unable to get unique ID" crash during spawn conflicts
	if not multiplayer.has_multiplayer_peer():
		return
	
	# Additional safety check for unique ID
	if multiplayer.get_unique_id() == 0:
		return
	
	# Only the multiplayer authority simulates input and movement
	if is_multiplayer_authority():
		handle_movement()
		if current_state == PlayerState.GHOST: return
		handle_visuals()
		update_all_players_in_cone()
		check_line_of_sight()
		
		# Sync position and animation state to other clients
		if Engine.get_physics_frames() % 2 == 0:  # Sync every 2nd frame
			var current_animation = animated_sprite.animation if animated_sprite else "idle"
			var is_flipped = animated_sprite.flip_h if animated_sprite else false
			_sync_player_state.rpc(global_position, velocity, current_animation, is_flipped)
	else:
		# Non-authority players smoothly interpolate to synced position
		if _sync_position != Vector2.ZERO:
			var distance = global_position.distance_to(_sync_position)
			var lerp_speed = 20.0  # Base interpolation speed
			
			# Adjust interpolation speed based on distance for smoother movement
			if distance > 100.0:
				lerp_speed = 30.0  # Faster catch-up for large distances
			elif distance < 10.0:
				lerp_speed = 10.0  # Slower for fine adjustments
			
			global_position = global_position.lerp(_sync_position, delta * lerp_speed)
		
		# Handle animations for remote players based on movement
		handle_remote_visuals()

# This is the single, authoritative function for updating player controls.
@rpc("any_peer", "call_local", "reliable")
func set_player_state(p_can_move: bool, p_can_attack: bool) -> void:
	self.can_move = p_can_move
	self.can_attack = p_can_attack

# This is the single, authoritative function for setting a player's role.
@rpc("any_peer", "call_local", "reliable")
func assign_role(new_role: PlayerRole, max_ammo: int = 0) -> void:
	self.role = new_role
	
	# Role-specific setup
	if self.role == PlayerRole.SEEKER:
		add_to_group("seeker")
		remove_from_group("hider")  # Ensure clean group membership
		self.ammo = 0  # Start with 0 ammo, must regenerate to full capacity before attacking
		self.max_ammo = max_ammo
		print("[Player] ", player_name, " assigned as SEEKER with max ammo capacity: ", max_ammo)
		print("[Player] ", player_name, " must regenerate to full ammo (", max_ammo, ") before attacking")
	else:
		add_to_group("hider")
		remove_from_group("seeker")  # Ensure clean group membership
		self.ammo = 0  # Hiders don't use ammo
		self.max_ammo = 0
		print("[Player] ", player_name, " assigned as HIDER")

# PHASE 1: Authoritative Player State Initialization
@rpc("any_peer", "call_local", "reliable")
func set_initial_state(role_int: int, ammo_count: int, p_can_move: bool, p_can_attack: bool) -> void:
	"""Complete player initialization from server - sets role, ammo, permissions, and UI"""
	print("[Player] 📡 RECEIVED: set_initial_state - role=", role_int, ", ammo=", ammo_count, ", move=", p_can_move, ", attack=", p_can_attack, " (Peer: ", multiplayer.get_unique_id(), ")")
	
	# Set role and group membership
	var new_role = role_int as PlayerRole
	self.role = new_role
	
	if new_role == PlayerRole.SEEKER:
		add_to_group("seeker")
		remove_from_group("hider")
		self.max_ammo = ammo_count
		self.ammo = ammo_count
		print("[Player] ✅ ", player_name, " initialized as SEEKER with ", ammo_count, " ammo")
	elif new_role == PlayerRole.HIDER:
		add_to_group("hider")
		remove_from_group("seeker")
		self.max_ammo = 0
		self.ammo = 0
		print("[Player] ✅ ", player_name, " initialized as HIDER")
	
	# Set player permissions
	self.can_move = p_can_move
	self.can_attack = p_can_attack
	self.can_sak = false  # Always start with SAK disabled, GameManager will enable it later
	
	# CRITICAL: Configure local UI if this is the local player
	if is_multiplayer_authority():
		_configure_local_ui_for_role(new_role, ammo_count)

func _configure_local_ui_for_role(role: PlayerRole, ammo_count: int) -> void:
	"""Configure the local GameUI for this player's role - only called on authority peer"""
	print("[Player] 🎨 Configuring local UI for role: ", PlayerRole.keys()[role])
	
	# Find the GameUI instance
	var game_ui = get_tree().current_scene.get_node_or_null("GameUI")
	if not game_ui:
		# Try alternative paths
		game_ui = get_tree().current_scene.find_child("GameUI", true, false)
	
	if game_ui and game_ui.has_method("configure_for_role"):
		game_ui.configure_for_role(role)
		print("[Player] ✅ UI configured for role: ", PlayerRole.keys()[role])
		
		# Update ammo display if seeker
		if role == PlayerRole.SEEKER and game_ui.has_method("update_ammo"):
			game_ui.update_ammo(ammo_count)
			print("[Player] ✅ UI ammo updated: ", ammo_count)
	else:
		print("[Player] ⚠️ GameUI not found or missing configure_for_role method")

@rpc("any_peer", "call_local", "reliable")
func set_ammo(new_ammo: int) -> void:
	"""RPC to set player ammo - called by server during gameplay"""
	self.ammo = new_ammo
	print("[Player] Ammo updated: ", ammo)
	
	# Update UI if this is the local player and they're a Seeker
	if is_main_player and role == PlayerRole.SEEKER:
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.has_method("update_ui"):
			game_manager.update_ui()

# New enhanced control system for game states
@rpc("any_peer", "call_local", "reliable")
func set_game_state_controls(p_can_move: bool, p_can_attack: bool, p_can_sak: bool) -> void:
	"""Enhanced control system with separate SAK control"""
	self.can_move = p_can_move
	self.can_attack = p_can_attack
	self.can_sak = p_can_sak
	print("[Player] Controls updated for ", player_name, " - Move: ", can_move, " Attack: ", can_attack, " SAK: ", can_sak)

# Ammo regeneration system
@rpc("any_peer", "call_local", "reliable")
func regenerate_ammo(max_capacity: int) -> void:
	"""Regenerate 1 ammo stone per second until max capacity"""
	if role != PlayerRole.SEEKER:
		return
	
	if ammo < max_capacity:
		ammo += 1
		print("[Player] Ammo regenerated: ", ammo, "/", max_capacity)
		
		# Update seeker attack capability based on ammo
		if ammo >= max_capacity:
			print("[Player] 🎯 SEEKER READY: Full ammo capacity reached - attacks enabled!")
		else:
			print("[Player] ⏳ SEEKER CHARGING: ", (max_capacity - ammo), " more stones needed")
	
	# Sync ammo to all clients
	set_ammo.rpc(ammo)

# Helper function for GameManager to get player role
func get_role() -> int:
	return int(role)

# This is the single, authoritative function for managing the Seeker's blindness.
@rpc("any_peer", "call_local", "reliable")
func set_seeker_blinded(is_blinded: bool) -> void:
	if not is_multiplayer_authority(): return
	# Find your full-screen black ColorRect in the GameUI and show/hide it.
	# Example: GameManager.game_ui_instance.seeker_blindness_overlay.visible = is_blinded

@rpc("any_peer", "unreliable")
func _sync_player_state(pos: Vector2, vel: Vector2, animation: String, flipped: bool):
	# Only apply updates to non-authority nodes
	if not is_multiplayer_authority():
		_sync_position = pos
		velocity = vel
		
		# Store animation state for smooth transitions
		_sync_animation = animation
		_sync_flip = flipped
		
		# Apply animation state with smooth transitions
		if animated_sprite and animation != "":
			if animated_sprite.sprite_frames.has_animation(animation):
				# Only change animation if it's different to avoid stuttering
				if animated_sprite.animation != animation:
					animated_sprite.play(animation)
					_last_animation = animation
					_animation_transition_time = 0.0
			animated_sprite.flip_h = flipped

# Legacy function for compatibility
@rpc("any_peer", "unreliable")
func _sync_player_position(pos: Vector2, vel: Vector2):
	_sync_player_state(pos, vel, "", false)

func _input(event: InputEvent) -> void:
	# Block ALL input for dying or ghost players
	if is_dying or current_state == PlayerState.GHOST: 
		return
	# Only the authority handles inputs
	if not is_multiplayer_authority(): 
		return
	if not is_main_player: 
		return
	
	# Handle fire input (both mouse and keyboard)
	if Input.is_action_just_pressed("fire"):
		print("[Player] FIRE INPUT DETECTED! Role: ", PlayerRole.keys()[role], " Ammo: ", ammo, " CanAttack: ", can_attack)
		_handle_fire_sak_input()

# Alternative input handler in case _input is being consumed
func _unhandled_input(event: InputEvent) -> void:
	# Block ALL unhandled input for dying or ghost players
	if is_dying or current_state == PlayerState.GHOST:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("[Player] UNHANDLED MOUSE INPUT - Player: ", player_name, " Authority: ", is_multiplayer_authority(), " Main: ", is_main_player)
		if is_multiplayer_authority() and is_main_player:
			print("[Player] Processing unhandled left click as fire/sak")
			_handle_fire_sak_input()

# PHASE 1: Simplified input handler for server-authoritative attacks
func _handle_phase1_fire_input() -> void:
	"""Phase 1: All players can fire projectiles regardless of role"""
	if not can_attack:
		print("[Player] Cannot attack - can_attack is false")
		return
	if is_in_action:
		print("[Player] Cannot attack - already in action")
		return
	
	print("[Player] Phase 1: Requesting projectile fire from server")
	# The client sends a request to the server to fire
	request_fire_projectile_rpc.rpc_id(1)

# Simplified input handling - just send attack request to server
func _handle_fire_sak_input() -> void:
	print("[Player] FIRE INPUT DETECTED! Role: ", PlayerRole.keys()[role], " CanAttack: ", can_attack, " CanSak: ", can_sak)
	
	# Simple client-side check - don't spam if already in action
	if is_in_action:
		print("[Player] Cannot attack - already in action")
		return
	
	# CLIENT-SIDE VALIDATION: Check basic permissions
	if role == PlayerRole.HIDER and not can_sak:
		print("[Player] ❌ CLIENT: Hider cannot SAK yet - can_sak is false")
		return
	elif role == PlayerRole.SEEKER and not can_attack:
		print("[Player] ❌ CLIENT: Seeker cannot attack yet - can_attack is false") 
		return
	
	# Send attack request to server - let server validate everything
	print("[Player] 🎯 Sending attack request to server")
	server_request_attack.rpc_id(1)

# Server-side attack validation and execution
@rpc("any_peer", "call_local", "reliable")
func server_request_attack() -> void:
	"""Server validates and executes attack requests"""
	if not multiplayer.is_server():
		return
	
	var requester_id = multiplayer.get_remote_sender_id()
	print("[Player] Server received attack request from peer: ", requester_id)
	
	# Validate game state and player permissions
	var game_manager = GameManager
	if not game_manager:
		print("[Player] Server rejected attack - GameManager not found")
		return
	
	# Check if player is in action
	if is_in_action:
		print("[Player] Server rejected attack - player already in action")
		show_temporary_message.rpc_id(requester_id, "You're already attacking!")
		return
	
	# Role-specific validation and execution
	if role == PlayerRole.SEEKER:
		_server_validate_seeker_attack(requester_id, game_manager)
	elif role == PlayerRole.HIDER:
		_server_validate_hider_attack(requester_id, game_manager)
	else:
		show_temporary_message.rpc_id(requester_id, "Invalid role for attack!")

func _server_validate_seeker_attack(requester_id: int, game_manager: Node) -> void:
	"""Server validates Seeker BANG attack"""
	# Check if Seeker can attack in current game state
	if not can_attack:
		show_temporary_message.rpc_id(requester_id, "Attacks disabled - wait for your turn!")
		return
	
	# Check ammo requirement
	if ammo < max_ammo:
		show_temporary_message.rpc_id(requester_id, "Need full ammo to attack! (" + str(ammo) + "/" + str(max_ammo) + ")")
		return
	
	# Execute BANG attack
	print("[Player] 🎯 Server authorizing Seeker BANG attack")
	var aim_direction = (get_global_mouse_position() - global_position).normalized()
	request_fire_projectile_rpc.rpc_id(1, aim_direction)

func _server_validate_hider_attack(requester_id: int, game_manager: Node) -> void:
	"""Server validates Hider SAK attack"""
	# Check if Hider can SAK in current game state
	if not can_sak:
		show_temporary_message.rpc_id(requester_id, "You're panicked and can't attack yet!")
		return
	
	# Find nearest target
	var nearest_target = _find_nearest_sak_target()
	if not nearest_target:
		show_temporary_message.rpc_id(requester_id, "No targets in range!")
		return
	
	# Execute SAK attack
	print("[Player] 🗡️ Server authorizing Hider SAK attack on: ", nearest_target.player_name)
	request_sak_attack_rpc.rpc_id(1, nearest_target.get_multiplayer_authority())

@rpc("any_peer", "call_local", "reliable")
func show_temporary_message(message: String) -> void:
	"""Show temporary message to specific client"""
	print("[Player] Temporary message: ", message)
	# This could be connected to UI later for better user feedback

# Helper function to find nearest valid SAK target
func _find_nearest_sak_target() -> PlayerCharacter:
	var nearest_target = null
	var nearest_distance = 50.0  # SAK range limit
	
	for player in get_tree().get_nodes_in_group("player"):
		if player == self or not is_instance_valid(player):
			continue
		# FRIENDLY FIRE ENABLED: Hiders can target both Seekers and other Hiders
		# This adds strategic risk - must be careful not to eliminate fellow Hiders!
		if player.current_state == PlayerState.GHOST:  # Can't SAK ghosts
			continue
			
		var distance = global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = player
	
	return nearest_target

func eliminate(attacker: PlayerCharacter) -> void:
	if is_dying or current_state == PlayerState.GHOST: 
		return
	
	print("[Player] Eliminating ", player_name, " - starting death sequence")
	is_dying = true
	
	# Disable all interactions immediately
	can_move = false
	can_attack = false
	collision_shape.disabled = true
	melee_range.monitoring = false
	vision_cone.monitoring = false
	
	# Notify GameManager of elimination
	if GameManager:
		GameManager.player_eliminated.emit(self, attacker)
	
	# Play death animation - become_ghost() will be called when animation finishes
	animated_sprite.stop()
	animated_sprite.play("death")
	print("[Player] Playing death animation for ", player_name, " - current: ", animated_sprite.animation)

func become_ghost() -> void:
	print(player_name, " has become a ghost!")
	current_state = PlayerState.GHOST
	
	# Make ghost semi-transparent
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 0.5)  # Semi-transparent white
	
	# Change vision light to cyan for ghosts
	if vision_light:
		vision_light.color = Color.CYAN
	
	# Disable collision for ghosts
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# Notify GameManager for win condition checking
	if GameManager and GameManager.has_method("check_win_conditions"):
		GameManager.check_win_conditions()
	
	print("[Player] ", player_name, " is now a ghost (transparent: ", animated_sprite.modulate.a, ")")
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	animated_sprite.set_visibility_layer_bit(1, false)
	animated_sprite.set_visibility_layer_bit(2, true)
	if is_main_player:
		camera.set_cull_mask_bit(2, true)

# Called by GameManager when fire action is approved
func execute_fire_projectile() -> void:
	if is_in_action: 
		print("[Player] Cannot execute fire - already in action")
		return
	if role != PlayerRole.SEEKER:
		print("[Player] ERROR: Non-seeker trying to fire!")
		return
		
	print("[Player] Executing fire projectile - ", player_name)
	is_in_action = true
	
	# Force stop current animation and play seeker_bang
	animated_sprite.stop()
	animated_sprite.play("seeker_bang")
	print("[Player] Playing seeker_bang animation - current: ", animated_sprite.animation)

# Called by GameManager when SAK action is approved
func execute_sak_attack(target: PlayerCharacter) -> void:
	if is_in_action: 
		print("[Player] Cannot execute SAK - already in action")
		return
	if role != PlayerRole.HIDER:
		print("[Player] ERROR: Non-hider trying to SAK!")
		return
	if not is_instance_valid(target):
		print("[Player] ERROR: Invalid SAK target!")
		return
		
	print("[Player] Executing SAK attack - ", player_name, " -> ", target.player_name)
	target_for_sak = target
	is_in_action = true
	
	# Force stop current animation and play hider_sak
	animated_sprite.stop()
	animated_sprite.play("hider_sak")
	print("[Player] Playing hider_sak animation - current: ", animated_sprite.animation)

func handle_movement() -> void:
	# CRITICAL: Movement is now strictly gated by the can_move boolean
	if not can_move:
		velocity = Vector2.ZERO
		move_and_slide()
		return
		
	if is_in_action:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# Get input and apply movement
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_direction * current_speed
	move_and_slide()
	
	# Debug output for movement
	if input_direction != Vector2.ZERO and randf() < 0.05:
		print("[Player] ", player_name, " moving with input: ", input_direction, " velocity: ", velocity, " position: ", global_position)

func handle_visuals() -> void:
	var mouse_position = get_global_mouse_position()
	vision_cone.look_at(mouse_position)
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	
	# Don't change animations during action sequences
	if is_in_action: 
		print("[Player] Skipping visual update - in action. Current animation: ", animated_sprite.animation)
		return
	var is_aiming_up = (mouse_position.y < global_position.y)
	if velocity.length() > 0:
		var is_running = Input.is_action_pressed("run")
		var anim_to_play = ""
		if is_aiming_up: anim_to_play = "back_run" if is_running else "back_walk"
		else: anim_to_play = "front_run" if is_running else "front_walk"
		animated_sprite.play(anim_to_play)
	else:
		if is_aiming_up: animated_sprite.play("back_idle")
		else: animated_sprite.play("idle")

func handle_remote_visuals() -> void:
	# Handle animations for remote players based on velocity and synced state
	if is_in_action: return
	
	# Update animation transition time
	_animation_transition_time += get_physics_process_delta_time()
	
	# Use synced animation if available, otherwise fall back to velocity-based
	if _sync_animation != "" and _animation_transition_time < 0.5:
		# Use synced animation state for better accuracy
		if animated_sprite.animation != _sync_animation:
			if animated_sprite.sprite_frames.has_animation(_sync_animation):
				animated_sprite.play(_sync_animation)
		animated_sprite.flip_h = _sync_flip
	else:
		# Fallback to velocity-based animations with smoother logic
		if velocity.length() > 10.0:  # Small threshold to avoid micro-movements
			# Determine if running based on velocity magnitude
			var is_running = velocity.length() > walk_speed * 1.2  # Lower threshold for smoother transition
			var anim_to_play = ""
			
			# Improved animation logic based on movement direction
			var vel_normalized = velocity.normalized()
			
			# Determine primary direction
			if abs(vel_normalized.y) > 0.7:  # Mostly vertical movement
				if vel_normalized.y < 0:
					anim_to_play = "back_run" if is_running else "back_walk"
				else:
					anim_to_play = "front_run" if is_running else "front_walk"
			else:
				# Horizontal or diagonal movement
				anim_to_play = "front_run" if is_running else "front_walk"
			
			# Set sprite direction based on velocity with hysteresis to avoid flipping
			if abs(velocity.x) > 20.0:  # Only flip if moving significantly horizontally
				animated_sprite.flip_h = velocity.x < 0
			
			# Only change animation if it's different to avoid stuttering
			if animated_sprite.animation != anim_to_play:
				animated_sprite.play(anim_to_play)
		else:
			# Idle animation with smooth transition
			if animated_sprite.animation != "idle":
				animated_sprite.play("idle")

func update_all_players_in_cone() -> void:
	var overlapping_bodies: Array[Node2D] = vision_cone.get_overlapping_bodies()
	hiders_in_cone.clear()
	for body in overlapping_bodies:
		var player: PlayerCharacter = body as PlayerCharacter
		if player and player != self and player.current_state == PlayerState.ALIVE:
			hiders_in_cone.append(player)

func check_line_of_sight() -> void:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = collision_shape.shape
	shape_query.transform = global_transform
	shape_query.collision_mask = 2 
	var intersection_result: Array[Dictionary] = space_state.intersect_shape(shape_query)
	if not intersection_result.is_empty():
		for player in previously_visible_hiders:
			player.visible = false
			# Hide spotted alert when LOS is broken
			if role == PlayerRole.SEEKER:
				_hide_spotted_alert_for_player(player)
		previously_visible_hiders.clear()
		visible_targets.clear()
		return
		
	var currently_visible_players: Array[PlayerCharacter] = []
	for player in hiders_in_cone:
		var ray_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, player.global_position, 2)
		var result: Dictionary = space_state.intersect_ray(ray_query)
		if result.is_empty():
			# Send vision data to GameManager instead of handling directly
			if GameManager:
				GameManager.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), true)
			
			# Show spotted alert for Hiders when seen by Seeker
			if role == PlayerRole.SEEKER and player.role == PlayerRole.HIDER:
				_show_spotted_alert_for_player(player)
			
			currently_visible_players.append(player)
		else:
			# Player is not visible
			if GameManager:
				GameManager.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), false)
			
			# Hide spotted alert when LOS is broken
			if role == PlayerRole.SEEKER:
				_hide_spotted_alert_for_player(player)
	
	# Update local visibility for immediate feedback
	for player in previously_visible_hiders:
		if not player in currently_visible_players:
			player.visible = false
			# Hide spotted alert when player leaves vision
			if role == PlayerRole.SEEKER:
				_hide_spotted_alert_for_player(player)
	for player in currently_visible_players:
		player.visible = true
	
	previously_visible_hiders = currently_visible_players
	if role == PlayerRole.SEEKER:
		visible_targets = currently_visible_players

# --- SPOTTED ALERT SYSTEM ---

func _show_spotted_alert_for_player(target_player: PlayerCharacter):
	"""Show spotted alert on the target player's screen"""
	if not target_player or target_player.role != PlayerRole.HIDER:
		return
	
	# Send RPC to show spotted alert on the target's client
	var target_id = target_player.get_multiplayer_authority()
	_trigger_spotted_alert.rpc_id(target_id)

func _hide_spotted_alert_for_player(target_player: PlayerCharacter):
	"""Hide spotted alert on the target player's screen"""
	if not target_player or target_player.role != PlayerRole.HIDER:
		return
	
	# Send RPC to hide spotted alert on the target's client
	var target_id = target_player.get_multiplayer_authority()
	_hide_spotted_alert.rpc_id(target_id)

@rpc("any_peer", "call_local", "reliable")
func _trigger_spotted_alert():
	"""RPC to trigger spotted alert on this client"""
	# Only show for Hiders
	if role != PlayerRole.HIDER or not is_main_player:
		return
	
	# Find GameUI and trigger spotted alert
	var game_ui = _find_game_ui()
	if game_ui and game_ui.has_method("show_spotted"):
		game_ui.show_spotted(true)

@rpc("any_peer", "call_local", "reliable")
func _hide_spotted_alert():
	"""RPC to hide spotted alert on this client"""
	# Only for Hiders
	if role != PlayerRole.HIDER or not is_main_player:
		return
	
	# Find GameUI and hide spotted alert
	var game_ui = _find_game_ui()
	if game_ui and game_ui.has_method("show_spotted"):
		game_ui.show_spotted(false)

# PHASE 3: Spotted Indicator Logic
@rpc("any_peer", "call_local", "reliable")
func set_spotted_status(is_spotted: bool) -> void:
	"""Server-authoritative spotted status for hiders"""
	print("[Player] 📡 RECEIVED: set_spotted_status - ", is_spotted, " for ", player_name, " (Peer: ", multiplayer.get_unique_id(), ")")
	
	# Only applies to Hiders
	if role != PlayerRole.HIDER:
		return
	
	# Toggle overhead "!" icon visibility
	var spotted_icon = get_node_or_null("SpottedIcon")  # Assuming this exists in player scene
	if spotted_icon:
		spotted_icon.visible = is_spotted
		print("[Player] ✅ Overhead spotted icon ", "shown" if is_spotted else "hidden", " for ", player_name)
	
	# Configure local UI if this is the local player
	if is_multiplayer_authority():
		var game_ui = _find_game_ui()
		if game_ui and game_ui.has_method("show_spotted"):
			game_ui.show_spotted(is_spotted)
			print("[Player] ✅ Local UI spotted indicator ", "shown" if is_spotted else "hidden")

func _find_game_ui() -> Control:
	"""Find the GameUI node in the scene"""
	# Try to find GameUI in the current scene
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_node("/root/DevWorld") # For dev_world.tscn
	
	if world and world.has_node("UI/GameUI"):
		return world.get_node("UI/GameUI")
	
	return null

# --- SIGNAL FUNCTIONS ---

func _on_game_state_changed(new_state: int) -> void:
	if not GameManager:
		# For dev_world, allow attacks by default
		can_move = true
		can_attack = true
		print("[Player] No GameManager found - enabling attacks for dev testing")
		return
		
	match new_state:
		GameManager.GameState.HIDER_HEADSTART:
			if role == PlayerRole.HIDER: can_move = true
			elif role == PlayerRole.SEEKER: can_move = false
		GameManager.GameState.GAME_START_COUNTDOWN:
			# Legacy countdown state - Seeker can move, Hiders can't attack yet
			if role == PlayerRole.SEEKER: can_move = true
			elif role == PlayerRole.HIDER: can_move = true
			can_attack = (role == PlayerRole.SEEKER)  # Only Seeker can attack during countdown
		GameManager.GameState.IN_PROGRESS:
			can_move = true
			can_attack = true  # Default to enabled for dev testing
			can_attack = true  # Enable attacks for both roles
		_:
			can_move = true
			can_attack = true  # Default to enabled for dev testing

func _on_animated_sprite_2d_animation_finished() -> void:
	print("[Player] Animation finished: ", animated_sprite.animation, " for ", player_name, " - is_in_action was: ", is_in_action)
	
	if animated_sprite.animation == "death":
		print("[Player] Death animation completed, becoming ghost...")
		become_ghost()
	else:
		# Reset action state for all non-death animations
		is_in_action = false
		target_for_sak = null
		print("[Player] Reset is_in_action to false for ", player_name) 

func _on_animated_sprite_2d_frame_changed() -> void:
	print("[Player] Frame changed - Animation: ", animated_sprite.animation, " Frame: ", animated_sprite.frame, " on ", player_name)
	
	# SEEKER BANG: Projectile spawns on frame 2 (server-authoritative)
	if animated_sprite.animation == "seeker_bang":
		if animated_sprite.frame == 2:
			print("[Player] SEEKER_BANG frame 2 - executing projectile spawn!")
			# This is called during the animation, so we spawn the projectile directly
			# The server validation already happened in request_fire_projectile_rpc
			if multiplayer.is_server() and role == PlayerRole.SEEKER:
				# Calculate aim direction (stored from the original request)
				var aim_direction = (get_global_mouse_position() - global_position).normalized()
				var projectile_rotation = aim_direction.angle()
				
				# Spawn projectile on all clients
				spawn_projectile_on_clients_rpc.rpc(muzzle.global_position, projectile_rotation, aim_direction)
				print("[Player] 🚀 SERVER: Projectile spawned from BANG animation frame 2")
				
	# HIDER SAK: Elimination happens on frame 2
	if animated_sprite.animation == "hider_sak":
		if animated_sprite.frame == 2:
			if is_instance_valid(target_for_sak):
				print("[Player] HIDER_SAK frame 2 - executing elimination!")
				# Direct elimination (already validated when SAK started)
				if multiplayer.is_server() and role == PlayerRole.HIDER:
					_eliminate_target_direct(target_for_sak)
				target_for_sak = null
			else:
				print("[Player] No valid SAK target!")

# --- PHASE 1: SERVER-AUTHORITATIVE ATTACK SYSTEM ---

# This RPC is sent from a client TO the server (peer_id = 1).
@rpc("any_peer", "call_local", "reliable")
func request_fire_projectile_rpc(aim_direction: Vector2 = Vector2.ZERO) -> void:
	"""Client requests to fire projectile - server validates and authorizes"""
	# This code only executes on the server's instance of this player.
	if not multiplayer.is_server():
		return
		
	if is_in_action: 
		print("[Player] Server rejected fire request - already in action")
		return

	# Server validation: ensure player can attack and has full ammo
	if not can_attack or role != PlayerRole.SEEKER:
		print("[Player] Server rejected fire request - can_attack: ", can_attack, " role: ", PlayerRole.keys()[role])
		return
	
	# NEW: Seeker must have FULL ammo capacity to attack
	if ammo < max_ammo:
		print("[Player] Server rejected fire request - insufficient ammo: ", ammo, "/", max_ammo, " (must be full)")
		return

	print("[Player] 🎯 SERVER: Seeker attack authorized - starting BANG animation")
	
	# The server validates the action, updates state, and triggers animation
	is_in_action = true
	set_ammo.rpc(ammo - 1) # Sync ammo change to all clients
	
	# Store aim direction for use in animation frame 2
	# (We'll use get_global_mouse_position() in the frame handler)
	
	# Command all clients to play the BANG animation
	play_attack_animation.rpc("seeker_bang")
	
	# Note: Projectile will be spawned in _on_animated_sprite_2d_frame_changed() at frame 2
	# is_in_action will be reset when animation finishes in _on_animated_sprite_2d_animation_finished()

# RPC to play attack animations on all clients
@rpc("any_peer", "call_local", "reliable")
func play_attack_animation(animation_name: String) -> void:
	"""Play attack animation on all clients"""
	print("[Player] 🎬 Playing attack animation: ", animation_name, " on ", player_name)
	if animated_sprite:
		print("[Player] 🎬 AnimatedSprite2D found, current animation: ", animated_sprite.animation)
		animated_sprite.play(animation_name)
		print("[Player] 🎬 Animation set to: ", animated_sprite.animation, " - is_playing: ", animated_sprite.is_playing())
		
		# Force stop any current animation first for immediate response
		if animation_name == "hider_sak":
			print("[Player] 🗡️ HIDER_SAK animation starting - should see frame changes soon")
		elif animation_name == "seeker_bang":
			print("[Player] 🎯 SEEKER_BANG animation starting - should see frame changes soon")
	else:
		print("[Player] ❌ ERROR: No AnimatedSprite2D found on ", player_name)

# RPC for Hider SAK attack requests
@rpc("any_peer", "call_local", "reliable")
func request_sak_attack_rpc(target_player_id: int) -> void:
	"""Client requests to perform SAK attack - server validates and authorizes"""
	# This code only executes on the server's instance of this player
	if not multiplayer.is_server():
		return
		
	if is_in_action:
		print("[Player] Server rejected SAK request - already in action")
		return

	# Server validation: ensure player can SAK and is a Hider
	if not can_sak or role != PlayerRole.HIDER:
		print("[Player] Server rejected SAK request - can_sak: ", can_sak, " role: ", PlayerRole.keys()[role])
		return
	
	# Find the target player
	var target_player = null
	for player in get_tree().get_nodes_in_group("player"):
		if player.get_multiplayer_authority() == target_player_id:
			target_player = player
			break
	
	if not target_player or not is_instance_valid(target_player):
		print("[Player] Server rejected SAK request - invalid target")
		return
	
	# FRIENDLY FIRE ENABLED: Hiders can SAK both Seekers and other Hiders
	# Strategic risk: Hiders must be careful not to eliminate teammates!
	print("[Player] 🎯 FRIENDLY FIRE: Target ", target_player.player_name, " role: ", PlayerRole.keys()[target_player.get_role()])
	
	# Check if target is in range (basic distance check)
	var distance = global_position.distance_to(target_player.global_position)
	if distance > 50.0:  # Adjust SAK range as needed
		print("[Player] Server rejected SAK request - target out of range: ", distance)
		return
	
	print("[Player] 🗡️ SERVER: Hider SAK attack authorized on ", target_player.player_name)
	
	# Set up SAK attack (SAK attacks do NOT consume ammo)
	is_in_action = true
	target_for_sak = target_player
	
	# Command all clients to play the SAK animation
	play_attack_animation.rpc("hider_sak")
	print("[Player] 🗡️ SAK animation triggered - no ammo consumed")
	
	# Note: Elimination will happen in _on_animated_sprite_2d_frame_changed() at frame 2

# This RPC is sent FROM the server TO all clients
@rpc("authority", "call_local", "reliable")
func spawn_projectile_on_clients_rpc(spawn_pos: Vector2, spawn_rot: float, aim_direction: Vector2 = Vector2.ZERO) -> void:
	"""Server commands all clients to spawn projectile at specified position/rotation"""
	print("[Player] 🚀 CLIENT: Spawning projectile at ", spawn_pos, " with rotation ", spawn_rot)
	var rock: Area2D = ROCK_PROJECTILE_SCENE.instantiate()
	rock.global_position = spawn_pos
	rock.rotation = spawn_rot
	
	# Set the owner_player reference for collision detection
	if rock.has_method("set_owner_player"):
		rock.set_owner_player(self)
	elif "owner_player" in rock:
		rock.owner_player = self
	
	# Set projectile direction if it has a direction property
	if "direction" in rock and aim_direction != Vector2.ZERO:
		rock.direction = aim_direction
	
	# Add to the main scene tree so it's not a child of the player
	get_tree().get_root().add_child(rock)
	print("[Player] ✅ CLIENT: Projectile spawned successfully with direction ", aim_direction)
