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
var can_move: bool = true  # Allow movement by default
var can_attack: bool = true  # Allow attacks by default

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
	
	# Configure based on whether this is the local player
	if is_local:
		if camera:
			camera.enabled = true
			camera.make_current()
		print("[Player] Set up LOCAL player: ", player_name)
	else:
		if camera:
			camera.enabled = false
		# Keep physics processing enabled for remote players so they can move
		# Only disable unhandled input for remote players
		set_process_unhandled_input(false)
		print("[Player] Set up REMOTE player: ", player_name)

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
		update_all_players_in_cone()
		check_line_of_sight()
		
		# Sync position to other clients more frequently for better responsiveness
		if Engine.get_physics_frames() % 2 == 0:  # Sync every 2nd frame
			_sync_player_position.rpc(global_position, velocity)
	else:
		# Non-authority players smoothly interpolate to synced position
		if _sync_position != Vector2.ZERO:
			global_position = global_position.lerp(_sync_position, delta * 15.0)  # Faster interpolation

@rpc("any_peer", "unreliable")
func _sync_player_position(pos: Vector2, vel: Vector2):
	# Only apply position updates to non-authority nodes
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
			# Send vision data to GameManager instead of handling directly
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm:
				gm.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), true)
			currently_visible_players.append(player)
		else:
			# Player is not visible
			var gm: GameManager = get_node_or_null("/root/GameManager") as GameManager
			if gm:
				gm.handle_player_vision.rpc_id(1, multiplayer.get_unique_id(), player.get_multiplayer_authority(), false)
	
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
