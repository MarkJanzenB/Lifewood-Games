# player.gd (Corrected: Animation is based on Aiming Direction)

extends CharacterBody2D

# --- Variables ---
@export var walk_speed: float = 200.0
@export var run_speed: float = 350.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


# --- Game Loop ---
func _physics_process(delta: float) -> void:
	handle_movement()
	handle_animation()


# --- Helper Functions ---

func handle_movement() -> void:
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed = run_speed if Input.is_action_pressed("run") else walk_speed
	
	velocity = input_direction * current_speed
	move_and_slide()


func handle_animation() -> void:
	var mouse_position = get_global_mouse_position()

	# --- 1. Horizontal Aiming (Flipping) ---
	# This part remains the same. The character always flips to face the cursor's L/R position.
	animated_sprite.flip_h = (mouse_position.x < global_position.x)

	# --- 2. Action Animations ---
	if Input.is_action_just_pressed("jump"):
		animated_sprite.play("jump") # Make sure you have a "jump" animation
		return

	# --- 3. CORE LOGIC: Aiming-Based Directional Animation ---
	var is_moving = velocity.length() > 0
	var is_running = Input.is_action_pressed("run")
	
	# Determine if the player is aiming "up" (cursor is above the character)
	var is_aiming_up = (mouse_position.y < global_position.y)
	
	var anim_to_play = ""

	if not is_moving:
		# --- IDLE STATE ---
		# Use back_idle if aiming up, otherwise use the normal (front) idle.
		if is_aiming_up:
			anim_to_play = "back_idle"
		else:
			anim_to_play = "idle"
	else:
		# --- MOVING STATE ---
		# Choose walk/run animations based on where the player is aiming.
		if is_aiming_up:
			anim_to_play = "back_run" if is_running else "back_walk"
		else:
			anim_to_play = "front_run" if is_running else "front_walk"
			
	animated_sprite.play(anim_to_play)
