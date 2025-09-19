# res://scenes/RockProjectile.tscn
# res://scripts/rock_projectile.gd 

extends Area2D

const SPEED: int = 700

# --- THE NEW VARIABLE ---
# This will store a reference to the player who fired the rock.
var owner_player: PlayerCharacter

func _ready() -> void:
	print("[RockProjectile] Rock created at position: ", global_position)
	# Ensure visibility
	if has_node("Sprite2D"):
		var sprite = get_node("Sprite2D")
		sprite.visible = true
		sprite.modulate = Color.WHITE
		print("[RockProjectile] Sprite visibility: ", sprite.visible, " modulate: ", sprite.modulate)

func _physics_process(delta: float) -> void:
	position += transform.x * SPEED * delta
	# Debug position occasionally
	if randf() < 0.1:
		print("[RockProjectile] Moving - Position: ", global_position, " Speed: ", SPEED)

func _on_body_entered(body: Node2D) -> void:
	var was_hit_processed = false

	if body.is_in_group("hider"):
		var hider = body as PlayerCharacter
		if hider and hider.current_state == PlayerCharacter.PlayerState.ALIVE:
			print("Rock hit a living hider!")
			# --- THE FIX IS HERE ---
			# We now pass our "owner_player" as the attacker.
			hider.eliminate(owner_player)
			was_hit_processed = true

	if body.is_in_group("walls"):
		was_hit_processed = true
		
	if was_hit_processed:
		queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
