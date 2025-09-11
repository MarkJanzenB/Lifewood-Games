extends CharacterBody2D

@export var speed: float = 100.0
@onready var anim: AnimationPlayer = $AnimationPlayer

var current_dir: String = "none"

func _physics_process(delta: float) -> void:
	player_movement(delta)

func player_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO

	# Input checks
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
		current_dir = "right"
	elif Input.is_action_pressed("move_left"):
		input_dir.x -= 1
		current_dir = "left"

	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
		current_dir = "down"
	elif Input.is_action_pressed("move_up"):
		input_dir.y -= 1
		current_dir = "up"

	# Set velocity
	velocity = input_dir.normalized() * speed

	# Move the character
	move_and_slide()

	# Play animation
	if input_dir == Vector2.ZERO:
		play_anim("idle")
	else:
		play_anim(current_dir)

func play_anim(direction: String) -> void:
	match direction:
		"right":
			anim.play("walk_right")
		"left":
			anim.play("walk_left")
		"up":
			anim.play("walk_up")
		"down":
			anim.play("walk_down")
		"idle":
			anim.play("idle")
