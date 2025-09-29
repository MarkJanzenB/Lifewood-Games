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
	print("[RockProjectile] 💥 Collision detected with: ", body.name, " (", body.get_class(), ") Groups: ", body.get_groups())
	var was_hit_processed = false

	# Hit detection for living players
	if body.is_in_group("player"):
		var target_player = body as PlayerCharacter
		if target_player and target_player.current_state == PlayerCharacter.PlayerState.ALIVE:
			# Don't hit yourself
			if target_player != owner_player:
				print("[RockProjectile] 🎯 Rock hit player: ", target_player.player_name)
				print("[RockProjectile] ✅ HIT CONFIRMED - ", owner_player.player_name if owner_player else "Unknown", " hit ", target_player.player_name)
				
				# Only eliminate on server to avoid duplicate eliminations
				if multiplayer.is_server():
					target_player.eliminate(owner_player)
					print("[RockProjectile] 💀 SERVER: ", target_player.player_name, " eliminated by ", owner_player.player_name if owner_player else "Unknown")
				
				was_hit_processed = true
			else:
				print("[RockProjectile] ⚠️ Ignoring self-hit for ", target_player.player_name)
		else:
			print("[RockProjectile] ⚠️ Target player invalid or not alive")

	# Hit detection for walls and obstacles
	elif body.is_in_group("walls") or body is StaticBody2D or body is RigidBody2D or body is CharacterBody2D:
		print("[RockProjectile] 🧱 Rock hit obstacle: ", body.name, " (", body.get_class(), ")")
		was_hit_processed = true
	
	# Destroy projectile on any collision
	if was_hit_processed:
		print("[RockProjectile] 🗑️ Destroying projectile after collision")
		queue_free()
	else:
		print("[RockProjectile] ⚠️ Collision ignored - no valid target")

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
