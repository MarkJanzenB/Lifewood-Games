# player.gd (Stable Version - Dash Mechanic Removed)

extends CharacterBody2D

# --- Variables ---
@export var walk_speed: float = 200.0
@export var run_speed: float = 350.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var vision_cone: Area2D = $VisionCone

# --- Game Loop ---
func _physics_process(delta: float) -> void:
	# Handle normal walking and running movement
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_direction * current_speed
	move_and_slide()
	
	# Handle all visual updates like animations and aiming
	handle_visuals()

# --- Helper Functions ---

func handle_visuals() -> void:
	var mouse_position = get_global_mouse_position()

	# --- 1. Horizontal Aiming (Flipping) ---
	animated_sprite.flip_h = (mouse_position.x < global_position.x)
	
	# --- 2. Rotate Vision Cone ---
	vision_cone.look_at(mouse_position)
	
	# --- 3. Animation Logic ---
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
