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

# --- STATE VARIABLES (Statically Typed) ---
var _sync_position: Vector2 = Vector2.ZERO
var current_state: PlayerState = PlayerState.ALIVE
var hiders_in_cone: Array[PlayerCharacter] = []
var visible_targets: Array[PlayerCharacter] = []
var previously_visible_hiders: Array[PlayerCharacter] = []
var is_in_action: bool = false
var target_for_sak: PlayerCharacter = null
var is_dying: bool = false
var can_move: bool = true  # Enable movement by default
var can_attack: bool = true  # Enable attacks by default

# Collision layers:
# 1 - Default (players, obstacles)
# 2 - Vision (for line of sight checks)
# 3 - Ghosts (visible to all players)
# 4 - Obstacles

# --- CORE FUNCTIONS ---

func _ready():
	await get_tree().process_frame
	
	# Initialize player state
	current_state = PlayerState.ALIVE
	
	# Connect to GameManager signals
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.game_state_changed.connect(_on_game_state_changed)
	
	# Setup MultiplayerSynchronizer
	if sync:
		_setup_replication_config()
		sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	
	# Configure role-specific settings
	if role == PlayerRole.HIDER:
		vision_light.energy = 0.5
	
	# Debug: Check if we have a character index set and apply appearance
	print("[Player] _ready() called for player: ", player_name)
	print("[Player] Character index: ", character_index)
	print("[Player] AnimatedSprite2D available: ", animated_sprite != null)
	
	# If we have a character index but no color applied yet, apply it now
	if character_index >= 0 and animated_sprite:
		var color = CharacterFactory.get_character_color(character_index)
		animated_sprite.modulate = color
		print("[Player] Applied character color in _ready(): ", color, " for ", CharacterFactory.get_character_name(character_index))

func _configure_multiplayer_authority():
	# Check if this is the local player (the one we control)
	var my_id = multiplayer.get_unique_id()
	var player_authority = get_multiplayer_authority()
	
	print("[Player] Configuring authority - My ID: ", my_id, ", Player authority: ", player_authority)
	
	if player_authority == my_id:
		# This is the local player we control
		is_main_player = true
		set_physics_process(true)
		set_process_unhandled_input(true)
		if camera:
			camera.enabled = true
			camera.make_current()
		if vision_light:
			vision_light.visible = true
		if vision_cone:
			vision_cone.monitoring = true
		if melee_range:
			melee_range.monitoring = true
		print("[Player] Configured as LOCAL player (controllable)")
	else:
		# This is a remote player
		is_main_player = false
		# Keep physics processing ON so we can interpolate remote players locally.
		# Only disable input processing and local-only visuals.
		set_physics_process(true)
		set_process_unhandled_input(false)
		if camera:
			camera.enabled = false
		if vision_light:
			vision_light.visible = false
		if vision_cone:
			vision_cone.monitoring = false
		if melee_range:
			melee_range.monitoring = false
		print("[Player] Configured as REMOTE player (not controllable)")

func _setup_replication_config():
	# Create and configure replication config for multiplayer synchronization
	if not sync:
		return
		
	var config = SceneReplicationConfig.new()
	
	# Add properties that need to be synchronized across clients
	config.add_property(".:position")
	config.add_property(".:rotation")
	config.add_property(".:role")
	config.add_property(".:player_state")
	config.add_property(".:player_name")
	config.add_property(".:health")
	config.add_property(".:ammo")
	config.add_property(".:is_main_player")
	
	# Set the config
	sync.replication_config = config
	print("[Player] Replication config set up for player: ", player_name)

# Called by World script when spawning players
func setup_multiplayer_player(player_data: Dictionary, is_local: bool):
	player_name = player_data.get("name", "Player")
	is_main_player = is_local
	
	print("[Player] Setting up multiplayer player: ", player_name, " (local: ", is_local, ")")
	
	# Apply character appearance if this is a base player
	var character_index = int(player_data.get("char_index", 0))
	_apply_character_setup(character_index)
	
	# Configure multiplayer authority properly
	_configure_multiplayer_authority()

# Apply character-specific setup (can be overridden by character classes)
func _apply_character_setup(char_index: int):
	set_character_index(char_index)
	
	print("[Player] Applying character setup for index: ", char_index, " (", CharacterFactory.get_character_name(char_index), ")")
	
	# If @onready variables aren't ready yet, defer the appearance setup
	if not animated_sprite:
		print("[Player] AnimatedSprite2D not ready yet, deferring character setup...")
		call_deferred("_apply_character_appearance_deferred", char_index)
		return
	
	# Apply character appearance directly
	if char_index >= 0 and char_index < CharacterFactory.CHARACTER_COLORS.size():
		var color = CharacterFactory.get_character_color(char_index)
		
		animated_sprite.modulate = color
		print("[Player] Applied character color: ", color, " to ", CharacterFactory.get_character_name(char_index))

# Deferred character appearance application
func _apply_character_appearance_deferred(char_index: int):
	print("[Player] Applying deferred character appearance for index: ", char_index)
	
	# Try to get the AnimatedSprite2D node directly if @onready failed
	var sprite_node = get_node_or_null("AnimatedSprite2D")
	if not sprite_node:
		print("[Player] ERROR: Could not find AnimatedSprite2D node!")
		return
	
	if char_index >= 0 and char_index < CharacterFactory.CHARACTER_COLORS.size():
		var color = CharacterFactory.get_character_color(char_index)
		sprite_node.modulate = color
		print("[Player] Successfully applied deferred character color: ", color, " to ", CharacterFactory.get_character_name(char_index))

# Get character info (can be overridden by character classes)
func get_character_index() -> int:
	return character_index

func set_character_index(index: int) -> void:
	character_index = index

func get_character_name() -> String:
	return CharacterFactory.get_character_name(get_character_index())

func get_character_color() -> Color:
	return CharacterFactory.get_character_color(get_character_index())

func set_is_main_player(value: bool):
	is_main_player = value
	_configure_multiplayer_authority()

func assign_role(new_role: PlayerRole):
	self.role = new_role
	if self.role == PlayerRole.SEEKER:
		add_to_group("seeker")
		if is_in_group("hider"): remove_from_group("hider")
		melee_range.monitoring = false
	else:
		add_to_group("hider")
		vision_light.energy = 0.5
	print(player_name, " has been assigned the role of: ", PlayerRole.keys()[role])

func set_ammo(new_ammo_count: int) -> void:
	ammo = new_ammo_count

func _physics_process(delta: float):
	if is_dying: return
	
	# Only the multiplayer authority simulates input and movement
	if is_multiplayer_authority():
		handle_movement()
		if current_state == PlayerState.GHOST: return
		handle_visuals()
		# Re-enable vision systems now that performance is fixed
		update_all_players_in_cone()
		check_line_of_sight()
		
		# Sync position to other clients (less frequently to avoid spam)
		if Engine.get_physics_frames() % 10 == 0:  # Only sync every 10th frame
			_sync_player_position.rpc(global_position, velocity)
	else:
		# Non-authority players just interpolate to synced position
		if _sync_position != Vector2.ZERO:
			global_position = global_position.lerp(_sync_position, delta * 10.0)

@rpc("any_peer", "unreliable")
func _sync_player_position(pos: Vector2, vel: Vector2):
	if not is_multiplayer_authority():
		_sync_position = pos
		velocity = vel

func _input(event: InputEvent) -> void:
	if is_dying or current_state == PlayerState.GHOST: return
	# Only the authority handles inputs
	if not is_multiplayer_authority(): return
	if not is_main_player: return
	if Input.is_action_just_pressed("fire"):
		if not can_attack: return
		# Request action from GameManager instead of handling directly
		var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
		if gm:
			if role == PlayerRole.SEEKER and ammo > 0:
				gm.request_player_action.rpc_id(1, multiplayer.get_unique_id(), "fire_projectile", {})
			if role == PlayerRole.HIDER:
				gm.request_player_action.rpc_id(1, multiplayer.get_unique_id(), "sak_attack", {})

func eliminate(attacker: PlayerCharacter) -> void:
	if is_dying or current_state == PlayerState.GHOST: return
	is_dying = true
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm:
		gm.player_eliminated.emit(self, attacker)
	animated_sprite.play("death")
	collision_shape.disabled = true
	melee_range.monitoring = false
	vision_cone.monitoring = false

func become_ghost() -> void:
	print(player_name, " has become a ghost!")
	current_state = PlayerState.GHOST
	var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if gm and gm.has_method("check_win_conditions"):
		gm.check_win_conditions()
	animated_sprite.modulate = Color(0.5, 0.7, 1, 0.5)
	vision_light.color = Color.CYAN
	set_collision_layer_value(1, false)
	set_collision_layer_value(3, true)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	animated_sprite.set_visibility_layer_bit(1, false)
	animated_sprite.set_visibility_layer_bit(2, true)
	if is_main_player:
		camera.set_cull_mask_bit(2, true)

# Called by GameManager when fire action is approved
func execute_fire_projectile() -> void:
	if is_in_action: return
	is_in_action = true
	animated_sprite.play("seeker_bang")
	print("Firing projectile!")

# Called by GameManager when SAK action is approved
func execute_sak_attack(target: PlayerCharacter) -> void:
	if is_in_action: return
	target_for_sak = target
	is_in_action = true
	animated_sprite.play("hider_sak")
	print("Performing SAK attack on ", target.player_name)

func handle_movement() -> void:
	if is_in_action:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# Allow movement regardless of can_move flag for testing
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_direction * current_speed
	move_and_slide()

func handle_visuals() -> void:
	var mouse_position = get_global_mouse_position()
	vision_cone.look_at(mouse_position)
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	if is_in_action: return
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

func update_all_players_in_cone() -> void:
	var overlapping_bodies: Array[Node2D] = vision_cone.get_overlapping_bodies()
	hiders_in_cone.clear()
	for body in overlapping_bodies:
		var player: PlayerCharacter = body as PlayerCharacter
		if player and player != self and player.current_state == PlayerState.ALIVE:
			hiders_in_cone.append(player)

func check_line_of_sight() -> void:
	# Only check line of sight occasionally to reduce RPC spam
	if Engine.get_physics_frames() % 10 != 0:
		return
		
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = collision_shape.shape
	shape_query.transform = global_transform
	shape_query.collision_mask = 2 
	var intersection_result: Array[Dictionary] = space_state.intersect_shape(shape_query)
	if not intersection_result.is_empty():
		for player in previously_visible_hiders:
			player.visible = false
		previously_visible_hiders.clear()
		visible_targets.clear()
		return
		
	var currently_visible_players: Array[PlayerCharacter] = []
	for player in hiders_in_cone:
		var ray_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, player.global_position, 2)
		var result: Dictionary = space_state.intersect_ray(ray_query)
		if result.is_empty():
			currently_visible_players.append(player)
		# Removed excessive RPC calls to GameManager
	
	# Update local visibility for immediate feedback
	for player in previously_visible_hiders:
		if not player in currently_visible_players:
			player.visible = false
	for player in currently_visible_players:
		player.visible = true
	
	previously_visible_hiders = currently_visible_players
	if role == PlayerRole.SEEKER:
		visible_targets = currently_visible_players

# --- SIGNAL FUNCTIONS ---

func _on_game_state_changed(new_state: int) -> void:
	var game_manager: GameManager = get_node_or_null("/root/GameManager") as GameManager
	if not game_manager:
		return
		
	match new_state:
		game_manager.GameState.HIDER_HEADSTART:
			if role == PlayerRole.HIDER: can_move = true
			elif role == PlayerRole.SEEKER: can_move = false
			can_attack = false
		game_manager.GameState.GAME_START_COUNTDOWN:
			can_move = false
			can_attack = false
		game_manager.GameState.IN_PROGRESS:
			can_move = true
			if role == PlayerRole.SEEKER:
				can_attack = true
		_:
			can_move = false
			can_attack = false

func _on_animated_sprite_2d_animation_finished() -> void:
	if animated_sprite.animation == "death":
		become_ghost()
	else:
		is_in_action = false
		target_for_sak = null 

func _on_animated_sprite_2d_frame_changed() -> void:
	if animated_sprite.animation == "seeker_bang":
		if animated_sprite.frame == 2:
			# Let GameManager handle projectile creation
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm:
				gm.create_projectile.rpc_id(1, multiplayer.get_unique_id(), muzzle.global_position, vision_cone.global_rotation)
	if animated_sprite.animation == "hider_sak":
		if animated_sprite.frame == 2:
			if is_instance_valid(target_for_sak):
				# Let GameManager handle the elimination
				var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
				if gm:
					gm.execute_elimination.rpc_id(1, target_for_sak.get_multiplayer_authority(), multiplayer.get_unique_id())
				target_for_sak = null
