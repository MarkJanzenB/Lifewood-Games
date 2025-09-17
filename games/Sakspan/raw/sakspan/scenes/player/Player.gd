extends CharacterBody2D

@onready var name_label = $NameLabel


@export var speed = 300

func _physics_process(delta):
	# Only allow the local player to control their character.
	if not is_multiplayer_authority():
		return

	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed
	move_and_slide()

func set_player_name(player_name):
	name_label.text = player_name


