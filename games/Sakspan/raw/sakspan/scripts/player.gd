# player.gd (Final, Reorganized Version)

class_name Player
extends CharacterBody2D

# --- ENUM DEFINITION (MOVED TO THE TOP) ---
# Enums must be declared before they are used in variables.
enum PlayerRole { HIDER, SEEKER }
const ROCK_PROJECTILE_SCENE = preload("res://scenes/RockProjectile.tscn") # Make sure the path is correct!

# --- EXPORTED VARIABLES ---
@export var walk_speed: float = 200.0
@export var run_speed: float = 350.0
@export var is_main_player: bool = false
# This now correctly uses the enum we defined above.
@export var role: PlayerRole = PlayerRole.HIDER
@export var player_name: String = "Player"
@export var ammo: int = 0
# --- NODE REFERENCES ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var vision_cone: Area2D = $VisionCone
@onready var vision_light: PointLight2D = $VisionCone/PointLight2D
@onready var melee_range: Area2D = $MeleeRange

# --- STATE VARIABLES ---
var hiders_in_cone: Array = []
var previously_visible_hiders: Array = []
var visible_targets: Array = []



func _ready() -> void:
	if not is_main_player:
		set_physics_process(false)
		set_process_unhandled_input(false)
		vision_light.visible = false
		vision_cone.monitoring = false
		melee_range.monitoring = false

	if role == PlayerRole.SEEKER:
		melee_range.monitoring = false
	elif role == PlayerRole.HIDER:
		vision_light.energy = 0.5


# (This is the updated eliminate function in player.gd)
func eliminate():
	print(player_name, " has been eliminated!")
	# Tell the GameManager that an elimination has occurred.
	GameManager.on_player_eliminated()
	queue_free()
func _physics_process(delta: float) -> void:
	if not is_main_player:
		return

	handle_movement()
	handle_visuals()
	update_hiders_in_cone()
	check_line_of_sight()
func set_ammo(new_ammo_count: int) -> void:
	ammo = new_ammo_count
# --- HELPER FUNCTIONS ---

func handle_movement() -> void:
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_direction * current_speed
	move_and_slide()

func handle_visuals() -> void:
	var mouse_position = get_global_mouse_position()
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	vision_cone.look_at(mouse_position)
	
	var is_moving = velocity.length() > 0
	var is_running = Input.is_action_pressed("run")
	var is_aiming_up = (mouse_position.y < global_position.y)
	
	var anim_to_play = ""
	if not is_moving:
		anim_to_play = "back_idle" if is_aiming_up else "idle"
	else:
		if is_aiming_up:
			anim_to_play = "back_run" if is_running else "back_walk"
		else:
			anim_to_play = "front_run" if is_running else "front_walk"
			
	animated_sprite.play(anim_to_play)

func update_hiders_in_cone() -> void:
	var overlapping_bodies = vision_cone.get_overlapping_bodies()
	hiders_in_cone.clear()

	for body in overlapping_bodies:
		if body.is_in_group("hider") and body != self:
			hiders_in_cone.append(body)

func check_line_of_sight() -> void:
	var currently_visible_hiders: Array = []
	var space_state = get_world_2d().direct_space_state

	for hider in hiders_in_cone:
		var query = PhysicsRayQueryParameters2D.create(global_position, hider.global_position, 2)
		var result = space_state.intersect_ray(query)
		
		if result.is_empty():
			hider.visible = true
			currently_visible_hiders.append(hider)
		else:
			hider.visible = false

	for hider in previously_visible_hiders:
		if not hider in currently_visible_hiders:
			hider.visible = false
			
	previously_visible_hiders = currently_visible_hiders
	visible_targets = currently_visible_hiders

# --- INPUT HANDLING ---
# --- INPUT HANDLING (FINAL, BULLETPROOF VERSION) ---

# --- INPUT HANDLING (FINAL, BULLETPROOF VERSION 2.0) ---

func _input(event: InputEvent) -> void:
	if not is_main_player: return
	if not (event.is_action_pressed("ui_accept") and event is InputEventMouseButton): return

	if role == PlayerRole.SEEKER:
		if ammo <= 0: return

		var space_state = get_world_2d().direct_space_state
		var mouse_position_in_world = get_global_mouse_position()

		var query = PhysicsPointQueryParameters2D.new()
		query.position = mouse_position_in_world
		query.collision_mask = 1
		query.exclude = [self]
		# This is the fix: It stops the click from hitting the VisionCone or MeleeRange.
		query.collide_with_areas = false
		
		var results = space_state.intersect_point(query)

		if not results.is_empty():
			var clicked_node = results[0].collider
			
			if visible_targets.has(clicked_node):
				print("SUCCESSFUL HIT ON: ", clicked_node.player_name)
				
				animated_sprite.play("seeker_bang")
				
				var rock = ROCK_PROJECTILE_SCENE.instantiate()
				rock.direction = (mouse_position_in_world - global_position).normalized()
				rock.global_position = global_position
				rock.rotation = rock.direction.angle()
				
				get_tree().get_root().add_child(rock)
				
				ammo -= 1
				print("Fired! Ammo remaining: ", ammo)
				return

	if role == PlayerRole.HIDER:
		# (The Hider's logic does not need to change)
		var nearby_players = melee_range.get_overlapping_bodies()
		for target in nearby_players:
			if target == self: continue

			var target_shape = target.get_node("CollisionShape2D")
			if target_shape and target_shape.shape.get_rect().has_point(target.to_local(event.position)):
				animated_sprite.play("hider_sak")
				print(player_name, " successfully SAK'D ", target.player_name)
				target.eliminate()
				return
