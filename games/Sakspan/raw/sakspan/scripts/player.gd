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
var can_move: bool = true  # Allow movement by default
var can_attack: bool = true  # Allow attacks by default

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
	
	# Connect to GameManager signals
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.game_state_changed.connect(_on_game_state_changed)
	
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

func assign_role(new_role: PlayerRole):
	self.role = new_role
	if self.role == PlayerRole.SEEKER:
		add_to_group("seeker")
		if is_in_group("hider"): remove_from_group("hider")
		melee_range.monitoring = false
		# Give seeker some ammo for testing
		if ammo <= 0:
			ammo = 5
			print("[Player] Seeker assigned, setting ammo to: ", ammo)
	else:
		add_to_group("hider")
		vision_light.energy = 0.5
	print(player_name, " has been assigned the role of: ", PlayerRole.keys()[role])
	
	# Show role overlay for the local player
	if is_main_player:
		# Delay slightly to ensure everything is set up
		await get_tree().process_frame
		display_role_for_round()

func set_ammo(new_ammo_count: int) -> void:
	ammo = new_ammo_count

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
	
	# Only the multiplayer authority simulates input and movement
	if is_multiplayer_authority():
		handle_movement()
		if current_state == PlayerState.GHOST: return
		handle_visuals()
		update_all_players_in_cone()
		check_line_of_sight()
		
		# Sync position and animation state to other clients
		if Engine.get_physics_frames() % 2 == 0:  # Sync every 2nd frame
			var current_animation = animated_sprite.animation if animated_sprite else ""
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

# Helper function to handle fire/sak input
func _handle_fire_sak_input() -> void:
	if not can_attack:
		print("[Player] Cannot attack - can_attack is false")
		return
	if is_in_action:
		print("[Player] Cannot attack - already in action")
		return
		
	print("[Player] Handling fire/sak input - Role: ", PlayerRole.keys()[role], " Ammo: ", ammo)
	
	if role == PlayerRole.SEEKER and ammo > 0:
		print("[Player] Executing seeker fire - using direct method")
		_direct_fire_projectile()
	elif role == PlayerRole.SEEKER and ammo <= 0:
		print("[Player] Cannot fire - out of ammo")
	elif role == PlayerRole.HIDER:
		print("[Player] Executing hider SAK - using direct method")
		_direct_sak_attack()
	else:
		print("[Player] Invalid role or conditions for attack")

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
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm:
		gm.player_eliminated.emit(self, attacker)
	
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
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm and gm.has_method("check_win_conditions"):
		gm.check_win_conditions()
	
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
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm:
				gm.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), true)
			
			# Show spotted alert for Hiders when seen by Seeker
			if role == PlayerRole.SEEKER and player.role == PlayerRole.HIDER:
				_show_spotted_alert_for_player(player)
			
			currently_visible_players.append(player)
		else:
			# Player is not visible
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm:
				gm.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), false)
			
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
	if game_ui and game_ui.has_method("show_spotted_alert"):
		game_ui.show_spotted_alert()

@rpc("any_peer", "call_local", "reliable")
func _hide_spotted_alert():
	"""RPC to hide spotted alert on this client"""
	# Only for Hiders
	if role != PlayerRole.HIDER or not is_main_player:
		return
	
	# Find GameUI and hide spotted alert
	var game_ui = _find_game_ui()
	if game_ui and game_ui.has_method("_hide_spotted_alert"):
		game_ui._hide_spotted_alert()

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
	var game_manager: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if not game_manager:
		# For dev_world, allow attacks by default
		can_move = true
		can_attack = true
		print("[Player] No GameManager found - enabling attacks for dev testing")
		return
		
	match new_state:
		game_manager.GameState.HIDER_HEADSTART:
			if role == PlayerRole.HIDER: can_move = true
			elif role == PlayerRole.SEEKER: can_move = false
			can_attack = false
		game_manager.GameState.GAME_START_COUNTDOWN:
			# Legacy countdown state - Seeker can move, Hiders can't attack yet
			if role == PlayerRole.SEEKER: can_move = true
			elif role == PlayerRole.HIDER: can_move = true
			can_attack = (role == PlayerRole.SEEKER)  # Only Seeker can attack during countdown
		game_manager.GameState.IN_PROGRESS:
			can_move = true
			can_attack = true  # Enable attacks for both roles
		_:
			can_move = true
			can_attack = true  # Default to enabled for dev testing

func _on_animated_sprite_2d_animation_finished() -> void:
	print("[Player] Animation finished: ", animated_sprite.animation, " for ", player_name)
	
	if animated_sprite.animation == "death":
		print("[Player] Death animation completed, becoming ghost...")
		become_ghost()
	else:
		# Reset action state for all non-death animations
		is_in_action = false
		target_for_sak = null
		print("[Player] Reset is_in_action to false for ", player_name) 

func _on_animated_sprite_2d_frame_changed() -> void:
	print("[Player] Frame changed - Animation: ", animated_sprite.animation, " Frame: ", animated_sprite.frame)
	
	if animated_sprite.animation == "seeker_bang":
		if animated_sprite.frame == 2:
			print("[Player] SEEKER_BANG frame 2 - creating projectile!")
			# Try GameManager first, then fallback to direct creation
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm and gm.has_method("create_projectile"):
				gm.create_projectile.rpc_id(1, multiplayer.get_unique_id(), muzzle.global_position, vision_cone.global_rotation)
			else:
				print("[Player] Creating projectile directly")
				_create_projectile_direct()
				
	if animated_sprite.animation == "hider_sak":
		if animated_sprite.frame == 2:
			print("[Player] HIDER_SAK frame 2 - executing elimination!")
			if is_instance_valid(target_for_sak):
				# Try GameManager first, then fallback to direct elimination
				var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
				if gm and gm.has_method("execute_elimination"):
					gm.execute_elimination.rpc_id(1, target_for_sak.get_multiplayer_authority(), multiplayer.get_unique_id())
				else:
					print("[Player] Executing elimination directly")
					_eliminate_target_direct(target_for_sak)
				target_for_sak = null
			else:
				print("[Player] No valid SAK target!")
