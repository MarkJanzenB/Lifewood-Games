# res://scripts/dev/dev_player.gd
# Simplified player script for dev testing - based on YouTube tutorial approach
extends CharacterBody2D

# Basic player properties
@export var speed: float = 200.0
@export var player_name: String = "Player"
@export var player_color: Color = Color.WHITE

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var camera: Camera2D = $Camera2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var vision_cone: Area2D = $VisionCone
@onready var melee_range: Area2D = $MeleeRange
@onready var muzzle: Marker2D = $Muzzle

# Multiplayer variables
var is_main_player: bool = false
var _sync_position: Vector2 = Vector2.ZERO
var _sync_rotation: float = 0.0

# Attack variables
var can_attack: bool = true
var attack_cooldown: float = 0.5

func _ready():
	print("[DevPlayer] _ready() called - ID: ", multiplayer.get_unique_id())
	
	# Wait a frame for proper initialization
	await get_tree().process_frame
	
	# Configure multiplayer authority
	_configure_multiplayer_authority()
	
	# Setup replication config
	_setup_replication_config()
	
	# Set default animation
	if animated_sprite:
		animated_sprite.play("idle")
		print("[DevPlayer] Animation set to idle")
	else:
		print("[DevPlayer] WARNING: AnimatedSprite2D not found!")
	
	print("[DevPlayer] Ready complete - Authority: ", is_multiplayer_authority())

func _configure_multiplayer_authority():
	# Only the authority processes input and physics for this player
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		if camera:
			camera.enabled = false
	else:
		# This is the local player
		is_main_player = true
		if camera:
			camera.enabled = true
			camera.make_current()
		print("[DevPlayer] Local player configured")

func _setup_replication_config():
	# Create and configure replication config for multiplayer synchronization
	if not sync:
		return
		
	var config = SceneReplicationConfig.new()
	
	# Add properties that need to be synchronized across clients
	config.add_property(".:position")
	config.add_property(".:rotation")
	config.add_property(".:player_name")
	config.add_property(".:player_color")
	config.add_property(".:is_main_player")
	
	# Set the config
	sync.replication_config = config
	print("[DevPlayer] Replication config set up for: ", player_name)

func _physics_process(delta):
	if not is_multiplayer_authority():
		# Non-authority players just interpolate to synced position
		if _sync_position != Vector2.ZERO:
			global_position = global_position.lerp(_sync_position, delta * 10.0)
		return
	
	# Handle mouse following (face cursor) - rotate sprite only, not the whole player
	if camera and is_main_player and animated_sprite:
		var mouse_pos = get_global_mouse_position()
		var direction_to_mouse = (mouse_pos - global_position).normalized()
		
		# Flip sprite based on mouse direction instead of rotating
		if direction_to_mouse.x < 0:
			animated_sprite.flip_h = true
		else:
			animated_sprite.flip_h = false
		
		# Store the direction for syncing (but don't rotate the whole player)
		var mouse_angle = direction_to_mouse.angle()
		# Only sync when there's actual movement or mouse change
		if velocity.length() > 0:
			_sync_player_data.rpc(global_position, velocity, mouse_angle)
	
	# Handle input for authority player
	var input_vector = Vector2.ZERO
	
	if Input.is_action_pressed("mv_up"):
		input_vector.y -= 1
	if Input.is_action_pressed("mv_down"):
		input_vector.y += 1
	if Input.is_action_pressed("mv_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("mv_right"):
		input_vector.x += 1
	
	# Handle attack input
	if Input.is_action_just_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if can_attack:
			_perform_attack()
	
	# Normalize diagonal movement
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
		velocity = input_vector * speed
		
		# Update animation based on movement
		_update_animation(input_vector)
		
		# Sync position to other clients (mouse direction already synced above)
		_sync_player_data.rpc(global_position, velocity, 0.0)
	else:
		velocity = Vector2.ZERO
		if animated_sprite and can_attack:  # Don't override attack animation
			animated_sprite.play("idle")
	
	# Apply movement
	move_and_slide()

func _update_animation(direction: Vector2):
	if not animated_sprite:
		return
	
	# Simple animation logic based on direction
	if direction.y < 0:  # Moving up
		animated_sprite.play("back_walk")
	elif direction.y > 0:  # Moving down
		animated_sprite.play("front_walk")
	else:  # Moving horizontally
		animated_sprite.play("front_walk")
	
	# Flip sprite for left/right movement
	if direction.x < 0:
		animated_sprite.flip_h = true
	elif direction.x > 0:
		animated_sprite.flip_h = false

@rpc("any_peer", "unreliable")
func _sync_player_data(pos: Vector2, vel: Vector2, mouse_angle: float):
	if not is_multiplayer_authority():
		_sync_position = pos
		velocity = vel
		
		# Apply sprite flipping based on mouse direction
		if animated_sprite:
			var direction = Vector2.from_angle(mouse_angle)
			if direction.x < 0:
				animated_sprite.flip_h = true
			else:
				animated_sprite.flip_h = false

func _perform_attack():
	if not can_attack:
		return
	
	can_attack = false
	print("[DevPlayer] ", player_name, " attacks!")
	
	# Play attack animation
	if animated_sprite:
		animated_sprite.play("hider_sak")  # Using SAK attack animation
	
	# Sync attack to other clients
	_sync_attack.rpc()
	
	# Start cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

@rpc("any_peer", "call_local", "reliable")
func _sync_attack():
	print("[DevPlayer] ", player_name, " performed attack!")
	# Visual feedback for attack (could add particles, sound, etc.)
	if animated_sprite and not is_multiplayer_authority():
		animated_sprite.play("hider_sak")

# Called by the spawning system to set up player data
func setup_player(player_data: Dictionary, is_local: bool):
	player_name = player_data.get("name", "Player")
	is_main_player = is_local
	
	# Set name label
	if name_label:
		name_label.text = player_name
	
	# Assign a color based on player ID
	var player_id = multiplayer.get_unique_id()
	player_color = _get_player_color(player_id)
	
	# Apply color tint to sprite
	if animated_sprite:
		animated_sprite.modulate = player_color
	
	print("[DevPlayer] Setup complete - Name: ", player_name, " Local: ", is_local, " Color: ", player_color)

func _get_player_color(player_id: int) -> Color:
	# Generate consistent colors for different players
	var colors = [
		Color.CYAN,
		Color.YELLOW,
		Color.MAGENTA,
		Color.GREEN,
		Color.ORANGE
	]
	
	var index = (player_id - 1) % colors.size()
	return colors[index]

# Animation signal handlers (if needed)
func _on_animated_sprite_2d_animation_finished():
	pass

func _on_animated_sprite_2d_frame_changed():
	pass
