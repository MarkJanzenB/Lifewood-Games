# res://scripts/player.gd

class_name PlayerCharacter
extends CharacterBody2D

enum PlayerRole { HIDER, SEEKER }
enum PlayerState { ALIVE, GHOST }

const ROCK_PROJECTILE_SCENE = preload("res://scenes/RockProjectile.tscn")

@export var player_name: String = "Player"
@export var is_main_player: bool = false 

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var vision_cone: Area2D = $VisionCone
@onready var vision_light: PointLight2D = $VisionCone/PointLight2D
@onready var melee_range: Area2D = $MeleeRange
@onready var muzzle: Marker2D = $Muzzle
@onready var camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

var role: PlayerRole
var _sync_position: Vector2
var current_state: PlayerState = PlayerState.ALIVE
var ammo: int = 0
var hiders_in_cone: Array = []
var visible_targets: Array = []
var previously_visible_hiders: Array = []
var is_in_action: bool = false
var target_for_sak: Node2D = null
var is_dying: bool = false
var can_move: bool = false
var can_attack: bool = false
var walk_speed: float = 200.0
var run_speed: float = 350.0

# Collision layers:
# 1 - Default (players, obstacles)
# 2 - Vision (for line of sight checks)
# 3 - Ghosts (visible to all players)
# 4 - Obstacles

func _ready():
	await get_tree().process_frame
	GameManager.game_state_changed.connect(_on_game_state_changed)
	
	# Only the authority processes input and physics for this player
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		camera.enabled = false
		vision_light.visible = false
		vision_cone.monitoring = false
		melee_range.monitoring = false
	
	# Setup MultiplayerSynchronizer
	sync.replication_config = null  # Will be set in editor
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	sync.visibility_public = true

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

func _physics_process(delta: float):
	if is_dying: return
	# Only the multiplayer authority simulates input and movement
	if not is_multiplayer_authority():
		return
	if not is_main_player:
		return
		
	handle_movement()
	if current_state == PlayerState.GHOST: return
	handle_visuals()
	update_all_players_in_cone()
	check_line_of_sight()
	
	# Update sync position for replication
	if is_multiplayer_authority():
		_sync_position = global_position

func _input(event: InputEvent) -> void:
	if is_dying or current_state == PlayerState.GHOST: return
	# Only the authority handles inputs
	if not is_multiplayer_authority(): return
	if not is_main_player: return
	if Input.is_action_just_pressed("fire"):
		if not can_attack: return
		if role == PlayerRole.SEEKER and ammo > 0:
			fire_projectile()
		if role == PlayerRole.HIDER:
			perform_sak_attack()

func set_ammo(new_ammo_count: int) -> void: ammo = new_ammo_count

func eliminate(attacker: PlayerCharacter):
	if is_dying or current_state == PlayerState.GHOST: return
	is_dying = true
	GameManager.player_eliminated.emit(self, attacker)
	animated_sprite.play("death")
	collision_shape.disabled = true
	melee_range.monitoring = false
	vision_cone.monitoring = false

func become_ghost():
	print(player_name, " has become a ghost!")
	current_state = PlayerState.GHOST
	GameManager.check_win_conditions()
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

func fire_projectile():
	if is_in_action: return
	is_in_action = true
	animated_sprite.play("seeker_bang")
	ammo -= 1
	print("Fired! Ammo remaining: ", ammo)
	if ammo == 0:
		GameManager.start_ammo_cooldown()

func perform_sak_attack():
	if is_in_action: return
	var nearby_players = melee_range.get_overlapping_bodies()
	for target in nearby_players:
		if target != self and (target as PlayerCharacter).current_state == PlayerState.ALIVE:
			target_for_sak = target 
			is_in_action = true
			animated_sprite.play("hider_sak")
			return

func handle_movement() -> void:
	if not can_move or is_in_action:
		velocity = Vector2.ZERO
		move_and_slide()
		return
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
	var overlapping_bodies = vision_cone.get_overlapping_bodies()
	hiders_in_cone.clear()
	for body in overlapping_bodies:
		if body is PlayerCharacter and body != self and body.current_state == PlayerState.ALIVE:
			hiders_in_cone.append(body)

func check_line_of_sight() -> void:
	var space_state = get_world_2d().direct_space_state
	var shape_query = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = collision_shape.shape
	shape_query.transform = global_transform
	shape_query.collision_mask = 2 
	var intersection_result = space_state.intersect_shape(shape_query)
	if not intersection_result.is_empty():
		for player in previously_visible_hiders:
			player.visible = false
		previously_visible_hiders.clear()
		visible_targets.clear()
		return
		
	var currently_visible_players: Array = []
	for player in hiders_in_cone:
		var ray_query = PhysicsRayQueryParameters2D.create(global_position, player.global_position, 2)
		var result = space_state.intersect_ray(ray_query)
		if result.is_empty():
			player.visible = true
			currently_visible_players.append(player)
			if player.is_main_player and player.role == PlayerRole.HIDER:
				var game_manager = get_node_or_null("/root/GameManager")
				if game_manager and is_instance_valid(game_manager.game_ui_instance):
					game_manager.game_ui_instance.show_spotted(true)
		else:
			player.visible = false
	for player in previously_visible_hiders:
		if not player in currently_visible_players:
			player.visible = false
			if player.is_main_player and player.role == PlayerRole.HIDER:
				var game_manager = get_node_or_null("/root/GameManager")
				if game_manager and is_instance_valid(game_manager.game_ui_instance):
					game_manager.game_ui_instance.show_spotted(false)
	previously_visible_hiders = currently_visible_players
	if role == PlayerRole.SEEKER:
		visible_targets = currently_visible_players

func _on_game_state_changed(new_state: int) -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return
		
	match new_state:
		game_manager.GameState.HIDER_HEADSTART:
			if role == PlayerRole.HIDER:
				can_move = true
			elif role == PlayerRole.SEEKER:
				can_move = false  # Explicitly freeze seekers during head start
			can_attack = false  # No one can attack during head start
		game_manager.GameState.GAME_START_COUNTDOWN:
			can_move = false
			can_attack = false
		game_manager.GameState.IN_PROGRESS:
			can_move = true
			can_attack = (role == PlayerRole.SEEKER)  # Only seekers can attack
		game_manager.GameState.GAME_OVER:
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
			var rock = ROCK_PROJECTILE_SCENE.instantiate()
			rock.owner_player = self
			rock.global_position = muzzle.global_position
			rock.rotation = vision_cone.global_rotation
			get_tree().get_root().add_child(rock)
	if animated_sprite.animation == "hider_sak":
		if animated_sprite.frame == 2:
			if is_instance_valid(target_for_sak):
				print(player_name, " successfully SAK'D ", target_for_sak.player_name)
				target_for_sak.eliminate(self)
				target_for_sak = null
