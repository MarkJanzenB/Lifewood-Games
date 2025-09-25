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
# REFACTORED: Granular ability system - removed global can_attack
var can_bang: bool = false  # Seeker BANG attack ability
var can_sak: bool = false  # Hider SAK attack ability
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
		# REFACTORED: No default attack permissions - GameManager controls these
		if camera:
			camera.enabled = true
			camera.make_current()

# Called by World script when spawning players
func setup_multiplayer_player(player_data: Dictionary, is_local: bool):
	player_name = player_data.get("name", "Player")
	is_main_player = is_local
	
	# Enable movement for all players - abilities controlled by GameManager
	can_move = true
	# REFACTORED: Removed default attack permission
	
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

# DEPRECATED: Bypasses GameManager authority - use GameManager RPC system instead
func enable_basic_controls() -> void:
	"""DEPRECATED: Enable immediate movement and attack capabilities for testing"""
	print("[Player] ⚠️ DEPRECATED: enable_basic_controls() bypasses GameManager authority")
	can_move = true
	# REFACTORED: Enable role-specific abilities for testing
	if role == PlayerRole.SEEKER:
		can_bang = true
	elif role == PlayerRole.HIDER:
		can_sak = true
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
		# Ghosts have limited interactions
		if current_state == PlayerState.GHOST:
			_handle_ghost_visuals()
			return
			
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

# DEPRECATED: Use set_initial_state() or set_ability_permissions() instead
@rpc("any_peer", "call_local", "reliable")
func set_player_state(p_can_move: bool, p_can_attack: bool) -> void:
	print("[Player] ⚠️ DEPRECATED: set_player_state() called - use set_initial_state() or set_ability_permissions()")
	self.can_move = p_can_move
	# REFACTORED: Convert legacy can_attack to role-specific abilities
	if role == PlayerRole.SEEKER:
		self.can_bang = p_can_attack
	elif role == PlayerRole.HIDER:
		self.can_sak = p_can_attack

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
	
	# Set player permissions - REFACTORED: Role-specific abilities
	self.can_move = p_can_move
	if new_role == PlayerRole.SEEKER:
		self.can_bang = p_can_attack
		self.can_sak = false  # Seekers cannot SAK
	elif new_role == PlayerRole.HIDER:
		self.can_bang = false  # Hiders cannot BANG
		self.can_sak = false  # Start disabled, GameManager will enable later
	
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

# REFACTORED: Granular ability permission system
@rpc("any_peer", "call_local", "reliable")
func set_ability_permissions(p_can_move: bool, p_can_bang: bool, p_can_sak: bool) -> void:
	"""Granular ability control system - role-specific permissions"""
	self.can_move = p_can_move
	self.can_bang = p_can_bang
	self.can_sak = p_can_sak
	print("[Player] Abilities updated for ", player_name, " - Move: ", can_move, " BANG: ", can_bang, " SAK: ", can_sak)

# DEPRECATED: Legacy compatibility wrapper
@rpc("any_peer", "call_local", "reliable")
func set_game_state_controls(p_can_move: bool, p_can_attack: bool, p_can_sak: bool) -> void:
	"""DEPRECATED: Use set_ability_permissions() instead"""
	print("[Player] ⚠️ DEPRECATED: set_game_state_controls() - use set_ability_permissions()")
	self.can_move = p_can_move
	if role == PlayerRole.SEEKER:
		self.can_bang = p_can_attack
	elif role == PlayerRole.HIDER:
		self.can_sak = p_can_sak
	print("[Player] Controls updated for ", player_name, " - Move: ", can_move, " BANG: ", can_bang, " SAK: ", can_sak)

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
			# Stop regeneration when max ammo reached
			if multiplayer.is_server():
				GameManager.ammo_regen_timer.stop()
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
		print("[Player] FIRE INPUT DETECTED! Role: ", PlayerRole.keys()[role], " Ammo: ", ammo, " CanBANG: ", can_bang, " CanSAK: ", can_sak)
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
	# REFACTORED: Check role-specific abilities
	var can_perform_attack := false
	if role == PlayerRole.SEEKER and can_bang:
		can_perform_attack = true
	elif role == PlayerRole.HIDER and can_sak:
		can_perform_attack = true
	
	if not can_perform_attack:
		print("[Player] Cannot attack - role-specific ability disabled")
		return
	if is_in_action:
		print("[Player] Cannot attack - already in action")
		return
	
	print("[Player] Phase 1: Requesting projectile fire from server")
	# The client sends a request to the server to fire
	request_fire_projectile_rpc.rpc_id(1)

# Simplified input handling - just send attack request to server
func _handle_fire_sak_input() -> void:
	print("[Player] FIRE INPUT DETECTED! Role: ", PlayerRole.keys()[role], " CanBANG: ", can_bang, " CanSAK: ", can_sak)
	
	# Simple client-side check - don't spam if already in action
	if is_in_action:
		print("[Player] Cannot attack - already in action")
		return
	
	# REFACTORED: Role-specific ability validation
	if role == PlayerRole.HIDER and not can_sak:
		print("[Player] ❌ CLIENT: Hider cannot SAK yet - can_sak is false")
		return
	elif role == PlayerRole.SEEKER and not can_bang:
		print("[Player] ❌ CLIENT: Seeker cannot BANG yet - can_bang is false") 
		return
	elif role == PlayerRole.SEEKER and ammo <= 0:
		print("[Player] ❌ CLIENT: Seeker has no ammo - ammo: ", ammo, "/", max_ammo)
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
	print("[Player] Server received attack request from peer: ", requester_id, " on player: ", player_name, " (role: ", PlayerRole.keys()[role], ")")
	
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
		print("[Player] 🎯 Processing SEEKER attack request")
		_server_validate_seeker_attack(requester_id, game_manager)
	elif role == PlayerRole.HIDER:
		print("[Player] 🗡️ Processing HIDER attack request")
		_server_validate_hider_attack(requester_id, game_manager)
	else:
		print("[Player] ❌ Invalid role for attack: ", role)
		show_temporary_message.rpc_id(requester_id, "Invalid role for attack!")

func _server_validate_seeker_attack(requester_id: int, game_manager: Node) -> void:
	"""Server validates Seeker BANG attack"""
	# REFACTORED: Check role-specific ability
	if not can_bang:
		print("[Player] ❌ Server rejected Seeker attack - can_bang is false")
		show_temporary_message.rpc_id(requester_id, "BANG attacks disabled - wait for your turn!")
		return
	
	# Check ammo requirement - Seeker needs at least 1 ammo to attack
	if ammo <= 0:
		print("[Player] ❌ Server rejected Seeker attack - no ammo (", ammo, "/", max_ammo, ")")
		show_temporary_message.rpc_id(requester_id, "No ammo! (" + str(ammo) + "/" + str(max_ammo) + ")")
		return
	
	# Execute BANG attack
	print("[Player] 🎯 Server authorizing Seeker BANG attack - ammo: ", ammo, "/", max_ammo)
	var aim_direction = (get_global_mouse_position() - global_position).normalized()
	request_fire_projectile_rpc.rpc_id(1, aim_direction)

func _server_validate_hider_attack(requester_id: int, game_manager: Node) -> void:
	"""Server validates Hider SAK attack"""
	print("[Player] 🗡️ Server validating Hider SAK attack from peer: ", requester_id, " - can_sak: ", can_sak)
	
	# Check if Hider can SAK in current game state
	if not can_sak:
		print("[Player] ❌ Server rejected Hider SAK - can_sak is false")
		show_temporary_message.rpc_id(requester_id, "You're panicked and can't attack yet!")
		return
	
	# Find nearest target
	var nearest_target = _find_nearest_sak_target()
	if not nearest_target:
		print("[Player] ❌ Server rejected Hider SAK - no targets in range")
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
	
	print("[Player] 💀 Eliminating ", player_name, " - starting death sequence")
	is_dying = true
	
	# Disable all interactions immediately
	can_move = false
	# REFACTORED: Disable all abilities
	can_bang = false
	can_sak = false
	collision_shape.disabled = true
	melee_range.monitoring = false
	vision_cone.monitoring = false
	
	# Stop any current actions
	is_in_action = false
	target_for_sak = null
	
	# Notify GameManager of elimination (server-side only)
	if multiplayer.is_server() and GameManager:
		GameManager.player_eliminated.emit(self, attacker)
	
	# Play death animation on all clients
	play_death_animation.rpc()
	
	print("[Player] 🎬 Death sequence initiated for ", player_name)

# RPC to play death animation on all clients
@rpc("any_peer", "call_local", "reliable")
func play_death_animation() -> void:
	"""Play death animation synchronized across all clients"""
	print("[Player] 🎬 Playing death animation on ", player_name)
	
	# Stop current animation and play death
	animated_sprite.stop()
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		print("[Player] ✅ Death animation started for ", player_name)
	else:
		print("[Player] ⚠️ No death animation found, becoming ghost immediately")
		# If no death animation exists, become ghost immediately
		become_ghost()

func become_ghost() -> void:
	print("[Player] 👻 ", player_name, " has become a ghost!")
	current_state = PlayerState.GHOST
	is_dying = false  # Death sequence complete
	
	# Visual changes for ghost state - make them much more transparent and ghostly
	animated_sprite.modulate = Color(0.7, 0.9, 1.0, 0.4)  # More transparent with blue tint
	
	# Add a subtle glow effect by duplicating the sprite with a larger, more transparent version
	_add_ghost_glow_effect()
	
	# Start floating animation for ghosts
	_start_ghost_floating_animation()
	
	# Change vision light to cyan for ghosts (if they have one)
	if vision_light:
		vision_light.color = Color.CYAN
		vision_light.energy = 0.3  # Dimmer light for ghosts
	
	# Configure ghost collision layers
	# Layer 1: Normal players (disable)
	# Layer 3: Ghosts (enable)
	set_collision_layer_value(1, false)  # Don't collide with living players
	set_collision_layer_value(3, true)   # Collide with other ghosts
	set_collision_mask_value(1, false)   # Don't detect living players
	set_collision_mask_value(3, true)    # Detect other ghosts
	set_collision_mask_value(4, true)    # Still detect obstacles
	
	# Enable ghost movement (they can still move around)
	can_move = true
	
	# Update username label for ghosts
	if username_label:
		username_label.add_theme_color_override("font_color", Color.CYAN)
		username_label.text = "👻 " + player_name
	
	# Notify GameManager for win condition checking (server only)
	if multiplayer.is_server() and GameManager and GameManager.has_method("check_win_conditions"):
		GameManager.check_win_conditions()
	
	# Show ghost status to local player
	if is_main_player:
		_show_ghost_status_message()
	
	print("[Player] ✅ ", player_name, " ghost transformation complete (alpha: ", animated_sprite.modulate.a, ")")

func _show_ghost_status_message() -> void:
	"""Show ghost status message to the local player"""
	var message := "👻 You are now a ghost! You can move around but cannot interact with living players."
	show_temporary_message.rpc_id(multiplayer.get_unique_id(), message)

func _add_ghost_glow_effect() -> void:
	"""Add a subtle glow effect to make ghosts more visible"""
	if not animated_sprite:
		return
	
	# Create a glow sprite behind the main sprite
	var glow_sprite = AnimatedSprite2D.new()
	glow_sprite.name = "GhostGlow"
	glow_sprite.sprite_frames = animated_sprite.sprite_frames
	glow_sprite.animation = animated_sprite.animation
	glow_sprite.frame = animated_sprite.frame
	
	# Make the glow larger and more transparent
	glow_sprite.scale = Vector2(1.2, 1.2)
	glow_sprite.modulate = Color(0.5, 0.8, 1.0, 0.2)  # Very transparent blue glow
	glow_sprite.z_index = animated_sprite.z_index - 1  # Behind the main sprite
	
	# Add it as a child
	add_child(glow_sprite)
	
	# Sync the glow animation with the main sprite
	if animated_sprite.is_connected("animation_changed", _on_ghost_animation_changed):
		animated_sprite.animation_changed.disconnect(_on_ghost_animation_changed)
	if animated_sprite.is_connected("frame_changed", _on_ghost_frame_changed):
		animated_sprite.frame_changed.disconnect(_on_ghost_frame_changed)
	
	animated_sprite.animation_changed.connect(_on_ghost_animation_changed)
	animated_sprite.frame_changed.connect(_on_ghost_frame_changed)
	
	print("[Player] ✨ Added ghost glow effect to ", player_name)

func _on_ghost_animation_changed() -> void:
	"""Sync glow sprite animation with main sprite"""
	var glow_sprite = get_node_or_null("GhostGlow")
	if glow_sprite and animated_sprite:
		glow_sprite.animation = animated_sprite.animation

func _on_ghost_frame_changed() -> void:
	"""Sync glow sprite frame with main sprite"""
	var glow_sprite = get_node_or_null("GhostGlow")
	if glow_sprite and animated_sprite:
		glow_sprite.frame = animated_sprite.frame

func _start_ghost_floating_animation() -> void:
	"""Add a subtle floating/bobbing animation to ghosts"""
	if not animated_sprite:
		return
	
	# Create a tween for the floating effect
	var ghost_tween = create_tween()
	ghost_tween.set_loops()  # Loop forever
	
	# Float up and down by 5 pixels over 4 seconds total
	var original_position = animated_sprite.position
	ghost_tween.tween_method(_set_ghost_float_position, original_position.y, original_position.y - 5, 1.0)
	ghost_tween.tween_method(_set_ghost_float_position, original_position.y - 5, original_position.y + 5, 2.0)
	ghost_tween.tween_method(_set_ghost_float_position, original_position.y + 5, original_position.y, 1.0)
	
	print("[Player] 🌊 Started floating animation for ghost ", player_name)

func _set_ghost_float_position(y_pos: float) -> void:
	"""Helper function for floating animation"""
	if animated_sprite:
		animated_sprite.position.y = y_pos
		# Also move the glow sprite
		var glow_sprite = get_node_or_null("GhostGlow")
		if glow_sprite:
			glow_sprite.position.y = y_pos

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
	# Handle ghost movement separately
	if current_state == PlayerState.GHOST:
		_handle_ghost_movement()
		return
	
	# Block movement for dying players
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
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

func _handle_ghost_movement() -> void:
	"""Handle movement for ghost players - they can move but with different physics"""
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var ghost_speed = walk_speed * 0.8  # Ghosts move slightly slower
	velocity = input_direction * ghost_speed
	move_and_slide()
	
	# Debug output for ghost movement
	if input_direction != Vector2.ZERO and randf() < 0.1:
		print("[Player] 👻 Ghost ", player_name, " moving: ", input_direction, " velocity: ", velocity)

func _handle_ghost_visuals() -> void:
	"""Handle visual updates for ghost players"""
	var mouse_position = get_global_mouse_position()
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	
	# Ghosts always use idle animation
	if animated_sprite.animation != "idle":
		animated_sprite.play("idle")

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
		if is_aiming_up: anim_to_play = "front_backward_run" if is_running else "front_backward_walk"
		else: anim_to_play = "front_run" if is_running else "front_walk"
		animated_sprite.play(anim_to_play)
	else:
		animated_sprite.play("idle")

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
					anim_to_play = "front_backward_run" if is_running else "front_backward_walk"
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
	
	var target_id = target_player.get_multiplayer_authority()
	if multiplayer.is_server():
		# Server directly triggers the alert on the target client
		_trigger_spotted_alert.rpc_id(target_id)
	else:
		# Client requests server to trigger alert
		_request_spotted_alert.rpc_id(1, target_id, true)

func _hide_spotted_alert_for_player(target_player: PlayerCharacter):
	"""Hide spotted alert on the target player's screen"""
	if not target_player or target_player.role != PlayerRole.HIDER:
		return
	
	var target_id = target_player.get_multiplayer_authority()
	if multiplayer.is_server():
		# Server directly hides the alert on the target client
		_hide_spotted_alert.rpc_id(target_id)
	else:
		# Client requests server to hide alert
		_request_spotted_alert.rpc_id(1, target_id, false)

@rpc("any_peer", "call_remote", "reliable")
func _request_spotted_alert(target_id: int, show: bool):
	"""RPC to request server to handle spotted alert"""
	if not multiplayer.is_server():
		return
	
	if show:
		_trigger_spotted_alert.rpc_id(target_id)
	else:
		_hide_spotted_alert.rpc_id(target_id)

@rpc("authority", "call_remote", "reliable")
func _trigger_spotted_alert():
	"""RPC to trigger spotted alert on this client"""
	# Only show for Hiders
	if role != PlayerRole.HIDER or not is_main_player:
		return
	
	# Find GameUI and trigger spotted alert
	var game_ui = _find_game_ui()
	if game_ui and game_ui.has_method("show_spotted"):
		game_ui.show_spotted(true)

@rpc("authority", "call_remote", "reliable")
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
	# CRITICAL FIX: Remove local state overrides - GameManager RPC system is authoritative
	# This function should only handle UI updates, not permission changes
	print("[Player] Game state changed to: ", new_state, " for ", player_name, " - GameManager controls permissions via RPC")

func _on_animated_sprite_2d_animation_finished() -> void:
	print("[Player] 🎬 Animation finished: ", animated_sprite.animation, " for ", player_name, " - is_in_action was: ", is_in_action)
	
	if animated_sprite.animation == "death":
		print("[Player] 💀 Death animation completed, becoming ghost...")
		become_ghost()
	else:
		# Reset action state for all non-death animations
		is_in_action = false
		target_for_sak = null
		print("[Player] ✅ Reset is_in_action to false for ", player_name) 

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

	# REFACTORED: Server validation with granular ability check
	if not can_bang or role != PlayerRole.SEEKER:
		print("[Player] Server rejected fire request - can_bang: ", can_bang, " role: ", PlayerRole.keys()[role])
		return
	
	# Seeker must have at least 1 ammo to attack
	if ammo <= 0:
		print("[Player] Server rejected fire request - no ammo: ", ammo, "/", max_ammo)
		return

	print("[Player] 🎯 SERVER: Seeker attack authorized - starting BANG animation")
	
	# The server validates the action, updates state, and triggers animation
	# NOTE: is_in_action will be set on all clients via play_attack_animation RPC
	set_ammo.rpc(ammo - 1) # Sync ammo change to all clients
	
	# Start ammo regeneration if not at max capacity
	if ammo - 1 < max_ammo:
		GameManager._start_ammo_regeneration()
	
	# Store aim direction for use in animation frame 2
	# (We'll use get_global_mouse_position() in the frame handler)
	
	# Command all clients to play the BANG animation
	play_attack_animation.rpc("seeker_bang")
	
	# Note: Projectile will be spawned in _on_animated_sprite_2d_frame_changed() at frame 2
	# is_in_action will be reset when animation finishes in _on_animated_sprite_2d_animation_finished()

# RPC to play attack animations on all clients
@rpc("any_peer", "call_local", "reliable")
func play_attack_animation(animation_name: String) -> void:
	"""Play attack animation on all clients - CRITICAL: Sync is_in_action state"""
	print("[Player] 🎬 Playing attack animation: ", animation_name, " on ", player_name)
	
	# CRITICAL FIX: Sync is_in_action state across all clients
	is_in_action = true
	print("[Player] 🔒 SYNC: Set is_in_action=true for animation sync on ", player_name)
	
	if animated_sprite:
		print("[Player] 🎬 AnimatedSprite2D found, current animation: ", animated_sprite.animation)
		# Force stop current animation to prevent interference
		animated_sprite.stop()
		animated_sprite.play(animation_name)
		print("[Player] 🎬 Animation set to: ", animated_sprite.animation, " - is_playing: ", animated_sprite.is_playing())
		
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
	# NOTE: is_in_action will be set on all clients via play_attack_animation RPC
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

# Removed direct RPC methods - using GameManager RPC system instead
