# player.gd (Definitive Version - Ghost and Hider LOS Update)
# This script contains a full state machine for Alive/Ghost states.

class_name Player
extends CharacterBody2D

# --- ENUM DEFINITIONS ---
enum PlayerRole { HIDER, SEEKER }
enum PlayerState { ALIVE, GHOST }

# --- CONSTANTS ---
const ROCK_PROJECTILE_SCENE = preload("res://scenes/RockProjectile.tscn") # Make sure the path is correct!

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
@onready var camera: Camera2D = $Camera2D # We need a reference to the camera

# --- STATE VARIABLES ---
var hiders_in_cone: Array = []
var visible_targets: Array = []
var previously_visible_hiders: Array = []
var is_in_action: bool = false
var target_for_sak: Node2D = null
var current_state: PlayerState = PlayerState.ALIVE # The new state variable

# --- CORE FUNCTIONS ---

func _ready() -> void:
	if not is_main_player:
		set_physics_process(false)
		set_process_unhandled_input(false)
		vision_light.visible = false
		vision_cone.monitoring = false
		melee_range.monitoring = false

	if role == PlayerRole.HIDER:
		vision_light.energy = 0.5
		
func set_ammo(new_ammo_count: int) -> void:
	ammo = new_ammo_count

func eliminate():
	if current_state == PlayerState.GHOST: return # Can't eliminate a ghost
	become_ghost()

func become_ghost():
	print(player_name, " has become a ghost!")
	current_state = PlayerState.GHOST
	GameManager.on_player_eliminated()
	
	animated_sprite.modulate = Color(0.5, 0.7, 1, 0.5) # Bluish and semi-transparent
	vision_light.color = Color.CYAN
	
	set_collision_layer_value(1, false) # No longer on "living_players"
	set_collision_layer_value(3, true)  # Now on "ghosts"
	set_collision_mask_value(1, false) # Can't hit living players
	set_collision_mask_value(2, false) # Can pass through walls
	set_collision_mask_value(3, true)  # Can bump into other ghosts
	
	animated_sprite.set_visibility_layer_bit(1, false) # No longer on "living_world"
	animated_sprite.set_visibility_layer_bit(2, true)  # Now on "ghost_world"
	
	if is_main_player:
		camera.set_cull_mask_bit(2, true)  # Now also sees "ghost_world"
	
	vision_cone.monitoring = false
	melee_range.monitoring = false

func _physics_process(delta: float) -> void:
	if not is_main_player: return
	
	if current_state == PlayerState.GHOST:
		handle_movement() # Ghosts can only move.
		return
		
	# Alive players run all logic.
	handle_movement()
	handle_visuals()
	update_all_players_in_cone() # Updated function name
	check_line_of_sight()

func _input(event: InputEvent) -> void:
	if current_state == PlayerState.GHOST: return
	if not is_main_player: return
	if Input.is_action_just_pressed("fire"):
		if role == PlayerRole.SEEKER and ammo > 0 and not visible_targets.is_empty():
			fire_projectile()
		if role == PlayerRole.HIDER:
			perform_sak_attack()

# --- HELPER FUNCTIONS ---

func fire_projectile():
	if is_in_action: return
	is_in_action = true
	animated_sprite.play("seeker_bang")
	ammo -= 1
	print("Fired! Ammo remaining: ", ammo)

func perform_sak_attack():
	if is_in_action: return
	var nearby_players = melee_range.get_overlapping_bodies()
	for target in nearby_players:
		if target != self and (target as Player).current_state == PlayerState.ALIVE:
			target_for_sak = target 
			is_in_action = true
			animated_sprite.play("hider_sak")
			return

func handle_movement() -> void:
	if is_in_action:
		velocity = Vector2.ZERO
		move_and_slide()
		return
		
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_direction * current_speed
	move_and_slide()

# (This is the updated handle_visuals function in player.gd)

func handle_visuals() -> void:
	var mouse_position = get_global_mouse_position()
	vision_cone.look_at(mouse_position)
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	
	if is_in_action:
		return
		
	if velocity.length() > 0:
		var is_running = Input.is_action_pressed("run")
		var is_aiming_up = (mouse_position.y < global_position.y)
		
		var anim_to_play = ""
		# --- THE NEW LOGIC IS HERE ---
		# Determine the base animation name based on aiming direction.
		var base_anim = "front_backward_" if is_aiming_up else "front_"
		# Determine the movement type.
		var move_type = "run" if is_running else "walk"
		# Combine them to get the final animation name.
		anim_to_play = base_anim + move_type
		animated_sprite.play(anim_to_play)
	else:
		# Idle logic also needs to check the aiming direction.
		if mouse_position.y < global_position.y:
			animated_sprite.play("back_idle") # Assuming you have or will create a "back_idle"
		else:
			animated_sprite.play("idle")

func update_all_players_in_cone() -> void:
	# This function now gets ALL players, not just hiders.
	var overlapping_bodies = vision_cone.get_overlapping_bodies()
	hiders_in_cone.clear() # We can rename this variable for clarity later if needed
	for body in overlapping_bodies:
		if body is Player and body != self and body.current_state == PlayerState.ALIVE:
			hiders_in_cone.append(body)

func check_line_of_sight() -> void:
	var currently_visible_players: Array = []
	var space_state = get_world_2d().direct_space_state

	for player in hiders_in_cone:
		var query = PhysicsRayQueryParameters2D.create(global_position, player.global_position, 2)
		var result = space_state.intersect_ray(query)
		if result.is_empty():
			player.visible = true
			currently_visible_players.append(player)
		else:
			player.visible = false
	
	for player in previously_visible_hiders:
		if not player in currently_visible_players:
			player.visible = false
			
	previously_visible_hiders = currently_visible_players
	
	if role == PlayerRole.SEEKER:
		visible_targets = currently_visible_players

# --- SIGNAL FUNCTIONS ---

func _on_animated_sprite_2d_animation_finished() -> void:
	if animated_sprite.animation == "death":
		# The player object now persists as a ghost. We don't call queue_free().
		pass
	else:
		is_in_action = false
		target_for_sak = null 

func _on_animated_sprite_2d_frame_changed() -> void:
	if animated_sprite.animation == "seeker_bang":
		if animated_sprite.frame == 2:
			var rock = ROCK_PROJECTILE_SCENE.instantiate()
			rock.global_position = muzzle.global_position
			rock.rotation = vision_cone.global_rotation
			get_tree().get_root().add_child(rock)
			
	if animated_sprite.animation == "hider_sak":
		if animated_sprite.frame == 3:
			if is_instance_valid(target_for_sak):
				print(player_name, " successfully SAK'D ", target_for_sak.player_name)
				target_for_sak.eliminate()
				target_for_sak = null
