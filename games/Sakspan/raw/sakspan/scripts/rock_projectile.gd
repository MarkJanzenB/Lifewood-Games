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
	print("[RockProjectile] 💥 Collision detected with: ", body.name, " (", body.get_class(), ")")
	var was_hit_processed = false

	# Hit detection for living players
	if body.is_in_group("player"):
		var target_player = body as PlayerCharacter
		if target_player and target_player.current_state == PlayerCharacter.PlayerState.ALIVE:
			# Don't hit yourself
			if target_player != owner_player:
				print("[RockProjectile] 🎯 Rock hit player: ", target_player.player_name)
				print("[RockProjectile] ✅ HIT CONFIRMED - ", owner_player.player_name, " hit ", target_player.player_name)
				
				# Eliminate the target player
				target_player.eliminate(owner_player)
				print("[RockProjectile] 💀 ", target_player.player_name, " eliminated by ", owner_player.player_name)
				
				was_hit_processed = true

	# Hit detection for walls and obstacles (StaticBody2D, RigidBody2D, etc.)
	if body.is_in_group("walls") or body is StaticBody2D or body is RigidBody2D:
		print("[RockProjectile] 🧱 Rock hit obstacle: ", body.name)
		was_hit_processed = true
	
	# Destroy projectile on any collision
	if was_hit_processed:
		print("[RockProjectile] 🗑️ Destroying projectile")
		queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
